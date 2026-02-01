<#
.SYNOPSIS
    Deploys Conditional Access policy templates for AI workloads.

.DESCRIPTION
    Deploys pre-configured Conditional Access policies from templates,
    supporting zone-based deployment and report-only testing mode.

.PARAMETER TenantId
    Azure AD tenant ID.

.PARAMETER ConfigPath
    Path to tenant configuration JSON file.

.PARAMETER TemplateSet
    Which templates to deploy: All, Zone1, Zone2, Zone3.

.PARAMETER TemplatePath
    Path to template directory. Defaults to ../templates.

.PARAMETER EnablePolicies
    Deploy as enabled ($true) or report-only ($false). Defaults to $false.

.PARAMETER DryRun
    Preview changes without deploying.

.EXAMPLE
    .\Deploy-CAPolicies.ps1 -TenantId "xxx" -ConfigPath "./config.json" -TemplateSet "Zone3" -DryRun

.EXAMPLE
    .\Deploy-CAPolicies.ps1 -TenantId "xxx" -ConfigPath "./config.json" -TemplateSet "All" -EnablePolicies $false
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("All", "Zone1", "Zone2", "Zone3")]
    [string]$TemplateSet = "All",

    [Parameter(Mandatory = $false)]
    [string]$TemplatePath = "$PSScriptRoot\..\templates",

    [Parameter(Mandatory = $false)]
    [bool]$EnablePolicies = $false,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Identity.SignIns

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Banner
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Conditional Access Policy Deployment" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host "Template Set: $TemplateSet"
Write-Host "Mode: $(if ($DryRun) { 'DRY RUN' } else { 'DEPLOY' })"
Write-Host "State: $(if ($EnablePolicies) { 'Enabled' } else { 'Report-Only' })"
Write-Host ""

# Load configuration
Write-Host "Loading configuration from $ConfigPath..."
if (-not (Test-Path $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath"
}
$config = Get-Content $ConfigPath | ConvertFrom-Json

# Validate configuration
$requiredFields = @("tenantId", "groups", "breakGlassAccounts", "applications")
foreach ($field in $requiredFields) {
    if (-not $config.$field) {
        throw "Configuration missing required field: $field"
    }
}
Write-Host "Configuration validated." -ForegroundColor Green

# Define template mapping
$templateMapping = @{
    "Zone1" = @(
        "CA-CopilotStudio-Zone1.json"
    )
    "Zone2" = @(
        "CA-CopilotStudio-Zone2.json",
        "CA-AgentBuilder-Zone2.json"
    )
    "Zone3" = @(
        "CA-CopilotStudio-Zone3.json",
        "CA-AgentBuilder-Zone3.json",
        "CA-RequireCompliantDevice-Zone3.json"
    )
    "Common" = @(
        "CA-M365Copilot-AllZones.json",
        "CA-BlockLegacyAuth-AI.json"
    )
}

# Determine templates to deploy
$templatesToDeploy = @()
switch ($TemplateSet) {
    "All" {
        $templatesToDeploy = $templateMapping.Values | ForEach-Object { $_ }
    }
    "Zone1" {
        $templatesToDeploy = $templateMapping["Zone1"] + $templateMapping["Common"]
    }
    "Zone2" {
        $templatesToDeploy = $templateMapping["Zone2"] + $templateMapping["Common"]
    }
    "Zone3" {
        $templatesToDeploy = $templateMapping["Zone3"] + $templateMapping["Common"]
    }
}

Write-Host "`nTemplates to deploy:" -ForegroundColor Yellow
$templatesToDeploy | ForEach-Object { Write-Host "  - $_" }

# Connect to Microsoft Graph
if (-not $DryRun) {
    Write-Host "`nConnecting to Microsoft Graph..."
    try {
        $context = Get-MgContext
        if (-not $context -or $context.TenantId -ne $TenantId) {
            Connect-MgGraph -TenantId $TenantId -Scopes "Policy.ReadWrite.ConditionalAccess"
        }
        Write-Host "Connected to Graph API." -ForegroundColor Green
    }
    catch {
        throw "Failed to connect to Microsoft Graph: $_"
    }
}

# Process templates
$deployedPolicies = @()
$errors = @()

foreach ($templateFile in $templatesToDeploy) {
    $templateFullPath = Join-Path $TemplatePath $templateFile

    if (-not (Test-Path $templateFullPath)) {
        Write-Host "  Template not found: $templateFile" -ForegroundColor Yellow
        continue
    }

    Write-Host "`nProcessing: $templateFile" -ForegroundColor Cyan

    # Load template
    $template = Get-Content $templateFullPath | ConvertFrom-Json -AsHashtable

    # Apply configuration substitutions
    $policyName = $template.displayName
    if ($config.policyPrefix) {
        $policyName = $policyName -replace "^CA-", "$($config.policyPrefix)-"
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

    # Substitute application IDs
    if ($template.conditions.applications.includeApplications) {
        $template.conditions.applications.includeApplications = $template.conditions.applications.includeApplications | ForEach-Object {
            switch ($_) {
                "<copilot-studio-app-id>" { $config.applications.copilotStudio }
                "<agent-builder-app-id>" { $config.applications.agentBuilder }
                "<m365-copilot-app-id>" { $config.applications.m365Copilot }
                default { $_ }
            }
        }
    }

    # Set policy state
    $template.state = if ($EnablePolicies) { "enabled" } else { "enabledForReportingButNotEnforced" }

    Write-Host "  Name: $policyName"
    Write-Host "  State: $($template.state)"

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would create policy" -ForegroundColor Yellow
        $deployedPolicies += @{
            Name = $policyName
            Template = $templateFile
            State = $template.state
            Status = "DryRun"
        }
        continue
    }

    # Check if policy exists
    try {
        $existingPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$policyName'" -ErrorAction SilentlyContinue

        if ($existingPolicy) {
            if ($Force) {
                Write-Host "  Updating existing policy..." -ForegroundColor Yellow
                Update-MgIdentityConditionalAccessPolicy `
                    -ConditionalAccessPolicyId $existingPolicy.Id `
                    -BodyParameter $template
                Write-Host "  Updated successfully." -ForegroundColor Green
                $deployedPolicies += @{
                    Name = $policyName
                    Template = $templateFile
                    State = $template.state
                    Status = "Updated"
                    Id = $existingPolicy.Id
                }
            }
            else {
                Write-Host "  Policy exists. Use -Force to update." -ForegroundColor Yellow
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
            Write-Host "  Creating policy..."
            $newPolicy = New-MgIdentityConditionalAccessPolicy -BodyParameter $template
            Write-Host "  Created successfully. ID: $($newPolicy.Id)" -ForegroundColor Green
            $deployedPolicies += @{
                Name = $policyName
                Template = $templateFile
                State = $template.state
                Status = "Created"
                Id = $newPolicy.Id
            }
        }
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
        $errors += @{
            Template = $templateFile
            Policy = $policyName
            Error = $_.Exception.Message
        }
    }
}

# Summary
Write-Host "`n" + "=" * 60 -ForegroundColor Cyan
Write-Host "Deployment Summary" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

Write-Host "`nPolicies Processed: $($deployedPolicies.Count)"
$deployedPolicies | ForEach-Object {
    $statusColor = switch ($_.Status) {
        "Created" { "Green" }
        "Updated" { "Yellow" }
        "Skipped" { "Cyan" }
        "DryRun" { "Gray" }
        default { "White" }
    }
    Write-Host "  [$($_.Status)] $($_.Name)" -ForegroundColor $statusColor
}

if ($errors.Count -gt 0) {
    Write-Host "`nErrors: $($errors.Count)" -ForegroundColor Red
    $errors | ForEach-Object {
        Write-Host "  - $($_.Template): $($_.Error)" -ForegroundColor Red
    }
}

if (-not $DryRun -and $deployedPolicies.Count -gt 0) {
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    if (-not $EnablePolicies) {
        Write-Host "  1. Policies deployed in report-only mode"
        Write-Host "  2. Wait 24-48 hours for data collection"
        Write-Host "  3. Review Conditional Access insights"
        Write-Host "  4. Re-run with -EnablePolicies `$true to enable"
    }
    else {
        Write-Host "  1. Monitor sign-in logs for issues"
        Write-Host "  2. Run Test-PolicyCompliance.ps1 to verify"
        Write-Host "  3. Set up drift detection with Watch-PolicyDrift.ps1"
    }
}

Write-Host "`nDeployment complete." -ForegroundColor Green
