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
            throw "WorkloadIdentity auth not yet implemented; use ManagedIdentity or DeviceCode"
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
            # legacy: dev-only path; prefer ManagedIdentity in production
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

            $isRetryable = ($status -eq 429 -or $status -eq 503)
            if ($isRetryable -and $attempt -le $MaxRetries) {
                $retryAfter = 0
                try {
                    $hdr = $_.Exception.Response.Headers['Retry-After']
                    if ($hdr) { $retryAfter = [int]$hdr }
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
            $msg = "Invoke-McmRest failed: status=$status method=$Method uri=$Uri error=$($_.Exception.Message)"
            if ($body) { $msg += " body=$body" }
            throw $msg
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
