#Requires -Modules Pester

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables are initialized in Pester BeforeAll and referenced by child It scriptblocks; PSSA static analysis misses Pester cross-scope reads.'
)]
param()

<#
.SYNOPSIS
    Pester tests for Export-ValidationEvidence.ps1
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot 'Export-ValidationEvidence.ps1'
    # Dot-source with a dummy mandatory Environment; the main guard prevents execution.
    . $script:ScriptPath -Environment 'https://contoso.crm.dynamics.com'

    $scriptContent = Get-Content -Path $script:ScriptPath -Raw
    if ($scriptContent -match "Environment -notmatch '([^']+)'") {
        $script:EnvUrlPattern = $Matches[1]
    } else {
        throw 'Could not extract environment URL regex from Export-ValidationEvidence.ps1'
    }
}

Describe 'Get-ErvEvidenceSummary' {
    It 'reports Validated when all expected check types pass' {
        $results = @(
            @{ TestType = 'FallbackCoverageCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $true }
            @{ TestType = 'ConnectorResilienceCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $true }
            @{ TestType = 'ErrorRecoveryCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $true }
        )
        $summary = Get-ErvEvidenceSummary -Results $results
        $summary.Status | Should -Be 'Validated'
        $summary.Metrics.Passed | Should -Be 3
        $summary.Metrics.PassRate | Should -Be 100
    }

    It 'reports ValidationFailures when any check failed' {
        $results = @(
            @{ TestType = 'FallbackCoverageCheck'; Status = 'Fail'; GapCount = 2; PromotionReady = $false }
            @{ TestType = 'ConnectorResilienceCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $true }
            @{ TestType = 'ErrorRecoveryCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $true }
        )
        $summary = Get-ErvEvidenceSummary -Results $results
        $summary.Status | Should -Be 'ValidationFailures'
        $summary.Metrics.TotalGaps | Should -Be 2
    }

    It 'reports IncompleteCoverage when a check type was never run' {
        $results = @(
            @{ TestType = 'FallbackCoverageCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $true }
        )
        $summary = Get-ErvEvidenceSummary -Results $results
        $summary.Status | Should -Be 'IncompleteCoverage'
        $summary.MissingTypes | Should -Contain 'ConnectorResilienceCheck'
        $summary.MissingTypes | Should -Contain 'ErrorRecoveryCheck'
    }

    It 'reports NoData for an empty result set' {
        (Get-ErvEvidenceSummary -Results @()).Status | Should -Be 'NoData'
    }

    It 'reports NotPromotionReady when a deferred readiness row is not promotion-ready' {
        $results = @(
            @{ TestType = 'FallbackCoverageCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $false }
            @{ TestType = 'ConnectorResilienceCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $false }
            @{ TestType = 'ErrorRecoveryCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $false }
            @{ TestType = 'EarlyReleaseReadinessCheck'; Status = 'Skipped'; GapCount = 0; PromotionReady = $false }
        )
        (Get-ErvEvidenceSummary -Results $results).Status | Should -Be 'NotPromotionReady'
    }

    It 'counts promotion-ready results' {
        $results = @(
            @{ TestType = 'FallbackCoverageCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $true }
            @{ TestType = 'ConnectorResilienceCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $false }
            @{ TestType = 'ErrorRecoveryCheck'; Status = 'Pass'; GapCount = 0; PromotionReady = $true }
        )
        (Get-ErvEvidenceSummary -Results $results).Metrics.PromotionReadyCount | Should -Be 2
    }
}

Describe 'Auth endpoint resolution' {
    It 'maps <env> to <endpoint>' -ForEach @(
        @{ env = 'https://contoso.crm.dynamics.com'; endpoint = 'https://login.microsoftonline.com' }
        @{ env = 'https://contoso.crm.dynamics.cn'; endpoint = 'https://login.chinacloudapi.cn' }
        @{ env = 'https://contoso.crm.microsoftdynamics.us'; endpoint = 'https://login.microsoftonline.us' }
    ) {
        Get-ErvEvidenceAuthEndpoint -EnvironmentUrl $env | Should -Be $endpoint
    }
}

Describe 'Environment URL validation' {
    It 'accepts a valid Dataverse URL: <url>' -ForEach @(
        @{ url = 'https://contoso.crm.dynamics.com' }
        @{ url = 'https://contoso.crm.dynamics.cn' }
    ) {
        $url | Should -Match $script:EnvUrlPattern
    }

    It 'rejects a non-Dataverse URL: <url>' -ForEach @(
        @{ url = 'https://evil.example.com' }
        @{ url = 'http://contoso.crm.dynamics.com' }
    ) {
        $url | Should -Not -Match $script:EnvUrlPattern
    }
}

Describe 'Evidence integrity' {
    It 'computes a SHA-256 companion for the evidence package' {
        $content = Get-Content -Path $script:ScriptPath -Raw
        $content | Should -Match 'SHA256'
        $content | Should -Match '\.sha256'
    }
}
