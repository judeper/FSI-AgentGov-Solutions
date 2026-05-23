<#
.SYNOPSIS
    Compares two Conditional Access policy baseline snapshots to detect drift.

.DESCRIPTION
    Accepts a previous and current baseline (arrays of normalized policy objects
    from Get-CAAPolicyBaseline) and compares them across five dimensions:

      1. State changes — enabled, reportOnly, disabled transitions
      2. Condition changes — user/group includes/excludes, applications, risk levels
      3. Grant control changes — controls added/removed, operator changes
      4. Session control changes — sign-in frequency, persistent browser
      5. Policy additions/removals — new or missing policies

    Each drift finding is assigned a severity level (1–5) using the ACV canonical
    scale. Zone 3 violations are escalated by +1 severity (capped at 5) to reflect
    the higher governance requirements of enterprise-managed environments.

.PARAMETER PreviousBaseline
    Array of normalized policy objects representing the expected (saved) state.

.PARAMETER CurrentBaseline
    Array of normalized policy objects representing the current (live) state.

.EXAMPLE
    $previous = Get-Content ./baseline.json | ConvertFrom-Json
    $current = Get-CAAPolicyBaseline
    Compare-CAAPolicyBaseline -PreviousBaseline $previous.policies -CurrentBaseline $current

    Compares stored baseline against current live state and returns drift results.

.EXAMPLE
    $drifts = Compare-CAAPolicyBaseline -PreviousBaseline $saved -CurrentBaseline $live
    $drifts | Where-Object { $_.Severity -ge 4 } | Format-Table

    Filters results to show only Failed and Error severity findings.

.OUTPUTS
    System.Collections.Hashtable[]
    Array of drift result objects with properties: PolicyName, DriftType, Dimension,
    Expected, Actual, Severity, Zone, Description.

    Severity values (ACV canonical):
      5 (Error)       — Expected policy deleted or missing
      4 (Failed)      — Policy disabled, grant controls weakened, break-glass exclusion removed
      3 (GracePeriod) — Policy moved to reportOnly when should be enforced
      2 (Warning)     — Session frequency loosened, new exclusions added, risk levels removed
      1 (Passed)      — No drift detected on this policy

.NOTES
    File: Compare-PolicyBaseline.ps1
    Version: 1.0.0
    Supports compliance with FINRA 4511/3110, SEC 17a-3/4, and OCC 2011-12
    through automated policy drift detection and severity classification.
#>

function Compare-CAAPolicyBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$PreviousBaseline,

        [Parameter(Mandatory)]
        [object[]]$CurrentBaseline
    )

    $ErrorActionPreference = 'Stop'

    $results = [System.Collections.Generic.List[hashtable]]::new()

    # Build lookup tables by PolicyId
    $previousById = @{}
    foreach ($policy in $PreviousBaseline) {
        $id = if ($policy.PolicyId) { $policy.PolicyId } else { $policy.policyId }
        $previousById[$id] = $policy
    }

    $currentById = @{}
    foreach ($policy in $CurrentBaseline) {
        $id = if ($policy.PolicyId) { $policy.PolicyId } else { $policy.policyId }
        $currentById[$id] = $policy
    }

    #region Helper: Apply zone-based severity escalation
    function Get-EscalatedSeverity {
        param([int]$BaseSeverity, [string]$Zone)
        if ($Zone -eq 'Zone3') {
            return [math]::Min($BaseSeverity + 1, 5)
        }
        return $BaseSeverity
    }
    #endregion

    #region Helper: Safe property access (handles PSCustomObject and hashtable)
    function Get-PolicyProp {
        param([object]$Obj, [string]$Name)
        if ($null -eq $Obj) { return $null }
        if ($Obj -is [hashtable]) { return $Obj[$Name] }
        return $Obj.$Name
    }
    #endregion

    #region Helper: Normalize nested objects for coarse-grained comparisons
    function Convert-ToComparableJson {
        param([object]$Value)
        if ($null -eq $Value) { return '' }
        return ($Value | ConvertTo-Json -Depth 20 -Compress)
    }

    function Get-AuthenticationStrengthIdentifier {
        param([object]$GrantControls)
        $strength = Get-PolicyProp $GrantControls 'AuthenticationStrength'
        if (-not $strength) { $strength = Get-PolicyProp $GrantControls 'authenticationStrength' }
        if (-not $strength) { return '' }

        $id = Get-PolicyProp $strength 'Id'
        if (-not $id) { $id = Get-PolicyProp $strength 'id' }
        $displayName = Get-PolicyProp $strength 'DisplayName'
        if (-not $displayName) { $displayName = Get-PolicyProp $strength 'displayName' }
        $requirements = Get-PolicyProp $strength 'RequirementsSatisfied'
        if (-not $requirements) { $requirements = Get-PolicyProp $strength 'requirementsSatisfied' }

        return (@($id, $displayName, $requirements) | Where-Object { $_ }) -join '|'
    }
    #endregion

    #region Helper: Compare arrays (order-independent)
    function Compare-Arrays {
        param([object[]]$Expected, [object[]]$Actual)
        $e = @($Expected | Where-Object { $_ })
        $a = @($Actual | Where-Object { $_ })
        if ($e.Count -eq 0 -and $a.Count -eq 0) { return $true }
        if ($e.Count -ne $a.Count) { return $false }
        $diff = Compare-Object -ReferenceObject $e -DifferenceObject $a -PassThru
        return ($null -eq $diff -or $diff.Count -eq 0)
    }
    #endregion

    # ----- Dimension 5: Policy Removals (expected policies missing) -----
    foreach ($prevId in $previousById.Keys) {
        if (-not $currentById.ContainsKey($prevId)) {
            $prev = $previousById[$prevId]
            $policyName = Get-PolicyProp $prev 'DisplayName'
            if (-not $policyName) { $policyName = Get-PolicyProp $prev 'displayName' }
            $zone = Get-PolicyProp $prev 'Zone'
            if (-not $zone) { $zone = Get-PolicyProp $prev 'zone' }
            if (-not $zone) { $zone = 'Common' }

            $severity = Get-EscalatedSeverity -BaseSeverity 5 -Zone $zone

            $results.Add(@{
                PolicyName  = $policyName
                DriftType   = 'PolicyRemoved'
                Dimension   = 'PolicyAdditionsRemovals'
                Expected    = 'Policy exists'
                Actual      = 'Policy missing or deleted'
                Severity    = $severity
                Zone        = $zone
                Description = "Expected policy '$policyName' was not found in the current tenant"
            })
        }
    }

    # ----- Dimension 5: Policy Additions (unexpected new policies) -----
    foreach ($curId in $currentById.Keys) {
        if (-not $previousById.ContainsKey($curId)) {
            $cur = $currentById[$curId]
            $policyName = Get-PolicyProp $cur 'DisplayName'
            if (-not $policyName) { $policyName = Get-PolicyProp $cur 'displayName' }
            $zone = Get-PolicyProp $cur 'Zone'
            if (-not $zone) { $zone = Get-PolicyProp $cur 'zone' }
            if (-not $zone) { $zone = 'Common' }

            $results.Add(@{
                PolicyName  = $policyName
                DriftType   = 'PolicyAdded'
                Dimension   = 'PolicyAdditionsRemovals'
                Expected    = 'Policy not in baseline'
                Actual      = 'New policy detected'
                Severity    = 2  # Warning — new policy, not necessarily bad
                Zone        = $zone
                Description = "New policy '$policyName' detected that was not in the baseline"
            })
        }
    }

    # ----- Compare matched policies across dimensions 1-4 -----
    foreach ($prevId in $previousById.Keys) {
        if (-not $currentById.ContainsKey($prevId)) { continue }

        $prev = $previousById[$prevId]
        $cur = $currentById[$prevId]

        $policyName = Get-PolicyProp $cur 'DisplayName'
        if (-not $policyName) { $policyName = Get-PolicyProp $cur 'displayName' }
        $zone = Get-PolicyProp $cur 'Zone'
        if (-not $zone) { $zone = Get-PolicyProp $cur 'zone' }
        if (-not $zone) { $zone = 'Common' }

        $prevState = Get-PolicyProp $prev 'State'
        if (-not $prevState) { $prevState = Get-PolicyProp $prev 'state' }
        $curState = Get-PolicyProp $cur 'State'
        if (-not $curState) { $curState = Get-PolicyProp $cur 'state' }

        $policyDriftFound = $false

        # ----- Dimension 1: State changes -----
        if ($prevState -ne $curState) {
            $policyDriftFound = $true

            # Determine severity based on transition direction
            $severity = if ($curState -eq 'disabled') {
                4  # Failed: policy disabled
            }
            elseif ($curState -eq 'enabledForReportingButNotEnforced' -and $prevState -eq 'enabled') {
                3  # GracePeriod: moved to reportOnly
            }
            elseif ($curState -eq 'enabled' -and $prevState -eq 'enabledForReportingButNotEnforced') {
                1  # Passed: upgraded to enforced (improvement)
            }
            else {
                2  # Warning: other state transition
            }

            $severity = Get-EscalatedSeverity -BaseSeverity $severity -Zone $zone

            $results.Add(@{
                PolicyName  = $policyName
                DriftType   = 'StateChanged'
                Dimension   = 'StateChanges'
                Expected    = $prevState
                Actual      = $curState
                Severity    = $severity
                Zone        = $zone
                Description = "Policy state changed from '$prevState' to '$curState'"
            })
        }

        # ----- Dimension 2: Condition changes -----
        $prevConditions = Get-PolicyProp $prev 'Conditions'
        if (-not $prevConditions) { $prevConditions = Get-PolicyProp $prev 'conditions' }
        $curConditions = Get-PolicyProp $cur 'Conditions'
        if (-not $curConditions) { $curConditions = Get-PolicyProp $cur 'conditions' }

        if ($prevConditions -and $curConditions) {
            # Users — includes
            $prevUsers = Get-PolicyProp (Get-PolicyProp $prevConditions 'Users') 'IncludeUsers'
            if (-not $prevUsers) { $prevUsers = Get-PolicyProp (Get-PolicyProp $prevConditions 'users') 'includeUsers' }
            $curUsers = Get-PolicyProp (Get-PolicyProp $curConditions 'Users') 'IncludeUsers'
            if (-not $curUsers) { $curUsers = Get-PolicyProp (Get-PolicyProp $curConditions 'users') 'includeUsers' }

            if (-not (Compare-Arrays -Expected @($prevUsers) -Actual @($curUsers))) {
                $policyDriftFound = $true
                $severity = Get-EscalatedSeverity -BaseSeverity 2 -Zone $zone
                $results.Add(@{
                    PolicyName  = $policyName
                    DriftType   = 'ConditionChanged'
                    Dimension   = 'ConditionChanges'
                    Expected    = ($prevUsers -join ', ')
                    Actual      = ($curUsers -join ', ')
                    Severity    = $severity
                    Zone        = $zone
                    Description = "Included users changed"
                })
            }

            # Users — excludes
            $prevExclUsers = Get-PolicyProp (Get-PolicyProp $prevConditions 'Users') 'ExcludeUsers'
            if (-not $prevExclUsers) { $prevExclUsers = Get-PolicyProp (Get-PolicyProp $prevConditions 'users') 'excludeUsers' }
            $curExclUsers = Get-PolicyProp (Get-PolicyProp $curConditions 'Users') 'ExcludeUsers'
            if (-not $curExclUsers) { $curExclUsers = Get-PolicyProp (Get-PolicyProp $curConditions 'users') 'excludeUsers' }

            if (-not (Compare-Arrays -Expected @($prevExclUsers) -Actual @($curExclUsers))) {
                $policyDriftFound = $true

                # Check if break-glass exclusions were removed (higher severity)
                $removedExclusions = @($prevExclUsers) | Where-Object { $_ -and $_ -notin @($curExclUsers) }
                $addedExclusions = @($curExclUsers) | Where-Object { $_ -and $_ -notin @($prevExclUsers) }

                if ($removedExclusions.Count -gt 0) {
                    $severity = Get-EscalatedSeverity -BaseSeverity 4 -Zone $zone
                    $results.Add(@{
                        PolicyName  = $policyName
                        DriftType   = 'ExclusionRemoved'
                        Dimension   = 'ConditionChanges'
                        Expected    = ($prevExclUsers -join ', ')
                        Actual      = ($curExclUsers -join ', ')
                        Severity    = $severity
                        Zone        = $zone
                        Description = "User exclusions removed: $($removedExclusions -join ', ')"
                    })
                }
                if ($addedExclusions.Count -gt 0) {
                    $severity = Get-EscalatedSeverity -BaseSeverity 2 -Zone $zone
                    $results.Add(@{
                        PolicyName  = $policyName
                        DriftType   = 'ExclusionAdded'
                        Dimension   = 'ConditionChanges'
                        Expected    = ($prevExclUsers -join ', ')
                        Actual      = ($curExclUsers -join ', ')
                        Severity    = $severity
                        Zone        = $zone
                        Description = "New user exclusions added: $($addedExclusions -join ', ')"
                    })
                }
            }

            # Applications
            $prevApps = Get-PolicyProp (Get-PolicyProp $prevConditions 'Applications') 'IncludeApplications'
            if (-not $prevApps) { $prevApps = Get-PolicyProp (Get-PolicyProp $prevConditions 'applications') 'includeApplications' }
            $curApps = Get-PolicyProp (Get-PolicyProp $curConditions 'Applications') 'IncludeApplications'
            if (-not $curApps) { $curApps = Get-PolicyProp (Get-PolicyProp $curConditions 'applications') 'includeApplications' }

            if (-not (Compare-Arrays -Expected @($prevApps) -Actual @($curApps))) {
                $policyDriftFound = $true
                $severity = Get-EscalatedSeverity -BaseSeverity 2 -Zone $zone
                $results.Add(@{
                    PolicyName  = $policyName
                    DriftType   = 'ConditionChanged'
                    Dimension   = 'ConditionChanges'
                    Expected    = ($prevApps -join ', ')
                    Actual      = ($curApps -join ', ')
                    Severity    = $severity
                    Zone        = $zone
                    Description = "Included applications changed"
                })
            }

            # Sign-in risk levels
            $prevRisk = Get-PolicyProp $prevConditions 'SignInRiskLevels'
            if (-not $prevRisk) { $prevRisk = Get-PolicyProp $prevConditions 'signInRiskLevels' }
            $curRisk = Get-PolicyProp $curConditions 'SignInRiskLevels'
            if (-not $curRisk) { $curRisk = Get-PolicyProp $curConditions 'signInRiskLevels' }

            if (-not (Compare-Arrays -Expected @($prevRisk) -Actual @($curRisk))) {
                $policyDriftFound = $true
                $removedRisks = @($prevRisk) | Where-Object { $_ -and $_ -notin @($curRisk) }
                # Removing risk levels weakens the policy and should escalate
                # severity above a routine "changed" event.
                $baseSev = if ($removedRisks.Count -gt 0) { 4 } else { 2 }
                $severity = Get-EscalatedSeverity -BaseSeverity $baseSev -Zone $zone
                $results.Add(@{
                    PolicyName  = $policyName
                    DriftType   = 'ConditionChanged'
                    Dimension   = 'ConditionChanges'
                    Expected    = ($prevRisk -join ', ')
                    Actual      = ($curRisk -join ', ')
                    Severity    = $severity
                    Zone        = $zone
                    Description = "Sign-in risk levels changed"
                })
            }

            # User risk levels
            $prevUserRisk = Get-PolicyProp $prevConditions 'UserRiskLevels'
            if (-not $prevUserRisk) { $prevUserRisk = Get-PolicyProp $prevConditions 'userRiskLevels' }
            $curUserRisk = Get-PolicyProp $curConditions 'UserRiskLevels'
            if (-not $curUserRisk) { $curUserRisk = Get-PolicyProp $curConditions 'userRiskLevels' }

            if (-not (Compare-Arrays -Expected @($prevUserRisk) -Actual @($curUserRisk))) {
                $policyDriftFound = $true
                $removedUserRisks = @($prevUserRisk) | Where-Object { $_ -and $_ -notin @($curUserRisk) }
                $baseSev = if ($removedUserRisks.Count -gt 0) { 4 } else { 2 }
                $severity = Get-EscalatedSeverity -BaseSeverity $baseSev -Zone $zone
                $results.Add(@{
                    PolicyName  = $policyName
                    DriftType   = 'ConditionChanged'
                    Dimension   = 'ConditionChanges'
                    Expected    = ($prevUserRisk -join ', ')
                    Actual      = ($curUserRisk -join ', ')
                    Severity    = $severity
                    Zone        = $zone
                    Description = "User risk levels changed"
                })
            }

            # Named locations
            foreach ($locationField in @('IncludeLocations', 'ExcludeLocations')) {
                $prevLocations = Get-PolicyProp (Get-PolicyProp (Get-PolicyProp $prevConditions 'Locations') $locationField) 'Value'
                if (-not $prevLocations) { $prevLocations = Get-PolicyProp (Get-PolicyProp (Get-PolicyProp $prevConditions 'locations') ($locationField.Substring(0,1).ToLower() + $locationField.Substring(1))) 'Value' }
                if (-not $prevLocations) { $prevLocations = Get-PolicyProp (Get-PolicyProp $prevConditions 'Locations') $locationField }
                if (-not $prevLocations) { $prevLocations = Get-PolicyProp (Get-PolicyProp $prevConditions 'locations') ($locationField.Substring(0,1).ToLower() + $locationField.Substring(1)) }
                $curLocations = Get-PolicyProp (Get-PolicyProp $curConditions 'Locations') $locationField
                if (-not $curLocations) { $curLocations = Get-PolicyProp (Get-PolicyProp $curConditions 'locations') ($locationField.Substring(0,1).ToLower() + $locationField.Substring(1)) }

                if (-not (Compare-Arrays -Expected @($prevLocations) -Actual @($curLocations))) {
                    $policyDriftFound = $true
                    $severity = Get-EscalatedSeverity -BaseSeverity 2 -Zone $zone
                    $results.Add(@{
                        PolicyName  = $policyName
                        DriftType   = 'ConditionChanged'
                        Dimension   = 'ConditionChanges'
                        Expected    = ($prevLocations -join ', ')
                        Actual      = ($curLocations -join ', ')
                        Severity    = $severity
                        Zone        = $zone
                        Description = "Location condition $locationField changed"
                    })
                }
            }

            # Device filter / device conditions
            $prevDevices = Get-PolicyProp $prevConditions 'Devices'
            if (-not $prevDevices) { $prevDevices = Get-PolicyProp $prevConditions 'devices' }
            $curDevices = Get-PolicyProp $curConditions 'Devices'
            if (-not $curDevices) { $curDevices = Get-PolicyProp $curConditions 'devices' }
            if ((Convert-ToComparableJson $prevDevices) -ne (Convert-ToComparableJson $curDevices)) {
                $policyDriftFound = $true
                $severity = Get-EscalatedSeverity -BaseSeverity 2 -Zone $zone
                $results.Add(@{
                    PolicyName  = $policyName
                    DriftType   = 'ConditionChanged'
                    Dimension   = 'ConditionChanges'
                    Expected    = Convert-ToComparableJson $prevDevices
                    Actual      = Convert-ToComparableJson $curDevices
                    Severity    = $severity
                    Zone        = $zone
                    Description = "Device condition changed"
                })
            }
        }

        # ----- Dimension 3: Grant control changes -----
        $prevGrant = Get-PolicyProp $prev 'GrantControls'
        if (-not $prevGrant) { $prevGrant = Get-PolicyProp $prev 'grantControls' }
        $curGrant = Get-PolicyProp $cur 'GrantControls'
        if (-not $curGrant) { $curGrant = Get-PolicyProp $cur 'grantControls' }

        if ($prevGrant -and $curGrant) {
            # Operator change (AND→OR is weakening)
            $prevOp = Get-PolicyProp $prevGrant 'Operator'
            if (-not $prevOp) { $prevOp = Get-PolicyProp $prevGrant 'operator' }
            $curOp = Get-PolicyProp $curGrant 'Operator'
            if (-not $curOp) { $curOp = Get-PolicyProp $curGrant 'operator' }

            if ($prevOp -ne $curOp) {
                $policyDriftFound = $true
                $baseSev = if ($prevOp -eq 'AND' -and $curOp -eq 'OR') { 4 } else { 2 }
                $severity = Get-EscalatedSeverity -BaseSeverity $baseSev -Zone $zone
                $results.Add(@{
                    PolicyName  = $policyName
                    DriftType   = 'GrantControlChanged'
                    Dimension   = 'GrantControlChanges'
                    Expected    = "Operator: $prevOp"
                    Actual      = "Operator: $curOp"
                    Severity    = $severity
                    Zone        = $zone
                    Description = "Grant control operator changed from '$prevOp' to '$curOp'"
                })
            }

            # Built-in controls
            $prevControls = Get-PolicyProp $prevGrant 'BuiltInControls'
            if (-not $prevControls) { $prevControls = Get-PolicyProp $prevGrant 'builtInControls' }
            $curControls = Get-PolicyProp $curGrant 'BuiltInControls'
            if (-not $curControls) { $curControls = Get-PolicyProp $curGrant 'builtInControls' }

            if (-not (Compare-Arrays -Expected @($prevControls) -Actual @($curControls))) {
                $policyDriftFound = $true
                $removedControls = @($prevControls) | Where-Object { $_ -and $_ -notin @($curControls) }
                # MFA removed is critical
                $baseSev = if ($removedControls -contains 'mfa') { 4 } else { 2 }
                $severity = Get-EscalatedSeverity -BaseSeverity $baseSev -Zone $zone
                $results.Add(@{
                    PolicyName  = $policyName
                    DriftType   = 'GrantControlChanged'
                    Dimension   = 'GrantControlChanges'
                    Expected    = ($prevControls -join ', ')
                    Actual      = ($curControls -join ', ')
                    Severity    = $severity
                    Zone        = $zone
                    Description = "Built-in grant controls changed"
                })
            }

            # Authentication strength relationship
            $prevStrength = Get-AuthenticationStrengthIdentifier -GrantControls $prevGrant
            $curStrength = Get-AuthenticationStrengthIdentifier -GrantControls $curGrant
            if ($prevStrength -ne $curStrength) {
                $policyDriftFound = $true
                $baseSev = if ($prevStrength -and -not $curStrength) { 4 } else { 2 }
                $severity = Get-EscalatedSeverity -BaseSeverity $baseSev -Zone $zone
                $results.Add(@{
                    PolicyName  = $policyName
                    DriftType   = 'GrantControlChanged'
                    Dimension   = 'GrantControlChanges'
                    Expected    = if ($prevStrength) { $prevStrength } else { '(none)' }
                    Actual      = if ($curStrength) { $curStrength } else { '(none)' }
                    Severity    = $severity
                    Zone        = $zone
                    Description = "Authentication strength requirement changed"
                })
            }
        }

        # ----- Dimension 4: Session control changes -----
        $prevSession = Get-PolicyProp $prev 'SessionControls'
        if (-not $prevSession) { $prevSession = Get-PolicyProp $prev 'sessionControls' }
        $curSession = Get-PolicyProp $cur 'SessionControls'
        if (-not $curSession) { $curSession = Get-PolicyProp $cur 'sessionControls' }

        if ($prevSession -and $curSession) {
            # Sign-in frequency
            $prevFreq = Get-PolicyProp $prevSession 'SignInFrequency'
            if (-not $prevFreq) { $prevFreq = Get-PolicyProp $prevSession 'signInFrequency' }
            $curFreq = Get-PolicyProp $curSession 'SignInFrequency'
            if (-not $curFreq) { $curFreq = Get-PolicyProp $curSession 'signInFrequency' }

            if ($prevFreq -and $curFreq) {
                $prevEnabled = Get-PolicyProp $prevFreq 'IsEnabled'
                if ($null -eq $prevEnabled) { $prevEnabled = Get-PolicyProp $prevFreq 'isEnabled' }
                $curEnabled = Get-PolicyProp $curFreq 'IsEnabled'
                if ($null -eq $curEnabled) { $curEnabled = Get-PolicyProp $curFreq 'isEnabled' }

                $prevValue = Get-PolicyProp $prevFreq 'Value'
                if ($null -eq $prevValue) { $prevValue = Get-PolicyProp $prevFreq 'value' }
                $curValue = Get-PolicyProp $curFreq 'Value'
                if ($null -eq $curValue) { $curValue = Get-PolicyProp $curFreq 'value' }

                $prevType = Get-PolicyProp $prevFreq 'Type'
                if (-not $prevType) { $prevType = Get-PolicyProp $prevFreq 'type' }
                $curType = Get-PolicyProp $curFreq 'Type'
                if (-not $curType) { $curType = Get-PolicyProp $curFreq 'type' }

                $freqChanged = ($prevEnabled -ne $curEnabled) -or ($prevValue -ne $curValue) -or ($prevType -ne $curType)

                if ($freqChanged) {
                    $policyDriftFound = $true
                    $severity = Get-EscalatedSeverity -BaseSeverity 2 -Zone $zone
                    $results.Add(@{
                        PolicyName  = $policyName
                        DriftType   = 'SessionControlChanged'
                        Dimension   = 'SessionControlChanges'
                        Expected    = "SignInFrequency: enabled=$prevEnabled, value=$prevValue, type=$prevType"
                        Actual      = "SignInFrequency: enabled=$curEnabled, value=$curValue, type=$curType"
                        Severity    = $severity
                        Zone        = $zone
                        Description = "Sign-in frequency settings changed"
                    })
                }
            }

            # Persistent browser
            $prevBrowser = Get-PolicyProp $prevSession 'PersistentBrowser'
            if (-not $prevBrowser) { $prevBrowser = Get-PolicyProp $prevSession 'persistentBrowser' }
            $curBrowser = Get-PolicyProp $curSession 'PersistentBrowser'
            if (-not $curBrowser) { $curBrowser = Get-PolicyProp $curSession 'persistentBrowser' }

            if ($prevBrowser -and $curBrowser) {
                $prevBrEnabled = Get-PolicyProp $prevBrowser 'IsEnabled'
                if ($null -eq $prevBrEnabled) { $prevBrEnabled = Get-PolicyProp $prevBrowser 'isEnabled' }
                $curBrEnabled = Get-PolicyProp $curBrowser 'IsEnabled'
                if ($null -eq $curBrEnabled) { $curBrEnabled = Get-PolicyProp $curBrowser 'isEnabled' }

                $prevBrMode = Get-PolicyProp $prevBrowser 'Mode'
                if (-not $prevBrMode) { $prevBrMode = Get-PolicyProp $prevBrowser 'mode' }
                $curBrMode = Get-PolicyProp $curBrowser 'Mode'
                if (-not $curBrMode) { $curBrMode = Get-PolicyProp $curBrowser 'mode' }

                $browserChanged = ($prevBrEnabled -ne $curBrEnabled) -or ($prevBrMode -ne $curBrMode)

                if ($browserChanged) {
                    $policyDriftFound = $true
                    $severity = Get-EscalatedSeverity -BaseSeverity 2 -Zone $zone
                    $results.Add(@{
                        PolicyName  = $policyName
                        DriftType   = 'SessionControlChanged'
                        Dimension   = 'SessionControlChanges'
                        Expected    = "PersistentBrowser: enabled=$prevBrEnabled, mode=$prevBrMode"
                        Actual      = "PersistentBrowser: enabled=$curBrEnabled, mode=$curBrMode"
                        Severity    = $severity
                        Zone        = $zone
                        Description = "Persistent browser settings changed"
                    })
                }
            }
        }

        # If no drift was found for this policy, add a Passed result
        if (-not $policyDriftFound) {
            $results.Add(@{
                PolicyName  = $policyName
                DriftType   = 'None'
                Dimension   = 'None'
                Expected    = 'No changes expected'
                Actual      = 'No changes detected'
                Severity    = 1
                Zone        = $zone
                Description = "No drift detected for policy '$policyName'"
            })
        }
    }

    return @($results)
}
