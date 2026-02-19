#Requires -Version 7.0

<#
.SYNOPSIS
    Queries Dataverse session security validation history for specified zone and date range.

.DESCRIPTION
    Retrieves validation result records from the fsi_validationhistories table
    via Dataverse Web API with OData filtering. Handles pagination automatically to
    ensure complete result sets for evidence export.

    Used by Export-SessionSecurityEvidence to retrieve historical validation data
    for compliance evidence packages supporting FINRA/SEC examination requirements.

    This helper is designed to fail gracefully. If Dataverse is unavailable or the
    table is not deployed, it throws an informative exception rather than returning
    partial data, ensuring evidence export integrity.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com). Required.

.PARAMETER AccessToken
    Bearer token for Dataverse Web API authentication. Optional.
    If omitted, attempts to extract token from current Microsoft Graph session
    via Get-MgContext.

    NOTE: The Dataverse Web API scope is different from Microsoft Graph scope.
    Callers should provide a Dataverse-scoped token when possible.

.PARAMETER Zone
    Governance zone filter. Valid values: 'All', '1', '2', '3'. Defaults to 'All'.
    - Zone 1 (Personal Productivity): Option set value 100000001
    - Zone 2 (Team Collaboration): Option set value 100000002
    - Zone 3 (Enterprise Managed): Option set value 100000003

.PARAMETER FromDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER ToDate
    End of date range filter (inclusive). Defaults to current timestamp.

.PARAMETER RunId
    Optional string to filter results to a specific validation run.

.EXAMPLE
    Get-SSCValidationResults `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -Zone "3" `
        -FromDate (Get-Date).AddDays(-90) `
        -ToDate (Get-Date)

    Retrieves all Zone 3 (Enterprise Managed) session security validation results
    from the past 90 days.

.EXAMPLE
    Get-SSCValidationResults `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -Zone "All" `
        -RunId "run-20260209-143022"

    Retrieves all validation results for a specific validation run across all zones.

.EXAMPLE
    # Using current Graph context token
    Connect-MgGraph -Scopes "https://contoso.crm.dynamics.com/.default"
    Get-SSCValidationResults -DataverseUrl "https://contoso.crm.dynamics.com" -Zone "2"

    Retrieves Zone 2 validation results from the past 30 days using current Graph context.

.OUTPUTS
    Array of PSCustomObjects containing validation result records. Each object
    includes fields: name, runId, zone, severity, validationType, rawValue,
    reason, remediationHint, checkCount, baselineId, timestamp.

.NOTES
    Version: 1.0.0

    This is a private helper function for internal use by Export-SessionSecurityEvidence.

    Option set mappings (must match Dataverse schema):
    - fsi_acv_zone: Zone1=100000001, Zone2=100000002, Zone3=100000003
    - fsi_acv_severity: Passed=1, Warning=2, GracePeriod=3, Failed=4, Error=5
    - fsi_ssc_validationtype: SessionControls=1, AuthStrength=2, PIMSettings=3,
                              BreakGlass=4, ConflictAudit=5, Orchestrator=6

    Query automatically handles pagination via @odata.nextLink to retrieve complete
    result sets (Dataverse default page size is 5000 records).

    Error handling:
    - 401: Authentication failed (token expired or invalid)
    - 404: Table not found (schema not deployed)
    - Other HTTP errors include full response details
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false)]
    [string]$AccessToken,

    [Parameter(Mandatory = $false)]
    [ValidateSet("All", "1", "2", "3")]
    [string]$Zone = "All",

    [Parameter(Mandatory = $false)]
    [datetime]$FromDate = (Get-Date).AddDays(-30),

    [Parameter(Mandatory = $false)]
    [datetime]$ToDate = (Get-Date),

    [Parameter(Mandatory = $false)]
    [string]$RunId
)

$ErrorActionPreference = "Stop"

function Get-SSCValidationResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataverseUrl,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [ValidateSet("All", "1", "2", "3")]
        [string]$Zone = "All",

        [Parameter(Mandatory = $false)]
        [datetime]$FromDate = (Get-Date).AddDays(-30),

        [Parameter(Mandatory = $false)]
        [datetime]$ToDate = (Get-Date),

        [Parameter(Mandatory = $false)]
        [string]$RunId
    )

    try {
        # Normalize Dataverse URL (remove trailing slash)
        $DataverseUrl = $DataverseUrl.TrimEnd('/')

        # Acquire access token if not provided
        $token = $null

        if ($AccessToken) {
            $token = $AccessToken
            Write-Verbose "Using provided access token for Dataverse authentication."
        }
        else {
            # Attempt to get token from current Graph context
            try {
                $context = Get-MgContext -ErrorAction SilentlyContinue
                if ($context) {
                    # Graph SDK v2 removed the AccessToken property from Get-MgContext
                    Write-Warning "Microsoft Graph SDK context found but cannot extract Dataverse token. Graph SDK v2 removed the AccessToken property. Provide a Dataverse-scoped token via -AccessToken parameter."
                }
            }
            catch {
                Write-Verbose "Failed to retrieve Graph context: $($_.Exception.Message)"
            }
        }

        if (-not $token) {
            throw "No access token available. Provide token via -AccessToken parameter or connect to Graph with Dataverse scope."
        }

        # Map zone to option set value
        $zoneMap = @{
            "1" = 100000001  # Zone 1 - Personal Productivity
            "2" = 100000002  # Zone 2 - Team Collaboration
            "3" = 100000003  # Zone 3 - Enterprise Managed
        }

        # Build OData filter components
        $filters = @()

        # Zone filter (if not 'All')
        if ($Zone -ne "All") {
            $zoneValue = $zoneMap[$Zone]
            $filters += "fsi_zone eq $zoneValue"
        }

        # Date range filters (convert to ISO 8601 UTC)
        $fromDateUtc = $FromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $toDateUtc = $ToDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $filters += "fsi_timestamp ge $fromDateUtc"
        $filters += "fsi_timestamp le $toDateUtc"

        # Optional RunId filter
        if ($RunId) {
            $filters += "fsi_runid eq '$RunId'"
        }

        # Combine filters with 'and'
        $filterString = if ($filters.Count -gt 0) { $filters -join ' and ' } else { $null }

        # Build full query URL with session security specific fields
        $selectFields = @(
            "fsi_name",
            "fsi_runid",
            "fsi_zone",
            "fsi_severity",
            "fsi_validationtype",
            "fsi_rawvalue",
            "fsi_reason",
            "fsi_remediationhint",
            "fsi_checkcount",
            "fsi_baselineid",
            "fsi_timestamp"
        ) -join ","

        $queryUrl = "$DataverseUrl/api/data/v9.2/fsi_validationhistories?`$orderby=fsi_timestamp desc&`$select=$selectFields"
        if ($filterString) {
            $queryUrl += "&`$filter=$filterString"
        }

        # Prepare headers
        $headers = @{
            "Authorization"    = "Bearer $token"
            "Accept"           = "application/json"
            "OData-MaxVersion" = "4.0"
            "OData-Version"    = "4.0"
        }

        # Execute query with pagination handling
        $allResults = @()
        $nextLink = $queryUrl

        Write-Verbose "Querying validation history: Zone=$Zone, FromDate=$fromDateUtc, ToDate=$toDateUtc"
        if ($RunId) {
            Write-Verbose "  RunId filter: $RunId"
        }

        while ($nextLink) {
            Write-Verbose "Fetching page: $nextLink"

            $response = Invoke-RestMethod `
                -Uri $nextLink `
                -Method Get `
                -Headers $headers `
                -ErrorAction Stop

            # Add results from this page
            if ($response.value) {
                $allResults += $response.value
                Write-Verbose "Retrieved $($response.value.Count) records (total: $($allResults.Count))"
            }

            # Check for next page
            $nextLink = $response.'@odata.nextLink'
        }

        Write-Verbose "Query complete. Total records retrieved: $($allResults.Count)"
        return $allResults
    }
    catch {
        $statusCode = $null
        $responseBody = $null

        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $responseBody = $_.ErrorDetails.Message
        }

        # Provide helpful error messages for common scenarios
        if ($statusCode -eq 401) {
            throw "Authentication failed. Access token may be expired or invalid. Status: 401"
        }
        elseif ($statusCode -eq 404) {
            throw "Session security validation history table (fsi_validationhistories) not found. Ensure Dataverse schema is deployed. Status: 404"
        }
        elseif ($statusCode) {
            throw "Failed to query validation results. Status: $statusCode, Response: $responseBody, Error: $($_.Exception.Message)"
        }
        else {
            throw "Failed to query validation results: $($_.Exception.Message)"
        }
    }
}

# Execute function if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $results = Get-SSCValidationResults @PSBoundParameters
    Write-Host "Retrieved $($results.Count) validation records" -ForegroundColor Green
    return $results
}

