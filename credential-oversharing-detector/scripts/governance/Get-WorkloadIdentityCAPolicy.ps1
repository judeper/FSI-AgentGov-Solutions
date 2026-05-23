<#
.SYNOPSIS
    Detects workload identity Conditional Access policy coverage for
    agent service principals and managed identities.

.DESCRIPTION
    Checks that workload identities (managed identities and service principals)
    used by Copilot Studio agents have appropriate Conditional Access policies
    applied. Evaluates location-based restrictions, risk-based blocking, and
    workload identity-specific CA policy coverage.

    Detection logic:
    1. Enumerates service principals tagged as agent workload identities
    2. Queries Conditional Access policies scoped to workload identities
       (servicePrincipal conditions)
    3. Cross-references to identify unprotected workload identities
    4. Flags workload identities without location or risk-based restrictions

    Reference: https://learn.microsoft.com/entra/identity/conditional-access/workload-identity

.PARAMETER TenantId
    Microsoft Entra ID tenant ID.

.PARAMETER OutputFormat
    Output format: Table (default), Json, or Object.

.PARAMETER AgentServicePrincipalTag
    Tag to filter agent-related service principals (default: 'CopilotStudioAgent').

.NOTES
    File: Get-WorkloadIdentityCAPolicy.ps1
    Version: 2.1.0
    Solution: Credential Oversharing Detector (COD)
    Controls: 1.14, 1.4, 1.18
    Requires: Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Applications

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Applications

function Get-WorkloadIdentityCAPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [ValidateSet('Table', 'Json', 'Object')]
        [string]$OutputFormat = 'Table',

        [string]$AgentServicePrincipalTag = 'CopilotStudioAgent'
    )

    begin {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "Analyzing workload identity CA policies for tenant $TenantId..."
    }

    process {
        # ---------------------------------------------------------------
        # Step 1: Retrieve CA policies targeting workload identities
        # ---------------------------------------------------------------
        $allPolicies = Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop
        $workloadPolicies = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($policy in $allPolicies) {
            $conditions = $policy.Conditions
            $hasWorkloadTarget = $false

            # Check for service principal conditions
            if ($null -ne $conditions.ClientApplications) {
                $clientApps = $conditions.ClientApplications
                if (($clientApps.IncludeServicePrincipals | Measure-Object).Count -gt 0 -or
                    $clientApps.ServicePrincipalFilter.Mode -eq 'include') {
                    $hasWorkloadTarget = $true
                }
            }

            if ($hasWorkloadTarget) {
                $hasLocationCondition = $null -ne $conditions.Locations -and
                    ($conditions.Locations.IncludeLocations | Measure-Object).Count -gt 0
                $hasRiskCondition = ($conditions.SignInRiskLevels | Measure-Object).Count -gt 0 -or
                    ($conditions.ServicePrincipalRiskLevels | Measure-Object).Count -gt 0

                $workloadPolicies.Add([PSCustomObject]@{
                    PolicyId               = $policy.Id
                    PolicyName             = $policy.DisplayName
                    State                  = $policy.State
                    HasLocationRestriction = $hasLocationCondition
                    HasRiskBasedBlocking   = $hasRiskCondition
                    IncludedSPs            = $conditions.ClientApplications.IncludeServicePrincipals -join ', '
                    SPFilter               = $conditions.ClientApplications.ServicePrincipalFilter.Rule
                    GrantControls          = ($policy.GrantControls.BuiltInControls -join ', ')
                })
            }
        }

        Write-Verbose "Found $($workloadPolicies.Count) workload identity CA policies."

        # ---------------------------------------------------------------
        # Step 2: Enumerate agent service principals
        # ---------------------------------------------------------------
        $agentSPs = Get-MgServicePrincipal -Filter "tags/any(t:t eq '$AgentServicePrincipalTag')" -All -ErrorAction SilentlyContinue
        if (-not $agentSPs) {
            # Fallback: list all app registrations with 'agent' in display name
            $agentSPs = Get-MgServicePrincipal -Filter "startsWith(displayName,'Copilot')" -All -ErrorAction SilentlyContinue
        }
        Write-Verbose "Found $(@($agentSPs).Count) agent service principal(s)."

        # ---------------------------------------------------------------
        # Step 3: Cross-reference coverage
        # ---------------------------------------------------------------
        $coverageResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        $coveredSPIds = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($pol in $workloadPolicies) {
            foreach ($spId in ($pol.IncludedSPs -split ',\s*')) {
                if ($spId -and $spId -ne 'All') {
                    [void]$coveredSPIds.Add($spId.Trim())
                }
            }
            # If 'All' is included, all SPs are covered
            if ($pol.IncludedSPs -match '\bAll\b') {
                foreach ($sp in $agentSPs) {
                    [void]$coveredSPIds.Add($sp.Id)
                }
            }
        }

        foreach ($sp in $agentSPs) {
            $isCovered = $coveredSPIds.Contains($sp.Id)
            $applicablePolicies = $workloadPolicies | Where-Object {
                $_.IncludedSPs -match '\bAll\b' -or $_.IncludedSPs -match $sp.Id
            }

            $hasLocation = ($applicablePolicies | Where-Object HasLocationRestriction).Count -gt 0
            $hasRisk = ($applicablePolicies | Where-Object HasRiskBasedBlocking).Count -gt 0

            $riskLevel = if (-not $isCovered) { 'Critical' }
                         elseif (-not $hasLocation -and -not $hasRisk) { 'High' }
                         elseif (-not $hasLocation -or -not $hasRisk) { 'Medium' }
                         else { 'Low' }

            $coverageResults.Add([PSCustomObject]@{
                ServicePrincipalId   = $sp.Id
                DisplayName          = $sp.DisplayName
                AppId                = $sp.AppId
                ServicePrincipalType = $sp.ServicePrincipalType
                CAPolicyCovered      = $isCovered
                LocationRestricted   = $hasLocation
                RiskBasedBlocking    = $hasRisk
                ApplicablePolicies   = ($applicablePolicies.PolicyName -join '; ')
                RiskLevel            = $riskLevel
                Recommendation       = switch ($riskLevel) {
                    'Critical' { 'No workload identity CA policy covers this service principal - create a CA policy with location and risk conditions' }
                    'High'     { 'CA policy exists but lacks both location and risk conditions - add location-based or risk-based restrictions' }
                    'Medium'   { 'Partial coverage - add missing location or risk-based condition for defense in depth' }
                    'Low'      { 'Adequate workload identity CA coverage' }
                }
            })
        }

        # ---------------------------------------------------------------
        # Step 4: Output
        # ---------------------------------------------------------------
        $uncovered = ($coverageResults | Where-Object { -not $_.CAPolicyCovered }).Count

        switch ($OutputFormat) {
            'Json' {
                @{
                    Timestamp           = (Get-Date -Format 'o')
                    TenantId            = $TenantId
                    WorkloadPolicies    = $workloadPolicies
                    AgentSPCount        = @($agentSPs).Count
                    CoverageResults     = $coverageResults
                    UncoveredCount      = $uncovered
                    Reference           = 'https://learn.microsoft.com/entra/identity/conditional-access/workload-identity'
                } | ConvertTo-Json -Depth 10
            }
            'Object' {
                $coverageResults
            }
            default {
                Write-Host "`nWorkload Identity CA Policy Coverage:" -ForegroundColor Cyan
                Write-Host ("=" * 60) -ForegroundColor Cyan
                Write-Host "  Workload CA Policies:    $($workloadPolicies.Count)"
                Write-Host "  Agent Service Principals: $(@($agentSPs).Count)"
                Write-Host "  Uncovered:               $uncovered" -ForegroundColor $(if ($uncovered -gt 0) { 'Red' } else { 'Green' })
                Write-Host ""
                $coverageResults | Format-Table -Property DisplayName, CAPolicyCovered, LocationRestricted, RiskBasedBlocking, RiskLevel -AutoSize
            }
        }
    }
}
