#Requires -Version 7.1
#Requires -Modules @{ ModuleName = "Microsoft.Graph.Identity.SignIns"; ModuleVersion = "2.0.0" }
#Requires -Modules @{ ModuleName = "Az.Accounts"; ModuleVersion = "3.0.0" }

<#
.SYNOPSIS
    Azure Automation runbook for CA policy compliance validation and drift detection.

.DESCRIPTION
    Adapts Test-PolicyCompliance.ps1 and Watch-PolicyDrift.ps1 for Azure Automation
    execution context. This runbook provides non-interactive certificate-based
    authentication, structured JSON output to the pipeline, and drift detection
    against Dataverse-stored baselines.

    Key differences from the interactive scripts:
    - Uses managed identity first for unattended authentication
    - Falls back to certificate-based app-only authentication when requested
    - Reads operational parameters from Dataverse environment variables
    - Persists validation history and violations to Dataverse via CAAClient
    - Outputs JSON to pipeline (captured by Get-AzAutomationJobOutput)
    - Includes AlertRequired flag for Power Automate flow routing
    - No Write-Host (uses Write-Verbose for diagnostics)

    Output structure enables Power Automate HTTP webhook actions to parse validation
    results and route alerts based on severity and drift status.

.PARAMETER TenantId
    Entra ID tenant GUID.

.PARAMETER ClientId
    App registration client ID for certificate-based Graph auth, or user-assigned managed identity client ID when -UseManagedIdentity is specified.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for certificate-based unattended authentication. Certificate must be uploaded to the Azure Automation account. Certificate auth is a fallback when managed identity is unavailable.

.PARAMETER ConfigPath
    Path to the tenant configuration JSON file within the Automation account.
    Must contain breakGlassAccounts array and optional policyPrefix.

.PARAMETER DataverseUrl
    Dataverse environment URL for writing compliance results.
    Example: https://governance.crm.dynamics.com

.PARAMETER Zone
    Optional. Governance zone filter (1, 2, or 3) for targeted scans.

.PARAMETER Scope
    Optional. Scan scope — 'Full' (default) or 'Targeted'.

.EXAMPLE
    Start-CAAValidationRunbook `
        -TenantId "00000000-0000-0000-0000-000000000000" `
        -UseManagedIdentity `
        -ConfigPath "./config.json" `
        -DataverseUrl "https://governance.crm.dynamics.com"

    Runs full validation using the Azure Automation system-assigned managed identity and outputs JSON.

.EXAMPLE
    Start-CAAValidationRunbook `
        -TenantId "00000000-0000-0000-0000-000000000000" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -ConfigPath "./config.json" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Zone 3 -Scope Targeted

    Runs targeted validation for Zone 3 policies only.

.OUTPUTS
    JSON object with properties:
    - RunId: Unique GUID for this validation run
    - Timestamp: ISO 8601 UTC timestamp
    - TenantId: Tenant that was scanned
    - ScanScope: Full or Targeted
    - OverallStatus: Passed | Warning | Failed | Error
    - OverallSeverity: Info | Warning | High | Critical
    - TotalPolicies: Count of checks performed
    - PassedCount: Checks that passed
    - WarningCount: Violations at Warning severity
    - FailedCount: Checks that failed
    - DriftCount: Drift items detected above threshold
    - ComplianceRate: Percentage of checks passed
    - AlertRequired: Boolean flag for flow routing
    - AlertSeverity: Severity for alert priority (None when no alert)
    - ZoneSummary: Array of per-zone status objects
    - Violations: Array of policy violation details
    - DriftItems: Array of drift detection findings

.NOTES
    Version: 1.0.0

    Azure Automation setup:
    1. Import this script as a runbook
    2. Enable a system-assigned managed identity on the Automation Account (or pass -ClientId for a user-assigned identity)
    3. Install required modules: Microsoft.Graph.Identity.SignIns,
       Microsoft.Graph.Authentication, Az.Accounts
    4. Grant application permissions: Policy.Read.All, Application.Read.All
    5. Upload tenant config JSON as Automation Account asset
    6. Schedule via Schedules or trigger via webhook

    This runbook connects to Microsoft Graph and Dataverse with managed identity when available. Certificate-based app-only authentication remains available for tenants that have not enabled Azure managed identities yet.
#>

[CmdletBinding(DefaultParameterSetName = 'ManagedIdentity')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'PSScriptAnalyzer honors this rule at script or function scope; flagged compatibility parameters below include individual justifications.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'h',
    Justification = 'Variable is initialized in ForEach-Object -Begin and read in -Process/-End at line 354; PSSA static analysis misses child scriptblock reads.'
)]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory, ParameterSetName = 'Certificate')]
    [Parameter(ParameterSetName = 'ManagedIdentity')]
    [string]$ClientId,

    [Parameter(Mandatory, ParameterSetName = 'Certificate')]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory, ParameterSetName = 'ManagedIdentity')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Required by the authentication parameter-set contract; the selected parameter set drives behavior in this implementation.'
    )]
    [switch]$UseManagedIdentity,

    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter(Mandatory)]
    [string]$DataverseUrl,

    [Parameter()]
    [int]$Zone,

    [Parameter()]
    [ValidateSet('Full', 'Targeted')]
    [string]$Scope = 'Full'
)

$ErrorActionPreference = "Stop"

function Test-CAAAuthStrengthSatisfiesMfa {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [object]$AuthenticationStrength)

    if ($null -eq $AuthenticationStrength) { return $false }

    $requirements = $null
    if ($AuthenticationStrength -is [hashtable]) {
        $requirements = $AuthenticationStrength['requirementsSatisfied']
        if (-not $requirements) { $requirements = $AuthenticationStrength['RequirementsSatisfied'] }
    }
    else {
        $requirements = ($AuthenticationStrength.PSObject.Properties['RequirementsSatisfied']).Value
        if (-not $requirements) { $requirements = ($AuthenticationStrength.PSObject.Properties['requirementsSatisfied']).Value }
        if (-not $requirements -and $AuthenticationStrength.AdditionalProperties) {
            $requirements = $AuthenticationStrength.AdditionalProperties['requirementsSatisfied']
        }
    }

    if ($requirements -eq 'mfa') { return $true }

    $displayName = $null
    if ($AuthenticationStrength -is [hashtable]) {
        $displayName = $AuthenticationStrength['displayName']
        if (-not $displayName) { $displayName = $AuthenticationStrength['DisplayName'] }
    }
    else {
        $displayName = ($AuthenticationStrength.PSObject.Properties['DisplayName']).Value
        if (-not $displayName) { $displayName = ($AuthenticationStrength.PSObject.Properties['displayName']).Value }
        if (-not $displayName -and $AuthenticationStrength.AdditionalProperties) {
            $displayName = $AuthenticationStrength.AdditionalProperties['displayName']
        }
    }

    return ($displayName -match '(?i)mfa|multifactor|phishing-resistant|passwordless')
}

try {
    $runId = [guid]::NewGuid().ToString()
    $scriptRoot = $PSScriptRoot

    Write-Verbose "Starting CAA validation runbook (RunId: $runId)"
    Write-Verbose "TenantId: $TenantId | Scope: $Scope | Zone: $(if ($Zone) { $Zone } else { 'All' })"

    #region Authenticate

    if ($PSCmdlet.ParameterSetName -eq 'ManagedIdentity') {
        $azIdentityParams = @{}
        $graphIdentityParams = @{ Identity = $true; ErrorAction = 'Stop' }
        if ($ClientId) {
            $azIdentityParams['AccountId'] = $ClientId
            $graphIdentityParams['ClientId'] = $ClientId
            Write-Verbose "Using user-assigned managed identity: $ClientId"
        }
        else {
            Write-Verbose "Using system-assigned managed identity"
        }

        Connect-AzAccount -Identity -TenantId $TenantId @azIdentityParams -ErrorAction Stop | Out-Null
        $tokenResponse = Get-AzAccessToken -ResourceUrl $DataverseUrl -AsSecureString -ErrorAction Stop
        $dataverseToken = [System.Net.NetworkCredential]::new('', $tokenResponse.Token).Password
        Write-Verbose "Dataverse token acquired via managed identity"

        Connect-MgGraph @graphIdentityParams | Out-Null
        Write-Verbose "Microsoft Graph session established (managed identity)"
    }
    else {
        # Certificate auth remains available for tenants that have not enabled
        # managed identities yet.
        Import-Module MSAL.PS -ErrorAction Stop

        $cert = Get-Item "Cert:\LocalMachine\My\$CertificateThumbprint" -ErrorAction Stop
        Write-Verbose "Certificate found: $($cert.Subject)"

        $dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"
        $tokenResult = Get-MsalToken `
            -ClientId $ClientId `
            -ClientCertificate $cert `
            -TenantId $TenantId `
            -Scopes $dataverseScope `
            -ErrorAction Stop
        $dataverseToken = $tokenResult.AccessToken
        Write-Verbose "Dataverse token acquired via certificate auth"

        Connect-MgGraph `
            -TenantId $TenantId `
            -ClientId $ClientId `
            -CertificateThumbprint $CertificateThumbprint `
            -ErrorAction Stop | Out-Null
        Write-Verbose "Microsoft Graph session established (certificate auth)"
    }

    #endregion

    #region Connect CAAClient to Dataverse

    Import-Module "$scriptRoot/private/CAAClient.psm1" -Force

    # Wrap all Dataverse calls in try/catch so the runbook still produces
    # valid output when the CAAClient connection is unavailable.
    $dataverseAvailable = $false
    try {
        Connect-CAADataverse -DataverseUrl $DataverseUrl -TenantId $TenantId -AccessToken $dataverseToken
        $dataverseAvailable = $true
        Write-Verbose "Dataverse connection established"
    } catch {
        Write-Verbose "CAAClient not available: $($_.Exception.Message)"
    }

    # Read operational parameters from Dataverse environment variables (with defaults).
    # NOTE: env var names below MUST match what scripts/create_caa_environment_variables.py
    # actually creates (full SchemaName with `fsi_CAA_` prefix). Earlier versions used
    # bare names like `SeverityThreshold` which never resolved against Dataverse.
    $severityThreshold = 'Warning'
    $includeReportOnly = $false
    $baselineMaxAgeDays = 30

    if ($dataverseAvailable) {
        # SeverityThreshold has no dedicated Dataverse env var; consumers can override
        # via the -SeverityThreshold parameter on Test-CAAPolicyCompliance directly.
        # The closest env var is fsi_CAA_DriftSeverityEscalation, which is a Zone-3
        # escalation flag, not a threshold value, so it intentionally is NOT used here.

        try {
            $dvReportOnly = Get-CAAEnvironmentVariable -VariableName 'fsi_CAA_IncludeReportOnlyPolicies'
            if ($dvReportOnly -eq 'true' -or $dvReportOnly -eq $true) {
                $includeReportOnly = $true
                Write-Verbose "Dataverse override: fsi_CAA_IncludeReportOnlyPolicies=true"
            }
        } catch { Write-Verbose "fsi_CAA_IncludeReportOnlyPolicies env var not available: $($_.Exception.Message)" }

        try {
            $dvMaxAge = Get-CAAEnvironmentVariable -VariableName 'fsi_CAA_BaselineMaxAgeDays'
            if ($dvMaxAge) {
                $baselineMaxAgeDays = [int]$dvMaxAge
                Write-Verbose "Dataverse override: fsi_CAA_BaselineMaxAgeDays=$baselineMaxAgeDays"
            }
        } catch { Write-Verbose "fsi_CAA_BaselineMaxAgeDays env var not available: $($_.Exception.Message)" }
    }

    Write-Verbose "Parameters: SeverityThreshold=$severityThreshold, IncludeReportOnly=$includeReportOnly, BaselineMaxAgeDays=$baselineMaxAgeDays"

    #endregion

    #region Dot-source private helpers

    # Import helpers directly (skip Connect-GraphSession.ps1 since we use cert auth)
    . "$scriptRoot/private/Get-ZoneClassification.ps1"
    . "$scriptRoot/private/Get-PolicyBaseline.ps1"
    . "$scriptRoot/private/Compare-PolicyBaseline.ps1"

    #endregion

    #region Load configuration

    Write-Verbose "Loading configuration from $ConfigPath"
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    $config = Get-Content $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json

    #endregion

    #region Retrieve CA policies from Graph

    Write-Verbose "Retrieving Conditional Access policies from Microsoft Graph"
    $allPolicies = Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop

    $fsiPolicies = @($allPolicies | Where-Object {
        $_.DisplayName -like "CA-FSI-*" -or
        $_.DisplayName -like "CA-CopilotStudio-*" -or
        $_.DisplayName -like "CA-AgentBuilder-*" -or
        $_.DisplayName -like "CA-M365Copilot-*" -or
        $_.DisplayName -like "CA-BlockLegacyAuth-*" -or
        $_.DisplayName -like "CA-RequireCompliantDevice-*" -or
        ($config.policyPrefix -and $_.DisplayName -like "$($config.policyPrefix)-*")
    })

    Write-Verbose "Found $($fsiPolicies.Count) FSI policies out of $($allPolicies.Count) total"

    # Apply zone filter if targeted
    if ($Zone) {
        $zoneLabel = "Zone$Zone"
        $fsiPolicies = @($fsiPolicies | Where-Object { $_.DisplayName -match $zoneLabel })
        Write-Verbose "Zone $Zone filter applied: $($fsiPolicies.Count) policies remaining"
    }

    #endregion

    #region Compliance checks (condensed from Test-PolicyCompliance.ps1)

    # Expected policy patterns per zone
    $expectedPolicies = @{
        "Zone1" = @(
            @{ Pattern = "*CopilotStudio*Zone1*"; Required = $true }
            @{ Pattern = "*AgentBuilder*Zone1*"; Required = $true }
        )
        "Zone2" = @(
            @{ Pattern = "*CopilotStudio*Zone2*"; Required = $true }
            @{ Pattern = "*AgentBuilder*Zone2*"; Required = $true }
        )
        "Zone3" = @(
            @{ Pattern = "*CopilotStudio*Zone3*"; Required = $true }
            @{ Pattern = "*AgentBuilder*Zone3*"; Required = $true }
            @{ Pattern = "*CompliantDevice*Zone3*"; Required = $true }
        )
        "Common" = @(
            @{ Pattern = "*M365Copilot*"; Required = $true }
            @{ Pattern = "*BlockLegacyAuth*"; Required = $true }
        )
    }

    # If zone-targeted, keep only the relevant zone (plus Common)
    if ($Zone) {
        $zoneLabel = "Zone$Zone"
        $targetZones = @($zoneLabel, 'Common')
        $expectedPolicies = $expectedPolicies.GetEnumerator() |
            Where-Object { $_.Key -in $targetZones } |
            ForEach-Object -Begin { $h = @{} } -Process { $h[$_.Key] = $_.Value } -End { $h }
    }

    $checksPerformed = 0
    $checksPassed = 0
    $checksFailed = 0
    $gaps = [System.Collections.Generic.List[hashtable]]::new()
    $coverage = @{
        zone1  = @{ status = "Unknown"; policies = @() }
        zone2  = @{ status = "Unknown"; policies = @() }
        zone3  = @{ status = "Unknown"; policies = @() }
        common = @{ status = "Unknown"; policies = @() }
    }

    # Check 1: Policy Existence
    Write-Verbose "Check 1: Policy existence"
    foreach ($zoneKey in $expectedPolicies.Keys) {
        foreach ($expected in $expectedPolicies[$zoneKey]) {
            $checksPerformed++
            $matched = @($fsiPolicies | Where-Object { $_.DisplayName -like $expected.Pattern })

            if ($matched.Count -gt 0) {
                $checksPassed++
                $zoneLower = $zoneKey.ToLower()
                if ($coverage.ContainsKey($zoneLower)) {
                    $coverage[$zoneLower].policies += @($matched | ForEach-Object { $_.DisplayName })
                }
            } else {
                $checksFailed++
                $gaps.Add(@{
                    type           = "MissingPolicy"
                    pattern        = $expected.Pattern
                    zone           = $zoneKey
                    recommendation = "Create policy matching pattern: $($expected.Pattern)"
                })
            }
        }
    }

    # Check 2: Policy State
    Write-Verbose "Check 2: Policy state"
    foreach ($policy in $fsiPolicies) {
        $checksPerformed++
        $isEnabled = $policy.State -eq "enabled"
        $isReportOnly = $policy.State -eq "enabledForReportingButNotEnforced"

        if ($isEnabled -or ($includeReportOnly -and $isReportOnly)) {
            $checksPassed++
        } elseif ($isReportOnly) {
            $checksFailed++
            $gaps.Add(@{
                type           = "PolicyNotEnabled"
                policy         = $policy.DisplayName
                policyId       = $policy.Id
                currentState   = $policy.State
                zone           = if ($policy.DisplayName -match 'Zone(\d)') { "Zone$($Matches[1])" } else { "Common" }
                recommendation = "Enable policy for enforcement"
            })
        } else {
            $checksFailed++
            $gaps.Add(@{
                type           = "PolicyDisabled"
                policy         = $policy.DisplayName
                policyId       = $policy.Id
                currentState   = $policy.State
                zone           = if ($policy.DisplayName -match 'Zone(\d)') { "Zone$($Matches[1])" } else { "Common" }
                recommendation = "Review and enable policy"
            })
        }
    }

    # Check 3: Break-Glass Exclusions
    Write-Verbose "Check 3: Break-glass exclusions"
    $breakGlassAccounts = @()
    if ($config.breakGlassAccounts) { $breakGlassAccounts = @($config.breakGlassAccounts) }

    if ($breakGlassAccounts.Count -gt 0) {
        foreach ($policy in $fsiPolicies) {
            $checksPerformed++
            $excludedUsers = @($policy.Conditions.Users.ExcludeUsers)
            $allExcluded = $true

            foreach ($bgAccount in $breakGlassAccounts) {
                if ($bgAccount -notin $excludedUsers) {
                    $allExcluded = $false
                    break
                }
            }

            if ($allExcluded) {
                $checksPassed++
            } else {
                $checksFailed++
                $gaps.Add(@{
                    type           = "MissingBreakGlassExclusion"
                    policy         = $policy.DisplayName
                    policyId       = $policy.Id
                    zone           = if ($policy.DisplayName -match 'Zone(\d)') { "Zone$($Matches[1])" } else { "Common" }
                    recommendation = "Add all break-glass accounts to exclusion list"
                })
            }
        }
    }

    # Check 4: MFA Grant Controls
    Write-Verbose "Check 4: MFA grant controls"
    foreach ($policy in $fsiPolicies) {
        if ($policy.GrantControls.BuiltInControls -contains "block") { continue }
        $checksPerformed++

        $authStrength = $policy.GrantControls.AuthenticationStrength
        $hasMfaStrength = Test-CAAAuthStrengthSatisfiesMfa -AuthenticationStrength $authStrength
        if (($policy.GrantControls.BuiltInControls -contains "mfa") -or $hasMfaStrength) {
            $checksPassed++
        } else {
            $checksFailed++
            $gaps.Add(@{
                type                   = "NoMFARequirement"
                policy                 = $policy.DisplayName
                policyId               = $policy.Id
                zone                   = if ($policy.DisplayName -match 'Zone(\d)') { "Zone$($Matches[1])" } else { "Common" }
                grantControls          = $policy.GrantControls.BuiltInControls
                authenticationStrength = $authStrength
                recommendation         = "Add MFA or an MFA-satisfying authentication strength to grant controls"
            })
        }
    }

    # Check 5: Session Controls
    Write-Verbose "Check 5: Session controls"
    foreach ($policy in $fsiPolicies) {
        if ($policy.GrantControls.BuiltInControls -contains "block") { continue }
        $checksPerformed++

        $sc = $policy.SessionControls
        $hasSignInFreq = $sc -and $sc.SignInFrequency -and $sc.SignInFrequency.IsEnabled -eq $true
        $hasPersistentBrowser = $sc -and $sc.PersistentBrowser -and $sc.PersistentBrowser.IsEnabled -eq $true
        $isZone3 = $policy.DisplayName -like "*Zone3*"

        if ($hasSignInFreq) {
            if ($isZone3 -and $hasPersistentBrowser -and $sc.PersistentBrowser.Mode -ne "never") {
                $checksFailed++
                $gaps.Add(@{
                    type           = "SessionControlMisconfigured"
                    policy         = $policy.DisplayName
                    policyId       = $policy.Id
                    zone           = "Zone3"
                    detail         = "persistentBrowser.mode is '$($sc.PersistentBrowser.Mode)', expected 'never'"
                    recommendation = "Set persistentBrowser.mode to 'never' for Zone3 policies"
                })
            } elseif ($isZone3 -and -not $hasPersistentBrowser) {
                $checksFailed++
                $gaps.Add(@{
                    type           = "MissingSessionControl"
                    policy         = $policy.DisplayName
                    policyId       = $policy.Id
                    zone           = "Zone3"
                    detail         = "Zone3 policy should have persistentBrowser set to 'never'"
                    recommendation = "Add persistentBrowser session control with mode 'never'"
                })
            } else {
                $checksPassed++
            }
        } else {
            $checksFailed++
            $gaps.Add(@{
                type           = "MissingSessionControl"
                policy         = $policy.DisplayName
                policyId       = $policy.Id
                zone           = if ($policy.DisplayName -match 'Zone(\d)') { "Zone$($Matches[1])" } else { "Common" }
                detail         = "signInFrequency not configured or not enabled"
                recommendation = "Configure sign-in frequency for session timeout enforcement"
            })
        }
    }

    # Determine zone coverage status
    foreach ($zoneKey in @("zone1", "zone2", "zone3", "common")) {
        $coverage[$zoneKey].status = if ($coverage[$zoneKey].policies.Count -gt 0) { "Covered" } else { "NotCovered" }
    }

    $complianceRate = if ($checksPerformed -gt 0) {
        [math]::Round(($checksPassed / $checksPerformed) * 100, 2)
    } else { 0 }

    $overallCompliance = if ($complianceRate -ge 95) { "Compliant" }
        elseif ($complianceRate -ge 80) { "PartiallyCompliant" }
        else { "NonCompliant" }

    Write-Verbose "Compliance: $overallCompliance ($complianceRate%) — $checksPerformed checks, $checksPassed passed, $checksFailed failed"

    #endregion

    #region Drift detection against Dataverse baseline

    Write-Verbose "Running drift detection against active Dataverse baseline"

    $severityMap = @{ 'Passed' = 1; 'Warning' = 2; 'GracePeriod' = 3; 'Failed' = 4; 'Error' = 5 }
    $thresholdNum = $severityMap[$severityThreshold]
    if (-not $thresholdNum) { $thresholdNum = 2 }

    $driftItems = [System.Collections.Generic.List[object]]::new()

    try {
        $activeBaseline = if ($dataverseAvailable) { Get-CAAActiveBaseline } else { $null }

        if ($activeBaseline -and $activeBaseline.Count -gt 0) {
            $bl = $activeBaseline | Select-Object -First 1

            if (-not $bl) {
                Write-Verbose "No active baseline found — skipping drift detection"
                $driftItems = [System.Collections.Generic.List[object]]::new()
            }
            else {
                # Retrieve previous policies from the baseline record
                $previousPolicies = if ($bl.Policies) { @($bl.Policies) }
                    elseif ($bl.policies) { @($bl.policies) }
                    else { @() }

                # Check baseline staleness
                $isStale = $false
                $capturedAtProp = if ($bl.CapturedAt) { $bl.CapturedAt } elseif ($bl.capturedAt) { $bl.capturedAt } else { $null }
                if ($capturedAtProp) {
                    $capturedAt = [datetime]$capturedAtProp
                    $ageInDays = ((Get-Date).ToUniversalTime() - $capturedAt).TotalDays
                    if ($ageInDays -gt $baselineMaxAgeDays) {
                        Write-Verbose "Stale baseline: $([math]::Round($ageInDays, 1)) days old (max: $baselineMaxAgeDays)"
                        $isStale = $true
                    }
                }

                if ($previousPolicies.Count -gt 0) {
                    # Get current normalized policy state for comparison
                    $baselineParams = @{}
                    if ($config.policyPrefix) { $baselineParams['PolicyNamePrefix'] = $config.policyPrefix }
                    if ($ConfigPath) { $baselineParams['ConfigPath'] = $ConfigPath }
                    $currentBaseline = Get-CAAPolicyBaseline @baselineParams

                    # Compare baselines
                    $allDrifts = Compare-CAAPolicyBaseline `
                        -PreviousBaseline $previousPolicies `
                        -CurrentBaseline @($currentBaseline)

                    $filteredDrifts = @($allDrifts | Where-Object {
                        $_.DriftType -ne 'None' -and $_.Severity -ge $thresholdNum
                    })

                    foreach ($d in $filteredDrifts) { $driftItems.Add($d) }
                    Write-Verbose "Drift detection: $($driftItems.Count) items above $severityThreshold threshold"
                } else {
                    Write-Verbose "Active baseline has no policy data — skipping comparison"
                }

                if ($isStale) {
                    $driftItems.Add(@{
                        PolicyName  = 'N/A'
                        DriftType   = 'StaleBaseline'
                        Severity    = 2
                        Zone        = 'All'
                        Dimension   = 'Baseline'
                        Expected    = "< $baselineMaxAgeDays days"
                        Actual      = "$([math]::Round($ageInDays, 1)) days"
                        Description = "Active baseline exceeds maximum age ($baselineMaxAgeDays days)"
                    })
                }
            }
        } else {
            Write-Verbose "No active baseline found in Dataverse — skipping drift detection"
        }
    } catch {
        Write-Verbose "Drift detection failed: $($_.Exception.Message). Continuing without drift data."
    }

    $driftCount = $driftItems.Count

    #endregion

    #region Build violations array

    $violations = [System.Collections.Generic.List[object]]::new()
    foreach ($gap in $gaps) {
        $violations.Add([PSCustomObject]@{
            PolicyName = if ($gap.ContainsKey('policy')) { $gap.policy } else { $gap.pattern }
            PolicyId   = if ($gap.ContainsKey('policyId')) { $gap.policyId } else { '' }
            Zone       = if ($gap.ContainsKey('zone')) { $gap.zone } else { '' }
            Type       = $gap.type
            Detail     = if ($gap.ContainsKey('detail')) { $gap.detail } else { $gap.recommendation }
            Expected   = $gap.recommendation
            Actual     = if ($gap.ContainsKey('currentState')) { $gap.currentState }
                         elseif ($gap.ContainsKey('detail')) { $gap.detail }
                         else { 'Non-compliant' }
            Severity   = switch ($gap.type) {
                'PolicyDisabled'              { 'Critical' }
                'MissingPolicy'               { 'High' }
                'MissingBreakGlassExclusion'  { 'High' }
                'NoMFARequirement'            { 'High' }
                'MissingSessionControl'       { 'Warning' }
                'SessionControlMisconfigured' { 'Warning' }
                'PolicyNotEnabled'            { 'Warning' }
                'PolicyDrift'                 { 'Warning' }
                default                       { 'Info' }
            }
        })
    }

    #endregion

    #region Persist results to Dataverse

    # Map overall status for Dataverse and output
    $overallStatus = switch ($overallCompliance) {
        'Compliant'          { 'Passed' }
        'PartiallyCompliant' { 'Warning' }
        'NonCompliant'       { 'Failed' }
        default              { 'Warning' }
    }

    # Determine overall severity from worst violation
    $severityOrder = @('Critical', 'High', 'Warning', 'Info')
    $overallSeverity = 'Info'
    if ($violations.Count -gt 0) {
        foreach ($sev in $severityOrder) {
            if ($violations.Severity -contains $sev) {
                $overallSeverity = $sev
                break
            }
        }
    }
    if ($driftCount -gt 0 -and $overallSeverity -eq 'Info') {
        $overallSeverity = 'Warning'
    }

    if ($dataverseAvailable) {
        # Write validation history
        $validatedBy = if ($ClientId) { "$ClientId (runbook)" } else { "managed-identity (runbook)" }
        try {
            Write-CAAValidationHistory -Record @{
                RunId          = $runId
                OverallStatus  = $overallStatus
                TotalPolicies  = $checksPerformed
                CompliantCount = $checksPassed
                ViolationCount = $checksFailed
                DriftCount     = $driftCount
                ScanScope      = $Scope
                ComplianceRate = $complianceRate
                ValidatedBy    = $validatedBy
                TenantId       = $TenantId
            }
            Write-Verbose "Validation history persisted to Dataverse"
        } catch {
            Write-Verbose "Failed to write validation history: $($_.Exception.Message)"
        }

        # Write individual violation records
        foreach ($v in $violations) {
            try {
                Write-CAAViolation -Violation @{
                    RunId         = $runId
                    PolicyName    = $v.PolicyName
                    PolicyId      = $v.PolicyId
                    Zone          = $v.Zone
                    ViolationType = $v.Type
                    Expected      = $v.Expected
                    Actual        = $v.Actual
                    Severity      = $v.Severity
                    TenantId      = $TenantId
                }
            } catch {
                Write-Verbose "Failed to write violation for $($v.PolicyName): $($_.Exception.Message)"
            }
        }
        Write-Verbose "Violation records persisted ($($violations.Count) items)"
    }

    #endregion

    #region Build zone summary

    $zoneSummary = @()
    foreach ($zoneKey in @('zone1', 'zone2', 'zone3', 'common')) {
        $zoneCoverage = $coverage[$zoneKey]
        $zoneViolations = @($violations | Where-Object {
            $_.Zone -eq $zoneKey -or $_.Zone -eq ($zoneKey.Substring(0,1).ToUpper() + $zoneKey.Substring(1))
        })
        $zoneSummary += [PSCustomObject]@{
            Zone       = $zoneKey.Substring(0,1).ToUpper() + $zoneKey.Substring(1)
            Status     = $zoneCoverage.status
            Policies   = $zoneCoverage.policies.Count
            Violations = $zoneViolations.Count
        }
    }

    #endregion

    #region Build and emit output

    $alertRequired = ($violations.Count -gt 0) -or ($driftCount -gt 0)

    $output = [PSCustomObject]@{
        RunId           = $runId
        Timestamp       = (Get-Date).ToUniversalTime().ToString('o')
        TenantId        = $TenantId
        ScanScope       = $Scope
        OverallStatus   = $overallStatus
        OverallSeverity = $overallSeverity
        TotalPolicies   = $checksPerformed
        PassedCount     = $checksPassed
        WarningCount    = @($violations | Where-Object { $_.Severity -eq 'Warning' }).Count
        FailedCount     = $checksFailed
        DriftCount      = $driftCount
        ComplianceRate  = $complianceRate
        AlertRequired   = $alertRequired
        AlertSeverity   = if ($alertRequired) { $overallSeverity } else { 'None' }
        ZoneSummary     = $zoneSummary
        Violations      = @($violations)
        DriftItems      = @($driftItems)
    }

    Write-Verbose "Alert required: $alertRequired | Severity: $($output.AlertSeverity)"

    # This is the ONLY pipeline output — Azure Automation captures it as job output
    $jsonOutput = $output | ConvertTo-Json -Depth 10
    Write-Verbose "JSON output length: $($jsonOutput.Length) characters"
    $jsonOutput

    #endregion

} catch {
    Write-Verbose "Runbook error: $($_.Exception.Message)"

    # Standardized error JSON so Power Automate flows receive a parseable structure
    $errorOutput = [PSCustomObject]@{
        RunId           = if ($runId) { $runId } else { [guid]::NewGuid().ToString() }
        Timestamp       = (Get-Date).ToUniversalTime().ToString('o')
        TenantId        = $TenantId
        ScanScope       = $Scope
        OverallStatus   = 'Error'
        OverallSeverity = 'Critical'
        TotalPolicies   = 0
        PassedCount     = 0
        WarningCount    = 0
        FailedCount     = 0
        DriftCount      = 0
        ComplianceRate  = 0
        AlertRequired   = $true
        AlertSeverity   = 'Critical'
        ZoneSummary     = @()
        Violations      = @()
        DriftItems      = @()
        Error           = @{
            Message    = $_.Exception.Message
            Type       = $_.Exception.GetType().FullName
            StackTrace = $_.ScriptStackTrace
        }
    }

    $errorOutput | ConvertTo-Json -Depth 5
}
