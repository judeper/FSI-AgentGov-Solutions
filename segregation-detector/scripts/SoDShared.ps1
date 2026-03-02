<#
.SYNOPSIS
    Shared helper functions for the Segregation of Duties Detector scripts.

.DESCRIPTION
    Contains Invoke-WithRetry and Get-AccessToken, used by both
    Invoke-SoDScan.ps1 and Import-ConflictRules.ps1.
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
            if ($statusCode -eq 429 -or ($statusCode -and $statusCode -ge 500)) {
                $delay = $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1)
                Write-Warning "HTTP $statusCode - retrying in ${delay}s (attempt $attempt/$MaxRetries)"
                Start-Sleep -Seconds $delay
            } else {
                throw
            }
        }
    }
}

function Get-AccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$Scope
    )

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
        grant_type    = "client_credentials"
    }

    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    return $response.access_token
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
