#Requires -Version 7.0

<#
.SYNOPSIS
    Queries Dataverse agent access validation history and violations for evidence export.

.DESCRIPTION
    Retrieves validation result records from the fsi_accessvalidationhistory table
    and optionally the fsi_accessviolations table via Dataverse Web API with OData
    filtering. Handles pagination automatically to retrieve complete result sets.

    Used by Export-AgentAccessEvidence to retrieve historical validation data
    for compliance evidence packages. Follows the established AAMClient.psm1 pattern
    for Dataverse Web API interaction.

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
    When specified, also queries the fsi_accessviolations table and includes
    violation records in the result object.

.EXAMPLE
    Get-AAMValidationResults `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -FromDate (Get-Date).AddDays(-90) `
        -ToDate (Get-Date) `
        -IncludeViolations

    Retrieves all validation history and violation records from the past 90 days.

.EXAMPLE
    Get-AAMValidationResults `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -RunId "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

    Retrieves validation history for a specific validation run.

.EXAMPLE
    Get-AAMValidationResults `
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
    Version: 1.1.1
    This is a private helper function for internal use by Export-AgentAccessEvidence.

    Dataverse tables queried:
    - fsi_accessvalidationhistory: Aggregate validation run summaries
    - fsi_accessviolations: Individual access policy violations

    Query automatically handles pagination via @odata.nextLink to retrieve complete
    result sets (Dataverse default page size is 5000 records).
#>

function Get-AAMValidationResults {
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

        #region Query fsi_accessvalidationhistory

        # Build OData filter components for validation history
        $historyFilters = @()

        # Date range filters (convert to ISO 8601 UTC)
        $fromDateUtc = $FromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $toDateUtc = $ToDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $historyFilters += "fsi_validationtime ge $fromDateUtc"
        $historyFilters += "fsi_validationtime le $toDateUtc"

        # Optional RunId filter
        if ($RunId) {
            $historyFilters += "fsi_runid eq '$($RunId -replace "'", "''")'"
        }

        # Combine filters
        $historyFilterString = $historyFilters -join ' and '

        # Select fields for validation history
        $historySelect = "fsi_name,fsi_runid,fsi_validationtime,fsi_totalenvironments,fsi_compliantcount,fsi_violationcount,fsi_overallstatus,fsi_summaryjson"

        # Build query URL
        $historyUrl = "$DataverseUrl/api/data/v9.2/fsi_accessvalidationhistory?`$filter=$historyFilterString&`$orderby=fsi_validationtime desc&`$select=$historySelect"

        Write-Verbose "Querying validation history: FromDate=$fromDateUtc, ToDate=$toDateUtc"
        if ($RunId) { Write-Verbose "RunId filter: $RunId" }

        # Execute query with pagination handling
        $allValidations = @()
        $nextLink = $historyUrl

        while ($nextLink) {
            Write-Verbose "Fetching page: $nextLink"

            $retryCount = 0
            $maxRetries = 3
            do {
                try {
                    $response = Invoke-RestMethod `
                        -Uri $nextLink `
                        -Method Get `
                        -Headers $headers `
                        -ErrorAction Stop
                    break
                }
                catch {
                    $retryCount++
                    if ($retryCount -ge $maxRetries) { throw }
                    $backoffSeconds = [math]::Pow(2, $retryCount)
                    Write-Verbose "Transient error fetching validations (attempt $retryCount/$maxRetries). Retrying in ${backoffSeconds}s: $_"
                    Start-Sleep -Seconds $backoffSeconds
                }
            } while ($retryCount -lt $maxRetries)

            if ($response.value) {
                $allValidations += $response.value
                Write-Verbose "Retrieved $($response.value.Count) validation records (total: $($allValidations.Count))"
            }

            # Check for next page
            $nextLink = $response.'@odata.nextLink'
        }

        Write-Verbose "Validation history query complete. Total records: $($allValidations.Count)"

        #endregion

        #region Query fsi_accessviolations (optional)

        $allViolations = @()

        if ($IncludeViolations) {
            # Build OData filter for violations
            $violationFilters = @()

            # Date range on detected_at
            $violationFilters += "fsi_detectedat ge $fromDateUtc"
            $violationFilters += "fsi_detectedat le $toDateUtc"

            # Optional RunId filter
            if ($RunId) {
                $violationFilters += "fsi_runid eq '$($RunId -replace "'", "''")'"
            }

            # Optional zone filter (not applied when 'All')
            if ($Zone -ne 'All') {
                # Map zone name to Dataverse option set integer
                $zoneIntMap = @{ '1' = 100000001; '2' = 100000002; '3' = 100000003 }
                $zoneInt = if ($zoneIntMap.ContainsKey($Zone)) { $zoneIntMap[$Zone] } else { $Zone }
                $violationFilters += "fsi_zone eq $zoneInt"
            }

            # Combine filters
            $violationFilterString = $violationFilters -join ' and '

            # Select fields for violations
            $violationSelect = "fsi_name,fsi_environmentguid,fsi_environmentname,fsi_zone,fsi_violationtype,fsi_expectedvalue,fsi_actualvalue,fsi_severity,fsi_severitylabel,fsi_regulatorycontext,fsi_detectedat,fsi_runid"

            # Build query URL
            $violationUrl = "$DataverseUrl/api/data/v9.2/fsi_accessviolations?`$filter=$violationFilterString&`$orderby=fsi_detectedat desc&`$select=$violationSelect"

            Write-Verbose "Querying violations: Zone=$Zone"

            $nextLink = $violationUrl

            while ($nextLink) {
                Write-Verbose "Fetching violations page: $nextLink"

                $vRetryCount = 0
                $vMaxRetries = 3
                do {
                    try {
                        $response = Invoke-RestMethod `
                            -Uri $nextLink `
                            -Method Get `
                            -Headers $headers `
                            -ErrorAction Stop
                        break
                    }
                    catch {
                        $vRetryCount++
                        if ($vRetryCount -ge $vMaxRetries) { throw }
                        $backoffSeconds = [math]::Pow(2, $vRetryCount)
                        Write-Verbose "Transient error fetching violations (attempt $vRetryCount/$vMaxRetries). Retrying in ${backoffSeconds}s: $_"
                        Start-Sleep -Seconds $backoffSeconds
                    }
                } while ($vRetryCount -lt $vMaxRetries)

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
            throw "Authentication failed querying AAM validation data. Access token may be expired or invalid. Status: 401"
        }
        elseif ($statusCode -eq 404) {
            throw "AAM Dataverse tables not found. Verify the AAM solution schema is deployed. Status: 404"
        }
        elseif ($statusCode) {
            throw "Failed to query AAM validation results. Status: $statusCode, Response: $responseBody, Error: $($_.Exception.Message)"
        }
        else {
            throw "Failed to query AAM validation results: $($_.Exception.Message)"
        }
    }
}
