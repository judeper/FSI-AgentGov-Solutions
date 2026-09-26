#Requires -Version 7.2
#Requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "5.0.0" }

BeforeAll {
    . (Join-Path $PSScriptRoot 'Invoke-HealthCheck.ps1')

    function Get-HealthResponse {
        param(
            [Parameter(Mandatory)] [int] $StatusCode,
            [Parameter()] [hashtable] $Headers = @{},
            [Parameter()] [string] $Content = ''
        )

        [pscustomobject]@{
            StatusCode = $StatusCode
            Headers    = $Headers
            Content    = $Content
        }
    }
}

Describe 'Test-PublishedArtifactUrl' {
    BeforeEach {
        Mock -CommandName Start-Sleep -MockWith { }
    }

    It 'retries transient 429 with Retry-After and reports every attempt status' {
        $script:i = 0
        $responses = @(
            (Get-HealthResponse -StatusCode 429 -Headers @{ 'Retry-After' = '1' }),
            (Get-HealthResponse -StatusCode 200 -Content 'ok')
        )
        Mock -CommandName Invoke-HealthHttpRequest -MockWith {
            $response = $responses[$script:i]
            $script:i++
            return $response
        }

        $result = Test-PublishedArtifactUrl -Label 'raw-lock' -Url 'https://unit/solutions.json' -MaxAttempts 4

        $result.Passed | Should -BeTrue
        $result.AttemptStatuses | Should -Be @('429', '200')
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 1 }
    }

    It 'fails only after every transient attempt is exhausted' {
        $script:i = 0
        $responses = @(
            (Get-HealthResponse -StatusCode 503),
            (Get-HealthResponse -StatusCode 504),
            (Get-HealthResponse -StatusCode 503)
        )
        Mock -CommandName Invoke-HealthHttpRequest -MockWith {
            $response = $responses[$script:i]
            $script:i++
            return $response
        }

        $result = Test-PublishedArtifactUrl -Label 'site-home' -Url 'https://unit/' -MaxAttempts 3 -BaseDelaySeconds 0

        $result.Passed | Should -BeFalse
        $result.AttemptStatuses | Should -Be @('503', '504', '503')
        $result.Errors[0] | Should -Match 'after attempts \[503 -> 504 -> 503\]'
    }
}

Describe 'Add-SolutionsLockValidation' {
    It 'attaches shape errors to a successful raw-lock HTTP response' {
        $result = [pscustomobject]@{
            Label           = 'raw-lock'
            Url             = 'https://unit/solutions.json'
            Expected        = '200'
            FinalStatus     = '200'
            AttemptStatuses = @('200')
            Passed          = $true
            Content         = '{"solutions":{"a":{"controls":[]}}}'
            Errors          = @()
        }

        $validated = Add-SolutionsLockValidation -RawLockResult $result -MinSolutions 36

        $validated.Passed | Should -BeFalse
        ($validated.Errors -join "`n") | Should -Match 'count below floor'
        ($validated.Errors -join "`n") | Should -Match 'missing schemaVersion'
    }
}

Describe 'Write-HealthOutputs' {
    It 'writes GitHub step outputs to the provided output path' {
        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $results = @(
            [pscustomobject]@{
                Label           = 'site-home'
                Url             = 'https://unit/'
                Expected        = '200'
                FinalStatus     = '200'
                AttemptStatuses = @('200')
                Passed          = $true
                Content         = 'ok'
                Errors          = @()
            },
            [pscustomobject]@{
                Label           = 'raw-lock'
                Url             = 'https://unit/solutions.json'
                Expected        = '200'
                FinalStatus     = '503'
                AttemptStatuses = @('503', '200')
                Passed          = $false
                Content         = ''
                Errors          = @('raw-lock expected 200 got 503')
            }
        )

        Write-HealthOutputs -Results $results -OutputPath $outputPath

        $output = Get-Content -LiteralPath $outputPath -Raw
        $output | Should -Match '^fail=1'
        $output | Should -Match 'errors<<EOF'
        $output | Should -Match '- raw-lock expected 200 got 503'
        $output | Should -Match 'report<<EOF'
        $output | Should -Match 'site-home  200  https://unit/'
        $output | Should -Match 'raw-lock  503 -> 200  https://unit/solutions.json'
    }
}

Describe 'Find-OpenHealthIssueForTarget' {
    It 'searches by target body marker and filters the exact health-check title locally' {
        Mock -CommandName Invoke-HealthGh -MockWith {
            ($ArgumentList -join ' ') | Should -Match 'issue list'
            ($ArgumentList -join ' ') | Should -Match '"raw-lock" in:body'
            return @'
[
  {
    "number": 370,
    "title": "Health check failure: published artifacts not healthy",
    "updatedAt": "2026-09-25T18:46:13Z",
    "body": "Automated probe detected failures:\n\n- raw-lock expected 200 got 429"
  },
  {
    "number": 999,
    "title": "Unrelated raw-lock investigation",
    "updatedAt": "2026-09-25T18:46:13Z",
    "body": "raw-lock"
  }
]
'@
        }

        $issues = @(Find-OpenHealthIssueForTarget -Repository 'judeper/FSI-AgentGov-Solutions' -TargetLabel 'raw-lock')

        $issues.Count | Should -Be 1
        $issues[0].number | Should -Be 370
    }
}

Describe 'Sync-PublishedArtifactHealthIssues' {
    It 'comments on an existing target issue instead of creating a duplicate' {
        Mock -CommandName Invoke-HealthGh -MockWith {
            $joined = $ArgumentList -join ' '
            if ($joined -match '^issue list ') { return '[{"number":370,"title":"Health check failure: published artifacts not healthy"}]' }
            if ($joined -match '^issue comment 370 ') { return 'commented' }
            throw "Unexpected gh call: $joined"
        }
        $result = [pscustomobject]@{
            Label           = 'raw-lock'
            Url             = 'https://unit/solutions.json'
            Expected        = '200'
            FinalStatus     = '429'
            AttemptStatuses = @('429', '429')
            Passed          = $false
            Content         = ''
            Errors          = @('raw-lock expected 200 got 429 after attempts [429 -> 429] -- https://unit/solutions.json')
        }

        Sync-PublishedArtifactHealthIssues -Repository 'judeper/FSI-AgentGov-Solutions' -Results @($result) -RunUrl 'https://unit/run'

        Should -Invoke Invoke-HealthGh -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match '^issue comment 370 ' }
        Should -Invoke Invoke-HealthGh -Times 0 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match '^issue create ' }
    }

    It 'auto-closes an existing target issue after the target passes' {
        Mock -CommandName Invoke-HealthGh -MockWith {
            $joined = $ArgumentList -join ' '
            if ($joined -match '^issue list ') { return '[{"number":348,"title":"Health check failure: published artifacts not healthy"}]' }
            if ($joined -match '^issue close 348 ') { return 'closed' }
            throw "Unexpected gh call: $joined"
        }
        $result = [pscustomobject]@{
            Label           = 'site-home'
            Url             = 'https://unit/'
            Expected        = '200'
            FinalStatus     = '200'
            AttemptStatuses = @('200')
            Passed          = $true
            Content         = 'ok'
            Errors          = @()
        }

        Sync-PublishedArtifactHealthIssues -Repository 'judeper/FSI-AgentGov-Solutions' -Results @($result) -RunUrl 'https://unit/run'

        Should -Invoke Invoke-HealthGh -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match '^issue close 348 ' }
    }
}
