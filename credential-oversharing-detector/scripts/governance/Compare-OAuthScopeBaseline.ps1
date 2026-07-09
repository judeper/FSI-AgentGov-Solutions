<#
.SYNOPSIS
    Compares actual OAuth scopes against an approved name-level baseline.

.DESCRIPTION
    Builds an OAuth scope baseline at the individual scope name level (e.g.,
    Mail.Read, Files.ReadWrite.All) and detects deviations. Replaces the
    prior count-only heuristic with a name-level comparison that distinguishes:

    - Approved scopes: match the agent's documented purpose baseline
    - Excessive scopes: broader than needed (e.g., Files.ReadWrite.All when
      only Files.Read is needed)
    - Sensitive scopes: require elevated approval (e.g., Mail.Send,
      Directory.ReadWrite.All, RoleManagement.ReadWrite.Directory)

    Reads baseline from Dataverse `fsi_agentconnectorscopes` table
    (`fsi_approvedscopes` column) and compares against actual scopes from
    the connector configuration (`fsi_actualscopes` column).

.PARAMETER DataverseUrl
    Dataverse environment URL.

.PARAMETER OutputFormat
    Output format: Table (default), Json, or Object.

.PARAMETER SensitiveScopes
    Array of scope names that require elevated approval. Defaults to a
    curated list of high-privilege Microsoft Graph scopes.

.PARAMETER WhatIf
    Preview mode - shows deviations without persisting to Dataverse.

.NOTES
    File: Compare-OAuthScopeBaseline.ps1
    Version: 2.1.1
    Solution: Credential Oversharing Detector (COD)
    Controls: 1.14, 1.4, 1.18
    Requires: Az.Accounts (>= 2.17.0) for Dataverse-scoped token acquisition

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Az.Accounts'; ModuleVersion='2.17.0' }

function Compare-OAuthScopeBaseline {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https://[a-zA-Z0-9\-]+\.crm[0-9]*\.dynamics\.com')]
        [string]$DataverseUrl,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$DataverseToken,

        [ValidateSet('Table', 'Json', 'Object')]
        [string]$OutputFormat = 'Table',

        [string[]]$SensitiveScopes = @(
            'Mail.Send',
            'Mail.ReadWrite',
            'Files.ReadWrite.All',
            'Directory.ReadWrite.All',
            'RoleManagement.ReadWrite.Directory',
            'User.ReadWrite.All',
            'Group.ReadWrite.All',
            'Application.ReadWrite.All',
            'AppRoleAssignment.ReadWrite.All',
            'Sites.FullControl.All',
            'Exchange.ManageAsApp',
            'MailboxSettings.ReadWrite'
        )
    )

    begin {
        $ErrorActionPreference = 'Stop'
        $sensitiveSet = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        foreach ($s in $SensitiveScopes) { [void]$sensitiveSet.Add($s) }

        Write-Verbose "Comparing OAuth scope baselines with $($sensitiveSet.Count) sensitive scope definitions..."
    }

    process {
        # ---------------------------------------------------------------
        # Step 1: Query scope baselines from Dataverse
        # ---------------------------------------------------------------
        $apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

        # IMPORTANT: Dataverse requires a token whose audience is the Dataverse
        # environment URL. A Microsoft Graph access token (audience graph.microsoft.com)
        # will produce HTTP 401 against /api/data/v9.2. Acquire a Dataverse-scoped
        # token via Az.Accounts unless the caller passed one in.
        $dvAccessToken = $DataverseToken
        if (-not $dvAccessToken) {
            try {
                if (-not (Get-AzContext)) {
                    if ($TenantId) {
                        Connect-AzAccount -Tenant $TenantId | Out-Null
                    } else {
                        Connect-AzAccount | Out-Null
                    }
                }
                $tokenResult = Get-AzAccessToken -ResourceUrl $DataverseUrl.TrimEnd('/') -AsSecureString -ErrorAction Stop
                $dvAccessToken = $tokenResult.Token | ConvertFrom-SecureString -AsPlainText
            } catch {
                throw "Could not acquire Dataverse token for $DataverseUrl. Pass -DataverseToken or run Connect-AzAccount first. Inner error: $($_.Exception.Message)"
            }
        }

        $headers = @{
            'Authorization' = "Bearer $dvAccessToken"
            'Accept'        = 'application/json'
            'Content-Type'  = 'application/json'
            'OData-Version' = '4.0'
        }

        $select = "fsi_scopename,fsi_agentconnectorscopeid,fsi_approvedscopes,fsi_actualscopes,fsi_agentid,fsi_agentname,fsi_connectorname"
        $uri = "$apiBase/fsi_agentconnectorscopes?`$select=$select&`$top=1000"

        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
        $scopeRecords = $resp.value
        Write-Verbose "Retrieved $($scopeRecords.Count) scope baseline record(s)."

        # ---------------------------------------------------------------
        # Step 2: Compare approved vs. actual scopes per record
        # ---------------------------------------------------------------
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($record in $scopeRecords) {
            $approved = @()
            $actual = @()

            if ($record.fsi_approvedscopes) {
                $approved = ($record.fsi_approvedscopes -split '[,;\s]+') |
                    Where-Object { $_ -ne '' } |
                    ForEach-Object { $_.Trim() }
            }
            if ($record.fsi_actualscopes) {
                $actual = ($record.fsi_actualscopes -split '[,;\s]+') |
                    Where-Object { $_ -ne '' } |
                    ForEach-Object { $_.Trim() }
            }

            $approvedSet = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            foreach ($s in $approved) { [void]$approvedSet.Add($s) }

            $actualSet = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            foreach ($s in $actual) { [void]$actualSet.Add($s) }

            # Excess = actual scopes not in approved
            $excessScopes = $actual | Where-Object { -not $approvedSet.Contains($_) }
            # Missing = approved scopes not in actual (informational)
            $missingScopes = $approved | Where-Object { -not $actualSet.Contains($_) }
            # Sensitive = actual scopes in the sensitive list
            $sensitiveFound = $actual | Where-Object { $sensitiveSet.Contains($_) }
            # Sensitive + excess = critical
            $sensitiveExcess = $excessScopes | Where-Object { $sensitiveSet.Contains($_) }

            $severity = 'Passed'
            if ($sensitiveExcess.Count -gt 0) {
                $severity = 'Critical'
            } elseif ($excessScopes.Count -gt 0) {
                $severity = 'High'
            } elseif ($sensitiveFound.Count -gt 0) {
                $severity = 'Medium'
            }

            $results.Add([PSCustomObject]@{
                ScopeRecordId    = $record.fsi_agentconnectorscopeid
                AgentId          = $record.fsi_agentid
                AgentName        = $record.fsi_agentname
                ConnectorName    = $record.fsi_connectorname
                ScopeName        = $record.fsi_scopename
                Approved         = $approved
                Actual           = $actual
                ApprovedCount    = $approved.Count
                ActualCount      = $actual.Count
                ExcessScopes     = ($excessScopes -join ', ')
                ExcessCount      = $excessScopes.Count
                MissingScopes    = ($missingScopes -join ', ')
                SensitiveScopes  = ($sensitiveFound -join ', ')
                SensitiveExcess  = ($sensitiveExcess -join ', ')
                Severity         = $severity
                Recommendation   = switch ($severity) {
                    'Critical' { "Remove sensitive excess scopes: $($sensitiveExcess -join ', '). These require elevated approval." }
                    'High'     { "Remove excess scopes: $($excessScopes -join ', '). Agent should use least-privilege scopes." }
                    'Medium'   { "Sensitive scopes detected ($($sensitiveFound -join ', ')) - verify elevated approval is documented." }
                    'Passed'   { 'Scopes match approved baseline.' }
                }
            })
        }

        # ---------------------------------------------------------------
        # Step 3: Persist violations to Dataverse
        # ---------------------------------------------------------------
        if (-not $WhatIfPreference) {
            foreach ($result in ($results | Where-Object { $_.Severity -ne 'Passed' })) {
                $idSuffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
                $body = @{
                    fsi_violationid     = "SCOPE-$($result.AgentId)-$(Get-Date -Format 'yyyyMMdd')-$idSuffix"
                    fsi_agentid         = $result.AgentId
                    fsi_agentname       = $result.AgentName
                    fsi_violationtype   = 100000001  # ExcessiveOAuthScope
                    fsi_severity        = switch ($result.Severity) {
                        'Critical' { 100000000 }
                        'High'     { 100000001 }
                        'Medium'   { 100000002 }
                        default    { 100000003 }
                    }
                    fsi_violationstatus = 100000000  # Open
                    fsi_description     = $result.Recommendation
                    # Populate the timestamp + the v2.1.1 scope columns so
                    # Export-CredentialEvidence.ps1 (which filters by
                    # fsi_detectedat date range) includes these violations,
                    # and so the auditor JSON carries the baseline diff.
                    fsi_detectedat      = (Get-Date).ToUniversalTime().ToString('o')
                    fsi_approvedscopes  = ($result.Approved -join ' ')
                    fsi_actualscopes    = ($result.Actual -join ' ')
                } | ConvertTo-Json

                try {
                    if ($PSCmdlet.ShouldProcess($result.AgentName, 'Record scope baseline violation')) {
                        Invoke-RestMethod -Uri "$apiBase/fsi_credentialviolations" -Headers $headers -Method Post -Body $body -ErrorAction Stop | Out-Null
                    }
                } catch {
                    Write-Warning "Failed to record scope violation for $($result.AgentName): $_"
                }
            }
        }

        # ---------------------------------------------------------------
        # Step 4: Output
        # ---------------------------------------------------------------
        $violationCount = ($results | Where-Object { $_.Severity -ne 'Passed' }).Count

        switch ($OutputFormat) {
            'Json' {
                @{
                    Timestamp       = (Get-Date -Format 'o')
                    TotalBaselines  = $results.Count
                    Violations      = $violationCount
                    SensitiveScopes = @($SensitiveScopes)
                    Results         = $results
                } | ConvertTo-Json -Depth 10
            }
            'Object' {
                $results
            }
            default {
                Write-Host "`nOAuth Scope Baseline Comparison:" -ForegroundColor Cyan
                Write-Host ("=" * 60) -ForegroundColor Cyan
                Write-Host "  Baselines Evaluated: $($results.Count)"
                Write-Host "  Deviations Found:    $violationCount" -ForegroundColor $(if ($violationCount -gt 0) { 'Red' } else { 'Green' })
                Write-Host ""
                if ($violationCount -gt 0) {
                    $results | Where-Object { $_.Severity -ne 'Passed' } |
                        Format-Table -Property AgentName, ConnectorName, ExcessCount, SensitiveExcess, Severity -AutoSize
                } else {
                    Write-Host "  All scope baselines match." -ForegroundColor Green
                }
            }
        }
    }
}
