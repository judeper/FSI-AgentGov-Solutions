#Requires -Version 7.2

<#
.SYNOPSIS
    Shared helper module for Audit Logging Compliance Automation (ALCA) runbooks.

.DESCRIPTION
    Provides common functions used by both the detection (Test-AuditLoggingCompliance)
    and remediation (Enable-AuditLogging) runbooks. All functions use Managed Identity
    authentication — NEVER interactive auth or hardcoded credentials.

    Functions:
    - Invoke-WithRetry: Exponential backoff with jitter for transient errors
    - Get-ManagedIdentityToken: Azure Automation MI token acquisition
    - Get-DataverseToken: Dataverse-specific token with URL normalization
    - Invoke-DataverseRequest: Web API wrapper with OData headers and retry
    - Write-DataverseComplianceRecord: Upsert compliance record by environment ID
    - Send-ComplianceNotification: Graph sendMail via shared mailbox

.NOTES
    Version: 1.0.2
    Requires: PowerShell 7.2+, Azure Automation with System-Assigned Managed Identity
#>

# --- Status Option Set Mapping ---

$script:ComplianceStatusMap = @{
    'Compliant'          = 100000000
    'Non-Compliant'      = 100000001
    'Remediation Pending' = 100000002
    'Error'              = 100000003
}

$script:ComplianceStatusReverseMap = @{
    100000000 = 'Compliant'
    100000001 = 'Non-Compliant'
    100000002 = 'Remediation Pending'
    100000003 = 'Error'
}

# --- Invoke-WithRetry ---

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes a script block with exponential backoff and jitter for transient errors.

    .DESCRIPTION
        Retries on HTTP 429 (throttled), 503 (service unavailable), and 504 (gateway timeout).
        Uses exponential backoff with random jitter to avoid thundering herd.
        Non-retryable errors (4xx except 429) are thrown immediately.

    .PARAMETER ScriptBlock
        The script block to execute.

    .PARAMETER MaxRetries
        Maximum number of retry attempts. Default: 3.

    .PARAMETER InitialDelaySeconds
        Initial delay before first retry in seconds. Default: 2.

    .PARAMETER MaxDelaySeconds
        Maximum delay between retries in seconds. Default: 30.

    .PARAMETER OperationName
        Human-readable name for logging. Default: "Operation".

    .EXAMPLE
        Invoke-WithRetry -ScriptBlock { Invoke-RestMethod -Uri $uri } -MaxRetries 5

    .OUTPUTS
        The result of the script block execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory = $false)]
        [int]$InitialDelaySeconds = 2,

        [Parameter(Mandatory = $false)]
        [int]$MaxDelaySeconds = 30,

        [Parameter(Mandatory = $false)]
        [string]$OperationName = "Operation"
    )

    $retryableStatusCodes = @(429, 503, 504)
    $attempt = 0

    while ($true) {
        $attempt++
        try {
            $result = & $ScriptBlock
            return $result
        }
        catch {
            $statusCode = $null

            # Extract HTTP status code from various exception types
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            elseif ($_.Exception.Message -match '\b([4-5]\d{2})\b') {
                $candidateCode = [int]$Matches[1]
                if ($candidateCode -ge 400 -and $candidateCode -le 599) {
                    $statusCode = $candidateCode
                }
            }

            $isRetryable = ($statusCode -and $statusCode -in $retryableStatusCodes)

            if (-not $isRetryable -or $attempt -gt $MaxRetries) {
                Write-Verbose "$OperationName failed after $attempt attempt(s): $($_.Exception.Message)"
                throw
            }

            # Exponential backoff with jitter
            $baseDelay = [Math]::Min($InitialDelaySeconds * [Math]::Pow(2, ($attempt - 1)), $MaxDelaySeconds)
            $jitter = Get-Random -Minimum 0.0 -Maximum ($baseDelay * 0.5)
            $delay = $baseDelay + $jitter

            Write-Verbose "$OperationName attempt $attempt/$MaxRetries failed (HTTP $statusCode). Retrying in $([Math]::Round($delay, 1))s..."
            Start-Sleep -Seconds $delay
        }
    }
}

# --- Get-ManagedIdentityToken ---

function Get-ManagedIdentityToken {
    <#
    .SYNOPSIS
        Acquires an access token using Azure Automation System-Assigned Managed Identity.

    .DESCRIPTION
        Uses the IDENTITY_ENDPOINT and IDENTITY_HEADER environment variables available
        in Azure Automation to acquire a token for the specified resource. This function
        NEVER uses interactive authentication or hardcoded credentials.

    .PARAMETER Resource
        The resource URI to acquire a token for.
        Example: "https://graph.microsoft.com"

    .EXAMPLE
        $token = Get-ManagedIdentityToken -Resource "https://graph.microsoft.com"

    .OUTPUTS
        [string] The access token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Resource
    )

    $endpoint = $env:IDENTITY_ENDPOINT
    $header = $env:IDENTITY_HEADER

    if (-not $endpoint -or -not $header) {
        throw "Managed Identity environment variables not found. This function must run in Azure Automation with System-Assigned MI enabled."
    }

    $uri = "${endpoint}?resource=${Resource}&api-version=2019-08-01"

    $tokenResponse = Invoke-WithRetry -ScriptBlock {
        Invoke-RestMethod -Uri $uri -Method GET -Headers @{
            "X-IDENTITY-HEADER" = $header
            "Metadata"          = "true"
        } -ErrorAction Stop
    } -OperationName "Get-ManagedIdentityToken ($Resource)" -MaxRetries 3

    if (-not $tokenResponse.access_token) {
        throw "Failed to acquire Managed Identity token for resource: $Resource"
    }

    return $tokenResponse.access_token
}

# --- Get-DataverseToken ---

function Get-DataverseToken {
    <#
    .SYNOPSIS
        Acquires a Dataverse-specific access token via Managed Identity.

    .DESCRIPTION
        Normalizes the Dataverse environment URL and acquires a token scoped to
        that Dataverse instance. Handles trailing slash normalization.

    .PARAMETER DataverseEnvironmentUrl
        The Dataverse environment URL. Trailing slashes are normalized.
        Example: "https://org.crm.dynamics.com" or "https://org.crm.dynamics.com/"

    .EXAMPLE
        $token = Get-DataverseToken -DataverseEnvironmentUrl "https://org.crm.dynamics.com"

    .OUTPUTS
        [string] The Dataverse access token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataverseEnvironmentUrl
    )

    # Normalize URL — remove trailing slash for consistent resource URI
    $normalizedUrl = $DataverseEnvironmentUrl.TrimEnd('/')

    $token = Get-ManagedIdentityToken -Resource $normalizedUrl

    return $token
}

# --- Invoke-DataverseRequest ---

function Invoke-DataverseRequest {
    <#
    .SYNOPSIS
        Executes a Dataverse Web API request with OData headers and retry logic.

    .DESCRIPTION
        Wrapper around Invoke-RestMethod that adds required OData headers for
        Dataverse Web API, handles authentication via bearer token, and retries
        on transient errors. Supports GET, POST, PATCH, DELETE, and PUT methods.

    .PARAMETER EnvironmentUrl
        The Dataverse environment URL.

    .PARAMETER RelativeUri
        The API path relative to the environment URL.
        Example: "/api/data/v9.2/fsi_auditenvironmentcompliances"

    .PARAMETER Token
        The bearer token for authentication.

    .PARAMETER Method
        HTTP method. Default: GET.

    .PARAMETER Body
        Request body for POST/PATCH/PUT. Will be converted to JSON if a hashtable.

    .PARAMETER MaxRetries
        Maximum retry attempts. Default: 3.

    .EXAMPLE
        $result = Invoke-DataverseRequest -EnvironmentUrl $url -RelativeUri "/api/data/v9.2/organizations" -Token $token

    .OUTPUTS
        The response object from the Dataverse Web API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentUrl,

        [Parameter(Mandatory = $true)]
        [string]$RelativeUri,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $false)]
        [ValidateSet("GET", "POST", "PATCH", "DELETE", "PUT")]
        [string]$Method = "GET",

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3
    )

    $baseUrl = $EnvironmentUrl.TrimEnd('/')
    $fullUri = "${baseUrl}${RelativeUri}"

    $headers = @{
        "Authorization" = "Bearer $Token"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
        "Accept"           = "application/json"
        "Content-Type"     = "application/json; charset=utf-8"
        "Prefer"           = "return=representation"
    }

    $params = @{
        Uri     = $fullUri
        Method  = $Method
        Headers = $headers
        ErrorAction = "Stop"
    }

    if ($Body) {
        if ($Body -is [hashtable] -or $Body -is [System.Collections.Specialized.OrderedDictionary]) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
        }
        else {
            $params.Body = $Body
        }
    }

    $result = Invoke-WithRetry -ScriptBlock {
        Invoke-RestMethod @params -Verbose:$false
    } -OperationName "Dataverse $Method $RelativeUri" -MaxRetries $MaxRetries

    return $result
}

# --- Write-DataverseComplianceRecord ---

function Write-DataverseComplianceRecord {
    <#
    .SYNOPSIS
        Upserts a compliance record in the fsi_auditenvironmentcompliance table.

    .DESCRIPTION
        Queries Dataverse for an existing record matching the environment ID. If found,
        updates it (PATCH). If not found, creates a new record (POST). This implements
        the upsert pattern — one compliance record per environment.

        Status strings are mapped to Dataverse option set values:
        - Compliant = 100000000
        - Non-Compliant = 100000001
        - Remediation Pending = 100000002
        - Error = 100000003

    .PARAMETER EnvironmentUrl
        The Dataverse environment URL hosting the compliance table.

    .PARAMETER Token
        The bearer token for Dataverse authentication.

    .PARAMETER EnvironmentId
        The Power Platform environment GUID (upsert key).

    .PARAMETER EnvironmentName
        The display name of the environment.

    .PARAMETER AuditEnabled
        Whether Purview unified audit is enabled.

    .PARAMETER DataverseAuditEnabled
        Whether Dataverse auditing is enabled.

    .PARAMETER ComplianceStatus
        Status string: "Compliant", "Non-Compliant", "Remediation Pending", or "Error".

    .PARAMETER ErrorMessage
        Optional error message for Error status.

    .PARAMETER RemediatedBy
        Optional identifier of who/what performed remediation.

    .PARAMETER LastEventCaptured
        Optional DateTime of the most recent audit event.

    .EXAMPLE
        Write-DataverseComplianceRecord -EnvironmentUrl $url -Token $token `
            -EnvironmentId "abc-123" -EnvironmentName "Production" `
            -AuditEnabled $true -DataverseAuditEnabled $true `
            -ComplianceStatus "Compliant"

    .OUTPUTS
        The Dataverse response object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentUrl,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$EnvironmentId,

        [Parameter(Mandatory = $true)]
        [string]$EnvironmentName,

        [Parameter(Mandatory = $true)]
        [bool]$AuditEnabled,

        [Parameter(Mandatory = $true)]
        [bool]$DataverseAuditEnabled,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Compliant", "Non-Compliant", "Remediation Pending", "Error")]
        [string]$ComplianceStatus,

        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage,

        [Parameter(Mandatory = $false)]
        [string]$RemediatedBy,

        [Parameter(Mandatory = $false)]
        [datetime]$LastEventCaptured
    )

    # Map status string to option set value
    $statusValue = $script:ComplianceStatusMap[$ComplianceStatus]
    if ($null -eq $statusValue) {
        throw "Invalid ComplianceStatus: $ComplianceStatus. Valid values: $($script:ComplianceStatusMap.Keys -join ', ')"
    }

    # Build record payload
    $record = @{
        fsi_environmentid        = $EnvironmentId
        fsi_environmentname      = $EnvironmentName
        fsi_auditenabled         = $AuditEnabled
        fsi_dataverseauditenabled = $DataverseAuditEnabled
        fsi_lastchecked          = (Get-Date -AsUTC -Format "o")
        fsi_compliancestatus     = $statusValue
    }

    if ($ErrorMessage) {
        $record.fsi_errormessage = $ErrorMessage
    }

    if ($RemediatedBy) {
        $record.fsi_remediatedby = $RemediatedBy
        $record.fsi_remediationdate = (Get-Date -AsUTC -Format "o")
    }

    if ($LastEventCaptured) {
        $record.fsi_lasteventcaptured = $LastEventCaptured.ToUniversalTime().ToString("o")
    }

    # Upsert compliance record using Dataverse alternate key on fsi_environmentid
    $upsertUri = "/api/data/v9.2/fsi_auditenvironmentcompliances(fsi_environmentid='$EnvironmentId')"

    try {
        Write-Verbose "Upserting compliance record for environment $EnvironmentId"
        $result = Invoke-DataverseRequest -EnvironmentUrl $EnvironmentUrl -RelativeUri $upsertUri -Token $Token -Method PATCH -Body $record

        return $result
    }
    catch {
        Write-Verbose "Failed to write compliance record for $EnvironmentId : $($_.Exception.Message)"
        throw
    }
}

# --- Send-ComplianceNotification ---

function Send-ComplianceNotification {
    <#
    .SYNOPSIS
        Sends an email notification via Microsoft Graph using a shared mailbox.

    .DESCRIPTION
        Uses the Graph API sendMail endpoint to send compliance notification emails.
        Authenticates via Managed Identity (Mail.Send application permission).
        Supports base64-encoded file attachments (e.g., CSV reports).

    .PARAMETER FromAddress
        The shared mailbox email address to send from.

    .PARAMETER ToAddresses
        Array of recipient email addresses.

    .PARAMETER Subject
        Email subject line.

    .PARAMETER HtmlBody
        HTML-formatted email body.

    .PARAMETER AttachmentPath
        Optional path to a file to attach (e.g., CSV export).

    .PARAMETER AttachmentName
        Display name for the attachment. Defaults to the file name.

    .EXAMPLE
        Send-ComplianceNotification -FromAddress "governance@example.com" `
            -ToAddresses @("admin@example.com") `
            -Subject "Audit Compliance Report" `
            -HtmlBody "<h1>Report</h1>" `
            -AttachmentPath "C:\temp\report.csv"

    .OUTPUTS
        None. Throws on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FromAddress,

        [Parameter(Mandatory = $true)]
        [string[]]$ToAddresses,

        [Parameter(Mandatory = $true)]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [string]$HtmlBody,

        [Parameter(Mandatory = $false)]
        [string]$AttachmentPath,

        [Parameter(Mandatory = $false)]
        [string]$AttachmentName
    )

    # Acquire Graph token via Managed Identity
    $graphToken = Get-ManagedIdentityToken -Resource "https://graph.microsoft.com"

    # Build recipient list
    $toRecipients = $ToAddresses | ForEach-Object {
        @{
            emailAddress = @{
                address = $_
            }
        }
    }

    # Build message payload
    $message = @{
        message = @{
            subject = $Subject
            body    = @{
                contentType = "HTML"
                content     = $HtmlBody
            }
            toRecipients = @($toRecipients)
        }
        saveToSentItems = $false
    }

    # Add attachment if provided
    if ($AttachmentPath -and (Test-Path $AttachmentPath)) {
        $fileBytes = [System.IO.File]::ReadAllBytes($AttachmentPath)
        $base64Content = [System.Convert]::ToBase64String($fileBytes)

        $fileName = if ($AttachmentName) { $AttachmentName } else { [System.IO.Path]::GetFileName($AttachmentPath) }

        $message.message.attachments = @(
            @{
                "@odata.type"  = "#microsoft.graph.fileAttachment"
                name           = $fileName
                contentType    = "application/octet-stream"
                contentBytes   = $base64Content
            }
        )
    }

    $sendUri = "https://graph.microsoft.com/v1.0/users/$FromAddress/sendMail"
    $jsonBody = $message | ConvertTo-Json -Depth 10

    Invoke-WithRetry -ScriptBlock {
        Invoke-RestMethod -Uri $sendUri -Method POST -Headers @{
            "Authorization" = "Bearer $graphToken"
            "Content-Type"  = "application/json"
        } -Body $jsonBody -ErrorAction Stop
    } -OperationName "Send-ComplianceNotification" -MaxRetries 3

    Write-Verbose "Compliance notification sent to $($ToAddresses -join ', ')"
}

# --- Module Exports ---

Export-ModuleMember -Function @(
    'Invoke-WithRetry',
    'Get-ManagedIdentityToken',
    'Get-DataverseToken',
    'Invoke-DataverseRequest',
    'Write-DataverseComplianceRecord',
    'Send-ComplianceNotification'
)

Export-ModuleMember -Variable @(
    'ComplianceStatusMap',
    'ComplianceStatusReverseMap'
)
