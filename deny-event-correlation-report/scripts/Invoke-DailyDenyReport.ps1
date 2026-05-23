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

.PARAMETER ExchangeOrganization
    Tenant primary domain (for example, example.onmicrosoft.com) used by Exchange Online unattended authentication.

.PARAMETER ExchangeManagedIdentity
    Use the Azure managed identity assigned to the runbook host for Exchange Online connections in the Purview Audit and DLP extractors.

.PARAMETER ExchangeAppId
    Entra application (client) ID for certificate-based app-only Exchange Online authentication when managed identity is not available.

.PARAMETER ExchangeCertificateThumbprint
    Certificate thumbprint for certificate-based app-only Exchange Online authentication.

.PARAMETER KeyVaultName
    Optional Azure Key Vault name containing non-secret configuration such as AppInsightsAppId.

.PARAMETER StorageAccountName
    Optional Azure Storage account for blob upload.

.PARAMETER StorageContainerName
    Optional blob container name. Defaults to "deny-events".

.PARAMETER SkipRaiTelemetry
    Skip RAI telemetry extraction (if App Insights not configured).

.PARAMETER SkipDefenderEvents
    Skip Defender CloudAppEvents extraction (if Defender for Cloud Apps not licensed).

.PARAMETER SkipUpload
    Skip upload to Azure Blob Storage.

.EXAMPLE
    .\Invoke-DailyDenyReport.ps1 -OutputDirectory "C:\Reports"
    Runs all extractions, saves locally, skips upload.

.EXAMPLE
    .\Invoke-DailyDenyReport.ps1 -ExchangeManagedIdentity -ExchangeOrganization "example.onmicrosoft.com" -KeyVaultName "kv-governance" -StorageAccountName "stgovernance"
    Runs all extractions from Azure Automation using managed identity for Exchange Online and uploads to blob.

.EXAMPLE
    .\Invoke-DailyDenyReport.ps1 -ExchangeAppId $appId -ExchangeCertificateThumbprint $thumbprint -ExchangeOrganization "example.onmicrosoft.com"
    Runs Purview Audit and DLP extractors with certificate-based app-only Exchange Online authentication.

.NOTES
    Author: FSI Agent Governance Framework
    Version: 1.1
    Requires: ExchangeOnlineManagement module 3.0+ (Az.Storage and Az.KeyVault required only for upload/KeyVault features)

.LINK
    https://github.com/judeper/FSI-AgentGov
#>

<#
================================================================================
  AUTHENTICATION NOTE: Microsoft Entra ID - Migration Complete
================================================================================

  Export-RaiTelemetry.ps1 uses Entra ID authentication via Connect-AzAccount.

  Migration completed: February 4, 2026

  The deprecated x-api-key authentication method has been removed from
  Export-RaiTelemetry.ps1. No API key parameter is needed.

  Prerequisites:
  - Install Az.Accounts module: Install-Module Az.Accounts -Force
  - Authenticate before running: Connect-AzAccount (or Connect-AzAccount -Identity in Azure Automation)
  - Grant Monitoring Reader role on Application Insights resource
  - For Purview Audit / DLP extractors, prefer -ExchangeManagedIdentity with
    -ExchangeOrganization. Use -ExchangeAppId / -ExchangeCertificateThumbprint
    only when managed identity is not available.

  Last verified: 2026-Q2 Microsoft Learn refresh

================================================================================
#>

<#
================================================================================
  FAILURE NOTIFICATION: Production Deployment Requirement
================================================================================

  For unattended FSI compliance reporting, configure external alerting to notify
  the compliance team when this script exits with a non-zero code:

  - Exit 1: All extractions failed (critical)
  - Exit 2: Partial failure - some extractions succeeded, some failed

  Recommended notification mechanisms:
  - Azure Automation: Configure webhook or Logic App alert on runbook failure
  - Power Automate: Trigger flow on Azure Automation job failure status
  - Azure Monitor: Create alert rule on Automation job Failed/PartiallyFailed
  - SMTP: Wrap invocation in a script that sends email on $LASTEXITCODE -ne 0

  This script intentionally does not implement notification directly, as the
  mechanism depends on the deployment environment (Azure Automation, Task
  Scheduler, etc.).

================================================================================
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputDirectory = ".",

    [Parameter()]
    [string]$AppInsightsAppId,

    [Parameter()]
    [string]$ExchangeOrganization,

    [Parameter()]
    [switch]$ExchangeManagedIdentity,

    [Parameter()]
    [string]$ExchangeAppId,

    [Parameter()]
    [string]$ExchangeCertificateThumbprint,

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
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.0.0' }

#region Configuration

$ErrorActionPreference = "Stop"
# Capture current time once to avoid midnight-crossing mismatches between
# $dateStamp, $reportStartDate, and $reportEndDate.
$now = Get-Date
$dateStamp = $now.AddDays(-1).ToString("yyyy-MM-dd")
$scriptDir = $PSScriptRoot

# Compute date window once to ensure all sub-scripts query the same period,
# even if the orchestrator spans midnight.
$reportStartDate = $now.AddDays(-1).Date
$reportEndDate = $now.Date

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

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Invokes a script block with retry and exponential backoff for transient failures.
    #>
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [int]$MaxRetries = 3,

        [int]$BaseDelaySeconds = 60
    )

    $attempt = 0
    while ($true) {
        try {
            $attempt++
            return & $ScriptBlock
        }
        catch {
            if ($attempt -ge $MaxRetries) {
                throw
            }
            $delay = $BaseDelaySeconds * [math]::Pow(2, $attempt - 1)
            Write-Warning "Attempt $attempt of $MaxRetries failed: $_. Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-KeyVaultSecrets {
    <#
    .SYNOPSIS
        Retrieves non-secret configuration from Azure Key Vault.
    #>
    param([string]$VaultName)

    Write-Host "Retrieving configuration from Key Vault: $VaultName" -ForegroundColor Gray

    # Runtime check: Az.KeyVault is only required when -KeyVaultName is provided
    if (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
        throw "Az.KeyVault module is required when -KeyVaultName is specified. Run: Install-Module Az.KeyVault -Force"
    }

    $secrets = @{}

    # Retrieve App Insights App ID from Key Vault
    # NOTE: AppInsightsApiKey retrieval removed - Entra ID auth (Wave 1 migration) no longer needs it
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

    # Runtime check: Az.Storage is only required when uploading to blob
    if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
        throw "Az.Storage module is required for blob upload. Run: Install-Module Az.Storage -Force"
    }

    Write-Host "Uploading to Azure Blob Storage..." -ForegroundColor Gray
    Write-Host "  Account: $StorageAccount" -ForegroundColor Gray
    Write-Host "  Container: $Container" -ForegroundColor Gray

    # Get storage context using connected identity
    $context = New-AzStorageContext -StorageAccountName $StorageAccount -UseConnectedAccount

    $script:BlobUploadFailures = 0

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
                $script:BlobUploadFailures++
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

    # Get non-secret configuration from Key Vault if specified
    if ($KeyVaultName) {
        $kvSecrets = Get-KeyVaultSecrets -VaultName $KeyVaultName

        if (-not $AppInsightsAppId -and $kvSecrets.AppInsightsAppId) {
            $AppInsightsAppId = $kvSecrets.AppInsightsAppId
        }
        # NOTE: ApiKey no longer retrieved from KeyVault - Entra ID auth path does not need it
    }


    # Build Exchange Online auth pass-through for child audit extractors.
    # Managed identity is preferred for Azure Automation. Certificate-based
    # app-only auth is the fallback for non-Azure unattended hosts.
    $exchangeAuthArgs = @{}
    if ($ExchangeManagedIdentity -and ($ExchangeAppId -or $ExchangeCertificateThumbprint)) {
        throw "Use either -ExchangeManagedIdentity or certificate-based Exchange auth parameters, not both."
    }
    if ($ExchangeManagedIdentity) {
        if (-not $ExchangeOrganization) {
            throw "ExchangeOrganization is required when -ExchangeManagedIdentity is specified."
        }
        $exchangeAuthArgs.ManagedIdentity = $true
        $exchangeAuthArgs.Organization = $ExchangeOrganization
    }
    elseif ($ExchangeAppId -or $ExchangeCertificateThumbprint -or $ExchangeOrganization) {
        if (-not ($ExchangeAppId -and $ExchangeCertificateThumbprint -and $ExchangeOrganization)) {
            throw "ExchangeAppId, ExchangeCertificateThumbprint, and ExchangeOrganization are all required for certificate-based Exchange auth."
        }
        $exchangeAuthArgs.AppId = $ExchangeAppId
        $exchangeAuthArgs.CertificateThumbprint = $ExchangeCertificateThumbprint
        $exchangeAuthArgs.Organization = $ExchangeOrganization
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
            Invoke-WithRetry -ScriptBlock {
                & $copilotScript -StartDate $reportStartDate -EndDate $reportEndDate -OutputPath $copilotDenyPath @exchangeAuthArgs
            }

            # Script completed without error - mark success even if zero events (no CSV created)
            $results.CopilotDeny.Success = $true
            if (Test-Path $copilotDenyPath) {
                $count = (Import-Csv $copilotDenyPath | Measure-Object).Count
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
    Write-StepHeader "2/4" "Extracting DLP Events for Copilot Location"

    try {
        $dlpScript = Join-Path $scriptDir "Export-DlpCopilotEvents.ps1"

        if (Test-Path $dlpScript) {
            Invoke-WithRetry -ScriptBlock {
                & $dlpScript -StartDate $reportStartDate -EndDate $reportEndDate -OutputPath $dlpEventsPath @exchangeAuthArgs
            }

            # Script completed without error - mark success even if zero events (no CSV created)
            $results.DlpEvents.Success = $true
            if (Test-Path $dlpEventsPath) {
                $count = (Import-Csv $dlpEventsPath | Measure-Object).Count
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
        Write-StepHeader "3/4" "Extracting RAI Telemetry from Application Insights"

        if ($AppInsightsAppId) {
            try {
                $raiScript = Join-Path $scriptDir "Export-RaiTelemetry.ps1"

                if (Test-Path $raiScript) {
                    Invoke-WithRetry -ScriptBlock {
                        & $raiScript `
                            -AppInsightsAppId $AppInsightsAppId `
                            -StartDate $reportStartDate `
                            -EndDate $reportEndDate `
                            -OutputPath $raiTelemetryPath
                    }

                    # Script completed without error - mark success even if zero events (no CSV created)
                    $results.RaiTelemetry.Success = $true
                    if (Test-Path $raiTelemetryPath) {
                        $count = (Import-Csv $raiTelemetryPath | Measure-Object).Count
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
            Write-Warning "Skipping RAI telemetry: AppInsightsAppId not provided."
            $results.RaiTelemetry.Skipped = $true
        }
    }
    else {
        Write-Host "[3/4] Skipping RAI Telemetry (SkipRaiTelemetry flag set)" -ForegroundColor Yellow
        $results.RaiTelemetry.Skipped = $true
    }

    #---------------------------------------------------------------------------
    # Step 4: Extract Defender CloudAppEvents
    #---------------------------------------------------------------------------
    if (-not $SkipDefenderEvents) {
        Write-StepHeader "4/4" "Extracting Defender CloudAppEvents (XPIA/Jailbreak)"

        try {
            $defenderScript = Join-Path $scriptDir "Export-DefenderCopilotEvents.ps1"

            if (Test-Path $defenderScript) {
                # NOTE: $exchangeAuthArgs intentionally NOT splatted here. The Defender
                # extractor uses Microsoft Graph (advanced hunting) and does not require
                # an Exchange Online session; auth flows through Connect-MgGraph instead.
                Invoke-WithRetry -ScriptBlock {
                    & $defenderScript `
                        -StartDate $reportStartDate `
                        -EndDate $reportEndDate `
                        -OutputPath $defenderEventsPath
                }

                $results.DefenderEvents.Success = $true
                if (Test-Path $defenderEventsPath) {
                    $count = (Import-Csv $defenderEventsPath | Measure-Object).Count
                    $results.DefenderEvents.EventCount = $count
                    $results.DefenderEvents.Path = $defenderEventsPath
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
        $results.DefenderEvents.Skipped = $true
    }

    #---------------------------------------------------------------------------
    # Step 5: Upload to Blob Storage (optional)
    #---------------------------------------------------------------------------
    if (-not $SkipUpload -and $StorageAccountName) {
        Write-StepHeader "Upload" "Uploading to Azure Blob Storage"

        $filesToUpload = @($copilotDenyPath, $dlpEventsPath, $raiTelemetryPath, $defenderEventsPath) | Where-Object { Test-Path $_ }

        if ($filesToUpload.Count -gt 0) {
            Send-ToBlobStorage `
                -StorageAccount $StorageAccountName `
                -Container $StorageContainerName `
                -FilePaths $filesToUpload `
                -DateFolder $dateStamp

            # Clean up local CSV files only if all blob uploads succeeded (data hygiene - CSVs contain PII)
            if ($script:BlobUploadFailures -eq 0) {
                foreach ($csvFile in $filesToUpload) {
                    try {
                        Remove-Item -Path $csvFile -Force -ErrorAction Stop
                        Write-Host "  Cleaned up local file: $(Split-Path $csvFile -Leaf)" -ForegroundColor Gray
                    }
                    catch {
                        Write-Warning "  Failed to remove local CSV $csvFile`: $_"
                    }
                }
            }
            else {
                Write-Warning "  Skipping local file cleanup - $($script:BlobUploadFailures) blob upload(s) failed. Local CSVs retained for manual upload."
            }
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
        $status = if ($result.Skipped) { "SKIPPED" } elseif ($result.Success) { "SUCCESS" } else { "FAILED" }
        $color = if ($result.Skipped) { "Yellow" } elseif ($result.Success) { "Green" } else { "Red" }

        Write-Host "  $key`: " -NoNewline
        Write-Host $status -ForegroundColor $color -NoNewline
        Write-Host " ($($result.EventCount) events)"

        $totalEvents += $result.EventCount
    }

    Write-Host ""
    Write-Host "  Total Events: $totalEvents" -ForegroundColor White
    Write-Host ""

    # Exit with appropriate code (exclude skipped steps from failure calculation)
    $executed = $results.Values | Where-Object { -not $_.Skipped }
    $successCount = @($executed | Where-Object { $_.Success }).Count
    $executedCount = @($executed).Count
    if ($executedCount -eq 0) {
        Write-Host "All extractions were skipped." -ForegroundColor Yellow
        exit 0
    }
    elseif ($successCount -eq 0) {
        Write-Error "All extractions failed."
        exit 1
    }
    elseif ($successCount -lt $executedCount) {
        Write-Warning "Some extractions failed. Review output above."
        Write-Warning "ACTION REQUIRED: For unattended FSI compliance reporting, configure external alerting (e.g., Azure Monitor, Power Automate, or SMTP) to notify the compliance team on non-zero exit codes."
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
    catch {
        Write-Verbose ("Exchange Online disconnect after daily deny report in {0} failed (non-fatal): {1}" -f $OutputDirectory, $_.Exception.Message)
    }
}

#endregion Main Execution
