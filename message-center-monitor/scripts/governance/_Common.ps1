<#
.SYNOPSIS
    Shared helpers for Message Center Monitor governance scripts.

.DESCRIPTION
    Dot-sourced by Invoke-MessageCenterSync.ps1, Get-MessageCenterAssessmentStatus.ps1,
    and Export-MessageCenterEvidence.ps1. Provides:

      - Get-McmAccessToken     : managed-identity-first token acquisition.
      - Get-McmDvHeaders       : cached Dataverse headers with proactive refresh.
      - Invoke-McmRest         : retry-aware REST wrapper honouring Retry-After.
      - Format-McmODataLiteral : single-quote OData literal escape helper.
      - Format-McmODataDate    : ISO-8601 round-trip Dataverse date formatter.

    All callers should run with Set-StrictMode and ErrorActionPreference=Stop.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module-scope token cache: one entry per (scope) string.
$script:McmTokenCache = @{}

function Get-McmAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ManagedIdentity', 'WorkloadIdentity', 'Interactive', 'DeviceCode', 'ClientSecret')]
        [string]$AuthMode,

        [Parameter(Mandatory)]
        [string]$Scope,

        [string]$TenantId,
        [string]$ClientId,
        [SecureString]$ClientSecret
    )

    Import-Module MSAL.PS -ErrorAction Stop

    switch ($AuthMode) {
        'ManagedIdentity' {
            # Managed-identity support added in MSAL.PS 4.37.
            $msal = Get-Module MSAL.PS
            if (-not $msal -or $msal.Version -lt [Version]'4.37.0.0') {
                throw "MSAL.PS 4.37.0 or later is required for -AuthMode ManagedIdentity. Installed: $($msal.Version). Run: Install-Module MSAL.PS -MinimumVersion 4.37.0 -Scope CurrentUser -Force"
            }
            # Resource form (no /.default) is what the IMDS endpoint expects.
            $resource = $Scope -replace '/\.default$', ''
            return Get-MsalToken -ManagedIdentity -Resource $resource
        }
        'WorkloadIdentity' {
            # Workload identity federation (GitHub Actions OIDC, Azure DevOps OIDC, etc.).
            # Exchanges a federated token for an Azure AD access token.
            if (-not $ClientId) { throw "ClientId is required for WorkloadIdentity auth." }
            if (-not $TenantId) { throw "TenantId is required for WorkloadIdentity auth." }

            # Resolve the federated token from one of three standard locations.
            $federatedToken = $null
            if ($env:AZURE_FEDERATED_TOKEN) {
                $federatedToken = $env:AZURE_FEDERATED_TOKEN
            }
            elseif ($env:AZURE_FEDERATED_TOKEN_FILE -and (Test-Path -LiteralPath $env:AZURE_FEDERATED_TOKEN_FILE)) {
                $federatedToken = (Get-Content -LiteralPath $env:AZURE_FEDERATED_TOKEN_FILE -Raw).Trim()
            }
            elseif ($env:ACTIONS_ID_TOKEN_REQUEST_URL -and $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN) {
                # GitHub Actions OIDC: request a token scoped to api://AzureADTokenExchange
                $reqUri = "$($env:ACTIONS_ID_TOKEN_REQUEST_URL)&audience=api://AzureADTokenExchange"
                $reqHeaders = @{ Authorization = "Bearer $($env:ACTIONS_ID_TOKEN_REQUEST_TOKEN)" }
                $resp = Invoke-RestMethod -Uri $reqUri -Headers $reqHeaders -Method Get
                $federatedToken = $resp.value
            }
            else {
                throw "WorkloadIdentity auth requires one of: `$env:AZURE_FEDERATED_TOKEN, `$env:AZURE_FEDERATED_TOKEN_FILE, or GitHub Actions OIDC env vars (ACTIONS_ID_TOKEN_REQUEST_URL + ACTIONS_ID_TOKEN_REQUEST_TOKEN)."
            }

            return Get-MsalToken -TenantId $TenantId -ClientId $ClientId -ClientAssertion $federatedToken -Scopes @($Scope)
        }
        'Interactive' {
            if (-not $ClientId) { throw "ClientId is required for Interactive auth." }
            if (-not $TenantId) { throw "TenantId is required for Interactive auth." }
            return Get-MsalToken -ClientId $ClientId -TenantId $TenantId -Interactive -Scopes @($Scope)
        }
        'DeviceCode' {
            if (-not $ClientId) { throw "ClientId is required for DeviceCode auth." }
            if (-not $TenantId) { throw "TenantId is required for DeviceCode auth." }
            return Get-MsalToken -ClientId $ClientId -TenantId $TenantId -DeviceCode -Scopes @($Scope)
        }
        'ClientSecret' {
            # legacy: dev-only path; prefer ManagedIdentity in production
            if (-not $ClientId) { throw "ClientId is required for ClientSecret auth." }
            if (-not $TenantId) { throw "TenantId is required for ClientSecret auth." }
            if (-not $ClientSecret) { throw "ClientSecret is required for -AuthMode ClientSecret." }
            return Get-MsalToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scopes @($Scope)
        }
    }
}

function Get-McmDvHeaders {
    <#
    .SYNOPSIS
        Returns Dataverse REST headers with a cached, auto-refreshing token.

    .DESCRIPTION
        Re-acquires the token when within 5 minutes of expiry. Safe to call once
        per per-message iteration in long-running sync loops.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ManagedIdentity', 'WorkloadIdentity', 'Interactive', 'DeviceCode', 'ClientSecret')]
        [string]$AuthMode,

        [Parameter(Mandatory)]
        [string]$Scope,

        [string]$TenantId,
        [string]$ClientId,
        [SecureString]$ClientSecret,

        [hashtable]$ExtraHeaders
    )

    $cached = $null
    if ($script:McmTokenCache.ContainsKey($Scope)) {
        $cached = $script:McmTokenCache[$Scope]
    }

    $needsRefresh = $true
    if ($cached -and $cached.ExpiresOn) {
        $threshold = (Get-Date).ToUniversalTime().AddMinutes(5)
        if ($cached.ExpiresOn.UtcDateTime -gt $threshold) {
            $needsRefresh = $false
        } else {
            Write-Verbose "Token within 5 minutes of expiry; refreshing."
        }
    }

    if ($needsRefresh) {
        $cached = Get-McmAccessToken -AuthMode $AuthMode -Scope $Scope `
            -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
        $script:McmTokenCache[$Scope] = $cached
    }

    $headers = @{
        Authorization      = "Bearer $($cached.AccessToken)"
        'Content-Type'     = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }
    if ($ExtraHeaders) {
        foreach ($k in $ExtraHeaders.Keys) { $headers[$k] = $ExtraHeaders[$k] }
    }
    return $headers
}

function Invoke-McmRest {
    <#
    .SYNOPSIS
        Throttling-aware REST wrapper for Graph and Dataverse.

    .DESCRIPTION
        Honors Retry-After (seconds or HTTP-date) on 429/503; otherwise applies
        exponential backoff capped at 60 seconds. Throws on terminal failure with
        a structured error containing status code and response body when available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [hashtable]$Headers,
        [Parameter(Mandatory)] [string]$Method,
        [string]$Body,
        [int]$MaxRetries = 5,
        [int]$BaseDelaySeconds = 2,
        [int]$MaxDelaySeconds = 60
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($PSBoundParameters.ContainsKey('Body') -and $Body) {
                return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body $Body
            } else {
                return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method
            }
        }
        catch {
            $status = $null
            try { $status = [int]$_.Exception.Response.StatusCode } catch {}

            $isRetryable = ($status -eq 429 -or ($status -ge 500 -and $status -le 599))
            if ($isRetryable -and $attempt -le $MaxRetries) {
                $retryAfter = 0
                try {
                    # PS 7+ throws HttpResponseException whose .Headers is
                    # HttpResponseHeaders. String indexing returns $null, so
                    # use TryGetValues and fall back to PS 5.1 dictionary access.
                    $hdrs = $_.Exception.Response.Headers
                    $values = $null
                    if ($hdrs -and $hdrs.GetType().GetMethod('TryGetValues')) {
                        if ($hdrs.TryGetValues('Retry-After', [ref]$values)) {
                            $retryAfter = [int]([System.Linq.Enumerable]::FirstOrDefault($values))
                        }
                    } elseif ($hdrs) {
                        $hdr = $hdrs['Retry-After']
                        if ($hdr) { $retryAfter = [int]$hdr }
                    }
                } catch {}
                if ($retryAfter -le 0) {
                    $retryAfter = [Math]::Min($MaxDelaySeconds, $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1))
                }
                Write-Warning "  Throttled ($status). Sleeping $retryAfter s (attempt $attempt/$MaxRetries)..."
                Start-Sleep -Seconds $retryAfter
                continue
            }

            $body = $null
            try {
                if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                    $body = $_.ErrorDetails.Message
                }
            } catch {}
            $msg = "Invoke-McmRest failed: status=$status method=$Method uri=$Uri error=$($_.Exception.Message)"
            if ($body) { $msg += " body=$body" }
            throw $msg
        }
    }
}

function Invoke-McmDvUpsertMessage {
    <#
    .SYNOPSIS
        Upserts a Message Center record into Dataverse, preserving admin-owned assessment fields.

    .DESCRIPTION
        Implements the conditional create -> 412 -> update branching that protects
        admin-owned columns (fsi_assessmentstatus, fsi_assessment, fsi_assessedby,
        fsi_assesseddate, fsi_actionstaken, fsi_impactsagents, fsi_notifiedon) from
        being clobbered on subsequent syncs.

        Step 1: PATCH with `If-None-Match: *` (create-only). On HTTP 201 the row is
                created with fsi_assessmentstatus = NotAssessed.
        Step 2: On HTTP 412 the row exists. Issue a second PATCH WITHOUT
                If-None-Match and WITHOUT any admin-owned columns. The caller MUST
                ensure $Record excludes admin-owned columns (the function enforces
                this contract by adding only fsi_assessmentstatus to the create
                payload, never to the update payload).
        404:    Alternate key not provisioned -> throws with actionable hint.

        Extracted from Invoke-MessageCenterSync.ps1 in v2.4.0 to make C1 branching
        unit-testable. No behavioural change.

    .PARAMETER DataverseBaseUrl
        Dataverse Web API base URL (e.g. https://org.crm.dynamics.com/api/data/v9.2).

    .PARAMETER MessageId
        The Message Center post id (used as the alternate-key value).

    .PARAMETER Record
        Hashtable of Graph-owned columns to write. MUST NOT include admin-owned
        columns. Caller is responsible for honoring this contract; see
        Guards.Tests.ps1 for the static check.

    .PARAMETER DataverseHeaders
        Dataverse REST headers (Authorization, Content-Type, OData-* etc.).

    .PARAMETER AssessmentNotAssessedValue
        Integer choice value for "NotAssessed" status. Provided by the caller so
        this function stays free of solution-specific constants.

    .OUTPUTS
        [pscustomobject] @{ Action = 'Created' | 'Updated'; MessageId = <string> }

    .NOTES
        On terminal failure throws a descriptive message; caller catches and
        increments its own failed counter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$DataverseBaseUrl,
        [Parameter(Mandatory)] [string]$MessageId,
        [Parameter(Mandatory)] [hashtable]$Record,
        [Parameter(Mandatory)] [hashtable]$DataverseHeaders,
        [Parameter(Mandatory)] [int]$AssessmentNotAssessedValue
    )

    $escapedId = Format-McmODataLiteral $MessageId
    $upsertUrl = "$DataverseBaseUrl/fsi_messagecenterlogs(fsi_messagecenterid='$escapedId')"

    # Create-only payload: clone $Record then ADD fsi_assessmentstatus.
    # The original $Record is never mutated and is reused verbatim for the
    # update branch, guaranteeing admin-owned columns are never sent on update.
    $createPayload = $Record.Clone()
    $createPayload['fsi_assessmentstatus'] = $AssessmentNotAssessedValue

    $createHeaders = @{}
    foreach ($k in $DataverseHeaders.Keys) { $createHeaders[$k] = $DataverseHeaders[$k] }
    $createHeaders['If-None-Match'] = '*'

    $existed = $false
    try {
        Invoke-McmRest -Uri $upsertUrl -Headers $createHeaders -Method Patch `
            -Body ($createPayload | ConvertTo-Json -Depth 5) | Out-Null
        return [pscustomobject]@{ Action = 'Created'; MessageId = $MessageId }
    }
    catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -match 'status=412' -or $errMsg -match 'PreconditionFailed') {
            $existed = $true
        }
        elseif ($errMsg -match 'status=404' -or $errMsg -match 'Resource not found for the segment') {
            throw "Upsert failed for ${MessageId}: Alternate key fsi_MessageCenterIdKey not found - re-run create_mcm_dataverse_schema.py to provision it."
        }
        else {
            throw "Create failed for ${MessageId}: $errMsg"
        }
    }

    if ($existed) {
        try {
            # Update path: $Record (NOT $createPayload) is sent. By contract it
            # excludes admin-owned columns, so PATCH cannot overwrite them.
            Invoke-McmRest -Uri $upsertUrl -Headers $DataverseHeaders -Method Patch `
                -Body ($Record | ConvertTo-Json -Depth 5) | Out-Null
            return [pscustomobject]@{ Action = 'Updated'; MessageId = $MessageId }
        }
        catch {
            throw "Update failed for ${MessageId}: $($_.Exception.Message)"
        }
    }
}

function Write-McmRedacted {
    <#
    .SYNOPSIS
        Writes a log line with Bearer tokens, client secrets, and Authorization
        headers redacted.

    .DESCRIPTION
        Centralised secret-scrubbing for lab and governance scripts. Use this
        instead of Write-Host / Write-Information when emitting strings that
        could contain HTTP bodies, headers, or token responses.

        Redactions:
          - Bearer <token>                   -> Bearer <REDACTED>
          - "access_token":"..."             -> "access_token":"<REDACTED>"
          - client_secret=<value>            -> client_secret=<REDACTED>
          - "client_secret":"..."            -> "client_secret":"<REDACTED>"
          - Authorization: <value>           -> Authorization: <REDACTED>

    .PARAMETER Message
        The string to scrub. Multiline OK.

    .PARAMETER Stream
        Output stream: Host (default), Verbose, Warning, Information.

    .EXAMPLE
        Write-McmRedacted "Authorization: Bearer eyJhbGc..."
        # writes: Authorization: Bearer <REDACTED>
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [AllowEmptyString()] [string]$Message,
        [ValidateSet('Host', 'Verbose', 'Warning', 'Information')]
        [string]$Stream = 'Host'
    )
    process {
        $scrubbed = $Message
        $scrubbed = $scrubbed -replace '(?i)Bearer\s+[A-Za-z0-9._\-+/=]+', 'Bearer <REDACTED>'
        $scrubbed = $scrubbed -replace '(?i)"access_token"\s*:\s*"[^"]*"', '"access_token":"<REDACTED>"'
        $scrubbed = $scrubbed -replace '(?i)"refresh_token"\s*:\s*"[^"]*"', '"refresh_token":"<REDACTED>"'
        $scrubbed = $scrubbed -replace '(?i)"id_token"\s*:\s*"[^"]*"', '"id_token":"<REDACTED>"'
        $scrubbed = $scrubbed -replace '(?i)"client_secret"\s*:\s*"[^"]*"', '"client_secret":"<REDACTED>"'
        $scrubbed = $scrubbed -replace '(?i)client_secret=[^&\s"]+', 'client_secret=<REDACTED>'
        $scrubbed = $scrubbed -replace '(?im)^(\s*Authorization\s*:\s*).+$', '$1<REDACTED>'

        switch ($Stream) {
            'Verbose'     { Write-Verbose     $scrubbed }
            'Warning'     { Write-Warning     $scrubbed }
            'Information' { Write-Information $scrubbed -InformationAction Continue }
            default       { Write-Host        $scrubbed }
        }
    }
}

function Format-McmODataLiteral {
    <#
    .SYNOPSIS
        Escapes a string for safe use as an OData single-quoted literal.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return $Value.Replace("'", "''")
}

function Format-McmODataDate {
    <#
    .SYNOPSIS
        Formats a DateTime as a UTC ISO-8601 string suitable for Dataverse OData filters.
    #>
    param([Parameter(Mandatory)][datetime]$Value)
    return [System.Xml.XmlConvert]::ToString(
        $Value.ToUniversalTime(),
        [System.Xml.XmlDateTimeSerializationMode]::Utc
    )
}
