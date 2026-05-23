#Requires -Version 7.1

<#
.SYNOPSIS
    Scans for Segregation of Duties violations across Entra ID and Power Platform.

.DESCRIPTION
    This script queries role assignments from multiple sources and compares them
    against configured conflict rules to detect SoD violations.

.PARAMETER Environment
    The Dataverse environment URL (e.g., https://your-org.crm.dynamics.com)

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. If not specified, uses AZURE_TENANT_ID environment variable.

.PARAMETER ClientId
    Application (client) ID for WorkloadIdentity or legacy ClientSecret auth. If not specified, uses AZURE_CLIENT_ID.

.PARAMETER AuthMode
    Authentication mode. Defaults to ManagedIdentity. Use WorkloadIdentity for federated CI runners or ClientSecret only as a legacy dev fallback.

.PARAMETER ManagedIdentityClientId
    Optional user-assigned managed identity client ID. If not specified, uses AZURE_CLIENT_ID when AuthMode is ManagedIdentity.

.PARAMETER FederatedTokenFile
    Federated token file path for WorkloadIdentity auth. If not specified, uses AZURE_FEDERATED_TOKEN_FILE.

.PARAMETER ClientSecret
    Legacy dev-only client secret. If not specified, uses FSI_CLIENT_SECRET or AZURE_CLIENT_SECRET when AuthMode is ClientSecret.

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
    [ValidatePattern('^https://[\w.-]+\.(crm(?!9\b)\d*\.dynamics\.com|crm\.microsoftdynamics\.us|crm\.appsplatform\.us|crm\.dynamics\.cn)/?$')]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [ValidateSet("ManagedIdentity", "WorkloadIdentity", "ClientSecret")]
    [string]$AuthMode = ($env:FSI_AUTH_MODE ?? "ManagedIdentity"),

    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityClientId = ($env:MANAGED_IDENTITY_CLIENT_ID ?? $env:AZURE_CLIENT_ID),

    [Parameter(Mandatory = $false)]
    [string]$FederatedTokenFile = $env:AZURE_FEDERATED_TOKEN_FILE,

    [Parameter(Mandatory = $false)]
    # legacy: dev-only -- replace with managed identity in production
    # Prefer environment variables (FSI_CLIENT_SECRET or AZURE_CLIENT_SECRET) over the -ClientSecret
    # parameter to avoid exposing secrets in process listings, shell history, and transcript logs.
    # Note: do NOT use [ValidateNotNullOrEmpty()] here -- the parameter resolves at bind time, before
    # the manual check below can run, and the validator's generic message would mask the actionable
    # "FSI_CLIENT_SECRET / AZURE_CLIENT_SECRET" guidance the script emits later. (Council Opus #6)
    [string]$ClientSecret = ($env:FSI_CLIENT_SECRET ?? $env:AZURE_CLIENT_SECRET),

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    # When set, allow the scan to continue even if Power Platform BAP role enumeration fails for
    # ALL environments. Default is fail-closed: a complete BAP outage exits non-zero so operators
    # do not interpret an empty scan as "no violations". (Council Opus #3 / Goldeneye #2)
    [switch]$AllowPartialResults
)

$ErrorActionPreference = "Stop"

# Expose param to function scope (used by Get-PowerPlatformRoleAssignments fail-closed guard)
$script:AllowPartialResults = $AllowPartialResults

# Normalize: strip trailing slash to prevent double-slash in API URLs
$Environment = $Environment.TrimEnd('/')

# Import shared helper functions (Invoke-WithRetry, Get-AccessToken, Get-BapApiBaseUrl)
. (Join-Path $PSScriptRoot "SoDShared.ps1")
$script:SoDChoices = Get-SoDChoiceValues

# Structured audit logging (console only; Dataverse fsi_sodauditlog persistence is planned but not yet implemented)
function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$CorrelationId = $script:CorrelationId
    )
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ" -AsUTC
    Write-Host "[$timestamp] [$Level] [$CorrelationId] $Message"
}
$script:CorrelationId = [guid]::NewGuid().ToString("N").Substring(0,8)

#region Helper Functions

function Get-EntraDirectoryRoleAssignments {
    param([string]$Token, [string]$GraphEndpoint = "https://graph.microsoft.com")

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $assignments = [System.Collections.Generic.List[object]]::new()
    # Microsoft Graph v1.0 PIM schedule instances include active assignments made
    # through PIM activation requests and direct role assignments.
    $uri = "$GraphEndpoint/v1.0/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal"

    do {
        try {
            $response = Invoke-WithRetry { Invoke-RestMethod -Uri $uri -Headers $headers -Method Get }
        } catch {
            Write-Warning "Failed to query Entra active directory role assignment schedule instances: $($_.Exception.Message)"
            throw
        }
        $assignments.AddRange([object[]]$response.value)
        $uri = $response.'@odata.nextLink'
    } while ($uri)

    return $assignments
}

function Get-EntraDirectoryRoles {
    param([string]$Token, [string]$GraphEndpoint = "https://graph.microsoft.com")

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $roles = [System.Collections.Generic.List[object]]::new()
    $uri = "$GraphEndpoint/v1.0/roleManagement/directory/roleDefinitions"

    do {
        try {
            $response = Invoke-WithRetry { Invoke-RestMethod -Uri $uri -Headers $headers -Method Get }
        } catch {
            Write-Warning "Failed to query Entra directory roles: $($_.Exception.Message)"
            throw
        }
        $roles.AddRange([object[]]$response.value)
        $uri = $response.'@odata.nextLink'
    } while ($uri)

    return $roles
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

    $assignments = [System.Collections.Generic.List[object]]::new()

    # Derive BAP API base URL from environment domain (supports sovereign clouds)
    $bapBase = Get-BapApiBaseUrl -EnvironmentUrl $EnvironmentUrl

    # Get all environments (follow nextLink for pagination)
    $envUri = "$bapBase/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2023-06-01"
    $environments = [System.Collections.Generic.List[object]]::new()
    do {
        try {
            $envResponse = Invoke-WithRetry { Invoke-RestMethod -Uri $envUri -Headers $headers -Method Get }
        } catch {
            Write-Warning "Unable to query Power Platform environments: $($_.Exception.Message)"
            throw
        }
        $environments.AddRange([object[]]$envResponse.value)
        $envUri = $envResponse.nextLink
    } while ($envUri)

    $skippedCount = 0
    $totalEnvironments = $environments.Count
    foreach ($env in $environments) {
        $envId = $env.name
        $envDisplayName = $env.properties.displayName

        # Get role assignments for each environment (follow nextLink for pagination)
        $roleUri = "$bapBase/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$envId/roleAssignments?api-version=2023-06-01"
        do {
            try {
                $roleResponse = Invoke-WithRetry { Invoke-RestMethod -Uri $roleUri -Headers $headers -Method Get }
                foreach ($ra in $roleResponse.value) {
                    # Filter to user principals only -- groups and service principals would otherwise
                    # be merged into the user role map and emit false-positive SoD violations against
                    # GUIDs that are not real users. (Council Opus #1 / Goldeneye #4)
                    $principalType = $ra.properties.principal.type
                    if ($principalType -and $principalType -ne 'User') { continue }

                    $assignments.Add(@{
                        PrincipalId     = $ra.properties.principal.id
                        PrincipalType   = $principalType
                        RoleName        = $ra.properties.roleDefinition.displayName
                        RoleId          = $ra.properties.roleDefinition.id
                        EnvironmentId   = $envId
                        EnvironmentName = $envDisplayName
                    })
                }
                $roleUri = $roleResponse.nextLink
            } catch {
                Write-Verbose "  Skipping environment $envDisplayName role query: $($_.Exception.Message)"
                $skippedCount++
                $roleUri = $null
            }
        } while ($roleUri)
    }
    if ($skippedCount -gt 0) {
        Write-Warning "$skippedCount of $totalEnvironments environment(s) failed Power Platform role queries -- results may be incomplete"
        # Fail closed when ALL environment queries failed -- silently returning an empty
        # assignment set would be reported as "no violations" when in fact no data was
        # retrieved (e.g., service principal not registered with New-PowerAppManagementApp,
        # or BAP outage). (Council Opus #3 / Goldeneye #2)
        if ($skippedCount -eq $totalEnvironments -and $totalEnvironments -gt 0) {
            if ($script:AllowPartialResults) {
                Write-Warning "All Power Platform environment role queries failed; -AllowPartialResults set, continuing with empty PP role data."
            }
            else {
                throw "All $totalEnvironments Power Platform environment role queries failed. Verify the service principal is registered as a Power Platform admin (New-PowerAppManagementApp -ApplicationId <ClientId>) and re-run, or pass -AllowPartialResults to override."
            }
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

    $results = [System.Collections.Generic.List[hashtable]]::new()
    # Filter out application users (service principals provisioned as systemusers) -- they would
    # otherwise be merged into the user role map and reported as SoD violators against the
    # service principal's Microsoft Entra object ID. (Council Opus #2)
    $nextLink = "$Environment/api/data/v9.2/systemusers?`$select=systemuserid,azureactivedirectoryobjectid,domainname,fullname&`$expand=systemuserroles_association(`$select=name,roleid)&`$filter=isdisabled eq false and applicationid eq null"
    while ($nextLink) {
        try {
            $response = Invoke-WithRetry { Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get }
        } catch {
            Write-Warning "Failed to query Dataverse security role assignments: $($_.Exception.Message)"
            throw
        }
        foreach ($user in $response.value) {
            foreach ($role in $user.systemuserroles_association) {
                $results.Add(@{
                    PrincipalId = $user.azureactivedirectoryobjectid
                    DomainName  = $user.domainname
                    DisplayName = $user.fullname
                    RoleName    = $role.name
                    RoleId      = $role.roleid
                })
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

    $results = [System.Collections.Generic.List[object]]::new()
    $nextLink = "$Environment/api/data/v9.2/fsi_conflictrules?`$filter=fsi_enabled eq true"
    while ($nextLink) {
        try {
            $response = Invoke-WithRetry { Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get }
        } catch {
            Write-Warning "Failed to query conflict rules: $($_.Exception.Message)"
            throw
        }
        $results.AddRange([object[]]$response.value)
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

    $results = [System.Collections.Generic.List[object]]::new()
    $activeStatusUpperBound = $script:SoDChoices.ViolationStatus['ResolvedRoleRemoved']
    $nextLink = "$Environment/api/data/v9.2/fsi_sodviolations?`$filter=fsi_status lt $activeStatusUpperBound"
    while ($nextLink) {
        try {
            $response = Invoke-WithRetry { Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get }
        } catch {
            Write-Warning "Failed to query existing violations (page $([Math]::Floor($results.Count / 50) + 1)): $($_.Exception.Message)"
            throw
        }
        $results.AddRange([object[]]$response.value)
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
        if ($Rule.fsi_roleacontext -eq $script:SoDChoices.RoleContext['PowerPlatformEnvironmentRole'] -and $Rule.fsi_rolebcontext -eq $script:SoDChoices.RoleContext['PowerPlatformEnvironmentRole']) {
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

# Validate authentication parameters
switch ($AuthMode) {
    "ManagedIdentity" {
        Write-Host "Authentication: ManagedIdentity" -ForegroundColor Gray
    }
    "WorkloadIdentity" {
        if (-not $TenantId -or -not $ClientId) {
            throw "TenantId and ClientId are required for WorkloadIdentity auth. Set AZURE_TENANT_ID / AZURE_CLIENT_ID or pass parameters."
        }
        if (-not $FederatedTokenFile) {
            throw "FederatedTokenFile is required for WorkloadIdentity auth. Set AZURE_FEDERATED_TOKEN_FILE or pass -FederatedTokenFile."
        }
        Write-Host "Authentication: WorkloadIdentity" -ForegroundColor Gray
    }
    "ClientSecret" {
        # legacy: dev-only -- replace with managed identity in production
        if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
            throw "TenantId, ClientId, and ClientSecret are required for legacy ClientSecret auth. Prefer -AuthMode ManagedIdentity or WorkloadIdentity for production."
        }
        Write-Warning "ClientSecret auth is legacy dev-only. Use ManagedIdentity for Azure-hosted runs or WorkloadIdentity for federated CI."
    }
}

Write-Host "Environment: $Environment"
if ($TenantId) { Write-Host "Tenant: $TenantId" }
Write-Host ""

$tokenParams = @{
    TenantId                = $TenantId
    ClientId                = $ClientId
    ClientSecret            = $ClientSecret
    AuthMode                = $AuthMode
    ManagedIdentityClientId = $ManagedIdentityClientId
    FederatedTokenFile      = $FederatedTokenFile
}

# Get tokens
Write-Host "Acquiring access tokens..." -ForegroundColor Gray
$graphEndpoint = Get-GraphEndpoint -EnvironmentUrl $Environment
$graphToken = Get-AccessToken @tokenParams -Scope "$graphEndpoint/.default"
$dataverseToken = Get-AccessToken @tokenParams -Scope "$Environment/.default"
Write-Host "  Tokens acquired successfully" -ForegroundColor Green

# Get conflict rules
Write-Host ""
Write-Host "Loading conflict rules..." -ForegroundColor Gray
$rules = Get-ConflictRules -Environment $Environment -Token $dataverseToken
Write-Host "  Found $($rules.Count) active rules" -ForegroundColor Green
if ($rules.Count -eq 0) {
    Write-Warning "No active conflict rules found. Import rules with Import-ConflictRules.ps1 before scanning."
}

# Get existing violations
Write-Host ""
Write-Host "Loading existing violations..." -ForegroundColor Gray
$existingViolations = Get-ExistingViolations -Environment $Environment -Token $dataverseToken
Write-Host "  Found $($existingViolations.Count) open violations" -ForegroundColor Green

# Build hashtable index for O(1) violation deduplication
$violationIndex = @{}
foreach ($v in $existingViolations) {
    $baseKey = "$($v.fsi_userobjectid)|$($v._fsi_conflictruleid_value)"
    $violationIndex[$baseKey] = $true
    if ($v.fsi_environment) {
        $violationIndex["$baseKey|$($v.fsi_environment)"] = $true
    }
}

# Get Entra ID role assignments
Write-Host ""
Write-Host "Querying Entra ID directory roles..." -ForegroundColor Gray
$directoryRoles = Get-EntraDirectoryRoles -Token $graphToken -GraphEndpoint $graphEndpoint
$roleAssignments = Get-EntraDirectoryRoleAssignments -Token $graphToken -GraphEndpoint $graphEndpoint
Write-Host "  Found $($roleAssignments.Count) active role assignment schedule instances" -ForegroundColor Green

# Build hashtable for O(1) directory role lookup by ID
$directoryRoleLookup = @{}
foreach ($dr in $directoryRoles) { $directoryRoleLookup[$dr.id] = $dr }

# Get Power Platform role assignments
Write-Host ""
Write-Host "Querying Power Platform role assignments..." -ForegroundColor Gray
$bapBaseUrl = Get-BapApiBaseUrl -EnvironmentUrl $Environment
$ppToken = Get-AccessToken @tokenParams -Scope "$bapBaseUrl/.default"
$ppRoleAssignments = Get-PowerPlatformRoleAssignments -Token $ppToken -EnvironmentUrl $Environment
Write-Host "  Found $($ppRoleAssignments.Count) Power Platform role assignments" -ForegroundColor Green

# Build user role map
Write-Host ""
Write-Host "Building user role map..." -ForegroundColor Gray
$userRoleMap = @{}

$skippedAssignments = 0
foreach ($assignment in $roleAssignments) {
    $userId = $assignment.principalId
    $roleId = $assignment.roleDefinitionId
    $role = $directoryRoleLookup[$roleId]

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
            Context = $script:SoDChoices.RoleContext['EntraDirectoryRole']  # Entra ID Directory Role
            Assignment = $assignment.id
        }
    }
    else {
        # Track silent drops so operators can detect when the SP lacks principal-expansion
        # permissions or principals were deleted, instead of seeing an empty result. (Council Opus #5)
        $skippedAssignments++
    }
}

if ($skippedAssignments -gt 0) {
    Write-Warning "$skippedAssignments Entra active role assignment schedule instance(s) skipped (principal not expanded as user, deleted, or non-user principal). If this number is high, verify the identity holds Directory.Read.All and RoleAssignmentSchedule.Read.Directory (or a higher privileged Graph permission) and that `?$expand=principal` returned data."
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
        Context       = $script:SoDChoices.RoleContext['PowerPlatformEnvironmentRole']  # Power Platform Environment Role
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
    } elseif ($userRoleMap[$userId].UserPrincipalName -eq $userId) {
        # Update fallback identity (GUID) with richer Dataverse data
        $userRoleMap[$userId].UserPrincipalName = $dvAssignment.DomainName
        $userRoleMap[$userId].DisplayName = $dvAssignment.DisplayName
    }

    $userRoleMap[$userId].Roles += @{
        RoleName = $dvAssignment.RoleName
        RoleId = $dvAssignment.RoleId
        Context = $script:SoDChoices.RoleContext['DataverseSecurityRole']  # Dataverse Security Role
        Assignment = "Dataverse:$($dvAssignment.RoleName)"
    }
}
Write-Host "  Merged Dataverse roles ($dvUsersAdded new users added)" -ForegroundColor Green

# NOTE: Entra ID App Role assignments and Custom Application Roles
# are not currently queried. Rules targeting these contexts will not match.
# See Known Limitations in README.md.

# Scan for violations
Write-Host ""
Write-Host "Scanning for violations..." -ForegroundColor Gray
$newViolations = [System.Collections.Generic.List[hashtable]]::new()
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

                # Check if violation already exists using hashtable index (O(1) lookup)
                $matchEnvId = $match.RoleA.EnvironmentId
                $existingMatch = if ($matchEnvId) {
                    $violationIndex.ContainsKey("$userId|$($rule.fsi_conflictruleid)|$matchEnvId")
                } else {
                    $violationIndex.ContainsKey("$userId|$($rule.fsi_conflictruleid)")
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
                    fsi_roleaassignment = $(if ($match.RoleA.Context -eq $script:SoDChoices.RoleContext['PowerPlatformEnvironmentRole']) { $match.RoleA.Assignment } else { $match.RoleA.RoleName })
                    fsi_rolebassignment = $(if ($match.RoleB.Context -eq $script:SoDChoices.RoleContext['PowerPlatformEnvironmentRole']) { $match.RoleB.Assignment } else { $match.RoleB.RoleName })
                    fsi_status = $script:SoDChoices.ViolationStatus['Open']  # Open
                    fsi_detectedon = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
                if ($matchEnvId) {
                    $violation.fsi_environment = $matchEnvId
                }

                $newViolations.Add($violation)

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
    $createdCount = 0
    $failedCount = 0

    foreach ($violation in $newViolations) {
        try {
            New-Violation -Environment $Environment -Token $dataverseToken -Violation $violation | Out-Null
            $createdCount++
            Write-Host "  Created: $($violation.fsi_name)" -ForegroundColor Green
        } catch {
            $failedCount++
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
if (-not $DryRun -and $newViolations.Count -gt 0) {
    Write-Host "  Created:          $createdCount"
    Write-Host "  Failed:           $failedCount"
}
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN - No changes made]" -ForegroundColor Yellow
}

$persistedCount = if ($DryRun -or $newViolations.Count -eq 0) { 0 } else { $createdCount }
$activeOpenCount = $existingViolations.Count + $newViolations.Count
Write-AuditLog -Message "SoD scan completed: $usersScanned users scanned, $conflictsFound conflicts found, $($newViolations.Count) new violations ($persistedCount persisted), $($existingViolations.Count) pre-existing open violations"

# Exit-code semantics for CI/CD pipeline gates (Council Opus #13 / Goldeneye #1):
#   * In -DryRun mode, NEVER fail the build -- dry runs are evidence collection and would
#     otherwise block every CI run that finds even pre-existing conflicts.
#   * Otherwise, exit non-zero if ANY active conflicts exist (newly detected OR previously
#     recorded but not yet resolved). The earlier behavior of gating only on "newly created"
#     allowed repeat runs to return 0 while the same SoD violation remained open.
if ($DryRun) {
    exit 0
}
if ($activeOpenCount -gt 0) {
    Write-Host "Pipeline gate: $activeOpenCount unresolved SoD violation(s) remain open ($($existingViolations.Count) pre-existing + $($newViolations.Count) new). Exiting non-zero." -ForegroundColor Red
    exit 1
}
exit 0

#endregion
