<#
.SYNOPSIS
    Compares agent generative AI configuration against zone-specific policies.

.DESCRIPTION
    Takes agent GenAI settings (from Get-AgentGenAISettings) and evaluates each
    agent's configuration against the expected policy for its zone. Returns
    compliance results with severity classification, violation type, and
    regulatory context.

    Checks include: AOAI enabled vs policy, orchestration mode vs policy,
    generative answers node usage vs policy, AOAI connection whitelist
    validation when a Dataverse URL is provided, Model Knowledge toggle
    vs policy, and Semantic Search toggle vs policy.

.NOTES
    File: Compare-GenAIConfigCompliance.ps1
    Version: 1.0.0
    Solution: Generative AI Config Auditor (GAC)
    Control: 2.24 (Agent Feature Enablement Governance)
#>

#Requires -Version 7.4

function Compare-GenAIConfigCompliance {
    <#
    .SYNOPSIS
        Compares agent generative AI configuration against zone-specific policies.

    .DESCRIPTION
        Takes agent GenAI settings (from Get-AgentGenAISettings) and evaluates each
        agent's configuration against the expected policy for its zone. Returns
        compliance results with severity classification, violation type, and
        regulatory context.

        By default, only non-compliant agents are returned. Use -IncludeCompliant
        to include all agents in the output.

    .PARAMETER InputObject
        Pipeline input: PSCustomObject[] from Get-AgentGenAISettings.
        Each object must include AgentId, AgentName, AzureOpenAIEnabled,
        OrchestrationMode, GenerativeAnswersNodeCount, AoaiConnectionId,
        ModelKnowledgeEnabled, SemanticSearchEnabled, EnvironmentDisplayName,
        Zone, and AgentStatus properties.

    .PARAMETER IncludeCompliant
        Include compliant agents in output. By default, only violations are returned.

    .PARAMETER DataverseUrl
        Optional Dataverse URL for querying approved connection whitelist from
        fsi_gacapprovedconnections table. When provided, AOAI connection IDs
        are validated against the approved list.

    .PARAMETER DataverseToken
        Pre-obtained access token for Dataverse authentication.

    .EXAMPLE
        . ./Get-AgentGenAISettings.ps1
        . ./Compare-GenAIConfigCompliance.ps1
        Get-AgentGenAISettings | Compare-GenAIConfigCompliance

        Retrieves all agents and returns only non-compliant agents with severity.

    .EXAMPLE
        . ./Get-AgentGenAISettings.ps1
        . ./Compare-GenAIConfigCompliance.ps1
        Get-AgentGenAISettings -ExcludeSandbox | Compare-GenAIConfigCompliance -IncludeCompliant

        Returns compliance status for all agents including compliant ones.

    .EXAMPLE
        . ./Get-AgentGenAISettings.ps1
        . ./Compare-GenAIConfigCompliance.ps1
        $results = Get-AgentGenAISettings | Compare-GenAIConfigCompliance
        $results | Where-Object { $_.Severity -eq 'Critical' }

        Filters compliance results for critical violations only.

    .OUTPUTS
        PSCustomObject[] -- One object per agent with properties:
        AgentId, AgentName, EnvironmentId, EnvironmentDisplayName, Zone,
        AzureOpenAIEnabled, OrchestrationMode, GenerativeAnswersNodeCount,
        AoaiConnectionId, ModelKnowledgeEnabled, SemanticSearchEnabled,
        IsCompliant, Severity, ViolationType, RegulatoryContext, AgentStatus
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]]$InputObject,

        [Parameter()]
        [switch]$IncludeCompliant,

        [Parameter()]
        [string]$DataverseUrl,

        [Parameter()]
        [string]$DataverseToken
    )

    begin {
        try {
        #region Load Zone Policy

        $privateRoot = Join-Path $PSScriptRoot 'private'

        # Approved connections whitelist (loaded once if DataverseUrl provided)
        $approvedConnections = $null

        if ($DataverseUrl -and $DataverseToken) {
            try {
                Write-Verbose "Querying approved connections whitelist from Dataverse..."
                $baseUrl = $DataverseUrl.TrimEnd('/')
                $uri = "$baseUrl/api/data/v9.2/fsi_gacapprovedconnections?" +
                    "`$filter=statecode eq 0 and fsi_isactive eq true&" +
                    "`$select=fsi_connectionid,fsi_connectionname,fsi_zone"

                $headers = @{
                    'Authorization'    = "Bearer $DataverseToken"
                    'Accept'           = 'application/json'
                    'OData-MaxVersion' = '4.0'
                    'OData-Version'    = '4.0'
                }

                $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
                $approvedConnections = @{}
                $zoneIntToName = @{ 1 = 'Zone1'; 2 = 'Zone2'; 3 = 'Zone3'; 0 = 'Unknown' }

                foreach ($conn in $response.value) {
                    if ($conn.fsi_connectionid) {
                        $connZoneName = $zoneIntToName[[int]$conn.fsi_zone] ?? 'Unknown'
                        $approvedConnections["$($conn.fsi_connectionid)|$connZoneName"] = $conn
                    }
                }

                Write-Verbose "Loaded $($approvedConnections.Count) approved connection(s)"
            } catch {
                Write-Warning "Failed to query approved connections: $($_.Exception.Message). Connection whitelist validation will be skipped."
                $approvedConnections = $null
            }
        }

        #endregion

        #region Initialize Counters

        $totalCount = 0
        $compliantCount = 0
        $violationCount = 0
        $severityCounts = @{
            Critical = 0
            High     = 0
            Medium   = 0
            Warning  = 0
        }

        #endregion
        } catch {
            Write-Error "Failed to initialize GenAI compliance comparison: $($_.Exception.Message)"
            throw
        }
    }

    process {
        try {
        foreach ($agent in $InputObject) {
            $totalCount++

            # Normalize inputs defensively
            $agentZone = if ([string]::IsNullOrWhiteSpace($agent.Zone)) { 'Unknown' } else { $agent.Zone }

            # Get expected GenAI policy for this zone
            try {
                $policy = & (Join-Path $privateRoot 'Get-ExpectedGenAIPolicy.ps1') -Zone $agentZone
            } catch {
                Write-Warning "Failed to get GenAI policy for zone '$agentZone': $($_.Exception.Message)"
                $policy = [PSCustomObject]@{
                    Zone                             = $agentZone
                    AoaiAllowed                      = $false
                    AllowedOrchestrationModes        = @('Classic')
                    GenerativeAnswersAllowed         = $false
                    AoaiViolationSeverity            = 'High'
                    OrchestrationViolationSeverity   = 'High'
                    GenAnswersViolationSeverity      = 'High'
                    WhitelistViolationSeverity       = 'High'
                    ModelKnowledgeViolationSeverity  = 'High'
                    SemanticSearchViolationSeverity  = 'High'
                    RegulatoryContext                = 'Policy evaluation failed'
                }
            }

            # Evaluate compliance rules
            $violations = @()

            # Rule 1: Azure OpenAI enablement vs policy
            if ($agent.AzureOpenAIEnabled -eq 'Yes' -and -not $policy.AoaiAllowed) {
                $violations += [PSCustomObject]@{
                    ViolationType    = 'AoaiNotAllowed'
                    Description      = "Azure OpenAI is enabled but not permitted in $agentZone"
                    Severity         = $policy.AoaiViolationSeverity
                    RegulatoryContext = "Supports supervisory expectations under FINRA Rule 3110(a)(1) for AI model usage; $($policy.RegulatoryContext)"
                }
            }

            # Rule 2: Orchestration mode vs policy
            if ($agent.OrchestrationMode -ne 'Unable to Determine') {
                $modeAllowed = $policy.AllowedOrchestrationModes -contains $agent.OrchestrationMode
                if (-not $modeAllowed) {
                    $violations += [PSCustomObject]@{
                        ViolationType    = 'OrchestrationModeNotAllowed'
                        Description      = "Orchestration mode '$($agent.OrchestrationMode)' is not permitted in $agentZone (allowed: $($policy.AllowedOrchestrationModes -join ', '))"
                        Severity         = $policy.OrchestrationViolationSeverity
                        RegulatoryContext = "GLBA Section 501(b) - safeguard controls for generative orchestration; $($policy.RegulatoryContext)"
                    }
                }
            }

            # Rule 3: Generative answers nodes vs policy
            if ($agent.GenerativeAnswersNodeCount -gt 0 -and -not $policy.GenerativeAnswersAllowed) {
                $violations += [PSCustomObject]@{
                    ViolationType    = 'GenerativeAnswersNotAllowed'
                    Description      = "Agent has $($agent.GenerativeAnswersNodeCount) generative answers node(s) but generative answers are not permitted in $agentZone"
                    Severity         = $policy.GenAnswersViolationSeverity
                    RegulatoryContext = "SOX Section 404 - internal control over generative content; $($policy.RegulatoryContext)"
                }
            }

            # Rule 4: AOAI connection whitelist validation (fail-closed)
            # If AOAI is enabled at the agent and we have a connection ID, the connection MUST appear
            # in the approved-connections store. If the whitelist could not be loaded ($approvedConnections
            # is $null) and the agent zone enforces the whitelist (Zone 2/3), emit a Critical violation
            # rather than silently passing — this is an audit control bypass.
            $whitelistEnforcedZones = @('Zone2', 'Zone3')
            if ($agent.AoaiConnectionId) {
                if ($null -eq $approvedConnections) {
                    if ($whitelistEnforcedZones -contains $agentZone) {
                        $violations += [PSCustomObject]@{
                            ViolationType    = 'AuditControlBypass'
                            Description      = "AOAI connection whitelist could not be loaded for $agentZone agent — fail-closed; connection '$($agent.AoaiConnectionId)' cannot be validated"
                            Severity         = 'Critical'
                            RegulatoryContext = "Supports supervisory expectations under FINRA Rule 3110(a)(1) for AI vendor oversight; $($policy.RegulatoryContext)"
                        }
                    }
                } else {
                    $approvalKey = "$($agent.AoaiConnectionId)|$agentZone"
                    if (-not $approvedConnections.ContainsKey($approvalKey)) {
                        $violations += [PSCustomObject]@{
                            ViolationType    = 'UnapprovedAoaiConnection'
                            Description      = "AOAI connection '$($agent.AoaiConnectionId)' is not in the approved connections whitelist for $agentZone"
                            Severity         = $policy.WhitelistViolationSeverity
                            RegulatoryContext = "Supports supervisory expectations under FINRA Rule 3110(a)(1) for AI vendor oversight; $($policy.RegulatoryContext)"
                        }
                    }
                }
            } elseif ($agent.AzureOpenAIEnabled -eq 'Yes' -and ($whitelistEnforcedZones -contains $agentZone)) {
                # AOAI enabled but no connection ID extracted in a whitelist-enforced zone — fail-closed.
                $violations += [PSCustomObject]@{
                    ViolationType    = 'UnresolvedAoaiConnection'
                    Description      = "AOAI is enabled in $agentZone but the connection ID could not be extracted from agent configuration; whitelist validation cannot proceed"
                    Severity         = $policy.WhitelistViolationSeverity
                    RegulatoryContext = "Supports supervisory expectations under FINRA Rule 3110(a)(1) for AI vendor oversight; $($policy.RegulatoryContext)"
                }
            }

            # Rule 5: Model Knowledge toggle vs policy
            if ($agent.ModelKnowledgeEnabled -eq 'Yes' -and $policy.ModelKnowledgePolicy -in @('Disabled', 'RequiresApproval')) {
                $violations += [PSCustomObject]@{
                    ViolationType    = 'UnauthorizedModelKnowledge'
                    Description      = "Model Knowledge (AI general knowledge) is enabled but policy is '$($policy.ModelKnowledgePolicy)' in $agentZone"
                    Severity         = $policy.ModelKnowledgeViolationSeverity
                    RegulatoryContext = "Supports supervisory expectations under FINRA Rule 3110(a)(1) for AI knowledge sources; $($policy.RegulatoryContext)"
                }
            }

            # Rule 6: Semantic Search toggle vs policy
            if ($agent.SemanticSearchEnabled -eq 'Yes' -and $policy.SemanticSearchPolicy -eq 'RequiresApproval') {
                $violations += [PSCustomObject]@{
                    ViolationType    = 'UnauthorizedSemanticSearch'
                    Description      = "Semantic Search (Dataverse vector search) is enabled but requires explicit approval in $agentZone"
                    Severity         = $policy.SemanticSearchViolationSeverity
                    RegulatoryContext = "SOX Section 404 - internal control over data search capabilities; $($policy.RegulatoryContext)"
                }
            }

            # Determine overall compliance for this agent
            $isCompliant = $violations.Count -eq 0

            # Pick highest severity across all violations
            $worstSeverity = $null
            $worstViolationType = $null
            $combinedRegulatoryContext = $null

            if (-not $isCompliant) {
                $severityOrder = @('Critical', 'High', 'Medium', 'Warning')
                foreach ($sev in $severityOrder) {
                    $match = $violations | Where-Object { $_.Severity -eq $sev } | Select-Object -First 1
                    if ($match) {
                        $worstSeverity = $sev
                        $worstViolationType = $match.ViolationType
                        break
                    }
                }
                $combinedRegulatoryContext = ($violations | ForEach-Object { $_.Description }) -join '; '
            }

            # Build compliance result object
            $complianceResult = [PSCustomObject]@{
                AgentId                    = $agent.AgentId
                AgentName                  = $agent.AgentName
                EnvironmentId              = $agent.EnvironmentId
                EnvironmentDisplayName     = $agent.EnvironmentDisplayName
                Zone                       = $agentZone
                AzureOpenAIEnabled         = $agent.AzureOpenAIEnabled
                OrchestrationMode          = $agent.OrchestrationMode
                GenerativeAnswersNodeCount = $agent.GenerativeAnswersNodeCount
                AoaiConnectionId           = $agent.AoaiConnectionId
                ModelKnowledgeEnabled      = $agent.ModelKnowledgeEnabled
                SemanticSearchEnabled      = $agent.SemanticSearchEnabled
                IsCompliant                = $isCompliant
                Severity                   = if ($isCompliant) { $null } else { $worstSeverity }
                ViolationType              = if ($isCompliant) { $null } else { $worstViolationType }
                RegulatoryContext          = if ($isCompliant) { $null } else { $combinedRegulatoryContext }
                AgentStatus                = $agent.AgentStatus
                ViolationDetails           = if ($isCompliant) { @() } else { $violations }
            }

            # Update counters
            if ($isCompliant) {
                $compliantCount++
            } else {
                $violationCount++
                if ($worstSeverity -and $severityCounts.ContainsKey($worstSeverity)) {
                    $severityCounts[$worstSeverity]++
                }
            }

            # Emit to pipeline if violation or IncludeCompliant
            if (-not $isCompliant -or $IncludeCompliant) {
                $complianceResult
            }
        }
        } catch {
            Write-Error "Failed to evaluate agent compliance: $($_.Exception.Message)"
            throw
        }
    }

    end {
        try {
        #region Summary Statistics

        Write-Verbose "Compliance check complete:"
        Write-Verbose "  Total agents scanned: $totalCount"
        Write-Verbose "  Compliant: $compliantCount"
        Write-Verbose "  Violations: $violationCount"

        if ($violationCount -gt 0) {
            Write-Verbose "  Violations by severity:"
            foreach ($sev in @('Critical', 'High', 'Medium', 'Warning')) {
                if ($severityCounts[$sev] -gt 0) {
                    Write-Verbose "    $($sev): $($severityCounts[$sev])"
                }
            }
        }

        #endregion
        } catch {
            Write-Error "Failed to summarize compliance results: $($_.Exception.Message)"
            throw
        }
    }
}
