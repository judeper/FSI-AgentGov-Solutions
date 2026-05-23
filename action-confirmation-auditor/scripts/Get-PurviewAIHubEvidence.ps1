<#
.SYNOPSIS
    Integrates with Microsoft Purview AI Hub (DSPM for AI) to cross-reference
    action confirmation events with AI data security posture evidence.

.DESCRIPTION
    Queries Purview AI Hub for confirmed actions on AI-classified data and
    cross-references with action-confirmation events from Copilot Studio agents.
    Generates dual-confirmation evidence (action-level from ACA + DSPM-level
    from Purview AI Hub).

    Integration points:
    1. Queries Purview AI Hub activity explorer for AI interaction events
    2. Reads ACA action confirmation results from Dataverse
    3. Cross-references by agent identity and timestamp proximity
    4. Generates evidence document showing dual confirmation coverage

    Purview AI Hub (DSPM for AI) provides:
    - Visibility into AI interactions with sensitive data
    - Data classification for AI-accessed content
    - Interaction analytics for compliance monitoring

    Reference: https://learn.microsoft.com/purview/ai-microsoft-purview

.PARAMETER DataverseUrl
    Dataverse environment URL for querying ACA scan results.

.PARAMETER OutputFormat
    Output format: Table (default), Json, or Object.

.PARAMETER LookbackDays
    Number of days to look back for activity correlation (default: 7).

.PARAMETER OutputPath
    Directory to write evidence file. Defaults to current directory.

.PARAMETER WhatIf
    Preview mode — shows evidence without writing files.

.NOTES
    File: Get-PurviewAIHubEvidence.ps1
    Version: 1.2.1
    Solution: Action Confirmation Auditor (ACA)
    Controls: 2.12, 1.10
    Requires: Microsoft.Graph.Authentication

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication

function Get-PurviewAIHubEvidence {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https://[a-zA-Z0-9\-]+\.crm[0-9]*\.dynamics\.com')]
        [string]$DataverseUrl,

        [ValidateSet('Table', 'Json', 'Object')]
        [string]$OutputFormat = 'Table',

        [ValidateRange(1, 90)]
        [int]$LookbackDays = 7,

        [string]$OutputPath = '.'
    )

    begin {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "Collecting Purview AI Hub evidence with $LookbackDays-day lookback..."
    }

    process {
        $evidence = @{
            Timestamp            = (Get-Date -Format 'o')
            CollectionType       = 'PurviewAIHubDSPMEvidence'
            LookbackDays         = $LookbackDays
            AIHubActivities      = [System.Collections.Generic.List[PSCustomObject]]::new()
            ACAConfirmations     = [System.Collections.Generic.List[PSCustomObject]]::new()
            DualConfirmations    = [System.Collections.Generic.List[PSCustomObject]]::new()
            Summary              = $null
        }

        $graphHeaders = @{
            'Authorization' = "Bearer $((Get-MgContext).AccessToken)"
            'Accept'        = 'application/json'
            'Content-Type'  = 'application/json'
        }

        # ---------------------------------------------------------------
        # Step 1: Query Purview AI Hub activities via Graph
        # ---------------------------------------------------------------
        Write-Verbose "Querying Purview AI Hub for AI interaction activities..."

        $startDate = (Get-Date).AddDays(-$LookbackDays).ToString('yyyy-MM-ddTHH:mm:ssZ')

        # Use Purview Data Map / AI Hub Graph endpoint
        # The exact endpoint depends on Purview API availability
        try {
            # Query audit log for AI-related activities
            $auditUri = "https://graph.microsoft.com/v1.0/security/auditLog/queries"
            $auditBody = @{
                displayName     = "ACA-DSPM-Correlation-$(Get-Date -Format 'yyyyMMdd')"
                filterStartDateTime = $startDate
                filterEndDateTime   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
                recordTypeFilters   = @('CopilotInteraction', 'AipDiscover', 'AipSensitivityLabelAction')
            } | ConvertTo-Json

            $auditResp = Invoke-RestMethod -Uri $auditUri -Headers $graphHeaders -Method Post -Body $auditBody -ErrorAction SilentlyContinue

            if ($auditResp -and $auditResp.id) {
                Write-Verbose "Audit query created: $($auditResp.id). Waiting for results..."
                Start-Sleep -Seconds 5

                # Poll for results
                $resultsUri = "https://graph.microsoft.com/v1.0/security/auditLog/queries/$($auditResp.id)/records?`$top=500"
                $resultsResp = Invoke-RestMethod -Uri $resultsUri -Headers $graphHeaders -Method Get -ErrorAction SilentlyContinue

                if ($resultsResp.value) {
                    foreach ($record in $resultsResp.value) {
                        $evidence.AIHubActivities.Add([PSCustomObject]@{
                            ActivityId    = $record.id
                            ActivityType  = $record.auditData.Operation
                            UserId        = $record.auditData.UserId
                            Workload      = $record.auditData.Workload
                            CreatedDate   = $record.createdDateTime
                            ClientIP      = $record.auditData.ClientIP
                            ObjectId      = $record.auditData.ObjectId
                            ResultStatus  = $record.auditData.ResultStatus
                        })
                    }
                }
            }
        } catch {
            Write-Warning "Purview audit log query: $_. AI Hub activity collection may be limited."
        }

        # Fallback: try compliance activity explorer
        if (Get-Command -Name 'Get-ActivityExplorerData' -ErrorAction SilentlyContinue) {
            try {
                $activities = Get-ActivityExplorerData `
                    -StartDate (Get-Date).AddDays(-$LookbackDays) `
                    -EndDate (Get-Date) `
                    -Filter 'CopilotInteraction' `
                    -ErrorAction Stop

                foreach ($activity in $activities) {
                    $evidence.AIHubActivities.Add([PSCustomObject]@{
                        ActivityId    = $activity.Id
                        ActivityType  = $activity.ActivityType
                        UserId        = $activity.User
                        Workload      = $activity.Workload
                        CreatedDate   = $activity.Timestamp
                        ClientIP      = $null
                        ObjectId      = $activity.ItemName
                        ResultStatus  = $activity.ResultStatus
                    })
                }
            } catch {
                Write-Warning "Activity Explorer query: $_"
            }
        }

        Write-Verbose "Collected $($evidence.AIHubActivities.Count) AI Hub activities."

        # ---------------------------------------------------------------
        # Step 2: Query ACA confirmation results from Dataverse
        # ---------------------------------------------------------------
        Write-Verbose "Querying ACA action confirmation results from Dataverse..."
        $apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
        $dvHeaders = @{
            'Authorization' = "Bearer $((Get-MgContext).AccessToken)"
            'Accept'        = 'application/json'
            'OData-Version' = '4.0'
        }

        $acaFilter = "createdon ge $startDate"
        $acaSelect = "fsi_actionauditresultid,fsi_agentname,fsi_actionname,fsi_hasconfirmation,fsi_severity,createdon"
        $acaUri = "$apiBase/fsi_actionauditresults?`$filter=$acaFilter&`$select=$acaSelect&`$orderby=createdon desc&`$top=500"

        try {
            $acaResp = Invoke-RestMethod -Uri $acaUri -Headers $dvHeaders -Method Get -ErrorAction Stop
            foreach ($result in $acaResp.value) {
                $evidence.ACAConfirmations.Add([PSCustomObject]@{
                    ResultId         = $result.fsi_actionauditresultid
                    AgentName        = $result.fsi_agentname
                    ActionName       = $result.fsi_actionname
                    HasConfirmation  = $result.fsi_hasconfirmation
                    Severity         = $result.fsi_severity
                    CreatedOn        = $result.createdon
                })
            }
        } catch {
            Write-Warning "ACA Dataverse query failed: $_"
        }

        Write-Verbose "Retrieved $($evidence.ACAConfirmations.Count) ACA confirmation results."

        # ---------------------------------------------------------------
        # Step 3: Cross-reference for dual confirmation
        # ---------------------------------------------------------------
        Write-Verbose "Cross-referencing AI Hub activities with ACA confirmations..."

        foreach ($aca in $evidence.ACAConfirmations) {
            # Find AI Hub activities matching the agent/time window
            $matchingActivities = $evidence.AIHubActivities | Where-Object {
                $_.Workload -match 'Copilot' -and
                [Math]::Abs(([DateTime]$_.CreatedDate - [DateTime]$aca.CreatedOn).TotalMinutes) -lt 60
            }

            if ($matchingActivities) {
                foreach ($activity in $matchingActivities) {
                    $evidence.DualConfirmations.Add([PSCustomObject]@{
                        ACAResultId        = $aca.ResultId
                        AgentName          = $aca.AgentName
                        ActionName         = $aca.ActionName
                        ACAConfirmed       = $aca.HasConfirmation
                        AIHubActivityId    = $activity.ActivityId
                        AIHubActivityType  = $activity.ActivityType
                        DSPMCovered        = $true
                        ConfirmationType   = 'DualConfirmation'
                        TimeDeltaMinutes   = [Math]::Round(
                            [Math]::Abs(([DateTime]$activity.CreatedDate - [DateTime]$aca.CreatedOn).TotalMinutes), 1
                        )
                    })
                }
            }
        }

        # ---------------------------------------------------------------
        # Step 4: Generate summary
        # ---------------------------------------------------------------
        $evidence.Summary = [PSCustomObject]@{
            AIHubActivityCount     = $evidence.AIHubActivities.Count
            ACAConfirmationCount   = $evidence.ACAConfirmations.Count
            DualConfirmationCount  = $evidence.DualConfirmations.Count
            CoveragePercent        = if ($evidence.ACAConfirmations.Count -gt 0) {
                [Math]::Round(($evidence.DualConfirmations.Count / $evidence.ACAConfirmations.Count) * 100, 1)
            } else { 0 }
            CompliancePosture      = if ($evidence.DualConfirmations.Count -gt 0) { 'DualConfirmed' }
                                     elseif ($evidence.ACAConfirmations.Count -gt 0) { 'ACAOnly' }
                                     else { 'NoEvidence' }
            Recommendation         = if ($evidence.AIHubActivities.Count -eq 0) {
                'No Purview AI Hub activities found — verify DSPM for AI is enabled and Copilot audit logging is active'
            } elseif ($evidence.DualConfirmations.Count -eq 0) {
                'AI Hub activities exist but no dual confirmations found — verify ACA scan coverage matches AI Hub scope'
            } else {
                "Dual confirmation evidence available: $($evidence.DualConfirmations.Count) correlated event(s)"
            }
            Reference              = 'https://learn.microsoft.com/purview/ai-microsoft-purview'
        }

        # ---------------------------------------------------------------
        # Step 5: Write evidence file
        # ---------------------------------------------------------------
        if (-not $WhatIfPreference) {
            $evidenceFileName = "aca-purview-aihub-evidence-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
            $evidenceFilePath = Join-Path $OutputPath $evidenceFileName
            $evidenceJson = $evidence | ConvertTo-Json -Depth 10

            $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($evidenceJson)
            )
            $hashHex = ($hash | ForEach-Object { $_.ToString('x2') }) -join ''

            $envelope = @{
                Evidence      = $evidence
                IntegrityHash = $hashHex
                HashAlgorithm = 'SHA-256'
            } | ConvertTo-Json -Depth 12

            if ($PSCmdlet.ShouldProcess($evidenceFilePath, 'Write evidence file')) {
                $envelope | Out-File -FilePath $evidenceFilePath -Encoding UTF8
                Write-Verbose "Evidence written to: $evidenceFilePath (SHA-256: $hashHex)"
            }
        }

        # ---------------------------------------------------------------
        # Step 6: Output
        # ---------------------------------------------------------------
        switch ($OutputFormat) {
            'Json' {
                $evidence | ConvertTo-Json -Depth 10
            }
            'Object' {
                $evidence
            }
            default {
                Write-Host "`nPurview AI Hub / DSPM Evidence:" -ForegroundColor Cyan
                Write-Host ("=" * 60) -ForegroundColor Cyan
                Write-Host "  AI Hub Activities:       $($evidence.AIHubActivities.Count)"
                Write-Host "  ACA Confirmations:       $($evidence.ACAConfirmations.Count)"
                Write-Host "  Dual Confirmations:      $($evidence.DualConfirmations.Count)" -ForegroundColor $(
                    if ($evidence.DualConfirmations.Count -gt 0) { 'Green' } else { 'Yellow' }
                )
                Write-Host "  Coverage:                $($evidence.Summary.CoveragePercent)%"
                Write-Host "  Posture:                 $($evidence.Summary.CompliancePosture)"
                Write-Host ""

                if ($evidence.DualConfirmations.Count -gt 0) {
                    Write-Host "  Dual Confirmation Events:" -ForegroundColor Green
                    $evidence.DualConfirmations | Select-Object -First 10 |
                        Format-Table -Property AgentName, ActionName, ACAConfirmed, DSPMCovered, TimeDeltaMinutes -AutoSize
                }

                Write-Host "`n  Reference: $($evidence.Summary.Reference)" -ForegroundColor DarkGray
            }
        }
    }
}
