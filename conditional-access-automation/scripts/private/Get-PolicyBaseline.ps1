<#
.SYNOPSIS
    Retrieves a normalized baseline snapshot of Conditional Access policies
    matching FSI governance naming patterns.

.DESCRIPTION
    Queries Microsoft Graph for all Conditional Access policies that match
    FSI agent governance naming conventions (CA-CopilotStudio-*, CA-AgentBuilder-*,
    CA-M365Copilot-*, CA-BlockLegacyAuth-*, CA-RequireCompliantDevice-*, and custom
    prefixes). Returns a normalized array of policy objects suitable for baseline
    comparison and drift detection.

    Each policy object includes conditions, grant controls, session controls,
    governance zone classification (derived from the policy name), and a UTC
    timestamp marking the snapshot time.

    Supports WhatIf mode to preview which policies would be queried without
    making Graph API calls.

.PARAMETER TenantId
    Optional Entra ID tenant GUID. When provided, used for logging
    and correlation. The active Graph session determines the actual tenant.

.PARAMETER PolicyNamePrefix
    Optional policy name prefix for matching additional custom-prefixed policies.
    Default FSI patterns (CA-CopilotStudio-*, CA-AgentBuilder-*, CA-M365Copilot-*,
    CA-BlockLegacyAuth-*, CA-RequireCompliantDevice-*) are always included.

.PARAMETER ConfigPath
    Optional path to a tenant configuration JSON file. When provided and
    the file contains a policyPrefix property, that prefix is added to the
    set of matching patterns.

.EXAMPLE
    Get-CAAPolicyBaseline

    Returns normalized policy objects for all FSI-patterned CA policies
    in the currently connected tenant.

.EXAMPLE
    Get-CAAPolicyBaseline -PolicyNamePrefix "CA-Custom-"

    Returns policies matching default FSI patterns plus any policies
    whose DisplayName starts with "CA-Custom-".

.EXAMPLE
    Get-CAAPolicyBaseline -ConfigPath "./config.json"

    Loads additional policy prefix from the configuration file and
    includes matching policies in the baseline.

.EXAMPLE
    Get-CAAPolicyBaseline -WhatIf

    Previews which naming patterns would be queried without calling Graph.

.OUTPUTS
    System.Collections.Hashtable[]
    Array of normalized policy objects with properties: PolicyId, DisplayName,
    State, Conditions, GrantControls, SessionControls, Zone, SnapshotTimestamp.

.NOTES
    File: Get-PolicyBaseline.ps1
    Version: 1.0.0
    Supports compliance with FINRA 4511/3110, SEC 17a-3/4, and OCC 2011-12
    through automated policy baseline capture for drift detection.
#>

function Get-CAAPolicyBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId,

        [Parameter(Mandatory = $false)]
        [string]$PolicyNamePrefix,

        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    $ErrorActionPreference = 'Stop'

    # Default FSI naming patterns
    $defaultPatterns = @(
        'CA-CopilotStudio-*',
        'CA-AgentBuilder-*',
        'CA-M365Copilot-*',
        'CA-BlockLegacyAuth-*',
        'CA-RequireCompliantDevice-*'
    )

    # Build pattern list
    $patterns = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $defaultPatterns) { $patterns.Add($p) }

    # Add custom prefix if provided directly
    if ($PolicyNamePrefix) {
        $prefixPattern = if ($PolicyNamePrefix.EndsWith('*')) { $PolicyNamePrefix } else { "$PolicyNamePrefix*" }
        $patterns.Add($prefixPattern)
        Write-Verbose "Added custom prefix pattern: $prefixPattern"
    }

    # Load config prefix if ConfigPath provided
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        $configData = Get-Content $ConfigPath -ErrorAction Stop | ConvertFrom-Json
        if ($configData.policyPrefix) {
            $configPattern = "$($configData.policyPrefix)-*"
            $patterns.Add($configPattern)
            Write-Verbose "Added config prefix pattern: $configPattern"
        }
    }

    # NOTE: This is a read-only Get- function. ShouldProcess/-WhatIf are
    # intentionally NOT enabled — earlier versions wrapped the entire query in
    # ShouldProcess, which caused $null returns under -WhatIf and broke
    # callers (Test-PolicyCompliance, Watch-PolicyDrift) that expected a
    # baseline array.

    function Get-CAANestedValue {
        param(
            [Parameter(Mandatory = $false)] [object]$InputObject,
            [Parameter(Mandatory)] [string[]]$Path
        )

        $current = $InputObject
        foreach ($segment in $Path) {
            if ($null -eq $current) { return $null }
            if ($current -is [hashtable]) {
                if (-not $current.ContainsKey($segment)) { return $null }
                $current = $current[$segment]
                continue
            }
            $property = $current.PSObject.Properties[$segment]
            if (-not $property) { return $null }
            $current = $property.Value
        }
        return $current
    }

    # Retrieve all CA policies with pagination
    Write-Verbose "Retrieving all Conditional Access policies from Graph..."
    $allPolicies = Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop
    Write-Verbose "Found $($allPolicies.Count) total CA policies"

    # Filter to FSI-matching policies
    $matchedPolicies = @()
    foreach ($policy in $allPolicies) {
        foreach ($pattern in $patterns) {
            if ($policy.DisplayName -like $pattern) {
                $matchedPolicies += $policy
                break  # avoid duplicates if policy matches multiple patterns
            }
        }
    }

    Write-Verbose "Matched $($matchedPolicies.Count) policies against FSI patterns"

    # Snapshot timestamp (UTC ISO 8601)
    $snapshotTime = (Get-Date).ToUniversalTime().ToString('o')

    # Normalize each policy into a baseline object
    $baselineObjects = @()
    foreach ($policy in $matchedPolicies) {
        # Derive zone from policy display name
        $zone = if ($policy.DisplayName -match 'Zone1') { 'Zone1' }
                elseif ($policy.DisplayName -match 'Zone2') { 'Zone2' }
                elseif ($policy.DisplayName -match 'Zone3') { 'Zone3' }
                elseif ($policy.DisplayName -match 'AllZones') { 'AllZones' }
                else { 'Common' }

        # Normalize conditions. Keep the fields that Microsoft Graph v1.0 exposes
        # for conditionalAccessConditionSet so drift detection can see risk,
        # location, device, client-app, and authentication-flow changes.
        $conditions = @{
            Users                      = @{
                IncludeUsers                 = @(Get-CAANestedValue $policy @('Conditions', 'Users', 'IncludeUsers'))
                ExcludeUsers                 = @(Get-CAANestedValue $policy @('Conditions', 'Users', 'ExcludeUsers'))
                IncludeGroups                = @(Get-CAANestedValue $policy @('Conditions', 'Users', 'IncludeGroups'))
                ExcludeGroups                = @(Get-CAANestedValue $policy @('Conditions', 'Users', 'ExcludeGroups'))
                IncludeRoles                 = @(Get-CAANestedValue $policy @('Conditions', 'Users', 'IncludeRoles'))
                ExcludeRoles                 = @(Get-CAANestedValue $policy @('Conditions', 'Users', 'ExcludeRoles'))
                ExcludeGuestsOrExternalUsers = Get-CAANestedValue $policy @('Conditions', 'Users', 'ExcludeGuestsOrExternalUsers')
            }
            Applications               = @{
                IncludeApplications = @(Get-CAANestedValue $policy @('Conditions', 'Applications', 'IncludeApplications'))
                ExcludeApplications = @(Get-CAANestedValue $policy @('Conditions', 'Applications', 'ExcludeApplications'))
                IncludeUserActions  = @(Get-CAANestedValue $policy @('Conditions', 'Applications', 'IncludeUserActions'))
                IncludeAuthenticationContextClassReferences = @(Get-CAANestedValue $policy @('Conditions', 'Applications', 'IncludeAuthenticationContextClassReferences'))
            }
            ClientApplications         = @{
                IncludeServicePrincipals = @(Get-CAANestedValue $policy @('Conditions', 'ClientApplications', 'IncludeServicePrincipals'))
                ExcludeServicePrincipals = @(Get-CAANestedValue $policy @('Conditions', 'ClientApplications', 'ExcludeServicePrincipals'))
            }
            SignInRiskLevels           = @(Get-CAANestedValue $policy @('Conditions', 'SignInRiskLevels'))
            UserRiskLevels             = @(Get-CAANestedValue $policy @('Conditions', 'UserRiskLevels'))
            ServicePrincipalRiskLevels = @(Get-CAANestedValue $policy @('Conditions', 'ServicePrincipalRiskLevels'))
            InsiderRiskLevels          = Get-CAANestedValue $policy @('Conditions', 'InsiderRiskLevels')
            AuthenticationFlows        = Get-CAANestedValue $policy @('Conditions', 'AuthenticationFlows')
            ClientAppTypes             = @(Get-CAANestedValue $policy @('Conditions', 'ClientAppTypes'))
            Locations                  = @{
                IncludeLocations = @(Get-CAANestedValue $policy @('Conditions', 'Locations', 'IncludeLocations'))
                ExcludeLocations = @(Get-CAANestedValue $policy @('Conditions', 'Locations', 'ExcludeLocations'))
            }
            Platforms                  = @{
                IncludePlatforms = @(Get-CAANestedValue $policy @('Conditions', 'Platforms', 'IncludePlatforms'))
                ExcludePlatforms = @(Get-CAANestedValue $policy @('Conditions', 'Platforms', 'ExcludePlatforms'))
            }
            Devices                    = @{
                IncludeDevices = @(Get-CAANestedValue $policy @('Conditions', 'Devices', 'IncludeDevices'))
                ExcludeDevices = @(Get-CAANestedValue $policy @('Conditions', 'Devices', 'ExcludeDevices'))
                DeviceFilter   = Get-CAANestedValue $policy @('Conditions', 'Devices', 'DeviceFilter')
            }
        }

        # Normalize grant controls, including authentication strengths. Microsoft
        # Graph models authentication strength as a relationship on grantControls;
        # it can satisfy MFA without listing `mfa` in builtInControls.
        $grantControls = @{
            Operator                  = Get-CAANestedValue $policy @('GrantControls', 'Operator')
            BuiltInControls           = @(Get-CAANestedValue $policy @('GrantControls', 'BuiltInControls'))
            CustomAuthenticationFactors = @(Get-CAANestedValue $policy @('GrantControls', 'CustomAuthenticationFactors'))
            TermsOfUse                = @(Get-CAANestedValue $policy @('GrantControls', 'TermsOfUse'))
            AuthenticationStrength    = Get-CAANestedValue $policy @('GrantControls', 'AuthenticationStrength')
        }

        # Normalize session controls, including current v1.0 controls used for
        # CAE/resilience and app-enforced restrictions.
        $sessionControls = @{
            SignInFrequency  = @{
                IsEnabled = if (Get-CAANestedValue $policy @('SessionControls', 'SignInFrequency')) { Get-CAANestedValue $policy @('SessionControls', 'SignInFrequency', 'IsEnabled') } else { $false }
                Value     = Get-CAANestedValue $policy @('SessionControls', 'SignInFrequency', 'Value')
                Type      = Get-CAANestedValue $policy @('SessionControls', 'SignInFrequency', 'Type')
            }
            PersistentBrowser = @{
                IsEnabled = if (Get-CAANestedValue $policy @('SessionControls', 'PersistentBrowser')) { Get-CAANestedValue $policy @('SessionControls', 'PersistentBrowser', 'IsEnabled') } else { $false }
                Mode      = Get-CAANestedValue $policy @('SessionControls', 'PersistentBrowser', 'Mode')
            }
            ApplicationEnforcedRestrictions = Get-CAANestedValue $policy @('SessionControls', 'ApplicationEnforcedRestrictions')
            CloudAppSecurity                = Get-CAANestedValue $policy @('SessionControls', 'CloudAppSecurity')
            DisableResilienceDefaults       = Get-CAANestedValue $policy @('SessionControls', 'DisableResilienceDefaults')
        }

        $baselineObjects += @{
            PolicyId          = $policy.Id
            DisplayName       = $policy.DisplayName
            State             = $policy.State
            Conditions        = $conditions
            GrantControls     = $grantControls
            SessionControls   = $sessionControls
            Zone              = $zone
            SnapshotTimestamp  = $snapshotTime
        }
    }

    Write-Verbose "Baseline snapshot captured: $($baselineObjects.Count) policies at $snapshotTime"
    return $baselineObjects
}
