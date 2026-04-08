#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Microsoft.PowerApps.Administration.PowerShell"; ModuleVersion="2.0.180" }, @{ ModuleName="MSAL.PS"; ModuleVersion="4.37.0" }
# NOTE: MSAL.PS is archived and no longer maintained. Plan migration to
# Az.Accounts (Get-AzAccessToken) or Microsoft.Identity.Client.

<#
.SYNOPSIS
    Azure Automation runbook wrapper for environment-level audit configuration validation.

.DESCRIPTION
    Adapts Invoke-EnvironmentAuditValidation.ps1 for Azure Automation execution context.
    This runbook provides non-interactive authentication, structured JSON output to
    the pipeline, and per-environment drift detection for downstream alerting.

    Key differences from interactive orchestrator:
    - Uses certificate or client secret authentication (no interactive prompts)
    - Outputs JSON to pipeline (captured by Get-AzAutomationJobOutput)
    - Includes per-environment drift detection via Compare-ValidationBaseline
    - Adds AlertRequired flag to each environment result
    - Returns aggregated AlertsRequired array for flow routing
    - No Write-Host (uses Write-Verbose for diagnostics)

    Output structure enables Power Automate HTTP webhook actions to parse validation
    results and route per-environment alerts based on drift status.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID for authentication.

.PARAMETER DataverseUrl
    Central Dataverse organization URL where environment registryand validation
    history are stored. Example: https://governance.crm.dynamics.com

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for service principal authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication. Certificate must be
    uploaded to the Azure Automation account.

.PARAMETER ClientSecret
    Client secret for service principal authentication (alternative to certificate).
    Must be stored as encrypted variable in Automation Account.

.PARAMETER IncludeTrialDev
    Override to include Trial and Developer environments in validation.

.PARAMETER GracePeriodHours
    Hours after audit enablement to allow before treating absence as failure. Default: 24.

.PARAMETER SkipDiscovery
    Skip discovery phase and use existing environment registry data. Useful for
    faster repeat validations. Default: false.

.EXAMPLE
    Start-EnvironmentValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456"

    Runs environment validation using certificate authentication.
    Outputs JSON to pipeline with per-environment drift detection.

.OUTPUTS
    JSON object with properties:
    - RunType: "EnvironmentValidation"
    - RunId: GUID linking all validation records
    - Timestamp: ISO 8601 UTC timestamp
    - TotalEnvironments: Count of environments validated
    - OverallStatus: Passed | Warning | GracePeriod | Failed | Error
    - PerEnvironmentResults: Array with drift info and AlertRequired per environment
    - AlertsRequired: Filtered array of environments needing alerts
    - NewEnvironments: Array of newly discovered environment names
    - SkippedUnclassified: Array of unclassified environment names
    - SkippedTrialDev: Array of Trial/Developer environment names

.NOTES
    Version: 1.0.0

    Azure Automation setup:
    1. Import this script as a runbook
    2. Upload certificate to Automation Account > Certificates (or store ClientSecret as encrypted variable)
    3. Install required modules: Microsoft.PowerApps.Administration.PowerShell, MSAL.PS
    4. Grant application permissions:
       - Power Platform Administrator role
       - Dataverse System Administrator role in central environment
    5. Schedule via Schedules or trigger via webhook

    Performance:
    - Full validation (with discovery): 2-5 minutes
    - Without discovery (-SkipDiscovery): 30-60 seconds

    This script is designed to run as an Azure Automation runbook. Import into
    Azure Automation Account and configure with certificate-based authentication.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeTrialDev,

    [Parameter(Mandatory = $false)]
    [int]$GracePeriodHours = 24,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDiscovery
)

$ErrorActionPreference = "Stop"

try {
    Write-Verbose "Starting environment validation runbook"
    Write-Verbose "TenantId: $TenantId"
    Write-Verbose "DataverseUrl: $DataverseUrl"
    Write-Verbose "IncludeTrialDev: $IncludeTrialDev"
    Write-Verbose "SkipDiscovery: $SkipDiscovery"

    # Dot-source required scripts from same directory
    $scriptRoot = $PSScriptRoot
    Write-Verbose "Script root: $scriptRoot"

    $privatePath = Join-Path $PSScriptRoot 'private'
    $requiredHelpers = @(
        'Compare-ValidationBaseline.ps1'
    )
    foreach ($helper in $requiredHelpers) {
        $helperPath = Join-Path $privatePath $helper
        if (-not (Test-Path $helperPath)) {
            throw "Required helper script not found: $helperPath. Ensure the solution is installed correctly."
        }
        . $helperPath
    }

    Write-Verbose "Scripts loaded successfully"

    # Build parameters for Invoke-EnvironmentAuditValidation
    # Do NOT pass -Interactive or -OutputPath (not suitable for runbook context)
    $envParams = @{
        TenantId         = $TenantId
        DataverseUrl     = $DataverseUrl
        GracePeriodHours = $GracePeriodHours
    }

    if ($ClientId) { $envParams.ClientId = $ClientId }
    if ($CertificateThumbprint) { $envParams.CertificateThumbprint = $CertificateThumbprint }

    if ($ClientSecret) {
        # Convert plain text secret to SecureString
        $envParams.ClientSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    }

    if ($IncludeTrialDev) { $envParams.IncludeTrialDev = $true }
    if ($SkipDiscovery) { $envParams.SkipDiscovery = $true }

    Write-Verbose "Invoking Invoke-EnvironmentAuditValidation with parameters: $($envParams.Keys -join ', ')"

    # Execute environment validation orchestrator
    $validationResults = & "$scriptRoot\Invoke-EnvironmentAuditValidation.ps1" @envParams

    Write-Verbose "Validation complete. Total environments: $($validationResults.TotalEnvironments)"
    Write-Verbose "Overall status: $($validationResults.OverallStatus)"

    # Acquire Dataverse token for drift detection
    Write-Verbose "Acquiring Dataverse token for drift detection"

    # Import MSAL.PS module
    Import-Module MSAL.PS -ErrorAction Stop

    # Acquire token based on authentication method
    $dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"

    if ($CertificateThumbprint) {
        # Certificate authentication
        $cert = Get-Item "Cert:\*\$CertificateThumbprint" -ErrorAction Stop
        Write-Verbose "Certificate found: $($cert.Subject)"

        $tokenResult = Get-MsalToken `
            -ClientId $ClientId `
            -ClientCertificate $cert `
            -TenantId $TenantId `
            -Scopes $dataverseScope `
            -ErrorAction Stop
    }
    elseif ($ClientSecret) {
        # Client secret authentication
        $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force

        $tokenResult = Get-MsalToken `
            -ClientId $ClientId `
            -ClientSecret $secureSecret `
            -TenantId $TenantId `
            -Scopes $dataverseScope `
            -ErrorAction Stop
    }
    else {
        throw "Either CertificateThumbprint or ClientSecret must be provided for authentication."
    }

    $dataverseToken = $tokenResult.AccessToken
    Write-Verbose "Dataverse token acquired"

    # Run drift detection for each environment
    Write-Verbose "Running per-environment drift detection"

    foreach ($envResult in $validationResults.PerEnvironmentResults) {
        $envId = $envResult.EnvironmentId
        $envStatus = $envResult.OverallStatus

        Write-Verbose "Drift detection for $($envResult.EnvironmentName): $envStatus"

        try {
            $envDrift = Compare-ValidationBaseline `
                -DataverseUrl $DataverseUrl `
                -DataverseToken $dataverseToken `
                -Scope "Environment" `
                -CurrentStatus $envStatus `
                -EnvironmentId $envId `
                -ValidationType "Orchestrator"

            # Add drift info to environment result
            $envResult | Add-Member -NotePropertyName "Drift" -NotePropertyValue $envDrift -Force

            # Add alert flag (drift detected AND status is not Passed)
            $alertRequired = ($envDrift.DriftDetected -and $envStatus -ne "Passed")
            $envResult | Add-Member -NotePropertyName "AlertRequired" -NotePropertyValue $alertRequired -Force

            Write-Verbose "  Drift detected: $($envDrift.DriftDetected), Alert required: $alertRequired"
        }
        catch {
            Write-Warning "Drift detection failed for $($envResult.EnvironmentName): $($_.Exception.Message)"

            # On error, fail open (set alert required)
            $envResult | Add-Member -NotePropertyName "Drift" -NotePropertyValue $null -Force
            $envResult | Add-Member -NotePropertyName "AlertRequired" -NotePropertyValue $true -Force
        }
    }

    # Build output object with drift info and aggregated alerts
    $output = [PSCustomObject]@{
        RunType                 = "EnvironmentValidation"
        RunId                   = $validationResults.RunId
        Timestamp               = $validationResults.Timestamp
        TotalEnvironments       = $validationResults.TotalEnvironments
        OverallStatus           = $validationResults.OverallStatus
        PerEnvironmentResults   = $validationResults.PerEnvironmentResults
        NewEnvironments         = $validationResults.NewEnvironments
        SkippedUnclassified     = $validationResults.SkippedUnclassified
        SkippedTrialDev         = $validationResults.SkippedTrialDev
        AlertsRequired          = @($validationResults.PerEnvironmentResults | Where-Object { $_.AlertRequired })
    }

    Write-Verbose "Alerts required for $($output.AlertsRequired.Count) environment(s)"

    # Convert to JSON and output to pipeline
    # This is the ONLY Write-Output - Azure Automation captures this as job output
    $jsonOutput = $output | ConvertTo-Json -Depth 10
    Write-Verbose "JSON output length: $($jsonOutput.Length) characters"

    # Output to pipeline (no Write-Host - not retrievable by Power Automate)
    $jsonOutput
}
catch {
    # On error, output structured error JSON
    Write-Verbose "Error occurred: $($_.Exception.Message)"

    $errorOutput = [PSCustomObject]@{
        RunType       = "EnvironmentValidation"
        Timestamp     = (Get-Date -AsUTC -Format "o")
        OverallStatus = "Error"
        Reason        = $_.Exception.Message
        AlertsRequired = @()
    }

    $errorOutput | ConvertTo-Json -Depth 5
}
