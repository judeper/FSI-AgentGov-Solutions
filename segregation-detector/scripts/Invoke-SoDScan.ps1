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

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://', ErrorMessage = "Environment URL must use HTTPS to protect bearer tokens in transit.")]
    [ValidateNotNullOrEmpty()]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = ($env:FSI_CLIENT_SECRET ?? $env:AZURE_CLIENT_SECRET),

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# Normalize Environment URL: strip trailing slashes to prevent malformed API URIs
$Environment = $Environment.TrimEnd('/')

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

# TODO: Invoke-RestMethodWithRetry and Get-AccessToken are duplicated in Import-ConflictRules.ps1.
# Extract to a shared module to prevent implementation drift (see GAP-0000-01).

#region Helper Functions

function Invoke-RestMethodWithRetry {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Method = "Get",
        $Body,
        [string]$ContentType,
        [int]$MaxRetries = 3
    )
    $attempt = 0
    while ($true) {
        try {
            $params = @{
                Uri     = $Uri
                Headers = $Headers
                Method  = $Method
            }
            if ($Body) { $params.Body = $Body }
            if ($ContentType) { $params.ContentType = $ContentType }
            return Invoke-RestMethod @params
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if (($statusCode -eq 429 -or $statusCode -ge 500) -and $attempt -lt $MaxRetries) {
                $retryAfter = $_.Exception.Response.Headers['Retry-After']
                $wait = if ($retryAfter) { [int]$retryAfter } else { [math]::Pow(2, $attempt + 1) }
                Write-Warning "HTTP $statusCode. Retrying after $wait seconds (attempt $($attempt+1)/$MaxRetries)..."
                Start-Sleep -Seconds $wait
                $attempt++
            } else {
                throw
            }
        }
    }
}

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

    $response = Invoke-RestMethodWithRetry -Uri $tokenUrl -Headers @{} -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    return $response.access_token
}

function Get-EntraDirectoryRoleAssignments {
    param([string]$Token)

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $assignments = [System.Collections.Generic.List[object]]::new()
    $uri = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$expand=principal"

    do {
        $response = Invoke-RestMethodWithRetry -Uri $uri -Headers $headers
        $assignments.AddRange([object[]]$response.value)
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

    $roles = [System.Collections.Generic.List[object]]::new()

    # Built-in activated roles
    $uri = "https://graph.microsoft.com/v1.0/directoryRoles"
    do {
        $response = Invoke-RestMethodWithRetry -Uri $uri -Headers $headers
        $roles.AddRange([object[]]$response.value)
        $uri = $response.'@odata.nextLink'
    } while ($uri)

    # Custom roles via unified RBAC (roleManagement/directory/roleDefinitions with isBuiltIn eq false)
    $customUri = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?`$filter=isBuiltIn eq false"
    try {
        do {
            $customResponse = Invoke-RestMethodWithRetry -Uri $customUri -Headers $headers
            $roles.AddRange([object[]]$customResponse.value)
            $customUri = $customResponse.'@odata.nextLink'
        } while ($customUri)
    } catch {
        Write-Warning "Unable to query custom Entra ID roles (requires RoleManagement.Read.Directory): $($_.Exception.Message)"
    }

    return $roles
}

function Get-PowerPlatformRoleAssignments {
    param([string]$Token)

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $assignments = [System.Collections.Generic.List[object]]::new()

    # Get all environments (with pagination)
    $envUri = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2023-06-01"
    $environments = @()
    try {
        do {
            $envResponse = Invoke-RestMethodWithRetry -Uri $envUri -Headers $headers
            $environments += $envResponse.value
            $envUri = $envResponse.nextLink
        } while ($envUri)
    } catch {
        Write-Warning "Unable to query Power Platform environments: $($_.Exception.Message)"
        Write-AuditLog "Power Platform environment query failed: $($_.Exception.Message)" -Level "ERROR"
        return $assignments
    }

    foreach ($env in $environments) {
        $envId = $env.name
        $envDisplayName = $env.properties.displayName

        # Get role assignments for each environment (with pagination)
        $roleUri = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$envId/roleAssignments?api-version=2023-06-01"
        try {
            do {
                $roleResponse = Invoke-RestMethodWithRetry -Uri $roleUri -Headers $headers
                foreach ($ra in $roleResponse.value) {
                    $assignments.Add(@{
                        PrincipalId     = $ra.properties.principal.id
                        PrincipalType   = $ra.properties.principal.type
                        RoleName        = $ra.properties.roleDefinition.displayName
                        RoleId          = $ra.properties.roleDefinition.id
                        EnvironmentId   = $envId
                        EnvironmentName = $envDisplayName
                    })
                }
                $roleUri = $roleResponse.nextLink
            } while ($roleUri)
        } catch {
            Write-Warning "  Skipping environment $envDisplayName role query: $($_.Exception.Message)"
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

    $results = @()
    $nextLink = "$Environment/api/data/v9.2/fsi_conflictrules?`$filter=fsi_enabled eq true"
    while ($nextLink) {
        $response = Invoke-RestMethodWithRetry -Uri $nextLink -Headers $headers
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
        $response = Invoke-RestMethodWithRetry -Uri $nextLink -Headers $headers
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

    $response = Invoke-RestMethodWithRetry -Uri $uri -Headers $headers -Method Post -Body $body
    return $response
}

function Test-RoleConflict {
    param(
        [array]$UserRoles,
        [object]$Rule
    )

    $hasRoleA = $UserRoles | Where-Object {
        $_.RoleName -ieq $Rule.fsi_rolea -and
        $_.Context -eq $Rule.fsi_roleacontext
    }

    $hasRoleB = $UserRoles | Where-Object {
        $_.RoleName -ieq $Rule.fsi_roleb -and
        $_.Context -eq $Rule.fsi_rolebcontext
    }

    if ($hasRoleA -and $hasRoleB) {
        # Determine if same-environment matching is required.
        # fsi_scope=3 (Same Environment) requires both roles in the same environment.
        # Also apply same-environment logic when both contexts are environment-scoped
        # (context 3=PP Env Role or context 4=Dataverse Security Role) and no explicit scope is set.
        $scope = $Rule.fsi_scope
        $bothEnvScoped = ($Rule.fsi_roleacontext -in @(3,4)) -and ($Rule.fsi_rolebcontext -in @(3,4))
        $requireSameEnv = ($scope -eq 3) -or ($bothEnvScoped -and (-not $scope -or $scope -eq 0))

        if ($requireSameEnv) {
            # Collect ALL matching environment pairs — not just the first one.
            # Each environment with both conflicting roles is a separate violation.
            $matches = [System.Collections.Generic.List[object]]::new()
            $seenEnvs = @{}
            foreach ($ra in @($hasRoleA)) {
                foreach ($rb in @($hasRoleB)) {
                    if ($ra.EnvironmentId -and $rb.EnvironmentId -and $ra.EnvironmentId -eq $rb.EnvironmentId) {
                        if (-not $seenEnvs.ContainsKey($ra.EnvironmentId)) {
                            $seenEnvs[$ra.EnvironmentId] = $true
                            $matches.Add(@{ RoleA = $ra; RoleB = $rb })
                        }
                    }
                }
            }
            if ($matches.Count -eq 0) { return @{ Conflict = $false } }
            return @{
                Conflict = $true
                Matches = $matches
            }
        }
        return @{
            Conflict = $true
            Matches = @(,@{
                RoleA = $hasRoleA | Select-Object -First 1
                RoleB = $hasRoleB | Select-Object -First 1
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

# Validate parameters
if (-not $ClientSecret) {
    throw "ClientSecret is required. Set FSI_CLIENT_SECRET environment variable or pass -ClientSecret parameter."
}
if (-not $TenantId -or -not $ClientId) {
    throw "TenantId and ClientId are required. Set AZURE_TENANT_ID / AZURE_CLIENT_ID environment variables or pass parameters."
}
Write-Warning "For production use, store secrets in Azure Key Vault and use Managed Identity."

# WARNING: No concurrency guard — parallel scans against the same environment may
# create duplicate violation records. Ensure only one scan runs per environment at a time.
Write-AuditLog "Scan started for environment $Environment (Tenant: $TenantId)" -Level "INFO"

Write-Host "Environment: $Environment"
Write-Host "Tenant: $TenantId"
Write-Host ""

# Get tokens (re-acquired before each phase to prevent mid-scan expiry)
Write-Host "Acquiring access tokens..." -ForegroundColor Gray
# Phase 1: Load conflict rules
$dataverseToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default"
Write-Host "  Dataverse token acquired" -ForegroundColor Green

# Get conflict rules
Write-Host ""
Write-Host "Loading conflict rules..." -ForegroundColor Gray
$rules = Get-ConflictRules -Environment $Environment -Token $dataverseToken
Write-AuditLog "Loaded $($rules.Count) active conflict rules"
Write-Host "  Found $($rules.Count) active rules" -ForegroundColor Green

if ($rules.Count -eq 0) {
    Write-Warning "No active conflict rules found. Import rules with Import-ConflictRules.ps1 before scanning."
    Write-AuditLog "Scan aborted: no active conflict rules" -Level "WARN"
    exit 2
}

# Phase 2: Load existing violations (fresh token)
Write-Host ""
Write-Host "Loading existing violations..." -ForegroundColor Gray
$dataverseToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default"
$existingViolations = Get-ExistingViolations -Environment $Environment -Token $dataverseToken
Write-Host "  Found $($existingViolations.Count) open violations" -ForegroundColor Green

# Phase 3: Query Entra ID (fresh token)
Write-Host ""
Write-Host "Querying Entra ID directory roles..." -ForegroundColor Gray
$graphToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "https://graph.microsoft.com/.default"
$directoryRoles = Get-EntraDirectoryRoles -Token $graphToken
$roleAssignments = Get-EntraDirectoryRoleAssignments -Token $graphToken
Write-Host "  Found $($roleAssignments.Count) role assignments" -ForegroundColor Green
Write-AuditLog "Queried $($roleAssignments.Count) Entra ID role assignments"

# NOTE: Dataverse security role scanning (context 4) is not yet implemented.
# Rules referencing fsi_roleacontext=4 or fsi_rolebcontext=4 will not match until
# a Dataverse security role query integration is added.
$context4Rules = @($rules | Where-Object { $_.fsi_roleacontext -eq 4 -or $_.fsi_rolebcontext -eq 4 })
if ($context4Rules.Count -gt 0) {
    Write-Warning "Dataverse security role scanning (context=4) is not yet implemented. $($context4Rules.Count) of $($rules.Count) active rules reference Dataverse security roles and will not produce matches."
    Write-AuditLog "$($context4Rules.Count) rules reference unimplemented Dataverse context (context=4)" -Level "WARN"
}

$context2Rules = @($rules | Where-Object { $_.fsi_roleacontext -eq 2 -or $_.fsi_rolebcontext -eq 2 })
if ($context2Rules.Count -gt 0) {
    Write-Warning "Entra ID App Role scanning (context=2) is not yet implemented. $($context2Rules.Count) of $($rules.Count) active rules reference Entra ID App Roles and will not produce matches."
    Write-AuditLog "$($context2Rules.Count) rules reference unimplemented Entra ID App Role context (context=2)" -Level "WARN"
}

$context5Rules = @($rules | Where-Object { $_.fsi_roleacontext -eq 5 -or $_.fsi_rolebcontext -eq 5 })
if ($context5Rules.Count -gt 0) {
    Write-Warning "Custom Application Role scanning (context=5) is not yet implemented. $($context5Rules.Count) of $($rules.Count) active rules reference Custom Application Roles and will not produce matches."
    Write-AuditLog "$($context5Rules.Count) rules reference unimplemented Custom Application Role context (context=5)" -Level "WARN"
}

# Phase 4: Get Power Platform role assignments (fresh token)
Write-Host ""
Write-Host "Querying Power Platform role assignments..." -ForegroundColor Gray
$ppToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "https://api.bap.microsoft.com/.default"
$ppRoleAssignments = Get-PowerPlatformRoleAssignments -Token $ppToken
Write-Host "  Found $($ppRoleAssignments.Count) Power Platform role assignments" -ForegroundColor Green
Write-AuditLog "Queried $($ppRoleAssignments.Count) Power Platform role assignments"

# Build user role map
Write-Host ""
Write-Host "Building user role map..." -ForegroundColor Gray
$userRoleMap = @{}

foreach ($assignment in $roleAssignments) {
    $userId = $assignment.principalId
    $roleId = $assignment.roleDefinitionId
    $role = $directoryRoles | Where-Object { $_.roleTemplateId -eq $roleId -or $_.id -eq $roleId }

    if ($role) {
        $principalType = $assignment.principal.'@odata.type'

        if ($principalType -eq '#microsoft.graph.user') {
            $userPrincipalName = $assignment.principal.userPrincipalName
            $displayName = $assignment.principal.displayName

            if (-not $userRoleMap.ContainsKey($userId)) {
                $userRoleMap[$userId] = @{
                    UserId = $userId
                    UserPrincipalName = $userPrincipalName
                    DisplayName = $displayName
                    Roles = [System.Collections.Generic.List[object]]::new()
                }
            }

            $userRoleMap[$userId].Roles.Add(@{
                RoleName = $role.displayName
                RoleId = $role.id
                Context = 1  # Entra ID Directory Role
                Assignment = $assignment.id
            })
        } elseif ($principalType -eq '#microsoft.graph.group') {
            # Resolve group members to capture transitive role assignments
            $groupId = $assignment.principalId
            try {
                $membersUri = "https://graph.microsoft.com/v1.0/groups/$groupId/transitiveMembers/microsoft.graph.user?`$select=id,userPrincipalName,displayName"
                do {
                    $membersResponse = Invoke-RestMethodWithRetry -Uri $membersUri -Headers @{
                        "Authorization" = "Bearer $graphToken"
                        "Content-Type"  = "application/json"
                    }
                    foreach ($member in $membersResponse.value) {
                        $memberId = $member.id
                        if (-not $userRoleMap.ContainsKey($memberId)) {
                            $userRoleMap[$memberId] = @{
                                UserId = $memberId
                                UserPrincipalName = $member.userPrincipalName
                                DisplayName = $member.displayName
                                Roles = [System.Collections.Generic.List[object]]::new()
                            }
                        }
                        $userRoleMap[$memberId].Roles.Add(@{
                            RoleName = $role.displayName
                            RoleId = $role.id
                            Context = 1  # Entra ID Directory Role (via group)
                            Assignment = "$($assignment.id):group:$groupId"
                        })
                    }
                    $membersUri = $membersResponse.'@odata.nextLink'
                } while ($membersUri)
            } catch {
                Write-Warning "Unable to resolve members of group $groupId for role $($role.displayName): $($_.Exception.Message)"
                Write-AuditLog "Group member resolution failed for group $groupId: $($_.Exception.Message)" -Level "WARN"
            }
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

    # Filter to user-type principals only; skip group and service principal assignments
    if ($ppAssignment.PrincipalType -and $ppAssignment.PrincipalType -ne 'User') {
        Write-Verbose "  Skipping non-user PP assignment: PrincipalType=$($ppAssignment.PrincipalType) Id=$userId"
        continue
    }

    if (-not $userRoleMap.ContainsKey($userId)) {
        $userRoleMap[$userId] = @{
            UserId = $userId
            UserPrincipalName = $userId  # PP API may not return UPN
            DisplayName = $userId
            Roles = [System.Collections.Generic.List[object]]::new()
        }
        $ppUsersAdded++
    }

    $userRoleMap[$userId].Roles.Add(@{
        RoleName = $ppAssignment.RoleName
        RoleId = $ppAssignment.RoleId
        Context = 3  # Power Platform Environment Role
        Assignment = "$($ppAssignment.EnvironmentId):$($ppAssignment.RoleName)"
        EnvironmentId = $ppAssignment.EnvironmentId
        EnvironmentName = $ppAssignment.EnvironmentName
    })
}
Write-Host "  Merged PP roles ($ppUsersAdded new users added)" -ForegroundColor Green

# Scan for violations
Write-Host ""
Write-Host "Scanning for violations..." -ForegroundColor Gray
$newViolations = [System.Collections.Generic.List[object]]::new()
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

                $envName = ($match.RoleA.EnvironmentName, $match.RoleB.EnvironmentName | Where-Object { $_ }) | Select-Object -First 1

                # Check if violation already exists (include environment to avoid
                # suppressing same user+rule conflicts across different environments)
                $existingMatch = $existingViolations | Where-Object {
                    $_.fsi_userobjectid -eq $userId -and
                    $_._fsi_conflictruleid_value -eq $rule.fsi_conflictruleid -and
                    $_.fsi_environment -eq $envName
                }

                if ($existingMatch) {
                    Write-Verbose "  Existing violation: $($user.UserPrincipalName) - $($rule.fsi_name) [$envName]"
                    continue
                }

                $violation = @{
                    fsi_name = "$($user.DisplayName) - $($rule.fsi_name)"
                    "fsi_conflictruleid@odata.bind" = "/fsi_conflictrules($($rule.fsi_conflictruleid))"
                    fsi_userid = $user.UserPrincipalName
                    fsi_userobjectid = $userId
                    fsi_userdisplayname = $user.DisplayName
                    fsi_roleaassignment = $match.RoleA.Assignment
                    fsi_rolebassignment = $match.RoleB.Assignment
                    fsi_status = 1  # Open
                    fsi_detectedon = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
                if ($envName) { $violation.fsi_environment = $envName }

                $newViolations.Add($violation)

                if ($DryRun) {
                    Write-Host "  [DRY RUN] Would create: $($violation.fsi_name)" -ForegroundColor Yellow
                } else {
                    Write-Host "  NEW: $($violation.fsi_name)" -ForegroundColor Red
                }
            }
        }
    }
}

# Phase 5: Create violations (fresh token)
$createdCount = 0
if (-not $DryRun -and $newViolations.Count -gt 0) {
    Write-Host ""
    Write-Host "Creating violation records..." -ForegroundColor Gray
    $dataverseToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default"

    foreach ($violation in $newViolations) {
        if ($PSCmdlet.ShouldProcess("Violation: $($violation.fsi_name)", "Create in $Environment")) {
            try {
                New-Violation -Environment $Environment -Token $dataverseToken -Violation $violation | Out-Null
                $createdCount++
                Write-Host "  Created: $($violation.fsi_name)" -ForegroundColor Green
            } catch {
                Write-Host "  Failed: $($violation.fsi_name) - $($_.Exception.Message)" -ForegroundColor Red
                Write-AuditLog "Failed to create violation '$($violation.fsi_name)': $($_.Exception.Message)" -Level "ERROR"
            }
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
Write-Host "New violations:     $($newViolations.Count) detected, $createdCount created"
Write-AuditLog "Scan complete. Users=$usersScanned Conflicts=$conflictsFound Existing=$($existingViolations.Count) NewDetected=$($newViolations.Count) NewCreated=$createdCount"
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN - No changes made]" -ForegroundColor Yellow
}

# NOTE: Dataverse audit log writing (fsi_sodauditlog, event type 10) is not yet
# implemented. Write-AuditLog currently outputs to console only.

# Exit with meaningful code for CI/CD pipeline integration
if ($createdCount -lt $newViolations.Count -and -not $DryRun) {
    exit 2  # Some violations failed to create in Dataverse
} elseif ($newViolations.Count -gt 0) {
    exit 1  # Violations detected
}
exit 0  # Clean scan

#endregion
