<#
.SYNOPSIS
    Tracks Continuous Access Evaluation (CAE) configuration for AI agent sessions.

.DESCRIPTION
    Reads tenant CAE configuration via Microsoft Graph, identifies which
    Conditional Access policies have CAE enabled or disabled, tracks which
    agent sessions are CAE-eligible, and documents the CAE rollout posture
    for AI agents.

    CAE enables near-real-time policy enforcement by allowing resource providers
    to subscribe to Entra ID critical events (user revocation, IP change,
    policy change) rather than relying solely on token lifetime expiration.

    This script:
    1. Retrieves all Conditional Access policies via Graph
    2. Filters for CAE-relevant session controls (persistentBrowser, signInFrequency)
    3. Identifies policies with CAE explicitly disabled vs. default (enabled)
    4. Correlates with SSC session baselines to determine CAE coverage per zone
    5. Generates a CAE rollout posture report

    Reference: https://learn.microsoft.com/entra/identity/conditional-access/concept-continuous-access-evaluation

.PARAMETER OutputFormat
    Output format: Table (default), Json, or Object.

.PARAMETER Zone
    Filter to a specific governance zone (1, 2, or 3).

.PARAMETER IncludePolicyDetails
    Include full Conditional Access policy details in output.

.NOTES
    File: Get-CAEConfiguration.ps1
    Version: 1.2.0
    Solution: Session Security Configurator (SSC)
    Controls: 1.23, 1.11
    Requires: Microsoft.Graph.Identity.SignIns module

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns

function Get-CAEConfiguration {
    [CmdletBinding()]
    param(
        [ValidateSet('Table', 'Json', 'Object')]
        [string]$OutputFormat = 'Table',

        [ValidateSet('1', '2', '3')]
        [string]$Zone,

        [switch]$IncludePolicyDetails
    )

    begin {
        $ErrorActionPreference = 'Stop'

        Write-Verbose "Retrieving Conditional Access policies for CAE configuration analysis..."
    }

    process {
        # ---------------------------------------------------------------
        # Step 1: Retrieve all Conditional Access policies
        # ---------------------------------------------------------------
        $policies = Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop
        Write-Verbose "Retrieved $($policies.Count) Conditional Access policies."

        # ---------------------------------------------------------------
        # Step 2: Analyze CAE configuration per policy
        # ---------------------------------------------------------------
        $caeResults = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($policy in $policies) {
            $sessionControls = $policy.SessionControls

            # CAE is enabled by default in Entra ID. It can be explicitly
            # disabled via the continuousAccessEvaluation session control.
            $caeMode = 'DefaultEnabled'
            $caeExplicitlyDisabled = $false

            if ($null -ne $sessionControls -and
                $null -ne $sessionControls.ContinuousAccessEvaluation) {
                $caeConfig = $sessionControls.ContinuousAccessEvaluation
                if ($caeConfig.Mode -eq 'disabled') {
                    $caeMode = 'ExplicitlyDisabled'
                    $caeExplicitlyDisabled = $true
                } elseif ($caeConfig.Mode -eq 'strictEnforcement') {
                    $caeMode = 'StrictEnforcement'
                }
            }

            # Determine if policy targets AI agent service principals
            $targetsAgents = $false
            $conditions = $policy.Conditions
            if ($null -ne $conditions.Applications) {
                $appFilter = $conditions.Applications.ApplicationFilter
                if ($null -ne $appFilter -and $appFilter.Mode -eq 'include') {
                    $targetsAgents = $true
                }
                # Check for service principal includes
                if ($conditions.Applications.IncludeApplications -contains 'All' -or
                    ($conditions.ClientApplications.IncludeServicePrincipals | Measure-Object).Count -gt 0) {
                    $targetsAgents = $true
                }
            }

            # Determine zone from policy display name convention (SSC-Zone<N>-*)
            $policyZone = 'Unknown'
            if ($policy.DisplayName -match 'Zone\s*(\d)') {
                $policyZone = $Matches[1]
            }

            # Filter by zone if requested
            if ($Zone -and $policyZone -ne $Zone -and $policyZone -ne 'Unknown') {
                continue
            }

            $hasSessionControls = $null -ne $sessionControls -and (
                $null -ne $sessionControls.SignInFrequency -or
                $null -ne $sessionControls.PersistentBrowser
            )

            $signInFrequency = $null
            if ($null -ne $sessionControls.SignInFrequency) {
                $sif = $sessionControls.SignInFrequency
                $signInFrequency = "$($sif.Value) $($sif.Type)"
            }

            $result = [PSCustomObject]@{
                PolicyId              = $policy.Id
                PolicyName            = $policy.DisplayName
                State                 = $policy.State
                Zone                  = $policyZone
                CAEMode               = $caeMode
                CAEExplicitlyDisabled = $caeExplicitlyDisabled
                HasSessionControls    = $hasSessionControls
                SignInFrequency       = $signInFrequency
                PersistentBrowser     = $sessionControls.PersistentBrowser.Mode
                TargetsAgentWorkloads = $targetsAgents
                CAEEligible           = (-not $caeExplicitlyDisabled) -and ($policy.State -eq 'enabled')
            }

            if ($IncludePolicyDetails) {
                $result | Add-Member -NotePropertyName 'GrantControls' -NotePropertyValue ($policy.GrantControls | ConvertTo-Json -Compress)
                $result | Add-Member -NotePropertyName 'Conditions' -NotePropertyValue ($policy.Conditions | ConvertTo-Json -Compress -Depth 5)
            }

            $caeResults.Add($result)
        }

        # ---------------------------------------------------------------
        # Step 3: Generate posture summary
        # ---------------------------------------------------------------
        $totalPolicies = $caeResults.Count
        $caeEnabledCount = ($caeResults | Where-Object CAEEligible).Count
        $caeDisabledCount = ($caeResults | Where-Object CAEExplicitlyDisabled).Count
        $agentTargetedCount = ($caeResults | Where-Object TargetsAgentWorkloads).Count

        $posture = [PSCustomObject]@{
            Timestamp            = (Get-Date -Format 'o')
            TotalPoliciesScanned = $totalPolicies
            CAEEligible          = $caeEnabledCount
            CAEDisabled          = $caeDisabledCount
            AgentTargeted        = $agentTargetedCount
            CoveragePercent      = if ($totalPolicies -gt 0) { [Math]::Round(($caeEnabledCount / $totalPolicies) * 100, 1) } else { 0 }
            ZoneSummary          = @{
                Zone1 = ($caeResults | Where-Object { $_.Zone -eq '1' -and $_.CAEEligible }).Count
                Zone2 = ($caeResults | Where-Object { $_.Zone -eq '2' -and $_.CAEEligible }).Count
                Zone3 = ($caeResults | Where-Object { $_.Zone -eq '3' -and $_.CAEEligible }).Count
            }
            Recommendation       = if ($caeDisabledCount -gt 0) {
                "WARNING: $caeDisabledCount policy/policies have CAE explicitly disabled. Review for agent session security gaps."
            } else {
                'CAE is enabled (default or strict) across all scanned policies.'
            }
            Reference            = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-continuous-access-evaluation'
        }

        # ---------------------------------------------------------------
        # Step 4: Output
        # ---------------------------------------------------------------
        switch ($OutputFormat) {
            'Json' {
                @{
                    Posture  = $posture
                    Policies = $caeResults
                } | ConvertTo-Json -Depth 10
            }
            'Object' {
                @{
                    Posture  = $posture
                    Policies = $caeResults
                }
            }
            default {
                Write-Host "`nCAE Configuration Posture:" -ForegroundColor Cyan
                Write-Host ("=" * 60) -ForegroundColor Cyan
                Write-Host "  Total Policies Scanned:  $totalPolicies"
                Write-Host "  CAE Eligible:            $caeEnabledCount ($($posture.CoveragePercent)%)" -ForegroundColor $(if ($posture.CoveragePercent -ge 80) { 'Green' } else { 'Yellow' })
                Write-Host "  CAE Explicitly Disabled: $caeDisabledCount" -ForegroundColor $(if ($caeDisabledCount -gt 0) { 'Red' } else { 'Green' })
                Write-Host "  Agent-Targeted Policies: $agentTargetedCount"
                Write-Host "  Zone Coverage:           Z1=$($posture.ZoneSummary.Zone1) Z2=$($posture.ZoneSummary.Zone2) Z3=$($posture.ZoneSummary.Zone3)"
                Write-Host ""

                if ($caeDisabledCount -gt 0) {
                    Write-Host "  Policies with CAE Disabled:" -ForegroundColor Red
                    $caeResults | Where-Object CAEExplicitlyDisabled | Format-Table -Property PolicyName, Zone, State -AutoSize
                }

                Write-Host "`n  Reference: $($posture.Reference)" -ForegroundColor DarkGray
            }
        }
    }
}
