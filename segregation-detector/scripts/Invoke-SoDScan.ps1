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
    [ValidatePattern('^https://[\w.-]+\.(crm\d*\.dynamics\.com|crm\.microsoftdynamics\.us|crm\.appsplatform\.us|crm\.dynamics\.cn)/?$')]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    # Prefer environment variables (FSI_CLIENT_SECRET or AZURE_CLIENT_SECRET) over the -ClientSecret
    # parameter to avoid exposing secrets in process listings, shell history, and transcript logs.
    [ValidateNotNullOrEmpty()]
    [string]$ClientSecret = ($env:FSI_CLIENT_SECRET ?? $env:AZURE_CLIENT_SECRET),

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# Import shared helper functions (Invoke-WithRetry, Get-AccessToken, Get-BapApiBaseUrl)
. (Join-Path $PSScriptRoot "SoDShared.ps1")

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

#region Helper Functions

function Get-EntraDirectoryRoleAssignments {
    param([string]$Token)

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $assignments = @()
    $uri = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$expand=principal"

    do {
        try {
            $response = Invoke-WithRetry { Invoke-RestMethod -Uri $uri -Headers $headers -Method Get }
        } catch {
            Write-Warning "Failed to query Entra directory role assignments: $($_.Exception.Message)"
            return $assignments
        }
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
    try {
        $response = Invoke-WithRetry { Invoke-RestMethod -Uri $uri -Headers $headers -Method Get }
    } catch {
        Write-Warning "Failed to query Entra directory roles: $($_.Exception.Message)"
        return @()
    }
    return $response.value
}

function Get-PowerPlatformRoleAssignments {
    param(
        [string]$Token,
        [string]$EnvironmentUrl
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $assignments = @()

    # Derive BAP API base URL from environment domain (supports sovereign clouds)
    $bapBase = Get-BapApiBaseUrl -EnvironmentUrl $EnvironmentUrl

    # Get all environments
    $envUri = "$bapBase/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2023-06-01"
    try {
        $envResponse = Invoke-WithRetry { Invoke-RestMethod -Uri $envUri -Headers $headers -Method Get }
    } catch {
        Write-Warning "Unable to query Power Platform environments: $($_.Exception.Message)"
        return $assignments
    }

    foreach ($env in $envResponse.value) {
        $envId = $env.name
        $envDisplayName = $env.properties.displayName

        # Get role assignments for each environment
        $roleUri = "$bapBase/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$envId/roleAssignments?api-version=2023-06-01"
        try {
            $roleResponse = Invoke-WithRetry { Invoke-RestMethod -Uri $roleUri -Headers $headers -Method Get }
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

function Get-DataverseSecurityRoleAssignments {
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

    $results = @()
    $nextLink = "$Environment/api/data/v9.2/systemusers?`$select=systemuserid,azureactivedirectoryobjectid,domainname,fullname&`$expand=systemuserroles_association(`$select=name,roleid)&`$filter=isdisabled eq false"
    while ($nextLink) {
        try {
            $response = Invoke-WithRetry { Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get }
        } catch {
            Write-Warning "Failed to query Dataverse security role assignments: $($_.Exception.Message)"
            return $results
        }
        foreach ($user in $response.value) {
            foreach ($role in $user.systemuserroles_association) {
                $results += @{
                    PrincipalId = $user.azureactivedirectoryobjectid
                    DomainName  = $user.domainname
                    DisplayName = $user.fullname
                    RoleName    = $role.name
                    RoleId      = $role.roleid
                }
            }
        }
        $nextLink = $response.'@odata.nextLink'
    }

    return $results
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

    $results = @()
    $nextLink = "$Environment/api/data/v9.2/fsi_conflictrules?`$filter=fsi_enabled eq true"
    while ($nextLink) {
        $response = Invoke-WithRetry { Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get }
        $results += $response.value
        $nextLink = $response.'@odata.nextLink'
    }
    return $results
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

    $results = @()
    $nextLink = "$Environment/api/data/v9.2/fsi_sodviolations?`$filter=fsi_status lt 5"
    while ($nextLink) {
        $response = Invoke-WithRetry { Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get }
        $results += $response.value
        $nextLink = $response.'@odata.nextLink'
    }
    return $results
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

    $response = Invoke-WithRetry { Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body }
    return $response
}

function Test-RoleConflict {
    param(
        [array]$UserRoles,
        [object]$Rule
    )

    $matchesA = @($UserRoles | Where-Object {
        $_.RoleName -eq $Rule.fsi_rolea -and
        $_.Context -eq $Rule.fsi_roleacontext
    })

    $matchesB = @($UserRoles | Where-Object {
        $_.RoleName -eq $Rule.fsi_roleb -and
        $_.Context -eq $Rule.fsi_rolebcontext
    })

    if ($matchesA.Count -gt 0 -and $matchesB.Count -gt 0) {
        # When both roles are Power Platform Environment roles, require same environment
        # and collect ALL matching environment pairs (not just the first)
        if ($Rule.fsi_roleacontext -eq 3 -and $Rule.fsi_rolebcontext -eq 3) {
            $conflicts = @()
            foreach ($roleA in $matchesA) {
                foreach ($roleB in $matchesB) {
                    if ($roleA.EnvironmentId -and $roleB.EnvironmentId -and
                        $roleA.EnvironmentId -eq $roleB.EnvironmentId) {
                        $conflicts += @{
                            RoleA = $roleA
                            RoleB = $roleB
                        }
                    }
                }
            }
            if ($conflicts.Count -gt 0) {
                return @{ Conflict = $true; Matches = $conflicts }
            }
            return @{ Conflict = $false }
        }

        return @{
            Conflict = $true
            Matches  = @(,@{
                RoleA = $matchesA | Select-Object -First 1
                RoleB = $matchesB | Select-Object -First 1
            })
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

Write-AuditLog -Message "SoD scan started for environment $Environment (DryRun=$DryRun)"

# Validate parameters
if (-not $ClientSecret) {
    throw "ClientSecret is required. Set FSI_CLIENT_SECRET environment variable or pass -ClientSecret parameter."
}
if (-not $TenantId -or -not $ClientId) {
    throw "TenantId and ClientId are required. Set AZURE_TENANT_ID / AZURE_CLIENT_ID environment variables or pass parameters."
}
Write-Warning "For production use, store secrets in Azure Key Vault and use Managed Identity."

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
$bapBaseUrl = Get-BapApiBaseUrl -EnvironmentUrl $Environment
$ppToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$bapBaseUrl/.default"
$ppRoleAssignments = Get-PowerPlatformRoleAssignments -Token $ppToken -EnvironmentUrl $Environment
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
        RoleName      = $ppAssignment.RoleName
        RoleId        = $ppAssignment.RoleId
        Context       = 3  # Power Platform Environment Role
        EnvironmentId = $ppAssignment.EnvironmentId
        Assignment    = "$($ppAssignment.EnvironmentName):$($ppAssignment.RoleName)"
    }
}
Write-Host "  Merged PP roles ($ppUsersAdded new users added)" -ForegroundColor Green

# Get Dataverse security role assignments
Write-Host ""
Write-Host "Querying Dataverse security roles..." -ForegroundColor Gray
$dvRoleAssignments = Get-DataverseSecurityRoleAssignments -Environment $Environment -Token $dataverseToken
Write-Host "  Found $($dvRoleAssignments.Count) Dataverse security role assignments" -ForegroundColor Green

# Merge Dataverse security roles into user role map
Write-Host ""
Write-Host "Merging Dataverse security roles..." -ForegroundColor Gray
$dvUsersAdded = 0
foreach ($dvAssignment in $dvRoleAssignments) {
    $userId = $dvAssignment.PrincipalId
    if (-not $userId) { continue }

    if (-not $userRoleMap.ContainsKey($userId)) {
        $userRoleMap[$userId] = @{
            UserId = $userId
            UserPrincipalName = $dvAssignment.DomainName
            DisplayName = $dvAssignment.DisplayName
            Roles = @()
        }
        $dvUsersAdded++
    }

    $userRoleMap[$userId].Roles += @{
        RoleName = $dvAssignment.RoleName
        RoleId = $dvAssignment.RoleId
        Context = 4  # Dataverse Security Role
        Assignment = "Dataverse:$($dvAssignment.RoleName)"
    }
}
Write-Host "  Merged Dataverse roles ($dvUsersAdded new users added)" -ForegroundColor Green

# NOTE: Entra ID App Role assignments (context 2) and Custom Application Roles (context 5)
# are not currently queried. Rules targeting these contexts will not match.
# See Known Limitations in README.md.

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
            foreach ($match in $result.Matches) {
                $conflictsFound++

                # Check if violation already exists (include environment for context-3 rules)
                $matchEnvId = $match.RoleA.EnvironmentId
                $existingMatch = $existingViolations | Where-Object {
                    $_.fsi_userobjectid -eq $userId -and
                    $_._fsi_conflictruleid_value -eq $rule.fsi_conflictruleid -and
                    (-not $matchEnvId -or $_.fsi_environment -eq $matchEnvId)
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
                    fsi_roleaassignment = $match.RoleA.RoleName
                    fsi_rolebassignment = $match.RoleB.RoleName
                    fsi_status = 1  # Open
                    fsi_detectedon = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
                if ($matchEnvId) {
                    $violation.fsi_environment = $matchEnvId
                }

                $newViolations += $violation

                if ($DryRun) {
                    Write-Host "  [DRY RUN] Would create: $($violation.fsi_name)" -ForegroundColor Yellow
                } else {
                    Write-Host "  NEW: $($violation.fsi_name)" -ForegroundColor Red
                }
                Write-AuditLog -Message "Violation detected: $($violation.fsi_name)" -Level "WARN"
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

Write-AuditLog -Message "SoD scan completed: $usersScanned users scanned, $conflictsFound conflicts found, $($newViolations.Count) new violations"

#endregion
