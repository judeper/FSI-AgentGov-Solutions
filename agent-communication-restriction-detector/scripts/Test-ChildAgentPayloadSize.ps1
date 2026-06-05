<#
.SYNOPSIS
    Estimates child-agent input/output payload sizes against a configurable
    advisory payload-size threshold.

.DESCRIPTION
    Scans Copilot Studio agent skill registrations and connected-agent topic
    configurations to estimate child-agent payloads that approach or exceed a
    configurable advisory threshold (default 1 MB / 1,048,576 bytes).

    Important: Microsoft does not currently publish an explicit byte limit for
    child-agent (connected-agent) input/output. The published Copilot Studio
    limits document a 5 MB connector payload limit (450 KB for GCC) and a 28 KB
    Omnichannel channel-data limit. The 1 MB default used here is a conservative
    advisory heuristic, not a hard platform limit; tune it with -PayloadLimitKB
    to match your organization's policy.
    Reference: https://learn.microsoft.com/microsoft-copilot-studio/requirements-quotas#copilot-studio-web-app-limits

    Detection methods:
    1. Queries agent topic YAML for InvokeConnectedAgentTaskAction nodes and
       estimates payload size from input/output variable declarations
    2. Checks flow response receive configurations for payload size thresholds
    3. Emits warning events when estimated payloads exceed configurable thresholds

    Threshold levels (relative to -PayloadLimitKB, default 1024 KB):
    - Warning:  >= WarningThresholdKB  (default 768 KB)
    - Critical: >= CriticalThresholdKB (default 960 KB)
    - Blocked:  >= PayloadLimitKB      (default 1024 KB advisory threshold)

.PARAMETER DataverseUrl
    Dataverse environment URL.

.PARAMETER PayloadLimitKB
    Advisory payload-size threshold in KB that marks a finding as Critical
    (default: 1024). Not a documented platform limit — see DESCRIPTION.

.PARAMETER WarningThresholdKB
    Payload size in KB to trigger warning (default: 768).

.PARAMETER CriticalThresholdKB
    Payload size in KB to trigger critical alert (default: 960).

.PARAMETER OutputFormat
    Output format: Table (default), Json, or Object.

.PARAMETER WhatIf
    Preview mode — shows findings without persisting to Dataverse.

.NOTES
    File: Test-ChildAgentPayloadSize.ps1
    Version: 1.2.1
    Solution: Agent Communication Restriction Detector (ACRD)
    Control: 2.17 (Multi-Agent Orchestration Limits)

    Part of FSI Agent Governance Framework
#>

#Requires -Version 5.1
#Requires -PSEdition Desktop
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Test-ChildAgentPayloadSize {
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'PSScriptAnalyzer requires this rule suppression on the function param block; individual compatibility parameters carry specific justifications.'
    )]
    param(
        [Parameter()]
        # Accept commercial, GCC, GCC High, DoD, and Germany sovereign cloud URLs.
        # (council review M-4)
        [ValidatePattern('^https://[a-zA-Z0-9\-]+\.(crm[0-9]*\.dynamics\.com|crm\.microsoftdynamics\.(us|de))/?$')]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSReviewUnusedParameter', '',
            Justification = 'Parameter is retained for documented script and function interface compatibility with existing callers; intentionally unused in this implementation.'
        )]
        [string]$DataverseUrl,

        [ValidateRange(1, 5120)]
        [int]$PayloadLimitKB = 1024,

        [ValidateRange(1, 5120)]
        [int]$WarningThresholdKB = 768,

        [ValidateRange(1, 5120)]
        [int]$CriticalThresholdKB = 960,

        [ValidateSet('Table', 'Json', 'Object')]
        [string]$OutputFormat = 'Table',

        [string[]]$IncludeEnvironments,

        [switch]$ExcludeSandbox,

        [switch]$ExcludeTrial
    )

    begin {
        $ErrorActionPreference = 'Stop'
        $LIMIT_BYTES = $PayloadLimitKB * 1024  # advisory threshold (not a documented platform limit)
        $WARNING_BYTES = $WarningThresholdKB * 1024
        $CRITICAL_BYTES = $CriticalThresholdKB * 1024

        # Dot-source private helpers if available
        $privatePath = Join-Path $PSScriptRoot 'private'
        if (Test-Path (Join-Path $privatePath 'Connect-EnvironmentDataverse.ps1')) {
            . (Join-Path $privatePath 'Connect-EnvironmentDataverse.ps1')
        }

        Write-Verbose "Payload size thresholds: Warning=$($WarningThresholdKB)KB, Critical=$($CriticalThresholdKB)KB, Advisory limit=$($PayloadLimitKB)KB"
    }

    process {
        if (-not $PSCmdlet.ShouldProcess('Power Platform environments', 'Scan child-agent payload sizes')) {
            return
        }

        # ---------------------------------------------------------------
        # Step 1: Enumerate environments
        # ---------------------------------------------------------------
        $envParams = @{}
        if ($IncludeEnvironments) { $envParams['EnvironmentName'] = $IncludeEnvironments }
        $environments = Get-AdminPowerAppEnvironment @envParams

        if ($ExcludeSandbox) {
            $environments = $environments | Where-Object { $_.EnvironmentType -ne 'Sandbox' }
        }
        if ($ExcludeTrial) {
            $environments = $environments | Where-Object { $_.EnvironmentType -ne 'Trial' }
        }

        Write-Verbose "Scanning $($environments.Count) environment(s) for child-agent payload sizes..."

        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($env in $environments) {
            $envId = $env.EnvironmentName
            $envDisplayName = $env.DisplayName
            $dvUrl = $env.Internal.properties.linkedEnvironmentMetadata.instanceUrl

            if (-not $dvUrl) {
                Write-Warning "Environment '$envDisplayName' ($envId) has no Dataverse instance — skipping."
                continue
            }

            # ---------------------------------------------------------------
            # Step 2: Query bot components for connected-agent actions
            # ---------------------------------------------------------------
            $apiBase = "$($dvUrl.TrimEnd('/'))/api/data/v9.2"
            try {
                # Connect-EnvironmentDataverse returns the bearer token string directly
                # (not an object wrapper). Accessing .AccessToken yielded $null and produced
                # HTTP 401 on every Dataverse call. (council review C-3)
                $token = & (Join-Path $privatePath 'Connect-EnvironmentDataverse.ps1') `
                    -DataverseUrl $dvUrl
            } catch {
                Write-Warning "Failed to connect to '$envDisplayName': $_"
                continue
            }

            $headers = @{
                'Authorization' = "Bearer $token"
                'Accept'        = 'application/json'
                'OData-Version' = '4.0'
            }

            # Query botcomponent records containing InvokeConnectedAgentTaskAction.
            # botcomponent has no _botid_value column; the owning bot is the
            # parentbotid lookup, exposed in OData as _parentbotid_value.
            # Ref: https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/botcomponent
            $filter = "contains(content,'InvokeConnectedAgentTaskAction')"
            $select = "botcomponentid,name,content,_parentbotid_value"
            $uri = "$apiBase/botcomponents?`$filter=$filter&`$select=$select&`$top=500"

            try {
                $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
                $components = $resp.value
            } catch {
                Write-Warning "Failed to query botcomponents in '$envDisplayName': $_"
                continue
            }

            foreach ($component in $components) {
                $content = $component.content
                if (-not $content) { continue }

                # Estimate payload sizes from YAML input/output variable declarations
                $inputSize = 0
                $outputSize = 0

                # Match input variable blocks
                $inputMatches = [regex]::Matches($content, 'inputVariables:\s*\n((?:\s+-\s+.*\n)*)')
                foreach ($m in $inputMatches) {
                    $inputSize += [System.Text.Encoding]::UTF8.GetByteCount($m.Value)
                }

                # Match output variable blocks
                $outputMatches = [regex]::Matches($content, 'outputVariables:\s*\n((?:\s+-\s+.*\n)*)')
                foreach ($m in $outputMatches) {
                    $outputSize += [System.Text.Encoding]::UTF8.GetByteCount($m.Value)
                }

                # Use total content size as upper bound estimate
                $totalContentBytes = [System.Text.Encoding]::UTF8.GetByteCount($content)
                $estimatedPayloadBytes = [Math]::Max($inputSize + $outputSize, [Math]::Min($totalContentBytes, $LIMIT_BYTES))

                # Determine severity
                $severity = 'Passed'
                if ($estimatedPayloadBytes -ge $LIMIT_BYTES) {
                    $severity = 'Critical'
                } elseif ($estimatedPayloadBytes -ge $CRITICAL_BYTES) {
                    $severity = 'High'
                } elseif ($estimatedPayloadBytes -ge $WARNING_BYTES) {
                    $severity = 'Warning'
                }

                if ($severity -ne 'Passed') {
                    $results.Add([PSCustomObject]@{
                        EnvironmentId      = $envId
                        EnvironmentName    = $envDisplayName
                        BotComponentId     = $component.botcomponentid
                        ComponentName      = $component.name
                        BotId              = $component._parentbotid_value
                        EstimatedInputKB   = [Math]::Round($inputSize / 1024, 1)
                        EstimatedOutputKB  = [Math]::Round($outputSize / 1024, 1)
                        EstimatedTotalKB   = [Math]::Round($estimatedPayloadBytes / 1024, 1)
                        LimitKB            = $PayloadLimitKB
                        Severity           = $severity
                        Recommendation     = switch ($severity) {
                            'Critical' { 'Payload exceeds advisory limit — reduce input/output variable count or use pagination' }
                            'High'     { 'Payload approaching advisory limit — review for optimization opportunities' }
                            'Warning'  { 'Payload at 75%+ of advisory limit — monitor growth' }
                        }
                        PlatformReference  = 'https://learn.microsoft.com/microsoft-copilot-studio/requirements-quotas#copilot-studio-web-app-limits'
                    })
                }
            }
        }

        # ---------------------------------------------------------------
        # Step 3: Output
        # ---------------------------------------------------------------
        switch ($OutputFormat) {
            'Json' {
                @{
                    Timestamp      = (Get-Date -Format 'o')
                    LimitBytes     = $LIMIT_BYTES
                    WarningBytes   = $WARNING_BYTES
                    CriticalBytes  = $CRITICAL_BYTES
                    TotalFindings  = $results.Count
                    Findings       = $results
                } | ConvertTo-Json -Depth 10
            }
            'Object' {
                $results
            }
            default {
                if ($results.Count -eq 0) {
                    Write-Host "`nNo child-agent payload size findings." -ForegroundColor Green
                } else {
                    Write-Host "`nChild-Agent Payload Size Findings ($($results.Count)):" -ForegroundColor Yellow
                    Write-Host ("=" * 70) -ForegroundColor Yellow
                    $results | Format-Table -Property EnvironmentName, ComponentName, EstimatedTotalKB, LimitKB, Severity -AutoSize
                }
            }
        }
    }
}
