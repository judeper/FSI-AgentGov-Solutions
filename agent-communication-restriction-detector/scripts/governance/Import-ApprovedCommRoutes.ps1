#Requires -Version 7.0

<#
.SYNOPSIS
    Imports approved zone-to-zone communication routes into the ACRD governance
    whitelist.

.DESCRIPTION
    Reads a CSV file of approved communication routes and creates or updates
    records in the fsi_approvedcommroutes Dataverse table. This whitelist is
    used by the ACRD compliance scan to determine whether an agent's communication
    route to another agent is authorized for its governance zone pair.

    The script is idempotent -- if a route with the same SourceZone + TargetZone +
    DirectionType combination already exists, it updates the existing record rather
    than creating a duplicate.

    Supports -WhatIf for previewing changes without writing to Dataverse.

.PARAMETER CsvPath
    Path to a CSV file with approved communication routes.

    Required columns: SourceZone, TargetZone, DirectionType
    Optional columns: AllowCrossEnvironment, Notes, ApprovedBy, ExpirationDate

    Valid SourceZone/TargetZone values: Zone1, Zone2, Zone3
    Valid DirectionType values: OneWay, Bidirectional

.PARAMETER DataverseUrl
    The Dataverse environment URL (e.g., https://org.crm.dynamics.com).

.PARAMETER DataverseToken
    A pre-acquired Dataverse access token. If not provided, the script acquires
    a token using Az.Accounts (interactive) when -Interactive is specified.

.PARAMETER ApprovedBy
    UPN or display name of the approver. Applied to all imported records unless
    the CSV includes an ApprovedBy column per row. CSV column takes precedence.

.PARAMETER Interactive
    Use interactive browser authentication via Az.Accounts.

.EXAMPLE
    .\Import-ApprovedCommRoutes.ps1 `
        -CsvPath ".\approved-routes.csv" `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -ApprovedBy "admin@contoso.com" `
        -Interactive

    Imports approved routes from CSV using interactive authentication.

.EXAMPLE
    .\Import-ApprovedCommRoutes.ps1 `
        -CsvPath ".\approved-routes.csv" `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -DataverseToken $token `
        -WhatIf

    Previews the import without making changes.

.NOTES
    CSV Format:
        SourceZone,TargetZone,DirectionType,AllowCrossEnvironment,Notes
        Zone1,Zone1,Bidirectional,true,Same-zone same-env communication
        Zone2,Zone2,Bidirectional,false,Same-zone cross-env requires explicit route
        Zone2,Zone1,OneWay,true,Higher zone can call lower zone services

    Valid Zone values: Zone1, Zone2, Zone3
    Valid DirectionType values: OneWay, Bidirectional
    The combination of SourceZone + TargetZone + DirectionType is the idempotency key.

    Version: 1.1.0
    Solution: Agent Communication Restriction Detector (ACRD)
    Control: 2.17 (Multi-Agent Orchestration Limits)
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^https://[a-zA-Z0-9\-]+\.crm[0-9]*\.dynamics(\.com|\.us|\.de)/?$')]
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
$TableName = 'fsi_approvedcommroutes'
$ApiVersion = 'v9.2'
$ValidZones = @('Zone1', 'Zone2', 'Zone3')
$ValidDirections = @('OneWay', 'Bidirectional')
$ZoneOptionSetMap = @{
    'Zone1' = 1
    'Zone2' = 2
    'Zone3' = 3
}
$DirectionOptionSetMap = @{
    'OneWay'        = 100000000
    'Bidirectional' = 100000001
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
        Sends an HTTP request to the Dataverse Web API with retry logic for
        429 (throttle) and 5xx (server error) responses.
    #>
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Token,
        [hashtable]$Body,
        [int]$MaxRetries = 3
    )

    $headers = @{
        'Authorization'    = "Bearer $Token"
        'Content-Type'     = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
        'Accept'           = 'application/json'
        'Prefer'           = 'return=representation'
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

function Find-ExistingRoute {
    <#
    .SYNOPSIS
        Checks if an approved route record already exists by the idempotency key:
        SourceZone + TargetZone + DirectionType.
    #>
    param(
        [string]$BaseUrl,
        [string]$Token,
        [int]$SourceZoneInt,
        [int]$TargetZoneInt,
        [int]$DirectionTypeInt
    )

    $filter = "`$filter=fsi_sourcezone eq $SourceZoneInt and fsi_targetzone eq $TargetZoneInt and fsi_directiontype eq $DirectionTypeInt"
    $select = "`$select=fsi_approvedcommrouteid,fsi_sourcezone,fsi_targetzone,fsi_directiontype,fsi_isactive"
    $uri = "$BaseUrl/api/data/$ApiVersion/${TableName}?${filter}&${select}"

    $result = Invoke-DataverseRequest -Method 'GET' -Uri $uri -Token $Token
    if ($result.value -and $result.value.Count -gt 0) {
        return $result.value[0]
    }
    return $null
}

# --- Main ---

Write-Host "`nAgent Communication Restriction Detector - Approved Route Import" -ForegroundColor Cyan
Write-Host ("=" * 64) -ForegroundColor Cyan

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
    Write-Warning "CSV file is empty. No routes to import."
    return
}

# Validate required columns
$requiredColumns = @('SourceZone', 'TargetZone', 'DirectionType')
$csvColumns = $csvData[0].PSObject.Properties.Name
$missingColumns = $requiredColumns | Where-Object { $_ -notin $csvColumns }
if ($missingColumns) {
    throw "CSV is missing required columns: $($missingColumns -join ', '). Required: $($requiredColumns -join ', ')"
}

Write-Host "Found $($csvData.Count) route(s) to process.`n" -ForegroundColor Green

# Process each row
$created = 0
$updated = 0
$skipped = 0
$errors = 0

foreach ($row in $csvData) {
    $sourceZone = $row.SourceZone.Trim()
    $targetZone = $row.TargetZone.Trim()
    $directionType = $row.DirectionType.Trim()

    # Parse optional columns with safe property access
    $allowCrossEnv = if ($row.PSObject.Properties['AllowCrossEnvironment'] -and $row.AllowCrossEnvironment) {
        $row.AllowCrossEnvironment.Trim().ToLower() -eq 'true'
    } else { $false }

    $notes = if ($row.PSObject.Properties['Notes'] -and $row.Notes) {
        $row.Notes.Trim()
    } else { '' }

    $rowApprovedBy = if ($row.PSObject.Properties['ApprovedBy'] -and $row.ApprovedBy) {
        $row.ApprovedBy.Trim()
    } else { $ApprovedBy }

    if (-not $rowApprovedBy) {
        Write-Warning "Skipping row: ApprovedBy is required (Dataverse fsi_ApprovedBy is ApplicationRequired). Provide an 'ApprovedBy' column in the CSV or pass -ApprovedBy."
        $skipped++
        continue
    }

    $expirationDate = if ($row.PSObject.Properties['ExpirationDate'] -and $row.ExpirationDate) {
        $row.ExpirationDate.Trim()
    } else { $null }

    # Validate required fields
    if (-not $sourceZone -or -not $targetZone -or -not $directionType) {
        Write-Warning "Skipping row: missing required field (SourceZone, TargetZone, or DirectionType). SourceZone='$sourceZone'"
        $skipped++
        continue
    }

    # Validate SourceZone
    if ($sourceZone -notin $ValidZones) {
        Write-Warning "Skipping row: invalid SourceZone '$sourceZone'. Valid values: $($ValidZones -join ', ')"
        $skipped++
        continue
    }

    # Validate TargetZone
    if ($targetZone -notin $ValidZones) {
        Write-Warning "Skipping row: invalid TargetZone '$targetZone'. Valid values: $($ValidZones -join ', ')"
        $skipped++
        continue
    }

    # Validate DirectionType
    if ($directionType -notin $ValidDirections) {
        Write-Warning "Skipping row: invalid DirectionType '$directionType'. Valid values: $($ValidDirections -join ', ')"
        $skipped++
        continue
    }

    # Build record payload with fsi_ prefixed columns
    $sourceZoneInt = $ZoneOptionSetMap[$sourceZone]
    $targetZoneInt = $ZoneOptionSetMap[$targetZone]
    $directionTypeInt = $DirectionOptionSetMap[$directionType]

    $record = @{
        'fsi_name'                  = "$sourceZone->$targetZone ($directionType)"
        'fsi_sourcezone'            = $sourceZoneInt
        'fsi_targetzone'            = $targetZoneInt
        'fsi_directiontype'         = $directionTypeInt
        'fsi_allowcrossenvironment' = $allowCrossEnv
        'fsi_isactive'              = $true
        'fsi_notes'                 = $notes
        # fsi_ApprovedBy and fsi_ApprovedAt are ApplicationRequired in the schema —
        # always populate them on CREATE/UPDATE so Dataverse does not return HTTP 400.
        'fsi_approvedby'            = $rowApprovedBy
        'fsi_approvedat'            = (Get-Date -AsUTC -Format 'o')
    }

    if ($expirationDate) {
        $record['fsi_expiresat'] = $expirationDate
    }

    try {
        # Check for existing record (idempotent)
        $existing = Find-ExistingRoute -BaseUrl $BaseUrl -Token $DataverseToken `
            -SourceZoneInt $sourceZoneInt -TargetZoneInt $targetZoneInt -DirectionTypeInt $directionTypeInt

        if ($existing) {
            # Update existing record
            $recordId = $existing.fsi_approvedcommrouteid
            $uri = "$BaseUrl/api/data/$ApiVersion/$TableName($recordId)"

            if ($PSCmdlet.ShouldProcess("$sourceZone->$targetZone ($directionType)", "Update existing approved route")) {
                Invoke-DataverseRequest -Method 'PATCH' -Uri $uri -Token $DataverseToken -Body $record | Out-Null
                Write-Host "  UPDATED: $sourceZone -> $targetZone ($directionType)" -ForegroundColor Yellow
                $updated++
            }
        }
        else {
            # Create new record
            $uri = "$BaseUrl/api/data/$ApiVersion/$TableName"

            if ($PSCmdlet.ShouldProcess("$sourceZone->$targetZone ($directionType)", "Create new approved route")) {
                Invoke-DataverseRequest -Method 'POST' -Uri $uri -Token $DataverseToken -Body $record | Out-Null
                Write-Host "  CREATED: $sourceZone -> $targetZone ($directionType)" -ForegroundColor Green
                $created++
            }
        }
    }
    catch {
        Write-Warning "ERROR processing '$sourceZone->$targetZone ($directionType)': $_"
        $errors++
    }
}

# Summary
Write-Host "`n$("=" * 64)" -ForegroundColor Cyan
Write-Host "Import Summary" -ForegroundColor Cyan
Write-Host "  Created:  $created" -ForegroundColor Green
Write-Host "  Updated:  $updated" -ForegroundColor Yellow
Write-Host "  Skipped:  $skipped" -ForegroundColor DarkYellow
Write-Host "  Errors:   $errors" -ForegroundColor $(if ($errors -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Total:    $($csvData.Count)" -ForegroundColor White
Write-Host "$("=" * 64)`n" -ForegroundColor Cyan

if ($errors -gt 0) {
    Write-Warning "$errors error(s) occurred during import. Review warnings above for details."
}
