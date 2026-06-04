#Requires -Version 7.1

<#
.SYNOPSIS
    Shared helper functions for the Segregation of Duties Detector scripts.

.DESCRIPTION
    Contains retry, cloud endpoint, and managed-identity-first token helpers used by
    Invoke-SoDScan.ps1 and Import-ConflictRules.ps1.
#>

$script:SoDChoiceValues = @{
    Category = @{
        MakerChecker     = 100000000
        Segregation      = 100000001
        PrivilegedAccess = 100000002
    }
    RoleContext = @{
        EntraDirectoryRole           = 100000000
        EntraAppRole                 = 100000001
        PowerPlatformEnvironmentRole = 100000002
        DataverseSecurityRole        = 100000003
        CustomApplicationRole        = 100000004
    }
    Severity = @{
        Critical = 100000000
        High     = 100000001
        Medium   = 100000002
        Low      = 100000003
    }
    ViolationStatus = @{
        Open                       = 100000000
        UnderReview                = 100000001
        ExceptionRequested         = 100000002
        ExceptionApproved          = 100000003
        ResolvedRoleRemoved        = 100000004
        ResolvedUserRemoved        = 100000005
        ClosedFalsePositive        = 100000006
    }
    ResolutionType = @{
        RoleARemoved     = 100000000
        RoleBRemoved     = 100000001
        BothRolesRemoved = 100000002
        UserDeactivated  = 100000003
        ExceptionGranted = 100000004
        FalsePositive    = 100000005
        RuleDisabled     = 100000006
    }
    ExceptionType = @{
        Emergency = 100000000
        Temporary = 100000001
        Permanent = 100000002
    }
    ExceptionStatus = @{
        Requested        = 100000000
        ManagerApproved  = 100000001
        ComplianceReview = 100000002
        Approved         = 100000003
        Denied           = 100000004
        Expired          = 100000005
        Revoked          = 100000006
    }
    AuditEventType = @{
        ViolationDetected  = 100000000
        ViolationResolved  = 100000001
        ExceptionRequested = 100000002
        ExceptionApproved  = 100000003
        ExceptionDenied    = 100000004
        ExceptionExpired   = 100000005
        RuleCreated        = 100000006
        RuleModified       = 100000007
        RuleDisabled       = 100000008
        ScanCompleted      = 100000009
        AlertSent          = 100000010
    }
}

function Get-SoDChoiceValues {
    return $script:SoDChoiceValues
}

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
            # Retry on 429, 408, 5xx, and transient network errors (not 401 -- same credentials won't help)
            $isTransientNetwork = -not $statusCode -and $_.Exception.InnerException -is [System.Net.Sockets.SocketException]
            if ($statusCode -eq 429 -or $statusCode -eq 408 -or ($statusCode -and $statusCode -ge 500) -or $isTransientNetwork) {
                $delay = $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1)
                if ($statusCode -eq 429 -and $_.Exception.Response.Headers) {
                    $retryAfter = $_.Exception.Response.Headers | Where-Object { $_.Key -eq 'Retry-After' } | ForEach-Object { $_.Value } | Select-Object -First 1
                    $retryAfterSeconds = 0
                    if ($retryAfter -and [int]::TryParse([string]$retryAfter, [ref]$retryAfterSeconds)) {
                        $delay = [Math]::Max($delay, $retryAfterSeconds)
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

function Get-ResourceFromScope {
    param([Parameter(Mandatory = $true)][string]$Scope)
    if ($Scope.EndsWith('/.default')) {
        return $Scope.Substring(0, $Scope.Length - '/.default'.Length)
    }
    return $Scope
}

function Get-ManagedIdentityAccessToken {
    param(
        [Parameter(Mandatory = $true)][string]$Resource,
        [string]$ManagedIdentityClientId
    )

    $encodedResource = [System.Uri]::EscapeDataString($Resource)
    $headers = @{ Metadata = 'true' }

    if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
        $uri = "$($env:IDENTITY_ENDPOINT)?api-version=2019-08-01&resource=$encodedResource"
        $headers['X-IDENTITY-HEADER'] = $env:IDENTITY_HEADER
    }
    else {
        $uri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$encodedResource"
    }

    if ($ManagedIdentityClientId) {
        $uri += "&client_id=$([System.Uri]::EscapeDataString($ManagedIdentityClientId))"
    }

    $response = Invoke-WithRetry {
        Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 10
    }
    if (-not $response.access_token) {
        throw "Managed identity token response did not contain an access_token for resource '$Resource'."
    }
    return $response.access_token
}

function Get-WorkloadIdentityAccessToken {
    param(
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$Scope,
        [Parameter(Mandatory = $true)][string]$FederatedTokenFile
    )

    if (-not (Test-Path -Path $FederatedTokenFile -PathType Leaf)) {
        throw "Federated token file '$FederatedTokenFile' was not found. Set AZURE_FEDERATED_TOKEN_FILE or pass -FederatedTokenFile."
    }

    $loginEndpoint = Get-LoginEndpoint -Scope $Scope
    $tokenUrl = "$loginEndpoint/$TenantId/oauth2/v2.0/token"
    $assertion = Get-Content -Path $FederatedTokenFile -Raw

    $body = @{
        client_id             = $ClientId
        scope                 = $Scope
        grant_type            = "client_credentials"
        client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        client_assertion      = $assertion
    }

    $response = Invoke-WithRetry { Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" }
    if (-not $response.access_token) {
        throw "Workload identity token response did not contain an access_token. Verify federated credential issuer, subject, and audience."
    }
    return $response.access_token
}

function Get-ClientSecretAccessToken {
    param(
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$ClientSecret,
        [Parameter(Mandatory = $true)][string]$Scope
    )

    # legacy: dev-only -- replace with managed identity in production
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

function Get-AccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [Parameter(Mandatory = $true)][string]$Scope,
        [ValidateSet("ManagedIdentity", "WorkloadIdentity", "ClientSecret")]
        [string]$AuthMode = "ManagedIdentity",
        [string]$ManagedIdentityClientId,
        [string]$FederatedTokenFile = $env:AZURE_FEDERATED_TOKEN_FILE
    )

    switch ($AuthMode) {
        "ManagedIdentity" {
            $resource = Get-ResourceFromScope -Scope $Scope
            return Get-ManagedIdentityAccessToken -Resource $resource -ManagedIdentityClientId $ManagedIdentityClientId
        }
        "WorkloadIdentity" {
            if (-not $TenantId -or -not $ClientId) {
                throw "TenantId and ClientId are required for WorkloadIdentity auth. Set AZURE_TENANT_ID / AZURE_CLIENT_ID or pass parameters."
            }
            if (-not $FederatedTokenFile) {
                throw "FederatedTokenFile is required for WorkloadIdentity auth. Set AZURE_FEDERATED_TOKEN_FILE or pass -FederatedTokenFile."
            }
            return Get-WorkloadIdentityAccessToken -TenantId $TenantId -ClientId $ClientId -Scope $Scope -FederatedTokenFile $FederatedTokenFile
        }
        "ClientSecret" {
            if (-not $TenantId -or -not $ClientId) {
                throw "TenantId and ClientId are required for ClientSecret auth. Set AZURE_TENANT_ID / AZURE_CLIENT_ID or pass parameters."
            }
            if (-not $ClientSecret) {
                throw "ClientSecret is required only for legacy dev fallback. Set FSI_CLIENT_SECRET or pass -ClientSecret when -AuthMode ClientSecret is explicitly selected."
            }
            return Get-ClientSecretAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope $Scope
        }
    }
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

function Get-BapResource {
    <#
    .SYNOPSIS
        Returns the OAuth resource (audience) used to acquire a token for the Power Platform
        Business Application Platform (BAP) admin REST API.

    .DESCRIPTION
        The BAP admin REST API is hosted at api.bap.microsoft.com (and sovereign equivalents),
        but the request HOST is not the token AUDIENCE. Microsoft's documented audience for the
        BAP / Power Platform admin REST surface is the first-party "Power Apps Service" resource
        https://service.powerapps.com/ (Application ID 475226c6-020e-4fb2-8a90-7a972cbfc1d4) --
        the same resource the Microsoft.PowerApps.Administration.PowerShell module and
        New-PowerAppManagementApp registration target.
        Ref: https://learn.microsoft.com/power-platform/admin/programmability-authentication

        Requesting "https://api.bap.microsoft.com/.default" can fail token acquisition
        (AADSTS500011: resource principal not found) because that host is not a registered
        Microsoft Entra resource identifier URI.

        Sovereign-cloud resource identifier URIs for Power Apps Service are not publicly
        documented. For those clouds this helper falls back to the BAP base URL as the audience;
        operators should verify in-tenant and use -BapResource / FSI_BAP_RESOURCE to override.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$EnvironmentUrl,
        [Parameter(Mandatory = $true)][string]$BapApiBaseUrl
    )
    if ($EnvironmentUrl -match '\.(microsoftdynamics\.us|appsplatform\.us|dynamics\.cn)') {
        # Sovereign clouds: resource identifier URI not authoritatively documented -- verify in-tenant.
        return $BapApiBaseUrl
    }
    return "https://service.powerapps.com/"
}
