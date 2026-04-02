<#
.SYNOPSIS
    Queries CAA validation data from Dataverse via OData Web API.

.DESCRIPTION
    Private helper that retrieves Conditional Access policy compliance data
    from three Dataverse tables: validation histories, violations, and baselines.

    Supports date range filtering, run ID filtering, and automatic pagination
    via @odata.nextLink for large result sets. This function is intended to be
    dot-sourced by Export-CAAComplianceEvidence.ps1 and is not exported from the
    module.

.PARAMETER DataverseUrl
    The Dataverse environment URL (e.g., https://org.crm.dynamics.com).

.PARAMETER AccessToken
    A valid OAuth2 bearer token for the Dataverse environment.

.PARAMETER Table
    The Dataverse table to query. Valid values:
    - fsi_capolicyvalidationhistories — immutable validation run results
    - fsi_capolicyviolations — active policy violations
    - fsi_capolicybaselines — current policy baselines

.PARAMETER FromDate
    Optional start date for filtering records by timestamp.

.PARAMETER ToDate
    Optional end date for filtering records by timestamp.

.PARAMETER RunId
    Optional validation run identifier to filter validation history records.

.EXAMPLE
    $token = (Get-AzAccessToken -ResourceUrl $dvUrl).Token
    Get-CAAValidationResults -DataverseUrl 'https://org.crm.dynamics.com' `
        -AccessToken $token -Table 'fsi_capolicyvalidationhistories' `
        -FromDate (Get-Date).AddDays(-30)

    Retrieves the last 30 days of validation history records.

.EXAMPLE
    Get-CAAValidationResults -DataverseUrl $dvUrl -AccessToken $token `
        -Table 'fsi_capolicyviolations' -FromDate '2026-01-01' -ToDate '2026-01-31'

    Retrieves violations within the specified date range.

.EXAMPLE
    Get-CAAValidationResults -DataverseUrl $dvUrl -AccessToken $token `
        -Table 'fsi_capolicybaselines'

    Retrieves all active baseline records.

.OUTPUTS
    System.Collections.ArrayList
    An array of Dataverse records matching the query criteria.

.NOTES
    File: Get-CAAValidationResults.ps1
    Version: 1.0.0
    This is a private helper — not exported from the module.
    Supports evidence collection for FINRA 4511/3110 and SEC 17a-3/4
    examination readiness.
#>

#Requires -Version 7.0

function Get-CAAValidationResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DataverseUrl,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,

        [Parameter(Mandatory)]
        [ValidateSet(
            'fsi_capolicyvalidationhistories',
            'fsi_capolicyviolations',
            'fsi_capolicybaselines'
        )]
        [string]$Table,

        [Parameter()]
        [datetime]$FromDate,

        [Parameter()]
        [datetime]$ToDate,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z0-9\-]+$')]
        [string]$RunId
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Build request headers
    $headers = @{
        'Authorization' = "Bearer $AccessToken"
        'Accept'        = 'application/json'
        'OData-Version' = '4.0'
        'Prefer'        = 'odata.include-annotations="*",odata.maxpagesize=500'
    }

    # Determine timestamp column per table
    $timestampColumn = switch ($Table) {
        'fsi_capolicyvalidationhistories' { 'fsi_validation_time' }
        'fsi_capolicyviolations'          { 'fsi_detected_at' }
        'fsi_capolicybaselines'           { 'fsi_captured_at' }
    }

    # Build OData filter clauses
    $filters = [System.Collections.ArrayList]::new()

    if ($FromDate) {
        $fromIso = $FromDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        [void]$filters.Add("$timestampColumn ge $fromIso")
    }

    if ($ToDate) {
        $toIso = $ToDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        [void]$filters.Add("$timestampColumn le $toIso")
    }

    if ($RunId -and $Table -eq 'fsi_capolicyvalidationhistories') {
        [void]$filters.Add("fsi_run_id eq '$RunId'")
    }

    # For baselines, only retrieve active records by default
    if ($Table -eq 'fsi_capolicybaselines') {
        [void]$filters.Add("fsi_is_active eq true")
    }

    # Construct query URL
    $baseUrl = $DataverseUrl.TrimEnd('/')
    $queryUrl = "$baseUrl/api/data/v9.2/$Table"

    if ($filters.Count -gt 0) {
        $filterString = $filters -join ' and '
        $queryUrl += "?`$filter=$filterString&`$orderby=$timestampColumn desc"
    }
    else {
        $queryUrl += "?`$orderby=$timestampColumn desc"
    }

    Write-Verbose "Querying Dataverse: $Table"
    Write-Verbose "  URL: $queryUrl"

    # Execute paginated query
    $allRecords = [System.Collections.ArrayList]::new()
    $currentUrl = $queryUrl
    $pageCount = 0

    while ($currentUrl) {
        $pageCount++
        Write-Verbose "  Fetching page $pageCount..."

        try {
            $response = Invoke-RestMethod -Uri $currentUrl -Headers $headers -Method Get
        }
        catch {
            $statusCode = [int]$_.Exception.Response.StatusCode
            Write-Error "Dataverse query failed for table '$Table' (HTTP $statusCode): $($_.Exception.Message)"
            throw
        }

        # Collect records from this page
        if ($response.value) {
            foreach ($record in $response.value) {
                [void]$allRecords.Add($record)
            }
        }

        # Follow pagination link if present
        $currentUrl = $response.'@odata.nextLink'
    }

    Write-Verbose "  Retrieved $($allRecords.Count) records across $pageCount page(s)."

    return ,$allRecords
}
