#Requires -Version 7.2
#Requires -Modules @{ ModuleName="ExchangeOnlineManagement"; ModuleVersion="3.0.0"; MaximumVersion="3.9.2" }, Az.Accounts

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

    Auth-mode asymmetry vs. Start-EnvironmentValidationRunbook.ps1 (intentional):
    This tenant runbook requires certificate-based service-principal authentication
    only. It does NOT provide a client-secret fallback. The companion environment
    runbook accepts a -ClientSecret parameter as a "legacy dev-only" fallback per
    the AGENTS.md managed-identity-first auth standard. The asymmetry is
    deliberate: tenant-level operations (Unified Audit Log enable/disable,
    Exchange Online Set-AdminAuditLogConfig) impact every workload in the tenant
    and warrant the stronger credential. Environment-level operations are
    scoped to a single Power Platform environment and operators may legitimately
    need a client-secret path during early proof-of-concept testing before a
    certificate is in place. Production deployments for both runbooks must use
    certificate or Managed Identity authentication.

    Output structure enables Power Automate HTTP webhook actions to parse validation
    results and route alerts based on severity and drift status.

.PARAMETER Zone
    Governance zone to validate against.
    Valid values: Zone1, Zone2, Zone3

.PARAMETER DataverseUrl
    Central Dataverse organization URL where validation history is stored.
    Example: https://governance.crm.dynamics.com

.PARAMETER TenantId
    Microsoft Entra ID tenant ID for authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for certificate-based authentication.

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
    Version: 1.0.2

    Azure Automation setup:
    1. Import this script as a runbook
    2. Upload certificate to Automation Account > Certificates
    3. Install required modules: ExchangeOnlineManagement (3.0.0-3.9.2), Az.Accounts
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

    $dotSourceSafeVars = @{
        Zone                  = $Zone
        DataverseUrl          = $DataverseUrl
        TenantId              = $TenantId
        ClientId              = $ClientId
        CertificateThumbprint = $CertificateThumbprint
        SkipCanaryValidation  = $SkipCanaryValidation
        CanaryWaitSeconds     = $CanaryWaitSeconds
    }

    $privatePath = Join-Path $PSScriptRoot 'private'
    $requiredHelpers = @(
        'Compare-ValidationBaseline.ps1'
        'Connect-PowerPlatform.ps1'
    )
    foreach ($helper in $requiredHelpers) {
        $helperPath = Join-Path $privatePath $helper
        if (-not (Test-Path $helperPath)) {
            throw "Required helper script not found: $helperPath. Ensure the solution is installed correctly."
        }
        . $helperPath
    }
    foreach ($name in $dotSourceSafeVars.Keys) {
        Set-Variable -Name $name -Value $dotSourceSafeVars[$name] -Scope Local
    }

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
    Write-Verbose "Acquiring Dataverse token for drift detection via Connect-PowerPlatform"

    if (-not $TenantId -or -not $ClientId -or -not $CertificateThumbprint) {
        throw "TenantId, ClientId, and CertificateThumbprint are required for Dataverse drift detection in this runbook."
    }

    $authResult = Connect-PowerPlatform `
        -TenantId $TenantId `
        -DataverseUrl $DataverseUrl `
        -ClientId $ClientId `
        -CertificateThumbprint $CertificateThumbprint

    $dataverseToken = $authResult.DataverseAccessToken
    if (-not $dataverseToken) {
        throw "Failed to acquire Dataverse access token for drift detection."
    }
    Write-Verbose "Dataverse token acquired"

    # Run overall drift detection
    Write-Verbose "Running drift detection for overall status"
    $overallDrift = Compare-ValidationBaseline `
        -DataverseUrl $DataverseUrl `
        -DataverseToken $dataverseToken `
        -Scope "Tenant" `
        -CurrentStatus $validationResults.OverallStatus `
        -CurrentRunId $validationResults.RunId

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
                -CurrentRunId $validationResults.RunId `
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
