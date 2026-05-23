<#
.SYNOPSIS
    Validates agent sharing configuration for all Copilot Studio agents against
    zone-specific governance requirements.

.DESCRIPTION
    Orchestrates a full agent sharing compliance scan:
    1. Enumerates Power Platform environments
    2. Queries each environment's Dataverse for Copilot Studio agents (bot table)
    3. Evaluates each agent's sharing configuration against zone-based policy
    4. Detects unauthenticated public access, org-wide access, cross-tenant
       access, unapproved groups, and policy violations
    5. Reports violations with severity classification and regulatory context
    6. Optionally remediates by restricting sharing to approved security groups
       with rollback evidence captured before changes are applied

    This is the primary validation script for the Unrestricted Agent Sharing
    Detector (UASD) solution. It validates per-agent sharing posture against
    zone-based governance policies defined by Controls 1.1 and 3.8.

    Note: Excessive individual share counts require agent sharing APIs that
    expose per-principal assignments. The Dataverse bot table covers
    accesscontrolpolicy, authenticationmode, and authorizedsecuritygroupids.

    Zone-based severity:
    - Zone 3: Critical for any unrestricted/org-wide/external sharing
    - Zone 2: High for public/external, Medium for org-wide
    - Zone 1: Advisory (Low) for all sharing violations

.PARAMETER WhatIf
    Preview mode — shows what violations would be reported without persisting
    to Dataverse or triggering alerts or remediation. Always safe to run.

.PARAMETER OutputFormat
    Output format: Table (default), Json, or Object.
    - Table: Formatted table with color-coded severity
    - Json: Machine-readable JSON for evidence export pipeline
    - Object: Raw PSCustomObject[] for pipeline consumption

.PARAMETER IncludeEnvironments
    Limit scan to specific environment IDs.

.PARAMETER ExcludeEnvironments
    Exclude specific environment IDs from scan.

.PARAMETER ExcludeSandbox
    Exclude sandbox environments from scan.

.PARAMETER ExcludeTrial
    Exclude trial environments from scan.

.PARAMETER ExcludeDefault
    Exclude the default environment from scan.

.PARAMETER IncludeCompliant
    Include compliant agents in output (default: violations only).

.PARAMETER DataverseUrl
    ELM Dataverse URL for zone classification lookup. When provided with
    -PersistResults, also writes scan results to fsi_sharingviolations.

.PARAMETER DataverseToken
    Pre-obtained access token for Dataverse authentication.

.PARAMETER PersistResults
    When specified with -DataverseUrl, writes each violation to
    fsi_sharingviolations in Dataverse for evidence and dashboard reporting.

.PARAMETER AutoRemediate
    When specified, restricts sharing for agents with violations to approved
    security groups by patching the Dataverse bot table. The script captures
    the previous accesscontrolpolicy and authorizedsecuritygroupids in evidence
    before changes are applied. Use -WhatIf to preview remediation actions.

.PARAMETER Top
    Limit total agents processed (safety cap for large tenants).
    Default 0 means no limit.

.EXAMPLE
    . ./Test-AgentSharingCompliance.ps1
    Test-AgentSharingCompliance -WhatIf

    Dry-run scan of all environments — violations only, no Dataverse write.

.EXAMPLE
    . ./Test-AgentSharingCompliance.ps1
    Test-AgentSharingCompliance -IncludeEnvironments @("env-id-1") -OutputFormat Json

    Scan specific environments with JSON output for evidence pipeline.

.EXAMPLE
    . ./Test-AgentSharingCompliance.ps1
    Test-AgentSharingCompliance `
      -DataverseUrl "https://yourorg.crm.dynamics.com" `
      -DataverseToken $token `
      -PersistResults `
      -AutoRemediate

    Full scan with Dataverse persistence and auto-remediation enabled.

.OUTPUTS
    Formatted table (default), JSON string, or PSCustomObject[] depending on -OutputFormat.
    Summary statistics are always written to the host output stream.

.NOTES
    File: Test-AgentSharingCompliance.ps1
    Version: 2.0.1
    Solution: Unrestricted Agent Sharing Detector (UASD)
    Controls: 1.1 (Agent Access Governance), 3.8 (Copilot Hub)
    Regulations: FINRA Rule 4511(a), SEC Rule 17a-4, SOX Section 302/404, GLBA Section 501(b)

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell, Az.Accounts

function Test-AgentSharingCompliance {
    <#
    .SYNOPSIS
        Validates agent sharing configuration for all Copilot Studio agents
        against zone-specific governance requirements.

    .DESCRIPTION
        Orchestrates a full agent sharing compliance scan across Power Platform
        environments. For each agent, evaluates sharing configuration against
        zone-specific policies and reports violations with appropriate severity.
        Supports optional auto-remediation and Dataverse evidence persistence.

    .OUTPUTS
        Formatted table (default), JSON string, or PSCustomObject[] depending on -OutputFormat.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [ValidateSet('Table', 'Json', 'Object')]
        [string]$OutputFormat = 'Table',

        [Parameter()]
        [string[]]$IncludeEnvironments,

        [Parameter()]
        [string[]]$ExcludeEnvironments,

        [Parameter()]
        [switch]$ExcludeSandbox,

        [Parameter()]
        [switch]$ExcludeTrial,

        [Parameter()]
        [switch]$ExcludeDefault,

        [Parameter()]
        [switch]$IncludeCompliant,

        [Parameter()]
        [string]$DataverseUrl,

        [Parameter()]
        [string]$DataverseToken,

        [Parameter()]
        [switch]$PersistResults,

        [Parameter()]
        [switch]$AutoRemediate,

        [Parameter()]
        [int]$Top = 0
    )

    #region Script Initialization

    $ErrorActionPreference = 'Stop'
    $scriptRoot = $PSScriptRoot
    $runId = [guid]::NewGuid().ToString()
    $scanStartTime = Get-Date -Format 'o'

    # --- Auth helpers (managed identity / Az context first, explicit token fallback) ---
    $script:UasdTokenCache = @{}

    function Convert-UasdAccessTokenToPlainText {
        param([Parameter(Mandatory)]$Token)
        if ($Token -is [System.Security.SecureString]) {
            return ($Token | ConvertFrom-SecureString -AsPlainText)
        }
        return [string]$Token
    }

    function Get-UasdAccessToken {
        <#
        .SYNOPSIS
            Gets an access token for a Dataverse resource URL.
        .DESCRIPTION
            Uses the explicitly supplied -DataverseToken when present. Otherwise,
            uses Get-AzAccessToken so Azure Automation managed identities,
            user-assigned managed identities, workload identities, and interactive
            Az sessions can all acquire resource-scoped Dataverse tokens.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$ResourceUrl
        )

        if (-not [string]::IsNullOrWhiteSpace($DataverseToken)) {
            return $DataverseToken
        }

        $normalizedResourceUrl = $ResourceUrl.TrimEnd('/')
        if ($script:UasdTokenCache.ContainsKey($normalizedResourceUrl)) {
            return $script:UasdTokenCache[$normalizedResourceUrl]
        }

        try {
            $tokenResult = Get-AzAccessToken -ResourceUrl $normalizedResourceUrl -ErrorAction Stop
            $token = Convert-UasdAccessTokenToPlainText -Token $tokenResult.Token
            if ([string]::IsNullOrWhiteSpace($token)) {
                throw "Get-AzAccessToken returned an empty token"
            }
            $script:UasdTokenCache[$normalizedResourceUrl] = $token
            return $token
        } catch {
            throw "Failed to acquire Dataverse token for '$normalizedResourceUrl': $($_.Exception.Message). In Azure Automation, enable a managed identity and grant it the required Dataverse security role; for admin workstations, run Connect-AzAccount or pass -DataverseToken explicitly."
        }
    }

    Write-Verbose "========================================="
    Write-Verbose "Unrestricted Agent Sharing Detector v2.0.1"
    Write-Verbose "RunId: $runId"
    Write-Verbose "ScanStart: $scanStartTime"
    Write-Verbose "========================================="

    #endregion

    #region Import Companion Scripts

    $policyScript = Join-Path $scriptRoot 'Get-ExpectedSharingPolicy.ps1'

    if (-not (Test-Path $policyScript)) {
        throw "Required script not found: $policyScript"
    }

    #endregion

    #region Sharing Scope Classification Helpers
    # COUPLING NOTE: Get-SharingScopeType and Get-ViolationTypeCode are tightly coupled.
    # Get-SharingScopeType returns violation type strings that Get-ViolationTypeCode maps to
    # Dataverse option set integers. When adding a new violation type, update BOTH functions.

    function Get-SharingScopeType {
        <#
        .SYNOPSIS
            Classifies a bot sharing configuration into a violation type.
        .OUTPUTS
            String: UnrestrictedSharing, OrgWideAccess, ExternalSharing,
                    UnapprovedGroup, SharingPolicyViolation, or Compliant
        #>
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Agent,

            [Parameter(Mandatory)]
            [PSCustomObject]$Policy
        )

        $sharingScope       = $Agent.SharingScope
        $accessPolicy       = $Agent.AccessControlPolicy
        $authenticationMode = $Agent.AuthenticationMode
        $sharingStatus      = if ($Agent.SharingStatus) { $Agent.SharingStatus.ToLower() } else { '' }

        # Copilot Studio authenticationmode=1 (None) means anyone with the link can chat.
        if ($authenticationMode -eq 1 -or $sharingStatus -match 'unauthenticated|public') {
            return 'UnrestrictedSharing'
        }

        # accesscontrolpolicy=3 is Any (multi-tenant), which permits cross-tenant access.
        if ($accessPolicy -eq 3 -or $sharingStatus -match 'external|multitenant|multi-tenant') {
            return 'ExternalSharing'
        }

        # accesscontrolpolicy=0 is Any, meaning all users in the tenant can interact with the bot.
        if ($accessPolicy -eq 0 -or $sharingStatus -match 'orgwide|org-wide|everyone|allusers' -or
            $sharingScope -match 'orgwide|organization|anyuser') {
            return 'OrgWideAccess'
        }

        # accesscontrolpolicy=2 is Group membership; validate against the approved registry when available.
        if ($accessPolicy -eq 2) {
            $authorizedGroupIds = @($Agent.AuthorizedSecurityGroupIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $approvedGroupIds = @($Agent.ApprovedSecurityGroupIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

            if ($approvedGroupIds.Count -eq 0 -and -not $Policy.AdvisoryOnly) {
                return 'SharingPolicyViolation'
            }

            if ($authorizedGroupIds.Count -eq 0 -and -not $Policy.AdvisoryOnly) {
                return 'SharingPolicyViolation'
            }

            if ($approvedGroupIds.Count -gt 0) {
                $unapprovedGroups = @($authorizedGroupIds | Where-Object { $_.ToLowerInvariant() -notin $approvedGroupIds })
                if ($unapprovedGroups.Count -gt 0 -and -not $Policy.AdvisoryOnly) {
                    return 'UnapprovedGroup'
                }
            }
        }

        # Check against zone permitted scopes.
        if ($sharingScope -and
            $Policy.PermittedScopes -notcontains $sharingScope -and
            -not $Policy.AdvisoryOnly) {
            return 'SharingPolicyViolation'
        }

        return 'Compliant'
    }

    function Get-ViolationSeverity {
        <#
        .SYNOPSIS
            Returns violation severity based on zone policy and violation type.
        .OUTPUTS
            String: Critical, High, Medium, Low
        #>
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Policy,

            [Parameter(Mandatory)]
            [string]$ViolationType
        )

        switch ($ViolationType) {
            'UnrestrictedSharing'    { return $Policy.UnrestrictedSharingSeverity }
            'OrgWideAccess'          { return $Policy.OrgWideAccessSeverity }
            'ExternalSharing'        { return $Policy.ExternalSharingSeverity }
            'UnapprovedGroup'        { return $Policy.UnapprovedGroupSeverity }
            'SharingPolicyViolation' { return $Policy.SharingPolicyViolationSeverity }
            default                  { return 'Informational' }
        }
    }

    function Get-ViolationTypeCode {
        <#
        .SYNOPSIS
            Maps violation type string to Dataverse option set integer value.
        .OUTPUTS
            Integer matching fsi_UASD_violationtype option set
        #>
        param([string]$ViolationType)

        switch ($ViolationType) {
            'OrgWideAccess'          { return 100000000 }
            'UnrestrictedSharing'    { return 100000001 }
            'UnapprovedGroup'        { return 100000002 }
            'ExternalSharing'        { return 100000004 }
            'SharingPolicyViolation' { return 100000005 }
            default {
                Write-Warning "Unknown violation type '$ViolationType' — defaulting to POLICY_VIOLATION (100000005). Update Get-ViolationTypeCode and Get-SharingScopeType in parallel when adding new types."
                return 100000005
            }
        }
    }

    function Get-SeverityCode {
        <#
        .SYNOPSIS
            Maps severity string to Dataverse option set integer value.
        .OUTPUTS
            Integer matching fsi_UASD_severity option set
        #>
        param([string]$Severity)

        switch ($Severity) {
            'Critical'      { return 100000000 }
            'High'          { return 100000001 }
            'Medium'        { return 100000002 }
            'Low'           { return 100000003 }
            'Informational' { return $null }   # Not persisted; suppress
            default         { return 100000003 }
        }
    }

    function Get-ZoneCode {
        <#
        .SYNOPSIS
            Maps zone string to Dataverse option set integer value.
        .OUTPUTS
            Integer matching fsi_UASD_zoneclassification option set
        #>
        param([string]$Zone)

        switch ($Zone) {
            'Zone1' { return 100000000 }
            'Zone2' { return 100000001 }
            'Zone3' { return 100000002 }
            default { return 100000000 }  # Default to Zone1 for unknown
        }
    }

    function Get-ApprovedSecurityGroupIds {
        <#
        .SYNOPSIS
            Retrieves active approved security groups for a UASD zone.
        .OUTPUTS
            Lowercase Entra group IDs approved for the zone.
        #>
        param(
            [string]$DataverseUrl,
            [string]$AccessToken,
            [int]$ZoneCode
        )

        if ([string]::IsNullOrWhiteSpace($DataverseUrl) -or [string]::IsNullOrWhiteSpace($AccessToken)) {
            return @()
        }

        $headers = @{
            'Authorization'    = "Bearer $AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }
        $apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
        $filter = "fsi_isactive eq true and fsi_zoneclassification eq $ZoneCode"
        $url = "$apiBase/fsi_approvedsecuritygroups?`$select=fsi_entraidgroupid&`$filter=$filter"
        $approved = [System.Collections.Generic.List[string]]::new()

        while ($url) {
            $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
            foreach ($record in $response.value) {
                if (-not [string]::IsNullOrWhiteSpace($record.fsi_entraidgroupid)) {
                    $approved.Add($record.fsi_entraidgroupid.Trim().ToLowerInvariant())
                }
            }
            $url = $response.'@odata.nextLink'
        }

        return $approved.ToArray()
    }

    #endregion

    #region Zone Classification Helper

    function Get-EnvironmentZone {
        <#
        .SYNOPSIS
            Determines governance zone for an environment.
        .OUTPUTS
            String: Zone1, Zone2, Zone3, or Unknown
        #>
        param(
            [string]$EnvironmentId,
            [string]$EnvironmentDisplayName,
            [string]$DataverseUrl,
            [string]$AccessToken
        )

        # Try shared zone classification script if available.
        # $scriptRoot = ...\unrestricted-agent-sharing-detector\scripts\governance
        # repo root  = parent of the solution directory.
        $solutionRoot = Split-Path (Split-Path $scriptRoot -Parent) -Parent
        $repoRoot = Split-Path $solutionRoot -Parent
        $sharedZoneScript = Join-Path $repoRoot 'scripts\shared\Get-ZoneClassification.ps1'

        if (Test-Path $sharedZoneScript) {
            try {
                $zone = & $sharedZoneScript `
                    -EnvironmentId $EnvironmentId `
                    -EnvironmentDisplayName $EnvironmentDisplayName `
                    -DataverseUrl $DataverseUrl `
                    -AccessToken $AccessToken
                if ($zone) { return $zone }
            } catch {
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

    #region Display Scan Configuration

    Write-Verbose "Scan configuration:"
    Write-Verbose "  OutputFormat:       $OutputFormat"
    Write-Verbose "  ExcludeSandbox:     $($ExcludeSandbox.IsPresent)"
    Write-Verbose "  ExcludeTrial:       $($ExcludeTrial.IsPresent)"
    Write-Verbose "  ExcludeDefault:     $($ExcludeDefault.IsPresent)"
    Write-Verbose "  IncludeCompliant:   $($IncludeCompliant.IsPresent)"
    Write-Verbose "  AutoRemediate:      $($AutoRemediate.IsPresent)"
    Write-Verbose "  PersistResults:     $($PersistResults.IsPresent)"
    Write-Verbose "  Top:                $(if ($Top -gt 0) { $Top } else { 'No limit' })"
    Write-Verbose "  WhatIf:             $WhatIfPreference"
    if ($DataverseUrl) { Write-Verbose "  DataverseUrl:       $DataverseUrl" }

    #endregion

    #region Enumerate Environments

    Write-Host ""
    Write-Host "Unrestricted Agent Sharing Detector v2.0.1" -ForegroundColor Cyan
    Write-Host "RunId: $runId" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[1/4] Enumerating Power Platform environments..." -ForegroundColor Cyan

    try {
        $allEnvironments = Get-AdminPowerAppEnvironment -ErrorAction Stop
    } catch {
        throw "Failed to enumerate environments. Verify Microsoft.PowerApps.Administration.PowerShell is installed and authenticated: $($_.Exception.Message)"
    }

    # Apply environment filters
    $environments = $allEnvironments | Where-Object {
        $env = $_
        $include = $true

        if ($IncludeEnvironments -and $env.EnvironmentName -notin $IncludeEnvironments) {
            $include = $false
        }
        if ($ExcludeEnvironments -and $env.EnvironmentName -in $ExcludeEnvironments) {
            $include = $false
        }
        if ($ExcludeSandbox -and $env.EnvironmentType -eq 'Sandbox') {
            $include = $false
        }
        if ($ExcludeTrial -and $env.EnvironmentType -eq 'Trial') {
            $include = $false
        }
        if ($ExcludeDefault -and $env.IsDefault) {
            $include = $false
        }

        $include
    }

    Write-Host "  Found $($environments.Count) environment(s) to scan (of $($allEnvironments.Count) total)"

    #endregion

    #region Scan Agents Across Environments

    Write-Host "[2/4] Scanning agent sharing configurations..." -ForegroundColor Cyan

    $violations     = [System.Collections.Generic.List[PSCustomObject]]::new()
    $compliantItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalAgents    = 0
    $agentCount     = 0

    foreach ($environment in $environments) {
        $envId      = $environment.EnvironmentName
        $envName    = $environment.DisplayName
        $envOrgUrl  = $environment.Internal.properties.linkedEnvironmentMetadata.instanceApiUrl

        Write-Verbose "Scanning environment: $envName ($envId)"

        # Determine zone classification
        $zoneLookupToken = $null
        if ($DataverseUrl) {
            try {
                $zoneLookupToken = Get-UasdAccessToken -ResourceUrl $DataverseUrl
            } catch {
                Write-Verbose "Could not acquire token for zone lookup Dataverse URL: $($_.Exception.Message)"
            }
        }

        $zone = Get-EnvironmentZone `
            -EnvironmentId $envId `
            -EnvironmentDisplayName $envName `
            -DataverseUrl $DataverseUrl `
            -AccessToken $zoneLookupToken

        Write-Verbose "  Zone: $zone"

        # Get zone policy and approved security groups for the zone.
        $policy = & $policyScript -Zone $zone
        $approvedGroupIds = @()
        if ($DataverseUrl -and $zoneLookupToken) {
            try {
                $approvedGroupIds = @(Get-ApprovedSecurityGroupIds `
                    -DataverseUrl $DataverseUrl `
                    -AccessToken $zoneLookupToken `
                    -ZoneCode (Get-ZoneCode -Zone $zone))
                Write-Verbose "  Approved groups for $($zone): $($approvedGroupIds.Count)"
            } catch {
                Write-Warning "  Could not load approved security groups for $($zone): $($_.Exception.Message)"
            }
        }

        # Query Copilot Studio bots in this environment via Dataverse
        if (-not $envOrgUrl) {
            Write-Verbose "  Skipping $envName — no Dataverse instance URL available"
            continue
        }

        try {
            $botApiUrl = "$($envOrgUrl.TrimEnd('/'))/api/data/v9.2/bots"
            # Per Microsoft Learn (https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/bot)
            # the bot table exposes accesscontrolpolicy (0=Any, 1=Copilot readers,
            # 2=Group membership, 3=Any multi-tenant), authorizedsecuritygroupids,
            # authenticationmode (1=None), and authenticationtrigger.
            $envAccessToken = Get-UasdAccessToken -ResourceUrl $envOrgUrl
            $selectCols = 'botid,name,statecode,statuscode,publishedby,' +
                          'accesscontrolpolicy,authorizedsecuritygroupids,' +
                          'authenticationmode,authenticationtrigger,createdon'

            $headers = @{
                'Authorization' = "Bearer $envAccessToken"
                'Accept'        = 'application/json'
                'OData-MaxVersion' = '4.0'
                'OData-Version'    = '4.0'
            }

            $queryParams = "`$select=$selectCols&`$filter=statecode eq 0"
            $bots = [System.Collections.ArrayList]::new()
            $nextUrl = "$($botApiUrl)?$queryParams"
            while ($nextUrl) {
                $response = Invoke-RestMethod `
                    -Uri $nextUrl `
                    -Headers $headers `
                    -Method Get `
                    -ErrorAction Stop
                foreach ($record in $response.value) {
                    [void]$bots.Add($record)
                }
                $nextUrl = $response.'@odata.nextLink'
            }
        } catch {
            $errMsg = $_.Exception.Message
            Write-Warning "  Could not query bots in $envName`: $errMsg"
            Write-Warning "  Ensure the service principal has Dataverse read access on the bot table."
            # Emit a SCAN_COVERAGE_GAP sentinel violation so coverage gaps surface
            # instead of silently producing a clean report (mirrors Invoke-SharingAudit.ps1).
            $coverageViolation = [PSCustomObject]@{
                RunId              = $runId
                EnvironmentId      = $envId
                EnvironmentName    = $envName
                AgentId            = $envId
                AgentName          = 'SCAN_COVERAGE_GAP'
                SharingScope       = 'Unknown'
                Zone               = $zone
                ViolationType      = 'SCAN_COVERAGE_GAP'  # Local sentinel; not in fsi_UASD_violationtype
                Severity           = 'High'
                RegulatoryContext  = 'Coverage gap — scanner could not query bots in this environment.'
                DetectedAt         = $scanStartTime
                RemediatedAt       = $null
                RemediationAction  = $null
                Details            = "ScanFailed: $errMsg"
            }
            $violations.Add($coverageViolation)
            continue
        }

        Write-Verbose "  Found $($bots.Count) agent(s) in $envName"
        $totalAgents += $bots.Count

        foreach ($bot in $bots) {
            $agentCount++

            if ($Top -gt 0 -and $agentCount -gt $Top) {
                Write-Verbose "Top limit ($Top) reached — stopping scan"
                break
            }

            $agentId   = $bot.botid
            $agentName = $bot.name

            # Build agent sharing object from bot properties.
            # accesscontrolpolicy: 0=Any (all users in tenant), 1=Copilot readers
            # (specific licensed users), 2=Group membership (authorizedsecuritygroupids),
            # 3=Any (multi-tenant / cross-tenant). authenticationmode=1 means no
            # user authentication, so anyone with the link can chat.
            $accessPolicyMap = @{
                0 = 'AnyUser'
                1 = 'CopilotReaders'
                2 = 'GroupMembership'
                3 = 'AnyMultiTenant'
            }
            $accessPolicy = if ($null -ne $bot.accesscontrolpolicy) { [int]$bot.accesscontrolpolicy } else { $null }
            $authenticationMode = if ($null -ne $bot.authenticationmode) { [int]$bot.authenticationmode } else { $null }
            $authenticationTrigger = if ($null -ne $bot.authenticationtrigger) { [int]$bot.authenticationtrigger } else { $null }
            $sharingScope = if ($null -ne $accessPolicy -and $accessPolicyMap.ContainsKey($accessPolicy)) {
                $accessPolicyMap[$accessPolicy]
            } else { 'Unknown' }
            $authorizedGroupIds = @()
            if (-not [string]::IsNullOrWhiteSpace($bot.authorizedsecuritygroupids)) {
                $authorizedGroupIds = @($bot.authorizedsecuritygroupids -split ',' |
                    ForEach-Object { $_.Trim().ToLowerInvariant() } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
            $isPublic      = ($authenticationMode -eq 1)
            $isCrossTenant = ($accessPolicy -eq 3)
            $previousSharingConfig = [ordered]@{
                accesscontrolpolicy       = $accessPolicy
                authorizedsecuritygroupids = $bot.authorizedsecuritygroupids
                authenticationmode        = $authenticationMode
                authenticationtrigger     = $authenticationTrigger
            }

            $agentObj = [PSCustomObject]@{
                AgentId                   = $agentId
                AgentName                 = $agentName
                SharingScope              = $sharingScope
                AccessControlPolicy       = $accessPolicy
                AuthenticationMode        = $authenticationMode
                AuthenticationTrigger     = $authenticationTrigger
                AuthorizedSecurityGroupIds = $authorizedGroupIds
                ApprovedSecurityGroupIds  = $approvedGroupIds
                PreviousSharingConfig     = $previousSharingConfig
                IsPublic                  = $isPublic
                AllowExternalUsers        = $isCrossTenant
                SharingStatus             = $sharingScope
            }

            # Classify sharing type
            $violationType = Get-SharingScopeType -Agent $agentObj -Policy $policy

            if ($violationType -eq 'Compliant') {
                if ($IncludeCompliant) {
                    $compliantItems.Add([PSCustomObject]@{
                        EnvironmentId   = $envId
                        EnvironmentName = $envName
                        AgentId         = $agentId
                        AgentName       = $agentName
                        SharingScope    = $sharingScope
                        Zone            = $zone
                        Status          = 'Compliant'
                        ViolationType   = 'None'
                        Severity        = 'Informational'
                    })
                }
                continue
            }

            $severity = Get-ViolationSeverity -Policy $policy -ViolationType $violationType

            $violation = [PSCustomObject]@{
                RunId              = $runId
                EnvironmentId      = $envId
                EnvironmentName    = $envName
                AgentId            = $agentId
                AgentName          = $agentName
                SharingScope       = $sharingScope
                Zone               = $zone
                ViolationType      = $violationType
                Severity           = $severity
                RegulatoryContext  = $policy.RegulatoryContext
                DetectedAt         = $scanStartTime
                RemediatedAt       = $null
                RemediationAction  = $null
                AccessControlPolicy       = $accessPolicy
                AuthenticationMode        = $authenticationMode
                AuthenticationTrigger     = $authenticationTrigger
                AuthorizedSecurityGroupIds = $authorizedGroupIds
                ApprovedSecurityGroupIds  = $approvedGroupIds
                PreviousSharingConfig     = $previousSharingConfig
                Details            = "Agent '$agentName' has sharing configuration '$sharingScope' (accesscontrolpolicy=$accessPolicy, authenticationmode=$authenticationMode) which violates $zone policy. $($policy.RegulatoryContext)"
            }

            $violations.Add($violation)
        }
    }

    Write-Host "  Scanned $totalAgents agent(s) across $($environments.Count) environment(s)"
    Write-Host "  Violations found: $($violations.Count)" -ForegroundColor $(if ($violations.Count -gt 0) { 'Yellow' } else { 'Green' })

    #endregion

    #region Auto-Remediation

    Write-Host "[3/4] Remediation..." -ForegroundColor Cyan

    if ($AutoRemediate -and $violations.Count -gt 0) {
        foreach ($violation in $violations) {
            if ([string]::IsNullOrWhiteSpace($violation.AgentId) -or $violation.ViolationType -eq 'SCAN_COVERAGE_GAP') {
                Write-Verbose "Skipping remediation for non-agent violation '$($violation.ViolationType)' in '$($violation.EnvironmentName)'"
                continue
            }

            $targetAction = "Restrict sharing for agent '$($violation.AgentName)' in '$($violation.EnvironmentName)' (current: $($violation.SharingScope))"

            if ($PSCmdlet.ShouldProcess($targetAction, 'RestrictSharing')) {
                try {
                    # Set sharing to Group membership (accesscontrolpolicy=2) using approved groups.
                    $envOrgUrl = ($environments | Where-Object { $_.EnvironmentName -eq $violation.EnvironmentId } |
                        Select-Object -First 1).Internal.properties.linkedEnvironmentMetadata.instanceApiUrl
                    $approvedGroupsForAgent = @($violation.ApprovedSecurityGroupIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

                    if ($approvedGroupsForAgent.Count -eq 0) {
                        $violation.RemediationAction = "Skipped: no approved security groups configured for $($violation.Zone). Previous sharing config retained in evidencejson."
                        Write-Warning "    Skipping remediation for $($violation.AgentName) — no approved groups configured for $($violation.Zone)"
                        continue
                    }

                    if ($envOrgUrl) {
                        $remediationToken = Get-UasdAccessToken -ResourceUrl $envOrgUrl
                        $patchUrl = "$($envOrgUrl.TrimEnd('/'))/api/data/v9.2/bots($($violation.AgentId))"
                        $approvedGroupCsv = ($approvedGroupsForAgent | Select-Object -First 20) -join ','
                        $patchBody = @{
                            accesscontrolpolicy       = 2
                            authorizedsecuritygroupids = $approvedGroupCsv
                        } | ConvertTo-Json
                        $headers = @{
                            'Authorization'    = "Bearer $remediationToken"
                            'Content-Type'     = 'application/json'
                            'OData-MaxVersion' = '4.0'
                            'OData-Version'    = '4.0'
                            'If-Match'         = '*'
                        }
                        Invoke-RestMethod -Uri $patchUrl -Headers $headers -Method Patch -Body $patchBody -ErrorAction Stop

                        $violation.RemediatedAt      = Get-Date -Format 'o'
                        $violation.RemediationAction = "Sharing restricted to Group membership (accesscontrolpolicy=2) with approved groups: $approvedGroupCsv. Previous sharing config retained in evidencejson for rollback."
                        Write-Host "    Remediated: $($violation.AgentName) ($($violation.EnvironmentName))" -ForegroundColor Green
                    } else {
                        Write-Warning "    Cannot remediate $($violation.AgentName) — missing environment Dataverse URL"
                    }
                } catch {
                    Write-Warning "    Remediation failed for $($violation.AgentName)`: $($_.Exception.Message)"
                }
            }
        }
    } elseif (-not $AutoRemediate) {
        Write-Host "  Auto-remediation not enabled (-AutoRemediate not specified)" -ForegroundColor DarkGray
    } else {
        Write-Host "  No violations to remediate" -ForegroundColor Green
    }

    #endregion

    #region Persist Results to Dataverse

    Write-Host "[4/4] Persisting results..." -ForegroundColor Cyan

    if ($PersistResults -and $DataverseUrl) {
        try {
            $persistToken = Get-UasdAccessToken -ResourceUrl $DataverseUrl
        } catch {
            throw "PersistResults requested but no Dataverse token could be acquired for '$DataverseUrl': $($_.Exception.Message)"
        }

        foreach ($violation in $violations) {
            if ($PSCmdlet.ShouldProcess("fsi_sharingviolations", "CreateViolationRecord")) {
                try {
                    # Dedup: check for existing Open violation with same agent + violation type
                    $violationTypeCode = Get-ViolationTypeCode -ViolationType $violation.ViolationType
                    $dedupFilter = "fsi_agentid eq '$($violation.AgentId)' and fsi_violationtype eq $violationTypeCode and fsi_violationstatus eq 100000000"
                    $dedupUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_sharingviolations?`$filter=$dedupFilter&`$top=1&`$select=fsi_sharingviolationid"
                    $dedupHeaders = @{
                        'Authorization'    = "Bearer $persistToken"
                        'OData-MaxVersion' = '4.0'
                        'OData-Version'    = '4.0'
                    }
                    $existing = Invoke-RestMethod -Uri $dedupUrl -Headers $dedupHeaders -Method Get -ErrorAction Stop
                    if ($existing.value -and $existing.value.Count -gt 0) {
                        Write-Verbose "  Skipped duplicate violation for $($violation.AgentName) ($($violation.ViolationType)) — existing Open record found"
                        continue
                    }

                    $evidencePayload = $violation | ConvertTo-Json -Depth 5 -Compress

                    $record = @{
                        'fsi_name'               = "UASD-$($violation.AgentName)-$runId".Substring(0, [Math]::Min(100, "UASD-$($violation.AgentName)-$runId".Length))
                        'fsi_agentid'            = $violation.AgentId
                        'fsi_agentname'          = $violation.AgentName
                        'fsi_environmentid'      = $violation.EnvironmentId
                        'fsi_environmentname'    = $violation.EnvironmentName
                        'fsi_violationtype'      = Get-ViolationTypeCode -ViolationType $violation.ViolationType
                        'fsi_violationstatus'    = if ($violation.RemediatedAt) { 100000001 } else { 100000000 }
                        'fsi_severity'           = Get-SeverityCode -Severity $violation.Severity
                        'fsi_detectedat'         = $violation.DetectedAt
                        'fsi_description'        = $violation.Details
                        'fsi_evidencejson'       = $evidencePayload
                        'fsi_scanrunid'          = $runId
                    }

                    if ($violation.RemediatedAt) {
                        $record['fsi_remediatedat'] = $violation.RemediatedAt
                    }
                    if ($violation.RemediationAction) {
                        $record['fsi_remediationresult'] = $violation.RemediationAction
                    }

                    $recordJson = $record | ConvertTo-Json -Compress
                    $headers = @{
                        'Authorization'    = "Bearer $persistToken"
                        'Content-Type'     = 'application/json'
                        'OData-MaxVersion' = '4.0'
                        'OData-Version'    = '4.0'
                    }
                    $createUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_sharingviolations"
                    Invoke-RestMethod -Uri $createUrl -Headers $headers -Method Post -Body $recordJson -ErrorAction Stop
                    Write-Verbose "  Persisted violation record for: $($violation.AgentName)"
                } catch {
                    Write-Warning "  Failed to persist record for $($violation.AgentName)`: $($_.Exception.Message)"
                }
            }
        }
        Write-Host "  Persisted $($violations.Count) violation record(s) to fsi_sharingviolations"
    } elseif ($PersistResults) {
        Write-Warning "  PersistResults requires -DataverseUrl"
    } else {
        Write-Host "  Persistence skipped (-PersistResults not specified)" -ForegroundColor DarkGray
    }

    #endregion

    #region Summary

    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "SCAN COMPLETE" -ForegroundColor Cyan
    Write-Host "  Environments scanned: $($environments.Count)"
    Write-Host "  Agents scanned:       $totalAgents"
    Write-Host "  Violations detected:  $($violations.Count)" -ForegroundColor $(if ($violations.Count -gt 0) { 'Yellow' } else { 'Green' })

    $criticalCount = ($violations | Where-Object { $_.Severity -eq 'Critical' }).Count
    $highCount     = ($violations | Where-Object { $_.Severity -eq 'High' }).Count
    $mediumCount   = ($violations | Where-Object { $_.Severity -eq 'Medium' }).Count

    if ($criticalCount -gt 0) { Write-Host "  Critical: $criticalCount" -ForegroundColor Red }
    if ($highCount -gt 0)     { Write-Host "  High: $highCount" -ForegroundColor DarkYellow }
    if ($mediumCount -gt 0)   { Write-Host "  Medium: $mediumCount" -ForegroundColor Yellow }

    $remediatedCount = ($violations | Where-Object { $null -ne $_.RemediatedAt }).Count
    if ($AutoRemediate -and $remediatedCount -gt 0) {
        Write-Host "  Remediated: $remediatedCount" -ForegroundColor Green
    }

    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""

    #endregion

    #region Output

    $allResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    $allResults.AddRange($violations)
    if ($IncludeCompliant) { $allResults.AddRange($compliantItems) }

    switch ($OutputFormat) {
        'Json' {
            $summary = [PSCustomObject]@{
                RunId              = $runId
                ScanTimestamp      = $scanStartTime
                EnvironmentsScanned = $environments.Count
                TotalAgents        = $totalAgents
                TotalViolations    = $violations.Count
                CriticalCount      = $criticalCount
                HighCount          = $highCount
                MediumCount        = $mediumCount
                RemediatedCount    = $remediatedCount
                Violations         = $violations
            }
            return $summary | ConvertTo-Json -Depth 10
        }
        'Object' {
            return $allResults.ToArray()
        }
        default {
            # Table output with color-coded severity
            if ($violations.Count -eq 0) {
                Write-Host "No violations found." -ForegroundColor Green
                return
            }

            $violations | Sort-Object @{e={switch ($_.Severity) { 'Critical' {0} 'High' {1} 'Medium' {2} 'Low' {3} default {4} }}}, EnvironmentName, AgentName |
            Format-Table -AutoSize -Property @(
                @{Label='Agent'; Expression={$_.AgentName}; Width=35},
                @{Label='Environment'; Expression={$_.EnvironmentName}; Width=30},
                @{Label='Zone'; Expression={$_.Zone}; Width=8},
                @{Label='Violation'; Expression={$_.ViolationType}; Width=22},
                @{Label='Sharing'; Expression={$_.SharingScope}; Width=15},
                @{
                    Label='Severity'
                    Expression={
                        $sev = $_.Severity
                        $color = switch ($sev) {
                            'Critical' { 'Red' }
                            'High'     { 'DarkYellow' }
                            'Medium'   { 'Yellow' }
                            default    { 'White' }
                        }
                        $sev
                    }
                    Width=10
                },
                @{Label='Remediated'; Expression={if ($_.RemediatedAt) { 'Yes' } else { 'No' }}; Width=10}
            )
        }
    }

    #endregion
}
