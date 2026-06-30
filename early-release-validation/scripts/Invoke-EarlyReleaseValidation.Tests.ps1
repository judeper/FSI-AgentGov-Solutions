#Requires -Modules Pester

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables are initialized in Pester BeforeAll and referenced by child It scriptblocks; PSSA static analysis misses Pester cross-scope reads.'
)]
param()

<#
.SYNOPSIS
    Pester tests for Invoke-EarlyReleaseValidation.ps1

.DESCRIPTION
    Dot-sources the validation script (its main flow is guarded so dot-sourcing
    only defines the helper functions) and exercises the three structural checks
    against synthetic unpacked-solution fixtures, the picklist value maps, the
    environment URL regex, and the Dataverse save error handling.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot 'Invoke-EarlyReleaseValidation.ps1'

    # Dot-source with dummy mandatory params; the main guard prevents execution.
    . $script:ScriptPath -CheckType FallbackCoverageCheck -SolutionPath $TestDrive

    # Helper: write a topic YAML file into a fresh fixture solution tree.
    function Initialize-ErvFixture {
        param([hashtable]$TopicFiles, [hashtable]$ConnRefFiles)
        $root = Join-Path $TestDrive ("fixture-" + [guid]::NewGuid().ToString('N'))
        $topics = Join-Path $root 'bot/topics'
        New-Item -ItemType Directory -Path $topics -Force | Out-Null
        foreach ($name in $TopicFiles.Keys) {
            Set-Content -Path (Join-Path $topics $name) -Value $TopicFiles[$name]
        }
        if ($ConnRefFiles) {
            $cr = Join-Path $root 'connectionreferences'
            New-Item -ItemType Directory -Path $cr -Force | Out-Null
            foreach ($name in $ConnRefFiles.Keys) {
                Set-Content -Path (Join-Path $cr $name) -Value $ConnRefFiles[$name]
            }
        }
        return $root
    }

    # Extract the environment URL regex from the script source (mirrors the
    # pattern used by the dr-testing-framework tests).
    $scriptContent = Get-Content -Path $script:ScriptPath -Raw
    if ($scriptContent -match "Environment -notmatch '([^']+)'") {
        $script:EnvUrlPattern = $Matches[1]
    } else {
        throw 'Could not extract environment URL regex from Invoke-EarlyReleaseValidation.ps1'
    }
}

Describe 'Marker helpers' {
    It 'detects a connector/flow action call' {
        Test-TopicHasConnectorCall -Content 'actions:
  - kind: InvokeConnectorAction' | Should -BeTrue
        Test-TopicHasConnectorCall -Content 'actions:
  - kind: InvokeFlowAction' | Should -BeTrue
    }

    It 'returns false when no connector call is present' {
        Test-TopicHasConnectorCall -Content 'actions:
  - kind: SendActivity' | Should -BeFalse
    }

    It 'detects an error-handling construct' {
        Test-TopicHasErrorHandling -Content 'errorHandling:
  kind: ConditionGroup' | Should -BeTrue
    }

    It 'treats a topic with only an empty message as a stub' {
        Test-TopicHasNonStubMessage -Content 'actions:
  - kind: SendActivity' | Should -BeFalse
    }

    It 'accepts a topic with a real user-facing message' {
        Test-TopicHasNonStubMessage -Content 'actions:
  - kind: SendActivity
    activity: "Sorry, let me get a person."' | Should -BeTrue
    }
}

Describe 'FallbackCoverageCheck' {
    It 'flags a topic that calls a connector with no error handling' {
        $fix = Initialize-ErvFixture -TopicFiles @{
            'GetMail.yaml' = "actions:`n  - kind: InvokeConnectorAction`n    connectionReference: shared_office365"
        }
        $findings = @(Get-FallbackCoverageFinding -SolutionPath $fix)
        $findings.Count | Should -Be 1
        $findings[0].topic | Should -Be 'GetMail.yaml'
    }

    It 'passes a topic whose connector call is wrapped in error handling' {
        $fix = Initialize-ErvFixture -TopicFiles @{
            'CreateTicket.yaml' = "actions:`n  - kind: InvokeFlowAction`n    errorHandling:`n      kind: ConditionGroup"
        }
        @(Get-FallbackCoverageFinding -SolutionPath $fix).Count | Should -Be 0
    }

    It 'flags a connector call whose only branch is an unrelated condition group (no error handling)' {
        $fix = Initialize-ErvFixture -TopicFiles @{
            'Lookup.yaml' = "actions:`n  - kind: InvokeConnectorAction`n  - kind: ConditionGroup`n    conditions:`n      - id: x"
        }
        @(Get-FallbackCoverageFinding -SolutionPath $fix).Count | Should -Be 1
    }
}

Describe 'ConnectorResilienceCheck' {
    It 'flags a connection reference with a hard-coded connectionid' {
        $fix = Initialize-ErvFixture -TopicFiles @{ 'noop.yaml' = 'kind: AdaptiveDialog' } -ConnRefFiles @{
            'fsi_cr_x.json' = '{ "connectionreferencelogicalname": "fsi_cr_x", "connectionid": "1a2b3c4d-1111-2222-3333-444455556666" }'
        }
        @(Get-ConnectorResilienceFinding -SolutionPath $fix).Count | Should -Be 1
    }

    It 'passes a connection reference with no hard-coded connectionid' {
        $fix = Initialize-ErvFixture -TopicFiles @{ 'noop.yaml' = 'kind: AdaptiveDialog' } -ConnRefFiles @{
            'fsi_cr_y.json' = '{ "connectionreferencelogicalname": "fsi_cr_y", "connectionid": null }'
        }
        @(Get-ConnectorResilienceFinding -SolutionPath $fix).Count | Should -Be 0
    }
}

Describe 'ErrorRecoveryCheck' {
    It 'flags a solution with no System Fallback topic' {
        $fix = Initialize-ErvFixture -TopicFiles @{
            'Greeting.yaml' = "actions:`n  - kind: SendActivity`n    activity: `"Hello`""
        }
        $findings = @(Get-ErrorRecoveryFinding -SolutionPath $fix)
        $findings.Count | Should -BeGreaterThan 0
        ($findings | Where-Object { $_.issue -match 'No System Fallback' }) | Should -Not -BeNullOrEmpty
    }

    It 'flags a System Fallback topic that has only a stub message' {
        $fix = Initialize-ErvFixture -TopicFiles @{
            'Fallback.yaml' = "kind: OnUnknownIntent`nactions:`n  - kind: SendActivity"
        }
        @(Get-ErrorRecoveryFinding -SolutionPath $fix).Count | Should -BeGreaterThan 0
    }

    It 'flags a System Fallback topic whose message is a placeholder' {
        $fix = Initialize-ErvFixture -TopicFiles @{
            'Fallback.yaml' = "kind: OnUnknownIntent`nactions:`n  - kind: SendActivity`n    activity: `"TODO`""
        }
        @(Get-ErrorRecoveryFinding -SolutionPath $fix).Count | Should -BeGreaterThan 0
    }

    It 'passes a System Fallback topic with a non-stub message' {
        $fix = Initialize-ErvFixture -TopicFiles @{
            'Fallback.yaml' = "kind: OnUnknownIntent`nactions:`n  - kind: SendActivity`n    activity: `"Sorry, let me connect you to a person.`""
        }
        @(Get-ErrorRecoveryFinding -SolutionPath $fix).Count | Should -Be 0
    }
}

Describe 'Invoke-StructuralCheck' {
    It 'returns Pass with zero gaps for a clean fixture' {
        $fix = Initialize-ErvFixture -TopicFiles @{
            'Fallback.yaml' = "kind: OnUnknownIntent`nactions:`n  - kind: SendActivity`n    activity: `"Sorry, let me get a person.`""
        }
        $r = Invoke-StructuralCheck -Name 'ErrorRecoveryCheck' -SolutionPath $fix
        $r.Status | Should -Be 'Pass'
        $r.GapCount | Should -Be 0
    }

    It 'returns Fail with a positive gap count when a gap is present' {
        $fix = Initialize-ErvFixture -TopicFiles @{
            'GetMail.yaml' = "actions:`n  - kind: InvokeConnectorAction"
        }
        $r = Invoke-StructuralCheck -Name 'FallbackCoverageCheck' -SolutionPath $fix
        $r.Status | Should -Be 'Fail'
        $r.GapCount | Should -BeGreaterThan 0
    }
}

Describe 'Picklist value maps match the Dataverse schema convention' {
    It 'uses 100000000+ values for every test type' {
        foreach ($v in $script:TestTypeOptionValue.Values) {
            $v | Should -BeGreaterOrEqual 100000000
        }
    }

    It 'uses 100000000+ values for every status' {
        foreach ($v in $script:TestStatusOptionValue.Values) {
            $v | Should -BeGreaterOrEqual 100000000
        }
    }

    It 'maps all four check types' {
        $script:TestTypeOptionValue.Keys | Should -Contain 'EarlyReleaseReadinessCheck'
        $script:TestTypeOptionValue.Count | Should -Be 4
    }
}

Describe 'Environment URL validation' {
    It 'accepts a valid Dataverse URL: <url>' -ForEach @(
        @{ url = 'https://contoso.crm.dynamics.com' }
        @{ url = 'https://contoso.crm.dynamics.cn' }
        @{ url = 'https://contoso.crm.microsoftdynamics.us' }
    ) {
        $url | Should -Match $script:EnvUrlPattern
    }

    It 'rejects a non-Dataverse URL: <url>' -ForEach @(
        @{ url = 'https://evil.example.com' }
        @{ url = 'http://contoso.crm.dynamics.com' }
        @{ url = 'https://contoso.crm.dynamics.evil' }
    ) {
        $url | Should -Not -Match $script:EnvUrlPattern
    }
}

Describe 'Save error handling' {
    It 'wraps the Dataverse save in a catch that warns on failure' {
        $content = Get-Content -Path $script:ScriptPath -Raw
        $content | Should -Match '(?s)catch\s*\{.*Write-Warning\s+.Failed to save result:'
    }
}
