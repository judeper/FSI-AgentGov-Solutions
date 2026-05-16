#Requires -Version 7.0
#Requires -Modules MSAL.PS, Az.KeyVault

<#
.SYNOPSIS
    Validates all prerequisites for the message-center-monitor Phase 1 PowerShell POC path
    before the first sync run.

.DESCRIPTION
    Runs 11 checks covering PowerShell version, module availability, Azure Key Vault
    reachability, Graph token acquisition, API permission consent, Dataverse connectivity,
    entity schema, alternate key activation status, Teams webhook health, and Phase 1 /
    Phase 3 notification-path mutual exclusion.

    Outputs a color-coded summary table. Exits 0 when all checks PASS or SKIP (zero WARN,
    zero FAIL), exits 0 with a caution message when there are WARNs but no FAILs, and
    exits 1 when any check FAILs.

    Each check is wrapped in its own try/catch so a failure on check N does not prevent
    checks N+1 through 11 from running.

    Supports FSI Agent Governance Framework Control 2.3 (Change Management and Release
    Planning). Authentication follows managed-identity-first policy; ClientSecret is a
    dev-only fallback.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Defaults to $env:AZURE_TENANT_ID.

.PARAMETER ClientId
    Application (client) ID of the Entra app registration.
    Defaults to $env:AZURE_CLIENT_ID.

.PARAMETER ClientSecret
    Client secret as a SecureString. Required only when -AuthMode ClientSecret.
    legacy: dev-only — replace with managed identity in production.

.PARAMETER AuthMode
    Authentication mode. Valid values: ManagedIdentity, WorkloadIdentity, Interactive,
    DeviceCode, ClientSecret. Defaults to ClientSecret for preflight convenience.
    Use ManagedIdentity in production Azure-hosted environments.

.PARAMETER DataverseUrl
    Dataverse organization URL, e.g. https://org.crm.dynamics.com. Required.
    Do not include /api/data/... in this value.

.PARAMETER TeamsWebhookUrl
    Incoming webhook URL for the Teams notification channel (Phase 1 path).
    Defaults to $env:MCM_TEAMS_WEBHOOK_URL. Check 10 is skipped when not supplied.

.PARAMETER Phase3EnvVarLogicalName
    Schema name of the Dataverse environment variable definition that signals Phase 3 flow
    deployment. Default: fsi_MCM_NotifySeverities. Override when the tenant uses a
    different naming convention.

.PARAMETER KeyVaultName
    Azure Key Vault name. When supplied, check 3 probes vault reachability and check 4
    retrieves the client secret. When omitted, both checks are skipped.

.PARAMETER KeyVaultSecretName
    Secret name within the Key Vault. Drives check 4; ignored when -KeyVaultName is absent.

.PARAMETER PostTestMessage
    When specified, check 10 POSTs a labeled preflight adaptive card to the Teams webhook
    in addition to URL and DNS validation. Default: dry-run (URL + DNS only).

.PARAMETER TeamsCardTemplatePath
    Path to the adaptive card template JSON used when -PostTestMessage is specified.
    Defaults to ../../templates/teams-notification-card.json relative to the script.

.EXAMPLE
    .\Test-McmPrerequisites.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AuthMode ManagedIdentity

    Minimal preflight using managed identity. Key Vault and Teams webhook checks are
    skipped (parameters not supplied). Recommended for Azure-hosted runners.

.EXAMPLE
    .\Test-McmPrerequisites.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
        -AuthMode ClientSecret `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -KeyVaultName "fsi-agentgov-kv" `
        -KeyVaultSecretName "MCM-ClientSecret"

    Dev workstation preflight with Key Vault secret retrieval. The retrieved secret is
    applied to -ClientSecret automatically so downstream Graph and Dataverse checks reuse it.

.EXAMPLE
    $secret = Read-Host -AsSecureString -Prompt "Client Secret"
    .\Test-McmPrerequisites.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
        -ClientSecret $secret `
        -AuthMode ClientSecret `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TeamsWebhookUrl "https://prod-12.westus.logic.azure.com/workflows/..." `
        -PostTestMessage

    Full preflight with all 11 checks including a Teams webhook test card POST.
    Supply -ClientSecret explicitly when not using Key Vault retrieval.

.NOTES
    Version: 2.5.1
    Solution: message-center-monitor
    Controls: 2.3 (Change Management and Release Planning)

    Requires:
    - PowerShell 7.2 or later
    - MSAL.PS module >= 4.37.0
    - Az.KeyVault module (when using -KeyVaultName)
    - Entra app registration with:
        ServiceMessage.Read.All (application permission, admin consent required)
        Dataverse Application User role in the target environment
    - fsi_messagecenterlog Dataverse table deployed via create_mcm_dataverse_schema.py

    Exit codes:
    - 0  All checks PASS or SKIP (zero FAIL, zero WARN)
    - 0  Zero FAIL, one or more WARN — prints caution message
    - 1  One or more FAIL
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)] [string]$TenantId = $env:AZURE_TENANT_ID,
    [Parameter(Mandatory=$false)] [string]$ClientId = $env:AZURE_CLIENT_ID,
    [Parameter(Mandatory=$false)] [SecureString]$ClientSecret,

    [Parameter(Mandatory=$false)]
    [ValidateSet('ManagedIdentity','WorkloadIdentity','Interactive','DeviceCode','ClientSecret')]
    [string]$AuthMode = 'ClientSecret',

    [Parameter(Mandatory=$true)]  [string]$DataverseUrl,

    [Parameter(Mandatory=$false)] [string]$TeamsWebhookUrl = $env:MCM_TEAMS_WEBHOOK_URL,

    [Parameter(Mandatory=$false)] [string]$Phase3EnvVarLogicalName = 'fsi_MCM_NotifySeverities',

    [Parameter(Mandatory=$false)] [string]$KeyVaultName,
    [Parameter(Mandatory=$false)] [string]$KeyVaultSecretName,

    [Parameter(Mandatory=$false)] [switch]$PostTestMessage,

    [Parameter(Mandatory=$false)] [switch]$AssumePhase1Only,

    [Parameter(Mandatory=$false)]
    [string]$TeamsCardTemplatePath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'templates\teams-notification-card.json')
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\_Common.ps1"

Set-StrictMode -Version Latest

#region Script-level state shared across checks

$script:graphToken = $null
$script:dvHeaders  = $null
$script:dvBaseUrl  = $null

#endregion

#region Local script helpers

function New-McmCheckResult {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [ValidateSet('PASS','WARN','FAIL','SKIP')] [string]$Status,
        [string]$Hint   = '',
        [object]$Detail = $null
    )
    return [pscustomobject]@{
        Check  = $Name
        Status = $Status
        Hint   = $Hint
        Detail = $Detail
    }
}

function Invoke-McmRenderTokens {
    <#
    .SYNOPSIS
        Recursively replaces {Token} placeholders in an adaptive card object tree.
    .DESCRIPTION
        Accepts a hashtable/array/scalar returned by ConvertFrom-Json -AsHashtable.
        For each string value:
          - Exact match '{TokenName}': replaced with the token value (may be non-string).
          - Partial match: all '{TokenName}' substrings replaced via regex scriptblock,
            preserving surrounding characters (e.g. Action.OpenUrl targets).
        Mutates the input hashtable in place and also returns it.
    #>
    param(
        [Parameter(Mandatory)] $Node,
        [Parameter(Mandatory)] [hashtable]$Tokens
    )
    if ($Node -is [string]) {
        if ($Node -match '^\{(\w+)\}$' -and $Tokens.ContainsKey($Matches[1])) {
            return $Tokens[$Matches[1]]
        }
        return [regex]::Replace($Node, '\{(\w+)\}', {
            param($m)
            $key = $m.Groups[1].Value
            if ($Tokens.ContainsKey($key)) { $Tokens[$key] } else { $m.Value }
        })
    }
    elseif ($Node -is [System.Collections.Hashtable]) {
        $keys = @($Node.Keys)
        foreach ($k in $keys) {
            $Node[$k] = Invoke-McmRenderTokens -Node $Node[$k] -Tokens $Tokens
        }
        return $Node
    }
    elseif ($Node -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $Node.Count; $i++) {
            $Node[$i] = Invoke-McmRenderTokens -Node $Node[$i] -Tokens $Tokens
        }
        return $Node
    }
    return $Node
}

#endregion

$results = [System.Collections.Generic.List[pscustomobject]]::new()

Write-Host ''
Write-Host '╔══════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  message-center-monitor — Preflight v2.5.1      ║' -ForegroundColor Cyan
Write-Host '╚══════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

#region Check 1 — PowerShell 7.2+

$checkName = 'PowerShell 7.2+'
try {
    $psVer = $PSVersionTable.PSVersion
    if ($psVer -ge [version]'7.2') {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'PASS' -Detail "v$psVer"))
    }
    else {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
            -Hint 'Install PowerShell 7.2 or later: winget install Microsoft.PowerShell' `
            -Detail "Installed: v$psVer"))
    }
}
catch {
    $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' -Hint $_.Exception.Message))
}

#endregion

#region Check 2 — MSAL.PS >= 4.37.0 and Az.KeyVault present

$checkName = 'Modules: MSAL.PS >= 4.37.0, Az.KeyVault'
try {
    $msalMod  = Get-Module -Name MSAL.PS    -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    $azkeyMod = Get-Module -Name Az.KeyVault -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

    $msalOk  = ($null -ne $msalMod)  -and ($msalMod.Version -ge [version]'4.37.0')
    $azkeyOk = $null -ne $azkeyMod

    if ($msalOk -and $azkeyOk) {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'PASS' `
            -Detail "MSAL.PS $($msalMod.Version); Az.KeyVault $($azkeyMod.Version)"))
    }
    else {
        $missing = [System.Collections.Generic.List[string]]::new()
        if (-not $msalOk)  { $missing.Add('MSAL.PS >= 4.37.0') }
        if (-not $azkeyOk) { $missing.Add('Az.KeyVault') }
        $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
            -Hint 'Install-Module MSAL.PS -MinimumVersion 4.37.0 -Scope CurrentUser -Force; Install-Module Az.KeyVault -Scope CurrentUser -Force' `
            -Detail "Missing: $($missing -join ', ')"))
    }
}
catch {
    $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' -Hint $_.Exception.Message))
}

#endregion

#region Check 3 — Key Vault reachable

$checkName = 'Key Vault reachable'
try {
    if (-not $KeyVaultName) {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'SKIP' `
            -Hint 'Supply -KeyVaultName to validate'))
    }
    else {
        Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction Stop | Out-Null
        $results.Add((New-McmCheckResult -Name $checkName -Status 'PASS' -Detail $KeyVaultName))
    }
}
catch {
    $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
        -Hint 'Run Connect-AzAccount with credentials that have Reader access to the Key Vault' `
        -Detail $_.Exception.Message))
}

#endregion

#region Check 4 — Client secret present in Key Vault

$checkName = 'Key Vault secret retrieval'
try {
    if (-not $KeyVaultName -or -not $KeyVaultSecretName) {
        $skipHint = if (-not $KeyVaultName) {
            'Supply -KeyVaultName to validate'
        }
        else {
            'Supply -KeyVaultSecretName to validate'
        }
        $results.Add((New-McmCheckResult -Name $checkName -Status 'SKIP' -Hint $skipHint))
    }
    else {
        $secretPlainText = Get-AzKeyVaultSecret -VaultName $KeyVaultName `
            -Name $KeyVaultSecretName -AsPlainText -ErrorAction Stop
        if ($secretPlainText) {
            $ClientSecret = ConvertTo-SecureString -String $secretPlainText -AsPlainText -Force
            $results.Add((New-McmCheckResult -Name $checkName -Status 'PASS' `
                -Detail "Secret '$KeyVaultSecretName' retrieved and applied to -ClientSecret"))
        }
        else {
            $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
                -Hint "Secret '$KeyVaultSecretName' exists but returned an empty value. Verify the secret has a current non-empty version." `
                -Detail "Vault: $KeyVaultName"))
        }
    }
}
catch {
    $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
        -Hint 'Run Connect-AzAccount with credentials that have Get access to Key Vault secrets' `
        -Detail $_.Exception.Message))
}

#endregion

#region Check 5 — Graph token acquisition

$checkName = 'Graph token acquisition'
try {
    $script:graphToken = Get-McmAccessToken -AuthMode $AuthMode `
        -Scope 'https://graph.microsoft.com/.default' `
        -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $results.Add((New-McmCheckResult -Name $checkName -Status 'PASS' `
        -Detail "Token acquired (expires: $($script:graphToken.ExpiresOn))"))
}
catch {
    $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
        -Hint 'Verify TenantId/ClientId/ClientSecret are correct and the app exists in the tenant' `
        -Detail $_.Exception.Message))
}

#endregion

#region Check 6 — ServiceMessage.Read.All consented

$checkName = 'ServiceMessage.Read.All consented'
try {
    if (-not $script:graphToken) {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'SKIP' `
            -Hint 'Graph token unavailable — check 5 (Graph token acquisition) must PASS first'))
    }
    else {
        $graphHeaders = @{
            Authorization  = "Bearer $($script:graphToken.AccessToken)"
            'Content-Type' = 'application/json'
        }
        $graphUri = 'https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages?$top=1'
        Invoke-McmRest -Uri $graphUri -Headers $graphHeaders -Method Get | Out-Null
        $results.Add((New-McmCheckResult -Name $checkName -Status 'PASS'))
    }
}
catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match 'status=403') {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
            -Hint ('Grant admin consent for ServiceMessage.Read.All in Entra portal: ' +
                   'https://entra.microsoft.com → Applications → App registrations → <your app> ' +
                   '→ API permissions → Add Microsoft Graph → Application permissions → ' +
                   'ServiceMessage.Read.All → Grant admin consent for <tenant>') `
            -Detail $errMsg))
    }
    elseif ($errMsg -match 'status=401') {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
            -Hint 'Token was acquired but Graph rejected it (401). Verify the token audience and app registration.' `
            -Detail $errMsg))
    }
    else {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
            -Hint 'Graph API call failed. Verify connectivity and app registration configuration.' `
            -Detail $errMsg))
    }
}

#endregion

#region Check 7 — Dataverse reachable

$checkName = 'Dataverse reachable'
try {
    $dvScope              = "$($DataverseUrl.TrimEnd('/'))/.default"
    $script:dvBaseUrl     = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
    $script:dvHeaders     = Get-McmDvHeaders -AuthMode $AuthMode -Scope $dvScope `
        -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $metadataUri = "$($script:dvBaseUrl)/`$metadata"
    Invoke-McmRest -Uri $metadataUri -Headers $script:dvHeaders -Method Get | Out-Null
    $results.Add((New-McmCheckResult -Name $checkName -Status 'PASS' -Detail $DataverseUrl))
}
catch {
    $script:dvHeaders = $null
    $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
        -Hint 'Verify DataverseUrl is the environment URL (e.g., https://org.crm.dynamics.com — no trailing /api/data/...)' `
        -Detail $_.Exception.Message))
}

#endregion

#region Check 8 — fsi_messagecenterlogs entity accessible

$checkName = 'fsi_messagecenterlogs entity accessible'
try {
    if (-not $script:dvHeaders) {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'SKIP' `
            -Hint 'Dataverse connection unavailable — check 7 (Dataverse reachable) must PASS first'))
    }
    else {
        $entityUri = "$($script:dvBaseUrl)/fsi_messagecenterlogs?`$top=1&`$select=fsi_messagecenterid"
        Invoke-McmRest -Uri $entityUri -Headers $script:dvHeaders -Method Get | Out-Null
        $results.Add((New-McmCheckResult -Name $checkName -Status 'PASS'))
    }
}
catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match 'status=404') {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
            -Hint 'Run python scripts/create_mcm_dataverse_schema.py — the table is missing' `
            -Detail $errMsg))
    }
    elseif ($errMsg -match 'status=401' -or $errMsg -match 'status=403') {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
            -Hint ("The app registration is not a Dataverse Application User with read access to " +
                   "fsi_messagecenterlog. See README Section 5 'Dataverse Application User'") `
            -Detail $errMsg))
    }
    else {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
            -Hint 'Unexpected error accessing fsi_messagecenterlogs entity set.' `
            -Detail $errMsg))
    }
}

#endregion

#region Check 9 — Alternate key fsi_MessageCenterIdKey Active

$checkName = 'Alt-key fsi_MessageCenterIdKey Active'
try {
    if (-not $script:dvHeaders) {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'SKIP' `
            -Hint 'Dataverse connection unavailable — check 7 (Dataverse reachable) must PASS first'))
    }
    else {
        $keysUri      = "$($script:dvBaseUrl)/EntityDefinitions(LogicalName='fsi_messagecenterlog')/Keys"
        $keysResponse = Invoke-McmRest -Uri $keysUri -Headers $script:dvHeaders -Method Get
        $altKey       = $null
        if ($keysResponse -and $keysResponse.value) {
            $altKey = $keysResponse.value |
                Where-Object { $_.SchemaName -eq 'fsi_MessageCenterIdKey' } |
                Select-Object -First 1
        }

        if (-not $altKey) {
            $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
                -Hint 'Alt-key not found; re-run create_mcm_dataverse_schema.py'))
        }
        else {
            $statusVal = [int]$altKey.EntityKeyIndexStatus
            switch ($statusVal) {
                2 {
                    $results.Add((New-McmCheckResult -Name $checkName -Status 'PASS' `
                        -Detail 'EntityKeyIndexStatus: Active (2)'))
                    break
                }
                { $_ -eq 0 -or $_ -eq 1 } {
                    $statusLabel = if ($statusVal -eq 0) { 'Pending (0)' } else { 'InProgress (1)' }
                    $results.Add((New-McmCheckResult -Name $checkName -Status 'WARN' `
                        -Hint 'Alt-key activation in progress — wait 60s and re-run preflight; OR see docs/poc-quickstart.md Step 1.3 wait gate' `
                        -Detail "EntityKeyIndexStatus: $statusLabel"))
                    break
                }
                3 {
                    $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
                        -Hint 'Alt-key activation FAILED — open the table in Power Apps maker portal → Keys → inspect; re-run create_mcm_dataverse_schema.py' `
                        -Detail 'EntityKeyIndexStatus: Failed (3)'))
                    break
                }
                default {
                    $results.Add((New-McmCheckResult -Name $checkName -Status 'WARN' `
                        -Hint "Unknown EntityKeyIndexStatus value: $statusVal. Validate manually in Power Apps maker portal." `
                        -Detail "EntityKeyIndexStatus: $statusVal"))
                }
            }
        }
    }
}
catch {
    $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
        -Hint 'Failed to query entity key definitions. Verify Dataverse connectivity and app permissions.' `
        -Detail $_.Exception.Message))
}

#endregion

#region Check 10 — Teams webhook URL

$checkName = 'Teams webhook URL'
try {
    if (-not $TeamsWebhookUrl) {
        $results.Add((New-McmCheckResult -Name $checkName -Status 'SKIP' `
            -Hint 'Supply -TeamsWebhookUrl or set $env:MCM_TEAMS_WEBHOOK_URL to validate'))
    }
    else {
        $webhookUri      = [uri]$TeamsWebhookUrl
        $safeWebhookHost = $webhookUri.Host
        $isHttps         = ($webhookUri.Scheme -eq 'https')
        $isLoopbackHttp  = ($webhookUri.Scheme -eq 'http' -and $webhookUri.IsLoopback)
        if (-not $isHttps -and -not $isLoopbackHttp) {
            $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
                -Hint "Webhook URL scheme is '$($webhookUri.Scheme)'; must be 'https' (or 'http' for loopback testing via lab/07)." `
                -Detail $safeWebhookHost))
        }
        else {
            [System.Net.Dns]::GetHostAddresses($webhookUri.Host) | Out-Null

            $loopbackNote = if ($isLoopbackHttp) { ' (loopback HTTP - lab/07 capture listener; NOT acceptable in production)' } else { '' }

            if (-not $PostTestMessage) {
                $status = if ($isLoopbackHttp) { 'WARN' } else { 'PASS' }
                $results.Add((New-McmCheckResult -Name $checkName -Status $status `
                    -Hint "URL parsed and DNS resolved$loopbackNote; supply -PostTestMessage to also POST a test card" `
                    -Detail $safeWebhookHost))
            }
            else {
                if (-not (Test-Path -LiteralPath $TeamsCardTemplatePath)) {
                    $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
                        -Hint "Adaptive card template not found at: $TeamsCardTemplatePath. Verify -TeamsCardTemplatePath or run from the correct working directory."))
                }
                else {
                    $now    = (Get-Date).ToUniversalTime().ToString('o')
                    $nowP1d = (Get-Date).AddDays(1).ToUniversalTime().ToString('o')

                    $tokens = @{
                        severity                 = 'High'
                        title                    = '[PREFLIGHT TEST] message-center-monitor'
                        category                 = 'Admin'
                        services                 = 'preflight'
                        startDateTime            = $now
                        actionRequiredByDateTime = $nowP1d
                        id                       = 'MC-PREFLIGHT-TEST'
                        environment              = 'preflight'
                        appId                    = '00000000-0000-0000-0000-000000000000'
                        publisherPrefix          = 'fsi'
                        recordId                 = '00000000-0000-0000-0000-000000000000'
                    }

                    $cardJson      = Get-Content -LiteralPath $TeamsCardTemplatePath -Raw
                    $cardHashtable = $cardJson | ConvertFrom-Json -AsHashtable
                    $rendered      = Invoke-McmRenderTokens -Node $cardHashtable -Tokens $tokens

                    $payload = @{
                        type        = 'message'
                        attachments = @(
                            @{
                                contentType = 'application/vnd.microsoft.card.adaptive'
                                content     = $rendered
                            }
                        )
                    }
                    $payloadJson    = $payload | ConvertTo-Json -Depth 20
                    $webhookHeaders = @{ 'Content-Type' = 'application/json' }

                    try {
                        Invoke-McmRest -Uri $TeamsWebhookUrl -Headers $webhookHeaders `
                            -Method Post -Body $payloadJson | Out-Null
                        $status = if ($isLoopbackHttp) { 'WARN' } else { 'PASS' }
                        $results.Add((New-McmCheckResult -Name $checkName -Status $status `
                            -Hint "URL parsed, DNS resolved, and test card POSTed successfully$loopbackNote." `
                            -Detail $safeWebhookHost))
                    }
                    catch {
                        # Invoke-McmRest already redacts the URI in its error message via
                        # Format-McmSafeUri. Keep Detail short and safe; never echo
                        # $TeamsWebhookUrl directly here.
                        $postErr     = $_.Exception.Message
                        $statusMatch = $postErr -match 'status=(\d+)'
                        $statusCode  = if ($statusMatch) { $Matches[1] } else { 'unknown' }
                        $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
                            -Hint "Webhook URL was created in Teams Workflows but the POST returned $statusCode; verify the workflow is enabled" `
                            -Detail "host=$safeWebhookHost http=$statusCode"))
                    }
                }
            }
        }
    }
}
catch {
    # Same redaction discipline as the inner POST catch: never include
    # $TeamsWebhookUrl (a credential) in Detail.
    $errMsg      = $_.Exception.Message
    $statusMatch = $errMsg -match 'status=(\d+)'
    $statusCode  = if ($statusMatch) { $Matches[1] } else { 'unknown' }
    $safeHost    = try { ([uri]$TeamsWebhookUrl).Host } catch { '<unparseable>' }
    $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
        -Hint "Teams webhook check failed (HTTP $statusCode); verify the URL is reachable and the workflow is enabled." `
        -Detail "host=$safeHost http=$statusCode"))
}

#endregion

#region Check 11 — Phase 1 / Phase 3 mutual exclusion (CRITICAL)
#
# Heuristic deliberately tiered so a stale-leftover env-var DEFINITION (e.g.
# from a prior lab/03 full run that was later rolled back to Phase-1-only)
# does not lock the customer out of preflight:
#
#   - DEFINITION exists + VALUE bound -> Phase 3 is genuinely deployed -> FAIL on conflict
#   - DEFINITION exists + VALUE absent -> leftover scaffolding         -> WARN on conflict
#   - DEFINITION absent                 -> Phase 3 not deployed         -> PASS
#
# Passing -AssumePhase1Only bypasses Dataverse querying entirely and short-
# circuits to PASS when $env:MCM_TEAMS_WEBHOOK_URL is set. Use when the
# customer knows they will never enable Phase 3 and the WARN tier above is
# noisier than they want.

$checkName = 'Phase 1 / Phase 3 mutual exclusion'
try {
    $phase1Active = -not [string]::IsNullOrWhiteSpace($TeamsWebhookUrl)

    if ($phase1Active -and $AssumePhase1Only) {
        # Downgraded from PASS to WARN: a misconfigured environment where
        # Phase 3 is actually deployed would silently double-notify if we
        # short-circuited to PASS. The switch still bypasses the Dataverse
        # query (its purpose), but the operator now sees an explicit
        # incomplete-check banner instead of a false all-clear.
        $results.Add((New-McmCheckResult -Name $checkName -Status 'WARN' `
            -Hint ("-AssumePhase1Only skipped the Dataverse query for the Phase 3 " +
                   "environment-variable binding. If Phase 3 is actually deployed in " +
                   "this environment, duplicate Teams alerts will fire on every sync. " +
                   "Re-run preflight WITHOUT -AssumePhase1Only to verify no Phase 3 " +
                   "env-var VALUE binding exists.") `
            -Detail 'Phase 1 webhook active; Phase 3 detection skipped (-AssumePhase1Only)'))
    }
    else {
        $phase3DefExists = $false
        $phase3HasValue  = $false

        if ($script:dvHeaders) {
            $escapedEnvVarName = Format-McmODataLiteral $Phase3EnvVarLogicalName

            $defUri = "$($script:dvBaseUrl)/environmentvariabledefinitions" +
                      "?`$select=schemaname&`$filter=schemaname eq '$escapedEnvVarName'"
            $defResp = Invoke-McmRest -Uri $defUri -Headers $script:dvHeaders -Method Get
            $phase3DefExists = ($defResp -and $defResp.value -and $defResp.value.Count -gt 0)

            if ($phase3DefExists) {
                # An env-var DEFINITION without a bound VALUE is leftover scaffolding;
                # the Phase 3 flow has no concrete severities to act on.
                $valUri = "$($script:dvBaseUrl)/environmentvariablevalues" +
                          "?`$select=environmentvariablevalueid,value" +
                          "&`$filter=environmentvariabledefinitionid/schemaname eq '$escapedEnvVarName'"
                $valResp = Invoke-McmRest -Uri $valUri -Headers $script:dvHeaders -Method Get
                # A value-row whose 'value' is empty/whitespace is leftover
                # scaffolding (e.g. an unset binding created by a prior lab/03
                # run), not an active Phase 3 configuration. Treat it the same
                # as no value row so the WARN tier below catches it instead of
                # the FAIL tier - the Phase 3 flow has no concrete severities
                # to act on without a bound value.
                $phase3HasValue = $false
                if ($valResp -and $valResp.value) {
                    $phase3HasValue = @(
                        $valResp.value | Where-Object {
                            -not [string]::IsNullOrWhiteSpace([string]$_.value)
                        }
                    ).Count -gt 0
                }
            }
        }

        $phase3Active = $phase3HasValue
        $phase3Stale  = ($phase3DefExists -and -not $phase3HasValue)

        if ($phase1Active -and $phase3Active) {
            $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
                -Hint ("Both Phase 1 webhook (`$env:MCM_TEAMS_WEBHOOK_URL set) AND Phase 3 flow " +
                       "(environment variable $Phase3EnvVarLogicalName has a bound value) are " +
                       "configured. Duplicate Teams alerts will fire. Choose ONE path: clear " +
                       "`$env:MCM_TEAMS_WEBHOOK_URL to use only Phase 3, or remove the Phase 3 " +
                       "env-var VALUE binding to use only Phase 1.") `
                -Detail 'Both Phase 1 and Phase 3 notification paths active'))
        }
        elseif ($phase1Active -and $phase3Stale) {
            $results.Add((New-McmCheckResult -Name $checkName -Status 'WARN' `
                -Hint ("Phase 1 webhook active AND a stale Phase 3 env-var DEFINITION " +
                       "($Phase3EnvVarLogicalName) exists in Dataverse, but with no VALUE " +
                       "bound. This is most likely leftover from a prior lab/03 run or a " +
                       "rolled-back Phase 3 trial. Remove the definition with Power Platform " +
                       "CLI / Maker portal, OR re-run with -AssumePhase1Only to suppress " +
                       "this warning.") `
                -Detail 'Phase 3 env-var definition leftover (no value bound)'))
        }
        elseif (-not $phase1Active -and -not $phase3Active) {
            $results.Add((New-McmCheckResult -Name $checkName -Status 'WARN' `
                -Hint ("No notification path configured. Set `$env:MCM_TEAMS_WEBHOOK_URL for Phase 1 " +
                       "OR deploy Phase 3 flow + env vars per docs/flow-configuration.md.") `
                -Detail 'No notification path active'))
        }
        elseif ($phase1Active) {
            $results.Add((New-McmCheckResult -Name $checkName -Status 'PASS' `
                -Detail 'Phase 1 webhook active; Phase 3 flow not deployed'))
        }
        else {
            $results.Add((New-McmCheckResult -Name $checkName -Status 'PASS' `
                -Detail 'Phase 3 flow active; Phase 1 webhook not configured'))
        }
    }
}
catch {
    $results.Add((New-McmCheckResult -Name $checkName -Status 'FAIL' `
        -Hint 'Failed to query environment variable definitions/values. Verify Dataverse connectivity, or re-run with -AssumePhase1Only to skip this check.' `
        -Detail $_.Exception.Message))
}

#endregion

#region Output — banner, color table, summary, hints

Write-Host ''
Write-Host '╔══════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  message-center-monitor — Preflight Results      ║' -ForegroundColor Cyan
Write-Host '╚══════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

$colCheck  = 45
$colStatus = 6
Write-Host ("{0,-$colCheck} {1,-$colStatus} {2}" -f 'Check', 'Status', 'Detail') -ForegroundColor White
Write-Host ("{0,-$colCheck} {1,-$colStatus} {2}" -f ('-' * ($colCheck - 1)), '------', ('-' * 30)) -ForegroundColor DarkGray

foreach ($r in $results) {
    $color = switch ($r.Status) {
        'PASS' { 'Green'    ; break }
        'WARN' { 'Yellow'   ; break }
        'FAIL' { 'Red'      ; break }
        'SKIP' { 'DarkGray' ; break }
        default { 'White' }
    }
    $detailText = if ($null -ne $r.Detail -and "$($r.Detail)" -ne '') {
        [string]$r.Detail
    }
    elseif ($r.Status -in @('SKIP','WARN')) {
        $r.Hint
    }
    else {
        ''
    }
    if ($detailText.Length -gt 60) { $detailText = $detailText.Substring(0, 57) + '...' }
    Write-Host ("{0,-$colCheck} {1,-$colStatus} {2}" -f $r.Check, $r.Status, $detailText) -ForegroundColor $color
}

Write-Host ''

$passCount = ($results | Where-Object Status -eq 'PASS').Count
$warnCount = ($results | Where-Object Status -eq 'WARN').Count
$failCount = ($results | Where-Object Status -eq 'FAIL').Count
$skipCount = ($results | Where-Object Status -eq 'SKIP').Count

Write-Host ("Total: {0} | PASS: {1} | WARN: {2} | FAIL: {3} | SKIP: {4}" -f `
    $results.Count, $passCount, $warnCount, $failCount, $skipCount)
Write-Host ''

$failedChecks = $results | Where-Object Status -eq 'FAIL'
if ($failedChecks) {
    Write-Host 'Failures requiring action:' -ForegroundColor Red
    foreach ($f in $failedChecks) {
        Write-Host "  [$($f.Check)]" -ForegroundColor Red
        Write-Host "  Hint: $($f.Hint)" -ForegroundColor Red
        Write-Host ''
    }
}

if ($failCount -gt 0) {
    exit 1
}
elseif ($warnCount -gt 0) {
    Write-Host 'Preflight complete with warnings — proceed with caution' -ForegroundColor Yellow
    exit 0
}
else {
    exit 0
}

#endregion
