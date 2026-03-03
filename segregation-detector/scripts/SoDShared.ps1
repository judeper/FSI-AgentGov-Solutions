<#
.SYNOPSIS
    Shared helper functions for the Segregation of Duties Detector scripts.

.DESCRIPTION
    Contains Invoke-WithRetry, Get-AccessToken, Get-LoginEndpoint, Get-GraphEndpoint,
    and Get-BapApiBaseUrl, used by both Invoke-SoDScan.ps1 and Import-ConflictRules.ps1.
#>

function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$BaseDelaySeconds = 2
    )

    $attempt = 0
    while ($true) {
        try {
            return & $ScriptBlock
        } catch {
            $attempt++
            if ($attempt -ge $MaxRetries) { throw }
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            # Retry on 429, 408, 5xx, and transient network errors (not 401 — same credentials won't help)
            $isTransientNetwork = -not $statusCode -and $_.Exception.InnerException -is [System.Net.Sockets.SocketException]
            if ($statusCode -eq 429 -or $statusCode -eq 408 -or ($statusCode -and $statusCode -ge 500) -or $isTransientNetwork) {
                $delay = $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1)
                if ($statusCode -eq 429 -and $_.Exception.Response.Headers) {
                    $retryAfter = $_.Exception.Response.Headers | Where-Object { $_.Key -eq 'Retry-After' } | ForEach-Object { $_.Value } | Select-Object -First 1
                    if ($retryAfter -and [int]::TryParse($retryAfter, [ref]$null)) {
                        $delay = [Math]::Max($delay, [int]$retryAfter)
                    }
                }
                $reason = if ($isTransientNetwork) { "Network error: $($_.Exception.InnerException.Message)" } else { "HTTP $statusCode" }
                Write-Warning "$reason - retrying in ${delay}s (attempt $attempt/$MaxRetries)"
                Start-Sleep -Seconds $delay
            } else {
                throw
            }
        }
    }
}

function Get-LoginEndpoint {
    param([string]$Scope)
    if ($Scope -match '\.(microsoftdynamics\.us|appsplatform\.us|microsoft\.us)') {
        return "https://login.microsoftonline.us"
    } elseif ($Scope -match '\.(dynamics\.cn|chinacloudapi\.cn|microsoftonline\.cn)') {
        return "https://login.partner.microsoftonline.cn"
    } else {
        return "https://login.microsoftonline.com"
    }
}

function Get-AccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$Scope
    )

    $loginEndpoint = Get-LoginEndpoint -Scope $Scope
    $tokenUrl = "$loginEndpoint/$TenantId/oauth2/v2.0/token"

    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
        grant_type    = "client_credentials"
    }

    $response = Invoke-WithRetry { Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" }
    if (-not $response.access_token) {
        throw "Token response did not contain an access_token. Verify client credentials and scope '$Scope'."
    }
    return $response.access_token
}

function Get-GraphEndpoint {
    param([string]$EnvironmentUrl)
    if ($EnvironmentUrl -match '\.(microsoftdynamics\.us|appsplatform\.us)') {
        return "https://graph.microsoft.us"
    } elseif ($EnvironmentUrl -match '\.dynamics\.cn') {
        return "https://microsoftgraph.chinacloudapi.cn"
    } else {
        return "https://graph.microsoft.com"
    }
}

function Get-BapApiBaseUrl {
    param([string]$EnvironmentUrl)
    if ($EnvironmentUrl -match '\.microsoftdynamics\.us') {
        return "https://api.bap.appsplatform.us"
    } elseif ($EnvironmentUrl -match '\.appsplatform\.us') {
        return "https://api.bap.appsplatform.us"
    } elseif ($EnvironmentUrl -match '\.dynamics\.cn') {
        return "https://api.bap.partner.microsoftonline.cn"
    } else {
        return "https://api.bap.microsoft.com"
    }
}
