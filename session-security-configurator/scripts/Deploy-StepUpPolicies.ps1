<#
.SYNOPSIS
    Deploys zone-specific step-up session security policies.

.DESCRIPTION
    Deploys Conditional Access policies with zone-appropriate session controls:
    - Zone 1: 8-hour sign-in frequency, standard MFA
    - Zone 2: 4-hour sign-in frequency, passwordless MFA
    - Zone 3: 1-hour sign-in frequency, phishing-resistant MFA, compliant device

    All policies deploy in report-only mode by default. After a 72-hour bake period,
    operators can transition policies to enforcement mode using -EnablePolicies.

    Includes pre-deployment CA policy conflict audit and mandatory break-glass validation.

.PARAMETER TenantId
    Azure AD tenant ID.

.PARAMETER ConfigPath
    Path to tenant configuration JSON file containing:
    - tenantId: Azure AD tenant ID
    - groups: Zone user group IDs (zone1Users, zone2Users, zone3Users)
    - breakGlassAccounts: Break-glass account user IDs (array)
    - authStrengthPolicies: Auth strength policy IDs (passwordlessMFA, phishingResistantMFA)
    - policyPrefix: Optional prefix for policy display names (default: "SSC")

.PARAMETER Zone
    Which zone policies to deploy: All, Zone1, Zone2, or Zone3.

.PARAMETER TemplatePath
    Path to policy template directory. Defaults to ../templates/step-up

.PARAMETER Interactive
    Use interactive browser authentication.

.PARAMETER ClientId
    Azure AD application (client) ID for service principal authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER EnablePolicies
    DANGEROUS: Transition policies from report-only to enforced mode.
    Requires 72-hour minimum bake period since policy creation.
    Cannot be combined with new policy deployment.

.PARAMETER DryRun
    Preview changes without deploying. Shows conflict audit results only.

.PARAMETER Force
    Update existing policies with template changes.

.PARAMETER SkipConflictAudit
    Skip pre-deployment CA policy conflict check. Not recommended.

.EXAMPLE
    .\Deploy-StepUpPolicies.ps1 -TenantId "contoso.onmicrosoft.com" -ConfigPath "./config.json" -Zone Zone2 -Interactive -DryRun
    Preview Zone 2 policy deployment with conflict audit.

.EXAMPLE
    .\Deploy-StepUpPolicies.ps1 -TenantId "contoso.onmicrosoft.com" -ConfigPath "./config.json" -Zone All -Interactive
    Deploy all zone policies in report-only mode.

.EXAMPLE
    .\Deploy-StepUpPolicies.ps1 -TenantId "contoso.onmicrosoft.com" -ConfigPath "./config.json" -EnablePolicies -Interactive
    Transition existing policies to enforcement mode (after 72-hour bake period).

.NOTES
    Version: 1.0.0
    Requires PowerShell 7.0+ and Microsoft.Graph.Identity.SignIns module v2.35.1+.
    Zone 3 risky-user policy requires Microsoft.Graph.Beta.Identity.SignIns module.

    FSI-AgentGov Control: 1.23 - Session Security Controls
    Solution: Session Security Configurator (SCM-02, SCM-04, SCM-05, SCM-07)

    Source: Microsoft Learn - Session controls
    https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-session
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Identity.SignIns

# Note: SupportsShouldProcess is intentionally omitted. Use -DryRun as the canonical
# preview mechanism (connects read-only for conflict audit unless -SkipConflictAudit
# is also specified). See Deploy-AuthContexts.ps1 for comparison; that script uses
# both SupportsShouldProcess and -DryRun because it queries existing auth contexts
# before deciding create vs update.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("All", "Zone1", "Zone2", "Zone3")]
    [string]$Zone = "All",

    [Parameter(Mandatory = $false)]
    [string]$TemplatePath = "$PSScriptRoot\..\templates\step-up",

    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [switch]$EnablePolicies,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipConflictAudit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Banner
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Session Security Configurator - Step-Up Policy Deployment" -ForegroundColor Cyan
Write-Host "FSI-AgentGov Control 1.23" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host "Zone: $Zone"
Write-Host "Mode: $(if ($EnablePolicies) { 'ENABLE ENFORCEMENT' } elseif ($DryRun) { 'DRY RUN' } else { 'DEPLOY REPORT-ONLY' })"
Write-Host ""

# Load and validate configuration
Write-Host "Loading configuration from $ConfigPath..." -ForegroundColor Cyan
if (-not (Test-Path $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath"
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Validate required configuration fields
$requiredFields = @("tenantId", "groups", "breakGlassAccounts", "authStrengthPolicies")
foreach ($field in $requiredFields) {
    if (-not $config.$field) {
        throw "Configuration missing required field: $field"
    }
}

# Validate group configuration
$requiredGroups = @("zone1Users", "zone2Users", "zone3Users")
foreach ($groupField in $requiredGroups) {
    if (-not $config.groups.$groupField) {
        throw "Configuration missing required group: groups.$groupField"
    }
}

# Validate auth strength configuration
$requiredAuthStrengths = @("passwordlessMFA", "phishingResistantMFA")
foreach ($authStrength in $requiredAuthStrengths) {
    if (-not $config.authStrengthPolicies.$authStrength) {
        throw "Configuration missing required auth strength policy: authStrengthPolicies.$authStrength"
    }
}

Write-Host "Configuration validated." -ForegroundColor Green

# Set default policy prefix if not specified
if (-not $config.policyPrefix) {
    $config | Add-Member -NotePropertyName "policyPrefix" -NotePropertyValue "SSC"
}

# Determine templates to deploy based on Zone parameter
$templateMapping = @{
    "Zone1" = @("zone1-step-up-policy.json")
    "Zone2" = @("zone2-step-up-policy.json")
    "Zone3" = @("zone3-step-up-policy.json")
}

$templatesToDeploy = @()
switch ($Zone) {
    "All" {
        $templatesToDeploy = @(
            "zone1-step-up-policy.json",
            "zone2-step-up-policy.json",
            "zone3-step-up-policy.json"
        )
    }
    default {
        $templatesToDeploy = $templateMapping[$Zone]
    }
}

Write-Host "`nTemplates to deploy:" -ForegroundColor Yellow
$templatesToDeploy | ForEach-Object { Write-Host "  - $_" }

# Dot-source helper scripts
. "$PSScriptRoot\private\Connect-GraphSession.ps1"
. "$PSScriptRoot\private\Test-BreakGlassExclusion.ps1"

# Connect to Microsoft Graph (skip only if DryRun AND SkipConflictAudit)
if (-not $DryRun -or -not $SkipConflictAudit) {
    Write-Host "`nConnecting to Microsoft Graph..." -ForegroundColor Cyan

    # Build connection parameters
    $connectParams = @{
        TenantId = $TenantId
    }

    if ($Interactive) {
        $connectParams.Interactive = $true
    }
    elseif ($ClientId -and $CertificateThumbprint) {
        $connectParams.ClientId = $ClientId
        $connectParams.CertificateThumbprint = $CertificateThumbprint
    }
    else {
        throw "Either -Interactive or both -ClientId and -CertificateThumbprint must be specified."
    }

    Connect-GraphSession @connectParams | Out-Null
    Write-Host "Graph API connected." -ForegroundColor Green
}
else {
    Write-Host "`nDry run mode with -SkipConflictAudit - skipping Microsoft Graph connection." -ForegroundColor Yellow
}

# --- 72-HOUR BAKE PERIOD ENFORCEMENT ---
if ($EnablePolicies) {
    Write-Host "`n" + "=" * 80 -ForegroundColor Yellow
    Write-Host "ENFORCEMENT MODE - 72-Hour Bake Period Validation" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow

    # Query existing SSC policies
    Write-Host "`nQuerying existing session security policies..." -ForegroundColor Cyan
    $sscPolicies = Get-MgIdentityConditionalAccessPolicy -Filter "startswith(displayName, '$($config.policyPrefix)-')" -ErrorAction Stop

    if ($sscPolicies.Count -eq 0) {
        throw "No session security policies found with prefix '$($config.policyPrefix)-'. Deploy policies first before enabling enforcement."
    }

    Write-Host "Found $($sscPolicies.Count) existing policies." -ForegroundColor Green

    # Check creation timestamps
    $now = Get-Date
    $minBakePeriodHours = 72
    $tooYoungPolicies = @()

    foreach ($policy in $sscPolicies) {
        $createdDateTime = [DateTime]$policy.CreatedDateTime
        $ageHours = ($now - $createdDateTime).TotalHours

        if ($ageHours -lt $minBakePeriodHours) {
            $tooYoungPolicies += @{
                Name = $policy.DisplayName
                CreatedDateTime = $createdDateTime
                AgeHours = [math]::Round($ageHours, 1)
                EarliestEnforcement = $createdDateTime.AddHours($minBakePeriodHours)
            }
        }
    }

    # Abort if any policy is too young
    if ($tooYoungPolicies.Count -gt 0) {
        Write-Host "`n" + "=" * 80 -ForegroundColor Red
        Write-Host "DEPLOYMENT ABORTED - BAKE PERIOD NOT MET" -ForegroundColor Red
        Write-Host "=" * 80 -ForegroundColor Red
        Write-Host "`nThe following policies were created less than 72 hours ago:" -ForegroundColor Red
        Write-Host ""

        foreach ($youngPolicy in $tooYoungPolicies) {
            Write-Host "  Policy: $($youngPolicy.Name)" -ForegroundColor Red
            Write-Host "    Created: $($youngPolicy.CreatedDateTime)" -ForegroundColor Yellow
            Write-Host "    Age: $($youngPolicy.AgeHours) hours" -ForegroundColor Red
            Write-Host "    Earliest enforcement: $($youngPolicy.EarliestEnforcement)" -ForegroundColor Yellow
            Write-Host ""
        }

        throw "Minimum 72-hour report-only bake period required before enforcement. See above for earliest enforcement times."
    }

    # All policies meet bake period - confirm enforcement
    Write-Host "`n✓ All policies meet 72-hour bake period requirement." -ForegroundColor Green
    Write-Host "`nWARNING: The following policies will be transitioned to ENFORCEMENT mode:" -ForegroundColor Yellow
    Write-Host ""

    foreach ($policy in $sscPolicies) {
        Write-Host "  - $($policy.DisplayName)" -ForegroundColor Yellow
    }

    Write-Host "`nThis will actively block non-compliant sessions for targeted users." -ForegroundColor Yellow
    Write-Host "Ensure you have reviewed sign-in logs for report-only impact." -ForegroundColor Yellow
    Write-Host ""

    # Prompt for confirmation
    $confirmation = Read-Host "Continue with enforcement transition? [y/N]"
    if ($confirmation -ne 'y') {
        Write-Host "`nEnforcement transition cancelled by user." -ForegroundColor Yellow
        return
    }

    # Update policies to enabled state
    Write-Host "`nTransitioning policies to enforcement mode..." -ForegroundColor Cyan
    $transitioned = @()
    $errors = @()

    foreach ($policy in $sscPolicies) {
        try {
            Write-Host "  Enabling: $($policy.DisplayName)..." -ForegroundColor Cyan
            Update-MgIdentityConditionalAccessPolicy `
                -ConditionalAccessPolicyId $policy.Id `
                -State "enabled" `
                -ErrorAction Stop
            Write-Host "    Status: Enforced" -ForegroundColor Green

            $transitioned += @{
                Name = $policy.DisplayName
                Id = $policy.Id
                Status = "Enforced"
            }
        }
        catch {
            Write-Host "    Status: ERROR" -ForegroundColor Red
            Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red

            $errors += @{
                Name = $policy.DisplayName
                Error = $_.Exception.Message
            }
        }
    }

    # Summary for enforcement transition
    Write-Host "`n" + "=" * 80 -ForegroundColor Cyan
    Write-Host "Enforcement Transition Summary" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan

    Write-Host "`nPolicies Enforced: $($transitioned.Count)"
    foreach ($result in $transitioned) {
        Write-Host "  [ENFORCED] $($result.Name)" -ForegroundColor Green
    }

    if ($errors.Count -gt 0) {
        Write-Host "`nErrors: $($errors.Count)" -ForegroundColor Red
        foreach ($error in $errors) {
            Write-Host "  - $($error.Name): $($error.Error)" -ForegroundColor Red
        }
    }

    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "  1. Monitor sign-in logs for blocked sessions"
    Write-Host "  2. Ensure help desk is aware of new session security requirements"
    Write-Host "  3. Run Test-SessionCompliance.ps1 to verify enforcement"

    Write-Host "`nEnforcement transition complete." -ForegroundColor Green
    return
}

# --- PRE-DEPLOYMENT CA POLICY CONFLICT AUDIT ---
$conflicts = @()
if (-not $SkipConflictAudit) {
    Write-Host "`n" + "=" * 80 -ForegroundColor Cyan
    Write-Host "Pre-Deployment Conflict Audit" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan

    Write-Host "`nQuerying all existing Conditional Access policies..." -ForegroundColor Cyan
    $allCAPolicies = Get-MgIdentityConditionalAccessPolicy -ErrorAction Stop
    Write-Host "Found $($allCAPolicies.Count) existing CA policies." -ForegroundColor Green

    $conflicts = @()

    # Check each template for conflicts
    foreach ($templateFile in $templatesToDeploy) {
        $templateFullPath = Join-Path $TemplatePath $templateFile
        if (-not (Test-Path $templateFullPath)) {
            Write-Warning "Template not found: $templateFile"
            continue
        }

        # Load template
        $template = Get-Content $templateFullPath -Raw | ConvertFrom-Json -AsHashtable

        # Extract zone from template file name (e.g., "zone2-step-up-policy.json" -> "zone2")
        $zoneName = $templateFile -replace '-step-up-policy\.json$', ''

        # Get target groups for this zone
        $targetGroupId = switch ($zoneName) {
            "zone1" { $config.groups.zone1Users }
            "zone2" { $config.groups.zone2Users }
            "zone3" { $config.groups.zone3Users }
        }

        # Check for overlapping policies
        foreach ($existingPolicy in $allCAPolicies) {
            # Skip SSC policies (would be false positives)
            if ($existingPolicy.DisplayName -like "$($config.policyPrefix)-*") {
                continue
            }

            # Check for group overlap
            if ($existingPolicy.Conditions.Users.IncludeGroups -contains $targetGroupId) {
                # Check for differing session controls
                $existingSignInFreq = $existingPolicy.SessionControls.SignInFrequency
                $templateSignInFreq = $template.sessionControls.signInFrequency

                if ($existingSignInFreq -and $templateSignInFreq) {
                    # Normalize to minutes for comparison
                    $existingMinutes = switch ($existingSignInFreq.Type) {
                        "hours" { $existingSignInFreq.Value * 60 }
                        "minutes" { $existingSignInFreq.Value }
                        "days" { $existingSignInFreq.Value * 1440 }
                        default { $existingSignInFreq.Value }
                    }

                    $templateMinutes = switch ($templateSignInFreq.type) {
                        "hours" { $templateSignInFreq.value * 60 }
                        "minutes" { $templateSignInFreq.value }
                        "days" { $templateSignInFreq.value * 1440 }
                        default { $templateSignInFreq.value }
                    }

                    if ($existingMinutes -ne $templateMinutes) {
                        $conflicts += @{
                            TemplateName = $templateFile
                            ExistingPolicyName = $existingPolicy.DisplayName
                            ConflictType = "Different sign-in frequency"
                            ExistingValue = "$($existingSignInFreq.Value) $($existingSignInFreq.Type)"
                            TemplateValue = "$($templateSignInFreq.value) $($templateSignInFreq.type)"
                            Impact = "Users may be subject to conflicting session requirements"
                        }
                    }
                }
            }
        }
    }

    # Display conflict warnings (but don't abort)
    if ($conflicts.Count -gt 0) {
        Write-Host "`nWARNING: Potential CA policy conflicts detected:" -ForegroundColor Yellow
        Write-Host ""

        foreach ($conflict in $conflicts) {
            Write-Host "  Template: $($conflict.TemplateName)" -ForegroundColor Yellow
            Write-Host "    Existing Policy: $($conflict.ExistingPolicyName)" -ForegroundColor Cyan
            Write-Host "    Conflict: $($conflict.ConflictType)" -ForegroundColor Yellow
            Write-Host "    Existing: $($conflict.ExistingValue)" -ForegroundColor Red
            Write-Host "    Template: $($conflict.TemplateValue)" -ForegroundColor Green
            Write-Host "    Impact: $($conflict.Impact)" -ForegroundColor Yellow
            Write-Host ""
        }

        Write-Host "Review these conflicts before proceeding. Deployment will continue." -ForegroundColor Yellow
    }
    else {
        Write-Host "`n✓ No CA policy conflicts detected." -ForegroundColor Green
    }
}

# If DryRun, stop here
if ($DryRun) {
    Write-Host "`n" + "=" * 80 -ForegroundColor Yellow
    Write-Host "DRY RUN COMPLETE" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    Write-Host "`nNo policies were deployed." -ForegroundColor Yellow
    Write-Host "Re-run without -DryRun to deploy policies in report-only mode." -ForegroundColor Yellow
    return
}

# --- TEMPLATE PROCESSING AND DEPLOYMENT ---
Write-Host "`n" + "=" * 80 -ForegroundColor Cyan
Write-Host "Policy Template Processing" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan

$deployedPolicies = @()
$errors = @()

foreach ($templateFile in $templatesToDeploy) {
    $templateFullPath = Join-Path $TemplatePath $templateFile

    if (-not (Test-Path $templateFullPath)) {
        Write-Warning "Template not found: $templateFile"
        continue
    }

    Write-Host "`nProcessing: $templateFile" -ForegroundColor Cyan

    # Load template
    $template = Get-Content $templateFullPath -Raw | ConvertFrom-Json -AsHashtable

    # Apply policy prefix
    $policyName = $template.displayName
    if ($config.policyPrefix -and $policyName -like "SSC-*") {
        $policyName = $policyName -replace "^SSC-", "$($config.policyPrefix)-"
    }
    $template.displayName = $policyName

    # Substitute group IDs
    if ($template.conditions.users.includeGroups) {
        $template.conditions.users.includeGroups = $template.conditions.users.includeGroups | ForEach-Object {
            switch ($_) {
                "<zone-1-users-group-id>" { $config.groups.zone1Users }
                "<zone-2-users-group-id>" { $config.groups.zone2Users }
                "<zone-3-users-group-id>" { $config.groups.zone3Users }
                default { $_ }
            }
        }
    }

    # Substitute break-glass accounts
    if ($template.conditions.users.excludeUsers) {
        $template.conditions.users.excludeUsers = $config.breakGlassAccounts
    }

    # Substitute auth strength policy IDs
    if ($template.grantControls.authenticationStrength.id) {
        $authStrengthId = $template.grantControls.authenticationStrength.id
        $template.grantControls.authenticationStrength.id = switch ($authStrengthId) {
            "<passwordless-mfa-policy-id>" { $config.authStrengthPolicies.passwordlessMFA }
            "<phishing-resistant-mfa-policy-id>" { $config.authStrengthPolicies.phishingResistantMFA }
            default { $authStrengthId }
        }
    }

    # Force report-only state (never deploy as enabled)
    $template.state = "enabledForReportingButNotEnforced"

    Write-Host "  Name: $policyName"
    Write-Host "  State: $($template.state)"

    # Break-glass validation
    Write-Host "`n  Validating break-glass exclusions..." -ForegroundColor Cyan
    $breakGlassValid = Test-BreakGlassExclusion -PolicyTemplate $template -Config $config

    if (-not $breakGlassValid) {
        Write-Host "`n  ERROR: Break-glass validation FAILED." -ForegroundColor Red
        Write-Host "  Deployment ABORTED to prevent tenant lockout." -ForegroundColor Red

        $errors += @{
            Template = $templateFile
            Policy = $policyName
            Error = "Break-glass validation failed"
        }

        throw "Break-glass validation failed for policy '$policyName'. All break-glass accounts must be excluded. Deployment aborted."
    }

    Write-Host "  ✓ Break-glass validation passed." -ForegroundColor Green

    # Check if policy exists
    try {
        $existingPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$policyName'" -ErrorAction SilentlyContinue

        if ($existingPolicy) {
            if ($Force) {
                Write-Host "`n  Updating existing policy..." -ForegroundColor Yellow
                Update-MgIdentityConditionalAccessPolicy `
                    -ConditionalAccessPolicyId $existingPolicy.Id `
                    -BodyParameter $template `
                    -ErrorAction Stop
                Write-Host "  Status: Updated" -ForegroundColor Yellow

                $deployedPolicies += @{
                    Name = $policyName
                    Template = $templateFile
                    State = $template.state
                    Status = "Updated"
                    Id = $existingPolicy.Id
                }
            }
            else {
                Write-Host "`n  Policy exists. Use -Force to update." -ForegroundColor Yellow
                $deployedPolicies += @{
                    Name = $policyName
                    Template = $templateFile
                    State = $template.state
                    Status = "Skipped"
                    Id = $existingPolicy.Id
                }
            }
        }
        else {
            # Create new policy
            Write-Host "`n  Creating policy..." -ForegroundColor Cyan

            # Check if Zone 3 and needs Beta API
            $isZone3 = $templateFile -like "zone3*"
            $signInFreqHours = if ($template.sessionControls.signInFrequency.type -eq "hours") {
                $template.sessionControls.signInFrequency.value
            } else { 0 }

            # Deploy standard policy using v1.0 API
            $newPolicy = New-MgIdentityConditionalAccessPolicy -BodyParameter $template -ErrorAction Stop
            Write-Host "  [v1.0 API] Created: $($newPolicy.Id)" -ForegroundColor Green

            $deployedPolicies += @{
                Name = $policyName
                Template = $templateFile
                State = $template.state
                Status = "Created"
                Id = $newPolicy.Id
            }

            # If Zone 3 with 1h frequency, also create Beta API risky-user policy
            if ($isZone3 -and $signInFreqHours -eq 1) {
                Write-Host "`n  Zone 3 detected - deploying risky-user reauthentication policy..." -ForegroundColor Cyan

                try {
                    # Import Beta module
                    Import-Module Microsoft.Graph.Beta.Identity.SignIns -ErrorAction Stop

                    # Create Beta policy template (clone from main policy)
                    $betaTemplate = $template.Clone()
                    $betaTemplate.displayName = "$($config.policyPrefix)-Zone3-Risky-User-Reauthentication"

                    # Set Beta-specific session controls
                    $betaTemplate.sessionControls.signInFrequency = @{
                        value = 1
                        type = "hours"
                        isEnabled = $true
                        frequencyInterval = "everyTime"
                        authenticationType = "primaryAndSecondaryAuthentication"
                    }

                    # Deploy via Beta API
                    $betaPolicy = New-MgBetaIdentityConditionalAccessPolicy -BodyParameter $betaTemplate -ErrorAction Stop
                    Write-Host "  [Beta API] Created risky-user policy: $($betaPolicy.Id)" -ForegroundColor Green

                    $deployedPolicies += @{
                        Name = $betaTemplate.displayName
                        Template = "$templateFile (Beta)"
                        State = $betaTemplate.state
                        Status = "Created (Beta API)"
                        Id = $betaPolicy.Id
                    }
                }
                catch {
                    Write-Warning "Failed to create Beta API risky-user policy: $($_.Exception.Message)"
                    Write-Warning "Install Microsoft.Graph.Beta.Identity.SignIns module for enhanced Zone 3 controls."
                }
            }
        }
    }
    catch {
        Write-Host "`n  ERROR: $_" -ForegroundColor Red
        $errors += @{
            Template = $templateFile
            Policy = $policyName
            Error = $_.Exception.Message
        }
    }
}

# --- DEPLOYMENT SUMMARY ---
Write-Host "`n" + "=" * 80 -ForegroundColor Cyan
Write-Host "Deployment Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan

Write-Host "`nPolicies Processed: $($deployedPolicies.Count)"
foreach ($result in $deployedPolicies) {
    $statusColor = switch ($result.Status) {
        "Created" { "Green" }
        { $_ -like "Created*" } { "Green" }
        "Updated" { "Yellow" }
        "Skipped" { "Cyan" }
        default { "White" }
    }
    Write-Host "  [$($result.Status)] $($result.Name)" -ForegroundColor $statusColor
}

if ($errors.Count -gt 0) {
    Write-Host "`nErrors: $($errors.Count)" -ForegroundColor Red
    foreach ($error in $errors) {
        Write-Host "  - $($error.Template): $($error.Error)" -ForegroundColor Red
    }
}

if ($deployedPolicies.Count -gt 0 -and $errors.Count -eq 0) {
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "  1. Policies deployed in report-only mode" -ForegroundColor Yellow
    Write-Host "  2. Wait 72 hours for sign-in log data collection" -ForegroundColor Yellow
    Write-Host "  3. Review Conditional Access insights for policy impact" -ForegroundColor Yellow
    Write-Host "  4. Run Test-SessionCompliance.ps1 to verify configurations" -ForegroundColor Yellow
    Write-Host "  5. After validation, re-run with -EnablePolicies to enforce" -ForegroundColor Yellow
}

Write-Host "`nDeployment complete." -ForegroundColor Green

# Return results object for downstream use
return @{
    DeployedPolicies = $deployedPolicies
    Errors = $errors
    ConflictAuditResults = $conflicts
}
