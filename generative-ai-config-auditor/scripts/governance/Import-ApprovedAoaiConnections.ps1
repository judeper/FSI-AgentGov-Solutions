#Requires -Version 7.0
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Imports approved Azure OpenAI connections into the GAC governance whitelist.

.DESCRIPTION
    Reads a CSV file of approved Azure OpenAI connections and creates or updates
    records in the fsi_GACApprovedConnection Dataverse table. This whitelist is
    used by the GAC compliance scan to determine whether an agent's AOAI connection
    is authorized for its governance zone.

    The script is idempotent -- if a connection with the same ConnectionId already
    exists, it updates the existing record rather than creating a duplicate.

.PARAMETER CsvPath
    Path to a CSV file with approved AOAI connections. Required columns:
    ConnectionId, ConnectionName, Zone, ResourceGroup, AoaiEndpoint.
    Optional columns: Notes, ApprovedBy, ExpirationDate.

.PARAMETER DataverseUrl
    The Dataverse environment URL (e.g., https://org.crm.dynamics.com).

.PARAMETER DataverseToken
    A pre-acquired Dataverse access token. If not provided, the script acquires
    a token using Az.Accounts (interactive) or MSAL (service principal).

.PARAMETER ApprovedBy
    UPN or display name of the approver. Applied to all imported records unless
    the CSV includes an ApprovedBy column per row. CSV column takes precedence.

.PARAMETER Interactive
    Use interactive browser authentication via Az.Accounts.

.EXAMPLE
    .\Import-ApprovedAoaiConnections.ps1 `
        -CsvPath ".\approved-connections.csv" `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -ApprovedBy "admin@contoso.com" `
        -Interactive

    Imports approved connections from CSV using interactive authentication.

.EXAMPLE
    .\Import-ApprovedAoaiConnections.ps1 `
        -CsvPath ".\approved-connections.csv" `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -DataverseToken $token `
        -WhatIf

    Previews the import without making changes.

.NOTES
    CSV Format:
        ConnectionId,ConnectionName,Zone,ResourceGroup,AoaiEndpoint,Notes
        abc-123,prod-openai-eastus,Zone3,rg-ai-prod,https://prod-openai.openai.azure.com/,Production AOAI

    Valid Zone values: Zone1, Zone2, Zone3
    The ConnectionId is used as the idempotency key.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^https://[a-zA-Z0-9\-]+\.crm[0-9]*\.dynamics\.com$')]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$DataverseToken,

    [Parameter()]
    [string]$ApprovedBy,

    [switch]$Interactive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Constants ---
$TableName = 'fsi_gacapprovedconnections'
$ApiVersion = 'v9.2'
$ValidZones = @('Zone1', 'Zone2', 'Zone3')
$ZoneOptionSetMap = @{
    'Zone1' = 1
    'Zone2' = 2
    'Zone3' = 3
}

# --- Functions ---

function Get-DataverseToken {
    <#
    .SYNOPSIS
        Acquires a Dataverse access token via Az.Accounts interactive login.
    #>
    param([string]$EnvironmentUrl)

    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        throw "Az.Accounts module is required for interactive authentication. Install with: Install-Module Az.Accounts -Scope CurrentUser"
    }

    Import-Module Az.Accounts -ErrorAction Stop

    $account = Connect-AzAccount -ErrorAction Stop
    if (-not $account) {
        throw "Interactive login failed. Please try again."
    }

    $resource = $EnvironmentUrl.TrimEnd('/')
    $tokenResult = Get-AzAccessToken -ResourceUrl $resource -ErrorAction Stop

    if (-not $tokenResult.Token) {
        throw "Failed to acquire Dataverse access token for $resource"
    }

    return $tokenResult.Token
}

function Invoke-DataverseRequest {
    <#
    .SYNOPSIS
        Sends an HTTP request to the Dataverse Web API with retry logic.
    #>
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Token,
        [hashtable]$Body,
        [int]$MaxRetries = 3
    )

    $headers = @{
        'Authorization' = "Bearer $Token"
        'Content-Type'  = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version' = '4.0'
        'Accept' = 'application/json'
        'Prefer' = 'return=representation'
    }

    $params = @{
        Method  = $Method
        Uri     = $Uri
        Headers = $headers
    }

    if ($Body) {
        $params['Body'] = ($Body | ConvertTo-Json -Depth 10)
    }

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            $response = Invoke-RestMethod @params -ErrorAction Stop
            return $response
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 429 -and $attempt -lt $MaxRetries) {
                $retryAfter = 5 * $attempt
                Write-Warning "Rate limited (429). Retrying in $retryAfter seconds (attempt $attempt/$MaxRetries)..."
                Start-Sleep -Seconds $retryAfter
            }
            elseif ($statusCode -ge 500 -and $attempt -lt $MaxRetries) {
                $retryAfter = 3 * $attempt
                Write-Warning "Server error ($statusCode). Retrying in $retryAfter seconds (attempt $attempt/$MaxRetries)..."
                Start-Sleep -Seconds $retryAfter
            }
            else {
                throw
            }
        }
    }
}

function Find-ExistingConnection {
    <#
    .SYNOPSIS
        Checks if an approved connection record already exists by ConnectionId.
    #>
    param(
        [string]$BaseUrl,
        [string]$Token,
        [string]$ConnectionId
    )

    $filter = "`$filter=fsi_connectionid eq '$ConnectionId'"
    $select = "`$select=fsi_gacapprovedconnectionid,fsi_connectionid,fsi_connectionname,fsi_isactive"
    $uri = "$BaseUrl/api/data/$ApiVersion/${TableName}?${filter}&${select}"

    $result = Invoke-DataverseRequest -Method 'GET' -Uri $uri -Token $Token
    if ($result.value -and $result.value.Count -gt 0) {
        return $result.value[0]
    }
    return $null
}

# --- Main ---

Write-Host "`nGenerative AI Config Auditor - Approved AOAI Connection Import" -ForegroundColor Cyan
Write-Host ("=" * 62) -ForegroundColor Cyan

# Acquire token if not provided
if (-not $DataverseToken) {
    if ($Interactive) {
        Write-Host "`nAcquiring Dataverse token via interactive login..." -ForegroundColor Yellow
        $DataverseToken = Get-DataverseToken -EnvironmentUrl $DataverseUrl
        Write-Host "Token acquired successfully." -ForegroundColor Green
    }
    else {
        throw "Either -DataverseToken or -Interactive must be specified."
    }
}

$BaseUrl = $DataverseUrl.TrimEnd('/')

# Read and validate CSV
Write-Host "`nReading CSV: $CsvPath" -ForegroundColor Yellow
$csvData = Import-Csv -Path $CsvPath -ErrorAction Stop

if ($csvData.Count -eq 0) {
    Write-Warning "CSV file is empty. No connections to import."
    return
}

# Validate required columns
$requiredColumns = @('ConnectionId', 'ConnectionName', 'Zone', 'ResourceGroup', 'AoaiEndpoint')
$csvColumns = $csvData[0].PSObject.Properties.Name
$missingColumns = $requiredColumns | Where-Object { $_ -notin $csvColumns }
if ($missingColumns) {
    throw "CSV is missing required columns: $($missingColumns -join ', '). Required: $($requiredColumns -join ', ')"
}

Write-Host "Found $($csvData.Count) connection(s) to process.`n" -ForegroundColor Green

# Process each row
$created = 0
$updated = 0
$skipped = 0
$errors = 0

foreach ($row in $csvData) {
    $connectionId = $row.ConnectionId.Trim()
    $connectionName = $row.ConnectionName.Trim()
    $zone = $row.Zone.Trim()
    $resourceGroup = $row.ResourceGroup.Trim()
    $aoaiEndpoint = $row.AoaiEndpoint.Trim()
    $notes = if ($row.PSObject.Properties['Notes']) { $row.Notes.Trim() } else { '' }
    $rowApprovedBy = if ($row.PSObject.Properties['ApprovedBy'] -and $row.ApprovedBy) { $row.ApprovedBy.Trim() } else { $ApprovedBy }
    $expirationDate = if ($row.PSObject.Properties['ExpirationDate'] -and $row.ExpirationDate) { $row.ExpirationDate.Trim() } else { $null }

    # Validate required fields
    if (-not $connectionId -or -not $connectionName -or -not $zone) {
        Write-Warning "Skipping row: missing required field (ConnectionId, ConnectionName, or Zone). ConnectionId='$connectionId'"
        $skipped++
        continue
    }

    # Validate zone
    if ($zone -notin $ValidZones) {
        Write-Warning "Skipping row '$connectionId': invalid Zone '$zone'. Valid values: $($ValidZones -join ', ')"
        $skipped++
        continue
    }

    # Validate AOAI endpoint format
    if ($aoaiEndpoint -and $aoaiEndpoint -notmatch '^https://[a-zA-Z0-9\-]+\.openai\.azure\.com') {
        Write-Warning "Skipping row '$connectionId': invalid AoaiEndpoint '$aoaiEndpoint'. Expected format: https://<name>.openai.azure.com/"
        $skipped++
        continue
    }

    # Build record payload
    $record = @{
        'fsi_connectionid'   = $connectionId
        'fsi_connectionname' = $connectionName
        'fsi_zone'           = $ZoneOptionSetMap[$zone]
        'fsi_resourcegroup'  = $resourceGroup
        'fsi_aoaiendpoint'   = $aoaiEndpoint
        'fsi_isactive'       = $true
        'fsi_notes'          = $notes
        'fsi_name'           = "$connectionName ($zone)"
    }

    if ($rowApprovedBy) {
        $record['fsi_approvedby'] = $rowApprovedBy
    }

    if ($expirationDate) {
        $record['fsi_expiresat'] = $expirationDate
    }

    try {
        # Check for existing record (idempotent)
        $existing = Find-ExistingConnection -BaseUrl $BaseUrl -Token $DataverseToken -ConnectionId $connectionId

        if ($existing) {
            # Update existing record
            $recordId = $existing.fsi_gacapprovedconnectionid
            $uri = "$BaseUrl/api/data/$ApiVersion/$TableName($recordId)"

            if ($PSCmdlet.ShouldProcess("$connectionName ($connectionId)", "Update existing approved connection")) {
                Invoke-DataverseRequest -Method 'PATCH' -Uri $uri -Token $DataverseToken -Body $record | Out-Null
                Write-Host "  UPDATED: $connectionName ($connectionId) - Zone: $zone" -ForegroundColor Yellow
                $updated++
            }
        }
        else {
            # Create new record
            $uri = "$BaseUrl/api/data/$ApiVersion/$TableName"

            if ($PSCmdlet.ShouldProcess("$connectionName ($connectionId)", "Create new approved connection")) {
                Invoke-DataverseRequest -Method 'POST' -Uri $uri -Token $DataverseToken -Body $record | Out-Null
                Write-Host "  CREATED: $connectionName ($connectionId) - Zone: $zone" -ForegroundColor Green
                $created++
            }
        }
    }
    catch {
        Write-Warning "ERROR processing '$connectionId': $_"
        $errors++
    }
}

# Summary
Write-Host "`n$("=" * 62)" -ForegroundColor Cyan
Write-Host "Import Summary" -ForegroundColor Cyan
Write-Host "  Created:  $created" -ForegroundColor Green
Write-Host "  Updated:  $updated" -ForegroundColor Yellow
Write-Host "  Skipped:  $skipped" -ForegroundColor DarkYellow
Write-Host "  Errors:   $errors" -ForegroundColor $(if ($errors -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Total:    $($csvData.Count)" -ForegroundColor White
Write-Host "$("=" * 62)`n" -ForegroundColor Cyan

if ($errors -gt 0) {
    Write-Warning "$errors error(s) occurred during import. Review warnings above for details."
}
