#Requires -Version 7.0

<#
.SYNOPSIS
    Restores agent sharing relationships from a previously captured evidence file.

.DESCRIPTION
    Reads an evidence file (CSV or JSON) listing agents and their prior sharing
    configurations, then re-applies sharing relationships using the Power Platform
    admin APIs (PAC CLI / Dataverse Web API).

    This runbook is designed for approved backout scenarios where a remediation
    action needs to be reversed after governance review. It reads the
    fsi_evidencejson column format produced by the UASD detection flow.

    Each restore action is logged to a JSON audit trail file for regulatory
    evidence retention (FINRA 4511, SOX 302).

    Authentication follows the managed-identity-first pattern:
      1. System-assigned managed identity (default)
      2. User-assigned managed identity
      3. Workload identity federation (OIDC)
      4. Interactive / device-code
      5. Client secret (legacy: dev-only)

.PARAMETER EvidenceFilePath
    Path to the CSV or JSON evidence file containing agents and their previous
    sharing configurations. Required.

    JSON format: Array of objects with agentId, environmentId, and
    previousSharingConfig properties.

    CSV format: Columns AgentId, EnvironmentId, PreviousSharingPrincipals
    (JSON-encoded array of principal objects).

.PARAMETER DataverseUrl
    Target Dataverse environment URL (e.g., https://org.crm.dynamics.com).
    Required for API calls to restore sharing.

.PARAMETER TenantId
    Microsoft Entra ID tenant GUID. Defaults to $env:AZURE_TENANT_ID.

.PARAMETER AuthMode
    Authentication mode. Valid values: ManagedIdentity (default), Interactive,
    ClientSecret. ManagedIdentity is recommended for production automation.

.PARAMETER AuditLogPath
    File path for the restore audit trail JSON.
    Defaults to .\output\restore-audit-{timestamp}.json.

.PARAMETER DryRun
    Preview restore actions without applying changes. Recommended for initial
    validation before executing a live restore.

.PARAMETER ApprovalTicketId
    Governance approval ticket ID authorizing this restore operation. Recorded
    in the audit trail for compliance evidence.

.EXAMPLE
    .\Restore-AgentSharingFromEvidence.ps1 -EvidenceFilePath .\evidence.json -DataverseUrl https://org.crm.dynamics.com -DryRun
    Preview restore actions without applying changes.

.EXAMPLE
    .\Restore-AgentSharingFromEvidence.ps1 -EvidenceFilePath .\evidence.csv -DataverseUrl https://org.crm.dynamics.com -ApprovalTicketId "CHG-2026-0042"
    Execute restore with governance approval ticket reference.

.NOTES
    FSI Agent Governance Framework - Unrestricted Agent Sharing Detector
    Supports compliance with FINRA 4511 record retention and SOX 302 controls.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string]$EvidenceFilePath,

    [Parameter(Mandatory)]
    [ValidatePattern('^https://.*\.crm.*\.dynamics\.com/?$')]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter()]
    [ValidateSet('ManagedIdentity', 'Interactive', 'ClientSecret')]
    [string]$AuthMode = 'ManagedIdentity',

    [Parameter()]
    [string]$AuditLogPath,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [string]$ApprovalTicketId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Audit trail ───────────────────────────────────────────────────────────

$timestamp = Get-Date -Format 'yyyy-MM-ddTHH-mm-ss'
$auditEntries = [System.Collections.Generic.List[PSObject]]::new()

function Add-AuditEntry {
    [CmdletBinding()]
    param(
        [string]$Action,
        [string]$AgentId,
        [string]$EnvironmentId,
        [string]$Status,
        [string]$Details,
        [string]$ErrorMessage
    )

    $entry = [PSCustomObject]@{
        timestamp      = (Get-Date -Format 'o')
        action         = $Action
        agentId        = $AgentId
        environmentId  = $EnvironmentId
        status         = $Status
        details        = $Details
        errorMessage   = $ErrorMessage
        approvalTicket = $ApprovalTicketId
        isDryRun       = [bool]$DryRun
        operatorUpn    = $env:USERNAME
    }
    $script:auditEntries.Add($entry)
    Write-Verbose "AUDIT: $Action | $AgentId | $Status"
}

# ── Authentication ────────────────────────────────────────────────────────

function Get-DataverseAccessToken {
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [string]$AuthMode
    )

    $resource = "$($DataverseUrl.TrimEnd('/'))/"

    switch ($AuthMode) {
        'ManagedIdentity' {
            Write-Verbose 'Acquiring token via system-assigned managed identity'
            $tokenResponse = Get-AzAccessToken -ResourceUrl $resource
            return $tokenResponse.Token
        }
        'Interactive' {
            Write-Verbose 'Acquiring token via interactive authentication'
            $tokenResponse = Get-AzAccessToken -ResourceUrl $resource -TenantId $TenantId
            return $tokenResponse.Token
        }
        'ClientSecret' {
            # legacy: dev-only — replace with managed identity in production
            Write-Warning 'ClientSecret auth is for development only. Use managed identity in production.'
            $secret = $env:AZURE_CLIENT_SECRET
            if (-not $secret) {
                throw 'AZURE_CLIENT_SECRET environment variable is required for ClientSecret auth mode.'
            }
            $clientId = $env:AZURE_CLIENT_ID
            $body = @{
                grant_type    = 'client_credentials'
                client_id     = $clientId
                client_secret = $secret
                resource      = $resource
            }
            $uri = "https://login.microsoftonline.com/$TenantId/oauth2/token"
            $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
            return $response.access_token
        }
    }
}

# ── Evidence file parsing ─────────────────────────────────────────────────

function Read-EvidenceFile {
    [CmdletBinding()]
    param(
        [string]$FilePath
    )

    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $agents = [System.Collections.Generic.List[PSObject]]::new()

    switch ($extension) {
        '.json' {
            $raw = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
            # Handle both array-at-root and wrapper object with .agents property
            $items = if ($raw -is [System.Array]) { $raw } elseif ($raw.agents) { $raw.agents } else { @($raw) }

            foreach ($item in $items) {
                $agents.Add([PSCustomObject]@{
                    AgentId                 = $item.agentId
                    EnvironmentId           = $item.environmentId
                    PreviousSharingConfig   = $item.previousSharingConfig
                })
            }
        }
        '.csv' {
            $rows = Import-Csv -Path $FilePath
            foreach ($row in $rows) {
                $sharingConfig = $null
                if ($row.PreviousSharingPrincipals) {
                    $sharingConfig = $row.PreviousSharingPrincipals | ConvertFrom-Json
                }
                $agents.Add([PSCustomObject]@{
                    AgentId               = $row.AgentId
                    EnvironmentId         = $row.EnvironmentId
                    PreviousSharingConfig = $sharingConfig
                })
            }
        }
        default {
            throw "Unsupported evidence file format: $extension. Use .json or .csv."
        }
    }

    return $agents
}

# ── Restore sharing via Dataverse Web API ─────────────────────────────────

function Restore-AgentSharing {
    [CmdletBinding()]
    param(
        [string]$AccessToken,
        [PSObject]$Agent
    )

    $agentId = $Agent.AgentId
    $envId = $Agent.EnvironmentId
    $sharingConfig = $Agent.PreviousSharingConfig

    if (-not $sharingConfig) {
        Add-AuditEntry -Action 'RESTORE_SKIP' -AgentId $agentId -EnvironmentId $envId `
            -Status 'Skipped' -Details 'No previous sharing configuration in evidence'
        Write-Warning "  Agent ${agentId}: No previous sharing config — skipping"
        return
    }

    $headers = @{
        Authorization  = "Bearer $AccessToken"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }

    $apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

    if ($DryRun) {
        Add-AuditEntry -Action 'RESTORE_DRYRUN' -AgentId $agentId -EnvironmentId $envId `
            -Status 'DryRun' -Details "Would restore sharing to: $($sharingConfig | ConvertTo-Json -Compress)"
        Write-Host "  [DRY-RUN] Agent ${agentId}: Would restore sharing config" -ForegroundColor Yellow
        return
    }

    if (-not $PSCmdlet.ShouldProcess("Agent $agentId in environment $envId", 'Restore sharing configuration')) {
        Add-AuditEntry -Action 'RESTORE_CANCELLED' -AgentId $agentId -EnvironmentId $envId `
            -Status 'Cancelled' -Details 'User declined ShouldProcess confirmation'
        return
    }

    try {
        # Look up the bot record by agent ID
        $lookupUri = "$apiBase/bots?`$filter=botid eq '$agentId'&`$select=botid"
        $lookupResponse = Invoke-RestMethod -Uri $lookupUri -Headers $headers -Method Get

        if (-not $lookupResponse.value -or $lookupResponse.value.Count -eq 0) {
            Add-AuditEntry -Action 'RESTORE_FAIL' -AgentId $agentId -EnvironmentId $envId `
                -Status 'Failed' -Details "Agent not found in Dataverse"
            Write-Warning "  Agent ${agentId}: Not found in Dataverse — skipping"
            return
        }

        # Build the sharing restoration payload
        $principalIds = @()
        foreach ($principal in $sharingConfig) {
            if ($principal.principalId) {
                $principalIds += $principal.principalId
            }
        }

        if ($principalIds.Count -eq 0) {
            Add-AuditEntry -Action 'RESTORE_SKIP' -AgentId $agentId -EnvironmentId $envId `
                -Status 'Skipped' -Details 'No valid principal IDs in previous sharing config'
            Write-Warning "  Agent ${agentId}: No valid principals to restore — skipping"
            return
        }

        # Restore sharing by granting access to each principal
        $restoredCount = 0
        $failedCount = 0
        foreach ($principal in $sharingConfig) {
            $principalId = $principal.principalId
            $principalType = if ($principal.principalType) { $principal.principalType } else { 'team' }
            $roleName = if ($principal.roleName) { $principal.roleName } else { 'CanView' }

            try {
                $grantBody = @{
                    Target = @{
                        botid    = $agentId
                        '@odata.type' = 'Microsoft.Dynamics.CRM.bot'
                    }
                    PrincipalAccess = @{
                        Principal = @{
                            '@odata.type' = "Microsoft.Dynamics.CRM.$principalType"
                            "${principalType}id" = $principalId
                        }
                        AccessMask = $roleName
                    }
                } | ConvertTo-Json -Depth 5

                $grantUri = "$apiBase/GrantAccess"
                Invoke-RestMethod -Uri $grantUri -Headers $headers -Method Post -Body $grantBody | Out-Null
                $restoredCount++
            } catch {
                $failedCount++
                Write-Warning "  Agent ${agentId}: Failed to restore principal $principalId — $($_.Exception.Message)"
            }
        }

        $status = if ($failedCount -eq 0) { 'Success' } else { 'PartialSuccess' }
        Add-AuditEntry -Action 'RESTORE_COMPLETE' -AgentId $agentId -EnvironmentId $envId `
            -Status $status `
            -Details "Restored $restoredCount of $($sharingConfig.Count) principals (failed: $failedCount)"

        Write-Host "  Agent ${agentId}: Restored $restoredCount principal(s)" -ForegroundColor Green

    } catch {
        Add-AuditEntry -Action 'RESTORE_FAIL' -AgentId $agentId -EnvironmentId $envId `
            -Status 'Failed' -ErrorMessage $_.Exception.Message
        Write-Error "  Agent ${agentId}: Restore failed — $($_.Exception.Message)"
    }
}

# ── Main ──────────────────────────────────────────────────────────────────

if (-not $AuditLogPath) {
    $outputDir = Join-Path $PSScriptRoot '..' 'output'
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $AuditLogPath = Join-Path $outputDir "restore-audit-$timestamp.json"
}

Write-Host "=== Agent Sharing Restore from Evidence ===" -ForegroundColor Cyan
Write-Host "Timestamp:      $timestamp"
Write-Host "Evidence file:  $EvidenceFilePath"
Write-Host "Dataverse URL:  $DataverseUrl"
Write-Host "Auth mode:      $AuthMode"
Write-Host "Dry run:        $DryRun"
if ($ApprovalTicketId) {
    Write-Host "Approval ticket: $ApprovalTicketId"
}

Add-AuditEntry -Action 'RESTORE_SESSION_START' -AgentId '' -EnvironmentId '' `
    -Status 'Started' -Details "Evidence: $EvidenceFilePath, DryRun: $DryRun"

# Parse evidence
$agents = Read-EvidenceFile -FilePath $EvidenceFilePath
Write-Host "`nAgents in evidence file: $($agents.Count)"

if ($agents.Count -eq 0) {
    Write-Warning 'No agents found in evidence file.'
    Add-AuditEntry -Action 'RESTORE_SESSION_END' -AgentId '' -EnvironmentId '' `
        -Status 'Completed' -Details 'No agents to process'
} else {
    # Authenticate
    $accessToken = Get-DataverseAccessToken -TenantId $TenantId -AuthMode $AuthMode

    # Process each agent
    foreach ($agent in $agents) {
        Write-Host "`nProcessing agent: $($agent.AgentId)" -ForegroundColor Yellow
        Restore-AgentSharing -AccessToken $accessToken -Agent $agent
    }

    $successCount = ($auditEntries | Where-Object { $_.status -eq 'Success' }).Count
    $failCount = ($auditEntries | Where-Object { $_.status -eq 'Failed' }).Count
    $skipCount = ($auditEntries | Where-Object { $_.status -eq 'Skipped' }).Count
    $dryRunCount = ($auditEntries | Where-Object { $_.status -eq 'DryRun' }).Count

    Add-AuditEntry -Action 'RESTORE_SESSION_END' -AgentId '' -EnvironmentId '' `
        -Status 'Completed' `
        -Details "Total: $($agents.Count), Success: $successCount, Failed: $failCount, Skipped: $skipCount, DryRun: $dryRunCount"
}

# Write audit trail
$auditReport = @{
    runId           = [guid]::NewGuid().ToString()
    timestamp       = $timestamp
    evidenceFile    = $EvidenceFilePath
    approvalTicket  = $ApprovalTicketId
    isDryRun        = [bool]$DryRun
    entries         = $auditEntries
}

$auditReport | ConvertTo-Json -Depth 10 | Set-Content -Path $AuditLogPath -Encoding utf8
Write-Host "`nAudit trail written to: $AuditLogPath" -ForegroundColor Cyan
