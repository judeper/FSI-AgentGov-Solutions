#Requires -Version 7.0

<#
.SYNOPSIS
    Validates authentication readiness for unattended agent-intake lab runs.

.DESCRIPTION
    Runs preflight checks to detect conditions that would cause an unattended lab deployment to
    hang or fail. Validates Conditional Access policies, token acquisition, PAC CLI behavior,
    environment SKU, and required modules. Exits non-zero only on hard failures (cannot acquire
    or verify tokens); warnings keep exit 0.

.PARAMETER EnvironmentUrl
    Dataverse environment URL (e.g., https://contoso-dev.crm.dynamics.com).

.PARAMETER EnvironmentId
    Optional. Environment ID (GUID). If not provided, the script will attempt to resolve it
    from the environment URL.

.PARAMETER TenantId
    Optional. Microsoft Entra tenant ID (GUID). If not provided, the script will attempt to
    resolve it from the current az CLI session.

.PARAMETER SkipPurviewLabel
    When set, skips the ExchangeOnlineManagement module check (Stage 3 Purview label step will
    not run).

.EXAMPLE
    .\Test-LabAuthReadiness.ps1 -EnvironmentUrl https://contoso-dev.crm.dynamics.com

.EXAMPLE
    .\Test-LabAuthReadiness.ps1 `
        -EnvironmentUrl https://contoso-dev.crm.dynamics.com `
        -EnvironmentId 00000000-0000-0000-0000-000000000000 `
        -SkipPurviewLabel
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$EnvironmentId,

    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$TenantId,

    [switch]$SkipPurviewLabel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$script:WarningCount = 0
$script:ErrorCount = 0

function Write-CheckStart {
    param([string]$Name)
    Write-Information "`n🔍 $Name..."
}

function Write-CheckPass {
    param([string]$Message)
    Write-Information "   ✅ $Message"
}

function Write-CheckWarn {
    param([string]$Message)
    Write-Warning "⚠️  $Message"
    $script:WarningCount++
}

function Write-CheckFail {
    param([string]$Message)
    Write-Error "❌ $Message" -ErrorAction Continue
    $script:ErrorCount++
}

function Test-ConditionalAccessPolicy {
    Write-CheckStart 'Conditional Access policy scan'
    
    try {
        $policiesJson = az rest --url 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-CheckWarn "Could not read Conditional Access policies (requires Policy.Read.All permission). Verify manually that no policies block device-code flow or set signInFrequency < 2 hours for the admin account."
            return
        }
        
        $policies = $policiesJson | ConvertFrom-Json
        $enabledPolicies = $policies.value | Where-Object { $_.state -eq 'enabled' }
        
        if ($enabledPolicies.Count -eq 0) {
            Write-CheckPass "No enabled Conditional Access policies found."
            return
        }
        
        $blockingPolicies = @()
        foreach ($policy in $enabledPolicies) {
            $blocks = $false
            
            # Check for authentication flows restrictions
            if ($policy.conditions.authenticationFlows -and 
                $policy.conditions.authenticationFlows.transferMethods -contains 'deviceCodeFlow' -and
                $policy.grantControls.builtInControls -contains 'block') {
                $blocks = $true
            }
            
            # Check for short sign-in frequency (guard nested properties to avoid null-reference)
            if ($policy.PSObject.Properties.Name -contains 'sessionControls' -and
                $null -ne $policy.sessionControls -and
                $policy.sessionControls.PSObject.Properties.Name -contains 'signInFrequency' -and
                $null -ne $policy.sessionControls.signInFrequency -and
                $policy.sessionControls.signInFrequency.PSObject.Properties.Name -contains 'value' -and
                $policy.sessionControls.signInFrequency.PSObject.Properties.Name -contains 'type' -and
                $policy.sessionControls.signInFrequency.value -lt 2 -and
                $policy.sessionControls.signInFrequency.type -eq 'hours') {
                $blocks = $true
            }
            
            if ($blocks) {
                $blockingPolicies += $policy.displayName
            }
        }
        
        if ($blockingPolicies.Count -gt 0) {
            Write-CheckWarn "Found $($blockingPolicies.Count) Conditional Access policy/policies that may block unattended runs: $($blockingPolicies -join ', '). Verify these policies do not block device-code flow or set signInFrequency < 2 hours for the admin account."
        } else {
            Write-CheckPass "No Conditional Access policies detected that would block unattended authentication."
        }
    }
    catch {
        Write-CheckWarn "CA policy scan failed: $_. Verify manually."
    }
}

function Test-TokenAcquisition {
    Write-CheckStart 'Token acquisition and verification'
    
    # Note: We do NOT clear $env:DATAVERSE_ACCESS_TOKEN or $env:GRAPH_ACCESS_TOKEN here
    # because those are token hooks consumed by other scripts (deploy.ps1, seed-test-data.ps1, etc.).
    # This preflight should never mutate the caller's environment.
    # The token acquisition test below verifies az can acquire tokens without touching those hooks.
    
    try {
        # Acquire Dataverse token
        Write-Information "   Acquiring Dataverse token for $EnvironmentUrl..."
        $dvTokenJson = az account get-access-token --resource $EnvironmentUrl --output json 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-CheckFail "Failed to acquire Dataverse token: $dvTokenJson"
            return $false
        }
        
        $dvToken = ($dvTokenJson | ConvertFrom-Json)
        Write-Information "   Dataverse token expires: $($dvToken.expiresOn)"
        
        # Verify Dataverse token with WhoAmI
        Write-Information "   Verifying Dataverse token with WhoAmI..."
        $whoAmIUrl = "$($EnvironmentUrl.TrimEnd('/'))/api/data/v9.2/WhoAmI"
        $whoAmIResponse = az rest --url $whoAmIUrl --headers "Authorization=Bearer $($dvToken.accessToken)" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-CheckFail "Dataverse token verification failed (WhoAmI returned non-zero): $whoAmIResponse"
            return $false
        }
        
        Write-CheckPass "Dataverse token acquired and verified."
        
        # Acquire Graph token
        Write-Information "   Acquiring Microsoft Graph token..."
        $graphTokenJson = az account get-access-token --resource https://graph.microsoft.com --output json 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-CheckFail "Failed to acquire Microsoft Graph token: $graphTokenJson"
            return $false
        }
        
        $graphToken = ($graphTokenJson | ConvertFrom-Json)
        Write-Information "   Microsoft Graph token expires: $($graphToken.expiresOn)"
        
        # Verify Graph token with /me
        Write-Information "   Verifying Microsoft Graph token with /me..."
        $meResponse = az rest --url 'https://graph.microsoft.com/v1.0/me' --headers "Authorization=Bearer $($graphToken.accessToken)" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-CheckFail "Microsoft Graph token verification failed (/me returned non-zero): $meResponse"
            return $false
        }
        
        Write-CheckPass "Microsoft Graph token acquired and verified."
        return $true
    }
    catch {
        Write-CheckFail "Token acquisition failed with exception: $_"
        return $false
    }
}

function Test-PacFreshShell {
    Write-CheckStart 'PAC CLI fresh-shell test'
    
    # Save original PAC environment variables so we don't mutate the parent shell
    $pacVars = @(
        'PAC_CLI_SPN_SECRET',
        'PAC_CLI_CLOUD',
        'PAC_CLI_PROFILE'
    )
    $savedVals = @{}
    foreach ($varName in $pacVars) {
        if (Test-Path "env:$varName") {
            $savedVals[$varName] = Get-Item "env:$varName" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value
        }
    }
    
    try {
        # Temporarily clear PAC vars for the test
        foreach ($varName in $pacVars) {
            if (Test-Path "env:$varName") {
                Remove-Item "env:$varName" -ErrorAction SilentlyContinue
            }
        }
        
        # Run 'pac auth who' in a child shell with a timeout to avoid hanging.
        # This checks if pac can authenticate in a fresh shell without cached env state.
        # NOTE: This probes the on-disk pac profile cache, not a truly "fresh" state.
        Write-Information "   Running 'pac auth who' in a fresh PowerShell process (30s timeout)..."
        
        $job = Start-Job -ScriptBlock {
            # Redirect stdin from null to avoid interactive prompts
            pwsh -NoProfile -Command "pac auth who < NUL" 2>&1
        }
        
        $completed = Wait-Job -Job $job -Timeout 30
        if ($null -eq $completed) {
            # Timeout reached
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            Write-CheckWarn "PAC CLI fresh-shell test timed out after 30 seconds. This may indicate an interactive auth prompt (WAM/browser hang). Unattended runs may fail."
        }
        else {
            $pacOutput = Receive-Job -Job $job
            $pacExitCode = $job.State -eq 'Completed' ? 0 : 1
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            
            if ($pacExitCode -eq 0) {
                Write-CheckPass "PAC CLI works in a fresh shell without cached env state."
            }
            else {
                $outputStr = $pacOutput -join "`n"
                if ($outputStr -match 'window handle|WAM|browser') {
                    Write-CheckWarn "PAC CLI appears to require interactive authentication (WAM/browser). This is the pac-1.30+ WAM-on-Windows behavior. Unattended runs may hang. Consider downgrading PAC CLI or using device-code flow with pre-authenticated tokens."
                }
                else {
                    Write-CheckWarn "PAC CLI 'auth who' failed in a fresh shell (exit $pacExitCode): $outputStr"
                }
            }
        }
    }
    catch {
        Write-CheckWarn "PAC CLI fresh-shell test threw an exception: $_"
    }
    finally {
        # Restore original PAC environment variables
        foreach ($varName in $pacVars) {
            if ($savedVals.ContainsKey($varName)) {
                [System.Environment]::SetEnvironmentVariable($varName, $savedVals[$varName], 'Process')
            }
        }
    }
}

function Get-EnvironmentSku {
    Write-CheckStart 'Environment SKU detection'
    
    $resolvedEnvId = $EnvironmentId
    
    if ([string]::IsNullOrWhiteSpace($resolvedEnvId)) {
        Write-Information "   Environment ID not provided; attempting to resolve from URL..."
        try {
            # Try to get environment details from BAP
            $envsJson = az rest --url "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2021-04-01" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $envs = ($envsJson | ConvertFrom-Json).value
                $matchedEnv = $envs | Where-Object { $_.properties.linkedEnvironmentMetadata.instanceUrl -eq $EnvironmentUrl.TrimEnd('/') }
                if ($matchedEnv) {
                    $resolvedEnvId = $matchedEnv.name
                    Write-Information "   Resolved environment ID: $resolvedEnvId"
                }
            }
        }
        catch {
            Write-CheckWarn "Could not resolve environment ID from URL. Environment SKU check will be skipped."
            return
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($resolvedEnvId)) {
        Write-CheckWarn "Environment ID could not be resolved. Environment SKU check skipped."
        return
    }
    
    try {
        $envDetailsJson = az rest --url "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$($resolvedEnvId)?api-version=2021-04-01" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-CheckWarn "Could not retrieve environment details from BAP API."
            return
        }
        
        $envDetails = $envDetailsJson | ConvertFrom-Json
        $envType = $envDetails.properties.environmentSku
        
        Write-Information "   Environment SKU: $envType"
        
        if ($envType -in @('Trial', 'Developer', 'Teams', 'Default')) {
            Write-CheckWarn "Environment type '$envType' detected. Pay-as-you-go billing policies cannot be attached to Trial/Developer/Teams environments. Set billing.allowedEnvironmentType='Any' in config.local.json if you want to bypass the SKU guard for testing."
        }
        else {
            Write-CheckPass "Environment SKU '$envType' supports billing policy attachment."
        }
    }
    catch {
        Write-CheckWarn "Environment SKU detection failed: $_"
    }
}

function Test-ExchangeOnlineModule {
    if ($SkipPurviewLabel) {
        Write-Information "`nℹ️  ExchangeOnlineManagement check skipped (-SkipPurviewLabel is set)."
        return
    }
    
    Write-CheckStart 'ExchangeOnlineManagement module presence'
    
    $module = Get-Module -ListAvailable -Name ExchangeOnlineManagement | 
              Sort-Object Version -Descending | 
              Select-Object -First 1
    
    if (-not $module) {
        Write-CheckWarn "ExchangeOnlineManagement module is not installed. Stage 3 (Purview retention label) will require interactive Connect-IPPSSession. Install with: Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser"
    }
    elseif ($module.Version -lt [Version]'3.2.0') {
        Write-CheckWarn "ExchangeOnlineManagement module version $($module.Version) is installed, but < 3.2.0. Stage 3 may require interactive authentication. Update with: Update-Module -Name ExchangeOnlineManagement"
    }
    else {
        Write-CheckPass "ExchangeOnlineManagement module version $($module.Version) is present."
    }
}

function Test-RequiredModules {
    Write-CheckStart 'Required PowerShell modules'
    
    # Az.Accounts (always required)
    $azModule = Get-Module -ListAvailable -Name Az.Accounts | 
                Sort-Object Version -Descending | 
                Select-Object -First 1
    
    if (-not $azModule) {
        Write-CheckFail "Az.Accounts module is not installed. Install with: Install-Module -Name Az.Accounts -Scope CurrentUser"
    }
    elseif ($azModule.Version -lt [Version]'2.0.0') {
        Write-CheckFail "Az.Accounts module version $($azModule.Version) is installed, but < 2.0.0. Update with: Update-Module -Name Az.Accounts"
    }
    else {
        Write-CheckPass "Az.Accounts module version $($azModule.Version) is present."
    }
    
    # powershell-yaml (always required for policy-table parsing)
    $yamlModule = Get-Module -ListAvailable -Name powershell-yaml | 
                  Sort-Object Version -Descending | 
                  Select-Object -First 1
    
    if (-not $yamlModule) {
        Write-CheckFail "powershell-yaml module is not installed. Install with: Install-Module -Name powershell-yaml -Scope CurrentUser"
    }
    elseif ($yamlModule.Version -lt [Version]'0.4.0') {
        Write-CheckFail "powershell-yaml module version $($yamlModule.Version) is installed, but < 0.4.0. Update with: Update-Module -Name powershell-yaml"
    }
    else {
        Write-CheckPass "powershell-yaml module version $($yamlModule.Version) is present."
    }
}

# Main execution
Write-Information "=== Agent Intake Lab Authentication Readiness Check ==="
Write-Information "Environment URL: $EnvironmentUrl"
if ($EnvironmentId) {
    Write-Information "Environment ID: $EnvironmentId"
}
if ($TenantId) {
    Write-Information "Tenant ID: $TenantId"
}
if ($SkipPurviewLabel) {
    Write-Information "Purview label skip: enabled"
}

Test-ConditionalAccessPolicy
Test-TokenAcquisition
Test-PacFreshShell
Get-EnvironmentSku
Test-RequiredModules
Test-ExchangeOnlineModule

Write-Information "`n=== Summary ==="
if ($script:ErrorCount -gt 0) {
    Write-Information "Status: ❌ NOT READY ($($script:ErrorCount) error(s), $($script:WarningCount) warning(s))"
    Write-Information "Action required: Fix the errors above before attempting an unattended lab run."
    exit 1
}
elseif ($script:WarningCount -gt 0) {
    Write-Information "Status: ⚠️  READY WITH WARNINGS ($($script:WarningCount) warning(s))"
    Write-Information "Unattended runs may succeed, but review the warnings above."
    exit 0
}
else {
    Write-Information "Status: ✅ READY"
    Write-Information "All preflight checks passed. The environment is ready for an unattended lab run."
    exit 0
}
