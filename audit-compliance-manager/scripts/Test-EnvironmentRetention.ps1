#Requires -Version 7.0

<#
.SYNOPSIS
    Validates Dataverse audit retention period against zone-specific thresholds.

.DESCRIPTION
    Validates that a Power Platform environment's Dataverse audit retention period
    meets or exceeds the minimum retention requirement for its governance zone.

    Zone-specific retention thresholds are stored in Dataverse environment variables
    (fsi_ACV_Zone1RetentionDays, fsi_ACV_Zone2RetentionDays, fsi_ACV_Zone3RetentionDays).
    This approach allows administrators to centrally manage retention policies without
    modifying script code.

    Default thresholds if environment variables are not found:
    - Zone1 (Personal Productivity): 180 days
    - Zone2 (Team Collaboration): 365 days
    - Zone3 (Enterprise Managed): 730 days (SEC 17a-4 requirement)

    This validation supports FSI-AgentGov Control 1.7 (Audit Trail Enablement) by
    verifying per-environment retention configuration.

.PARAMETER EnvironmentUrl
    Dataverse organization URL for the target environment to validate.
    Example: https://org.crm.dynamics.com

.PARAMETER AccessToken
    Bearer token for Dataverse Web API authentication for the target environment.
    Obtain via Connect-PowerPlatform.

.PARAMETER DataverseUrl
    Central Dataverse organization URL where environment variables are stored.
    This may be the same as EnvironmentUrl if the central registry is in the same
    environment, or different if using a dedicated governance environment.

.PARAMETER CentralAccessToken
    Bearer token for the central Dataverse instance (where environment variables
    are stored). May be the same as AccessToken if both are the same environment.

.PARAMETER Zone
    Governance zone classification for the environment being validated.
    Required. Determines which retention threshold to apply.

.PARAMETER EnvironmentName
    Display name of the environment for reporting purposes. Optional.

.EXAMPLE
    Test-EnvironmentRetention `
        -EnvironmentUrl "https://sales.crm.dynamics.com" `
        -AccessToken $envToken `
        -DataverseUrl "https://central.crm.dynamics.com" `
        -CentralAccessToken $centralToken `
        -Zone "Zone3" `
        -EnvironmentName "Sales Production"

    Validates that the Sales Production environment meets Zone3 retention requirements
    (730 days minimum) by reading the threshold from central Dataverse environment
    variables and comparing against the environment's actual retention setting.

.EXAMPLE
    Test-EnvironmentRetention `
        -EnvironmentUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -CentralAccessToken $token `
        -Zone "Zone2"

    Validates retention for Zone2 when the central registry is in the same environment
    as the target being validated (same URL and token).

.OUTPUTS
    PSCustomObject with validation result:
    - Timestamp: ISO 8601 UTC timestamp
    - ValidationType: "EnvironmentRetention"
    - EnvironmentId: GUID from Organization record
    - EnvironmentName: Display name or URL
    - Checks: Hashtable with ThresholdLookup and RetentionComparison sub-results
    - OverallStatus: Passed | Failed | Warning | Error
    - Confidence: High | Medium
    - Reason: Human-readable summary
    - RawValue: Actual retention vs threshold (e.g., "RetentionDays=365,RequiredDays=730")
    - RemediationHint: Suggested fix if failed

.NOTES
    Version: 1.0.0
    Requires PowerShell 7.0 or later.

    If the auditretentionperiodv2 field is not available or returns null, the validation
    returns Warning status rather than Failed to avoid false positives. Manual verification
    is recommended in this case.

    Regulatory context:
    This validator supports compliance with:
    - FINRA Rule 4511 (audit trail retention)
    - SEC Rule 17a-4 (2-year minimum retention for broker-dealer communications)
    - GLBA 501(b) (audit logging requirements)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentUrl,

    [Parameter(Mandatory = $true)]
    [string]$AccessToken,

    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $true)]
    [string]$CentralAccessToken,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Zone1", "Zone2", "Zone3")]
    [string]$Zone,

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName
)

function Test-EnvironmentRetention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentUrl,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [string]$DataverseUrl,

        [Parameter(Mandatory = $true)]
        [string]$CentralAccessToken,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Zone1", "Zone2", "Zone3")]
        [string]$Zone,

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentName
    )

    $timestamp = Get-Date -AsUTC -Format "o"
    $displayName = if ($EnvironmentName) { $EnvironmentName } else { $EnvironmentUrl }

    # Default thresholds (used if environment variables not found)
    $defaultThresholds = @{
        "Zone1" = 180
        "Zone2" = 365
        "Zone3" = 730
    }

    # Prepare result object
    $result = [PSCustomObject]@{
        Timestamp       = $timestamp
        ValidationType  = "EnvironmentRetention"
        EnvironmentId   = $null
        EnvironmentName = $displayName
        Checks          = @{}
        OverallStatus   = "Error"
        Confidence      = "High"
        Reason          = ""
        RawValue        = ""
        RemediationHint = ""
    }

    # Normalize URLs
    $envBaseUrl = $EnvironmentUrl.TrimEnd('/')
    $centralBaseUrl = $DataverseUrl.TrimEnd('/')

    # Step 1: Read zone threshold from Dataverse environment variable
    $envVarSchemaName = "fsi_ACV_$($Zone)RetentionDays"
    $threshold = $null

    $centralHeaders = @{
        "Authorization" = "Bearer $CentralAccessToken"
        "Accept"        = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    try {
        Write-Verbose "Reading zone threshold from environment variable: $envVarSchemaName"

        # Query environment variable definition
        $envVarUrl = "$centralBaseUrl/api/data/v9.2/environmentvariabledefinitions?`$filter=schemaname eq '$envVarSchemaName'&`$select=environmentvariabledefinitionid,schemaname,defaultvalue"
        $envVarResponse = Invoke-RestMethod -Uri $envVarUrl -Method Get -Headers $centralHeaders -ErrorAction Stop

        if ($envVarResponse.value -and $envVarResponse.value.Count -gt 0) {
            $envVarDef = $envVarResponse.value[0]
            $envVarDefId = $envVarDef.environmentvariabledefinitionid

            # Check for instance-specific override value
            $valueUrl = "$centralBaseUrl/api/data/v9.2/environmentvariablevalues?`$filter=_environmentvariabledefinitionid_value eq $envVarDefId&`$select=value&`$orderby=createdon desc&`$top=1"
            $valueResponse = Invoke-RestMethod -Uri $valueUrl -Method Get -Headers $centralHeaders -ErrorAction SilentlyContinue

            if ($valueResponse.value -and $valueResponse.value.Count -gt 0) {
                # Instance-specific value exists
                $threshold = [int]$valueResponse.value[0].value
                Write-Verbose "Using instance-specific environment variable value: $threshold days"
            } else {
                # Use default value
                $threshold = [int]$envVarDef.defaultvalue
                Write-Verbose "Using default environment variable value: $threshold days"
            }

            $result.Checks.ThresholdLookup = @{
                Status = "Success"
                Reason = "Zone threshold read from Dataverse environment variable: $envVarSchemaName = $threshold days"
            }
        } else {
            # Environment variable not found - use hardcoded default
            $threshold = $defaultThresholds[$Zone]
            Write-Warning "Environment variable $envVarSchemaName not found in central Dataverse. Using default threshold: $threshold days"

            $result.Checks.ThresholdLookup = @{
                Status = "Warning"
                Reason = "Environment variable $envVarSchemaName not found. Using default threshold: $threshold days"
            }
            $result.Confidence = "Medium"
        }
    } catch {
        # Failed to read environment variable - use hardcoded default
        $threshold = $defaultThresholds[$Zone]
        Write-Warning "Failed to read environment variable $envVarSchemaName. Error: $($_.Exception.Message). Using default threshold: $threshold days"

        $result.Checks.ThresholdLookup = @{
            Status = "Warning"
            Reason = "Failed to read environment variable (API error). Using default threshold: $threshold days"
        }
        $result.Confidence = "Medium"
    }

    # Step 2: Query environment retention settings
    $envHeaders = @{
        "Authorization" = "Bearer $AccessToken"
        "Accept"        = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $orgUrl = "$envBaseUrl/api/data/v9.2/organizations?`$select=organizationid,auditretentionperiodv2,isauditenabled"

    try {
        Write-Verbose "Querying environment retention settings at $orgUrl"
        $orgResponse = Invoke-RestMethod -Uri $orgUrl -Method Get -Headers $envHeaders -ErrorAction Stop

        if (-not $orgResponse.value -or $orgResponse.value.Count -eq 0) {
            $result.OverallStatus = "Error"
            $result.Reason = "No Organization record found in Dataverse. Environment may not have a Dataverse database."
            $result.RawValue = "OrganizationRecordCount=0"
            $result.RemediationHint = "Verify that the environment has a Dataverse database provisioned. Check in Power Platform admin center > Environments > $displayName > Resources > Dataverse."
            return $result
        }

        $org = $orgResponse.value[0]
        $result.EnvironmentId = $org.organizationid

        # Check if auditretentionperiodv2 is available
        if ($null -eq $org.auditretentionperiodv2) {
            # Retention period not available programmatically
            $result.OverallStatus = "Warning"
            $result.Confidence = "Low"
            $result.Reason = "Unable to determine audit retention period programmatically. The auditretentionperiodv2 field is not available or returns null."
            $result.RawValue = "RetentionDays=Unknown,RequiredDays=$threshold"
            $result.RemediationHint = "Verify audit retention manually in Power Platform admin center > Environments > $displayName > Settings > Auditing. Ensure retention is set to $threshold days or greater for $Zone compliance."

            $result.Checks.RetentionComparison = @{
                Status = "Warning"
                Reason = "Retention period unavailable via API (field not accessible)"
            }

            return $result
        }

        $actualRetention = [int]$org.auditretentionperiodv2
        $result.RawValue = "RetentionDays=$actualRetention,RequiredDays=$threshold"

        # Step 3: Compare against threshold
        if ($actualRetention -ge $threshold) {
            # Passed
            $result.OverallStatus = "Passed"
            $result.Reason = "Audit retention period ($actualRetention days) meets or exceeds $Zone minimum requirement ($threshold days)."
            $result.RemediationHint = "No action required."

            $result.Checks.RetentionComparison = @{
                Status = "Passed"
                Reason = "Retention $actualRetention days >= required $threshold days"
            }
        } else {
            # Failed
            $result.OverallStatus = "Failed"
            $result.Reason = "Audit retention period ($actualRetention days) is below $Zone minimum requirement ($threshold days)."
            $result.RemediationHint = "Increase audit retention to $threshold days minimum for $Zone in Power Platform admin center > Environments > $displayName > Settings > Auditing. Update 'Retention Period (days)' setting."

            $result.Checks.RetentionComparison = @{
                Status = "Failed"
                Reason = "Retention $actualRetention days < required $threshold days (shortfall: $($threshold - $actualRetention) days)"
            }
        }

    } catch {
        # API call failed
        $errorMessage = $_.Exception.Message
        $statusCode = $_.Exception.Response.StatusCode.value__ -as [int]

        $result.OverallStatus = "Error"
        $result.Checks.DataverseAccess = @{
            Status = "Error"
            Reason = "API call failed: $errorMessage"
        }

        if ($statusCode -eq 404) {
            $result.Reason = "No Dataverse database accessible at $EnvironmentUrl. Environment may not have Dataverse provisioned."
            $result.RawValue = "HttpStatus=404,RequiredDays=$threshold"
            $result.RemediationHint = "Verify that the environment has a Dataverse database. Check in Power Platform admin center > Environments > $displayName > Resources."
        } elseif ($statusCode -eq 401 -or $statusCode -eq 403) {
            $result.Reason = "Authentication or authorization failed. Access token may be invalid or insufficient permissions."
            $result.RawValue = "HttpStatus=$statusCode,RequiredDays=$threshold"
            $result.RemediationHint = "Verify that the access token is valid and has System Administrator or System Customizer role in Dataverse."
        } else {
            $result.Reason = "Failed to query Organization table: $errorMessage"
            $result.RawValue = "HttpStatus=$statusCode,RequiredDays=$threshold,Error=$errorMessage"
            $result.RemediationHint = "Check network connectivity to $EnvironmentUrl and verify Dataverse Web API is accessible."
        }
    }

    return $result
}

# Execute if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Test-EnvironmentRetention @PSBoundParameters
}
