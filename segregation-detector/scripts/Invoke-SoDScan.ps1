<#
.SYNOPSIS
    Scans for Segregation of Duties violations across Entra ID and Power Platform.

.DESCRIPTION
    This script queries role assignments from multiple sources and compares them
    against configured conflict rules to detect SoD violations.

.PARAMETER Environment
    The Dataverse environment URL (e.g., https://your-org.crm.dynamics.com)

.PARAMETER TenantId
    Azure AD tenant ID. If not specified, uses AZURE_TENANT_ID environment variable.

.PARAMETER ClientId
    Service principal client ID. If not specified, uses AZURE_CLIENT_ID environment variable.

.PARAMETER ClientSecret
    Service principal client secret. If not specified, uses AZURE_CLIENT_SECRET environment variable.

.PARAMETER DryRun
    Run scan without creating violation records.

.PARAMETER Verbose
    Enable verbose output.

.EXAMPLE
    .\Invoke-SoDScan.ps1 -Environment "https://contoso.crm.dynamics.com"

.EXAMPLE
    .\Invoke-SoDScan.ps1 -Environment "https://contoso.crm.dynamics.com" -DryRun -Verbose
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = $env:AZURE_CLIENT_SECRET,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

#region Helper Functions

function Get-AccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$Scope
    )

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
        grant_type    = "client_credentials"
    }

    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    return $response.access_token
}

function Get-EntraDirectoryRoleAssignments {
    param([string]$Token)

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $assignments = @()
    $uri = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$expand=principal"

    do {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        $assignments += $response.value
        $uri = $response.'@odata.nextLink'
    } while ($uri)

    return $assignments
}

function Get-EntraDirectoryRoles {
    param([string]$Token)

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $uri = "https://graph.microsoft.com/v1.0/directoryRoles"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    return $response.value
}

function Get-PowerPlatformRoleAssignments {
    param([string]$Token)

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $assignments = @()

    # Get all environments
    $envUri = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2023-06-01"
    try {
        $envResponse = Invoke-RestMethod -Uri $envUri -Headers $headers -Method Get
    } catch {
        Write-Warning "Unable to query Power Platform environments: $($_.Exception.Message)"
        return $assignments
    }

    foreach ($env in $envResponse.value) {
        $envId = $env.name
        $envDisplayName = $env.properties.displayName

        # Get role assignments for each environment
        $roleUri = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$envId/roleAssignments?api-version=2023-06-01"
        try {
            $roleResponse = Invoke-RestMethod -Uri $roleUri -Headers $headers -Method Get
            foreach ($ra in $roleResponse.value) {
                $assignments += @{
                    PrincipalId     = $ra.properties.principal.id
                    PrincipalType   = $ra.properties.principal.type
                    RoleName        = $ra.properties.roleDefinition.displayName
                    RoleId          = $ra.properties.roleDefinition.id
                    EnvironmentId   = $envId
                    EnvironmentName = $envDisplayName
                }
            }
        } catch {
            Write-Verbose "  Skipping environment $envDisplayName role query: $($_.Exception.Message)"
        }
    }

    return $assignments
}

function Get-ConflictRules {
    param(
        [string]$Environment,
        [string]$Token
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $uri = "$Environment/api/data/v9.2/fsi_conflictrules?`$filter=fsi_enabled eq true"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    return $response.value
}

function Get-ExistingViolations {
    param(
        [string]$Environment,
        [string]$Token
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $uri = "$Environment/api/data/v9.2/fsi_sodviolations?`$filter=fsi_status lt 5"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    return $response.value
}

function New-Violation {
    param(
        [string]$Environment,
        [string]$Token,
        [hashtable]$Violation
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $uri = "$Environment/api/data/v9.2/fsi_sodviolations"
    $body = $Violation | ConvertTo-Json -Depth 5

    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body
    return $response
}

function Test-RoleConflict {
    param(
        [array]$UserRoles,
        [object]$Rule
    )

    $hasRoleA = $UserRoles | Where-Object {
        $_.RoleName -eq $Rule.fsi_rolea -and
        $_.Context -eq $Rule.fsi_roleacontext
    }

    $hasRoleB = $UserRoles | Where-Object {
        $_.RoleName -eq $Rule.fsi_roleb -and
        $_.Context -eq $Rule.fsi_rolebcontext
    }

    if ($hasRoleA -and $hasRoleB) {
        return @{
            Conflict = $true
            RoleA = $hasRoleA | Select-Object -First 1
            RoleB = $hasRoleB | Select-Object -First 1
        }
    }

    return @{ Conflict = $false }
}

#endregion

#region Main Script

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Segregation of Duties Scanner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE - No violations will be created]" -ForegroundColor Yellow
    Write-Host ""
}

# Validate parameters
if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    Write-Error "Missing credentials. Set environment variables or provide parameters."
    exit 1
}

Write-Host "Environment: $Environment"
Write-Host "Tenant: $TenantId"
Write-Host ""

# Get tokens
Write-Host "Acquiring access tokens..." -ForegroundColor Gray
$graphToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "https://graph.microsoft.com/.default"
$dataverseToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default"
Write-Host "  Tokens acquired successfully" -ForegroundColor Green

# Get conflict rules
Write-Host ""
Write-Host "Loading conflict rules..." -ForegroundColor Gray
$rules = Get-ConflictRules -Environment $Environment -Token $dataverseToken
Write-Host "  Found $($rules.Count) active rules" -ForegroundColor Green

# Get existing violations
Write-Host ""
Write-Host "Loading existing violations..." -ForegroundColor Gray
$existingViolations = Get-ExistingViolations -Environment $Environment -Token $dataverseToken
Write-Host "  Found $($existingViolations.Count) open violations" -ForegroundColor Green

# Get Entra ID role assignments
Write-Host ""
Write-Host "Querying Entra ID directory roles..." -ForegroundColor Gray
$directoryRoles = Get-EntraDirectoryRoles -Token $graphToken
$roleAssignments = Get-EntraDirectoryRoleAssignments -Token $graphToken
Write-Host "  Found $($roleAssignments.Count) role assignments" -ForegroundColor Green

# Get Power Platform role assignments
Write-Host ""
Write-Host "Querying Power Platform role assignments..." -ForegroundColor Gray
$ppToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "https://api.bap.microsoft.com/.default"
$ppRoleAssignments = Get-PowerPlatformRoleAssignments -Token $ppToken
Write-Host "  Found $($ppRoleAssignments.Count) Power Platform role assignments" -ForegroundColor Green

# Build user role map
Write-Host ""
Write-Host "Building user role map..." -ForegroundColor Gray
$userRoleMap = @{}

foreach ($assignment in $roleAssignments) {
    $userId = $assignment.principalId
    $roleId = $assignment.roleDefinitionId
    $role = $directoryRoles | Where-Object { $_.roleTemplateId -eq $roleId }

    if ($role -and $assignment.principal.'@odata.type' -eq '#microsoft.graph.user') {
        $userPrincipalName = $assignment.principal.userPrincipalName
        $displayName = $assignment.principal.displayName

        if (-not $userRoleMap.ContainsKey($userId)) {
            $userRoleMap[$userId] = @{
                UserId = $userId
                UserPrincipalName = $userPrincipalName
                DisplayName = $displayName
                Roles = @()
            }
        }

        $userRoleMap[$userId].Roles += @{
            RoleName = $role.displayName
            RoleId = $role.id
            Context = 1  # Entra ID Directory Role
            Assignment = $assignment.id
        }
    }
}

Write-Host "  Mapped roles for $($userRoleMap.Count) users" -ForegroundColor Green

# Merge Power Platform role assignments into user role map
Write-Host ""
Write-Host "Merging Power Platform roles..." -ForegroundColor Gray
$ppUsersAdded = 0
foreach ($ppAssignment in $ppRoleAssignments) {
    $userId = $ppAssignment.PrincipalId
    if (-not $userId) { continue }

    if (-not $userRoleMap.ContainsKey($userId)) {
        $userRoleMap[$userId] = @{
            UserId = $userId
            UserPrincipalName = $userId  # PP API may not return UPN
            DisplayName = $userId
            Roles = @()
        }
        $ppUsersAdded++
    }

    $userRoleMap[$userId].Roles += @{
        RoleName = $ppAssignment.RoleName
        RoleId = $ppAssignment.RoleId
        Context = 2  # Power Platform Role
        Assignment = "$($ppAssignment.EnvironmentName):$($ppAssignment.RoleName)"
    }
}
Write-Host "  Merged PP roles ($ppUsersAdded new users added)" -ForegroundColor Green

# Scan for violations
Write-Host ""
Write-Host "Scanning for violations..." -ForegroundColor Gray
$newViolations = @()
$usersScanned = 0
$conflictsFound = 0

foreach ($userId in $userRoleMap.Keys) {
    $user = $userRoleMap[$userId]
    $usersScanned++

    foreach ($rule in $rules) {
        $result = Test-RoleConflict -UserRoles $user.Roles -Rule $rule

        if ($result.Conflict) {
            $conflictsFound++

            # Check if violation already exists
            $existingMatch = $existingViolations | Where-Object {
                $_.fsi_userobjectid -eq $userId -and
                $_.fsi_conflictruleid -eq $rule.fsi_conflictruleid
            }

            if ($existingMatch) {
                Write-Verbose "  Existing violation: $($user.UserPrincipalName) - $($rule.fsi_name)"
                continue
            }

            $violation = @{
                fsi_name = "$($user.DisplayName) - $($rule.fsi_name)"
                "fsi_conflictruleid@odata.bind" = "/fsi_conflictrules($($rule.fsi_conflictruleid))"
                fsi_userid = $user.UserPrincipalName
                fsi_userobjectid = $userId
                fsi_userdisplayname = $user.DisplayName
                fsi_roleaassignment = $result.RoleA.RoleName
                fsi_rolebassignment = $result.RoleB.RoleName
                fsi_status = 1  # Open
                fsi_detectedon = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $newViolations += $violation

            if ($DryRun) {
                Write-Host "  [DRY RUN] Would create: $($violation.fsi_name)" -ForegroundColor Yellow
            } else {
                Write-Host "  NEW: $($violation.fsi_name)" -ForegroundColor Red
            }
        }
    }
}

# Create violations
if (-not $DryRun -and $newViolations.Count -gt 0) {
    Write-Host ""
    Write-Host "Creating violation records..." -ForegroundColor Gray

    foreach ($violation in $newViolations) {
        try {
            New-Violation -Environment $Environment -Token $dataverseToken -Violation $violation | Out-Null
            Write-Host "  Created: $($violation.fsi_name)" -ForegroundColor Green
        } catch {
            Write-Host "  Failed: $($violation.fsi_name) - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Scan Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Users scanned:      $usersScanned"
Write-Host "Conflicts found:    $conflictsFound"
Write-Host "Existing violations: $($existingViolations.Count)"
Write-Host "New violations:     $($newViolations.Count)"
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN - No changes made]" -ForegroundColor Yellow
}

#endregion
