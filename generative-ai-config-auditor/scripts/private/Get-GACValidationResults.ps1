#Requires -Version 7.4

# Import GACClient module for Invoke-DataverseRequest (retry/backoff on 429/5xx)
Import-Module (Join-Path $PSScriptRoot 'GACClient.psm1') -Force

<#
.SYNOPSIS
    Queries Dataverse GAC validation history and violations for evidence export.

.DESCRIPTION
    Retrieves validation result records from the fsi_gacvalidationhistory table
    and optionally the fsi_gacviolations table via Dataverse Web API with OData
    filtering. Handles pagination automatically to retrieve complete result sets.

    Used by Export-GenAIConfigEvidence to retrieve historical validation data
    for compliance evidence packages. Follows the established GACClient.psm1
    pattern for Dataverse Web API interaction.

    GAC operates at the agent level: each violation record includes per-agent
    detail (fsi_agentid, fsi_agentname, fsi_aoaienabled, fsi_orchestrationmode)
    for generative AI configuration governance.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER AccessToken
    Bearer token for Dataverse Web API authentication.

.PARAMETER Zone
    Optional zone filter for violation records. Validation history records are
    aggregate summaries and are not zone-filtered. Valid values: All, 1, 2, 3.
    Default: All.

.PARAMETER FromDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER ToDate
    End of date range filter (inclusive). Defaults to current timestamp.

.PARAMETER RunId
    Optional GUID to filter results to a specific validation run.

.PARAMETER IncludeViolations
    When specified, also queries the fsi_gacviolations table and includes
    violation records in the result object.

.EXAMPLE
    Get-GACValidationResults `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -FromDate (Get-Date).AddDays(-90) `
        -ToDate (Get-Date) `
        -IncludeViolations

    Retrieves all validation history and violation records from the past 90 days.

.EXAMPLE
    Get-GACValidationResults `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -RunId "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

    Retrieves validation history for a specific validation run.

.EXAMPLE
    Get-GACValidationResults `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -Zone "2" `
        -IncludeViolations

    Retrieves validation history and Zone 2 violations from the past 30 days.

.OUTPUTS
    PSCustomObject with properties:
    - Validations: Array of validation history records
    - Violations: Array of violation records (empty if -IncludeViolations not specified)

.NOTES
    Version: 1.0.0
    This is a private helper function for internal use by Export-GenAIConfigEvidence.

    Dataverse tables queried:
    - fsi_gacvalidationhistory: Aggregate validation run summaries
    - fsi_gacviolations: Individual per-agent GenAI configuration violations

    Query automatically handles pagination via @odata.nextLink to retrieve complete
    result sets (Dataverse default page size is 5000 records).
#>

function Get-GACValidationResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataverseUrl,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [ValidateSet('All', '1', '2', '3')]
        [string]$Zone = 'All',

        [Parameter(Mandatory = $false)]
        [datetime]$FromDate = (Get-Date).AddDays(-30),

        [Parameter(Mandatory = $false)]
        [datetime]$ToDate = (Get-Date),

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[0-9a-fA-F\-]{36}$')]
        [string]$RunId,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeViolations
    )

    $ErrorActionPreference = "Stop"

    try {
        # Normalize Dataverse URL (remove trailing slash)
        $DataverseUrl = $DataverseUrl.TrimEnd('/')

        # Prepare standard Dataverse Web API headers
        $headers = @{
            "Authorization"    = "Bearer $AccessToken"
            "Accept"           = "application/json"
            "OData-MaxVersion" = "4.0"
            "OData-Version"    = "4.0"
        }

        #region Query fsi_gacvalidationhistory

        # Build OData filter components for validation history
        $historyFilters = @()

        # Date range filters (convert to ISO 8601 UTC)
        $fromDateUtc = $FromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $toDateUtc = $ToDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $historyFilters += "fsi_validationtime ge $fromDateUtc"
        $historyFilters += "fsi_validationtime le $toDateUtc"

        # Optional RunId filter
        if ($RunId) {
            $safeRunId = $RunId -replace "'", "''"
            $historyFilters += "fsi_runid eq '$safeRunId'"
        }

        # Combine filters
        $historyFilterString = $historyFilters -join ' and '

        # Select fields for validation history
        $historySelect = "fsi_name,fsi_runid,fsi_validationtime,fsi_totalagents,fsi_compliantcount,fsi_violationcount,fsi_overallstatus,fsi_environmentsscanned,fsi_summaryjson"

        # Build query URL
        $historyUrl = "$DataverseUrl/api/data/v9.2/fsi_gacvalidationhistory?`$filter=$historyFilterString&`$orderby=fsi_validationtime desc&`$select=$historySelect"

        Write-Verbose "Querying validation history: FromDate=$fromDateUtc, ToDate=$toDateUtc"
        if ($RunId) { Write-Verbose "RunId filter: $RunId" }

        # Execute query with pagination handling
        $allValidations = @()
        $nextLink = $historyUrl

        while ($nextLink) {
            Write-Verbose "Fetching page: $nextLink"

            $response = Invoke-DataverseRequest `
                -Uri $nextLink `
                -Method Get `
                -Headers $headers

            if ($response.value) {
                $allValidations += $response.value
                Write-Verbose "Retrieved $($response.value.Count) validation records (total: $($allValidations.Count))"
            }

            # Check for next page
            $nextLink = $response.'@odata.nextLink'
        }

        Write-Verbose "Validation history query complete. Total records: $($allValidations.Count)"

        #endregion

        #region Query fsi_gacviolations (optional)

        $allViolations = @()

        if ($IncludeViolations) {
            # Build OData filter for violations
            $violationFilters = @()

            # Date range on fsi_detectedat
            $violationFilters += "fsi_detectedat ge $fromDateUtc"
            $violationFilters += "fsi_detectedat le $toDateUtc"

            # Optional RunId filter
            if ($RunId) {
                $safeRunId = $RunId -replace "'", "''"
                $violationFilters += "fsi_runid eq '$safeRunId'"
            }

            # Optional zone filter (not applied when 'All')
            # fsi_zone is a Dataverse picklist (integer) column — do not quote the value
            if ($Zone -ne 'All') {
                $zoneIntMap = @{ '1' = 1; '2' = 2; '3' = 3 }
                $zoneIntValue = $zoneIntMap[$Zone]
                $violationFilters += "fsi_zone eq $zoneIntValue"
            }

            # Combine filters
            $violationFilterString = $violationFilters -join ' and '

            # Select fields for violations (agent-level detail for GAC)
            $violationSelect = "fsi_name,fsi_environmentguid,fsi_environmentname,fsi_agentid,fsi_agentname,fsi_zone,fsi_featuretype,fsi_expectedstate,fsi_actualstate,fsi_connectionstatus,fsi_severity,fsi_regulatorycontext,fsi_topicname,fsi_topicid,fsi_detectedat,fsi_runid"

            # Build query URL
            $violationUrl = "$DataverseUrl/api/data/v9.2/fsi_gacviolations?`$filter=$violationFilterString&`$orderby=fsi_detectedat desc&`$select=$violationSelect"

            Write-Verbose "Querying violations: Zone=$Zone"

            $nextLink = $violationUrl

            while ($nextLink) {
                Write-Verbose "Fetching violations page: $nextLink"

                $response = Invoke-DataverseRequest `
                    -Uri $nextLink `
                    -Method Get `
                    -Headers $headers

                if ($response.value) {
                    $allViolations += $response.value
                    Write-Verbose "Retrieved $($response.value.Count) violation records (total: $($allViolations.Count))"
                }

                $nextLink = $response.'@odata.nextLink'
            }

            Write-Verbose "Violations query complete. Total records: $($allViolations.Count)"
        }

        #endregion

        # Return structured result
        return [PSCustomObject]@{
            Validations = $allValidations
            Violations  = $allViolations
        }
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
            throw "Authentication failed querying GAC validation data. Access token may be expired or invalid. Status: 401"
        }
        elseif ($statusCode -eq 404) {
            throw "GAC Dataverse tables not found. Verify the Generative AI Config Auditor solution schema is deployed. Status: 404"
        }
        elseif ($statusCode) {
            throw "Failed to query GAC validation results. Status: $statusCode, Response: $responseBody, Error: $($_.Exception.Message)"
        }
        else {
            throw "Failed to query GAC validation results: $($_.Exception.Message)"
        }
    }
}
