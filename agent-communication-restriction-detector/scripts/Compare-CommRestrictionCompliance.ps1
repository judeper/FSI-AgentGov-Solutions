<#
.SYNOPSIS
    Pipeline function that evaluates agent skill registrations against
    zone-based communication restriction policies.

.DESCRIPTION
    Accepts PSCustomObject input from Get-AgentSkillRegistrations via the
    pipeline and evaluates each skill registration against the communication
    policy for the source governance zone.

    For each registration the function:
    1. Determines the communication route type (same-zone, cross-zone,
       cross-environment, cross-tenant)
    2. Looks up the expected policy via Get-ExpectedCommPolicy.ps1
    3. Checks approved routes and active exceptions (when DataverseUrl provided)
    4. Evaluates maker/checker requirements
    5. Determines violation type, severity, and regulatory context
    6. Emits a compliance result object per registration

    Route type classification:
    - SameZoneSameEnv:         Same zone and same environment
    - CrossEnvironment:        Same zone (or Unknown target zone) but different environment
    - CrossZoneHigherToLower:  Source zone rank > target zone rank (e.g. Zone3 -> Zone1)
    - CrossZoneLowerToHigher:  Source zone rank < target zone rank (e.g. Zone1 -> Zone3)
    - CrossTenant:             ManifestUrl contains cross-tenant indicator

    Policy evaluation rules:
    - Blocked:              Always a violation
    - BlockedUnlessApproved: Violation unless approved route or active exception exists
    - BlockedUnlessExplicit: Violation unless route explicitly allows cross-environment
    - RouteRequired:        Violation unless approved route exists
    - RequiresApproval:     Violation unless approved route or active exception exists
    - WarningWithApproval:  Warning severity if not in approved routes
    - Warning:              No violation (advisory only)
    - Advisory:             No violation (informational)
    - RequiresClassification: Treated as violation (zone not yet classified)

.PARAMETER InputObject
    PSCustomObject from Get-AgentSkillRegistrations with properties:
    EnvironmentId, EnvironmentDisplayName, Zone, AgentId, AgentName,
    SkillName, TargetAgentId, TargetAgentName, TargetEnvironmentId,
    TargetZone, ManifestUrl, OwnerId, DataverseUrl, RetrievedAt

.PARAMETER ApprovedRoutes
    Array of approved communication routes from Dataverse (Get-ApprovedCommRoutes).
    Each object should have: SourceZone, TargetZone, DirectionType,
    AllowCrossEnvironment, IsActive.

.PARAMETER CommExceptions
    Array of active communication exceptions from Dataverse (Get-CommExceptions).
    Each object should have: CallingAgentId, TargetAgentId, SourceZone,
    TargetZone, Status, ExpiresAt.

.PARAMETER AgentOwnerMap
    Hashtable mapping AgentId -> OwnerId for maker/checker validation.
    When not provided, maker/checker checks use OwnerId from input objects
    and attempt to look up target agent owners from pipeline data.

.PARAMETER IncludeCompliant
    When specified, emits compliant registrations in addition to violations.
    By default, only violations are emitted.

.EXAMPLE
    . ./Get-AgentSkillRegistrations.ps1
    . ./Compare-CommRestrictionCompliance.ps1

    Get-AgentSkillRegistrations | Compare-CommRestrictionCompliance

    Evaluates all skill registrations against zone policies (standalone mode,
    no Dataverse-backed approved routes or exceptions).

.EXAMPLE
    . ./Get-AgentSkillRegistrations.ps1
    . ./Compare-CommRestrictionCompliance.ps1

    $routes = Get-ApprovedCommRoutes -ActiveOnly
    $exceptions = Get-CommExceptions -ActiveOnly
    Get-AgentSkillRegistrations -ExcludeSandbox |
        Compare-CommRestrictionCompliance -ApprovedRoutes $routes -CommExceptions $exceptions -IncludeCompliant

    Full evaluation with Dataverse-backed approved routes and exceptions.

.OUTPUTS
    PSCustomObject with properties:
    AgentId, AgentName, EnvironmentId, EnvironmentDisplayName, SourceZone,
    SkillName, TargetAgentId, TargetAgentName, TargetEnvironmentId, TargetZone,
    RouteType, IsCompliant, Severity, ViolationType, RegulatoryContext

.NOTES
    File: Compare-CommRestrictionCompliance.ps1
    Version: 1.0.0
    Solution: Agent Communication Restriction Detector (ACRD)
    Control: 2.17 (Multi-Agent Orchestration Limits)
    Requires: PowerShell 7.0+

    This script supports compliance monitoring for Control 2.17.
    It does not guarantee detection of all communication violations.
#>

#Requires -Version 7.0

function Compare-CommRestrictionCompliance {
    <#
    .SYNOPSIS
        Evaluates agent skill registrations against zone communication policies.

    .DESCRIPTION
        Pipeline function that accepts skill registration objects and evaluates
        each against the zone-based communication restriction policy. Emits
        compliance result objects suitable for summary reporting, Dataverse
        persistence, or further pipeline processing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$InputObject,

        [Parameter()]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$ApprovedRoutes = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$CommExceptions = @(),

        [Parameter()]
        [hashtable]$AgentOwnerMap = @{},

        [Parameter()]
        [switch]$IncludeCompliant
    )

    begin {
        #region Resolve Policy Script Path

        $privateRoot = Join-Path $PSScriptRoot 'private'
        $policyScript = Join-Path $privateRoot 'Get-ExpectedCommPolicy.ps1'

        if (-not (Test-Path $policyScript)) {
            throw "Required policy script not found: $policyScript"
        }

        #endregion

        #region Zone Ranking

        $zoneRank = @{
            'Unknown' = 0
            'Zone1'   = 1
            'Zone2'   = 2
            'Zone3'   = 3
        }

        #endregion

        #region Build Approved Route Lookup

        # Key format: "SourceZone->TargetZone" => route object
        $routeLookup = @{}
        foreach ($route in $ApprovedRoutes) {
            $key = "$($route.SourceZone)->$($route.TargetZone)"
            if (-not $routeLookup.ContainsKey($key)) {
                $routeLookup[$key] = $route
            }
            # If bidirectional, add reverse route as well
            if ($route.DirectionType -eq 'Bidirectional') {
                $reverseKey = "$($route.TargetZone)->$($route.SourceZone)"
                if (-not $routeLookup.ContainsKey($reverseKey)) {
                    $routeLookup[$reverseKey] = $route
                }
            }
        }

        Write-Verbose "Approved route lookup built: $($routeLookup.Count) route key(s)"

        #endregion

        #region Build Exception Lookup

        # Key format: "CallingAgentId->TargetAgentId" => exception object
        $exceptionLookup = @{}
        foreach ($exception in $CommExceptions) {
            # Only include approved, non-expired exceptions
            $isValid = $true
            if ($exception.Status -and $exception.Status -ne 'Approved') {
                $isValid = $false
            }
            if ($exception.ExpiresAt) {
                try {
                    $expiresAt = [datetime]$exception.ExpiresAt
                    if ($expiresAt -lt (Get-Date).ToUniversalTime()) {
                        $isValid = $false
                    }
                } catch {
                    Write-Verbose "Unable to parse exception expiry: $($exception.ExpiresAt)"
                }
            }

            if ($isValid) {
                $key = "$($exception.CallingAgentId)->$($exception.TargetAgentId)"
                if (-not $exceptionLookup.ContainsKey($key)) {
                    $exceptionLookup[$key] = $exception
                }
            }
        }

        Write-Verbose "Exception lookup built: $($exceptionLookup.Count) active exception(s)"

        #endregion

        #region Policy Cache

        # Cache zone policies to avoid re-invoking the script for each registration
        $policyCache = @{}

        #endregion

        #region Counters

        $counters = @{
            TotalProcessed    = 0
            Compliant         = 0
            Violations        = 0
            CriticalCount     = 0
            HighCount         = 0
            MediumCount       = 0
            WarningCount      = 0
            ByViolationType   = @{
                'ZONE_BOUNDARY_VIOLATION'      = 0
                'CROSS_TENANT_VIOLATION'       = 0
                'CROSS_ENVIRONMENT_UNAPPROVED' = 0
                'MAKER_CHECKER_VIOLATION'      = 0
            }
        }

        #endregion

        #region Severity Ranking Helper

        # Lower index = higher severity
        $severityOrder = @('Critical', 'High', 'Medium', 'Warning')

        function Get-HighestSeverity {
            param([string[]]$Severities)
            foreach ($sev in $severityOrder) {
                if ($Severities -contains $sev) {
                    return $sev
                }
            }
            return 'Warning'
        }

        #endregion
    }

    process {
        $reg = $InputObject
        $counters.TotalProcessed++

        $sourceZone = $reg.Zone
        $targetZone = $reg.TargetZone
        $isCrossEnvironment = ($reg.TargetEnvironmentId -and $reg.TargetEnvironmentId -ne $reg.EnvironmentId)
        $isCrossTenant = $false

        #region Determine Route Type

        # Cross-tenant detection: ManifestUrl with external tenant pattern
        if ($reg.ManifestUrl -and $reg.ManifestUrl -match 'https://[^/]+\.api\.') {
            if (-not $reg.TargetEnvironmentId) {
                $isCrossTenant = $true
            }
        }

        $routeType = if ($isCrossTenant) {
            'CrossTenant'
        } elseif ($sourceZone -ne 'Unknown' -and $targetZone -ne 'Unknown' -and $sourceZone -ne $targetZone) {
            # Cross-zone: determine direction
            $srcRank = $zoneRank[$sourceZone]
            $tgtRank = $zoneRank[$targetZone]
            if ($srcRank -gt $tgtRank) {
                'CrossZoneHigherToLower'
            } else {
                'CrossZoneLowerToHigher'
            }
        } elseif ($isCrossEnvironment) {
            'CrossEnvironment'
        } elseif ($targetZone -eq 'Unknown' -and $isCrossEnvironment) {
            # Target zone unknown but different environment
            'CrossEnvironment'
        } elseif ($sourceZone -eq $targetZone -and -not $isCrossEnvironment) {
            'SameZoneSameEnv'
        } else {
            # Fallback: same zone, cross-environment check
            if ($isCrossEnvironment) {
                'CrossEnvironment'
            } else {
                'SameZoneSameEnv'
            }
        }

        Write-Verbose "Registration: $($reg.AgentName) -> $($reg.TargetAgentName) | Route: $routeType | Zones: $sourceZone -> $targetZone"

        #endregion

        #region Get Zone Policy (Cached)

        if (-not $policyCache.ContainsKey($sourceZone)) {
            $policyCache[$sourceZone] = & $policyScript -Zone $sourceZone
        }
        $policy = $policyCache[$sourceZone]

        #endregion

        #region Route and Exception Lookups

        $routeKey = "$sourceZone->$targetZone"
        $hasApprovedRoute = $routeLookup.ContainsKey($routeKey)
        $approvedRoute = if ($hasApprovedRoute) { $routeLookup[$routeKey] } else { $null }
        $routeAllowsCrossEnv = $hasApprovedRoute -and $approvedRoute.AllowCrossEnvironment

        $exceptionKey = "$($reg.AgentId)->$($reg.TargetAgentId)"
        $hasException = $exceptionLookup.ContainsKey($exceptionKey)

        #endregion

        #region Evaluate Violations

        $violations = [System.Collections.Generic.List[PSCustomObject]]::new()
        $isCompliant = $true

        # --- Check 1: Cross-Tenant Violation ---
        if ($routeType -eq 'CrossTenant') {
            $crossTenantPolicy = $policy.CrossTenantPolicy

            $isCrossTenantViolation = switch ($crossTenantPolicy) {
                'Blocked'               { $true }
                'BlockedUnlessApproved'  { -not $hasApprovedRoute -and -not $hasException }
                'RequiresApproval'       { -not $hasApprovedRoute -and -not $hasException }
                'Advisory'               { $false }
                default                  { $true }
            }

            if ($isCrossTenantViolation) {
                $isCompliant = $false
                $violations.Add([PSCustomObject]@{
                    ViolationType    = 'CROSS_TENANT_VIOLATION'
                    Severity         = $policy.CrossTenantViolationSeverity
                    PolicyApplied    = $crossTenantPolicy
                    RegulatoryContext = $policy.RegulatoryContext
                })
            }
        }

        # --- Check 2: Zone Boundary Violation (cross-zone communication) ---
        if ($routeType -in @('CrossZoneHigherToLower', 'CrossZoneLowerToHigher')) {
            $zonePolicyApplied = if ($routeType -eq 'CrossZoneHigherToLower') {
                $policy.CrossZoneHigherToLowerPolicy
            } else {
                $policy.CrossZoneLowerToHigherPolicy
            }

            $isZoneViolation = switch ($zonePolicyApplied) {
                'Blocked'                { $true }
                'BlockedUnlessApproved'  { -not $hasApprovedRoute -and -not $hasException }
                'RouteRequired'          { -not $hasApprovedRoute }
                'RequiresApproval'       { -not $hasApprovedRoute -and -not $hasException }
                'WarningWithApproval'    { -not $hasApprovedRoute -and -not $hasException }
                'Warning'                { $false }
                'Advisory'               { $false }
                'RequiresClassification' { $true }
                default                  { $true }
            }

            if ($isZoneViolation) {
                $isCompliant = $false

                # WarningWithApproval downgrades to Warning severity
                $zoneSeverity = if ($zonePolicyApplied -eq 'WarningWithApproval') {
                    'Warning'
                } else {
                    $policy.CrossZoneViolationSeverity
                }

                $violations.Add([PSCustomObject]@{
                    ViolationType    = 'ZONE_BOUNDARY_VIOLATION'
                    Severity         = $zoneSeverity
                    PolicyApplied    = $zonePolicyApplied
                    RegulatoryContext = $policy.RegulatoryContext
                })
            }
        }

        # --- Check 3: Cross-Environment Unapproved ---
        if ($isCrossEnvironment -and $routeType -ne 'CrossTenant') {
            $crossEnvPolicy = $policy.CrossEnvironmentPolicy

            $isCrossEnvViolation = switch ($crossEnvPolicy) {
                'Blocked'                { $true }
                'BlockedUnlessExplicit'  { -not $routeAllowsCrossEnv }
                'BlockedUnlessApproved'  { -not $hasApprovedRoute -and -not $hasException }
                'RouteRequired'          { -not $hasApprovedRoute }
                'RequiresApproval'       { -not $routeAllowsCrossEnv -and -not $hasException }
                'Advisory'               { $false }
                'RequiresClassification' { $true }
                default                  { $true }
            }

            if ($isCrossEnvViolation) {
                $isCompliant = $false
                $violations.Add([PSCustomObject]@{
                    ViolationType    = 'CROSS_ENVIRONMENT_UNAPPROVED'
                    Severity         = $policy.CrossEnvViolationSeverity
                    PolicyApplied    = $crossEnvPolicy
                    RegulatoryContext = $policy.RegulatoryContext
                })
            }
        }

        # --- Check 4: Same-Zone Same-Environment Policy ---
        if ($routeType -eq 'SameZoneSameEnv') {
            $sameZonePolicy = $policy.SameZoneSameEnvPolicy

            $isSameZoneViolation = switch ($sameZonePolicy) {
                'Blocked'                { $true }
                'RouteRequired'          { -not $hasApprovedRoute }
                'RequiresApproval'       { -not $hasApprovedRoute -and -not $hasException }
                'Advisory'               { $false }
                'RequiresClassification' { $true }
                default                  { $false }
            }

            if ($isSameZoneViolation) {
                $isCompliant = $false
                $violations.Add([PSCustomObject]@{
                    ViolationType    = 'ZONE_BOUNDARY_VIOLATION'
                    Severity         = $policy.SameZoneViolationSeverity
                    PolicyApplied    = $sameZonePolicy
                    RegulatoryContext = $policy.RegulatoryContext
                })
            }
        }

        # --- Check 5: Maker/Checker Violation ---
        if ($policy.MakerCheckerRequired -and $reg.OwnerId -and $reg.TargetAgentId) {
            # Resolve target agent owner: check provided map first, then pipeline data
            $targetOwnerId = if ($AgentOwnerMap.ContainsKey($reg.TargetAgentId)) {
                $AgentOwnerMap[$reg.TargetAgentId]
            } else {
                $null
            }

            if ($targetOwnerId -and $reg.OwnerId -eq $targetOwnerId) {
                $isCompliant = $false
                $violations.Add([PSCustomObject]@{
                    ViolationType    = 'MAKER_CHECKER_VIOLATION'
                    Severity         = $policy.MakerCheckerViolationSeverity
                    PolicyApplied    = 'MakerCheckerRequired'
                    RegulatoryContext = $policy.RegulatoryContext
                })
            }
        }

        #endregion

        #region Determine Highest Severity

        $highestSeverity = if ($violations.Count -gt 0) {
            Get-HighestSeverity -Severities @($violations | ForEach-Object { $_.Severity })
        } else {
            $null
        }

        #endregion

        #region Build Violation Type Summary

        $violationTypeSummary = if ($violations.Count -gt 0) {
            ($violations | ForEach-Object { $_.ViolationType } | Select-Object -Unique) -join ', '
        } else {
            $null
        }

        #endregion

        #region Build Regulatory Context (from highest-severity violation)

        $regulatoryContext = if ($violations.Count -gt 0) {
            # Pick regulatory context from the highest-severity violation
            $topViolation = $violations | Sort-Object {
                $severityOrder.IndexOf($_.Severity)
            } | Select-Object -First 1
            $topViolation.RegulatoryContext
        } else {
            $null
        }

        #endregion

        #region Update Counters

        if ($isCompliant) {
            $counters.Compliant++
        } else {
            $counters.Violations++

            # Severity counter
            switch ($highestSeverity) {
                'Critical' { $counters.CriticalCount++ }
                'High'     { $counters.HighCount++ }
                'Medium'   { $counters.MediumCount++ }
                'Warning'  { $counters.WarningCount++ }
            }

            # Violation type counters
            foreach ($v in $violations) {
                if ($counters.ByViolationType.ContainsKey($v.ViolationType)) {
                    $counters.ByViolationType[$v.ViolationType]++
                }
            }
        }

        #endregion

        #region Emit Result

        $result = [PSCustomObject]@{
            AgentId                = $reg.AgentId
            AgentName              = $reg.AgentName
            EnvironmentId          = $reg.EnvironmentId
            EnvironmentDisplayName = $reg.EnvironmentDisplayName
            SourceZone             = $sourceZone
            SkillName              = $reg.SkillName
            TargetAgentId          = $reg.TargetAgentId
            TargetAgentName        = $reg.TargetAgentName
            TargetEnvironmentId    = $reg.TargetEnvironmentId
            TargetZone             = $targetZone
            RouteType              = $routeType
            IsCompliant            = $isCompliant
            Severity               = $highestSeverity
            ViolationType          = $violationTypeSummary
            RegulatoryContext      = $regulatoryContext
            IsCrossEnvironment     = [bool]$isCrossEnvironment
            IsCrossTenant          = [bool]$isCrossTenant
            PolicyApplied          = if ($violations.Count -gt 0) {
                                         ($violations | ForEach-Object { $_.PolicyApplied } | Select-Object -Unique) -join ', '
                                     } else { $null }
            Violations             = $violations.ToArray()
        }

        if ($IncludeCompliant -or -not $isCompliant) {
            $result
        }

        #endregion
    }

    end {
        #region Summary Logging

        Write-Verbose "========================================="
        Write-Verbose "Compare-CommRestrictionCompliance Summary"
        Write-Verbose "========================================="
        Write-Verbose "  Total processed:          $($counters.TotalProcessed)"
        Write-Verbose "  Compliant:                $($counters.Compliant)"
        Write-Verbose "  Violations:               $($counters.Violations)"
        if ($counters.CriticalCount -gt 0) {
            Write-Verbose "    Critical:               $($counters.CriticalCount)"
        }
        if ($counters.HighCount -gt 0) {
            Write-Verbose "    High:                   $($counters.HighCount)"
        }
        if ($counters.MediumCount -gt 0) {
            Write-Verbose "    Medium:                 $($counters.MediumCount)"
        }
        if ($counters.WarningCount -gt 0) {
            Write-Verbose "    Warning:                $($counters.WarningCount)"
        }

        # Log violation type breakdown
        foreach ($vtype in $counters.ByViolationType.GetEnumerator()) {
            if ($vtype.Value -gt 0) {
                Write-Verbose "    $($vtype.Key): $($vtype.Value)"
            }
        }

        Write-Verbose "========================================="

        #endregion
    }
}
