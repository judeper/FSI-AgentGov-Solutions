<#
.SYNOPSIS
    Validates agent sharing configuration for all Copilot Studio agents against
    zone-specific governance requirements.

.DESCRIPTION
    Orchestrates a full agent sharing compliance scan:
    1. Enumerates Power Platform environments
    2. Queries each environment's Dataverse for Copilot Studio agents (bot table)
    3. Evaluates each agent's sharing configuration against zone-based policy
    4. Detects: public sharing, org-wide access, policy violations
    5. Reports violations with severity classification and regulatory context
    6. Optionally remediates by restricting sharing to compliant levels

    This is the primary validation script for the Unrestricted Agent Sharing
    Detector (UASD) solution. It validates per-agent sharing posture against
    zone-based governance policies defined by Controls 1.1 and 3.8.

    Note: External sharing (cross-tenant) detection requires role assignment
    data not available from the Dataverse bot table; use Invoke-SharingAudit.ps1
    for cross-tenant detection.

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
    When specified, restricts sharing for agents with violations to
    zone-compliant levels. Applies remediation via Power Apps Admin cmdlets.
    Use -WhatIf to preview remediation actions before applying.

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
    Version: 1.0.2
    Solution: Unrestricted Agent Sharing Detector (UASD)
    Controls: 1.1 (Agent Access Governance), 3.8 (Copilot Hub)
    Regulations: FINRA Rule 4511, SEC 17a-4, SOX 302/404, GLBA 501(b)

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

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

    Write-Verbose "========================================="
    Write-Verbose "Unrestricted Agent Sharing Detector v1.0.2"
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

    function Get-SharingScopeType {
        <#
        .SYNOPSIS
            Classifies a bot sharing configuration into a violation type.
        .OUTPUTS
            String: UnrestrictedSharing, OrgWideAccess, ExternalSharing,
                    SharingPolicyViolation, or Compliant
        #>
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Agent,

            [Parameter(Mandatory)]
            [PSCustomObject]$Policy
        )

        $sharingScope     = $Agent.SharingScope
        $isPublic         = $Agent.IsPublic
        $allowExternal    = $Agent.AllowExternalUsers
        $sharingStatus    = if ($Agent.SharingStatus) { $Agent.SharingStatus.ToLower() } else { '' }

        # Public sharing — accessible to anyone with the link
        if ($isPublic -eq $true -or $sharingStatus -match 'public') {
            return 'UnrestrictedSharing'
        }

        # External sharing — accessible to users outside the tenant
        if ($allowExternal -eq $true -or $sharingStatus -match 'external') {
            return 'ExternalSharing'
        }

        # Org-wide access — visible to all users in the tenant
        if ($sharingStatus -match 'orgwide|org-wide|everyone|allusers' -or
            $sharingScope -match 'orgwide|organization') {
            return 'OrgWideAccess'
        }

        # Check against zone permitted scopes
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
            'UnrestrictedSharing'    { return 100000001 }
            'OrgWideAccess'          { return 100000000 }
            'ExternalSharing'        { return 100000004 }
            'SharingPolicyViolation' { return 100000005 }
            default {
                Write-Warning "Unknown violation type '$ViolationType' — defaulting to EXCESSIVE_INDIVIDUAL (100000003). Add a mapping for this type."
                return 100000003
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
            'Informational' { return 100000003 }
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

        # Try shared zone classification script if available
        $sharedZoneScript = Join-Path (Split-Path (Split-Path $scriptRoot -Parent) -Parent | Join-Path -ChildPath '..') 'scripts\shared\Get-ZoneClassification.ps1'

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
    Write-Host "Unrestricted Agent Sharing Detector v1.0.2" -ForegroundColor Cyan
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
        $zone = Get-EnvironmentZone `
            -EnvironmentId $envId `
            -EnvironmentDisplayName $envName `
            -DataverseUrl $DataverseUrl `
            -AccessToken $DataverseToken

        Write-Verbose "  Zone: $zone"

        # Get zone policy
        $policy = & $policyScript -Zone $zone

        # Query Copilot Studio bots in this environment via Dataverse
        if (-not $envOrgUrl) {
            Write-Verbose "  Skipping $envName — no Dataverse instance URL available"
            continue
        }

        try {
            $botApiUrl = "$($envOrgUrl.TrimEnd('/'))/api/data/v9.2/bots"
            $selectCols = 'botid,name,statecode,statuscode,publishedby,' +
                          'sharingtype,allowedchannels,isunlicensed,createdon'

            $headers = @{
                'Authorization' = "Bearer $DataverseToken"
                'Accept'        = 'application/json'
                'OData-MaxVersion' = '4.0'
                'OData-Version'    = '4.0'
            }

            $queryParams = "`$select=$selectCols&`$filter=statecode eq 0"
            $response = Invoke-RestMethod `
                -Uri "$($botApiUrl)?$queryParams" `
                -Headers $headers `
                -Method Get `
                -ErrorAction Stop

            $bots = $response.value
        } catch {
            Write-Warning "  Could not query bots in $envName`: $($_.Exception.Message)"
            Write-Warning "  Ensure the service principal has Dataverse read access on the bot table."
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

            # Build agent sharing object from bot properties
            # sharingtype: 0=private/specific, 1=org-wide, 2=public
            $sharingTypeMap = @{ 0 = 'SpecificUsers'; 1 = 'OrgWide'; 2 = 'Public' }
            $sharingScope   = $sharingTypeMap[$bot.sharingtype] ?? 'Unknown'
            $isPublic       = ($bot.sharingtype -eq 2)
            $isOrgWide      = ($bot.sharingtype -eq 1)

            $agentObj = [PSCustomObject]@{
                AgentId          = $agentId
                AgentName        = $agentName
                SharingScope     = $sharingScope
                IsPublic         = $isPublic
                AllowExternalUsers = $false  # Determined by tenant DLP; not a bot property
                SharingStatus    = $sharingScope
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
                Details            = "Agent '$agentName' has sharing configuration '$sharingScope' which violates $zone policy. $($policy.RegulatoryContext)"
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
            $targetAction = "Restrict sharing for agent '$($violation.AgentName)' in '$($violation.EnvironmentName)' (current: $($violation.SharingScope))"

            if ($PSCmdlet.ShouldProcess($targetAction, 'RestrictSharing')) {
                try {
                    # Restrict sharing via Power Apps Admin API
                    # Set sharingtype back to 0 (SpecificUsers) to remove unrestricted access
                    $envOrgUrl = ($environments | Where-Object { $_.EnvironmentName -eq $violation.EnvironmentId } |
                        Select-Object -First 1).Internal.properties.linkedEnvironmentMetadata.instanceApiUrl

                    if ($envOrgUrl -and $DataverseToken) {
                        $patchUrl = "$($envOrgUrl.TrimEnd('/'))/api/data/v9.2/bots($($violation.AgentId))"
                        $patchBody = @{ sharingtype = 0 } | ConvertTo-Json
                        $headers = @{
                            'Authorization'    = "Bearer $DataverseToken"
                            'Content-Type'     = 'application/json'
                            'OData-MaxVersion' = '4.0'
                            'OData-Version'    = '4.0'
                        }
                        Invoke-RestMethod -Uri $patchUrl -Headers $headers -Method Patch -Body $patchBody -ErrorAction Stop

                        $violation.RemediatedAt      = Get-Date -Format 'o'
                        $violation.RemediationAction = "Sharing restricted to SpecificUsers (sharingtype=0)"
                        Write-Host "    Remediated: $($violation.AgentName) ($($violation.EnvironmentName))" -ForegroundColor Green
                    } else {
                        Write-Warning "    Cannot remediate $($violation.AgentName) — missing Dataverse URL or token"
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

    if ($PersistResults -and $DataverseUrl -and $DataverseToken) {
        foreach ($violation in $violations) {
            if ($PSCmdlet.ShouldProcess("fsi_sharingviolations", "CreateViolationRecord")) {
                try {
                    # Dedup: check for existing Open violation with same agent + violation type
                    $violationTypeCode = Get-ViolationTypeCode -ViolationType $violation.ViolationType
                    $dedupFilter = "fsi_agentid eq '$($violation.AgentId)' and fsi_violationtype eq $violationTypeCode and fsi_violationstatus eq 100000000"
                    $dedupUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_sharingviolations?`$filter=$dedupFilter&`$top=1&`$select=fsi_sharingviolationid"
                    $dedupHeaders = @{
                        'Authorization'    = "Bearer $DataverseToken"
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
                        'fsi_violationstatus'    = 100000000  # Open
                        'fsi_severity'           = Get-SeverityCode -Severity $violation.Severity
                        'fsi_detectedat'         = $violation.DetectedAt
                        'fsi_description'        = $violation.Details
                        'fsi_evidencejson'       = $evidencePayload
                        'fsi_scanrunid'          = $runId
                    }

                    if ($violation.RemediatedAt) {
                        $record['fsi_remediatedat']        = $violation.RemediatedAt
                        $record['fsi_remediationresult'] = $violation.RemediationAction
                    }

                    $recordJson = $record | ConvertTo-Json -Compress
                    $headers = @{
                        'Authorization'    = "Bearer $DataverseToken"
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
        Write-Warning "  PersistResults requires -DataverseUrl and -DataverseToken"
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
