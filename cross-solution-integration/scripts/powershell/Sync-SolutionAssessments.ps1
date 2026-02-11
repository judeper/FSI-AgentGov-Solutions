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
    Version: 1.0.0
    Date: 2026-02-10
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

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Interactive,

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

#region Authentication

function Connect-DataverseApi {
    param(
        [string]$Url,
        [string]$TenantId,
        [string]$ClientId,
        [SecureString]$ClientSecret,
        [switch]$Interactive
    )

    $scope = "$($Url.TrimEnd('/'))/.default"

    if ($Interactive) {
        Write-Verbose "Authenticating interactively to $Url"
        $token = Get-MsalToken -TenantId $TenantId -ClientId '51f81489-12ee-4a9e-aaae-a2591f45987d' -Scopes $scope -Interactive
    } else {
        Write-Verbose "Authenticating with service principal to $Url"
        $credential = New-Object System.Management.Automation.PSCredential($ClientId, $ClientSecret)
        $token = Get-MsalToken -TenantId $TenantId -ClientId $ClientId -ClientCredential $credential -Scopes $scope
    }

    return @{
        BaseUrl = "$($Url.TrimEnd('/'))/api/data/v9.2"
        Headers = @{
            'Authorization' = "Bearer $($token.AccessToken)"
            'OData-MaxVersion' = '4.0'
            'OData-Version' = '4.0'
            'Accept' = 'application/json'
            'Content-Type' = 'application/json'
            'Prefer' = 'return=representation'
        }
    }
}

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

    try {
        $response = Invoke-RestMethod -Uri $url -Headers $Connection.Headers -Method Get
        return $response.value
    } catch {
        Write-Warning "Failed to query $EntitySet : $($_.Exception.Message)"
        return @()
    }
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

    $response = Invoke-RestMethod -Uri $url -Headers $Connection.Headers -Method Post -Body $body
    return $response
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

    Invoke-RestMethod -Uri $url -Headers $Connection.Headers -Method Patch -Body $body
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
    $results = @()

    foreach ($controlId in $controlIds) {
        $controlGuid = $ControlGuids[$controlId]
        if (-not $controlGuid) {
            Write-Warning "Control $controlId not found in fsi_controlmaster — skipping"
            continue
        }

        $notes = "Automated assessment via $($tableConfig.SolutionName) $($tableConfig.SolutionVersion). " +
                 "Run ID: $runId. Status: $($dashStatus.StatusLabel). " +
                 "Source: $($tableConfig.EntitySet), Timestamp: $timestamp."

        $assessmentRecord = @{
            'fsi_controlmasterid@odata.bind' = "/fsi_controlmasters($controlGuid)"
            'fsi_assessmentdate'             = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            'fsi_status'                     = $dashStatus.Status
            'fsi_score'                      = $dashStatus.Score
            'fsi_notes'                      = $notes
            'fsi_nextreviewdate'             = (Get-Date).AddDays(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        $result = [PSCustomObject]@{
            Solution     = $Solution
            ControlId    = $controlId
            Status       = $dashStatus.StatusLabel
            Score        = $dashStatus.Score
            RunId        = $runId
            Timestamp    = $timestamp
            Action       = 'Pending'
        }

        if ($DryRun) {
            $result.Action = 'DryRun — would create assessment'
            Write-Host "  [DryRun] $Solution → Control $controlId : $($dashStatus.StatusLabel) (Score: $($dashStatus.Score))" -ForegroundColor Yellow
        } else {
            try {
                # Check for existing same-day assessment
                $today = (Get-Date).ToString('yyyy-MM-dd')
                $existingQuery = "?`$filter=_fsi_controlmasterid_value eq $controlGuid and Microsoft.Dynamics.CRM.On(PropertyName='fsi_assessmentdate',PropertyValue='$today')&`$top=1"
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
                    Write-Host "  [Updated] $Solution → Control $controlId : $($dashStatus.StatusLabel)" -ForegroundColor Green
                } else {
                    # Create new
                    $newRecord = New-DataverseRecord -Connection $Connection `
                        -EntitySet $cdConfig.Assessment.EntitySet `
                        -Record $assessmentRecord
                    $result.Action = 'Created'
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
        [switch]$DryRun
    )

    $evidenceScripts = Get-EvidenceExportScripts
    $cdConfig = Get-DashboardTableConfig

    # Look for evidence files matching the solution
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

    $hash = $null
    if (Test-Path $hashFile) {
        $hashContent = Get-Content $hashFile -Raw
        $hash = ($hashContent -split '\s+')[0]
    } else {
        # Calculate hash directly
        $hash = (Get-FileHash -Path $evidenceFile.FullName -Algorithm SHA256).Hash.ToLower()
    }

    $evidenceRecord = @{
        'fsi_name'          = "$Solution Evidence Export — $(Get-Date -Format 'yyyy-MM-dd')"
        'fsi_evidencetype'  = Get-EvidenceTypeId
        'fsi_description'   = "Automated evidence from $((Get-SolutionTableConfig)[$Solution].SolutionName). SHA-256 verified. File: $($evidenceFile.Name)"
        'fsi_collecteddate' = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
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
$connection = Connect-DataverseApi -Url $DataverseUrl -TenantId $TenantId `
    -ClientId $ClientId -ClientSecret $ClientSecret -Interactive:$Interactive

# Resolve control master GUIDs
Write-Host "Resolving control master GUIDs..." -ForegroundColor Gray
$controlGuids = Get-ControlMasterGuids -Connection $connection

if ($controlGuids.Count -eq 0) {
    throw "No control master records found. Ensure the Compliance Dashboard sample data is loaded."
}

Write-Host "Found $($controlGuids.Count) controls in dashboard`n" -ForegroundColor Green

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
                    -EvidenceDirectory $EvidenceDirectory -DryRun:$DryRun
            }
        }
    }

    Write-Host ""
}

#region Worst-of-Two Resolution for Control 1.11

# If both SSC and CAA contributed assessments for Control 1.11, apply worst-of-two logic
if (('SSC' -in $Solutions) -and ('CAA' -in $Solutions)) {
    $sscResult = $allResults | Where-Object { $_.Solution -eq 'SSC' -and $_.ControlId -eq '1.11' -and $_.Status -ne 'No Data' } | Select-Object -First 1
    $caaResult = $allResults | Where-Object { $_.Solution -eq 'CAA' -and $_.ControlId -eq '1.11' -and $_.Status -ne 'No Data' } | Select-Object -First 1

    if ($sscResult -and $caaResult) {
        # Map status labels to numeric values for comparison
        $statusOrder = @{ 'Compliant' = 1; 'Partial' = 2; 'Non-Compliant' = 3 }
        $sscValue = $statusOrder[$sscResult.Status]
        $caaValue = $statusOrder[$caaResult.Status]
        $worstValue = [Math]::Max($sscValue, $caaValue)
        $worstLabel = ($statusOrder.GetEnumerator() | Where-Object { $_.Value -eq $worstValue }).Key
        $worstScore = switch ($worstValue) { 1 { 100 } 2 { 50 } 3 { 0 } }

        if ($sscValue -ne $caaValue) {
            Write-Host "[Control 1.11] Dual-feed resolution: SSC=$($sscResult.Status), CAA=$($caaResult.Status) => Worst-of-two: $worstLabel" -ForegroundColor Magenta

            if (-not $DryRun) {
                try {
                    $controlGuid = $controlGuids['1.11']
                    if ($controlGuid) {
                        $cdConfig = Get-DashboardTableConfig
                        $today = (Get-Date).ToString('yyyy-MM-dd')
                        $existingQuery = "?`$filter=_fsi_controlmasterid_value eq $controlGuid and Microsoft.Dynamics.CRM.On(PropertyName='fsi_assessmentdate',PropertyValue='$today')&`$top=1"
                        $existing = Invoke-DataverseQuery -Connection $connection `
                            -EntitySet $cdConfig.Assessment.EntitySet `
                            -Query $existingQuery

                        if ($existing.Count -gt 0) {
                            $worstNotes = "Automated assessment — worst-of-two resolution. SSC: $($sscResult.Status), CAA: $($caaResult.Status). Final: $worstLabel."
                            Update-DataverseRecord -Connection $connection `
                                -EntitySet $cdConfig.Assessment.EntitySet `
                                -RecordId $existing[0].fsi_controlassessmentid `
                                -Record @{
                                    'fsi_status' = $worstValue
                                    'fsi_score'  = $worstScore
                                    'fsi_notes'  = $worstNotes
                                }
                            Write-Host "  [Updated] Control 1.11 assessment with worst-of-two result" -ForegroundColor Green
                        }
                    }
                } catch {
                    Write-Warning "  [Error] Worst-of-two update for Control 1.11: $($_.Exception.Message)"
                }
            } else {
                Write-Host "  [DryRun] Would update Control 1.11 assessment to $worstLabel (Score: $worstScore)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[Control 1.11] Dual-feed aligned: SSC and CAA both report $($sscResult.Status)" -ForegroundColor Green
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
