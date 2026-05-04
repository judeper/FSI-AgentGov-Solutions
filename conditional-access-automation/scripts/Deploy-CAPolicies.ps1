<#
.SYNOPSIS
    Deploys Conditional Access policy templates for AI workloads.

.DESCRIPTION
    Deploys pre-configured Conditional Access policies from JSON templates to an
    Entra ID tenant. Supports zone-based deployment (Zone1, Zone2, Zone3) and
    report-only testing mode. Templates use placeholder tokens that are replaced
    with tenant-specific values from a configuration file at deploy time.

    Supports WhatIf/Confirm via ShouldProcess so administrators can preview every
    Graph API call before it executes. The legacy -DryRun switch is retained for
    backward compatibility and maps to -WhatIf internally.

.PARAMETER TenantId
    The Entra ID tenant GUID to deploy policies into.

.PARAMETER ConfigPath
    Path to the tenant configuration JSON file containing group IDs,
    application IDs, break-glass accounts, and optional policy prefix.

.PARAMETER TemplateSet
    Which set of templates to deploy. Valid values: All, Zone1, Zone2, Zone3.
    Defaults to "All". Each zone includes its zone-specific templates plus
    common templates (M365Copilot, BlockLegacyAuth).

.PARAMETER Zone
    Optional shorthand for -TemplateSet. Accepts Zone1, Zone2, or Zone3.
    When specified, overrides -TemplateSet with the matching zone value.

.PARAMETER TemplatePath
    Path to the directory containing policy template JSON files.
    Defaults to ../templates relative to the script location.

.PARAMETER EnablePolicies
    When $true, deploys policies in enabled state. When $false (default),
    deploys in report-only mode (enabledForReportingButNotEnforced).

.PARAMETER DryRun
    [Obsolete] Legacy switch retained for backward compatibility. Maps to
    -WhatIf internally. Prefer using -WhatIf instead.

.PARAMETER Force
    When specified, updates existing policies with the same display name
    without prompting for confirmation.

.EXAMPLE
    .\Deploy-CAPolicies.ps1 -TenantId "contoso.onmicrosoft.com" -ConfigPath "./config.json" -TemplateSet "Zone3" -WhatIf

    Previews which Zone 3 policies would be deployed without making changes.

.EXAMPLE
    .\Deploy-CAPolicies.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -ConfigPath "./config.json" -TemplateSet "All" -EnablePolicies $false

    Deploys all templates in report-only mode for impact analysis.

.EXAMPLE
    .\Deploy-CAPolicies.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -ConfigPath "./config.json" -Zone Zone2 -Force

    Deploys Zone 2 templates, updating any existing policies with matching names.

.OUTPUTS
    None. Status output is written to the host and verbose streams.

.NOTES
    File: Deploy-CAPolicies.ps1
    Version: 2.0.1
    Supports compliance with FINRA 4511, SEC 17a-4, and OCC 2011-12
    through auditable, zone-based Conditional Access deployment.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("All", "Zone1", "Zone2", "Zone3")]
    [string]$TemplateSet = "All",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Zone1", "Zone2", "Zone3")]
    [string]$Zone,

    [Parameter(Mandatory = $false)]
    [string]$TemplatePath = "$PSScriptRoot\..\templates",

    [Parameter(Mandatory = $false)]
    [bool]$EnablePolicies = $false,

    # [Obsolete("Use -WhatIf instead of -DryRun. -DryRun is retained for backward compatibility.")]
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Identity.SignIns'; ModuleVersion = '2.0.0' }

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Structured audit logging
function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$CorrelationId = $script:CorrelationId
    )
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ" -AsUTC
    Write-Output "[$timestamp] [$Level] [$CorrelationId] $Message"
}
$script:CorrelationId = [guid]::NewGuid().ToString("N").Substring(0,8)

# Import private helpers
. $PSScriptRoot/private/Connect-GraphSession.ps1
. $PSScriptRoot/private/Get-ZoneClassification.ps1
. $PSScriptRoot/private/Test-ParameterValidation.ps1

# Map legacy -DryRun to WhatIf
if ($DryRun) { $WhatIfPreference = $true }

# Map -Zone shorthand to -TemplateSet
if ($Zone) { $TemplateSet = $Zone }

# Banner
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Conditional Access Policy Deployment" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host "Template Set: $TemplateSet"
Write-Host "Mode: $(if ($WhatIfPreference) { 'DRY RUN (WhatIf)' } else { 'DEPLOY' })"
Write-Host "State: $(if ($EnablePolicies) { 'Enabled' } else { 'Report-Only' })"
Write-Host ""

# Load and validate configuration
Write-Verbose "Loading configuration from $ConfigPath..."
Test-CAAConfigPath -Path $ConfigPath
$config = Get-Content $ConfigPath | ConvertFrom-Json
Write-Verbose "Configuration validated."

# Validate break-glass account GUIDs before deployment
if ($config.breakGlassAccounts -and $config.breakGlassAccounts.Count -gt 0) {
    Test-CAABreakGlassAccounts -AccountIds @($config.breakGlassAccounts)
}

# Validate group and application IDs are well-formed GUIDs
$guidValues = @()
if ($config.groups) {
    @('zone1Users', 'zone2Users', 'zone3Users') | ForEach-Object {
        if ($config.groups.$_) { $guidValues += @{ Name = "groups.$_"; Value = $config.groups.$_ } }
    }
}
if ($config.applications) {
    @('copilotStudio', 'agentBuilder', 'm365Copilot') | ForEach-Object {
        if ($config.applications.$_) { $guidValues += @{ Name = "applications.$_"; Value = $config.applications.$_ } }
    }
}
$invalidGuids = @()
foreach ($gv in $guidValues) {
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($gv.Value, [ref]$parsed)) {
        $invalidGuids += "$($gv.Name) = '$($gv.Value)'"
    }
}
if ($invalidGuids.Count -gt 0) {
    throw "Config contains malformed GUIDs: $($invalidGuids -join '; '). All group IDs, application IDs, and break-glass accounts must be valid GUIDs."
}

# Define template mapping
$templateMapping = @{
    "Zone1" = @(
        "CA-CopilotStudio-Zone1.json",
        "CA-AgentBuilder-Zone1.json"
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

Write-Verbose "Templates to deploy: $($templatesToDeploy -join ', ')"

# Connect to Microsoft Graph (skipped in WhatIf mode)
if (-not $WhatIfPreference) {
    Write-Verbose "Establishing Microsoft Graph session..."
    Connect-CAAGraphSession -TenantId $TenantId
    Write-Verbose "Connected to Graph API."
}

# Process templates
$deployedPolicies = @()
$errors = @()

foreach ($templateFile in $templatesToDeploy) {
    $templateFullPath = Join-Path $TemplatePath $templateFile

    if (-not (Test-Path $templateFullPath)) {
        Write-Verbose "Template not found: $templateFile — skipping."
        continue
    }

    Write-Verbose "Processing: $templateFile"

    # Load template
    $template = Get-Content $templateFullPath | ConvertFrom-Json -AsHashtable

    # Remove _metadata before sending to Graph API
    if ($template.ContainsKey('_metadata')) {
        $template.Remove('_metadata')
    }

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
        if (-not $config.breakGlassAccounts -or $config.breakGlassAccounts.Count -eq 0) {
            throw "config.breakGlassAccounts is empty or missing. Refusing to deploy CA policies without break-glass exclusions — this would lock emergency access accounts out of all AI workloads."
        }
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

    # Validate all placeholder tokens were substituted before calling Graph API
    $templateJson = $template | ConvertTo-Json -Depth 10
    $unresolvedTokens = [regex]::Matches($templateJson, '<[a-zA-Z][a-zA-Z0-9-]*>') | ForEach-Object { $_.Value } | Sort-Object -Unique
    if ($unresolvedTokens) {
        Write-Error "  Unresolved placeholder tokens in '$templateFile': $($unresolvedTokens -join ', '). Verify config.json contains all required values."
        $deployedPolicies += @{
            Name     = $policyName
            Template = $templateFile
            State    = 'Error'
            Status   = "UnresolvedPlaceholders"
        }
        continue
    }

    # Set policy state
    $template.state = if ($EnablePolicies) { "enabled" } else { "enabledForReportingButNotEnforced" }

    Write-Verbose "  Name: $policyName"
    Write-Verbose "  State: $($template.state)"

    if ($WhatIfPreference) {
        Write-Host "  [WhatIf] Would deploy policy: $policyName ($templateFile)" -ForegroundColor Yellow
        $deployedPolicies += @{
            Name = $policyName
            Template = $templateFile
            State = $template.state
            Status = "WhatIf"
        }
        continue
    }

    # Check if policy exists and deploy
    try {
        $sanitizedPolicyName = $policyName -replace "'", "''"
        $existingPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$sanitizedPolicyName'" -ErrorAction SilentlyContinue

        if ($existingPolicy) {
            if ($Force) {
                if ($PSCmdlet.ShouldProcess("Policy: $policyName (Id: $($existingPolicy.Id))", "Update in tenant $TenantId")) {
                    Write-Verbose "  Updating existing policy..."
                    Update-MgIdentityConditionalAccessPolicy `
                        -ConditionalAccessPolicyId $existingPolicy.Id `
                        -BodyParameter $template
                    Write-Verbose "  Updated successfully."
                    $deployedPolicies += @{
                        Name = $policyName
                        Template = $templateFile
                        State = $template.state
                        Status = "Updated"
                        Id = $existingPolicy.Id
                    }
                }
            }
            else {
                Write-Verbose "  Policy exists. Use -Force to update."
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
            if ($PSCmdlet.ShouldProcess("Policy: $policyName", "Deploy to tenant $TenantId")) {
                Write-Verbose "  Creating policy..."
                $newPolicy = New-MgIdentityConditionalAccessPolicy -BodyParameter $template
                Write-Verbose "  Created successfully. ID: $($newPolicy.Id)"
                $deployedPolicies += @{
                    Name = $policyName
                    Template = $templateFile
                    State = $template.state
                    Status = "Created"
                    Id = $newPolicy.Id
                }
            }
        }
    }
    catch {
        Write-Verbose "  ERROR: $_"
        $errors += @{
            Template = $templateFile
            Policy = $policyName
            Error = $_.Exception.Message
        }
    }
}

# Summary
Write-Host ("`n" + "=" * 60) -ForegroundColor Cyan
Write-Host "Deployment Summary" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

Write-Host "`nPolicies Processed: $($deployedPolicies.Count)"
$deployedPolicies | ForEach-Object {
    $statusColor = switch ($_.Status) {
        "Created" { "Green" }
        "Updated" { "Yellow" }
        "Skipped" { "Cyan" }
        "WhatIf" { "Gray" }
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

if (-not $WhatIfPreference -and $deployedPolicies.Count -gt 0) {
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
