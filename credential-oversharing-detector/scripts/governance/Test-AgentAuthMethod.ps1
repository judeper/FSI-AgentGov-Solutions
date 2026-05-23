<#
.SYNOPSIS
    Detects agent authentication method and flags client-secret usage as legacy.

.DESCRIPTION
    Inspects Copilot Studio agent service principals and managed identities to
    determine the authentication method in use. Classifies each credential as:
    - ManagedIdentity (system-assigned or user-assigned) - recommended
    - Certificate - acceptable
    - ClientSecret - legacy/risky, recommend migration
    - FederatedCredential (workload identity federation/OIDC) - acceptable

    Records evidence to Dataverse for audit trail, including credential type,
    creation date, expiration, and migration recommendation.

    Aligns with the managed-identity-first authentication standard:
    1. System-assigned MI > 2. User-assigned MI > 3. Workload identity federation
    > 4. Interactive/device-code > 5. Client secret (legacy)

    Reference: https://learn.microsoft.com/power-platform/admin/programmability-authentication

.PARAMETER TenantId
    Microsoft Entra ID tenant ID.

.PARAMETER DataverseUrl
    Dataverse environment URL for recording evidence.

.PARAMETER OutputFormat
    Output format: Table (default), Json, or Object.

.PARAMETER WhatIf
    Preview mode - shows findings without persisting to Dataverse.

.NOTES
    File: Test-AgentAuthMethod.ps1
    Version: 2.1.1
    Solution: Credential Oversharing Detector (COD)
    Controls: 1.14, 1.4, 1.18
    Requires: Microsoft.Graph.Applications, Microsoft.Graph.Authentication, Az.Accounts (>= 2.17.0)

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications
#Requires -Modules @{ ModuleName='Az.Accounts'; ModuleVersion='2.17.0' }

function Test-AgentAuthMethod {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [ValidatePattern('^https://[a-zA-Z0-9\-]+\.crm[0-9]*\.dynamics\.com')]
        [string]$DataverseUrl,

        [Parameter()]
        [string]$DataverseToken,

        [ValidateSet('Table', 'Json', 'Object')]
        [string]$OutputFormat = 'Table'
    )

    begin {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "Analyzing agent authentication methods for tenant $TenantId..."
    }

    process {
        # ---------------------------------------------------------------
        # Step 1: Enumerate agent-related service principals
        # ---------------------------------------------------------------
        $allSPs = Get-MgServicePrincipal -Filter "startsWith(displayName,'Copilot')" -All `
            -Property Id,DisplayName,AppId,ServicePrincipalType,KeyCredentials,PasswordCredentials `
            -ErrorAction SilentlyContinue

        # Also check managed identities
        $managedIdentitySPs = Get-MgServicePrincipal `
            -Filter "servicePrincipalType eq 'ManagedIdentity'" -All `
            -Property Id,DisplayName,AppId,ServicePrincipalType,AlternativeNames `
            -ErrorAction SilentlyContinue

        $allAgentSPs = @($allSPs) + @($managedIdentitySPs) | Sort-Object Id -Unique
        Write-Verbose "Found $($allAgentSPs.Count) agent-related service principal(s)."

        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($sp in $allAgentSPs) {
            $authMethods = [System.Collections.Generic.List[PSCustomObject]]::new()
            $primaryMethod = 'Unknown'
            $riskLevel = 'Unknown'

            # Check for managed identity
            if ($sp.ServicePrincipalType -eq 'ManagedIdentity') {
                $miType = if ($sp.AlternativeNames -match '/subscriptions/') {
                    'UserAssigned'
                } else {
                    'SystemAssigned'
                }
                $authMethods.Add([PSCustomObject]@{
                    Type       = "ManagedIdentity-$miType"
                    KeyId      = $null
                    StartDate  = $null
                    EndDate    = $null
                    IsExpired  = $false
                })
                $primaryMethod = "ManagedIdentity-$miType"
                $riskLevel = 'Low'
            }

            # Check for certificate credentials
            if ($sp.KeyCredentials) {
                foreach ($key in $sp.KeyCredentials) {
                    if ($key.Type -eq 'AsymmetricX509Cert') {
                        $isExpired = $key.EndDateTime -lt (Get-Date)
                        $authMethods.Add([PSCustomObject]@{
                            Type       = 'Certificate'
                            KeyId      = $key.KeyId
                            StartDate  = $key.StartDateTime
                            EndDate    = $key.EndDateTime
                            IsExpired  = $isExpired
                        })
                        if ($primaryMethod -eq 'Unknown') {
                            $primaryMethod = 'Certificate'
                            $riskLevel = if ($isExpired) { 'High' } else { 'Low' }
                        }
                    }
                }
            }

            # Check for federated credentials (OIDC). The Graph cmdlet expects the
            # Application *object* ID, not the AppId (client ID). Resolve via filter
            # before querying federated identity credentials.
            try {
                $appObject = Get-MgApplication -Filter "appId eq '$($sp.AppId)'" `
                    -Property Id -Top 1 -ErrorAction SilentlyContinue
                if ($appObject) {
                    $fedCreds = Get-MgApplicationFederatedIdentityCredential `
                        -ApplicationId $appObject.Id -ErrorAction SilentlyContinue
                } else {
                    $fedCreds = $null
                    Write-Verbose "No Application object found for AppId $($sp.AppId) (likely managed identity or first-party SP); skipping federated credential lookup."
                }
                if ($fedCreds) {
                    foreach ($fed in $fedCreds) {
                        $authMethods.Add([PSCustomObject]@{
                            Type       = 'FederatedCredential'
                            KeyId      = $fed.Id
                            StartDate  = $null
                            EndDate    = $null
                            IsExpired  = $false
                        })
                        if ($primaryMethod -eq 'Unknown') {
                            $primaryMethod = 'FederatedCredential'
                            $riskLevel = 'Low'
                        }
                    }
                }
            } catch {
                Write-Verbose "Could not query federated credentials for $($sp.DisplayName): $_"
            }

            # Check for client secrets (password credentials)
            if ($sp.PasswordCredentials) {
                foreach ($pwd in $sp.PasswordCredentials) {
                    $isExpired = $pwd.EndDateTime -lt (Get-Date)
                    $authMethods.Add([PSCustomObject]@{
                        Type       = 'ClientSecret'
                        KeyId      = $pwd.KeyId
                        StartDate  = $pwd.StartDateTime
                        EndDate    = $pwd.EndDateTime
                        IsExpired  = $isExpired
                    })
                    if ($primaryMethod -eq 'Unknown') {
                        $primaryMethod = 'ClientSecret'
                        $riskLevel = 'Critical'
                    }
                }
            }

            # If no credentials found, flag as unknown
            if ($authMethods.Count -eq 0) {
                $primaryMethod = 'NoCredentials'
                $riskLevel = 'Informational'
            }

            $hasClientSecret = ($authMethods | Where-Object Type -eq 'ClientSecret').Count -gt 0
            $hasMI = ($authMethods | Where-Object { $_.Type -match 'ManagedIdentity' }).Count -gt 0
            $hasCert = ($authMethods | Where-Object Type -eq 'Certificate').Count -gt 0

            $recommendation = if ($hasClientSecret -and -not $hasMI) {
                'MIGRATE: Replace client secret with managed identity (system-assigned preferred) or certificate-based authentication'
            } elseif ($hasClientSecret -and $hasMI) {
                'CLEANUP: Remove legacy client secret - managed identity is already configured'
            } elseif ($hasClientSecret -and $hasCert) {
                'CLEANUP: Remove legacy client secret - certificate is already configured'
            } else {
                'No action required - authentication method follows managed-identity-first standard'
            }

            $results.Add([PSCustomObject]@{
                ServicePrincipalId   = $sp.Id
                DisplayName          = $sp.DisplayName
                AppId                = $sp.AppId
                ServicePrincipalType = $sp.ServicePrincipalType
                PrimaryAuthMethod    = $primaryMethod
                HasClientSecret      = $hasClientSecret
                HasManagedIdentity   = $hasMI
                HasCertificate       = $hasCert
                TotalCredentials     = $authMethods.Count
                RiskLevel            = $riskLevel
                Recommendation       = $recommendation
                AuthMethods          = $authMethods
                Reference            = 'https://learn.microsoft.com/power-platform/admin/programmability-authentication'
            })
        }

        # ---------------------------------------------------------------
        # Step 2: Persist to Dataverse if URL provided
        # ---------------------------------------------------------------
        if ($DataverseUrl -and -not $WhatIfPreference) {
            Write-Verbose "Recording auth method evidence to Dataverse..."

            # IMPORTANT: Dataverse requires a token whose audience is the Dataverse
            # environment URL. A Microsoft Graph access token (audience graph.microsoft.com)
            # will produce HTTP 401 against /api/data/v9.2. Acquire a Dataverse-scoped
            # token via Az.Accounts unless the caller passed one in.
            $dvAccessToken = $DataverseToken
            if (-not $dvAccessToken) {
                try {
                    if (-not (Get-AzContext)) {
                        Connect-AzAccount -Tenant $TenantId | Out-Null
                    }
                    $tokenResult = Get-AzAccessToken -ResourceUrl $DataverseUrl.TrimEnd('/') -AsSecureString -ErrorAction Stop
                    $dvAccessToken = $tokenResult.Token | ConvertFrom-SecureString -AsPlainText
                } catch {
                    Write-Warning "Could not acquire Dataverse token for $DataverseUrl: $($_.Exception.Message). Skipping persistence."
                    $dvAccessToken = $null
                }
            }

            if (-not $dvAccessToken) {
                Write-Warning "No Dataverse token available; skipping violation persistence."
            } else {
                $apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
                $headers = @{
                    'Authorization' = "Bearer $dvAccessToken"
                    'Content-Type'  = 'application/json'
                    'OData-Version' = '4.0'
                }

                foreach ($result in ($results | Where-Object HasClientSecret)) {
                    $idSuffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
                    $body = @{
                        fsi_violationid     = "AUTH-$($result.ServicePrincipalId)-$(Get-Date -Format 'yyyyMMdd')-$idSuffix"
                        fsi_agentid         = $result.AppId
                        fsi_agentname       = $result.DisplayName
                        fsi_violationtype   = 100000002  # UnauthorizedServiceAccount
                        fsi_severity        = 100000000  # Critical
                        fsi_violationstatus = 100000000  # Open
                        fsi_description     = $result.Recommendation
                    } | ConvertTo-Json

                    try {
                        if ($PSCmdlet.ShouldProcess($result.DisplayName, 'Record auth method violation')) {
                            Invoke-RestMethod -Uri "$apiBase/fsi_credentialviolations" -Headers $headers -Method Post -Body $body -ErrorAction Stop | Out-Null
                        }
                    } catch {
                        Write-Warning "Failed to record violation for $($result.DisplayName): $_"
                    }
                }
            }
        }

        # ---------------------------------------------------------------
        # Step 3: Output
        # ---------------------------------------------------------------
        $secretCount = ($results | Where-Object HasClientSecret).Count

        switch ($OutputFormat) {
            'Json' {
                @{
                    Timestamp          = (Get-Date -Format 'o')
                    TenantId           = $TenantId
                    TotalSPs           = $results.Count
                    ClientSecretCount  = $secretCount
                    Results            = $results
                } | ConvertTo-Json -Depth 10
            }
            'Object' {
                $results
            }
            default {
                Write-Host "`nAgent Authentication Method Analysis:" -ForegroundColor Cyan
                Write-Host ("=" * 60) -ForegroundColor Cyan
                Write-Host "  Service Principals Scanned: $($results.Count)"
                Write-Host "  Using Client Secret:        $secretCount" -ForegroundColor $(if ($secretCount -gt 0) { 'Red' } else { 'Green' })
                Write-Host ""
                $results | Format-Table -Property DisplayName, PrimaryAuthMethod, HasClientSecret, HasManagedIdentity, RiskLevel -AutoSize
            }
        }
    }
}
