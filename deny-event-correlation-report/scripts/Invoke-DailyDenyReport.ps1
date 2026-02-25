<#
.SYNOPSIS
    Orchestrates daily execution of all deny event extraction scripts.

.DESCRIPTION
    Master orchestration script that:
    1. Extracts CopilotInteraction deny events from Purview Audit
    2. Extracts DLP events for Copilot policy location
    3. Extracts RAI telemetry from Application Insights
    4. Extracts Defender CloudAppEvents (XPIA/Jailbreak detections)
    5. Uploads results to Azure Blob Storage (optional)

.PARAMETER OutputDirectory
    Local directory for CSV exports. Defaults to current directory.

.PARAMETER AppInsightsAppId
    Application Insights Application ID for RAI telemetry.

.PARAMETER KeyVaultName
    Optional Azure Key Vault name containing credentials.

.PARAMETER StorageAccountName
    Optional Azure Storage account for blob upload.

.PARAMETER StorageContainerName
    Optional blob container name. Defaults to "deny-events".

.PARAMETER SkipRaiTelemetry
    Skip RAI telemetry extraction (if App Insights not configured).

.PARAMETER SkipUpload
    Skip upload to Azure Blob Storage.

.EXAMPLE
    .\Invoke-DailyDenyReport.ps1 -OutputDirectory "C:\Reports"
    Runs all extractions, saves locally, skips upload.

.EXAMPLE
    .\Invoke-DailyDenyReport.ps1 -KeyVaultName "kv-governance" -StorageAccountName "stgovernance"
    Runs all extractions using Key Vault credentials and uploads to blob.

.NOTES
    Author: FSI Agent Governance Framework
    Version: 2.0.0
    Requires: ExchangeOnlineManagement module; Az.Accounts and Az.Storage conditionally when RAI telemetry is not skipped or blob upload is used; Az.KeyVault conditionally when using Key Vault; Microsoft.Graph.Security conditionally when Defender events are not skipped

.LINK
    https://github.com/judeper/FSI-AgentGov
#>

<#
================================================================================
  Export-RaiTelemetry.ps1 uses Entra ID (Azure AD) authentication.
  Migration from deprecated x-api-key completed February 4, 2026.
================================================================================
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputDirectory = ".",

    [Parameter()]
    [string]$AppInsightsAppId,

    [Parameter()]
    [string]$KeyVaultName,

    [Parameter()]
    [string]$StorageAccountName,

    [Parameter()]
    [string]$StorageContainerName = "deny-events",

    [Parameter()]
    [switch]$SkipRaiTelemetry,

    [Parameter()]
    [switch]$SkipDefenderEvents,

    [Parameter()]
    [switch]$SkipUpload
)

#Requires -Version 7.0
#Requires -Modules ExchangeOnlineManagement

#region Configuration

$ErrorActionPreference = "Stop"
$dateStamp = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
$scriptDir = $PSScriptRoot

# Conditionally import Az modules only when needed
if ($KeyVaultName) {
    Import-Module Az.KeyVault -ErrorAction Stop
}
if ($StorageAccountName -and -not $SkipUpload) {
    Import-Module Az.Storage -ErrorAction Stop
}

# Output file paths
$copilotDenyPath = Join-Path $OutputDirectory "CopilotDenyEvents-$dateStamp.csv"
$dlpEventsPath = Join-Path $OutputDirectory "DlpCopilotEvents-$dateStamp.csv"
$raiTelemetryPath = Join-Path $OutputDirectory "RaiTelemetry-$dateStamp.csv"
$defenderEventsPath = Join-Path $OutputDirectory "DefenderCopilotEvents-$dateStamp.csv"

#endregion Configuration

#region Functions

function Write-StepHeader {
    param([string]$Step, [string]$Description)
    Write-Host "`n[$Step] $Description" -ForegroundColor Cyan
    Write-Host ("-" * 50) -ForegroundColor Gray
}

function Get-KeyVaultSecrets {
    <#
    .SYNOPSIS
        Retrieves credentials from Azure Key Vault.
    #>
    param([string]$VaultName)

    Write-Host "Retrieving credentials from Key Vault: $VaultName" -ForegroundColor Gray

    $secrets = @{}

    # Retrieve App Insights App ID from Key Vault
    # NOTE: AppInsightsApiKey retrieval removed — Entra ID auth (Wave 1 migration) no longer needs it
    try {
        $secrets.AppInsightsAppId = Get-AzKeyVaultSecret -VaultName $VaultName -Name "AppInsightsAppId" -AsPlainText -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Could not retrieve App Insights secrets from Key Vault."
    }

    return $secrets
}

function Send-ToBlobStorage {
    <#
    .SYNOPSIS
        Sends files to Azure Blob Storage.
    #>
    param(
        [string]$StorageAccount,
        [string]$Container,
        [string[]]$FilePaths,
        [string]$DateFolder
    )

    Write-Host "Uploading to Azure Blob Storage..." -ForegroundColor Gray
    Write-Host "  Account: $StorageAccount" -ForegroundColor Gray
    Write-Host "  Container: $Container" -ForegroundColor Gray

    # Get storage context using connected identity
    $context = New-AzStorageContext -StorageAccountName $StorageAccount -UseConnectedAccount

    foreach ($filePath in $FilePaths) {
        if (Test-Path $filePath) {
            $fileName = Split-Path $filePath -Leaf
            $blobName = "$DateFolder/$fileName"

            try {
                Set-AzStorageBlobContent `
                    -File $filePath `
                    -Container $Container `
                    -Blob $blobName `
                    -Context $context `
                    -Force | Out-Null

                Write-Host "  Uploaded: $blobName" -ForegroundColor Green
            }
            catch {
                Write-Warning "  Failed to upload $fileName`: $_"
            }
        }
    }
}

#endregion Functions

#region Main Execution

try {
    Write-Host "`n" -NoNewline
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     Daily Deny Event Report Orchestration        ║" -ForegroundColor Cyan
    Write-Host "║     FSI Agent Governance Framework               ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Report Date: $dateStamp" -ForegroundColor White
    Write-Host "Output Directory: $OutputDirectory" -ForegroundColor White
    Write-Host ""

    # Ensure output directory exists
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
        Write-Host "Created output directory: $OutputDirectory" -ForegroundColor Gray
    }

    # Get credentials from Key Vault if specified
    if ($KeyVaultName) {
        $kvSecrets = Get-KeyVaultSecrets -VaultName $KeyVaultName

        if (-not $AppInsightsAppId -and $kvSecrets.AppInsightsAppId) {
            $AppInsightsAppId = $kvSecrets.AppInsightsAppId
        }
        # NOTE: ApiKey no longer retrieved from KeyVault — Entra ID auth path does not need it
    }

    # Track results
    $results = @{
        CopilotDeny    = @{ Success = $false; EventCount = 0; Path = $null }
        DlpEvents      = @{ Success = $false; EventCount = 0; Path = $null }
        RaiTelemetry   = @{ Success = $false; EventCount = 0; Path = $null }
        DefenderEvents = @{ Success = $false; EventCount = 0; Path = $null }
    }

    #---------------------------------------------------------------------------
    # Step 1: Extract CopilotInteraction Deny Events
    #---------------------------------------------------------------------------
    Write-StepHeader "1/4" "Extracting CopilotInteraction Deny Events"

    try {
        $copilotScript = Join-Path $scriptDir "Export-CopilotDenyEvents.ps1"

        if (Test-Path $copilotScript) {
            & $copilotScript -OutputPath $copilotDenyPath

            if (Test-Path $copilotDenyPath) {
                $count = (Import-Csv $copilotDenyPath | Measure-Object).Count
                $results.CopilotDeny.Success = $true
                $results.CopilotDeny.EventCount = $count
                $results.CopilotDeny.Path = $copilotDenyPath
            }
            elseif ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                # Child script exited successfully but found zero events (no CSV created)
                $results.CopilotDeny.Success = $true
                $results.CopilotDeny.EventCount = 0
                Write-Host "  No deny events found (zero events is normal)." -ForegroundColor Yellow
            }
        }
        else {
            Write-Warning "Script not found: $copilotScript"
        }
    }
    catch {
        Write-Warning "CopilotInteraction extraction failed: $_"
    }

    #---------------------------------------------------------------------------
    # Step 2: Extract DLP Events
    #---------------------------------------------------------------------------
    Write-StepHeader "2/4" "Extracting DLP Events for Copilot Location"

    try {
        $dlpScript = Join-Path $scriptDir "Export-DlpCopilotEvents.ps1"

        if (Test-Path $dlpScript) {
            & $dlpScript -OutputPath $dlpEventsPath

            if (Test-Path $dlpEventsPath) {
                $count = (Import-Csv $dlpEventsPath | Measure-Object).Count
                $results.DlpEvents.Success = $true
                $results.DlpEvents.EventCount = $count
                $results.DlpEvents.Path = $dlpEventsPath
            }
            elseif ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                $results.DlpEvents.Success = $true
                $results.DlpEvents.EventCount = 0
                Write-Host "  No DLP events found (zero events is normal)." -ForegroundColor Yellow
            }
        }
        else {
            Write-Warning "Script not found: $dlpScript"
        }
    }
    catch {
        Write-Warning "DLP extraction failed: $_"
    }

    #---------------------------------------------------------------------------
    # Step 3: Extract RAI Telemetry
    #---------------------------------------------------------------------------
    if (-not $SkipRaiTelemetry) {
        Write-StepHeader "3/4" "Extracting RAI Telemetry from Application Insights"

        if ($AppInsightsAppId) {
            try {
                $raiScript = Join-Path $scriptDir "Export-RaiTelemetry.ps1"

                if (Test-Path $raiScript) {
                    & $raiScript `
                        -AppInsightsAppId $AppInsightsAppId `
                        -OutputPath $raiTelemetryPath

                    if (Test-Path $raiTelemetryPath) {
                        $count = (Import-Csv $raiTelemetryPath | Measure-Object).Count
                        $results.RaiTelemetry.Success = $true
                        $results.RaiTelemetry.EventCount = $count
                        $results.RaiTelemetry.Path = $raiTelemetryPath
                    }
                    elseif ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                        $results.RaiTelemetry.Success = $true
                        $results.RaiTelemetry.EventCount = 0
                        Write-Host "  No RAI events found (zero events is normal)." -ForegroundColor Yellow
                    }
                }
                else {
                    Write-Warning "Script not found: $raiScript"
                }
            }
            catch {
                Write-Warning "RAI telemetry extraction failed: $_"
            }
        }
        else {
            Write-Warning "Skipping RAI telemetry: AppInsightsAppId not provided."
        }
    }
    else {
        Write-Host "[3/4] Skipping RAI Telemetry (SkipRaiTelemetry flag set)" -ForegroundColor Yellow
        $results.Remove('RaiTelemetry')
    }

    #---------------------------------------------------------------------------
    # Step 4: Extract Defender CloudAppEvents (XPIA/Jailbreak)
    #---------------------------------------------------------------------------
    if (-not $SkipDefenderEvents) {
        Write-StepHeader "4/4" "Extracting Defender CloudAppEvents (XPIA/Jailbreak)"

        try {
            $defenderScript = Join-Path $scriptDir "Export-DefenderCopilotEvents.ps1"

            if (Test-Path $defenderScript) {
                & $defenderScript -OutputPath $defenderEventsPath

                if (Test-Path $defenderEventsPath) {
                    $count = (Import-Csv $defenderEventsPath | Measure-Object).Count
                    $results.DefenderEvents.Success = $true
                    $results.DefenderEvents.EventCount = $count
                    $results.DefenderEvents.Path = $defenderEventsPath
                }
                elseif ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                    $results.DefenderEvents.Success = $true
                    $results.DefenderEvents.EventCount = 0
                    Write-Host "  No Defender events found (zero events is normal)." -ForegroundColor Yellow
                }
            }
            else {
                Write-Warning "Script not found: $defenderScript"
            }
        }
        catch {
            Write-Warning "Defender CloudAppEvents extraction failed: $_"
        }
    }
    else {
        Write-Host "[4/4] Skipping Defender CloudAppEvents (SkipDefenderEvents flag set)" -ForegroundColor Yellow
        $results.Remove('DefenderEvents')
    }

    #---------------------------------------------------------------------------
    # Step 5: Upload to Blob Storage (optional)
    #---------------------------------------------------------------------------
    if (-not $SkipUpload -and $StorageAccountName) {
        Write-StepHeader "Upload" "Uploading to Azure Blob Storage"

        $uploadCandidates = @($copilotDenyPath, $dlpEventsPath)
        if (-not $SkipRaiTelemetry) { $uploadCandidates += $raiTelemetryPath }
        if (-not $SkipDefenderEvents) { $uploadCandidates += $defenderEventsPath }
        $filesToUpload = $uploadCandidates | Where-Object { Test-Path $_ }

        if ($filesToUpload.Count -gt 0) {
            Send-ToBlobStorage `
                -StorageAccount $StorageAccountName `
                -Container $StorageContainerName `
                -FilePaths $filesToUpload `
                -DateFolder $dateStamp
        }
        else {
            Write-Warning "No files to upload."
        }
    }

    #---------------------------------------------------------------------------
    # Summary
    #---------------------------------------------------------------------------
    Write-Host "`n" -NoNewline
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                  Execution Summary               ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan

    $totalEvents = 0

    foreach ($key in $results.Keys) {
        $result = $results[$key]
        $status = if ($result.Success) { "SUCCESS" } else { "FAILED" }
        $color = if ($result.Success) { "Green" } else { "Red" }

        Write-Host "  $key`: " -NoNewline
        Write-Host $status -ForegroundColor $color -NoNewline
        Write-Host " ($($result.EventCount) events)"

        $totalEvents += $result.EventCount
    }

    Write-Host ""
    Write-Host "  Total Events: $totalEvents" -ForegroundColor White
    Write-Host ""

    # Exit with appropriate code
    $successCount = ($results.Values | Where-Object { $_.Success }).Count

    # Write execution log for regulatory audit trail
    $logPath = Join-Path $OutputDirectory "DenyReport-ExecutionLog-$dateStamp.log"
    $logEntries = [System.Collections.Generic.List[string]]::new()
    $logEntries.Add("=== Deny Event Report Execution Log ===")
    $logEntries.Add("Timestamp : $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')")
    $logEntries.Add("ReportDate: $dateStamp")
    $logEntries.Add("OutputDir : $OutputDirectory")
    $logEntries.Add("---")
    foreach ($key in $results.Keys) {
        $r = $results[$key]
        $status = if ($r.Success) { "SUCCESS" } else { "FAILED" }
        $logEntries.Add("$key : $status ($($r.EventCount) events)")
    }
    $logEntries.Add("TotalEvents: $totalEvents")
    $logEntries.Add("OverallStatus: $(if ($successCount -eq $results.Count) { 'SUCCESS' } elseif ($successCount -eq 0) { 'FAILED' } else { 'PARTIAL' })")
    $logEntries | Out-File -FilePath $logPath -Encoding UTF8
    Write-Host "  Execution log: $logPath" -ForegroundColor Gray

    if ($successCount -eq 0) {
        Write-Error "All extractions failed."
        exit 1
    }
    elseif ($successCount -lt $results.Count) {
        Write-Warning "Some extractions failed. Review output above."
        exit 2
    }
    else {
        Write-Host "Daily deny report completed successfully!" -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Error "Orchestration failed: $_"
    exit 1
}
finally {
    # Disconnect from Exchange Online if connected
    try {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch { }
}

#endregion Main Execution
