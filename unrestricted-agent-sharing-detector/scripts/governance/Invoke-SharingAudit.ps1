#Requires -Version 7.0
#Requires -Modules Az.Accounts, Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Performs an on-demand sharing audit of all Copilot Studio agents.

.DESCRIPTION
    Scans all Power Platform environments and their Copilot Studio agents
    for sharing configurations that violate organizational policy.
    
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

# --- Authentication ---
Write-Host "`n[UASD On-Demand Sharing Audit]" -ForegroundColor Cyan

if (-not (Get-AzContext)) {
    Write-Host "  Authenticating..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
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

# --- Prerequisite Check ---
if (-not (Get-Command Get-AdminPowerAppChatBot -ErrorAction SilentlyContinue)) {
    Write-Error "Get-AdminPowerAppChatBot not available. Install the latest Microsoft.PowerApps.Administration.PowerShell module or use Test-AgentSharingCompliance.ps1 for Dataverse-based scanning."
    exit 1
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
            # Get all Copilot Studio agents (chatbots) in this environment
            $agents = Get-AdminPowerAppChatBot -EnvironmentName $envId -ErrorAction Stop

            foreach ($agent in $agents) {
                $agentCount++
                $agentId = $agent.ChatBotName
                $agentName = $agent.DisplayName

                # Extract sharing configuration
                $sharingScope = "unknown"
                $principals = @()
                $publicLinkEnabled = $false
                $crossTenantEnabled = $false
                $securityGroups = @()
                $individualShares = @()

                # Check app permissions/sharing
                # LIMITATION: Get-AdminPowerAppRoleAssignment is designed for Canvas/Model-driven apps
                # and may not return Copilot Studio chatbot-specific sharing data. This can produce
                # false negatives. Consider using the Dataverse bot table API (api/data/v9.2/bots)
                # with sharingtype field for more reliable chatbot sharing detection.
                Write-Warning "Agent '$agentName': Permission data retrieved via Get-AdminPowerAppRoleAssignment may be incomplete for chatbot-type agents. For higher-confidence results, use Test-AgentSharingCompliance.ps1 which queries the Dataverse bot table directly."
                try {
                    $permissions = Get-AdminPowerAppRoleAssignment -EnvironmentName $envId -AppName $agentId -ErrorAction Stop
                    
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
                            # Cross-tenant check for group principals
                            if ($perm.PrincipalTenantId -and $perm.PrincipalTenantId -ne $HomeTenantId) {
                                $crossTenantEnabled = $true
                            }
                        }
                        elseif ($principalType -eq "User") {
                            $individualShares += @{
                                UserId = $principalId
                                DisplayName = $principalDisplayName
                            }

                            # Check for cross-tenant
                            if ($perm.PrincipalTenantId -and $perm.PrincipalTenantId -ne $HomeTenantId) {
                                $crossTenantEnabled = $true
                            }
                        }
                    }

                    # Check for public/anonymous link access
                    if ($agent.Internal -and $agent.Internal.properties -and
                        $agent.Internal.properties.sharingConfiguration -and
                        $agent.Internal.properties.sharingConfiguration.publicLinkEnabled -eq $true) {
                        $publicLinkEnabled = $true
                    }
                } catch {
                    Write-Host "    Warning: Could not read permissions for $agentName" -ForegroundColor Yellow
                    [void]$violations.Add(@{
                        scan_run_id      = $scanRunId
                        agent_id         = $agentId
                        agent_name       = $agentName
                        environment_id   = $envId
                        environment_name = $envDisplayName
                        violation_type   = "SCAN_COVERAGE_GAP"  # Local-only sentinel; not in fsi_UASD_violationtype Dataverse option set
                        severity         = "Warning"
                        description      = "Could not read permissions for agent: $($_.Exception.Message)"
                        detected_at      = $scanTimestamp
                    })
                    continue
                }

                if ($securityGroups.Count -gt 0 -and $sharingScope -ne "organization") { $sharingScope = "securityGroups" }
                if ($individualShares.Count -gt 0 -and $sharingScope -eq "unknown") { $sharingScope = "individuals" }

                # --- Rule Engine: Check 5 of 6 violation types (POLICY_VIOLATION requires zone classification - see Test-AgentSharingCompliance.ps1) ---

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
                        $evidenceJson = ($permissions | ConvertTo-Json -Depth 5 -Compress)
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
                        $evidenceData = @{
                            agentId = $agentId
                            publicLinkEnabled = $true
                            sharingConfiguration = $agent.Internal.properties.sharingConfiguration
                        }
                        $evidenceJson = ($evidenceData | ConvertTo-Json -Depth 5 -Compress)
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
                        $evidenceJson = ($individualShares | ConvertTo-Json -Depth 5 -Compress)
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
                            $_.PrincipalTenantId -and $_.PrincipalTenantId -ne $HomeTenantId
                        }
                        $evidenceJson = ($crossTenantPrincipals | ConvertTo-Json -Depth 5 -Compress)
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
            [void]$violations.Add(@{
                scan_run_id      = $scanRunId
                agent_id         = ""
                agent_name       = ""
                environment_id   = $envId
                environment_name = $envDisplayName
                violation_type   = "SCAN_COVERAGE_GAP"  # Local-only sentinel; not in fsi_UASD_violationtype Dataverse option set
                severity         = "Warning"
                description      = "Failed to scan environment: $($_.Exception.Message)"
                detected_at      = $scanTimestamp
            })
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
    # Sanitize string fields to prevent CSV injection (CWE-1236)
    $sanitized = $violations | ForEach-Object {
        $obj = [PSCustomObject]$_
        foreach ($prop in $obj.PSObject.Properties) {
            if ($prop.Value -is [string] -and $prop.Value.Length -gt 0 -and $prop.Value[0] -in @('=', '+', '-', '@')) {
                $prop.Value = "'" + $prop.Value
            }
        }
        $obj
    }
    $sanitized | Export-Csv -Path $OutputPath -NoTypeInformation
} else {
    $OutputPath = [System.IO.Path]::ChangeExtension($OutputPath, ".json")
    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8
}

Write-Host "  Output: $OutputPath" -ForegroundColor Green
Write-Host "`n  Audit: COMPLETE" -ForegroundColor Green
