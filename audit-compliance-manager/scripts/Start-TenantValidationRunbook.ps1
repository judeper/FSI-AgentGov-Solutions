#Requires -Version 7.0
#Requires -Modules @{ ModuleName="ExchangeOnlineManagement"; ModuleVersion="3.0.0" }, @{ ModuleName="MSAL.PS"; ModuleVersion="4.37.0" }

<#
.SYNOPSIS
    Azure Automation runbook wrapper for tenant-level audit configuration validation.

.DESCRIPTION
    Adapts Invoke-TenantAuditValidation.ps1 for Azure Automation execution context.
    This runbook provides non-interactive authentication, structured JSON output to
    the pipeline, and drift detection logic for downstream alerting.

    Key differences from interactive orchestrator:
    - Uses certificate-based authentication (no interactive prompts)
    - Outputs JSON to pipeline (captured by Get-AzAutomationJobOutput)
    - Includes drift detection via Compare-ValidationBaseline
    - Adds AlertRequired flag for Power Automate flow routing
    - No Write-Host (uses Write-Verbose for diagnostics)

    Output structure enables Power Automate HTTP webhook actions to parse validation
    results and route alerts based on severity and drift status.

.PARAMETER Zone
    Governance zone to validate against.
    Valid values: Zone1, Zone2, Zone3

.PARAMETER DataverseUrl
    Central Dataverse organization URL where validation history is stored.
    Example: https://governance.crm.dynamics.com

.PARAMETER TenantId
    Azure AD tenant ID for authentication.

.PARAMETER ClientId
    Azure AD application (client) ID for certificate-based authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication. Certificate must be
    uploaded to the Azure Automation account.

.PARAMETER SkipCanaryValidation
    Skip canary event validation in Unified Audit Log testing. Returns medium-confidence
    result based only on cmdlet status checks.

.PARAMETER CanaryWaitSeconds
    Seconds to wait after generating canary event before searching for it. Default: 300.

.EXAMPLE
    Start-TenantValidationRunbook `
        -Zone "Zone3" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456"

    Runs tenant validation for Zone3 using certificate authentication.
    Outputs JSON to pipeline for Power Automate consumption.

.OUTPUTS
    JSON object with properties:
    - RunType: "TenantValidation"
    - Timestamp: ISO 8601 UTC timestamp
    - Zone: Zone1 | Zone2 | Zone3
    - OverallStatus: Passed | Warning | GracePeriod | Failed | Error
    - Reason: Summary explanation
    - Validators: Hashtable with UnifiedAuditLog, MailboxAudit, PurviewRetention results
    - Drift: Object with drift detection results
    - AlertRequired: Boolean flag for flow routing
    - AlertSeverity: Status value for alert priority

.NOTES
    Version: 1.0.0

    Azure Automation setup:
    1. Import this script as a runbook
    2. Upload certificate to Automation Account > Certificates
    3. Install required modules: ExchangeOnlineManagement, MSAL.PS
    4. Grant application permissions:
       - Exchange.ManageAsApp
       - SecurityEvents.Read.All (for Purview)
    5. Schedule via Schedules or trigger via webhook

    Performance:
    - Full validation (with canary): 5-10 minutes
    - Without canary: 1-2 minutes

    This script is designed to run as an Azure Automation runbook. Import into
    Azure Automation Account and configure with certificate-based authentication.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Zone1", "Zone2", "Zone3")]
    [string]$Zone,

    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCanaryValidation,

    [Parameter(Mandatory = $false)]
    [int]$CanaryWaitSeconds = 300
)

$ErrorActionPreference = "Stop"

try {
    Write-Verbose "Starting tenant validation runbook"
    Write-Verbose "Zone: $Zone"
    Write-Verbose "DataverseUrl: $DataverseUrl"

    # Dot-source required scripts from same directory
    $scriptRoot = $PSScriptRoot
    Write-Verbose "Script root: $scriptRoot"

    . "$scriptRoot\private\Compare-ValidationBaseline.ps1"

    Write-Verbose "Scripts loaded successfully"

    # Build parameters for Invoke-TenantAuditValidation
    # Do NOT pass -Interactive or -OutputPath (not suitable for runbook context)
    $ualParams = @{
        Zone = $Zone
    }

    if ($TenantId) { $ualParams.TenantId = $TenantId }
    if ($ClientId) { $ualParams.ClientId = $ClientId }
    if ($CertificateThumbprint) { $ualParams.CertificateThumbprint = $CertificateThumbprint }
    if ($SkipCanaryValidation) { $ualParams.SkipCanaryValidation = $true }
    if ($CanaryWaitSeconds) { $ualParams.CanaryWaitSeconds = $CanaryWaitSeconds }

    Write-Verbose "Invoking Invoke-TenantAuditValidation with parameters: $($ualParams.Keys -join ', ')"

    # Execute tenant validation orchestrator
    $validationResults = & "$scriptRoot\Invoke-TenantAuditValidation.ps1" @ualParams

    Write-Verbose "Validation complete. Overall status: $($validationResults.OverallStatus)"

    # Acquire Dataverse token for drift detection
    Write-Verbose "Acquiring Dataverse token for drift detection"

    # Import MSAL.PS module
    Import-Module MSAL.PS -ErrorAction Stop

    # Get certificate for authentication
    $cert = Get-Item "Cert:\*\$CertificateThumbprint" -ErrorAction Stop
    Write-Verbose "Certificate found: $($cert.Subject)"

    # Acquire token
    $dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"
    $tokenResult = Get-MsalToken `
        -ClientId $ClientId `
        -ClientCertificate $cert `
        -TenantId $TenantId `
        -Scopes $dataverseScope `
        -ErrorAction Stop

    $dataverseToken = $tokenResult.AccessToken
    Write-Verbose "Dataverse token acquired"

    # Run overall drift detection
    Write-Verbose "Running drift detection for overall status"
    $overallDrift = Compare-ValidationBaseline `
        -DataverseUrl $DataverseUrl `
        -DataverseToken $dataverseToken `
        -Scope "Tenant" `
        -CurrentStatus $validationResults.OverallStatus

    Write-Verbose "Overall drift detected: $($overallDrift.DriftDetected)"

    # Run per-validator drift detection
    $perValidatorDrift = @{}

    foreach ($validatorName in @("UnifiedAuditLog", "MailboxAudit", "PurviewRetention")) {
        if ($validationResults.Validators.ContainsKey($validatorName)) {
            $validator = $validationResults.Validators[$validatorName]
            $validatorStatus = if ($validator.OverallStatus) {
                $validator.OverallStatus
            }
            elseif ($validator.Status) {
                $validator.Status
            }
            else {
                "Unknown"
            }

            Write-Verbose "Running drift detection for $validatorName (status: $validatorStatus)"

            $validatorDrift = Compare-ValidationBaseline `
                -DataverseUrl $DataverseUrl `
                -DataverseToken $dataverseToken `
                -Scope "Tenant" `
                -CurrentStatus $validatorStatus `
                -ValidationType $validatorName

            $perValidatorDrift[$validatorName] = $validatorDrift
            Write-Verbose "$validatorName drift detected: $($validatorDrift.DriftDetected)"
        }
    }

    # Build output object with drift info and alert flags
    $output = [PSCustomObject]@{
        RunType           = "TenantValidation"
        Timestamp         = $validationResults.Timestamp
        Zone              = $validationResults.Zone
        OverallStatus     = $validationResults.OverallStatus
        Reason            = $validationResults.Reason
        Validators        = $validationResults.Validators
        Drift             = @{
            Overall       = $overallDrift
            PerValidator  = $perValidatorDrift
        }
        AlertRequired     = ($overallDrift.DriftDetected -and $validationResults.OverallStatus -ne "Passed")
        AlertSeverity     = $validationResults.OverallStatus
    }

    Write-Verbose "Alert required: $($output.AlertRequired)"
    Write-Verbose "Alert severity: $($output.AlertSeverity)"

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
        RunType       = "TenantValidation"
        Timestamp     = (Get-Date -AsUTC -Format "o")
        OverallStatus = "Error"
        Reason        = $_.Exception.Message
        AlertRequired = $true
        AlertSeverity = "Error"
    }

    $errorOutput | ConvertTo-Json -Depth 5
}
