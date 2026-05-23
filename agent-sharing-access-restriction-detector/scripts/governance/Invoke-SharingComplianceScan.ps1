<#
.SYNOPSIS
    Detects agents with sharing configurations that violate zone-based access policies.

.DESCRIPTION
    Main scanning script for the Agent Sharing Access Restriction Detector (ASARD).
    Enumerates Power Platform environments and evaluates each Copilot Studio agent's
    sharing configuration against zone-specific governance policies.

    For each agent, the script:
    1. Authenticates to Power Platform admin cmdlets via service principal
    2. Enumerates environments (with optional sandbox/trial exclusion)
    3. Determines governance zone per environment naming convention or Dataverse lookup
    4. Queries Copilot Studio agents via the Dataverse Web API (/api/data/v9.2/bots)
    5. Extracts sharing configuration from accesscontrolpolicy and authorizedsecuritygroupids
    6. Loads approved security groups for the zone
    7. Compares actual sharing against zone policy:
       - Zone 1: Any group/org-wide/public sharing = NonCompliant
       - Zone 2: Sharing to groups not in approved list = NonCompliant
       - Zone 3: Sharing to groups not in approved list = NonCompliant; org-wide/public = NonCompliant
       - Unknown: Treated as Zone 1 (most restrictive)
    8. Optionally persists results to Dataverse fsi_agentsharingcompliances table
    9. Outputs results in the specified format

    Where UASD detects broad unrestricted sharing, ASARD validates granular zone-based
    group policies per Controls 1.18 and 2.8.

.PARAMETER TenantId
    Microsoft Entra ID tenant GUID. Defaults to $env:AZURE_TENANT_ID.

.PARAMETER ClientId
    Service principal application (client) ID. Defaults to $env:AZURE_CLIENT_ID.

.PARAMETER ClientSecret
    Service principal client secret as SecureString. If not provided, attempts to
    read from $env:AZURE_CLIENT_SECRET. This is a legacy development fallback;
    prefer managed identity, workload identity federation, or certificate-based
    service principal authentication for production automation.

.PARAMETER EnvironmentFilter
    Optional list of environment display names or IDs to limit the scan scope.
    When omitted, all accessible environments are scanned.

.PARAMETER ExcludeSandbox
    Exclude sandbox environments from scan. Default: $true.

.PARAMETER ExcludeTrial
    Exclude trial environments from scan. Default: $false.

.PARAMETER DataverseUrl
    Dataverse organization URL for persisting results and loading approved groups.
    When provided, results are written to fsi_agentsharingcompliances.

.PARAMETER OutputFormat
    Output format: Table (default), JSON, or Object.

.PARAMETER IncludeCompliant
    Include compliant agents in output. Default: violations only.

.OUTPUTS
    Formatted table (default), JSON string, or PSCustomObject[] depending on -OutputFormat.

.EXAMPLE
    .\Invoke-SharingComplianceScan.ps1

    Scan all non-sandbox environments using environment variable credentials.

.EXAMPLE
    .\Invoke-SharingComplianceScan.ps1 -EnvironmentFilter @("Prod-Zone3") -OutputFormat JSON

    Scan specific environments with JSON output for evidence pipeline.

.EXAMPLE
    .\Invoke-SharingComplianceScan.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -IncludeCompliant

    Full scan with Dataverse persistence and compliant agents included.

.NOTES
    File: Invoke-SharingComplianceScan.ps1
    Version: 2.0.2
    Solution: Agent Sharing Access Restriction Detector (ASARD)
    Controls: 1.18 (Application-Level Authorization), 2.8 (Access Control/Segregation of Duties)
    Regulations: FINRA Rule 4511, SOX Section 404, GLBA Section 501(b)

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Invoke-SharingComplianceScan {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Dev-only legacy auth path. Production deployments use managed identity via scripts/shared/dataverse_client.py per AGENTS.md "Authentication standard". Plaintext secret here is wrapped immediately into SecureString and never persisted.'
    )]
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TenantId = $env:AZURE_TENANT_ID,

        [Parameter()]
        [string]$ClientId = $env:AZURE_CLIENT_ID,

        [Parameter()]
        [SecureString]$ClientSecret,

        [Parameter()]
        [string[]]$EnvironmentFilter,

        [Parameter()]
        [switch]$ExcludeSandbox = $true,

        [Parameter()]
        [switch]$ExcludeTrial,

        [Parameter()]
        [string]$DataverseUrl,

        [Parameter()]
        [ValidateSet('Table', 'JSON', 'Object')]
        [string]$OutputFormat = 'Table',

        [Parameter()]
        [switch]$IncludeCompliant,

        [Parameter()]
        [switch]$DryRun
    )

    $ErrorActionPreference = 'Stop'
    $scriptRoot = $PSScriptRoot
    $runId = [guid]::NewGuid().ToString()
    $scanStartTime = Get-Date -Format 'o'

    Write-Verbose "========================================="
    Write-Verbose "Agent Sharing Access Restriction Detector v2.0.2"
    Write-Verbose "RunId: $runId"
    Write-Verbose "ScanStart: $scanStartTime"
    Write-Verbose "========================================="

    #region Import Companion Scripts

    $policyScript = Join-Path $scriptRoot 'Get-ExpectedSharingPolicy.ps1'
    if (-not (Test-Path $policyScript)) {
        throw "Required script not found: $policyScript"
    }

    #endregion

    #region Authentication

    Write-Host ""
    Write-Host "Agent Sharing Access Restriction Detector v2.0.2" -ForegroundColor Cyan
    Write-Host "RunId: $runId" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[1/5] Authenticating to Power Platform Admin API..." -ForegroundColor Cyan

    if (-not $TenantId) {
        throw "TenantId is required. Set -TenantId or `$env:AZURE_TENANT_ID."
    }
    if (-not $ClientId) {
        throw "ClientId is required. Set -ClientId or `$env:AZURE_CLIENT_ID."
    }

    # legacy: dev-only — replace with managed identity in production.
    # Resolve client secret for environments that do not yet support stronger unattended credentials.
    $plainSecret = $null
    if ($ClientSecret) {
        $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
        )
    }
    elseif ($env:AZURE_CLIENT_SECRET) {
        $plainSecret = $env:AZURE_CLIENT_SECRET
    }
    else {
        throw "ClientSecret is required. Set -ClientSecret or `$env:AZURE_CLIENT_SECRET."
    }

    # Acquire token for the Power Platform admin scope.
    $tokenBody = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $plainSecret
        scope         = 'https://service.powerapps.com/.default'
    }
    try {
        $tokenResponse = Invoke-RestMethod `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Method Post `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body $tokenBody `
            -ErrorAction Stop

        $accessToken = $tokenResponse.access_token
        Write-Host "  Authentication successful." -ForegroundColor Green
    }
    catch {
        throw "Authentication failed: $($_.Exception.Message)"
    }

    # If DataverseUrl provided, also get a Dataverse token
    $dataverseToken = $null
    if ($DataverseUrl) {
        $dvTokenBody = @{
            grant_type    = 'client_credentials'
            client_id     = $ClientId
            client_secret = $plainSecret
            scope         = "$($DataverseUrl.TrimEnd('/'))/.default"
        }
        try {
            $dvTokenResponse = Invoke-RestMethod `
                -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                -Method Post `
                -ContentType 'application/x-www-form-urlencoded' `
                -Body $dvTokenBody `
                -ErrorAction Stop
            $dataverseToken = $dvTokenResponse.access_token
        }
        catch {
            Write-Warning "Dataverse authentication failed. Approved-group lookups and result persistence will be DISABLED for this run: $($_.Exception.Message)"
            $script:DataverseAuthFailed = $true
            $DataverseUrl = $null
        }
    }

    #endregion

    #region Authenticate PowerApps Admin Module

    # The Microsoft.PowerApps.Administration.PowerShell module is used for
    # environment enumeration. Bot sharing posture is read from the Dataverse
    # bot table because Microsoft Learn documents Get-AdminPowerAppRoleAssignment
    # for Power Apps only; the module does not publish bot-specific sharing
    # cmdlets such as Set-AdminBotPermissions or Get-AdminBotShare. The module's
    # cmdlets require a separate session login via Add-PowerAppsAccount — the
    # OAuth token above is for raw REST calls and does not authenticate the
    # cmdlet session.
    try {
        $secureSecret = ConvertTo-SecureString $plainSecret -AsPlainText -Force
        Add-PowerAppsAccount -TenantID $TenantId -ApplicationId $ClientId -ClientSecret $secureSecret -Endpoint prod -ErrorAction Stop | Out-Null
        Write-Host "  PowerApps admin session established." -ForegroundColor Green
    }
    catch {
        throw "Add-PowerAppsAccount failed. Verify the service principal is registered as a Power Platform admin: $($_.Exception.Message)"
    }

    #endregion

    #region Enumerate Environments

    Write-Host "[2/5] Enumerating Power Platform environments..." -ForegroundColor Cyan

    try {
        $allEnvironments = Get-AdminPowerAppEnvironment -ErrorAction Stop
    }
    catch {
        throw "Failed to enumerate environments. Verify Microsoft.PowerApps.Administration.PowerShell is installed and authenticated: $($_.Exception.Message)"
    }

    $environments = $allEnvironments | Where-Object {
        $env = $_
        $include = $true

        if ($EnvironmentFilter) {
            $matchesFilter = ($env.EnvironmentName -in $EnvironmentFilter) -or
                             ($env.DisplayName -in $EnvironmentFilter)
            if (-not $matchesFilter) { $include = $false }
        }
        if ($ExcludeSandbox -and $env.EnvironmentType -eq 'Sandbox') {
            $include = $false
        }
        if ($ExcludeTrial -and $env.EnvironmentType -eq 'Trial') {
            $include = $false
        }

        $include
    }

    Write-Host "  Found $($environments.Count) environment(s) to scan (of $($allEnvironments.Count) total)"

    #endregion

    #region Zone Classification Helper

    function Get-EnvironmentZone {
        param(
            [string]$EnvironmentId,
            [string]$EnvironmentDisplayName
        )

        # Try shared zone classification script
        $sharedZoneScript = Join-Path (Split-Path (Split-Path $scriptRoot -Parent) -Parent) 'scripts\shared\Get-ZoneClassification.ps1'
        if (Test-Path $sharedZoneScript) {
            try {
                $zone = & $sharedZoneScript `
                    -EnvironmentId $EnvironmentId `
                    -EnvironmentDisplayName $EnvironmentDisplayName
                if ($zone) { return $zone }
            }
            catch {
                Write-Verbose "Shared zone classification failed: $($_.Exception.Message)"
            }
        }

        # Fallback: naming convention
        $normalized = $EnvironmentDisplayName.ToLower()
        if ($normalized -match 'z3|zone3|prod|production|enterprise') { return 'Zone3' }
        if ($normalized -match 'z2|zone2|team|collab|shared')         { return 'Zone2' }
        if ($normalized -match 'z1|zone1|personal|dev|sandbox')       { return 'Zone1' }

        return 'Unknown'
    }

    #endregion

    #region Load Approved Security Groups

    function Get-ApprovedSecurityGroups {
        param(
            [string]$Zone,
            [string]$DvUrl,
            [string]$DvToken
        )

        if ($DvUrl -and $DvToken) {
            try {
                $apiBase = "$($DvUrl.TrimEnd('/'))/api/data/v9.2"
                $zoneIntMap = @{ 'Zone1' = 1; 'Zone2' = 2; 'Zone3' = 3 }
                $zoneInt = if ($zoneIntMap.ContainsKey($Zone)) { $zoneIntMap[$Zone] } else { 0 }
                $filter = "fsi_zone eq $zoneInt and fsi_isactive eq true"
                $select = "fsi_securitygroupid,fsi_securitygroupname,fsi_zone"
                $queryUrl = "$apiBase/fsi_approvedsecuritygrouppolicies?`$filter=$filter&`$select=$select"

                $headers = @{
                    'Authorization'    = "Bearer $DvToken"
                    'Accept'           = 'application/json'
                    'OData-MaxVersion' = '4.0'
                    'OData-Version'    = '4.0'
                }

                $groups = [System.Collections.ArrayList]::new()
                $nextUrl = $queryUrl
                while ($nextUrl) {
                    $response = Invoke-RestMethod -Uri $nextUrl -Headers $headers -Method Get -ErrorAction Stop
                    $values = if ($response.value) { $response.value } else { @() }
                    foreach ($record in $values) {
                        if ($record.fsi_securitygroupid) { [void]$groups.Add($record.fsi_securitygroupid) }
                    }
                    $nextUrl = $response.'@odata.nextLink'
                }

                return $groups.ToArray()
            }
            catch {
                Write-Warning "Failed to load approved groups from Dataverse for $Zone`: $($_.Exception.Message)"
            }
        }

        # Default empty — no approved groups means all group sharing is non-compliant
        return @()
    }

    #endregion

    #region Compliance Evaluation Helpers

    function Get-SharingViolationType {
        param(
            [int]$SharingType,
            [string[]]$SharedGroupIds,
            [PSCustomObject]$Policy,
            [string[]]$ApprovedGroupIds
        )

        # Internal ASARD mapping: 0=SpecificUsers/GroupMembership, 1=OrgWide, 2=Public/Unknown.
        if ($SharingType -eq 2) {
            return 'PublicSharing'
        }

        if ($SharingType -eq 1) {
            if (-not $Policy.AllowOrgWideSharing) {
                return 'OrgWideSharing'
            }
        }

        # Check group sharing
        if ($SharedGroupIds -and $SharedGroupIds.Count -gt 0) {
            if (-not $Policy.AllowGroupSharing) {
                return 'GroupSharing'
            }

            if ($Policy.RequireApprovedGroups) {
                if (-not $ApprovedGroupIds -or $ApprovedGroupIds.Count -eq 0) {
                    return 'UnapprovedGroup'
                }

                foreach ($groupId in $SharedGroupIds) {
                    if ($groupId -notin $ApprovedGroupIds) {
                        return 'UnapprovedGroup'
                    }
                }
            }
        }

        return 'Compliant'
    }

    function Get-ViolationSeverity {
        param(
            [PSCustomObject]$Policy,
            [string]$ViolationType
        )

        if ($Policy.ViolationSeverity.ContainsKey($ViolationType)) {
            return $Policy.ViolationSeverity[$ViolationType]
        }
        return 'Informational'
    }

    function Get-SeverityCode {
        param([string]$Severity)
        switch ($Severity) {
            'Critical'      { return 100000000 }
            'High'          { return 100000001 }
            'Medium'        { return 100000002 }
            'Low'           { return 100000003 }
            'Informational' { return 100000004 }
            default         { return 100000003 }
        }
    }

    function ConvertTo-AuthorizedSecurityGroupIds {
        param([object]$AuthorizedSecurityGroupIds)

        if ($null -eq $AuthorizedSecurityGroupIds) { return @() }

        $rawIds = if ($AuthorizedSecurityGroupIds -is [System.Array]) {
            $AuthorizedSecurityGroupIds
        }
        else {
            $rawText = ([string]$AuthorizedSecurityGroupIds).Trim()
            if ($rawText.StartsWith('[')) {
                try {
                    @($rawText | ConvertFrom-Json -ErrorAction Stop)
                }
                catch {
                    $rawText -split '[,;]'
                }
            }
            else {
                $rawText -split '[,;]'
            }
        }

        return @(
            $rawIds |
                ForEach-Object { ([string]$_).Trim().Trim('"', '[', ']') } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }

    function Get-AgentSharingClassification {
        param([object]$AccessControlPolicy)

        [int]$policyCode = -1
        if ($null -ne $AccessControlPolicy) {
            [void][int]::TryParse([string]$AccessControlPolicy, [ref]$policyCode)
        }

        switch ($policyCode) {
            0 {
                return [PSCustomObject]@{
                    SharingType       = 1
                    SharingLabel      = 'OrgWide'
                    IsGroupMembership = $false
                }
            }
            1 {
                return [PSCustomObject]@{
                    SharingType       = 0
                    SharingLabel      = 'SpecificUsers'
                    IsGroupMembership = $false
                }
            }
            2 {
                return [PSCustomObject]@{
                    SharingType       = 0
                    SharingLabel      = 'GroupMembership'
                    IsGroupMembership = $true
                }
            }
            3 {
                return [PSCustomObject]@{
                    SharingType       = 2
                    SharingLabel      = 'Public'
                    IsGroupMembership = $false
                }
            }
            default {
                return [PSCustomObject]@{
                    SharingType       = 2
                    SharingLabel      = 'Unknown'
                    IsGroupMembership = $false
                }
            }
        }
    }

    #endregion

    #region Scan Agents Across Environments

    Write-Host "[3/5] Scanning agent sharing configurations..." -ForegroundColor Cyan

    $violations     = [System.Collections.Generic.List[PSCustomObject]]::new()
    $compliantItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalAgents    = 0
    $approvedGroupCache = @{}

    foreach ($environment in $environments) {
        $envId   = $environment.EnvironmentName
        $envName = $environment.DisplayName
        $envOrgUrl = $environment.Internal.properties.linkedEnvironmentMetadata.instanceApiUrl
        $envDataverseToken = $null

        Write-Verbose "Scanning environment: $envName ($envId)"

        $zone = Get-EnvironmentZone -EnvironmentId $envId -EnvironmentDisplayName $envName
        Write-Verbose "  Zone: $zone"

        $policy = & $policyScript -Zone $zone

        if (-not $envOrgUrl) {
            Write-Verbose "  Skipping $envName — no Dataverse instance URL available"
            continue
        }

        # Load approved groups for this zone (cached)
        if (-not $approvedGroupCache.ContainsKey($zone)) {
            $approvedGroupCache[$zone] = Get-ApprovedSecurityGroups `
                -Zone $zone `
                -DvUrl $DataverseUrl `
                -DvToken $dataverseToken
        }
        $approvedGroups = $approvedGroupCache[$zone]

        if ($envOrgUrl -and $ClientId) {
            try {
                $envTokenBody = @{
                    grant_type    = 'client_credentials'
                    client_id     = $ClientId
                    client_secret = $plainSecret
                    scope         = "$($envOrgUrl.TrimEnd('/'))/.default"
                }
                $envTokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $envTokenBody -ErrorAction Stop
                $envDataverseToken = $envTokenResponse.access_token
            }
            catch {
                $errMsg = $_.Exception.Message
                Write-Warning "Could not acquire token for $envOrgUrl - skipping environment: $errMsg"
                Write-Warning "  Recording SCAN_COVERAGE_GAP so missing telemetry is not reported as compliant."
                $violations.Add([PSCustomObject]@{
                    RunId             = $runId
                    EnvironmentId     = $envId
                    EnvironmentName   = $envName
                    AgentId           = "SCAN_COVERAGE_GAP-$envId"
                    AgentName         = 'Scan coverage gap'
                    Zone              = $zone
                    SharingType       = -1
                    SharingLabel      = 'Unknown'
                    SharedGroupIds    = '[]'
                    ViolationType     = 'SCAN_COVERAGE_GAP'
                    Severity          = 'High'
                    RegulatoryContext = 'Coverage gap — scanner could not query Copilot Studio bots in this environment.'
                    DetectedAt        = $scanStartTime
                    Details           = "TokenAcquisitionFailed: $errMsg"
                })
                continue
            }
        }

        # Query bots in this environment. Per Microsoft Learn, the Copilot Studio
        # bot table exposes accesscontrolpolicy and authorizedsecuritygroupids for
        # sharing posture; the older sharingtype assumption is not current.
        try {
            $botApiUrl = "$($envOrgUrl.TrimEnd('/'))/api/data/v9.2/bots"
            $selectCols = 'botid,name,statecode,accesscontrolpolicy,authorizedsecuritygroupids,createdon'
            $botHeaders = @{
                'Authorization'    = "Bearer $envDataverseToken"
                'Accept'           = 'application/json'
                'OData-MaxVersion' = '4.0'
                'OData-Version'    = '4.0'
            }

            $bots = [System.Collections.ArrayList]::new()
            $nextUrl = "$($botApiUrl)?`$select=$selectCols&`$filter=statecode eq 0"
            while ($nextUrl) {
                $response = Invoke-RestMethod -Uri $nextUrl -Headers $botHeaders -Method Get -ErrorAction Stop
                $values = if ($response.value) { $response.value } else { @() }
                foreach ($record in $values) {
                    [void]$bots.Add($record)
                }
                $nextUrl = $response.'@odata.nextLink'
            }
        }
        catch {
            $errMsg = $_.Exception.Message
            Write-Warning "  Could not query bots in $envName`: $errMsg"
            Write-Warning "  Recording SCAN_COVERAGE_GAP so missing telemetry is not reported as compliant."
            $violations.Add([PSCustomObject]@{
                RunId             = $runId
                EnvironmentId     = $envId
                EnvironmentName   = $envName
                AgentId           = "SCAN_COVERAGE_GAP-$envId"
                AgentName         = 'Scan coverage gap'
                Zone              = $zone
                SharingType       = -1
                SharingLabel      = 'Unknown'
                SharedGroupIds    = '[]'
                ViolationType     = 'SCAN_COVERAGE_GAP'
                Severity          = 'High'
                RegulatoryContext = 'Coverage gap — scanner could not query Copilot Studio bots in this environment.'
                DetectedAt        = $scanStartTime
                Details           = "ScanFailed: $errMsg"
            })
            continue
        }

        Write-Verbose "  Found $($bots.Count) agent(s) in $envName"
        $totalAgents += $bots.Count

        foreach ($bot in $bots) {
            $agentId   = if ($bot.botid) { $bot.botid } else { 'unknown' }
            $agentName = if ($bot.name) { $bot.name } else { 'Unknown Agent' }

            $sharingClassification = Get-AgentSharingClassification -AccessControlPolicy $bot.accesscontrolpolicy
            $sharingType  = [int]$sharingClassification.SharingType
            $sharingLabel = [string]$sharingClassification.SharingLabel
            $sharedGroupIds = if ($sharingClassification.IsGroupMembership) {
                ConvertTo-AuthorizedSecurityGroupIds -AuthorizedSecurityGroupIds $bot.authorizedsecuritygroupids
            }
            else {
                @()
            }

            $violationType = Get-SharingViolationType `
                -SharingType $sharingType `
                -SharedGroupIds $sharedGroupIds `
                -Policy $policy `
                -ApprovedGroupIds $approvedGroups

            if ($violationType -eq 'Compliant') {
                if ($IncludeCompliant) {
                    $compliantItems.Add([PSCustomObject]@{
                        RunId           = $runId
                        EnvironmentId   = $envId
                        EnvironmentName = $envName
                        AgentId         = $agentId
                        AgentName       = $agentName
                        Zone            = $zone
                        SharingType     = $sharingType
                        SharingLabel    = $sharingLabel
                        SharedGroupIds  = (ConvertTo-Json -InputObject @($sharedGroupIds) -Compress)
                        Status          = 'Compliant'
                        ViolationType   = 'None'
                        Severity        = 'Informational'
                        DetectedAt      = $scanStartTime
                    })
                }
                continue
            }

            $severity = Get-ViolationSeverity -Policy $policy -ViolationType $violationType

            $violations.Add([PSCustomObject]@{
                RunId             = $runId
                EnvironmentId     = $envId
                EnvironmentName   = $envName
                AgentId           = $agentId
                AgentName         = $agentName
                Zone              = $zone
                SharingType       = $sharingType
                SharingLabel      = $sharingLabel
                SharedGroupIds    = (ConvertTo-Json -InputObject @($sharedGroupIds) -Compress)
                ViolationType     = $violationType
                Severity          = $severity
                RegulatoryContext = $policy.RegulatoryContext
                DetectedAt        = $scanStartTime
                Details           = "Agent '$agentName' has sharing '$sharingLabel' which violates $zone policy. $($policy.RegulatoryContext)"
            })
        }
    }

    Write-Host "  Scanned $totalAgents agent(s) across $($environments.Count) environment(s)"
    Write-Host "  Violations found: $($violations.Count)" -ForegroundColor $(if ($violations.Count -gt 0) { 'Yellow' } else { 'Green' })

    #endregion

    #region Persist Results to Dataverse

    Write-Host "[4/5] Persisting results..." -ForegroundColor Cyan

    if (-not $DryRun) {
        if ($DataverseUrl -and $dataverseToken -and $violations.Count -gt 0) {
            $zoneMap = @{ 'Zone1' = 1; 'Zone2' = 2; 'Zone3' = 3; 'Unknown' = 0 }
            $apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
            $dvHeaders = @{
                'Authorization'    = "Bearer $dataverseToken"
                'Content-Type'     = 'application/json'
                'OData-MaxVersion' = '4.0'
                'OData-Version'    = '4.0'
            }
            $persistedCount = 0

            foreach ($v in $violations) {
                try {
                    $record = @{
                        'fsi_complianceid'      = "ASARD-$($v.AgentName)-$runId".Substring(0, [Math]::Min(100, "ASARD-$($v.AgentName)-$runId".Length))
                        'fsi_agentid'           = $v.AgentId
                        'fsi_agentname'         = $v.AgentName
                        'fsi_environmentid'     = $v.EnvironmentId
                        'fsi_environmentname'   = $v.EnvironmentName
                        'fsi_zone'              = if ($zoneMap.ContainsKey($v.Zone)) { $zoneMap[$v.Zone] } else { 0 }
                        'fsi_sharingtype'       = $v.SharingLabel
                        'fsi_violationtype'     = $v.ViolationType
                        'fsi_severity'          = Get-SeverityCode -Severity $v.Severity
                        'fsi_compliancestatus'  = 100000001  # NonCompliant
                        'fsi_detectedat'        = $v.DetectedAt
                        'fsi_description'       = $v.Details
                        'fsi_scanrunid'         = $runId
                        'fsi_sharedgroupids'    = $v.SharedGroupIds
                        'fsi_regulatorycontext' = $v.RegulatoryContext
                    }

                    Invoke-RestMethod `
                        -Uri "$apiBase/fsi_agentsharingcompliances" `
                        -Headers $dvHeaders `
                        -Method Post `
                        -Body ($record | ConvertTo-Json -Compress) `
                        -ErrorAction Stop | Out-Null

                    $persistedCount++
                }
                catch {
                    Write-Warning "  Failed to persist record for $($v.AgentName)`: $($_.Exception.Message)"
                }
            }
            Write-Host "  Persisted $persistedCount of $($violations.Count) violation record(s)" -ForegroundColor Green
        }
        elseif (-not $DataverseUrl) {
            Write-Host "  Persistence skipped (-DataverseUrl not specified)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "  No violations to persist" -ForegroundColor Green
        }
    }
    else {
        Write-Host "[DRY RUN] Would persist scan results to Dataverse" -ForegroundColor Yellow
    }

    #endregion

    #region Output Results

    Write-Host "[5/5] Generating output..." -ForegroundColor Cyan
    Write-Host ""

    $allResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($v in $violations) { $allResults.Add($v) }
    if ($IncludeCompliant) {
        foreach ($c in $compliantItems) { $allResults.Add($c) }
    }

    # Summary
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "SCAN COMPLETE" -ForegroundColor Cyan
    Write-Host "  RunId:                $runId"
    Write-Host "  Environments scanned: $($environments.Count)"
    Write-Host "  Agents scanned:       $totalAgents"
    Write-Host "  Violations detected:  $($violations.Count)" -ForegroundColor $(if ($violations.Count -gt 0) { 'Yellow' } else { 'Green' })

    $criticalCount = ($violations | Where-Object { $_.Severity -eq 'Critical' }).Count
    $highCount     = ($violations | Where-Object { $_.Severity -eq 'High' }).Count
    if ($criticalCount -gt 0) { Write-Host "  Critical:             $criticalCount" -ForegroundColor Red }
    if ($highCount -gt 0)     { Write-Host "  High:                 $highCount" -ForegroundColor Yellow }
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""

    switch ($OutputFormat) {
        'JSON' {
            return ($allResults | ConvertTo-Json -Depth 5)
        }
        'Object' {
            return $allResults.ToArray()
        }
        default {
            if ($allResults.Count -gt 0) {
                $allResults | Format-Table -Property EnvironmentName, AgentName, Zone, ViolationType, Severity, SharingLabel -AutoSize
            }
            else {
                Write-Host "No results to display." -ForegroundColor Green
            }
        }
    }

    #endregion
}
