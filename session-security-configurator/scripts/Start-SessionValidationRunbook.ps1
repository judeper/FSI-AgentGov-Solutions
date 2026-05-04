#Requires -Version 7.1
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
    Microsoft Entra ID tenant ID for authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for certificate-based authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication. Certificate must be
    uploaded to the Azure Automation account.

.PARAMETER ConfigPath
    Path to tenant configuration JSON file with breakGlassAccounts array.

.PARAMETER SkipPimValidation
    Skip PIM role settings validation. Returns result without PIM checks when
    account lacks RoleManagement.Read.Directory permission.

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
    3. Install required modules: Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Groups, Microsoft.Graph.Identity.Governance, MSAL.PS
    4. Grant application permissions:
       - Policy.Read.All (for CA policies)
       - GroupMember.Read.All (for break-glass group membership resolution)
       - RoleManagement.Read.Directory (optional, for PIM validation)
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

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    Write-Verbose "Starting session validation runbook"
    Write-Verbose "Zone: $Zone"
    Write-Verbose "DataverseUrl: $DataverseUrl"
    Write-Verbose "ConfigPath: $ConfigPath"

    # Resolve script path (do NOT dot-source — it is a standalone script, not a function)
    $scriptRoot = $PSScriptRoot
    Write-Verbose "Script root: $scriptRoot"

    $complianceScript = "$scriptRoot\Test-SessionCompliance.ps1"
    if (-not (Test-Path $complianceScript)) {
        throw "Test-SessionCompliance.ps1 not found at: $complianceScript"
    }

    Write-Verbose "Compliance script resolved: $complianceScript"

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

    # Execute session validation orchestrator via call operator (not dot-source)
    $validationResults = & $complianceScript @validationParams

    Write-Verbose "Validation complete. Overall status: $($validationResults.OverallStatus)"

    # Acquire Dataverse token for drift detection
    Write-Verbose "Acquiring Dataverse token for drift detection"

    # Import MSAL.PS module
    Import-Module MSAL.PS -ErrorAction Stop

    # Get certificate for authentication
    $cert = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction Stop
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
            [string]$CurrentStatus,

            [Parameter(Mandatory = $true)]
            [ValidateSet("Zone1", "Zone2", "Zone3")]
            [string]$Zone
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

            # Build OData filter for active baseline query
            # Drift detection compares the current run against the active SessionBaseline for this zone
            # (recorded by Invoke-BaselineCapture.ps1). fsi_sessionbaselines is the canonical source of
            # truth for "known good"; fsi_validationhistories captures point-in-time runs only.
            $zoneMap = @{ 'Zone1' = 100000001; 'Zone2' = 100000002; 'Zone3' = 100000003 }
            $zoneVal = $zoneMap[$Zone]
            $filter = "fsi_zone eq $zoneVal and fsi_isactive eq true"

            # Construct API URL with OData query
            $apiUrl = "$DataverseUrl/api/data/v9.2/fsi_sessionbaselines"
            $apiUrl += "?`$filter=$filter"
            $apiUrl += "&`$orderby=fsi_capturedon desc"
            $apiUrl += "&`$top=1"
            $apiUrl += "&`$select=fsi_name,fsi_signinfrequencyminutes,fsi_authstrength,fsi_requirecompliantdevice,fsi_capturedon"

            Write-Verbose "Querying active baseline: $apiUrl"

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
                # No active baseline exists - this is first run
                # Any non-Passed result is treated as drift so it surfaces for investigation
                Write-Verbose "No active SessionBaseline found for $Zone (first run). Current: $CurrentStatus"

                return [PSCustomObject]@{
                    DriftDetected  = ($CurrentStatus -ne "Passed")
                    Status         = "OK"
                    CurrentStatus  = $CurrentStatus
                    BaselineStatus = $null
                    BaselineDate   = $null
                    IsFirstRun     = $true
                }
            }

            # Active baseline exists - drift is signalled when current severity is worse than Passed,
            # i.e. the live config diverged from the captured baseline. Per-property comparison is
            # already performed by Compare-SessionBaseline; here we only summarize for routing.
            $baselineDate = if ($baseline.fsi_capturedon) { $baseline.fsi_capturedon } else { $null }
            $driftDetected = $currentSeverity -gt 1  # 1 = Passed

            Write-Verbose "Active baseline: $($baseline.fsi_name) captured $baselineDate"
            Write-Verbose "Current: $CurrentStatus (severity=$currentSeverity); Drift detected: $driftDetected"

            return [PSCustomObject]@{
                DriftDetected  = $driftDetected
                Status         = "OK"
                CurrentStatus  = $CurrentStatus
                BaselineStatus = "Passed"
                BaselineName   = $baseline.fsi_name
                BaselineDate   = $baselineDate
                IsFirstRun     = $false
            }
        }
        catch {
            # Fail-closed for alerting: surface a Dataverse error as drift so the alert path still
            # fires, but tag Status='Error' so downstream Power Automate routing can distinguish
            # infrastructure errors from genuine drift.
            $errorMsg = $_.Exception.Message
            Write-Verbose "Baseline comparison failed: $errorMsg. Returning DriftDetected=true with Status='Error'."

            return [PSCustomObject]@{
                DriftDetected  = $true
                Status         = "Error"
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
        -CurrentStatus $validationResults.OverallStatus `
        -Zone $Zone

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
        Validators    = @{
            SessionControls        = @{ Status = "Error"; Reason = "Runbook execution failed" }
            AuthenticationStrength = @{ Status = "Error"; Reason = "Runbook execution failed" }
            PimRoleSettings        = @{ Status = "Error"; Reason = "Runbook execution failed" }
            BreakGlassExclusions   = @{ Status = "Error"; Reason = "Runbook execution failed" }
        }
        Drift         = @{
            DriftDetected  = $true
            CurrentStatus  = "Error"
            BaselineStatus = $null
            BaselineDate   = $null
            IsFirstRun     = $null
            Error          = $_.Exception.Message
        }
        AlertRequired = $true
        AlertSeverity = "Error"
    }

    $errorOutput | ConvertTo-Json -Depth 5
}
