#Requires -Version 7.2

<#
.SYNOPSIS
    Writes a single validation result record to Dataverse audit validation history table.

.DESCRIPTION
    Creates an immutable validation result record in the fsi_auditvalidationhistory table
    via Dataverse Web API. This function supports append-only operations and does NOT
    provide update or delete capabilities. Each validation run creates a new set of records
    linked by a common RunId GUID.

    Records capture the state of configuration at a specific point in time, with severity
    ratings, remediation guidance, and optional environment context.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER AccessToken
    Bearer token for Dataverse Web API authentication. Obtain via Connect-PowerPlatform.

.PARAMETER RunId
    GUID linking all validation records in a single validation run. Use the same RunId
    for all records generated during one execution.

.PARAMETER Scope
    Validation scope: Tenant-level or Environment-level checks.

.PARAMETER Severity
    Validation result severity rating.

.PARAMETER ValidationType
    Type of validation performed (e.g., "UnifiedAuditLog", "EnvironmentAudit",
    "RetentionPolicy", "MailboxAudit").

.PARAMETER RawValue
    Actual configuration values checked. Serialized JSON for complex objects.

.PARAMETER Reason
    Human-readable explanation of the validation result. Describes what was checked
    and why the result was generated.

.PARAMETER Zone
    Governance zone classification (optional, for environment-scoped validations).

.PARAMETER EnvironmentId
    Power Platform environment GUID (optional, for environment-scoped validations).

.PARAMETER EnvironmentName
    Power Platform environment display name (optional, for environment-scoped validations).

.PARAMETER RemediationHint
    Guidance for resolving issues (optional). PowerShell commands, portal steps, or
    documentation links to help administrators address findings.

.PARAMETER CheckCount
    Number of sub-checks performed in this validation (optional). Useful for aggregated
    validations that combine multiple checks.

.EXAMPLE
    Write-ValidationResult `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -RunId $runId `
        -Scope "Tenant" `
        -Severity "Passed" `
        -ValidationType "UnifiedAuditLog" `
        -RawValue "UnifiedAuditLogIngestionEnabled=True" `
        -Reason "Unified Audit Log is enabled tenant-wide." `
        -RemediationHint "No action required."

    Creates a tenant-level validation record with Passed severity.

.EXAMPLE
    Write-ValidationResult `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AccessToken $token `
        -RunId $runId `
        -Scope "Environment" `
        -Severity "Failed" `
        -ValidationType "EnvironmentAudit" `
        -RawValue "EnvironmentAuditSettings.IsEnabled=False" `
        -Reason "Environment audit logging is disabled." `
        -Zone "Zone2" `
        -EnvironmentId "12345-guid" `
        -EnvironmentName "Sales Production" `
        -RemediationHint "Enable audit via Admin Center > Environments > Settings > Audit"

    Creates an environment-level validation record with Failed severity.

.NOTES
    Version: 1.0.2
    This function only creates records (append-only). No update or delete operations are supported.

    Option set mappings (MUST match Dataverse schema):
    - fsi_acv_severity: Passed=100000000, Warning=100000001, GracePeriod=100000002, Failed=100000003, Error=100000004
    - fsi_acv_scope: Tenant=100000000, Environment=100000001
    - fsi_acv_zone: Unclassified=100000000, Zone1=100000001, Zone2=100000002, Zone3=100000003

.OUTPUTS
    String (GUID) - The created record ID on success. Throws on failure.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $true)]
    [string]$AccessToken,

    [Parameter(Mandatory = $true)]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Tenant", "Environment")]
    [string]$Scope,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Passed", "Warning", "GracePeriod", "Failed", "Error")]
    [string]$Severity,

    [Parameter(Mandatory = $true)]
    [string]$ValidationType,

    [Parameter(Mandatory = $true)]
    [string]$RawValue,

    [Parameter(Mandatory = $true)]
    [string]$Reason,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Unclassified", "Zone1", "Zone2", "Zone3")]
    [string]$Zone,

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName,

    [Parameter(Mandatory = $false)]
    [string]$RemediationHint,

    [Parameter(Mandatory = $false)]
    [int]$CheckCount
)

$ErrorActionPreference = "Stop"

function Write-ValidationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataverseUrl,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Tenant", "Environment")]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Passed", "Warning", "GracePeriod", "Failed", "Error")]
        [string]$Severity,

        [Parameter(Mandatory = $true)]
        [string]$ValidationType,

        [Parameter(Mandatory = $true)]
        [string]$RawValue,

        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Unclassified", "Zone1", "Zone2", "Zone3")]
        [string]$Zone,

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentId,

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentName,

        [Parameter(Mandatory = $false)]
        [string]$RemediationHint,

        [Parameter(Mandatory = $false)]
        [int]$CheckCount
    )

    try {
        # Normalize Dataverse URL (remove trailing slash)
        $DataverseUrl = $DataverseUrl.TrimEnd('/')

        # Map string parameters to option set integer values
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

        $zoneMap = @{
            "Unclassified" = 100000000
            "Zone1"        = 100000001
            "Zone2"        = 100000002
            "Zone3"        = 100000003
        }

        # Build record name
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
        $recordName = if ($Scope -eq "Tenant") {
            "TENANT-$timestamp"
        }
        else {
            $envNameSafe = if ($EnvironmentName) { $EnvironmentName.Replace(' ', '-') } else { "Unknown" }
            "ENV-$envNameSafe-$timestamp"
        }

        # Build JSON body with fsi_ prefixed field names
        $body = @{
            fsi_name           = $recordName
            fsi_runid          = $RunId
            fsi_scope          = $scopeMap[$Scope]
            fsi_severity       = $severityMap[$Severity]
            fsi_validationtype = $ValidationType
            fsi_rawvalue       = $RawValue
            fsi_reason         = $Reason
            fsi_timestamp      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }

        # Add optional fields
        if ($Zone) {
            $body.fsi_zone = $zoneMap[$Zone]
        }

        if ($EnvironmentId) {
            $body.fsi_environmentid = $EnvironmentId
        }

        if ($EnvironmentName) {
            $body.fsi_environmentname = $EnvironmentName
        }

        if ($RemediationHint) {
            $body.fsi_remediationhint = $RemediationHint
        }

        if ($PSBoundParameters.ContainsKey('CheckCount')) {
            $body.fsi_checkcount = $CheckCount
        }

        # Convert to JSON
        $jsonBody = $body | ConvertTo-Json -Depth 10

        # Construct API endpoint
        $apiUrl = "$DataverseUrl/api/data/v9.2/fsi_auditvalidationhistories"

        # Prepare headers
        $headers = @{
            "Authorization"    = "Bearer $AccessToken"
            "Content-Type"     = "application/json"
            "OData-MaxVersion" = "4.0"
            "OData-Version"    = "4.0"
        }

        # POST request to create record
        $response = Invoke-RestMethod `
            -Uri $apiUrl `
            -Method Post `
            -Headers $headers `
            -Body $jsonBody `
            -ErrorAction Stop

        # Extract created record ID from response headers or body
        # Dataverse returns the ID in the OData-EntityId header
        $recordId = $response.'@odata.context' -replace '.*\(([^)]+)\).*', '$1'
        if (-not $recordId) {
            # Fallback: extract from response if available
            $recordId = $response.fsi_auditvalidationhistoryid
        }

        Write-Verbose "Created validation result record: $recordId"
        return $recordId
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $responseBody = $_.ErrorDetails.Message

        throw "Failed to write validation result to Dataverse. Status: $statusCode, Response: $responseBody, Error: $($_.Exception.Message)"
    }
}

# Execute function if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $recordId = Write-ValidationResult @PSBoundParameters
    Write-Host "Record created: $recordId" -ForegroundColor Green
    return $recordId
}

# Note: This script is dot-sourced; do not use Export-ModuleMember outside a .psm1 module.
