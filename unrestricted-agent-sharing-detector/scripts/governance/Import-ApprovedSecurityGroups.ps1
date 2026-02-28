#Requires -Version 7.0
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Imports approved security groups into UASD Dataverse table.

.DESCRIPTION
    Reads a CSV file of approved security groups and upserts records
    into the fsi_ApprovedSecurityGroup Dataverse table. Groups already
    present (matched by GroupId) are updated; new groups are created.

.PARAMETER DataverseUrl
    Dataverse environment URL (e.g., https://org.crm.dynamics.com)

.PARAMETER InputPath
    Path to CSV file with columns: GroupId, GroupName, Zone, ApprovedBy

.PARAMETER TenantId
    Entra ID tenant GUID (optional)

.EXAMPLE
    .\Import-ApprovedSecurityGroups.ps1 -DataverseUrl "https://org.crm.dynamics.com" -InputPath .\config\approved-groups.csv

.NOTES
    FSI Agent Governance Framework - Unrestricted Agent Sharing Detector
    
    CSV Format:
    GroupId,GroupName,Zone,ApprovedBy
    aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee,Zone2-PowerUsers,2,admin@contoso.com
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$InputPath,

    [Parameter()]
    [string]$TenantId
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "`n[UASD Approved Security Groups Import]" -ForegroundColor Cyan
Write-Host "  Target: $DataverseUrl"
Write-Host "  Source: $InputPath"

# --- Authentication ---
if (-not (Get-AzContext)) {
    Write-Host "  Authenticating..." -ForegroundColor Yellow
    if ($TenantId) { Connect-AzAccount -TenantId $TenantId | Out-Null }
    else { Connect-AzAccount | Out-Null }
}

$tokenResult = Get-AzAccessToken -ResourceUrl $DataverseUrl -AsSecureString
$token = $tokenResult.Token | ConvertFrom-SecureString -AsPlainText
$headers = @{
    "Authorization"    = "Bearer $token"
    "Content-Type"     = "application/json"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
    "Accept"           = "application/json"
}

$apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

# --- Read CSV ---
$groups = Import-Csv -Path $InputPath
Write-Host "  Groups in CSV: $($groups.Count)"

if ($groups.Count -eq 0) {
    Write-Host "  No groups found in CSV. Exiting." -ForegroundColor Yellow
    exit 0
}

# --- Validate CSV columns ---
$requiredColumns = @("GroupId", "GroupName", "Zone", "ApprovedBy")
$csvColumns = $groups[0].PSObject.Properties.Name
foreach ($col in $requiredColumns) {
    if ($col -notin $csvColumns) {
        Write-Host "  ERROR: Missing required CSV column: $col" -ForegroundColor Red
        Write-Host "  Required columns: $($requiredColumns -join ', ')" -ForegroundColor Red
        exit 1
    }
}

# --- Map zone values to Dataverse option set ---
$zoneMap = @{
    "1" = 100000001  # Zone 1 (Personal)
    "2" = 100000002  # Zone 2 (Team)
    "3" = 100000003  # Zone 3 (Enterprise)
}

# --- Upsert Groups ---
$created = 0
$updated = 0
$errors = 0
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

foreach ($group in $groups) {
    $groupId = $group.GroupId.Trim()
    $groupName = $group.GroupName.Trim()
    $zone = $group.Zone.Trim()
    $approvedBy = $group.ApprovedBy.Trim()

    if (-not $groupId -or -not $groupName) {
        Write-Host "  Skipping row with empty GroupId or GroupName" -ForegroundColor Yellow
        continue
    }

    if ($groupId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        Write-Host "  Skipping $groupName: GroupId '$groupId' is not a valid GUID" -ForegroundColor Yellow
        $errors++
        continue
    }

    $zoneValue = $zoneMap[$zone]
    if (-not $zoneValue) {
        Write-Host "  ERROR: Invalid zone '$zone' for $groupName — must be 1, 2, or 3. Skipping row." -ForegroundColor Red
        $errors++
        continue
    }

    $payload = @{
        fsi_entraidgroupid    = $groupId
        fsi_displayname       = $groupName
        fsi_zoneclassification = $zoneValue
        fsi_isactive          = $true
        fsi_approvedby        = $approvedBy
        fsi_approvedat        = $timestamp
    } | ConvertTo-Json

    if ($PSCmdlet.ShouldProcess("$groupName ($groupId)", "Import to fsi_ApprovedSecurityGroup")) {
        try {
            # Check if group exists
            $checkUrl = "$apiBase/fsi_approvedsecuritygroups?`$filter=fsi_entraidgroupid eq '$groupId'&`$select=fsi_approvedsecuritygroupid"
            $existing = Invoke-RestMethod -Uri $checkUrl -Headers $headers -Method Get

            if ($existing.value.Count -gt 0) {
                # Update existing
                $recordId = $existing.value[0].fsi_approvedsecuritygroupid
                $updateUrl = "$apiBase/fsi_approvedsecuritygroups($recordId)"
                Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method Patch -Body $payload | Out-Null
                Write-Host "  Updated: $groupName ($groupId)" -ForegroundColor Yellow
                $updated++
            } else {
                # Create new
                $createUrl = "$apiBase/fsi_approvedsecuritygroups"
                Invoke-RestMethod -Uri $createUrl -Headers $headers -Method Post -Body $payload | Out-Null
                Write-Host "  Created: $groupName ($groupId)" -ForegroundColor Green
                $created++
            }
        } catch {
            Write-Host "  ERROR: $groupName - $($_.Exception.Message)" -ForegroundColor Red
            $errors++
        }
    }
}

# --- Summary ---
Write-Host "`n[Import Summary]" -ForegroundColor Cyan
Write-Host "  Created: $created" -ForegroundColor Green
Write-Host "  Updated: $updated" -ForegroundColor Yellow
if ($errors -gt 0) {
    Write-Host "  Errors:  $errors" -ForegroundColor Red
}
Write-Host "`n  Import: COMPLETE" -ForegroundColor Green

if ($errors -gt 0) { exit 1 }
