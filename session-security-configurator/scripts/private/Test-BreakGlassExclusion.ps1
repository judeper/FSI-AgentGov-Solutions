#Requires -Version 7.0

<#
.SYNOPSIS
    Validates that break-glass accounts are excluded from a Conditional Access policy.

.DESCRIPTION
    Critical safety check to prevent tenant lockout. Verifies that all break-glass
    (emergency access) accounts are excluded from a CA policy either directly via
    excludeUsers or indirectly via excludeGroups membership.

    This function MUST be called before every CA policy deployment operation.
    Deployment should be aborted if break-glass validation fails.

.PARAMETER PolicyTemplate
    Hashtable representing the CA policy template. Must contain:
    - conditions.users.excludeUsers (array of user object IDs)
    - conditions.users.excludeGroups (array of group object IDs)

.PARAMETER Config
    Configuration object containing breakGlassAccounts array (user object IDs).

.PARAMETER DryRun
    When true, skip Graph API calls for group membership resolution.
    Only checks direct user exclusions. Useful for template validation.

.EXAMPLE
    $config = @{ breakGlassAccounts = @("user-guid-1", "user-guid-2") }
    $policyTemplate = @{
        displayName = "SSC-Zone2-Session-Controls"
        conditions = @{
            users = @{
                excludeUsers = @("user-guid-1", "user-guid-2")
            }
        }
    }
    Test-BreakGlassExclusion -PolicyTemplate $policyTemplate -Config $config

    Returns $true if all break-glass accounts are excluded directly.

.EXAMPLE
    Test-BreakGlassExclusion -PolicyTemplate $policyTemplate -Config $config -DryRun
    Checks only direct exclusions, skips group membership resolution.

.OUTPUTS
    System.Boolean
    Returns $true if ALL break-glass accounts are excluded (safe to deploy).
    Returns $false if ANY break-glass account is not excluded (deployment should abort).

.NOTES
    Version: 1.0.0

    Exclusion check order:
    1. Direct exclusion: Check if break-glass accounts in excludeUsers
    2. Group exclusion: Check if break-glass accounts are members of excludeGroups

    Source: Microsoft Learn - Manage Emergency Access Accounts
    https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$PolicyTemplate,

    [Parameter(Mandatory = $true)]
    [object]$Config,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Test-BreakGlassExclusion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PolicyTemplate,

        [Parameter(Mandatory = $true)]
        [object]$Config,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    try {
        # Validate inputs
        if (-not $Config.breakGlassAccounts) {
            Write-Error "Config object missing 'breakGlassAccounts' property."
            return $false
        }

        if ($Config.breakGlassAccounts.Count -eq 0) {
            Write-Warning "No break-glass accounts configured. Skipping validation."
            return $true
        }

        if (-not $PolicyTemplate.conditions.users) {
            Write-Error "Policy template missing 'conditions.users' property."
            return $false
        }

        $excludedUsers = $PolicyTemplate.conditions.users.excludeUsers
        $excludedGroups = $PolicyTemplate.conditions.users.excludeGroups

        if (-not $excludedUsers) { $excludedUsers = @() }
        if (-not $excludedGroups) { $excludedGroups = @() }

        Write-Host "`nValidating break-glass account exclusions..." -ForegroundColor Cyan
        Write-Host "Policy: $($PolicyTemplate.displayName)" -ForegroundColor Cyan
        Write-Host "Break-glass accounts to check: $($Config.breakGlassAccounts.Count)" -ForegroundColor Cyan

        # Check 1: Direct user exclusions
        $directlyExcluded = @()
        $notExcluded = @()

        foreach ($breakGlassAccount in $Config.breakGlassAccounts) {
            if ($excludedUsers -contains $breakGlassAccount) {
                $directlyExcluded += $breakGlassAccount
                Write-Host "  ✓ $breakGlassAccount - Directly excluded" -ForegroundColor Green
            }
            else {
                $notExcluded += $breakGlassAccount
            }
        }

        # All accounts directly excluded - success
        if ($notExcluded.Count -eq 0) {
            Write-Host "`n✓ PASS: All break-glass accounts directly excluded." -ForegroundColor Green
            return $true
        }

        # Check 2: Group membership exclusions (skip in DryRun mode)
        if ($DryRun) {
            Write-Warning "DryRun mode: Skipping group membership resolution."
            Write-Warning "Not directly excluded: $($notExcluded -join ', ')"
            Write-Host "`n✗ FAIL: Some break-glass accounts not directly excluded (DryRun mode)." -ForegroundColor Red
            return $false
        }

        # Resolve group memberships
        if ($excludedGroups.Count -eq 0) {
            Write-Error "No excluded groups configured. Break-glass accounts must be excluded directly or via group."
            Write-Host "`n✗ FAIL: Break-glass accounts not excluded." -ForegroundColor Red
            return $false
        }

        Write-Host "`nChecking group membership exclusions..." -ForegroundColor Cyan

        $groupExcluded = @()

        foreach ($groupId in $excludedGroups) {
            try {
                Write-Host "  Resolving members of group: $groupId" -ForegroundColor Cyan

                # Query group members
                $groupMembers = Get-MgGroupMember -GroupId $groupId -ErrorAction Stop |
                    Select-Object -ExpandProperty Id

                foreach ($breakGlassAccount in $notExcluded) {
                    if ($groupMembers -contains $breakGlassAccount) {
                        $groupExcluded += $breakGlassAccount
                        Write-Host "    ✓ $breakGlassAccount - Excluded via group $groupId" -ForegroundColor Green
                    }
                }
            }
            catch {
                Write-Warning "Failed to resolve group membership for $groupId: $($_.Exception.Message)"
            }
        }

        # Remove group-excluded accounts from not-excluded list
        $notExcluded = $notExcluded | Where-Object { $groupExcluded -notcontains $_ }

        # Final validation
        if ($notExcluded.Count -eq 0) {
            Write-Host "`n✓ PASS: All break-glass accounts excluded (direct + group)." -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "`n✗ FAIL: Break-glass validation failed." -ForegroundColor Red
            Write-Host "Policy: $($PolicyTemplate.displayName)" -ForegroundColor Red
            Write-Host "Break-glass accounts NOT excluded:" -ForegroundColor Red
            foreach ($account in $notExcluded) {
                Write-Host "  - $account" -ForegroundColor Red
            }
            Write-Host "`nDeployment should be ABORTED to prevent tenant lockout." -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Error "Break-glass validation error: $($_.Exception.Message)"
        return $false
    }
}

# Execute function if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $result = Test-BreakGlassExclusion @PSBoundParameters
    return $result
}

