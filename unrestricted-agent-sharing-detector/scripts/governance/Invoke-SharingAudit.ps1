#Requires -Version 7.0
#Requires -Modules Az.Accounts, Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Performs an on-demand sharing audit of Power Platform apps (proxy for Copilot Studio agents).

.DESCRIPTION
    Scans all Power Platform environments and their apps for sharing configurations
    that violate organizational policy.

    NOTE: This script uses Get-AdminPowerApp and Get-AdminPowerAppRoleAssignment
    cmdlets which enumerate Power Apps, not Copilot Studio agents directly.
    These cmdlets may not return Copilot Studio agent-specific sharing
    configurations. For comprehensive agent scanning, use the Detection Flow
    (UASD-Detector-Scan-Agents) which queries the Dataverse Web API directly.
    
    Detects five violation types:
    - ORG_WIDE_SHARING: Agent shared with Everyone or All Users
    - PUBLIC_INTERNET_LINK: Agent has public internet-facing link enabled
    - UNAPPROVED_GROUP: Agent shared with group not in approved list
    - EXCESSIVE_INDIVIDUAL: Agent shared with more individuals than threshold
    - CROSS_TENANT_ACCESS: Agent shared with external tenant principals
    
    Results are written to a local file (JSON or CSV). This script does
    not write to Dataverse — use the Detection Flow for automated scanning.

.PARAMETER HomeTenantId
    Home tenant GUID for cross-tenant detection. If omitted, uses
    the tenant from the current Az context.

.PARAMETER OutputFormat
    Output format: JSON or CSV (default: JSON)

.PARAMETER OutputPath
    File path for the audit report output

.PARAMETER IncludeEvidence
    Include SHA-256 evidence hash and full sharing configuration snapshot

.PARAMETER MaxIndividualShares
    Threshold for excessive individual sharing (default: 5)

.PARAMETER ApprovedGroupsPath
    Path to CSV file of approved security groups (columns: GroupId, GroupName).
    If omitted, all group-based sharing is flagged.

.EXAMPLE
    .\Invoke-SharingAudit.ps1 -OutputFormat JSON -OutputPath .\evidence\audit.json -IncludeEvidence

.EXAMPLE
    .\Invoke-SharingAudit.ps1 -HomeTenantId "12345678-..." -OutputFormat CSV -OutputPath .\audit.csv

.NOTES
    FSI Agent Governance Framework - Unrestricted Agent Sharing Detector
    Requires: Az.Accounts, Microsoft.PowerApps.Administration.PowerShell
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$HomeTenantId,

    [Parameter()]
    [ValidateSet("JSON", "CSV")]
    [string]$OutputFormat = "JSON",

    [Parameter()]
    [string]$OutputPath = ".\uasd-sharing-audit.json",

    [Parameter()]
    [switch]$IncludeEvidence,

    [Parameter()]
    [int]$MaxIndividualShares = 5,

    [Parameter()]
    [string]$ApprovedGroupsPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# --- Authentication ---
Write-Host "`n[UASD On-Demand Sharing Audit]" -ForegroundColor Cyan

if (-not (Get-AzContext)) {
    Write-Host "  Authenticating..." -ForegroundColor Yellow
    if ($HomeTenantId) { Connect-AzAccount -TenantId $HomeTenantId | Out-Null }
    else { Connect-AzAccount | Out-Null }
}

$context = Get-AzContext
if (-not $HomeTenantId) {
    $HomeTenantId = $context.Tenant.Id
    Write-Host "  Home Tenant: $HomeTenantId (from Az context)" -ForegroundColor Gray
} else {
    Write-Host "  Home Tenant: $HomeTenantId" -ForegroundColor Gray
}

# --- Load Approved Groups (if provided) ---
$approvedGroups = @{}
if ($ApprovedGroupsPath -and (Test-Path $ApprovedGroupsPath)) {
    $groupsCsv = Import-Csv -Path $ApprovedGroupsPath
    foreach ($group in $groupsCsv) {
        $approvedGroups[$group.GroupId] = $group.GroupName
    }
    Write-Host "  Approved groups loaded: $($approvedGroups.Count)" -ForegroundColor Gray
}

# --- Scan Environments ---
Write-Host "`n  Scanning environments..." -ForegroundColor Cyan

$scanRunId = [guid]::NewGuid().ToString()
$scanTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$violations = [System.Collections.ArrayList]::new()
$agentCount = 0
$envCount = 0

try {
    $environments = Get-AdminPowerAppEnvironment
    $envCount = $environments.Count
    Write-Host "  Environments found: $envCount"

    foreach ($env in $environments) {
        $envId = $env.EnvironmentName
        $envDisplayName = $env.DisplayName
        Write-Host "  Scanning: $envDisplayName ($envId)" -ForegroundColor Gray

        try {
            # NOTE: Get-AdminPowerApp enumerates Power Apps, not Copilot Studio agents directly.
            # Use the Detection Flow for comprehensive agent-specific scanning.
            $preErrorCount = $Error.Count
            $apps = Get-AdminPowerApp -EnvironmentName $envId -ErrorAction SilentlyContinue
            if (-not $apps -and $Error.Count -gt $preErrorCount) {
                $lastErr = $Error[0]
                if ($lastErr.ToString() -match 'Forbidden|Unauthorized|Access') {
                    Write-Warning "  Permissions error scanning environment $envDisplayName - audit results may be incomplete: $($lastErr.ToString())"
                }
            }

            foreach ($app in $apps) {
                $agentCount++
                $agentId = $app.AppName
                $agentName = $app.DisplayName

                # Extract sharing configuration
                $sharingScope = "unknown"
                $publicLinkEnabled = $false
                $crossTenantEnabled = $false
                $securityGroups = @()
                $individualShares = @()

                # Check app permissions/sharing
                try {
                    $permissions = Get-AdminPowerAppRoleAssignment -EnvironmentName $envId -AppName $agentId -ErrorAction SilentlyContinue
                    
                    foreach ($perm in $permissions) {
                        $principalType = $perm.PrincipalType
                        $principalId = $perm.PrincipalObjectId
                        $principalDisplayName = $perm.PrincipalDisplayName

                        if ($principalType -eq "Tenant") {
                            $sharingScope = "organization"
                        }
                        elseif ($principalType -eq "Group") {
                            $securityGroups += @{
                                GroupId = $principalId
                                DisplayName = $principalDisplayName
                            }

                            # Check for cross-tenant (null-safe for strict mode)
                            $permTenantId = if ($perm.PSObject.Properties['PrincipalTenantId']) { $perm.PrincipalTenantId } else { $null }
                            if ($permTenantId -and $permTenantId -ne $HomeTenantId) {
                                $crossTenantEnabled = $true
                            }
                        }
                        elseif ($principalType -eq "User") {
                            $individualShares += @{
                                UserId = $principalId
                                DisplayName = $principalDisplayName
                            }

                            # Check for cross-tenant (null-safe for strict mode)
                            $permTenantId = if ($perm.PSObject.Properties['PrincipalTenantId']) { $perm.PrincipalTenantId } else { $null }
                            if ($permTenantId -and $permTenantId -ne $HomeTenantId) {
                                $crossTenantEnabled = $true
                            }
                        }
                    }

                    # Deduplicate: collapse multiple role assignments (e.g., CanView + CanEdit) per principal.
                    # If future enhancements need per-role granularity, revise to group rather than deduplicate.
                    $securityGroups = @($securityGroups | Sort-Object -Property GroupId -Unique)
                    $individualShares = @($individualShares | Sort-Object -Property UserId -Unique)

                    # Check for public/anonymous link access (null-safe for strict mode)
                    $hasPublicLink = try {
                        $app.Internal.properties.sharingConfiguration.publicLinkEnabled -eq $true
                    } catch { $false }
                    if ($hasPublicLink) {
                        $publicLinkEnabled = $true
                    }
                } catch {
                    Write-Host "    Warning: Could not read permissions for $agentName" -ForegroundColor Yellow
                    continue
                }

                if ($securityGroups.Count -gt 0 -and $sharingScope -ne "organization") { $sharingScope = "securityGroups" }
                if ($individualShares.Count -gt 0 -and $sharingScope -eq "unknown") { $sharingScope = "individuals" }

                # --- Rule Engine: Check 5 violation types ---

                # Rule 1: ORG_WIDE_SHARING
                if ($sharingScope -eq "organization") {
                    $violation = @{
                        scan_run_id      = $scanRunId
                        agent_id         = $agentId
                        agent_name       = $agentName
                        environment_id   = $envId
                        environment_name = $envDisplayName
                        violation_type   = "ORG_WIDE_SHARING"
                        severity         = "Critical"
                        description      = "Agent is shared organization-wide"
                        detected_at      = $scanTimestamp
                    }
                    if ($IncludeEvidence) {
                        $evidenceJson = (ConvertTo-Json -InputObject @($permissions) -Depth 5 -Compress)
                        $violation["evidence_json"] = $evidenceJson
                        $hashBytes = [System.Security.Cryptography.SHA256]::HashData(
                            [System.Text.Encoding]::UTF8.GetBytes($evidenceJson)
                        )
                        $violation["evidence_hash"] = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
                    }
                    [void]$violations.Add($violation)
                }

                # Rule 2: PUBLIC_INTERNET_LINK
                if ($publicLinkEnabled) {
                    $violation = @{
                        scan_run_id      = $scanRunId
                        agent_id         = $agentId
                        agent_name       = $agentName
                        environment_id   = $envId
                        environment_name = $envDisplayName
                        violation_type   = "PUBLIC_INTERNET_LINK"
                        severity         = "Critical"
                        description      = "Agent has public internet-facing link enabled"
                        detected_at      = $scanTimestamp
                    }
                    if ($IncludeEvidence) {
                        $evidenceJson = (@{ publicLinkEnabled = $true; agentId = $agentId } | ConvertTo-Json -Depth 5 -Compress)
                        $violation["evidence_json"] = $evidenceJson
                        $hashBytes = [System.Security.Cryptography.SHA256]::HashData(
                            [System.Text.Encoding]::UTF8.GetBytes($evidenceJson)
                        )
                        $violation["evidence_hash"] = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
                    }
                    [void]$violations.Add($violation)
                }

                # Rule 3: UNAPPROVED_GROUP
                foreach ($group in $securityGroups) {
                    if ($approvedGroups.Count -eq 0 -or (-not $approvedGroups.ContainsKey($group.GroupId))) {
                            $violation = @{
                                scan_run_id      = $scanRunId
                                agent_id         = $agentId
                                agent_name       = $agentName
                                environment_id   = $envId
                                environment_name = $envDisplayName
                                violation_type   = "UNAPPROVED_GROUP"
                                severity         = "High"
                                description      = "Agent shared with unapproved group: $($group.DisplayName) ($($group.GroupId))"
                                detected_at      = $scanTimestamp
                            }
                            if ($IncludeEvidence) {
                                $evidenceJson = ($group | ConvertTo-Json -Depth 5 -Compress)
                                $violation["evidence_json"] = $evidenceJson
                                $hashBytes = [System.Security.Cryptography.SHA256]::HashData(
                                    [System.Text.Encoding]::UTF8.GetBytes($evidenceJson)
                                )
                                $violation["evidence_hash"] = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
                            }
                            [void]$violations.Add($violation)
                    }
                }

                # Rule 4: EXCESSIVE_INDIVIDUAL
                if ($individualShares.Count -gt $MaxIndividualShares) {
                    $violation = @{
                        scan_run_id      = $scanRunId
                        agent_id         = $agentId
                        agent_name       = $agentName
                        environment_id   = $envId
                        environment_name = $envDisplayName
                        violation_type   = "EXCESSIVE_INDIVIDUAL"
                        severity         = "Medium"
                        description      = "Agent shared with $($individualShares.Count) individuals (threshold: $MaxIndividualShares)"
                        detected_at      = $scanTimestamp
                    }
                    if ($IncludeEvidence) {
                        $evidenceJson = (ConvertTo-Json -InputObject @($individualShares) -Depth 5 -Compress)
                        $violation["evidence_json"] = $evidenceJson
                        $hashBytes = [System.Security.Cryptography.SHA256]::HashData(
                            [System.Text.Encoding]::UTF8.GetBytes($evidenceJson)
                        )
                        $violation["evidence_hash"] = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
                    }
                    [void]$violations.Add($violation)
                }

                # Rule 5: CROSS_TENANT_ACCESS
                if ($crossTenantEnabled) {
                    $violation = @{
                        scan_run_id      = $scanRunId
                        agent_id         = $agentId
                        agent_name       = $agentName
                        environment_id   = $envId
                        environment_name = $envDisplayName
                        violation_type   = "CROSS_TENANT_ACCESS"
                        severity         = "Critical"
                        description      = "Agent shared with external tenant principals"
                        detected_at      = $scanTimestamp
                    }
                    if ($IncludeEvidence) {
                        $crossTenantPrincipals = $permissions | Where-Object {
                            $tid = if ($_.PSObject.Properties['PrincipalTenantId']) { $_.PrincipalTenantId } else { $null }
                            $tid -and $tid -ne $HomeTenantId
                        }
                        $evidenceJson = (ConvertTo-Json -InputObject @($crossTenantPrincipals) -Depth 5 -Compress)
                        $violation["evidence_json"] = $evidenceJson
                        $hashBytes = [System.Security.Cryptography.SHA256]::HashData(
                            [System.Text.Encoding]::UTF8.GetBytes($evidenceJson)
                        )
                        $violation["evidence_hash"] = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
                    }
                    [void]$violations.Add($violation)
                }
            }
        } catch {
            Write-Host "    Warning: Failed to scan environment $envDisplayName - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  ERROR: Failed to enumerate environments - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Generate Report ---
Write-Host "`n[Audit Results]" -ForegroundColor Cyan
Write-Host "  Environments scanned: $envCount"
Write-Host "  Agents scanned: $agentCount"
Write-Host "  Violations found: $($violations.Count)"

if ($violations.Count -gt 0) {
    $critical = @($violations | Where-Object { $_.severity -eq "Critical" }).Count
    $high = @($violations | Where-Object { $_.severity -eq "High" }).Count
    $medium = @($violations | Where-Object { $_.severity -eq "Medium" }).Count
    Write-Host "    Critical: $critical" -ForegroundColor Red
    Write-Host "    High: $high" -ForegroundColor Yellow
    Write-Host "    Medium: $medium" -ForegroundColor White
}

$report = @{
    scan_run_id    = $scanRunId
    scan_timestamp = $scanTimestamp
    home_tenant_id = $HomeTenantId
    summary        = @{
        environments_scanned = $envCount
        agents_scanned       = $agentCount
        violations_found     = $violations.Count
    }
    violations     = $violations.ToArray()
}

# --- Write Output ---
$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

if ($OutputFormat -eq "CSV") {
    $OutputPath = [System.IO.Path]::ChangeExtension($OutputPath, ".csv")
    $violations | ForEach-Object { [PSCustomObject]$_ } | Export-Csv -Path $OutputPath -NoTypeInformation
} else {
    $OutputPath = [System.IO.Path]::ChangeExtension($OutputPath, ".json")
    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8
}

Write-Host "  Output: $OutputPath" -ForegroundColor Green
Write-Host "`n  Audit: COMPLETE" -ForegroundColor Green
