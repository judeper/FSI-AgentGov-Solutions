<#
.SYNOPSIS
    Syncs Tier 2 governance solution validation results into Compliance Dashboard assessments.

.DESCRIPTION
    Queries the latest validation history from each of the 6 Tier 2 governance solutions
    (ACV, SSC, AAM, CMM, FUS, CAA), translates their status/severity values into Compliance
    Dashboard fsi_controlassessment records, and optionally registers evidence.

    This script can run interactively, via Azure Automation, or be invoked by the
    CD-SolutionFeedCollector Power Automate flow.

.PARAMETER DataverseUrl
    The Dataverse environment URL (e.g., https://org.crm.dynamics.com).
    Used when all solutions are in the same environment.

.PARAMETER TenantId
    The Microsoft Entra tenant ID.

.PARAMETER ClientId
    App registration client ID for service principal authentication.

.PARAMETER ClientSecret
    App registration client secret (use SecureString in production).

.PARAMETER Interactive
    Use interactive authentication (browser sign-in).

.PARAMETER DryRun
    Show what would be created/updated without writing to Dataverse.

.PARAMETER Solutions
    Array of solution abbreviations to sync. Default: all 6 (ACV, SSC, AAM, CMM, FUS, CAA).

.PARAMETER RegisterEvidence
    When specified, also register evidence records in fsi_complianceevidence from
    the latest evidence export files.

.PARAMETER EvidenceDirectory
    Path to directory containing per-solution evidence export files.

.PARAMETER OutputFormat
    Output format: Table, Json, Object. Default: Table.

.EXAMPLE
    .\Sync-SolutionAssessments.ps1 -DataverseUrl "https://org.crm.dynamics.com" -TenantId "guid" -Interactive -DryRun

.EXAMPLE
    .\Sync-SolutionAssessments.ps1 -DataverseUrl "https://org.crm.dynamics.com" -TenantId "guid" -ClientId "app-guid" -ClientSecret $secret

.NOTES
    Version: 2.0.0
    Date: 2026-04-16
    Requires: IntegrationConfig.psm1
#>

#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory)]
    [string]$DataverseUrl,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter(ParameterSetName = 'Interactive', Mandatory)]
    [switch]$Interactive,

    [ValidateSet('Public', 'USGov', 'USGovHigh', 'USGovDoD', 'China', 'Germany')]
    [string]$Cloud = 'Public',

    [switch]$DryRun,

    [ValidateSet('ACV', 'SSC', 'AAM', 'CMM', 'FUS', 'CAA')]
    [string[]]$Solutions = @('ACV', 'SSC', 'AAM', 'CMM', 'FUS', 'CAA'),

    [switch]$RegisterEvidence,

    [string]$EvidenceDirectory,

    [ValidateSet('Table', 'Json', 'Object')]
    [string]$OutputFormat = 'Table'
)

$ErrorActionPreference = 'Stop'

#region Module Import

$modulePath = Join-Path $PSScriptRoot 'IntegrationConfig.psm1'
if (-not (Test-Path $modulePath)) {
    throw "IntegrationConfig.psm1 not found at $modulePath. Ensure the module is in the same directory."
}
Import-Module $modulePath -Force

#endregion

#region Authentication (provided by IntegrationConfig.psm1)

#endregion

#region Dataverse Operations

function Invoke-DataverseQuery {
    param(
        [hashtable]$Connection,
        [string]$EntitySet,
        [string]$Query
    )

    $separator = if ($Query.StartsWith('?')) { '' } else { '?' }
    $url = "$($Connection.BaseUrl)/$EntitySet$separator$Query"
    Write-Verbose "GET $url"

    $allRecords = @()
    $maxRetries = 3
    while ($url) {
        $retryCount = 0
        $success = $false
        while (-not $success -and $retryCount -lt $maxRetries) {
            try {
                $response = Invoke-RestMethod -Uri $url -Headers $Connection.Headers -Method Get
                $allRecords += $response.value
                $url = $response.'@odata.nextLink'
                $success = $true
            } catch {
                $retryCount++
                $statusCode = $_.Exception.Response.StatusCode.value__
                if ($statusCode -in @(429, 503) -and $retryCount -lt $maxRetries) {
                    $delay = [math]::Pow(2, $retryCount) * 5
                    Write-Warning "Transient error ($statusCode) querying $EntitySet — retrying in ${delay}s (attempt $retryCount/$maxRetries)"
                    Start-Sleep -Seconds $delay
                } else {
                    throw
                }
            }
        }
    }
    return $allRecords
}

function New-DataverseRecord {
    param(
        [hashtable]$Connection,
        [string]$EntitySet,
        [hashtable]$Record
    )

    $url = "$($Connection.BaseUrl)/$EntitySet"
    $body = $Record | ConvertTo-Json -Depth 10
    Write-Verbose "POST $url"

    $maxRetries = 3
    $retryCount = 0
    while ($true) {
        try {
            $response = Invoke-RestMethod -Uri $url -Headers $Connection.Headers -Method Post -Body $body
            return $response
        } catch {
            $retryCount++
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -in @(429, 503) -and $retryCount -lt $maxRetries) {
                $delay = [math]::Pow(2, $retryCount) * 5
                Write-Warning "Transient error ($statusCode) creating record in $EntitySet — retrying in ${delay}s (attempt $retryCount/$maxRetries)"
                Start-Sleep -Seconds $delay
            } else {
                throw
            }
        }
    }
}

function Update-DataverseRecord {
    param(
        [hashtable]$Connection,
        [string]$EntitySet,
        [string]$RecordId,
        [hashtable]$Record
    )

    $url = "$($Connection.BaseUrl)/$EntitySet($RecordId)"
    $body = $Record | ConvertTo-Json -Depth 10
    Write-Verbose "PATCH $url"

    $maxRetries = 3
    $retryCount = 0
    while ($true) {
        try {
            Invoke-RestMethod -Uri $url -Headers $Connection.Headers -Method Patch -Body $body
            return
        } catch {
            $retryCount++
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -in @(429, 503) -and $retryCount -lt $maxRetries) {
                $delay = [math]::Pow(2, $retryCount) * 5
                Write-Warning "Transient error ($statusCode) updating record in $EntitySet — retrying in ${delay}s (attempt $retryCount/$maxRetries)"
                Start-Sleep -Seconds $delay
            } else {
                throw
            }
        }
    }
}

#endregion

#region Control Master Resolution

function Get-ControlMasterGuids {
    param(
        [hashtable]$Connection
    )

    $cdConfig = Get-DashboardTableConfig
    $controls = Invoke-DataverseQuery -Connection $Connection `
        -EntitySet $cdConfig.ControlMaster.EntitySet `
        -Query '?$select=fsi_controlmasterid,fsi_controlid'

    $map = @{}
    foreach ($control in $controls) {
        $map[$control.fsi_controlid] = $control.fsi_controlmasterid
    }

    Write-Verbose "Resolved $($map.Count) control master GUIDs"
    return $map
}

#endregion

#region Solution Query

function Get-LatestValidation {
    param(
        [hashtable]$Connection,
        [string]$Solution
    )

    $tableConfig = Get-SolutionTableConfig
    $config = $tableConfig[$Solution]

    if (-not $config) {
        Write-Warning "No table configuration found for solution: $Solution"
        return $null
    }

    $results = Invoke-DataverseQuery -Connection $Connection `
        -EntitySet $config.EntitySet `
        -Query "?$($config.FilterLatest)"

    if ($results.Count -eq 0) {
        Write-Warning "No validation records found for $Solution in $($config.EntitySet)"
        return $null
    }

    return $results[0]
}

#endregion

#region Assessment Sync

function Sync-SolutionToAssessment {
    param(
        [hashtable]$Connection,
        [string]$Solution,
        [object]$ValidationRecord,
        [hashtable]$ControlGuids,
        [switch]$DryRun
    )

    $controlMapping = Get-SolutionControlMapping
    $tableConfig = (Get-SolutionTableConfig)[$Solution]
    $cdConfig = Get-DashboardTableConfig
    $controlIds = $controlMapping[$Solution]

    if (-not $controlIds) {
        Write-Warning "No control mapping found for $Solution"
        return @()
    }

    # Translate status
    $dashStatus = switch ($tableConfig.StatusType) {
        'Choice' {
            ConvertTo-DashboardStatus -Solution $Solution -Severity $ValidationRecord.($tableConfig.StatusField)
        }
        'String' {
            ConvertTo-DashboardStatus -Solution $Solution -Severity $ValidationRecord.($tableConfig.StatusField)
        }
        'Percentage' {
            if ($tableConfig.ContainsKey('CompliantField')) {
                ConvertTo-DashboardStatus -Solution $Solution `
                    -CompliantCount $ValidationRecord.($tableConfig.CompliantField) `
                    -TotalAgents $ValidationRecord.($tableConfig.TotalField)
            } else {
                ConvertTo-DashboardStatus -Solution $Solution `
                    -ComplianceRate $ValidationRecord.($tableConfig.StatusField)
            }
        }
    }

    $timestamp = $ValidationRecord.($tableConfig.TimestampField)
    $runId = $ValidationRecord.($tableConfig.RunIdField)
    $zone = if ($ValidationRecord.PSObject.Properties['fsi_zone']) {
        Get-CanonicalZoneValue -ZoneValue $ValidationRecord.fsi_zone
    } else { $null }
    $results = @()

    foreach ($controlId in $controlIds) {
        $controlGuid = $ControlGuids[$controlId]
        if (-not $controlGuid) {
            Write-Warning "Control $controlId not found in fsi_controlmaster — skipping"
            continue
        }

        $notes = "Automated: $($tableConfig.SolutionName) $($tableConfig.SolutionVersion). " +
                 "Run ID: $runId. Status: $($dashStatus.StatusLabel). " +
                 "Source: $($tableConfig.EntitySet), Timestamp: $timestamp."

        $assessmentRecord = @{
            'fsi_controlmasterid@odata.bind' = "/fsi_controlmasters($controlGuid)"
            'fsi_assessmentdate'             = (Get-IsoUtcTimestamp)
            'fsi_status'                     = $dashStatus.Status
            'fsi_score'                      = $dashStatus.Score
            'fsi_notes'                      = $notes
            'fsi_nextreviewdate'             = [DateTime]::UtcNow.AddDays(1).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        if ($null -ne $zone) {
            $assessmentRecord['fsi_zone'] = $zone
        }

        $result = [PSCustomObject]@{
            Solution       = $Solution
            ControlId      = $controlId
            Status         = $dashStatus.StatusLabel
            Score          = $dashStatus.Score
            RunId          = $runId
            Timestamp      = $timestamp
            Zone           = $zone
            Action         = 'Pending'
            AssessmentGuid = $null
        }

        if ($DryRun) {
            $result.Action = 'DryRun — would create assessment'
            Write-Host "  [DryRun] $Solution → Control $controlId : $($dashStatus.StatusLabel) (Score: $($dashStatus.Score))" -ForegroundColor Yellow
        } else {
            try {
                # Check for existing same-day assessment using a UTC date window
                # (avoids the Microsoft.Dynamics.CRM.On function, which expects a
                # full ISO timestamp, and the local-vs-UTC midnight skew that
                # caused duplicate inserts).
                $todayStart = [DateTime]::UtcNow.Date.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                $tomorrowStart = [DateTime]::UtcNow.Date.AddDays(1).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                $sanitizedZone = if ($null -ne $zone) { [int]$zone } else { $null }
                $zoneFilter = if ($null -ne $sanitizedZone) { " and fsi_zone eq $sanitizedZone" } else { '' }
                $existingQuery = "?`$filter=_fsi_controlmasterid_value eq $controlGuid and fsi_assessmentdate ge $todayStart and fsi_assessmentdate lt $tomorrowStart$zoneFilter&`$top=1"
                $existing = Invoke-DataverseQuery -Connection $Connection `
                    -EntitySet $cdConfig.Assessment.EntitySet `
                    -Query $existingQuery

                if ($existing.Count -gt 0) {
                    # Update existing
                    $recordId = $existing[0].fsi_controlassessmentid
                    Update-DataverseRecord -Connection $Connection `
                        -EntitySet $cdConfig.Assessment.EntitySet `
                        -RecordId $recordId `
                        -Record $assessmentRecord
                    $result.Action = 'Updated'
                    $result.AssessmentGuid = $recordId
                    Write-Host "  [Updated] $Solution → Control $controlId : $($dashStatus.StatusLabel)" -ForegroundColor Green
                } else {
                    # Create new
                    $newRecord = New-DataverseRecord -Connection $Connection `
                        -EntitySet $cdConfig.Assessment.EntitySet `
                        -Record $assessmentRecord
                    $result.Action = 'Created'
                    $result.AssessmentGuid = $newRecord.fsi_controlassessmentid
                    Write-Host "  [Created] $Solution → Control $controlId : $($dashStatus.StatusLabel)" -ForegroundColor Green
                }
            } catch {
                $result.Action = "Error: $($_.Exception.Message)"
                Write-Warning "  [Error] $Solution → Control $controlId : $($_.Exception.Message)"
            }
        }

        $results += $result
    }

    return $results
}

#endregion

#region Evidence Registration

function Register-SolutionEvidence {
    param(
        [hashtable]$Connection,
        [string]$Solution,
        [string]$EvidenceDirectory,
        [string]$AssessmentGuid,
        [psobject]$Manifest,
        [switch]$DryRun
    )

    $cdConfig = Get-DashboardTableConfig

    # Manifest-aware mode: use Export-UnifiedComplianceEvidence output format
    if ($Manifest) {
        $solKey = $Solution.ToLower()
        $manifestFiles = $Manifest.fileHashes.PSObject.Properties |
            Where-Object { $_.Name -like "$solKey/*" }

        if (-not $manifestFiles -or $manifestFiles.Count -eq 0) {
            Write-Verbose "No manifest entries found for $solKey"
            return $null
        }

        # Build file list and combined hash from manifest
        $fileNames = ($manifestFiles | ForEach-Object { Split-Path $_.Name -Leaf }) -join ', '
        $combinedHash = ($manifestFiles | Sort-Object Name |
            ForEach-Object { $_.Value }) -join ''
        $packageHash = [System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($combinedHash)
            )
        ).Replace('-', '')

        # Verify files exist on disk
        foreach ($entry in $manifestFiles) {
            $filePath = Join-Path $EvidenceDirectory ($entry.Name -replace '/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path $filePath)) {
                Write-Warning "  [Evidence] Manifest references missing file: $($entry.Name)"
                return $null
            }
        }

        # Use manifest export timestamp
        $exportDate = if ($Manifest.solutions.$solKey.exportedAt) {
            $Manifest.solutions.$solKey.exportedAt
        } elseif ($Manifest.exportDate) {
            $Manifest.exportDate
        } else {
            (Get-IsoUtcTimestamp)
        }

        # Re-hash files on disk and verify they match the manifest. The
        # manifest itself is mutable on a normal filesystem, so trusting its
        # stored hashes without recomputation would let an attacker swap
        # both file and manifest entry. WORM/immutable storage downstream
        # is still required for tamper-evidence.
        $diskHashes = @()
        foreach ($entry in ($manifestFiles | Sort-Object Name)) {
            $filePath = Join-Path $EvidenceDirectory ($entry.Name -replace '/', [IO.Path]::DirectorySeparatorChar)
            $diskHash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
            if ($diskHash -ne $entry.Value) {
                Write-Warning "  [Evidence] Hash mismatch for $($entry.Name) — manifest=$($entry.Value), disk=$diskHash"
                return $null
            }
            $diskHashes += $diskHash
        }
        $combinedHash = ($diskHashes -join '')
        $packageHash = [System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($combinedHash)
            )
        ).Replace('-', '')

        $evidenceRecord = @{
            'fsi_name'          = "$Solution Evidence Package — $($exportDate.Substring(0,10))"
            'fsi_evidencetype'  = Get-EvidenceTypeId
            'fsi_description'   = "Automated evidence package from $((Get-SolutionTableConfig)[$Solution].SolutionName). Files: $fileNames. SHA-256 recomputed and verified against manifest at registration time."
            'fsi_collecteddate' = $exportDate
            'fsi_hash'          = $packageHash
        }

        if ($AssessmentGuid) {
            $evidenceRecord['fsi_controlassessmentid@odata.bind'] = "/fsi_controlassessments($AssessmentGuid)"
        }

        if ($DryRun) {
            Write-Host "  [DryRun] Evidence package: $fileNames (Hash: $($packageHash.Substring(0,16))...)" -ForegroundColor Yellow
            return $null
        }

        try {
            $created = New-DataverseRecord -Connection $Connection `
                -EntitySet $cdConfig.Evidence.EntitySet `
                -Record $evidenceRecord
            Write-Host "  [Evidence] Registered package: $fileNames" -ForegroundColor Cyan
            return $created
        } catch {
            Write-Warning "  [Error] Evidence registration failed: $($_.Exception.Message)"
            return $null
        }
    }

    # Legacy mode: per-solution JSON files with optional sidecar hashes
    $solutionDirs = Get-SolutionDirectories
    $solDir = $solutionDirs[$Solution]
    $evidencePath = Join-Path $EvidenceDirectory $solDir

    if (-not (Test-Path $evidencePath)) {
        Write-Verbose "No evidence directory found at $evidencePath"
        return $null
    }

    # Find latest evidence JSON
    $evidenceFiles = Get-ChildItem -Path $evidencePath -Filter '*.json' -File |
        Where-Object { $_.Name -notmatch '\.sha256$' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $evidenceFiles) {
        Write-Verbose "No evidence files found for $Solution in $evidencePath"
        return $null
    }

    $evidenceFile = $evidenceFiles
    $hashFile = "$($evidenceFile.FullName).sha256"

    # In legacy mode we already have the file path; recompute hash from disk
    # rather than trusting any sidecar (sidecars are mutable too).
    $hash = (Get-FileHash -Path $evidenceFile.FullName -Algorithm SHA256).Hash
    if (Test-Path $hashFile) {
        $hashContent = Get-Content $hashFile -Raw
        $sidecarHash = ($hashContent -split '\s+')[0]
        if ($sidecarHash -and $sidecarHash -ne $hash) {
            Write-Warning "  [Evidence] Hash mismatch for $($evidenceFile.Name) — sidecar=$sidecarHash, disk=$hash"
            return $null
        }
    }

    $evidenceRecord = @{
        'fsi_name'          = "$Solution Evidence Export — $([DateTime]::UtcNow.ToString('yyyy-MM-dd'))"
        'fsi_evidencetype'  = Get-EvidenceTypeId
        'fsi_description'   = "Automated evidence from $((Get-SolutionTableConfig)[$Solution].SolutionName). SHA-256 recomputed at registration. File: $($evidenceFile.Name)"
        'fsi_collecteddate' = (Get-IsoUtcTimestamp)
        'fsi_hash'          = $hash
    }

    if ($AssessmentGuid) {
        $evidenceRecord['fsi_controlassessmentid@odata.bind'] = "/fsi_controlassessments($AssessmentGuid)"
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Evidence: $($evidenceFile.Name) (SHA-256: $($hash.Substring(0,16))...)" -ForegroundColor Yellow
        return $null
    }

    try {
        $created = New-DataverseRecord -Connection $Connection `
            -EntitySet $cdConfig.Evidence.EntitySet `
            -Record $evidenceRecord
        Write-Host "  [Evidence] Registered: $($evidenceFile.Name)" -ForegroundColor Cyan
        return $created
    } catch {
        Write-Warning "  [Error] Evidence registration failed: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Main Execution

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Cross-Solution Assessment Sync" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')" -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "[DryRun Mode] No changes will be written to Dataverse`n" -ForegroundColor Yellow
}

# Connect
Write-Host "Connecting to Dataverse..." -ForegroundColor Gray
if ($Interactive) {
    $connection = Connect-DataverseApi -Url $DataverseUrl -TenantId $TenantId -Interactive -Cloud $Cloud
} else {
    $connection = Connect-DataverseApi -Url $DataverseUrl -TenantId $TenantId `
        -ClientId $ClientId -ClientSecret $ClientSecret -Cloud $Cloud
}

# Resolve control master GUIDs
Write-Host "Resolving control master GUIDs..." -ForegroundColor Gray
$controlGuids = Get-ControlMasterGuids -Connection $connection

if ($controlGuids.Count -eq 0) {
    throw "No control master records found. Ensure the Compliance Dashboard sample data is loaded."
}

Write-Host "Found $($controlGuids.Count) controls in dashboard`n" -ForegroundColor Green

# Load evidence manifest once (if evidence registration is requested)
$evidenceManifest = $null
if ($RegisterEvidence -and $EvidenceDirectory) {
    $manifestPath = Join-Path $EvidenceDirectory 'manifest.json'
    if (Test-Path $manifestPath) {
        try {
            $evidenceManifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            Write-Host "Loaded evidence manifest: $($evidenceManifest.exportId ?? 'unknown')" -ForegroundColor Green
        } catch {
            Write-Warning "Evidence manifest found but could not be parsed: $($_.Exception.Message)"
            Write-Warning "Falling back to legacy per-solution evidence lookup."
        }
    } else {
        Write-Verbose "No manifest.json found — using legacy per-solution evidence lookup"
    }
}

# Process each solution
$allResults = @()
$solutionControlMapping = Get-SolutionControlMapping

foreach ($solution in $Solutions) {
    $controls = $solutionControlMapping[$solution]
    Write-Host "[$solution] Querying latest validation (feeds: $($controls -join ', '))..." -ForegroundColor White

    $validation = Get-LatestValidation -Connection $connection -Solution $solution

    if (-not $validation) {
        Write-Host "  [Skip] No validation data available`n" -ForegroundColor DarkYellow
        $allResults += [PSCustomObject]@{
            Solution  = $solution
            ControlId = ($controls -join ', ')
            Status    = 'No Data'
            Score     = '-'
            RunId     = '-'
            Timestamp = '-'
            Action    = 'Skipped — no validation records'
        }
        continue
    }

    $results = Sync-SolutionToAssessment -Connection $connection -Solution $solution `
        -ValidationRecord $validation -ControlGuids $controlGuids -DryRun:$DryRun

    $allResults += $results

    # Evidence registration
    if ($RegisterEvidence -and $EvidenceDirectory) {
        foreach ($result in $results) {
            if ($result.Action -in @('Created', 'Updated', 'DryRun — would create assessment')) {
                Register-SolutionEvidence -Connection $connection -Solution $solution `
                    -EvidenceDirectory $EvidenceDirectory -Manifest $evidenceManifest `
                    -AssessmentGuid $result.AssessmentGuid -DryRun:$DryRun
            }
        }
    }

    Write-Host ""
}

#region Worst-of-Two Resolution for Dual-Fed Controls (1.11 and 1.23)

# SSC and CAA both feed Controls 1.11 and 1.23; apply worst-of-two logic for each
if (('SSC' -in $Solutions) -and ('CAA' -in $Solutions)) {
    foreach ($dualFedControl in @('1.11', '1.23')) {
        $sscResult = $allResults | Where-Object { $_.Solution -eq 'SSC' -and $_.ControlId -eq $dualFedControl -and $_.Status -ne 'No Data' } | Select-Object -First 1
        $caaResult = $allResults | Where-Object { $_.Solution -eq 'CAA' -and $_.ControlId -eq $dualFedControl -and $_.Status -ne 'No Data' } | Select-Object -First 1

        if ($sscResult -and $caaResult) {
            # Map status labels to numeric values for comparison
            $statusOrder = @{ 'Compliant' = 1; 'Partial' = 2; 'Non-Compliant' = 3 }
            $sscValue = $statusOrder[$sscResult.Status]
            $caaValue = $statusOrder[$caaResult.Status]
            $worstValue = [Math]::Max($sscValue, $caaValue)
            $worstLabel = ($statusOrder.GetEnumerator() | Where-Object { $_.Value -eq $worstValue }).Key
            $worstScore = switch ($worstValue) { 1 { 100 } 2 { 50 } 3 { 0 } }

            if ($sscValue -ne $caaValue) {
                Write-Host "[Control $dualFedControl] Dual-feed resolution: SSC=$($sscResult.Status), CAA=$($caaResult.Status) => Worst-of-two: $worstLabel" -ForegroundColor Magenta

                if (-not $DryRun) {
                    try {
                        $controlGuid = $controlGuids[$dualFedControl]
                        if ($controlGuid) {
                            $cdConfig = Get-DashboardTableConfig
                            # Use a UTC date window — the prior Microsoft.Dynamics.CRM.On
                            # call expected an ISO timestamp and used local time; both
                            # caused 400s and cross-day duplicates around midnight UTC.
                            $todayStart = [DateTime]::UtcNow.Date.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                            $tomorrowStart = [DateTime]::UtcNow.Date.AddDays(1).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

                            # Worst-of-two is computed *per zone* — limit the update
                            # to the SSC/CAA pair's zones so a Zone3 finding cannot
                            # overwrite an unrelated Zone1 row.
                            $candidateZones = @($sscResult.Zone, $caaResult.Zone) |
                                Where-Object { $_ -ne $null -and $_ -ne '' } |
                                Sort-Object -Unique
                            $zoneFilter = if ($candidateZones.Count -gt 0) {
                                ' and (' + (($candidateZones | ForEach-Object { "fsi_zone eq $_" }) -join ' or ') + ')'
                            } else { '' }

                            $existingQuery = "?`$filter=_fsi_controlmasterid_value eq $controlGuid and fsi_assessmentdate ge $todayStart and fsi_assessmentdate lt $tomorrowStart$zoneFilter"
                            $existingRecords = Invoke-DataverseQuery -Connection $connection `
                                -EntitySet $cdConfig.Assessment.EntitySet `
                                -Query $existingQuery

                            foreach ($existingRecord in $existingRecords) {
                                $worstNotes = "Automated assessment — worst-of-two resolution. SSC: $($sscResult.Status), CAA: $($caaResult.Status). Final: $worstLabel."
                                Update-DataverseRecord -Connection $connection `
                                    -EntitySet $cdConfig.Assessment.EntitySet `
                                    -RecordId $existingRecord.fsi_controlassessmentid `
                                    -Record @{
                                        'fsi_status' = $worstValue
                                        'fsi_score'  = $worstScore
                                        'fsi_notes'  = $worstNotes
                                    }
                            }
                            if ($existingRecords.Count -gt 0) {
                                Write-Host "  [Updated] Control $dualFedControl — $($existingRecords.Count) assessment(s) with worst-of-two result" -ForegroundColor Green
                            }
                        }
                    } catch {
                        Write-Warning "  [Error] Worst-of-two update for Control $dualFedControl : $($_.Exception.Message)"
                    }
                } else {
                    Write-Host "  [DryRun] Would update Control $dualFedControl assessment to $worstLabel (Score: $worstScore)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "[Control $dualFedControl] Dual-feed aligned: SSC and CAA both report $($sscResult.Status)" -ForegroundColor Green
            }
        }
    }
}

#endregion
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Sync Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

switch ($OutputFormat) {
    'Table' {
        $allResults | Format-Table Solution, ControlId, Status, Score, Action -AutoSize
    }
    'Json' {
        $allResults | ConvertTo-Json -Depth 5
    }
    'Object' {
        $allResults
    }
}

# Summary stats
$created = ($allResults | Where-Object { $_.Action -eq 'Created' }).Count
$updated = ($allResults | Where-Object { $_.Action -eq 'Updated' }).Count
$skipped = ($allResults | Where-Object { $_.Action -like 'Skip*' }).Count
$errors = ($allResults | Where-Object { $_.Action -like 'Error*' }).Count
$dryRunCount = ($allResults | Where-Object { $_.Action -like 'DryRun*' }).Count

Write-Host "Results: $created created, $updated updated, $skipped skipped, $errors errors" -ForegroundColor $(if ($errors -gt 0) { 'Red' } else { 'Green' })
if ($dryRunCount -gt 0) {
    Write-Host "DryRun: $dryRunCount assessments would be written" -ForegroundColor Yellow
}

Write-Host "`nSync complete.`n" -ForegroundColor Cyan

#endregion
