<#
.SYNOPSIS
    Orchestrates daily execution of all deny event extraction scripts.

.DESCRIPTION
    Master orchestration script that:
    1. Extracts CopilotInteraction deny events from Purview Audit
    2. Extracts DLP events for Copilot policy location
    3. Extracts RAI telemetry from Application Insights
    4. Uploads results to Azure Blob Storage (optional)

.PARAMETER OutputDirectory
    Local directory for CSV exports. Defaults to current directory.

.PARAMETER AppInsightsAppId
    Application Insights Application ID for RAI telemetry.

.PARAMETER AppInsightsApiKey
    Application Insights API key. Can also be provided via KeyVault.

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
    Version: 1.0
    Requires: ExchangeOnlineManagement, Az.Storage, Az.KeyVault modules

.LINK
    https://github.com/judeper/FSI-AgentGov
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputDirectory = ".",

    [Parameter()]
    [string]$AppInsightsAppId,

    [Parameter()]
    [string]$AppInsightsApiKey,

    [Parameter()]
    [string]$KeyVaultName,

    [Parameter()]
    [string]$StorageAccountName,

    [Parameter()]
    [string]$StorageContainerName = "deny-events",

    [Parameter()]
    [switch]$SkipRaiTelemetry,

    [Parameter()]
    [switch]$SkipUpload
)

#region Configuration

$ErrorActionPreference = "Stop"
$dateStamp = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
$scriptDir = $PSScriptRoot

# Output file paths
$copilotDenyPath = Join-Path $OutputDirectory "CopilotDenyEvents-$dateStamp.csv"
$dlpEventsPath = Join-Path $OutputDirectory "DlpCopilotEvents-$dateStamp.csv"
$raiTelemetryPath = Join-Path $OutputDirectory "RaiTelemetry-$dateStamp.csv"

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

    # Try to get App Insights credentials
    try {
        $secrets.AppInsightsAppId = Get-AzKeyVaultSecret -VaultName $VaultName -Name "AppInsightsAppId" -AsPlainText -ErrorAction SilentlyContinue
        $secrets.AppInsightsApiKey = Get-AzKeyVaultSecret -VaultName $VaultName -Name "AppInsightsApiKey" -AsPlainText -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Could not retrieve App Insights secrets from Key Vault."
    }

    return $secrets
}

function Upload-ToBlobStorage {
    <#
    .SYNOPSIS
        Uploads files to Azure Blob Storage.
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
        if (-not $AppInsightsApiKey -and $kvSecrets.AppInsightsApiKey) {
            $AppInsightsApiKey = $kvSecrets.AppInsightsApiKey
        }
    }

    # Track results
    $results = @{
        CopilotDeny = @{ Success = $false; EventCount = 0; Path = $null }
        DlpEvents   = @{ Success = $false; EventCount = 0; Path = $null }
        RaiTelemetry = @{ Success = $false; EventCount = 0; Path = $null }
    }

    #---------------------------------------------------------------------------
    # Step 1: Extract CopilotInteraction Deny Events
    #---------------------------------------------------------------------------
    Write-StepHeader "1/3" "Extracting CopilotInteraction Deny Events"

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
    Write-StepHeader "2/3" "Extracting DLP Events for Copilot Location"

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
        Write-StepHeader "3/3" "Extracting RAI Telemetry from Application Insights"

        if ($AppInsightsAppId -and $AppInsightsApiKey) {
            try {
                $raiScript = Join-Path $scriptDir "Export-RaiTelemetry.ps1"

                if (Test-Path $raiScript) {
                    & $raiScript `
                        -AppInsightsAppId $AppInsightsAppId `
                        -ApiKey $AppInsightsApiKey `
                        -OutputPath $raiTelemetryPath

                    if (Test-Path $raiTelemetryPath) {
                        $count = (Import-Csv $raiTelemetryPath | Measure-Object).Count
                        $results.RaiTelemetry.Success = $true
                        $results.RaiTelemetry.EventCount = $count
                        $results.RaiTelemetry.Path = $raiTelemetryPath
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
            Write-Warning "Skipping RAI telemetry: AppInsightsAppId or ApiKey not provided."
        }
    }
    else {
        Write-Host "[3/3] Skipping RAI Telemetry (SkipRaiTelemetry flag set)" -ForegroundColor Yellow
    }

    #---------------------------------------------------------------------------
    # Step 4: Upload to Blob Storage (optional)
    #---------------------------------------------------------------------------
    if (-not $SkipUpload -and $StorageAccountName) {
        Write-StepHeader "Upload" "Uploading to Azure Blob Storage"

        $filesToUpload = @($copilotDenyPath, $dlpEventsPath, $raiTelemetryPath) | Where-Object { Test-Path $_ }

        if ($filesToUpload.Count -gt 0) {
            Upload-ToBlobStorage `
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
    if ($successCount -eq 0) {
        Write-Error "All extractions failed."
        exit 1
    }
    elseif ($successCount -lt $results.Count) {
        Write-Warning "Some extractions failed. Review output above."
        exit 0
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
