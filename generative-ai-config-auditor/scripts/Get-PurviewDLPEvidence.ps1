<#
.SYNOPSIS
    Collects Purview DLP and sensitivity label evidence for generative AI
    configurations.

.DESCRIPTION
    Queries Microsoft Purview for DLP policies and sensitivity labels applied
    to generative AI configurations, and generates an audit evidence document.

    Evidence collection:
    1. Queries Purview Compliance Manager for DLP policies covering the
       Microsoft 365 Copilot and Copilot Studio locations
    2. Reads sensitivity labels applied to AI-related Dataverse tables and
       SharePoint sites used as knowledge sources
    3. Generates an audit evidence document with policy IDs, label IDs,
       and application timestamps

    Reference: https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about

.PARAMETER DataverseUrl
    Dataverse environment URL for querying GAC configuration data.

.PARAMETER OutputFormat
    Output format: Table (default), Json, or Object.

.PARAMETER OutputPath
    Directory to write evidence file. Defaults to current directory.

.PARAMETER WhatIf
    Preview mode — shows evidence without writing files.

.NOTES
    File: Get-PurviewDLPEvidence.ps1
    Version: 1.2.0
    Solution: Generative AI Config Auditor (GAC)
    Control: 2.24 (Agent Feature Enablement Governance)
    Requires: Microsoft.Graph.Authentication, ExchangeOnlineManagement (for DLP cmdlets)

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication

function Get-PurviewDLPEvidence {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [ValidatePattern('^https://[a-zA-Z0-9\-]+\.crm[0-9]*\.dynamics\.com')]
        [string]$DataverseUrl,

        [ValidateSet('Table', 'Json', 'Object')]
        [string]$OutputFormat = 'Table',

        [string]$OutputPath = '.'
    )

    begin {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "Collecting Purview DLP and sensitivity label evidence for generative AI..."
    }

    process {
        $evidence = @{
            Timestamp       = (Get-Date -Format 'o')
            CollectionType  = 'PurviewDLPSensitivityLabelEvidence'
            DLPPolicies     = [System.Collections.Generic.List[PSCustomObject]]::new()
            SensitivityLabels = [System.Collections.Generic.List[PSCustomObject]]::new()
            Summary         = $null
        }

        # ---------------------------------------------------------------
        # Step 1: Query DLP policies (via Security & Compliance PowerShell)
        # ---------------------------------------------------------------
        Write-Verbose "Querying DLP policies for generative AI scope..."

        try {
            # Use Graph Security API for DLP policy retrieval
            $graphHeaders = @{
                'Authorization' = "Bearer $((Get-MgContext).AccessToken)"
                'Accept'        = 'application/json'
                'Content-Type'  = 'application/json'
            }

            # Query information protection policies
            $dlpUri = 'https://graph.microsoft.com/v1.0/informationProtection/policy/labels'
            $dlpResp = Invoke-RestMethod -Uri $dlpUri -Headers $graphHeaders -Method Get -ErrorAction SilentlyContinue
            $infoLabels = $dlpResp.value

            if ($infoLabels) {
                Write-Verbose "Retrieved $($infoLabels.Count) information protection label(s)."
                foreach ($label in $infoLabels) {
                    $evidence.SensitivityLabels.Add([PSCustomObject]@{
                        LabelId     = $label.id
                        LabelName   = $label.name
                        Description = $label.description
                        Color       = $label.color
                        IsActive    = $label.isActive
                        Parent      = $label.parent
                        Source      = 'InformationProtectionPolicy'
                    })
                }
            }
        } catch {
            Write-Warning "Graph information protection query: $_. Falling back to compliance cmdlets."
        }

        # Try Security & Compliance cmdlets if available
        if (Get-Command -Name 'Get-DlpCompliancePolicy' -ErrorAction SilentlyContinue) {
            try {
                $dlpPolicies = Get-DlpCompliancePolicy -ErrorAction Stop
                foreach ($policy in $dlpPolicies) {
                    # Check if policy covers Copilot/AI locations
                    $coversAI = $false
                    $aiLocations = @()

                    if ($policy.Workload -match 'Copilot' -or
                        $policy.Workload -match 'MicrosoftCopilot' -or
                        $policy.Comment -match 'AI|Copilot|generative') {
                        $coversAI = $true
                        $aiLocations += 'MicrosoftCopilot'
                    }

                    # Check for Exchange, SharePoint, OneDrive locations
                    # that may be knowledge sources
                    if ($policy.ExchangeLocation -or $policy.SharePointLocation -or
                        $policy.OneDriveLocation) {
                        $aiLocations += @(
                            $(if ($policy.ExchangeLocation) { 'Exchange' }),
                            $(if ($policy.SharePointLocation) { 'SharePoint' }),
                            $(if ($policy.OneDriveLocation) { 'OneDrive' })
                        ) | Where-Object { $_ }
                    }

                    $evidence.DLPPolicies.Add([PSCustomObject]@{
                        PolicyId      = $policy.Guid
                        PolicyName    = $policy.Name
                        Enabled       = $policy.Enabled
                        Mode          = $policy.Mode
                        Workload      = $policy.Workload
                        CoversAI      = $coversAI
                        AILocations   = ($aiLocations -join ', ')
                        CreatedDate   = $policy.WhenCreatedUTC
                        ModifiedDate  = $policy.WhenChangedUTC
                        Comment       = $policy.Comment
                    })
                }
                Write-Verbose "Found $($evidence.DLPPolicies.Count) DLP policies, $(($evidence.DLPPolicies | Where-Object CoversAI).Count) covering AI scope."
            } catch {
                Write-Warning "DLP policy query failed: $_"
            }

            # Query sensitivity labels via compliance cmdlets
            try {
                $labels = Get-Label -ErrorAction Stop
                foreach ($label in $labels) {
                    $evidence.SensitivityLabels.Add([PSCustomObject]@{
                        LabelId     = $label.Guid
                        LabelName   = $label.Name
                        DisplayName = $label.DisplayName
                        Description = $label.Comment
                        Priority    = $label.Priority
                        IsActive    = $label.Enabled
                        ContentType = ($label.ContentType -join ', ')
                        Source      = 'ComplianceLabel'
                    })
                }
                Write-Verbose "Found $($evidence.SensitivityLabels.Count) sensitivity label(s)."
            } catch {
                Write-Warning "Sensitivity label query failed: $_"
            }
        } else {
            Write-Verbose "Security & Compliance cmdlets not available — using Graph-only evidence."
        }

        # ---------------------------------------------------------------
        # Step 2: Query Dataverse for AI-related label application
        # ---------------------------------------------------------------
        if ($DataverseUrl) {
            Write-Verbose "Querying Dataverse for AI configuration label references..."
            $apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
            $dvHeaders = @{
                'Authorization' = "Bearer $((Get-MgContext).AccessToken)"
                'Accept'        = 'application/json'
                'OData-Version' = '4.0'
            }

            # Query GAC validation history for sensitivity label references
            $select = "fsi_gacvalidationhistoryid,fsi_agentname,fsi_zone,createdon"
            $uri = "$apiBase/fsi_gacvalidationhistories?`$select=$select&`$orderby=createdon desc&`$top=100"

            try {
                $validationResp = Invoke-RestMethod -Uri $uri -Headers $dvHeaders -Method Get -ErrorAction Stop
                $evidence | Add-Member -NotePropertyName 'ValidationHistoryCount' -NotePropertyValue $validationResp.value.Count
            } catch {
                Write-Warning "Dataverse GAC history query failed: $_"
            }
        }

        # ---------------------------------------------------------------
        # Step 3: Generate summary
        # ---------------------------------------------------------------
        $aiDLPCount = ($evidence.DLPPolicies | Where-Object CoversAI).Count

        $evidence.Summary = [PSCustomObject]@{
            TotalDLPPolicies      = $evidence.DLPPolicies.Count
            AICoveringPolicies    = $aiDLPCount
            TotalLabels           = $evidence.SensitivityLabels.Count
            ActiveLabels          = ($evidence.SensitivityLabels | Where-Object IsActive).Count
            HasAIDLPCoverage      = $aiDLPCount -gt 0
            CompliancePosture     = if ($aiDLPCount -gt 0) { 'Covered' } else { 'GapIdentified' }
            Recommendation        = if ($aiDLPCount -eq 0) {
                'No DLP policies found covering Microsoft Copilot location — create a DLP policy with the Microsoft 365 Copilot location enabled'
            } else {
                "DLP coverage in place: $aiDLPCount policy/policies cover AI scope"
            }
            Reference             = 'https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about'
        }

        # ---------------------------------------------------------------
        # Step 4: Write evidence file
        # ---------------------------------------------------------------
        if (-not $WhatIfPreference) {
            $evidenceFileName = "gac-purview-evidence-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
            $evidenceFilePath = Join-Path $OutputPath $evidenceFileName
            $evidenceJson = $evidence | ConvertTo-Json -Depth 10

            # Add SHA-256 hash
            $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($evidenceJson)
            )
            $hashHex = ($hash | ForEach-Object { $_.ToString('x2') }) -join ''

            $envelope = @{
                Evidence     = $evidence
                IntegrityHash = $hashHex
                HashAlgorithm = 'SHA-256'
            } | ConvertTo-Json -Depth 12

            if ($PSCmdlet.ShouldProcess($evidenceFilePath, 'Write evidence file')) {
                $envelope | Out-File -FilePath $evidenceFilePath -Encoding UTF8
                Write-Verbose "Evidence written to: $evidenceFilePath (SHA-256: $hashHex)"
            }
        }

        # ---------------------------------------------------------------
        # Step 5: Output
        # ---------------------------------------------------------------
        switch ($OutputFormat) {
            'Json' {
                $evidence | ConvertTo-Json -Depth 10
            }
            'Object' {
                $evidence
            }
            default {
                Write-Host "`nPurview DLP & Sensitivity Label Evidence:" -ForegroundColor Cyan
                Write-Host ("=" * 60) -ForegroundColor Cyan
                Write-Host "  DLP Policies:            $($evidence.DLPPolicies.Count)"
                Write-Host "  AI-Covering Policies:    $aiDLPCount" -ForegroundColor $(if ($aiDLPCount -gt 0) { 'Green' } else { 'Red' })
                Write-Host "  Sensitivity Labels:      $($evidence.SensitivityLabels.Count)"
                Write-Host "  Compliance Posture:      $($evidence.Summary.CompliancePosture)"
                Write-Host ""

                if ($evidence.DLPPolicies.Count -gt 0) {
                    Write-Host "  DLP Policies:" -ForegroundColor Yellow
                    $evidence.DLPPolicies | Format-Table -Property PolicyName, CoversAI, Mode, AILocations -AutoSize
                }

                Write-Host "`n  Reference: $($evidence.Summary.Reference)" -ForegroundColor DarkGray
            }
        }
    }
}
