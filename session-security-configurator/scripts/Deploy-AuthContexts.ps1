<#
.SYNOPSIS
    Deploys authentication context class references for step-up session security.

.DESCRIPTION
    Creates authentication contexts (c1-c5) for zone-based session security controls.
    Supports dry-run preview, conflict detection, force overwrite, and ID remapping.

    Authentication contexts enable step-up authentication triggers in Conditional Access
    policies. This script deploys the standard FSI-AgentGov contexts:
    - c1: Zone 1 AI workloads (Personal Productivity)
    - c2: Zone 2 AI workloads (Team Collaboration)
    - c3: Zone 3 AI workloads (Enterprise Managed)
    - c4: Privileged Identity Management
    - c5: Emergency access

.PARAMETER TenantId
    Azure AD tenant ID.

.PARAMETER Interactive
    Use interactive browser authentication.

.PARAMETER ClientId
    Azure AD application (client) ID for service principal authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER TemplatePath
    Path to authentication context template JSON file.
    Defaults to ../templates/auth-contexts/auth-contexts-c1-c5.json

.PARAMETER AuthContextPrefix
    Optional ID offset for conflict avoidance (e.g., "c10" to use c10-c14 instead of c1-c5).
    If specified, remaps c1->c10, c2->c11, c3->c12, c4->c13, c5->c14.

.PARAMETER DryRun
    Preview changes without deploying. Does not connect to Microsoft Graph.

.PARAMETER Force
    Overwrite existing authentication contexts with different display names.
    Without -Force, script aborts on ID conflicts with different names.

.EXAMPLE
    .\Deploy-AuthContexts.ps1 -TenantId "contoso.onmicrosoft.com" -Interactive -DryRun
    Preview authentication context deployment without connecting to tenant.

.EXAMPLE
    .\Deploy-AuthContexts.ps1 -TenantId "contoso.onmicrosoft.com" -Interactive
    Deploy c1-c5 authentication contexts in production mode.

.EXAMPLE
    .\Deploy-AuthContexts.ps1 -TenantId "contoso.onmicrosoft.com" -Interactive -AuthContextPrefix "c10"
    Deploy c10-c14 authentication contexts (use when c1-c5 already exist for other purposes).

.EXAMPLE
    .\Deploy-AuthContexts.ps1 -TenantId "contoso.onmicrosoft.com" -Interactive -Force
    Update existing c1-c5 contexts to match FSI-AgentGov definitions.

.NOTES
    Version: 1.0.0
    Requires PowerShell 7.0+ and Microsoft.Graph.Identity.SignIns module v2.35.1+.

    FSI-AgentGov Control: 1.23 - Session Security Controls
    Solution: Session Security Configurator (SCM-01, SCM-04)

    Source: Microsoft Learn - Authentication contexts
    https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-cloud-apps#authentication-context
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Identity.SignIns

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string]$TemplatePath = "$PSScriptRoot\..\templates\auth-contexts\auth-contexts-c1-c5.json",

    [Parameter(Mandatory = $false)]
    [string]$AuthContextPrefix = "",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Banner
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Session Security Configurator - Authentication Context Deployment" -ForegroundColor Cyan
Write-Host "FSI-AgentGov Control 1.23" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host "Mode: $(if ($DryRun) { 'DRY RUN' } else { 'DEPLOY' })"
Write-Host "Force: $(if ($Force) { 'Yes' } else { 'No' })"
if ($AuthContextPrefix) {
    Write-Host "ID Prefix: $AuthContextPrefix (remapping c1-c5)"
}
Write-Host ""

# Load authentication context template
Write-Host "Loading authentication context template from $TemplatePath..." -ForegroundColor Cyan
if (-not (Test-Path $TemplatePath)) {
    throw "Template file not found: $TemplatePath"
}

$templateContent = Get-Content $TemplatePath -Raw | ConvertFrom-Json
if ($templateContent -is [System.Array]) {
    $authContexts = $templateContent
} elseif ($templateContent.authenticationContexts) {
    $authContexts = $templateContent.authenticationContexts
} else {
    throw "Invalid template: Expected JSON array or object with 'authenticationContexts'"
}
Write-Host "Loaded $($authContexts.Count) authentication context definitions." -ForegroundColor Green

# Apply ID prefix remapping if specified
if ($AuthContextPrefix) {
    Write-Host "`nRemapping authentication context IDs..." -ForegroundColor Cyan

    # Extract numeric suffix from prefix (e.g., "c10" -> 10)
    if ($AuthContextPrefix -match '^c(\d+)$') {
        $baseOffset = [int]$Matches[1]

        foreach ($context in $authContexts) {
            # Extract current numeric ID (e.g., "c1" -> 1)
            if ($context.id -match '^c(\d+)$') {
                $currentNum = [int]$Matches[1]
                $newNum = $baseOffset + ($currentNum - 1)
                $oldId = $context.id
                $context.id = "c$newNum"
                Write-Host "  $oldId -> $($context.id)" -ForegroundColor Yellow
            }
        }
    }
    else {
        throw "Invalid AuthContextPrefix format. Expected format: 'c10', 'c20', etc."
    }
}

# Connect to Microsoft Graph (skip in DryRun mode)
if (-not $DryRun) {
    Write-Host "`nConnecting to Microsoft Graph..." -ForegroundColor Cyan

    # Dot-source Connect-GraphSession helper
    . "$PSScriptRoot\private\Connect-GraphSession.ps1"

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

# Query existing authentication contexts
$existingContexts = @{}
if (-not $DryRun) {
    Write-Host "`nQuerying existing authentication contexts..." -ForegroundColor Cyan
    try {
        $existingList = Get-MgIdentityConditionalAccessAuthenticationContextClassReference -ErrorAction Stop
        foreach ($ctx in $existingList) {
            $existingContexts[$ctx.Id] = $ctx
        }
        Write-Host "Found $($existingContexts.Count) existing authentication contexts." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to query existing contexts: $($_.Exception.Message)"
    }
}

# Deployment loop
Write-Host "`nProcessing authentication contexts..." -ForegroundColor Cyan
$deployedContexts = @()
$errors = @()
$conflicts = @()

foreach ($context in $authContexts) {
    $contextId = $context.id
    $displayName = $context.displayName
    $description = $context.description

    Write-Host "`n  Context: $contextId - $displayName" -ForegroundColor Cyan

    # Check for conflicts
    if ($existingContexts.ContainsKey($contextId)) {
        $existingContext = $existingContexts[$contextId]

        if ($existingContext.DisplayName -eq $displayName) {
            # Same ID, same name - idempotent, skip
            Write-Host "    Status: Already configured (idempotent)" -ForegroundColor Green
            $deployedContexts += @{
                Id = $contextId
                DisplayName = $displayName
                Status = "Skipped"
                Reason = "Already exists with same name"
            }
            continue
        }
        else {
            # Same ID, different name - conflict
            $conflictDetail = @{
                Id = $contextId
                ExpectedName = $displayName
                ExistingName = $existingContext.DisplayName
            }
            $conflicts += $conflictDetail

            if (-not $Force) {
                Write-Host "    Status: CONFLICT DETECTED" -ForegroundColor Red
                Write-Host "    Expected: '$displayName'" -ForegroundColor Red
                Write-Host "    Existing: '$($existingContext.DisplayName)'" -ForegroundColor Red
                continue
            }
            else {
                Write-Host "    Status: Conflict detected - Force update enabled" -ForegroundColor Yellow
            }
        }
    }

    # DryRun mode - preview only
    if ($DryRun) {
        if ($existingContexts.ContainsKey($contextId)) {
            Write-Host "    [DRY RUN] Would update authentication context $contextId" -ForegroundColor Yellow
            $status = "DryRun-Update"
        }
        else {
            Write-Host "    [DRY RUN] Would create authentication context $contextId" -ForegroundColor Yellow
            $status = "DryRun-Create"
        }

        $deployedContexts += @{
            Id = $contextId
            DisplayName = $displayName
            Status = $status
            Reason = "Preview mode"
        }
        continue
    }

    # Deploy or update context
    try {
        $bodyParams = @{
            Id = $contextId
            DisplayName = $displayName
            Description = $description
            IsAvailable = $true
        }

        if ($existingContexts.ContainsKey($contextId)) {
            # Update existing context
            if ($PSCmdlet.ShouldProcess("Auth context: $contextId ($displayName)", "Update in tenant $TenantId")) {
                Write-Host "    Updating existing context..." -ForegroundColor Yellow
                Update-MgIdentityConditionalAccessAuthenticationContextClassReference `
                    -AuthenticationContextClassReferenceId $contextId `
                    -BodyParameter $bodyParams `
                    -ErrorAction Stop
                Write-Host "    Status: Updated (forced)" -ForegroundColor Yellow

                $deployedContexts += @{
                    Id = $contextId
                    DisplayName = $displayName
                    Status = "Updated"
                    Reason = "Force overwrite"
                }
            }
        }
        else {
            # Create new context
            if ($PSCmdlet.ShouldProcess("Auth context: $contextId ($displayName)", "Create in tenant $TenantId")) {
                Write-Host "    Creating new context..." -ForegroundColor Cyan
                New-MgIdentityConditionalAccessAuthenticationContextClassReference `
                    -BodyParameter $bodyParams `
                    -ErrorAction Stop
                Write-Host "    Status: Created" -ForegroundColor Green

                $deployedContexts += @{
                    Id = $contextId
                    DisplayName = $displayName
                    Status = "Created"
                    Reason = "New deployment"
                }
            }
        }
    }
    catch {
        Write-Host "    Status: ERROR" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red

        $errors += @{
            Id = $contextId
            DisplayName = $displayName
            Error = $_.Exception.Message
        }
    }
}

# Check for conflicts that would abort deployment
if ($conflicts.Count -gt 0 -and -not $Force) {
    Write-Host "`n" + "=" * 80 -ForegroundColor Red
    Write-Host "DEPLOYMENT ABORTED - CONFLICTS DETECTED" -ForegroundColor Red
    Write-Host "=" * 80 -ForegroundColor Red
    Write-Host "`nAuthentication context conflicts detected:" -ForegroundColor Red
    Write-Host ""

    foreach ($conflict in $conflicts) {
        Write-Host "  Context ID: $($conflict.Id)" -ForegroundColor Red
        Write-Host "    Expected: '$($conflict.ExpectedName)'" -ForegroundColor Yellow
        Write-Host "    Existing: '$($conflict.ExistingName)'" -ForegroundColor Red
        Write-Host ""
    }

    Write-Host "Resolution options:" -ForegroundColor Yellow
    Write-Host "  1. Use -Force to overwrite existing contexts with FSI-AgentGov definitions"
    Write-Host "  2. Use -AuthContextPrefix 'c10' to deploy c10-c14 instead of c1-c5"
    Write-Host "  3. Manually rename or remove conflicting contexts in Entra portal"
    Write-Host ""

    throw "Deployment aborted due to authentication context conflicts. See above for resolution options."
}

# Summary
Write-Host "`n" + "=" * 80 -ForegroundColor Cyan
Write-Host "Deployment Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan

Write-Host "`nAuthentication Contexts Processed: $($deployedContexts.Count)"
foreach ($result in $deployedContexts) {
    $statusColor = switch ($result.Status) {
        "Created" { "Green" }
        "Updated" { "Yellow" }
        "Skipped" { "Cyan" }
        { $_ -like "DryRun*" } { "Gray" }
        default { "White" }
    }
    Write-Host "  [$($result.Status)] $($result.Id): $($result.DisplayName)" -ForegroundColor $statusColor
}

if ($errors.Count -gt 0) {
    Write-Host "`nErrors: $($errors.Count)" -ForegroundColor Red
    foreach ($error in $errors) {
        Write-Host "  - $($error.Id): $($error.Error)" -ForegroundColor Red
    }
}

if ($DryRun) {
    Write-Host "`nDRY RUN completed. No changes were made." -ForegroundColor Yellow
    Write-Host "Re-run without -DryRun to deploy authentication contexts." -ForegroundColor Yellow
}
elseif ($deployedContexts.Count -gt 0 -and $errors.Count -eq 0) {
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "  1. Authentication contexts are now available in Conditional Access policies"
    Write-Host "  2. Run Deploy-StepUpPolicies.ps1 to deploy zone-specific session controls"
    Write-Host "  3. Assign authentication contexts to sensitive applications as needed"
}

Write-Host "`nDeployment complete." -ForegroundColor Green

# Return results object for downstream use
return @{
    DeployedContexts = $deployedContexts
    Errors = $errors
    Conflicts = $conflicts
}
