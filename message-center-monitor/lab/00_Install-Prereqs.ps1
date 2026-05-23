#Requires -Version 7.0
<#
.SYNOPSIS
    Installs and verifies prerequisites for the message-center-monitor lab dry-run.

.DESCRIPTION
    Idempotent prereq installer for an engineer setting up a fresh non-prod
    workstation against a non-prod Microsoft Entra tenant + Power Platform
    environment. Verifies runtime versions, installs PowerShell modules at
    pinned minimum versions, installs Python packages, and (when -CheckRoles is
    set) confirms the runner has Application Administrator + Power Platform
    Administrator roles. Prints clear remediation when something is missing
    rather than failing silently.

.PARAMETER ConfigPath
    Path to lab-config.json. Defaults to ./lab-config.json relative to this script.

.PARAMETER SkipPython
    Skip Python package install. Useful if running on a workstation where
    Python is managed via a venv outside this script's control.

.PARAMETER CheckRoles
    Query Microsoft Graph for the runner's directory role assignments and warn
    if Application Administrator or Power Platform Administrator is missing.
    Requires an interactive Graph sign-in; off by default to keep -WhatIf runs
    side-effect-free.

.EXAMPLE
    pwsh ./00_Install-Prereqs.ps1
    Run with defaults; install missing modules and verify runtime versions.

.EXAMPLE
    pwsh ./00_Install-Prereqs.ps1 -CheckRoles -Verbose
    Full install + role check.

.NOTES
    Lab dry-run step 0 of 7. See docs/lab-dry-run.md for the full sequence.
    Solution: message-center-monitor v2.5.0+
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()] [string] $ConfigPath,
    [Parameter()] [switch] $SkipPython,
    [Parameter()] [switch] $CheckRoles
)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/lib/Write-LabLog.ps1
$null = Initialize-LabLog -StepName '00-prereqs'

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

# --- 1. Runtime versions -----------------------------------------------------
Write-LabLog -Level Info -Message "Checking runtime versions..."

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $failures.Add("PowerShell 7+ required. Detected $($PSVersionTable.PSVersion). Install from https://aka.ms/powershell-release")
} else {
    Write-LabLog -Level Info -Message "  pwsh: $($PSVersionTable.PSVersion) [OK]"
}

try {
    $py = (& python --version 2>&1).ToString().Trim()
    $m  = [regex]::Match($py, 'Python\s+(\d+)\.(\d+)\.(\d+)')
    if (-not $m.Success -or [int]$m.Groups[1].Value -lt 3 -or ([int]$m.Groups[1].Value -eq 3 -and [int]$m.Groups[2].Value -lt 10)) {
        $failures.Add("Python 3.10+ required. Detected '$py'. Install from https://www.python.org/downloads/")
    } else {
        Write-LabLog -Level Info -Message "  python: $py [OK]"
    }
} catch {
    $failures.Add("Python not found on PATH. Install Python 3.10+ from https://www.python.org/downloads/")
}

try {
    $gh = (& gh --version 2>&1 | Select-Object -First 1).ToString().Trim()
    Write-LabLog -Level Info -Message "  gh: $gh [OK]"
} catch {
    $warnings.Add("GitHub CLI ('gh') not found on PATH. Optional but recommended for PR validation. Install from https://cli.github.com/")
}

# --- 2. PowerShell modules ---------------------------------------------------
$requiredModules = @(
    @{ Name = 'MSAL.PS';                                     MinVersion = '4.37.0.0' }
    @{ Name = 'Pester';                                      MinVersion = '5.5.0' }
    @{ Name = 'Microsoft.Graph.Authentication';              MinVersion = '2.0.0' }
    @{ Name = 'Microsoft.Graph.Applications';                MinVersion = '2.0.0' }
    @{ Name = 'Microsoft.Graph.Users';                       MinVersion = '2.0.0' }
    @{ Name = 'Microsoft.Graph.Identity.SignIns';            MinVersion = '2.0.0' }
    @{ Name = 'Microsoft.Graph.Identity.DirectoryManagement';MinVersion = '2.0.0' }
    @{ Name = 'Az.Accounts';                                 MinVersion = '2.15.0' }
    @{ Name = 'Az.KeyVault';                                 MinVersion = '5.0.0' }
    @{ Name = 'Az.Resources';                                MinVersion = '6.0.0' }
    @{ Name = 'Microsoft.PowerApps.Administration.PowerShell'; MinVersion = '2.0.180' }
)

Write-LabLog -Level Info -Message "Checking PowerShell modules..."
foreach ($m in $requiredModules) {
    $installed = Get-Module -ListAvailable -Name $m.Name |
        Sort-Object Version -Descending |
        Select-Object -First 1
    $needsInstall = -not $installed -or $installed.Version -lt [version]$m.MinVersion

    if ($needsInstall) {
        Write-LabLog -Level Info -Message "  Installing $($m.Name) >= $($m.MinVersion)..."
        if ($PSCmdlet.ShouldProcess($m.Name, "Install-Module")) {
            try {
                Install-Module -Name $m.Name -MinimumVersion $m.MinVersion -Scope CurrentUser -AllowClobber -Force -ErrorAction Stop
                Write-LabLog -Level Info -Message "    [installed]"
            } catch {
                $failures.Add("Failed to install module $($m.Name): $($_.Exception.Message). Try: Install-Module -Name $($m.Name) -Scope CurrentUser -Force")
            }
        }
    } else {
        Write-LabLog -Level Info -Message "  $($m.Name) $($installed.Version) [OK]"
    }
}

# --- 3. Python packages ------------------------------------------------------
if (-not $SkipPython) {
    Write-LabLog -Level Info -Message "Installing Python packages..."
    $reqFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/requirements.txt'
    if (Test-Path -LiteralPath $reqFile) {
        if ($PSCmdlet.ShouldProcess($reqFile, 'pip install -r')) {
            & python -m pip install --quiet -r $reqFile
            if ($LASTEXITCODE -ne 0) {
                $failures.Add("pip install -r '$reqFile' failed (exit $LASTEXITCODE). Check Python venv and network.")
            } else {
                Write-LabLog -Level Info -Message "  requirements.txt installed [OK]"
            }
        }
    } else {
        $warnings.Add("Could not find scripts/requirements.txt at '$reqFile'; skipping pip install.")
    }
    # Test deps
    if ($PSCmdlet.ShouldProcess('pytest', 'pip install')) {
        & python -m pip install --quiet pytest 2>&1 | Out-Null
    }
}

# --- 4. Optional: directory role check ---------------------------------------
if ($CheckRoles) {
    try {
        $cfg = Get-LabConfig -ConfigPath $ConfigPath
        Write-LabLog -Level Info -Message "Checking directory role assignments for $($cfg.operator.runnerUpn)..."
        Connect-MgGraph -Scopes 'RoleManagement.Read.Directory','User.Read.All' -NoWelcome -TenantId $cfg.tenant.tenantId -ErrorAction Stop | Out-Null
        $user = Get-MgUser -Filter "userPrincipalName eq '$($cfg.operator.runnerUpn)'" -ErrorAction Stop
        if (-not $user) {
            $warnings.Add("User $($cfg.operator.runnerUpn) not found in tenant $($cfg.tenant.tenantId).")
        } else {
            $assignments = Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$($user.Id)'" -ExpandProperty roleDefinition -ErrorAction Stop
            $roleNames = @($assignments.AdditionalProperties.roleDefinition.displayName) +
                         @($assignments | ForEach-Object { $_.RoleDefinition.DisplayName }) | Where-Object { $_ } | Sort-Object -Unique
            $required = @('Application Administrator', 'Power Platform Administrator')
            foreach ($r in $required) {
                if ($roleNames -notcontains $r) {
                    $warnings.Add("Role '$r' is NOT assigned to $($cfg.operator.runnerUpn). Lab steps that require it will fail. Assign via Microsoft Entra admin center > Roles & Administrators.")
                } else {
                    Write-LabLog -Level Info -Message "  Role '$r' [OK]"
                }
            }
        }
    } catch {
        $warnings.Add("Role check failed: $($_.Exception.Message). Re-run with -CheckRoles after fixing Graph sign-in.")
    } finally {
        try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {
            Write-Verbose ("Microsoft Graph disconnect during message-center prereq role check for {0} failed (non-fatal): {1}" -f $ConfigPath, $_.Exception.Message)
        }
    }
}

# --- 5. Summary --------------------------------------------------------------
Write-Host ""
foreach ($w in $warnings) { Write-LabLog -Level Warn  -Message "WARNING: $w" }
foreach ($f in $failures) { Write-LabLog -Level Error -Message "FAILURE: $f" }

if ($failures.Count -gt 0) {
    Write-LabLog -Level Error -Message "Prereq install incomplete: $($failures.Count) failure(s). Fix and re-run." -Throw
}
Write-LabLog -Level Info -Message "Prereqs OK. Next: pwsh ./01_New-AppRegistration.ps1"
