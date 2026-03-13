#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for Export-DREvidence.ps1

.DESCRIPTION
    Validates Environment URL regex, TestRunId parameter validation,
    and evidence export behaviour.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot 'Export-DREvidence.ps1'
    $scriptContent = Get-Content -Path $scriptPath -Raw

    # Extract the environment URL regex pattern used in the script
    if ($scriptContent -match "Environment -notmatch '([^']+)'") {
        $script:EnvUrlPattern = $Matches[1]
    } else {
        throw 'Could not extract environment URL regex from Export-DREvidence.ps1'
    }
}

Describe 'Export-DREvidence Environment URL Validation' {

    Context 'Valid Dataverse URLs' {
        It 'Accepts commercial cloud URL: <url>' -ForEach @(
            @{ url = 'https://contoso.crm.dynamics.com' }
            @{ url = 'https://myorg.crm2.dynamics.com' }
            @{ url = 'https://myorg.crm10.dynamics.com' }
        ) {
            $url | Should -Match $script:EnvUrlPattern
        }

        It 'Accepts sovereign cloud URL: <url>' -ForEach @(
            @{ url = 'https://contoso.crm.dynamics.cn' }
            @{ url = 'https://contoso.crm9.dynamics.com' }
            @{ url = 'https://contoso.crm.appsplatform.us' }
        ) {
            $url | Should -Match $script:EnvUrlPattern
        }

        It 'Accepts GCC High URL: <url>' -ForEach @(
            @{ url = 'https://contoso.crm.microsoftdynamics.us' }
        ) {
            $url | Should -Match $script:EnvUrlPattern
        }
    }

    Context 'Invalid URLs rejected' {
        It 'Rejects fabricated TLD: <url>' -ForEach @(
            @{ url = 'https://contoso.crm.dynamics.evil' }
            @{ url = 'https://contoso.crm.dynamics.xyz' }
        ) {
            $url | Should -Not -Match $script:EnvUrlPattern
        }

        It 'Rejects non-Dataverse URL: <url>' -ForEach @(
            @{ url = 'https://evil.example.com' }
            @{ url = 'http://contoso.crm.dynamics.com' }
        ) {
            $url | Should -Not -Match $script:EnvUrlPattern
        }

        It 'Rejects URL with trailing path: <url>' -ForEach @(
            @{ url = 'https://contoso.crm.dynamics.com/api/data' }
        ) {
            $url | Should -Not -Match $script:EnvUrlPattern
        }
    }
}

Describe 'Export-DREvidence TestRunId Validation' {

    It 'Rejects TestRunId containing wildcard asterisk' {
        {
            & $PSScriptRoot\Export-DREvidence.ps1 `
                -Environment 'https://contoso.crm.dynamics.com' `
                -TestRunId 'abc*def'
        } | Should -Throw
    }

    It 'Rejects TestRunId containing wildcard question mark' {
        {
            & $PSScriptRoot\Export-DREvidence.ps1 `
                -Environment 'https://contoso.crm.dynamics.com' `
                -TestRunId 'abc?def'
        } | Should -Throw
    }

    It 'Accepts alphanumeric TestRunId with hyphens' {
        # Should not throw on validation — will proceed to evidence export logic
        # Use a temp output dir to avoid writing to default location
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "dr-evidence-test-$(Get-Random)"
        try {
            & $PSScriptRoot\Export-DREvidence.ps1 `
                -Environment 'https://contoso.crm.dynamics.com' `
                -TestRunId 'abc-123-def' `
                -OutputDir $tempDir
        } finally {
            if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
        }
    }
}

Describe 'Export-DREvidence script structure' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path (Join-Path $PSScriptRoot 'Export-DREvidence.ps1') -Raw
    }

    It 'Validates Environment URL with SSRF regex' {
        $script:scriptContent | Should -Match 'Environment -notmatch'
    }

    It 'Validates TestRunId parameter with ValidatePattern' {
        $script:scriptContent | Should -Match '\[ValidatePattern\('
    }

    It 'Generates JSON evidence metadata file' {
        $script:scriptContent | Should -Match 'ConvertTo-Json'
    }
}
