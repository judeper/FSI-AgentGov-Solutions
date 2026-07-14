#Requires -Version 7.2

<#
.SYNOPSIS
    Compares current validation severity against last known good baseline from Dataverse history.

.DESCRIPTION
    Queries the fsi_auditvalidationhistory table for the most recent Passed (severity=1)
    validation result matching the specified scope and type. Compares the current validation
    severity against the baseline to determine if drift (regression) has occurred.

    Drift detection logic:
    - If no baseline exists (first run), any non-Passed result is drift
    - If current severity > baseline severity (numerically), drift detected
    - If current severity <= baseline severity, no drift

    This function supports automated alerting by providing a boolean DriftDetected flag
    that downstream systems (Power Automate) can use to route alert notifications.

    Severity values (higher = worse):
    - Passed = 1
    - Warning = 2
    - GracePeriod = 3
    - Failed = 4
    - Error = 5

.PARAMETER DataverseUrl
    Dataverse organization URL where validation history is stored.
    Example: https://governance.crm.dynamics.com

.PARAMETER DataverseToken
    Bearer token for Dataverse Web API authentication.

.PARAMETER Scope
    Validation scope: "Tenant" or "Environment".

.PARAMETER CurrentStatus
    Current validation status to compare against baseline.
    Valid values: Passed, Warning, GracePeriod, Failed, Error

.PARAMETER ValidationType
    Type of validation (optional filter for baseline query).
    Examples: UnifiedAuditLog, MailboxAudit, PurviewRetention, EnvironmentAudit, Orchestrator

.PARAMETER EnvironmentId
    Power Platform environment GUID. Required when Scope is "Environment".

.PARAMETER CurrentRunId
    Optional current validation run GUID. When provided, the baseline query excludes
    records with this run ID to avoid selecting the current in-flight run as baseline.

.EXAMPLE
    $drift = Compare-ValidationBaseline `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -DataverseToken $token `
        -Scope "Tenant" `
        -CurrentStatus "Failed" `
        -ValidationType "UnifiedAuditLog"

    Compares current UnifiedAuditLog validation status against last Passed baseline.
    Returns object with DriftDetected=$true if Failed represents a regression.

.EXAMPLE
    $drift = Compare-ValidationBaseline `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -DataverseToken $token `
        -Scope "Environment" `
        -CurrentStatus "Passed" `
        -EnvironmentId "12345-guid-67890"

    Compares current environment validation status against baseline.
    Returns object with DriftDetected=$false if status is same or better.

.OUTPUTS
    PSCustomObject with properties:
    - DriftDetected: Boolean indicating if current severity is worse than baseline
    - CurrentStatus: Current validation status string
    - CurrentSeverity: Current severity numeric value (1-5)
    - BaselineStatus: Last known good status string (or $null if first run)
    - BaselineSeverity: Last known good severity numeric value (or $null if first run)
    - BaselineDate: ISO 8601 timestamp of baseline record (or $null if first run)
    - IsFirstRun: Boolean indicating if no baseline exists

.NOTES
    Version: 1.0.3

    Dataverse schema reference:
    - Table: fsi_auditvalidationhistory
    - Severity field: fsi_severity (option set)
    - Scope field: fsi_scope (option set: Tenant=100000000, Environment=100000001)
    - ValidationType field: fsi_validationtype (text)
    - EnvironmentId field: fsi_environmentid (text)

    On error, this function fails open (returns DriftDetected=$true) to avoid
    silently suppressing alerts when baseline query fails.
#>

[CmdletBinding()]
param(
    # Optional at script scope to support safe dot-sourcing; required by Compare-ValidationBaseline function and direct execution guard.
    [Parameter(Mandatory = $false)]
    [string]$DataverseUrl,

    # Optional at script scope to support safe dot-sourcing; required by Compare-ValidationBaseline function and direct execution guard.
    [Parameter(Mandatory = $false)]
    [string]$DataverseToken,

    # Optional at script scope to support safe dot-sourcing; required by Compare-ValidationBaseline function and direct execution guard.
    [Parameter(Mandatory = $false)]
    [ValidateSet("Tenant", "Environment")]
    [string]$Scope,

    # Optional at script scope to support safe dot-sourcing; required by Compare-ValidationBaseline function and direct execution guard.
    [Parameter(Mandatory = $false)]
    [ValidateSet("Passed", "Warning", "GracePeriod", "Failed", "Error")]
    [string]$CurrentStatus,

    [Parameter(Mandatory = $false)]
    [string]$ValidationType,

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $false)]
    [string]$CurrentRunId
)

$ErrorActionPreference = "Stop"

function Compare-ValidationBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataverseUrl,

        [Parameter(Mandatory = $true)]
        [string]$DataverseToken,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Tenant", "Environment")]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Passed", "Warning", "GracePeriod", "Failed", "Error")]
        [string]$CurrentStatus,

        [Parameter(Mandatory = $false)]
        [string]$ValidationType,

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentId,

        [Parameter(Mandatory = $false)]
        [string]$CurrentRunId
    )

    try {
        # Normalize Dataverse URL
        $DataverseUrl = $DataverseUrl.TrimEnd('/')

        # Map status strings to severity values (higher = worse)
        $severityMap = @{
            "Passed"      = 100000000
            "Warning"     = 100000001
            "GracePeriod" = 100000002
            "Failed"      = 100000003
            "Error"       = 100000004
        }

        $scopeMap = @{
            "Tenant"      = 100000000
            "Environment" = 100000001
        }

        $currentSeverity = $severityMap[$CurrentStatus]
        $scopeValue = $scopeMap[$Scope]

        # Build OData filter for baseline query
        # Find most recent Passed (severity=100000000) validation for this scope
        $filter = "fsi_scope eq $scopeValue and fsi_severity eq 100000000"

        if ($Scope -eq "Environment") {
            if (-not $EnvironmentId) {
                throw "EnvironmentId is required when Scope is 'Environment'."
            }
            $filter += " and fsi_environmentid eq '$EnvironmentId'"

            # For environment scope, typically we want Orchestrator type for overall status
            # Or we can filter by specific ValidationType if provided
            if ($ValidationType) {
                $filter += " and fsi_validationtype eq '$ValidationType'"
            }
            else {
                # Default to Orchestrator for environment-level drift detection
                $filter += " and fsi_validationtype eq 'Orchestrator'"
            }
        }
        elseif ($ValidationType) {
            # For tenant scope, filter by ValidationType if provided
            $filter += " and fsi_validationtype eq '$ValidationType'"
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentRunId)) {
            $escapedCurrentRunId = $CurrentRunId.Replace("'", "''")
            $filter += " and fsi_runid ne '$escapedCurrentRunId'"
        }

        # Construct API URL with OData query
        $apiUrl = "$DataverseUrl/api/data/v9.2/fsi_auditvalidationhistories"
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
        $isFirstRun = $null -eq $baseline

        if ($isFirstRun) {
            # No baseline exists - this is first run
            # Any non-Passed result is drift (alert should fire)
            Write-Verbose "No baseline found (first run). Current: $CurrentStatus"

            return [PSCustomObject]@{
                DriftDetected     = ($CurrentStatus -ne "Passed")
                CurrentStatus     = $CurrentStatus
                CurrentSeverity   = $currentSeverity
                BaselineStatus    = $null
                BaselineSeverity  = $null
                BaselineDate      = $null
                IsFirstRun        = $true
            }
        }
        else {
            # Baseline exists - compare severities
            $baselineSeverity = $baseline.fsi_severity
            $baselineDate = if ($baseline.fsi_timestamp) {
                $baseline.fsi_timestamp
            }
            elseif ($baseline.createdon) {
                $baseline.createdon
            }
            else {
                $null
            }

            # Map baseline severity back to status string
            $reverseSeverityMap = @{
                100000000 = "Passed"
                100000001 = "Warning"
                100000002 = "GracePeriod"
                100000003 = "Failed"
                100000004 = "Error"
            }
            $baselineStatus = $reverseSeverityMap[$baselineSeverity]

            # Drift detected if current severity is worse (higher number) than baseline
            $driftDetected = $currentSeverity -gt $baselineSeverity

            Write-Verbose "Baseline found: $baselineStatus (severity=$baselineSeverity) at $baselineDate"
            Write-Verbose "Current: $CurrentStatus (severity=$currentSeverity)"
            Write-Verbose "Drift detected: $driftDetected"

            return [PSCustomObject]@{
                DriftDetected     = $driftDetected
                CurrentStatus     = $CurrentStatus
                CurrentSeverity   = $currentSeverity
                BaselineStatus    = $baselineStatus
                BaselineSeverity  = $baselineSeverity
                BaselineDate      = $baselineDate
                IsFirstRun        = $false
            }
        }
    }
    catch {
        # On error, fail open - return drift detected to avoid suppressing alerts
        $errorMsg = $_.Exception.Message
        Write-Warning "Baseline comparison failed: $errorMsg. Failing open (DriftDetected=true)."

        return [PSCustomObject]@{
            DriftDetected     = $true
            CurrentStatus     = $CurrentStatus
            CurrentSeverity   = $severityMap[$CurrentStatus]
            BaselineStatus    = $null
            BaselineSeverity  = $null
            BaselineDate      = $null
            IsFirstRun        = $null
            Error             = $errorMsg
        }
    }
}

# Execute function if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $missingDirectParams = @()
    if ([string]::IsNullOrWhiteSpace($DataverseUrl)) { $missingDirectParams += 'DataverseUrl' }
    if ([string]::IsNullOrWhiteSpace($DataverseToken)) { $missingDirectParams += 'DataverseToken' }
    if ([string]::IsNullOrWhiteSpace($Scope)) { $missingDirectParams += 'Scope' }
    if ([string]::IsNullOrWhiteSpace($CurrentStatus)) { $missingDirectParams += 'CurrentStatus' }

    if ($missingDirectParams.Count -gt 0) {
        throw "Missing required parameter(s) for direct invocation: $($missingDirectParams -join ', '). Dot-source this helper to load the Compare-ValidationBaseline function, or pass the required parameters when invoking the script directly."
    }

    $result = Compare-ValidationBaseline @PSBoundParameters
    return $result
}

# Note: This script is dot-sourced; do not use Export-ModuleMember outside a .psm1 module.
