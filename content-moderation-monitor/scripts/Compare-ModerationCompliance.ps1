<#
.SYNOPSIS
    Compares agent content moderation levels against zone-specific requirements.

.DESCRIPTION
    Takes agent moderation settings (from Get-AgentModerationSettings) and
    evaluates each agent's content moderation level against the expected level
    for its zone. Returns compliance results with severity classification
    and regulatory context.

.NOTES
    File: Compare-ModerationCompliance.ps1
    Version: 1.0.0
    Solution: Content Moderation Monitor (v7)
#>

function Compare-ModerationCompliance {
    <#
    .SYNOPSIS
        Compares agent content moderation levels against zone-specific requirements.

    .DESCRIPTION
        Takes agent moderation settings (from Get-AgentModerationSettings) and
        evaluates each agent's content moderation level against the expected level
        for its zone. Returns compliance results with severity classification
        and regulatory context.

        By default, only non-compliant agents are returned. Use -IncludeCompliant
        to include all agents in the output.

    .PARAMETER AgentSettings
        Pipeline input: PSCustomObject[] from Get-AgentModerationSettings.
        Each object must include AgentId, AgentName, ContentModerationLevel,
        EnvironmentDisplayName, Zone, and AgentStatus properties.

    .PARAMETER BaselinePath
        Path to moderation-baseline.json. Defaults to ../templates/moderation-baseline.json
        relative to the script location.

    .PARAMETER IncludeCompliant
        Include compliant agents in output. By default, only violations are returned.

    .EXAMPLE
        . ./Get-AgentModerationSettings.ps1
        . ./Compare-ModerationCompliance.ps1
        Get-AgentModerationSettings | Compare-ModerationCompliance

        Retrieves all agents and returns only non-compliant agents with severity.

    .EXAMPLE
        . ./Get-AgentModerationSettings.ps1
        . ./Compare-ModerationCompliance.ps1
        Get-AgentModerationSettings -ExcludeSandbox | Compare-ModerationCompliance -IncludeCompliant

        Returns compliance status for all agents including compliant ones.

    .EXAMPLE
        . ./Get-AgentModerationSettings.ps1
        . ./Compare-ModerationCompliance.ps1
        $results = Get-AgentModerationSettings | Compare-ModerationCompliance
        $results | Where-Object { $_.Severity -eq 'Critical' }

        Filters compliance results for critical violations only.

    .OUTPUTS
        PSCustomObject[] — One object per agent with properties:
        AgentId, AgentName, EnvironmentDisplayName, Zone,
        CurrentModerationLevel, ExpectedModerationLevel, IsCompliant,
        Severity, RegulatoryContext, AgentStatus
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
            $BaselinePath = Join-Path $PSScriptRoot '..' 'templates' 'moderation-baseline.json'
        }

        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BaselinePath)

        if (-not (Test-Path $resolvedPath)) {
            throw "Baseline file not found: $resolvedPath"
        }

        Write-Verbose "Loading moderation baseline from: $resolvedPath"
        $null = Get-Content $resolvedPath -Raw | ConvertFrom-Json  # validate JSON parses

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
    }

    process {
        foreach ($agent in $AgentSettings) {
            $totalCount++

            # Normalize inputs defensively
            $agentZone = if ([string]::IsNullOrWhiteSpace($agent.Zone)) { 'Unknown' } else { $agent.Zone }
            $agentLevel = if ([string]::IsNullOrWhiteSpace($agent.ContentModerationLevel)) { 'Unknown' } else { $agent.ContentModerationLevel }

            # Get expected moderation level and compliance result
            try {
                $result = & "$PSScriptRoot/private/Get-ExpectedModerationLevel.ps1" `
                    -Zone $agentZone `
                    -ActualLevel $agentLevel `
                    -BaselinePath $resolvedPath
            } catch {
                Write-Warning "Failed to evaluate compliance for agent '$($agent.AgentName)': $($_.Exception.Message)"
                $result = [PSCustomObject]@{
                    Zone              = $agentZone
                    ExpectedLevel     = 'Unknown'
                    ActualLevel       = $agentLevel
                    IsCompliant       = $false
                    Severity          = 'Warning'
                    RegulatoryContext = "Compliance evaluation failed: $($_.Exception.Message)"
                }
            }

            # Build compliance result object
            $complianceResult = [PSCustomObject]@{
                AgentId                 = $agent.AgentId
                AgentName               = $agent.AgentName
                EnvironmentDisplayName  = $agent.EnvironmentDisplayName
                Zone                    = $agentZone
                CurrentModerationLevel  = $agentLevel
                ExpectedModerationLevel = $result.ExpectedLevel
                IsCompliant             = $result.IsCompliant
                Severity                = $result.Severity
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
    }
}
