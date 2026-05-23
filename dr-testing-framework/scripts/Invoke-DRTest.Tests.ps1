#Requires -Modules Pester

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingInvokeExpression', '',
    Justification = 'Pester test harness: extracts FunctionDefinitionAst nodes from production script and evaluates them in test scope via Invoke-Expression. The input is a verified AST .Extent.Text from a trusted file under source control, NOT untrusted user input. This is the standard pattern for testing nested helper functions that are not exported from their parent script.'
)]
param()

<#
.SYNOPSIS
    Pester tests for Invoke-DRTest.ps1

.DESCRIPTION
    Validates environment URL regex, parameter validation, and Save-TestResult
    error handling logic.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot 'Invoke-DRTest.ps1'
    $scriptContent = Get-Content -Path $scriptPath -Raw

    # Extract the environment URL regex pattern used in the script
    if ($scriptContent -match "Environment -notmatch '([^']+)'") {
        $script:EnvUrlPattern = $Matches[1]
    } else {
        throw 'Could not extract environment URL regex from Invoke-DRTest.ps1'
    }
}

Describe 'Environment URL Validation' {

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
            @{ url = 'https://contoso.crm.dynamics.internal' }
        ) {
            $url | Should -Not -Match $script:EnvUrlPattern
        }

        It 'Rejects non-Dataverse URL: <url>' -ForEach @(
            @{ url = 'https://evil.example.com' }
            @{ url = 'https://login.microsoftonline.com' }
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

    Context 'Accepted after normalization' {
        # TrimEnd('/') runs before the regex check, so a single trailing slash is
        # stripped and the URL passes validation. This test documents that behaviour.
        It 'Accepts URL after TrimEnd strips trailing slash: <url>' -ForEach @(
            @{ url = 'https://contoso.crm.dynamics.com/' }
        ) {
            $normalized = $url.TrimEnd('/')
            $normalized | Should -Match $script:EnvUrlPattern
        }
    }
}

Describe 'Save-TestResult failure warning' {
    It 'Script contains catch block for failed save' {
        $scriptContent = Get-Content -Path (Join-Path $PSScriptRoot 'Invoke-DRTest.ps1') -Raw
        $scriptContent | Should -Match '(?s)catch\s*\{.*Write-Warning\s+.Failed to save result:'
    }
}

Describe 'Script structure' {
    BeforeAll {
        $script:scriptContent = Get-Content -Path (Join-Path $PSScriptRoot 'Invoke-DRTest.ps1') -Raw
    }

    It 'Defines Save-TestResult function' {
        $script:scriptContent | Should -Match 'function Save-TestResult'
    }

    It 'Defines Get-AccessToken function' {
        $script:scriptContent | Should -Match 'function Get-AccessToken'
    }

    It 'Uses option set values 1 and 2 for fsi_status' {
        $script:scriptContent | Should -Match 'fsi_status\s*=\s*if\s*\(\$Result\.Success\)\s*\{\s*1\s*\}\s*else\s*\{\s*2\s*\}'
    }

    It 'Serializes fsi_validationchecks as JSON' {
        $script:scriptContent | Should -Match 'fsi_validationchecks\s*=.*ConvertTo-Json'
    }
}

Describe 'Get-AccessToken retry logic' {
    BeforeAll {
        # Source only the functions from the script without running main logic
        $scriptPath = Join-Path $PSScriptRoot 'Invoke-DRTest.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw
        # Extract function definitions
        $functionBlock = [regex]::Match($scriptContent, '(?s)(function Get-AccessToken\s*\{.+?\n\})')
        if (-not $functionBlock.Success) { throw 'Could not extract Get-AccessToken function' }
        Invoke-Expression $functionBlock.Value
        # Provide Write-AuditLog dependency (called in retry catch blocks)
        function script:Write-AuditLog { param([string]$Message, [string]$Level = "INFO", [string]$CorrelationId) }
        $script:CorrelationId = 'test'
        $script:TestSecret = 'secret' | ConvertTo-SecureString -AsPlainText -Force
    }

    It 'Retries on 429 and succeeds on second attempt' {
        $script:callCount = 0
        Mock Invoke-RestMethod {
            $script:callCount++
            if ($script:callCount -eq 1) {
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("429", $response)
                throw $exception
            }
            return @{ access_token = 'mock-token' }
        }
        Mock Start-Sleep {}

        $token = Get-AccessToken -TenantId '00000000-0000-0000-0000-000000000000' `
            -ClientId '00000000-0000-0000-0000-000000000001' `
            -ClientSecret $script:TestSecret -Scope 'https://contoso.crm.dynamics.com/.default'

        $token | Should -Be 'mock-token'
        $script:callCount | Should -Be 2
        Should -Invoke Start-Sleep -Times 1 -Exactly
    }

    It 'Retries on 503 and succeeds on third attempt' {
        $script:callCount = 0
        Mock Invoke-RestMethod {
            $script:callCount++
            if ($script:callCount -le 2) {
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::ServiceUnavailable)
                $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("503", $response)
                throw $exception
            }
            return @{ access_token = 'mock-token-3' }
        }
        Mock Start-Sleep {}

        $token = Get-AccessToken -TenantId '00000000-0000-0000-0000-000000000000' `
            -ClientId '00000000-0000-0000-0000-000000000001' `
            -ClientSecret $script:TestSecret -Scope 'https://contoso.crm.dynamics.com/.default'

        $token | Should -Be 'mock-token-3'
        $script:callCount | Should -Be 3
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }

    It 'Throws after exhausting retries on 429' {
        Mock Invoke-RestMethod {
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
            $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("429", $response)
            throw $exception
        }
        Mock Start-Sleep {}

        { Get-AccessToken -TenantId '00000000-0000-0000-0000-000000000000' `
            -ClientId '00000000-0000-0000-0000-000000000001' `
            -ClientSecret $script:TestSecret -Scope 'https://contoso.crm.dynamics.com/.default' } | Should -Throw

        Should -Invoke Invoke-RestMethod -Times 3 -Exactly
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }
}

Describe 'Save-TestResult retry logic' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot 'Invoke-DRTest.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw
        $functionBlock = [regex]::Match($scriptContent, '(?s)(function Save-TestResult\s*\{.+?\n\})')
        if (-not $functionBlock.Success) { throw 'Could not extract Save-TestResult function' }
        Invoke-Expression $functionBlock.Value
        # Provide Write-AuditLog dependency (called in retry catch blocks)
        function script:Write-AuditLog { param([string]$Message, [string]$Level = "INFO", [string]$CorrelationId) }
        $script:CorrelationId = 'test'
    }

    BeforeEach {
        $script:mockResult = @{
            TestType = 'AgentReadinessCheck'
            ExecutedOn = '2026-01-01T00:00:00Z'
            ProbeDurationHours = 0.5
            ProbeDurationTargetHours = 4
            ProbeWithinBudget = $true
            MinutesSinceLastResult = $null
            MaxMinutesSinceLastResult = 1440
            LastResultWithinThreshold = $null
            Success = $true
            ValidationChecks = @(@{Check = 'Test'; Status = 'PASS'})
        }
    }

    It 'Retries on 429 and returns $true on success' {
        $script:callCount = 0
        Mock Invoke-RestMethod {
            $script:callCount++
            if ($script:callCount -eq 1) {
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("429", $response)
                throw $exception
            }
            return @{}
        }
        Mock Start-Sleep {}

        $result = Save-TestResult -Environment 'https://contoso.crm.dynamics.com' `
            -Token 'mock-token' -Result $script:mockResult

        $result | Should -BeTrue
        $script:callCount | Should -Be 2
        Should -Invoke Start-Sleep -Times 1 -Exactly
    }

    It 'Returns $false and warns after exhausting retries on 503' {
        Mock Invoke-RestMethod {
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::ServiceUnavailable)
            $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("503", $response)
            throw $exception
        }
        Mock Start-Sleep {}

        $result = Save-TestResult -Environment 'https://contoso.crm.dynamics.com' `
            -Token 'mock-token' -Result $script:mockResult 3>&1

        # Last element is the return value ($false), preceding are warning records
        $returnValue = $result | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
        $warnings = $result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

        $returnValue | Should -BeFalse
        $warnings.Count | Should -BeGreaterOrEqual 1
        Should -Invoke Invoke-RestMethod -Times 3 -Exactly
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }

    It 'Returns $false immediately on non-transient error (e.g. 400)' {
        Mock Invoke-RestMethod {
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::BadRequest)
            $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("400 Bad Request", $response)
            throw $exception
        }
        Mock Start-Sleep {}

        $result = Save-TestResult -Environment 'https://contoso.crm.dynamics.com' `
            -Token 'mock-token' -Result $script:mockResult 3>&1

        $returnValue = $result | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
        $returnValue | Should -BeFalse
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }
}

Describe 'FullValidation test type aggregation' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot 'Invoke-DRTest.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw

        # Extract all three sub-test functions
        foreach ($funcName in @('Test-AgentReadiness', 'Test-EnvironmentReachability', 'Test-DataverseAccess')) {
            $block = [regex]::Match($scriptContent, "(?s)(function $funcName\s*\{.+?\n\})")
            if (-not $block.Success) { throw "Could not extract $funcName function" }
            Invoke-Expression $block.Value
        }
    }

    It 'Merges ValidationChecks from all three sub-tests' {
        Mock Start-Sleep {}
        Mock Write-Host {}
        Mock Write-Warning {}
        Mock Write-AuditLog {} -ErrorAction SilentlyContinue
        Mock Invoke-WebRequest { [PSCustomObject]@{StatusCode = 200} }

        $agentResult = Test-AgentReadiness -AgentId '00000000-0000-0000-0000-000000000001' -DryRun $false
        $envResult = Test-EnvironmentReachability -DryRun $false
        $dataResult = Test-DataverseAccess -DryRun $false

        $combined = @{
            ValidationChecks = $agentResult.ValidationChecks + $envResult.ValidationChecks + $dataResult.ValidationChecks
            Success = $agentResult.Success -and $envResult.Success -and $dataResult.Success
        }

        $expectedCount = $agentResult.ValidationChecks.Count + $envResult.ValidationChecks.Count + $dataResult.ValidationChecks.Count
        $combined.ValidationChecks.Count | Should -Be $expectedCount
        $combined.ValidationChecks.Count | Should -BeGreaterThan 0
    }

    It 'ANDs Success flags - all pass yields $true' {
        Mock Start-Sleep {}
        Mock Write-Host {}
        Mock Write-Warning {}
        Mock Write-AuditLog {} -ErrorAction SilentlyContinue
        Mock Invoke-WebRequest { [PSCustomObject]@{StatusCode = 200} }

        $agentResult = Test-AgentReadiness -AgentId '00000000-0000-0000-0000-000000000001' -DryRun $false
        $envResult = Test-EnvironmentReachability -DryRun $false
        $dataResult = Test-DataverseAccess -DryRun $false

        $combined = $agentResult.Success -and $envResult.Success -and $dataResult.Success
        $combined | Should -BeTrue
    }

    It 'ANDs Success flags - one failure yields $false' {
        Mock Start-Sleep {}
        Mock Write-Host {}
        Mock Write-Warning {}
        Mock Write-AuditLog {} -ErrorAction SilentlyContinue
        Mock Invoke-WebRequest { [PSCustomObject]@{StatusCode = 200} }

        $agentResult = Test-AgentReadiness -AgentId '00000000-0000-0000-0000-000000000001' -DryRun $false
        $envResult = Test-EnvironmentReachability -DryRun $false
        $dataResult = Test-DataverseAccess -DryRun $false

        # Simulate one sub-test failing
        $envResult.Success = $false

        $combined = $agentResult.Success -and $envResult.Success -and $dataResult.Success
        $combined | Should -BeFalse
    }
}

Describe 'DryRun mode' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot 'Invoke-DRTest.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw
        foreach ($funcName in @('Test-AgentReadiness', 'Test-EnvironmentReachability', 'Test-DataverseAccess')) {
            $block = [regex]::Match($scriptContent, "(?s)(function $funcName\s*\{.+?\n\})")
            if (-not $block.Success) { throw "Could not extract $funcName function" }
            Invoke-Expression $block.Value
        }
    }

    It 'Test-AgentReadiness DryRun returns empty ValidationChecks' {
        Mock Write-Host {}
        Mock Write-Warning {}
        $result = Test-AgentReadiness -AgentId '00000000-0000-0000-0000-000000000001' -DryRun $true
        $result.ValidationChecks.Count | Should -Be 0
    }

    It 'Test-EnvironmentReachability DryRun returns empty ValidationChecks' {
        Mock Write-Host {}
        Mock Write-Warning {}
        $result = Test-EnvironmentReachability -DryRun $true
        $result.ValidationChecks.Count | Should -Be 0
    }

    It 'Test-DataverseAccess DryRun returns empty ValidationChecks' {
        Mock Write-Host {}
        Mock Write-Warning {}
        $result = Test-DataverseAccess -DryRun $true
        $result.ValidationChecks.Count | Should -Be 0
    }
}

Describe 'Write-AuditLog stream isolation' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot 'Invoke-DRTest.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw
        $functionBlock = [regex]::Match($scriptContent, '(?s)(function Write-AuditLog\s*\{.+?\n\})')
        if (-not $functionBlock.Success) { throw 'Could not extract Write-AuditLog function' }
        Invoke-Expression $functionBlock.Value
        $script:AuditLogPath = $null
        $script:CorrelationId = 'test'
    }

    It 'Does not write to the success output stream' {
        # Write-AuditLog must use Write-Information, not Write-Output,
        # to avoid contaminating function return values when called inside
        # functions like Get-AccessToken.
        $output = Write-AuditLog "test message" -Level "INFO"
        $output | Should -BeNullOrEmpty
    }
}

Describe 'Get-AuthEndpoint sovereign cloud mapping' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot 'Invoke-DRTest.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw
        $functionBlock = [regex]::Match($scriptContent, '(?s)(function Get-AuthEndpoint\s*\{.+?\n\})')
        if (-not $functionBlock.Success) { throw 'Could not extract Get-AuthEndpoint function' }
        Invoke-Expression $functionBlock.Value
    }

    It 'Returns commercial endpoint for .dynamics.com' {
        Get-AuthEndpoint -EnvironmentUrl 'https://contoso.crm.dynamics.com' | Should -Be 'https://login.microsoftonline.com'
    }

    It 'Returns China endpoint for .dynamics.cn' {
        Get-AuthEndpoint -EnvironmentUrl 'https://contoso.crm.dynamics.cn' | Should -Be 'https://login.chinacloudapi.cn'
    }

    It 'Returns GCC High endpoint for .microsoftdynamics.us' {
        Get-AuthEndpoint -EnvironmentUrl 'https://contoso.crm.microsoftdynamics.us' | Should -Be 'https://login.microsoftonline.us'
    }

    It 'Returns GCC High endpoint for .appsplatform.us' {
        Get-AuthEndpoint -EnvironmentUrl 'https://contoso.crm.appsplatform.us' | Should -Be 'https://login.microsoftonline.us'
    }
}

Describe 'ClientId parameter validation' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot 'Invoke-DRTest.ps1'
        $scriptContent = Get-Content -Path $scriptPath -Raw
    }

    It 'Has ValidatePattern on ClientId parameter' {
        $scriptContent | Should -Match '\[ValidatePattern\(.+\]\s*\[string\]\$ClientId'
    }

    It 'Uses same GUID pattern as TenantId' {
        # Extract ValidatePattern values for both parameters
        $tenantPattern = [regex]::Match($scriptContent, '(?s)ValidatePattern\(''([^'']+)''\)\]\s*\[string\]\$TenantId').Groups[1].Value
        $clientPattern = [regex]::Match($scriptContent, '(?s)ValidatePattern\(''([^'']+)''\)\]\s*\[string\]\$ClientId').Groups[1].Value
        $tenantPattern | Should -Not -BeNullOrEmpty
        $clientPattern | Should -Be $tenantPattern
    }
}
