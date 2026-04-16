#Requires -Version 7.2

<#
.SYNOPSIS
    Validates Dataverse audit log enablement for a Power Platform environment.

.DESCRIPTION
    Validates that Dataverse audit logging is enabled for a specific Power Platform
    environment by querying the Organization table via Dataverse Web API. This check
    verifies that audit events are being captured at the environment level.

    The validation includes a configurable grace period to avoid false negatives for
    recently-enabled environments. Audit enablement can take time to propagate, so
    environments enabled within the grace period window receive a "GracePeriod" status
    instead of "Failed".

    This validation supports FSI-AgentGov Control 1.7 (Audit Trail Enablement) by
    verifying per-environment audit configuration.

.PARAMETER EnvironmentUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com). Required.
    This is the target environment to validate.

.PARAMETER AccessToken
    Bearer token for Dataverse Web API authentication. Required.
    Obtain via Connect-PowerPlatform.

.PARAMETER EnvironmentName
    Display name of the environment for reporting purposes. Optional.
    If not provided, the EnvironmentUrl will be used in output.

.PARAMETER GracePeriodHours
    Hours after audit enablement to allow before treating absence as failure. Default: 24.
    If audit was enabled within this window, the status will be "GracePeriod" instead
    of "Failed" to avoid false negatives during propagation.

.EXAMPLE
    $token = Get-DataverseToken -EnvironmentUrl "https://org.crm.dynamics.com"
    Test-EnvironmentAudit -EnvironmentUrl "https://org.crm.dynamics.com" -AccessToken $token

    Validates audit enablement for the specified environment with default 24-hour grace period.

.EXAMPLE
    Test-EnvironmentAudit `
        -EnvironmentUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -EnvironmentName "Sales Production" `
        -GracePeriodHours 12

    Validates with a custom 12-hour grace period and friendly environment name for reporting.

.OUTPUTS
    PSCustomObject with validation result:
    - Timestamp: ISO 8601 UTC timestamp
    - ValidationType: "EnvironmentAudit"
    - EnvironmentId: GUID from Organization record
    - EnvironmentName: Display name or URL
    - Checks: Hashtable with AuditEnabled and GracePeriod sub-results
    - OverallStatus: Passed | GracePeriod | Failed | Error
    - Confidence: High | Medium
    - Reason: Human-readable summary
    - RawValue: Actual configuration values checked
    - RemediationHint: Suggested fix if failed

.NOTES
    Version: 1.0.2
    Requires PowerShell 7.0 or later.

    Grace period detection is best-effort. If enablement timestamp cannot be determined
    from audit records, the validation treats the environment as Passed (with a note)
    rather than Failed to avoid false positives.

    Regulatory context:
    This validator supports compliance with:
    - FINRA Rule 4511 (audit trail retention)
    - SEC Rule 17a-4 (records retention)
    - GLBA 501(b) (audit logging requirements)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentUrl,

    [Parameter(Mandatory = $true)]
    [string]$AccessToken,

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName,

    [Parameter(Mandatory = $false)]
    [int]$GracePeriodHours = 24
)

function Test-EnvironmentAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentUrl,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentName,

        [Parameter(Mandatory = $false)]
        [int]$GracePeriodHours = 24
    )

    $timestamp = Get-Date -AsUTC -Format "o"
    $displayName = if ($EnvironmentName) { $EnvironmentName } else { $EnvironmentUrl }

    # Prepare result object
    $result = [PSCustomObject]@{
        Timestamp       = $timestamp
        ValidationType  = "EnvironmentAudit"
        EnvironmentId   = $null
        EnvironmentName = $displayName
        Checks          = @{}
        OverallStatus   = "Error"
        Confidence      = "High"
        Reason          = ""
        RawValue        = ""
        RemediationHint = ""
    }

    # Normalize environment URL
    $baseUrl = $EnvironmentUrl.TrimEnd('/')

    # Query Organization table for audit settings
    $apiUrl = "$baseUrl/api/data/v9.2/organizations?`$select=organizationid,isauditenabled,createdon,modifiedon"

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Accept"        = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    try {
        Write-Verbose "Querying Organization table at $apiUrl"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -ErrorAction Stop

        if (-not $response.value -or $response.value.Count -eq 0) {
            $result.OverallStatus = "Error"
            $result.Confidence = "High"
            $result.Reason = "No Organization record found in Dataverse. Environment may not have a Dataverse database."
            $result.RawValue = "OrganizationRecordCount=0"
            $result.RemediationHint = "Verify that the environment has a Dataverse database provisioned. Check in Power Platform admin center > Environments > $displayName > Resources > Dataverse."
            return $result
        }

        $org = $response.value[0]
        if (-not $org) {
            throw "Organization record returned null from Dataverse API"
        }
        $result.EnvironmentId = $org.organizationid
        $result.RawValue = "AuditEnabled=$($org.isauditenabled)"

        # Check if audit is enabled
        if ($org.isauditenabled -eq $true) {
            # Audit is enabled - check grace period
            $gracePeriodCheck = @{
                Status = "Passed"
                Reason = "Grace period check not applicable (audit enabled)"
            }

            # Attempt to determine enablement timing (best-effort)
            # Note: Grace period detection is best-effort. If we cannot determine
            # when audit was enabled, we treat as Passed rather than Failed.
            try {
                # Query for recent audit settings changes (attempts to find enablement event)
                $auditUrl = "$baseUrl/api/data/v9.2/audits?`$filter=objecttypecode eq 'organization' and action eq 1&`$orderby=createdon desc&`$top=10"
                $auditResponse = Invoke-RestMethod -Uri $auditUrl -Method Get -Headers $headers -ErrorAction SilentlyContinue

                if ($auditResponse.value -and $auditResponse.value.Count -gt 0) {
                    # Look for the most recent audit enablement event
                    $enablementEvent = $auditResponse.value | Where-Object { $_.attributemask -like '*isauditenabled*' } | Select-Object -First 1

                    if ($enablementEvent) {
                        $enablementTime = [DateTime]::Parse($enablementEvent.createdon)
                        $hoursSinceEnablement = ((Get-Date -AsUTC) - $enablementTime).TotalHours

                        if ($hoursSinceEnablement -le $GracePeriodHours) {
                            $gracePeriodCheck.Status = "GracePeriod"
                            $gracePeriodCheck.Reason = "Audit enabled $([math]::Round($hoursSinceEnablement, 1))h ago, within $GracePeriodHours-hour grace period"

                            $result.OverallStatus = "GracePeriod"
                            $result.Reason = "Dataverse audit is enabled but was recently activated. Grace period applies."
                            $result.RawValue += ", EnablementHoursAgo=$([math]::Round($hoursSinceEnablement, 1))"
                            $result.RemediationHint = "Audit is enabled. Wait for propagation to complete. Re-validate after grace period expires."
                        } else {
                            $result.OverallStatus = "Passed"
                            $result.Reason = "Dataverse audit is enabled and has been active for $([math]::Round($hoursSinceEnablement, 1)) hours."
                            $result.RemediationHint = "No action required."
                        }
                    } else {
                        # No enablement event found in recent audit log - treat as Passed
                        $result.OverallStatus = "Passed"
                        $result.Confidence = "Medium"
                        $result.Reason = "Dataverse audit is enabled. Enablement timestamp not available (audit may have been enabled before audit log retention period)."
                        $result.RemediationHint = "No action required."
                    }
                } else {
                    # No audit records available - treat as Passed
                    $result.OverallStatus = "Passed"
                    $result.Confidence = "Medium"
                    $result.Reason = "Dataverse audit is enabled. Enablement timestamp not available (no audit history accessible)."
                    $result.RemediationHint = "No action required."
                }
            } catch {
                # Grace period detection failed (API error, permissions, etc.) - treat as Passed
                Write-Verbose "Grace period detection failed: $($_.Exception.Message). Treating as Passed."
                $result.OverallStatus = "Passed"
                $result.Confidence = "Medium"
                $result.Reason = "Dataverse audit is enabled. Grace period check could not be performed (best-effort check failed)."
                $result.RemediationHint = "No action required."
            }

            $result.Checks.AuditEnabled = @{
                Status = "Passed"
                Reason = "isauditenabled=true in Organization table"
            }
            $result.Checks.GracePeriod = $gracePeriodCheck

        } else {
            # Audit is NOT enabled
            $result.Checks.AuditEnabled = @{
                Status = "Failed"
                Reason = "isauditenabled=false in Organization table"
            }
            $result.Checks.GracePeriod = @{
                Status = "NotApplicable"
                Reason = "Grace period check skipped (audit is disabled)"
            }

            $result.OverallStatus = "Failed"
            $result.Confidence = "High"
            $result.Reason = "Dataverse audit is disabled for this environment."
            $result.RemediationHint = "Enable Dataverse auditing in Power Platform admin center > Environments > $displayName > Settings > Auditing. Set 'Start Auditing' to On."
        }

    } catch {
        # API call failed
        $errorMessage = $_.Exception.Message
        $statusCode = $_.Exception.Response.StatusCode.value__ -as [int]

        $result.OverallStatus = "Error"
        $result.Confidence = "High"
        $result.Checks.DataverseAccess = @{
            Status = "Error"
            Reason = "API call failed: $errorMessage"
        }

        if ($statusCode -eq 404) {
            $result.Reason = "No Dataverse database accessible at $EnvironmentUrl. Environment may not have Dataverse provisioned."
            $result.RawValue = "HttpStatus=404"
            $result.RemediationHint = "Verify that the environment has a Dataverse database. Check in Power Platform admin center > Environments > $displayName > Resources."
        } elseif ($statusCode -eq 401 -or $statusCode -eq 403) {
            $result.Reason = "Authentication or authorization failed. Access token may be invalid or insufficient permissions."
            $result.RawValue = "HttpStatus=$statusCode"
            $result.RemediationHint = "Verify that the access token is valid and has System Administrator or System Customizer role in Dataverse."
        } else {
            $result.Reason = "Failed to query Organization table: $errorMessage"
            $result.RawValue = "HttpStatus=$statusCode, Error=$errorMessage"
            $result.RemediationHint = "Check network connectivity to $EnvironmentUrl and verify Dataverse Web API is accessible."
        }
    }

    return $result
}

# Execute if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Test-EnvironmentAudit @PSBoundParameters
}
