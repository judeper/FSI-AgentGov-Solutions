<#
.SYNOPSIS
    Compares agent file upload settings against zone-specific governance policies.

.DESCRIPTION
    Takes agent file upload settings (from Get-AgentFileUploadSettings) and
    evaluates each agent's file upload enabled status against the expected policy
    for its zone. Includes content moderation cross-check for agents with file
    uploads enabled. Returns compliance results with severity classification
    and regulatory context.

.NOTES
    File: Compare-FileUploadCompliance.ps1
    Version: 1.0.0
    Solution: File Upload Security Configurator (v8)
#>

function Compare-FileUploadCompliance {
    <#
    .SYNOPSIS
        Compares agent file upload settings against zone-specific governance policies.

    .DESCRIPTION
        Takes agent file upload settings (from Get-AgentFileUploadSettings) and
        evaluates each agent's file upload enabled status against the expected policy
        for its zone. Includes content moderation cross-check: agents with file
        uploads enabled must meet minimum moderation level per zone policy.

        By default, only non-compliant agents are returned. Use -IncludeCompliant
        to include all agents in the output.

    .PARAMETER AgentSettings
        Pipeline input: PSCustomObject[] from Get-AgentFileUploadSettings.
        Each object must include AgentId, AgentName, FileUploadEnabled,
        ContentModerationLevel, EnvironmentDisplayName, Zone, and AgentStatus.

    .PARAMETER BaselinePath
        Path to fileupload-baseline.json. Defaults to ../templates/fileupload-baseline.json
        relative to the script location.

    .PARAMETER IncludeCompliant
        Include compliant agents in output. By default, only violations are returned.

    .EXAMPLE
        . ./Get-AgentFileUploadSettings.ps1
        . ./Compare-FileUploadCompliance.ps1
        Get-AgentFileUploadSettings | Compare-FileUploadCompliance

        Retrieves all agents and returns only non-compliant agents with severity.

    .EXAMPLE
        . ./Get-AgentFileUploadSettings.ps1
        . ./Compare-FileUploadCompliance.ps1
        Get-AgentFileUploadSettings -ExcludeSandbox | Compare-FileUploadCompliance -IncludeCompliant

        Returns compliance status for all agents including compliant ones.

    .OUTPUTS
        PSCustomObject[] — One object per agent with properties:
        AgentId, AgentName, EnvironmentId, EnvironmentDisplayName, Zone,
        FileUploadEnabled, ExpectedFileUpload, ContentModerationLevel,
        ExpectedModerationLevel, IsCompliant, FileUploadCompliant,
        ModerationCompliant, Severity, ViolationType, RegulatoryContext, AgentStatus
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]]$AgentSettings,

        [Parameter()]
        [string]$BaselinePath,

        [Parameter()]
        [switch]$IncludeCompliant
    )

    begin {
        #region Load Baseline

        if (-not $BaselinePath) {
            $BaselinePath = Join-Path $PSScriptRoot '..' 'templates' 'fileupload-baseline.json'
        }

        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BaselinePath)

        if (-not (Test-Path $resolvedPath)) {
            throw "Baseline file not found: $resolvedPath"
        }

        Write-Verbose "Loading file upload baseline from: $resolvedPath"
        $cachedBaseline = Get-Content $resolvedPath -Raw | ConvertFrom-Json

        #endregion

        #region Initialize Counters

        $totalCount = 0
        $compliantCount = 0
        $violationCount = 0
        $fileUploadEnabledCount = 0
        $severityCounts = @{
            Critical = 0
            High     = 0
            Medium   = 0
            Warning  = 0
        }

        #endregion
    }

    process {
        foreach ($agent in $AgentSettings) {
            $totalCount++

            # Normalize inputs defensively
            $agentZone = if ([string]::IsNullOrWhiteSpace($agent.Zone)) { 'Unknown' } else { $agent.Zone }
            $fileUploadEnabled = $agent.FileUploadEnabled
            $moderationLevel = if ([string]::IsNullOrWhiteSpace($agent.ContentModerationLevel)) { 'Unknown' } else { $agent.ContentModerationLevel }

            if ($fileUploadEnabled -eq $true) {
                $fileUploadEnabledCount++
            }

            # Get expected policy and compliance result
            try {
                $result = & "$PSScriptRoot/private/Get-ExpectedFileUploadPolicy.ps1" `
                    -Zone $agentZone `
                    -FileUploadEnabled $fileUploadEnabled `
                    -ContentModerationLevel $moderationLevel `
                    -Baseline $cachedBaseline
            } catch {
                Write-Warning "Failed to evaluate compliance for agent '$($agent.AgentName)': $($_.Exception.Message)"
                $result = [PSCustomObject]@{
                    Zone                = $agentZone
                    ExpectedFileUpload  = 'Unknown'
                    ActualFileUpload    = if ($fileUploadEnabled) { 'Enabled' } else { 'Disabled' }
                    ExpectedModeration  = 'Unknown'
                    ActualModeration    = $moderationLevel
                    IsCompliant         = $false
                    FileUploadCompliant = $false
                    ModerationCompliant = $false
                    Severity            = 'Warning'
                    ViolationType       = 'EvaluationFailed'
                    RegulatoryContext   = "Compliance evaluation failed: $($_.Exception.Message)"
                }
            }

            # Build compliance result object
            $complianceResult = [PSCustomObject]@{
                AgentId                 = $agent.AgentId
                AgentName               = $agent.AgentName
                EnvironmentId           = $agent.EnvironmentId
                EnvironmentDisplayName  = $agent.EnvironmentDisplayName
                Zone                    = $agentZone
                FileUploadEnabled       = $fileUploadEnabled
                ExpectedFileUpload      = $result.ExpectedFileUpload
                ContentModerationLevel  = $moderationLevel
                ExpectedModerationLevel = $result.ExpectedModeration
                IsCompliant             = $result.IsCompliant
                FileUploadCompliant     = $result.FileUploadCompliant
                ModerationCompliant     = $result.ModerationCompliant
                Severity                = $result.Severity
                ViolationType           = $result.ViolationType
                RegulatoryContext       = $result.RegulatoryContext
                AgentStatus             = $agent.AgentStatus
            }

            # Update counters
            if ($result.IsCompliant) {
                $compliantCount++
            } else {
                $violationCount++
                if ($result.Severity -and $severityCounts.ContainsKey($result.Severity)) {
                    $severityCounts[$result.Severity]++
                }
            }

            # Emit to pipeline if violation or IncludeCompliant
            if (-not $result.IsCompliant -or $IncludeCompliant) {
                $complianceResult
            }
        }
    }

    end {
        #region Summary Statistics

        Write-Verbose "File upload compliance check complete:"
        Write-Verbose "  Total agents scanned: $totalCount"
        Write-Verbose "  File uploads enabled: $fileUploadEnabledCount"
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
    }
}
