#Requires -Version 7.0
#Requires -Modules @{ ModuleName="Microsoft.Graph.Identity.SignIns"; ModuleVersion="2.0.0" }, @{ ModuleName="MSAL.PS"; ModuleVersion="4.37.0" }

<#
.SYNOPSIS
    Azure Automation runbook wrapper for session security configuration validation.

.DESCRIPTION
    Adapts Test-SessionCompliance.ps1 for Azure Automation execution context.
    This runbook provides non-interactive authentication, structured JSON output to
    the pipeline, and drift detection logic for downstream alerting.

    Key differences from interactive orchestrator:
    - Uses certificate-based authentication (no interactive prompts)
    - Outputs JSON to pipeline (captured by Get-AzAutomationJobOutput)
    - Includes drift detection via Dataverse ValidationHistory query
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

.PARAMETER ConfigPath
    Path to tenant configuration JSON file with breakGlassAccounts array.

.PARAMETER SkipPimValidation
    Skip PIM role settings validation. Returns result without PIM checks when
    account lacks RoleManagement.Read.All permission.

.EXAMPLE
    Start-SessionValidationRunbook `
        -Zone "Zone3" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -ConfigPath "D:\RunbookAssets\tenant-config.json"

    Runs session validation for Zone3 using certificate authentication.
    Outputs JSON to pipeline for Power Automate consumption.

.OUTPUTS
    JSON object with properties:
    - RunType: "SessionValidation"
    - Timestamp: ISO 8601 UTC timestamp
    - Zone: Zone1 | Zone2 | Zone3
    - OverallStatus: Passed | Warning | Failed | Error
    - Reason: Summary explanation
    - Validators: Hashtable with SessionControls, AuthenticationStrength, PimRoleSettings, BreakGlassExclusions results
    - Drift: Object with drift detection results
    - AlertRequired: Boolean flag for flow routing
    - AlertSeverity: Status value for alert priority

.NOTES
    Version: 1.0.0

    Azure Automation setup:
    1. Import this script as a runbook
    2. Upload certificate to Automation Account > Certificates
    3. Install required modules: Microsoft.Graph.Identity.SignIns, MSAL.PS
    4. Grant application permissions:
       - Policy.Read.All (for CA policies)
       - RoleManagement.Read.All (optional, for PIM validation)
    5. Schedule via Schedules or trigger via webhook

    Performance:
    - Full validation (with PIM): 2-5 minutes
    - Without PIM (-SkipPimValidation): 30-60 seconds

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

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPimValidation
)

$ErrorActionPreference = "Stop"

try {
    Write-Verbose "Starting session validation runbook"
    Write-Verbose "Zone: $Zone"
    Write-Verbose "DataverseUrl: $DataverseUrl"
    Write-Verbose "ConfigPath: $ConfigPath"

    # Resolve script root for sibling script invocation
    $scriptRoot = $PSScriptRoot
    Write-Verbose "Script root: $scriptRoot"

    # Build parameters for Test-SessionCompliance
    # Do NOT pass -Interactive or -OutputPath (not suitable for runbook context)
    $validationParams = @{
        Zone                  = $Zone
        ConfigPath            = $ConfigPath
        TenantId              = $TenantId
        ClientId              = $ClientId
        CertificateThumbprint = $CertificateThumbprint
        DataverseUrl          = $DataverseUrl
    }

    if ($SkipPimValidation) {
        $validationParams.SkipPimValidation = $true
    }

    Write-Verbose "Invoking Test-SessionCompliance with parameters: $($validationParams.Keys -join ', ')"

    # Execute session validation orchestrator (invoke as script, not function)
    $validationResults = & "$scriptRoot\Test-SessionCompliance.ps1" @validationParams

    Write-Verbose "Validation complete. Overall status: $($validationResults.OverallStatus)"

    # Acquire Dataverse token for drift detection
    Write-Verbose "Acquiring Dataverse token for drift detection"

    # Import MSAL.PS module
    Import-Module MSAL.PS -ErrorAction Stop

    # Get certificate for authentication
    $cert = Get-Item "Cert:\LocalMachine\My\$CertificateThumbprint" -ErrorAction Stop
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

    # Define inline drift detection function
    function Get-DriftStatus {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [string]$DataverseUrl,

            [Parameter(Mandatory = $true)]
            [string]$DataverseToken,

            [Parameter(Mandatory = $true)]
            [string]$CurrentStatus
        )

        try {
            # Normalize Dataverse URL
            $DataverseUrl = $DataverseUrl.TrimEnd('/')

            # Map status strings to severity values (higher = worse)
            $severityMap = @{
                "Passed"      = 1
                "Warning"     = 2
                "GracePeriod" = 3
                "Failed"      = 4
                "Error"       = 5
            }

            $currentSeverity = $severityMap[$CurrentStatus]

            # Build OData filter for baseline query
            # Find most recent Passed (severity=1) validation
            $filter = "fsi_severity eq 1"

            # Construct API URL with OData query
            $apiUrl = "$DataverseUrl/api/data/v9.2/fsi_validationhistories"
            $apiUrl += "?`$filter=$filter"
            $apiUrl += "&`$orderby=createdon desc"
            $apiUrl += "&`$top=1"
            $apiUrl += "&`$select=fsi_severity,fsi_timestamp,createdon"

            Write-Verbose "Querying baseline: $apiUrl"

            # Prepare headers
            $headers = @{
                "Authorization"    = "Bearer $DataverseToken"
                "Accept"           = "application/json"
                "OData-MaxVersion" = "4.0"
                "OData-Version"    = "4.0"
            }

            # Execute query
            $response = Invoke-RestMethod `
                -Uri $apiUrl `
                -Method Get `
                -Headers $headers `
                -ErrorAction Stop

            # Parse baseline result
            $baseline = $response.value | Select-Object -First 1

            if ($null -eq $baseline) {
                # No baseline exists - this is first run
                # Any non-Passed result is drift
                Write-Verbose "No baseline found (first run). Current: $CurrentStatus"

                return [PSCustomObject]@{
                    DriftDetected  = ($CurrentStatus -ne "Passed")
                    CurrentStatus  = $CurrentStatus
                    BaselineStatus = $null
                    BaselineDate   = $null
                    IsFirstRun     = $true
                }
            }

            # Baseline exists - compare severities
            $baselineSeverity = $baseline.fsi_severity

            # Map baseline severity back to status string
            $reverseSeverityMap = @{
                1 = "Passed"
                2 = "Warning"
                3 = "GracePeriod"
                4 = "Failed"
                5 = "Error"
            }
            $baselineStatus = $reverseSeverityMap[$baselineSeverity]

            $baselineDate = if ($baseline.fsi_timestamp) {
                $baseline.fsi_timestamp
            }
            elseif ($baseline.createdon) {
                $baseline.createdon
            }
            else {
                $null
            }

            # Drift detected if current severity is worse (higher number) than baseline
            $driftDetected = $currentSeverity -gt $baselineSeverity

            Write-Verbose "Baseline found: $baselineStatus (severity=$baselineSeverity) at $baselineDate"
            Write-Verbose "Current: $CurrentStatus (severity=$currentSeverity)"
            Write-Verbose "Drift detected: $driftDetected"

            return [PSCustomObject]@{
                DriftDetected  = $driftDetected
                CurrentStatus  = $CurrentStatus
                BaselineStatus = $baselineStatus
                BaselineDate   = $baselineDate
                IsFirstRun     = $false
            }
        }
        catch {
            # On error, fail open - return drift detected to avoid suppressing alerts
            $errorMsg = $_.Exception.Message
            Write-Verbose "Baseline comparison failed: $errorMsg. Failing open (DriftDetected=true)."

            return [PSCustomObject]@{
                DriftDetected  = $true
                CurrentStatus  = $CurrentStatus
                BaselineStatus = $null
                BaselineDate   = $null
                IsFirstRun     = $null
                Error          = $errorMsg
            }
        }
    }

    # Run drift detection
    Write-Verbose "Running drift detection for overall status"
    $drift = Get-DriftStatus `
        -DataverseUrl $DataverseUrl `
        -DataverseToken $dataverseToken `
        -CurrentStatus $validationResults.OverallStatus

    Write-Verbose "Drift detected: $($drift.DriftDetected)"

    # Build output object with drift info and alert flags
    $output = [PSCustomObject]@{
        RunType       = "SessionValidation"
        Timestamp     = (Get-Date -AsUTC -Format "o")
        Zone          = $Zone
        OverallStatus = $validationResults.OverallStatus
        Reason        = $validationResults.Reason
        Validators    = $validationResults.Validators
        Drift         = $drift
        AlertRequired = ($drift.DriftDetected -or $validationResults.OverallStatus -ne "Passed")
        AlertSeverity = $validationResults.OverallStatus
    }

    Write-Verbose "Alert required: $($output.AlertRequired)"
    Write-Verbose "Alert severity: $($output.AlertSeverity)"

    # Convert to JSON and output to pipeline
    # This is the ONLY output - Azure Automation captures this as job output
    $jsonOutput = $output | ConvertTo-Json -Depth 10
    Write-Verbose "JSON output length: $($jsonOutput.Length) characters"

    # Output to pipeline (no Write-Host - not retrievable by Power Automate)
    $jsonOutput
}
catch {
    # On error, output structured error JSON
    Write-Verbose "Error occurred: $($_.Exception.Message)"

    $errorOutput = [PSCustomObject]@{
        RunType       = "SessionValidation"
        Timestamp     = (Get-Date -AsUTC -Format "o")
        Zone          = $Zone
        OverallStatus = "Error"
        Reason        = $_.Exception.Message
        AlertRequired = $true
        AlertSeverity = "Error"
    }

    $errorOutput | ConvertTo-Json -Depth 5
}
