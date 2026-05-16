<#
.SYNOPSIS
    Shared helpers for Message Center Monitor governance scripts.

.DESCRIPTION
    Dot-sourced by Invoke-MessageCenterSync.ps1, Get-MessageCenterAssessmentStatus.ps1,
    and Export-MessageCenterEvidence.ps1. Provides:

      - Get-McmAccessToken     : managed-identity-first token acquisition.
      - Get-McmDvHeaders       : cached Dataverse headers with proactive refresh.
      - Invoke-McmRest         : retry-aware REST wrapper honouring Retry-After.
      - Format-McmODataLiteral : single-quote OData literal escape helper.
      - Format-McmODataDate    : ISO-8601 round-trip Dataverse date formatter.

    All callers should run with Set-StrictMode and ErrorActionPreference=Stop.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module-scope token cache: one entry per (scope) string.
$script:McmTokenCache = @{}

function Get-McmAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ManagedIdentity', 'WorkloadIdentity', 'Interactive', 'DeviceCode', 'ClientSecret')]
        [string]$AuthMode,

        [Parameter(Mandatory)]
        [string]$Scope,

        [string]$TenantId,
        [string]$ClientId,
        [SecureString]$ClientSecret
    )

    Import-Module MSAL.PS -ErrorAction Stop

    switch ($AuthMode) {
        'ManagedIdentity' {
            # Managed-identity support added in MSAL.PS 4.37.
            $msal = Get-Module MSAL.PS
            if (-not $msal -or $msal.Version -lt [Version]'4.37.0.0') {
                throw "MSAL.PS 4.37.0 or later is required for -AuthMode ManagedIdentity. Installed: $($msal.Version). Run: Install-Module MSAL.PS -MinimumVersion 4.37.0 -Scope CurrentUser -Force"
            }
            # Resource form (no /.default) is what the IMDS endpoint expects.
            $resource = $Scope -replace '/\.default$', ''
            return Get-MsalToken -ManagedIdentity -Resource $resource
        }
        'WorkloadIdentity' {
            # Workload identity federation (GitHub Actions OIDC, Azure DevOps OIDC, etc.).
            # Exchanges a federated token for a Microsoft Entra ID access token.
            if (-not $ClientId) { throw "ClientId is required for WorkloadIdentity auth." }
            if (-not $TenantId) { throw "TenantId is required for WorkloadIdentity auth." }

            # Resolve the federated token from one of three standard locations.
            $federatedToken = $null
            if ($env:AZURE_FEDERATED_TOKEN) {
                $federatedToken = $env:AZURE_FEDERATED_TOKEN
            }
            elseif ($env:AZURE_FEDERATED_TOKEN_FILE -and (Test-Path -LiteralPath $env:AZURE_FEDERATED_TOKEN_FILE)) {
                $federatedToken = (Get-Content -LiteralPath $env:AZURE_FEDERATED_TOKEN_FILE -Raw).Trim()
            }
            elseif ($env:ACTIONS_ID_TOKEN_REQUEST_URL -and $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN) {
                # GitHub Actions OIDC: request a token scoped to api://AzureADTokenExchange
                $reqUri = "$($env:ACTIONS_ID_TOKEN_REQUEST_URL)&audience=api://AzureADTokenExchange"
                $reqHeaders = @{ Authorization = "Bearer $($env:ACTIONS_ID_TOKEN_REQUEST_TOKEN)" }
                $resp = Invoke-RestMethod -Uri $reqUri -Headers $reqHeaders -Method Get
                $federatedToken = $resp.value
            }
            else {
                throw "WorkloadIdentity auth requires one of: `$env:AZURE_FEDERATED_TOKEN, `$env:AZURE_FEDERATED_TOKEN_FILE, or GitHub Actions OIDC env vars (ACTIONS_ID_TOKEN_REQUEST_URL + ACTIONS_ID_TOKEN_REQUEST_TOKEN)."
            }

            return Get-MsalToken -TenantId $TenantId -ClientId $ClientId -ClientAssertion $federatedToken -Scopes @($Scope)
        }
        'Interactive' {
            if (-not $ClientId) { throw "ClientId is required for Interactive auth." }
            if (-not $TenantId) { throw "TenantId is required for Interactive auth." }
            return Get-MsalToken -ClientId $ClientId -TenantId $TenantId -Interactive -Scopes @($Scope)
        }
        'DeviceCode' {
            if (-not $ClientId) { throw "ClientId is required for DeviceCode auth." }
            if (-not $TenantId) { throw "TenantId is required for DeviceCode auth." }
            return Get-MsalToken -ClientId $ClientId -TenantId $TenantId -DeviceCode -Scopes @($Scope)
        }
        'ClientSecret' {
            # legacy: dev-only — replace with managed identity in production
            if (-not $ClientId) { throw "ClientId is required for ClientSecret auth." }
            if (-not $TenantId) { throw "TenantId is required for ClientSecret auth." }
            if (-not $ClientSecret) { throw "ClientSecret is required for -AuthMode ClientSecret." }
            return Get-MsalToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scopes @($Scope)
        }
    }
}

function Get-McmDvHeaders {
    <#
    .SYNOPSIS
        Returns Dataverse REST headers with a cached, auto-refreshing token.

    .DESCRIPTION
        Re-acquires the token when within 5 minutes of expiry. Safe to call once
        per per-message iteration in long-running sync loops.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ManagedIdentity', 'WorkloadIdentity', 'Interactive', 'DeviceCode', 'ClientSecret')]
        [string]$AuthMode,

        [Parameter(Mandatory)]
        [string]$Scope,

        [string]$TenantId,
        [string]$ClientId,
        [SecureString]$ClientSecret,

        [hashtable]$ExtraHeaders
    )

    $cached = $null
    if ($script:McmTokenCache.ContainsKey($Scope)) {
        $cached = $script:McmTokenCache[$Scope]
    }

    $needsRefresh = $true
    if ($cached -and $cached.ExpiresOn) {
        $threshold = (Get-Date).ToUniversalTime().AddMinutes(5)
        if ($cached.ExpiresOn.UtcDateTime -gt $threshold) {
            $needsRefresh = $false
        } else {
            Write-Verbose "Token within 5 minutes of expiry; refreshing."
        }
    }

    if ($needsRefresh) {
        $cached = Get-McmAccessToken -AuthMode $AuthMode -Scope $Scope `
            -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
        $script:McmTokenCache[$Scope] = $cached
    }

    $headers = @{
        Authorization      = "Bearer $($cached.AccessToken)"
        'Content-Type'     = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }
    if ($ExtraHeaders) {
        foreach ($k in $ExtraHeaders.Keys) { $headers[$k] = $ExtraHeaders[$k] }
    }
    return $headers
}

function Format-McmSafeUri {
    <#
    .SYNOPSIS
        Returns a log-safe representation of a URI, redacting bearer-credential paths and queries.

    .DESCRIPTION
        Teams Workflows incoming webhook URLs, Logic Apps shared-access signature URLs, and
        any URL with a `sig=` or `code=` query parameter carry the *credential* in the URL
        itself. If Invoke-McmRest logs or throws the raw URI on failure, a transient
        4xx/5xx response will leak the webhook bearer secret into console output, scheduled-
        run logs, and any Application Insights / Log Analytics pipeline downstream.

        This helper rewrites such URIs as `<scheme>://<host>/<redacted>` BEFORE they reach
        any log sink. Dataverse and Microsoft Graph URLs are returned unchanged so legitimate
        troubleshooting (which entity set, which $filter) is not impaired.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Uri)

    if ([string]::IsNullOrEmpty($Uri)) { return '' }

    try {
        $u = [uri]$Uri
        # Relative URIs accept any string via cast but throw on .Host / .Scheme
        # property access. Treat them as unparseable for safe-logging purposes.
        if (-not $u.IsAbsoluteUri) { return '<unparseable-uri>' }
    } catch {
        return '<unparseable-uri>'
    }

    $hostLc = $u.Host.ToLowerInvariant()
    $isBearerUrl = (
        $hostLc -like '*.logic.azure.com' -or
        $hostLc -like '*.azure-apim.net' -or
        $hostLc -like '*.webhook.office.com' -or
        $hostLc -eq  'webhook.office.com' -or
        $u.Query -match '[?&]sig='   -or
        $u.Query -match '[?&]code='
    )

    if ($isBearerUrl) {
        return ('{0}://{1}/<redacted>' -f $u.Scheme, $u.Host)
    }

    return $Uri
}

function Format-McmSafeErrorBody {
    <#
    .SYNOPSIS
        Returns a log-safe representation of an HTTP error response body, scrubbing
        bearer-credential query parameters.

    .DESCRIPTION
        Even after Invoke-McmRest's URI argument is redacted via Format-McmSafeUri,
        some APIs echo the original request URL inside the error response body
        (e.g. "Request to https://prod-XX.westus.logic.azure.com/.../triggers/.../paths/invoke?sig=ABC123 failed").
        Logging the raw body would re-leak the bearer credential the URI redaction
        was meant to suppress.

        This helper performs a defense-in-depth scrub: it rewrites any sig=...
        and code=... query parameter value to <redacted>, regardless of the URL
        host. This preserves all other diagnostic value (status code, error
        message text, field-level validation errors) while preventing credential
        leak through this alternate path.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string]$Body)

    if ([string]::IsNullOrEmpty($Body)) { return '' }

    return ($Body -replace '(?i)(sig|code)=[^&\s"''>]+', '$1=<redacted>')
}

function Invoke-McmRest {
    <#
    .SYNOPSIS
        Throttling-aware REST wrapper for Graph and Dataverse.

    .DESCRIPTION
        Honors Retry-After (seconds or HTTP-date) on 429/503; otherwise applies
        exponential backoff capped at 60 seconds. Throws on terminal failure with
        a structured error containing status code and response body when available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [hashtable]$Headers,
        [Parameter(Mandatory)] [string]$Method,
        [string]$Body,
        [int]$MaxRetries = 5,
        [int]$BaseDelaySeconds = 2,
        [int]$MaxDelaySeconds = 60
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($PSBoundParameters.ContainsKey('Body') -and $Body) {
                return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body $Body
            } else {
                return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method
            }
        }
        catch {
            $status = $null
            try { $status = [int]$_.Exception.Response.StatusCode } catch {}

            $isRetryable = ($status -eq 429 -or ($status -ge 500 -and $status -le 599))
            if ($isRetryable -and $attempt -le $MaxRetries) {
                $retryAfter = 0
                try {
                    # PS 7+ throws HttpResponseException whose .Headers is
                    # HttpResponseHeaders. String indexing returns $null, so
                    # use TryGetValues and fall back to PS 5.1 dictionary access.
                    $hdrs = $_.Exception.Response.Headers
                    $values = $null
                    if ($hdrs -and $hdrs.GetType().GetMethod('TryGetValues')) {
                        if ($hdrs.TryGetValues('Retry-After', [ref]$values)) {
                            $retryAfter = [int]([System.Linq.Enumerable]::FirstOrDefault($values))
                        }
                    } elseif ($hdrs) {
                        $hdr = $hdrs['Retry-After']
                        if ($hdr) { $retryAfter = [int]$hdr }
                    }
                } catch {}
                if ($retryAfter -le 0) {
                    $retryAfter = [Math]::Min($MaxDelaySeconds, $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1))
                }
                Write-Warning "  Throttled ($status). Sleeping $retryAfter s (attempt $attempt/$MaxRetries)..."
                Start-Sleep -Seconds $retryAfter
                continue
            }

            $body = $null
            try {
                if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                    $body = $_.ErrorDetails.Message
                }
            } catch {}
            $msg = "Invoke-McmRest failed: status=$status method=$Method uri=$(Format-McmSafeUri $Uri) error=$($_.Exception.Message)"
            if ($body) { $msg += " body=$(Format-McmSafeErrorBody $body)" }
            throw $msg
        }
    }
}

function Invoke-McmDvUpsertMessage {
    <#
    .SYNOPSIS
        Upserts a Message Center record into Dataverse, preserving admin-owned assessment fields.

    .DESCRIPTION
        Implements the conditional create -> 412 -> update branching that protects
        admin-owned columns (fsi_assessmentstatus, fsi_assessment, fsi_assessedby,
        fsi_assesseddate, fsi_actionstaken, fsi_impactsagents, fsi_notifiedon) from
        being clobbered on subsequent syncs.

        Step 1: PATCH with `If-None-Match: *` (create-only). On HTTP 201 the row is
                created with fsi_assessmentstatus = NotAssessed.
        Step 2: On HTTP 412 the row exists. Issue a second PATCH WITHOUT
                If-None-Match and WITHOUT any admin-owned columns. The caller MUST
                ensure $Record excludes admin-owned columns (the function enforces
                this contract by adding only fsi_assessmentstatus to the create
                payload, never to the update payload).
        404:    Alternate key not provisioned -> throws with actionable hint.

        Extracted from Invoke-MessageCenterSync.ps1 in v2.4.0 to make C1 branching
        unit-testable. No behavioural change.

    .PARAMETER DataverseBaseUrl
        Dataverse Web API base URL (e.g. https://org.crm.dynamics.com/api/data/v9.2).

    .PARAMETER MessageId
        The Message Center post id (used as the alternate-key value).

    .PARAMETER Record
        Hashtable of Graph-owned columns to write. MUST NOT include admin-owned
        columns. Caller is responsible for honoring this contract; see
        Guards.Tests.ps1 for the static check.

    .PARAMETER DataverseHeaders
        Dataverse REST headers (Authorization, Content-Type, OData-* etc.).

    .PARAMETER AssessmentNotAssessedValue
        Integer choice value for "NotAssessed" status. Provided by the caller so
        this function stays free of solution-specific constants.

    .OUTPUTS
        [pscustomobject] with properties:
          - Action       : 'Created' or 'Updated'
          - MessageId    : the Message Center post id (string, as supplied)
          - EntityId     : the Dataverse row primary-key GUID (string, or
                           $null if the caller did not set
                           Prefer: return=representation in $DataverseHeaders,
                           or the response did not include
                           fsi_messagecenterlogid)
          - ResponseBody : the parsed Dataverse response body (or $null when
                           Prefer: return=representation is absent); callers
                           can read additional columns such as fsi_notifiedon
                           for idempotent notification logic

    .NOTES
        On terminal failure throws a descriptive message; caller catches and
        increments its own failed counter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$DataverseBaseUrl,
        [Parameter(Mandatory)] [string]$MessageId,
        [Parameter(Mandatory)] [hashtable]$Record,
        [Parameter(Mandatory)] [hashtable]$DataverseHeaders,
        [Parameter(Mandatory)] [int]$AssessmentNotAssessedValue
    )

    $escapedId = Format-McmODataLiteral $MessageId
    $upsertUrl = "$DataverseBaseUrl/fsi_messagecenterlogs(fsi_messagecenterid='$escapedId')"

    # Create-only payload: clone $Record then ADD fsi_assessmentstatus.
    # The original $Record is never mutated and is reused verbatim for the
    # update branch, guaranteeing admin-owned columns are never sent on update.
    $createPayload = $Record.Clone()
    $createPayload['fsi_assessmentstatus'] = $AssessmentNotAssessedValue

    $createHeaders = @{}
    foreach ($k in $DataverseHeaders.Keys) { $createHeaders[$k] = $DataverseHeaders[$k] }
    $createHeaders['If-None-Match'] = '*'

    $existed = $false
    try {
        # Capture the response body. Callers that set the Prefer:
        # return=representation header on $DataverseHeaders (the sync script
        # does) receive the full Dataverse row back, including the row's
        # fsi_messagecenterlogid primary-key GUID and any admin-owned
        # columns (e.g. fsi_notifiedon) that already exist on the row.
        # Callers without that Prefer header (or mocks) receive $null —
        # ResponseBody is then $null and EntityId resolves to $null.
        $resp = Invoke-McmRest -Uri $upsertUrl -Headers $createHeaders -Method Patch `
            -Body ($createPayload | ConvertTo-Json -Depth 5)
        $entityId = $null
        if ($resp -and ($resp.PSObject.Properties.Name -contains 'fsi_messagecenterlogid')) {
            $entityId = [string]$resp.fsi_messagecenterlogid
        }
        return [pscustomobject]@{
            Action       = 'Created'
            MessageId    = $MessageId
            EntityId     = $entityId
            ResponseBody = $resp
        }
    }
    catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -match 'status=412' -or $errMsg -match 'PreconditionFailed') {
            $existed = $true
        }
        elseif ($errMsg -match 'status=404' -or $errMsg -match 'Resource not found for the segment') {
            throw "Upsert failed for ${MessageId}: Alternate key fsi_MessageCenterIdKey not found - re-run create_mcm_dataverse_schema.py to provision it."
        }
        else {
            throw "Create failed for ${MessageId}: $errMsg"
        }
    }

    if ($existed) {
        try {
            # Update path: $Record (NOT $createPayload) is sent. By contract it
            # excludes admin-owned columns, so PATCH cannot overwrite them.
            $resp = Invoke-McmRest -Uri $upsertUrl -Headers $DataverseHeaders -Method Patch `
                -Body ($Record | ConvertTo-Json -Depth 5)
            $entityId = $null
            if ($resp -and ($resp.PSObject.Properties.Name -contains 'fsi_messagecenterlogid')) {
                $entityId = [string]$resp.fsi_messagecenterlogid
            }
            return [pscustomobject]@{
                Action       = 'Updated'
                MessageId    = $MessageId
                EntityId     = $entityId
                ResponseBody = $resp
            }
        }
        catch {
            throw "Update failed for ${MessageId}: $($_.Exception.Message)"
        }
    }
}

function Expand-McmCardTokens {
    <#
    .SYNOPSIS
        Recursively substitutes {token} placeholders in a parsed adaptive card tree.

    .DESCRIPTION
        Walks a tree of hashtables, arrays, and strings produced by
        ConvertFrom-Json -AsHashtable, replacing every occurrence of {tokenName}
        inside string values with the corresponding value from $Tokens.

        Substitution happens at the OBJECT level (parsed JSON tree), so quote,
        newline, backslash, and other special characters in token values are
        correctly JSON-escaped when the result is re-serialized with
        ConvertTo-Json. This prevents JSON-injection from message titles that
        contain quotes or control characters - the brittleness of naive
        string.Replace() on raw template text is avoided entirely.

        Missing tokens are left as the literal placeholder (e.g. "{missing}").
        Null token values are substituted as empty strings.

    .PARAMETER Node
        Current node in the tree. Initial call passes the parsed root.

    .PARAMETER Tokens
        Hashtable of token names -> string values.

    .OUTPUTS
        The same shape as the input (hashtable, array, string, or scalar) with
        substitutions applied.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Node,
        [Parameter(Mandatory)] [hashtable]$Tokens
    )

    if ($null -eq $Node) { return $null }

    if ($Node -is [string]) {
        $captured = $Tokens
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
            param($match)
            $name = $match.Groups[1].Value
            if ($captured.ContainsKey($name)) {
                $val = $captured[$name]
                if ($null -eq $val) { return '' }
                return [string]$val
            }
            return $match.Value
        }.GetNewClosure()
        return [System.Text.RegularExpressions.Regex]::Replace($Node, '\{(\w+)\}', $evaluator)
    }

    if ($Node -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($k in @($Node.Keys)) {
            $out[$k] = Expand-McmCardTokens -Node $Node[$k] -Tokens $Tokens
        }
        return $out
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $Node) {
            $null = $list.Add((Expand-McmCardTokens -Node $item -Tokens $Tokens))
        }
        return ,$list.ToArray()
    }

    return $Node
}

function Send-McmTeamsWebhook {
    <#
    .SYNOPSIS
        Posts an adaptive card to a Microsoft Teams Workflows incoming webhook.

    .DESCRIPTION
        Loads the shared adaptive card template, performs object-level token
        substitution (safe against JSON injection from quotes/newlines/specials
        in token values), wraps the result in the Teams Workflows message
        envelope (type='message' + attachments[] with contentType
        application/vnd.microsoft.card.adaptive), and POSTs via Invoke-McmRest.

        On 2xx: returns a result object with Success=$true.
        On 4xx/5xx after retries: returns Success=$false with the error
        message. This function does NOT throw on HTTP failure - callers (the
        sync loop) want to continue processing remaining messages and surface
        the failure as a warning. Other terminal failures (template missing,
        JSON parse error) throw.

    .PARAMETER WebhookUrl
        The Teams Workflows incoming webhook URL (HTTPS, from the Workflows
        app's "When a Teams webhook request is received" trigger).

    .PARAMETER CardTokens
        Hashtable of token names -> string values to substitute into the card
        template. Token names match the {tokenName} placeholders in the
        template (e.g. severity, title, category, services, startDateTime,
        actionRequiredByDateTime, id, environment, appId, publisherPrefix,
        recordId).

    .PARAMETER AdaptiveCardTemplatePath
        Filesystem path to the adaptive card template JSON. Default is
        ../../templates/teams-notification-card.json relative to this script.

    .PARAMETER MaxRetries
        Forwarded to Invoke-McmRest. Default: 3.

    .OUTPUTS
        [pscustomobject] @{ Success = $true|$false; Error = $null|<string> }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$WebhookUrl,
        [Parameter(Mandatory)] [hashtable]$CardTokens,
        [Parameter(Mandatory)] [string]$AdaptiveCardTemplatePath,
        [int]$MaxRetries = 3
    )

    if (-not (Test-Path -LiteralPath $AdaptiveCardTemplatePath)) {
        throw "Adaptive card template not found: $AdaptiveCardTemplatePath"
    }

    $templateRaw = Get-Content -LiteralPath $AdaptiveCardTemplatePath -Raw
    try {
        $card = $templateRaw | ConvertFrom-Json -AsHashtable -Depth 50
    } catch {
        throw "Failed to parse adaptive card template ${AdaptiveCardTemplatePath}: $($_.Exception.Message)"
    }

    # Strip the author-only _comment field; it is not part of the Adaptive
    # Cards schema and adds noise to the wire payload.
    if ($card -is [System.Collections.IDictionary] -and $card.Contains('_comment')) {
        $null = $card.Remove('_comment')
    }

    $renderedCard = Expand-McmCardTokens -Node $card -Tokens $CardTokens

    $envelope = [ordered]@{
        type        = 'message'
        attachments = @(
            [ordered]@{
                contentType = 'application/vnd.microsoft.card.adaptive'
                contentUrl  = $null
                content     = $renderedCard
            }
        )
    }

    $body = $envelope | ConvertTo-Json -Depth 20 -Compress
    $headers = @{ 'Content-Type' = 'application/json' }

    try {
        # Workflows incoming webhook typically responds 202 Accepted.
        # Invoke-McmRest handles 429/5xx retry with Retry-After honoring.
        $null = Invoke-McmRest -Uri $WebhookUrl -Headers $headers -Method Post `
            -Body $body -MaxRetries $MaxRetries
        return [pscustomobject]@{
            Success = $true
            Error   = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Write-McmRedacted {
    <#
    .SYNOPSIS
        Writes a log line with Bearer tokens, client secrets, and Authorization
        headers redacted.

    .DESCRIPTION
        Centralised secret-scrubbing for lab and governance scripts. Use this
        instead of Write-Host / Write-Information when emitting strings that
        could contain HTTP bodies, headers, or token responses.

        Redactions:
          - Bearer <token>                   -> Bearer <REDACTED>
          - "access_token":"..."             -> "access_token":"<REDACTED>"
          - client_secret=<value>            -> client_secret=<REDACTED>
          - "client_secret":"..."            -> "client_secret":"<REDACTED>"
          - Authorization: <value>           -> Authorization: <REDACTED>

    .PARAMETER Message
        The string to scrub. Multiline OK.

    .PARAMETER Stream
        Output stream: Host (default), Verbose, Warning, Information.

    .EXAMPLE
        Write-McmRedacted "Authorization: Bearer eyJhbGc..."
        # writes: Authorization: Bearer <REDACTED>
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [AllowEmptyString()] [string]$Message,
        [ValidateSet('Host', 'Verbose', 'Warning', 'Information')]
        [string]$Stream = 'Host'
    )
    process {
        $scrubbed = $Message
        $scrubbed = $scrubbed -replace '(?i)Bearer\s+[A-Za-z0-9._\-+/=]+', 'Bearer <REDACTED>'
        $scrubbed = $scrubbed -replace '(?i)"access_token"\s*:\s*"[^"]*"', '"access_token":"<REDACTED>"'
        $scrubbed = $scrubbed -replace '(?i)"refresh_token"\s*:\s*"[^"]*"', '"refresh_token":"<REDACTED>"'
        $scrubbed = $scrubbed -replace '(?i)"id_token"\s*:\s*"[^"]*"', '"id_token":"<REDACTED>"'
        $scrubbed = $scrubbed -replace '(?i)"client_secret"\s*:\s*"[^"]*"', '"client_secret":"<REDACTED>"'
        $scrubbed = $scrubbed -replace '(?i)client_secret=[^&\s"]+', 'client_secret=<REDACTED>'
        $scrubbed = $scrubbed -replace '(?im)^(\s*Authorization\s*:\s*).+$', '$1<REDACTED>'

        switch ($Stream) {
            'Verbose'     { Write-Verbose     $scrubbed }
            'Warning'     { Write-Warning     $scrubbed }
            'Information' { Write-Information $scrubbed -InformationAction Continue }
            default       { Write-Host        $scrubbed }
        }
    }
}

function Format-McmODataLiteral {
    <#
    .SYNOPSIS
        Escapes a string for safe use as an OData single-quoted literal.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return $Value.Replace("'", "''")
}

function Format-McmODataDate {
    <#
    .SYNOPSIS
        Formats a DateTime as a UTC ISO-8601 string suitable for Dataverse OData filters.
    #>
    param([Parameter(Mandatory)][datetime]$Value)
    return [System.Xml.XmlConvert]::ToString(
        $Value.ToUniversalTime(),
        [System.Xml.XmlDateTimeSerializationMode]::Utc
    )
}
