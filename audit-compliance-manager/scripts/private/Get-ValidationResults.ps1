#Requires -Version 7.0

<#
.SYNOPSIS
    Queries Dataverse audit validation history for specified scope and date range.

.DESCRIPTION
    Retrieves validation result records from the fsi_auditvalidationhistories table
    via Dataverse Web API with OData filtering. Handles pagination automatically to
    ensure complete result sets for evidence export.

    Used by Export-AuditValidationEvidence to retrieve historical validation data
    for compliance evidence packages.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER AccessToken
    Bearer token for Dataverse Web API authentication. Obtain via Connect-PowerPlatform.

.PARAMETER Scope
    Validation scope filter: Tenant-level or Environment-level checks.

.PARAMETER RunId
    Optional GUID to filter results to a specific validation run.

.PARAMETER FromDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER ToDate
    End of date range filter (inclusive). Defaults to current timestamp.

.EXAMPLE
    Get-ValidationResults `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -Scope "Tenant" `
        -FromDate (Get-Date).AddDays(-90) `
        -ToDate (Get-Date)

    Retrieves all tenant-level validation results from the past 90 days.

.EXAMPLE
    Get-ValidationResults `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -Scope "Environment" `
        -RunId "12345-guid"

    Retrieves all environment-level results for a specific validation run.

.OUTPUTS
    Array of PSCustomObjects containing validation result records. Each object
    includes fields: fsi_name, fsi_runid, fsi_scope, fsi_environmentid, fsi_zone,
    fsi_severity, fsi_validationtype, fsi_rawvalue, fsi_reason, fsi_timestamp.

.NOTES
    Version: 1.0.0
    This is a private helper function for internal use by Export-AuditValidationEvidence.

    Option set mappings (must match Dataverse schema):
    - fsi_acv_scope: Tenant=100000000, Environment=100000001
    - fsi_acv_severity: Passed=1, Warning=2, GracePeriod=3, Failed=4, Error=5
    - fsi_acv_zone: Unclassified=0, Zone1=1, Zone2=2, Zone3=3

    Query automatically handles pagination via @odata.nextLink to retrieve complete
    result sets (Dataverse default page size is 5000 records).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $true)]
    [string]$AccessToken,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Tenant", "Environment")]
    [string]$Scope,

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [datetime]$FromDate = (Get-Date).AddDays(-30),

    [Parameter(Mandatory = $false)]
    [datetime]$ToDate = (Get-Date)
)

$ErrorActionPreference = "Stop"

function Get-ValidationResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataverseUrl,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Tenant", "Environment")]
        [string]$Scope,

        [Parameter(Mandatory = $false)]
        [string]$RunId,

        [Parameter(Mandatory = $false)]
        [datetime]$FromDate = (Get-Date).AddDays(-30),

        [Parameter(Mandatory = $false)]
        [datetime]$ToDate = (Get-Date)
    )

    try {
        # Normalize Dataverse URL (remove trailing slash)
        $DataverseUrl = $DataverseUrl.TrimEnd('/')

        # Map scope to option set value
        $scopeMap = @{
            "Tenant"      = 100000000
            "Environment" = 100000001
        }
        $scopeValue = $scopeMap[$Scope]

        # Build OData filter components
        $filters = @()

        # Scope filter
        $filters += "fsi_scope eq $scopeValue"

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
        $filterString = $filters -join ' and '

        # Build full query URL
        $selectFields = "fsi_name,fsi_runid,fsi_scope,fsi_environmentid,fsi_environmentname,fsi_zone,fsi_severity,fsi_validationtype,fsi_rawvalue,fsi_reason,fsi_timestamp,fsi_remediationhint,fsi_checkcount"
        $queryUrl = "$DataverseUrl/api/data/v9.2/fsi_auditvalidationhistories?`$filter=$filterString&`$orderby=fsi_timestamp desc&`$select=$selectFields"

        # Prepare headers
        $headers = @{
            "Authorization"    = "Bearer $AccessToken"
            "Accept"           = "application/json"
            "OData-MaxVersion" = "4.0"
            "OData-Version"    = "4.0"
        }

        # Execute query with pagination handling
        $allResults = @()
        $nextLink = $queryUrl

        Write-Verbose "Querying validation history: Scope=$Scope, FromDate=$fromDateUtc, ToDate=$toDateUtc"

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
        $statusCode = $_.Exception.Response.StatusCode.value__
        $responseBody = $_.ErrorDetails.Message

        # Provide helpful error messages for common scenarios
        if ($statusCode -eq 401) {
            throw "Authentication failed. Access token may be expired or invalid. Status: 401"
        }
        elseif ($statusCode -eq 404) {
            throw "Audit validation history table not found. Ensure Dataverse schema is deployed. Status: 404"
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
    $results = Get-ValidationResults @PSBoundParameters
    Write-Host "Retrieved $($results.Count) validation records" -ForegroundColor Green
    return $results
}

# Note: This script is dot-sourced; do not use Export-ModuleMember outside a .psm1 module.
