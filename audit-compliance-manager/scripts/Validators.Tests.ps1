#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

<#
.SYNOPSIS
    Pester 5 unit tests for validator scripts.

.DESCRIPTION
    Tests output contracts, Confidence value casing, and basic behavior for
    Test-UnifiedAuditLog, Test-MailboxAudit, Test-PurviewRetention,
    Test-EnvironmentAudit, and Test-EnvironmentRetention validators.

.NOTES
    Run with: Invoke-Pester -Path .\Validators.Tests.ps1 -Output Detailed
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'validatorFiles',
    Justification = 'Variable feeds Pester -ForEach discovery at line 65; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'environmentRetentionValidator',
    Justification = 'Variable feeds Pester -ForEach discovery at line 82; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'unifiedAuditLogValidator',
    Justification = 'Variable feeds Pester -ForEach discovery at line 91; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'purviewRetentionValidator',
    Justification = 'Variable feeds Pester -ForEach discovery at line 100; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'mailboxAuditValidator',
    Justification = 'Variable feeds Pester -ForEach discovery at line 109; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'tenantValidators',
    Justification = 'Variable feeds Pester -ForEach discovery at line 120; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'privateScripts',
    Justification = 'Variable feeds Pester -ForEach discovery at line 129; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'runbookWrappers',
    Justification = 'Variable feeds Pester -ForEach discovery for runbook currency checks; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'exchangeBoundedScripts',
    Justification = 'Variable feeds Pester -ForEach discovery for ExchangeOnlineManagement version-bound checks; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
param()

BeforeDiscovery {
    $validatorRoot = $PSScriptRoot

    $validatorFiles = @(
        @{ Name = "Test-UnifiedAuditLog.ps1"; Path = Join-Path $validatorRoot "Test-UnifiedAuditLog.ps1" }
        @{ Name = "Test-MailboxAudit.ps1"; Path = Join-Path $validatorRoot "Test-MailboxAudit.ps1" }
        @{ Name = "Test-PurviewRetention.ps1"; Path = Join-Path $validatorRoot "Test-PurviewRetention.ps1" }
        @{ Name = "Test-EnvironmentAudit.ps1"; Path = Join-Path $validatorRoot "Test-EnvironmentAudit.ps1" }
        @{ Name = "Test-EnvironmentRetention.ps1"; Path = Join-Path $validatorRoot "Test-EnvironmentRetention.ps1" }
    )

    $environmentRetentionValidator = @(
        @{ Name = "Test-EnvironmentRetention.ps1"; Path = Join-Path $validatorRoot "Test-EnvironmentRetention.ps1" }
    )

    $unifiedAuditLogValidator = @(
        @{ Name = "Test-UnifiedAuditLog.ps1"; Path = Join-Path $validatorRoot "Test-UnifiedAuditLog.ps1" }
    )

    $purviewRetentionValidator = @(
        @{ Name = "Test-PurviewRetention.ps1"; Path = Join-Path $validatorRoot "Test-PurviewRetention.ps1" }
    )

    $mailboxAuditValidator = @(
        @{ Name = "Test-MailboxAudit.ps1"; Path = Join-Path $validatorRoot "Test-MailboxAudit.ps1" }
    )

    $tenantValidators = @(
        @{ Name = "Test-UnifiedAuditLog.ps1"; Path = Join-Path $validatorRoot "Test-UnifiedAuditLog.ps1" }
        @{ Name = "Test-MailboxAudit.ps1"; Path = Join-Path $validatorRoot "Test-MailboxAudit.ps1" }
        @{ Name = "Test-PurviewRetention.ps1"; Path = Join-Path $validatorRoot "Test-PurviewRetention.ps1" }
    )

    $privateRoot = Join-Path $validatorRoot "private"
    $privateScripts = @(
        @{ Name = "New-CanaryEvent.ps1"; Path = Join-Path $privateRoot "New-CanaryEvent.ps1" }
        @{ Name = "Connect-AuditServices.ps1"; Path = Join-Path $privateRoot "Connect-AuditServices.ps1" }
        @{ Name = "Connect-PowerPlatform.ps1"; Path = Join-Path $privateRoot "Connect-PowerPlatform.ps1" }
        @{ Name = "Get-ValidationResults.ps1"; Path = Join-Path $privateRoot "Get-ValidationResults.ps1" }
    )

    $runbookWrappers = @(
        @{ Name = "Start-TenantValidationRunbook.ps1"; Path = Join-Path $validatorRoot "Start-TenantValidationRunbook.ps1" }
        @{ Name = "Start-EnvironmentValidationRunbook.ps1"; Path = Join-Path $validatorRoot "Start-EnvironmentValidationRunbook.ps1" }
    )

    $exchangeBoundedScripts = @(
        @{ Name = "Enable-AuditLogging.ps1"; Path = Join-Path $validatorRoot "Enable-AuditLogging.ps1" }
        @{ Name = "Invoke-TenantAuditValidation.ps1"; Path = Join-Path $validatorRoot "Invoke-TenantAuditValidation.ps1" }
        @{ Name = "Start-TenantValidationRunbook.ps1"; Path = Join-Path $validatorRoot "Start-TenantValidationRunbook.ps1" }
        @{ Name = "Test-AuditLoggingCompliance.ps1"; Path = Join-Path $validatorRoot "Test-AuditLoggingCompliance.ps1" }
        @{ Name = "Test-MailboxAudit.ps1"; Path = Join-Path $validatorRoot "Test-MailboxAudit.ps1" }
        @{ Name = "Test-PurviewRetention.ps1"; Path = Join-Path $validatorRoot "Test-PurviewRetention.ps1" }
        @{ Name = "Test-UnifiedAuditLog.ps1"; Path = Join-Path $validatorRoot "Test-UnifiedAuditLog.ps1" }
        @{ Name = "private\\Connect-AuditServices.ps1"; Path = Join-Path $privateRoot "Connect-AuditServices.ps1" }
    )
}

BeforeAll {
    $script:validConfidenceValues = @("High", "Medium", "N/A")
}

Describe "Validator Confidence value consistency" {
    # All validators must use title-case Confidence values: High, Medium, or N/A (error only)
    It "<Name> uses only valid Confidence values (High, Medium, or N/A)" -ForEach $validatorFiles {
        $Path | Should -Exist -Because "$Name should exist"
        $content = Get-Content -LiteralPath $Path -Raw

        # Find all Confidence assignments (code lines, not comments/docstrings)
        $confidenceMatches = [regex]::Matches($content, '(?:Confidence\s*=\s*"([^"]+)"|\$confidence\s*=\s*"([^"]+)")')

        $confidenceMatches.Count | Should -BeGreaterThan 0 -Because "$Name should contain Confidence assignments"

        foreach ($match in $confidenceMatches) {
            $value = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
            ($script:validConfidenceValues -ccontains $value) | Should -BeTrue -Because "Confidence value '$value' in $Name must be title-case (High, Medium, or N/A)"
        }
    }
}

Describe "Test-EnvironmentRetention output contract" {
    It "Does not use undocumented Confidence value 'Low'" -ForEach $environmentRetentionValidator {
        $Path | Should -Exist -Because "$Name should exist"
        $content = Get-Content -LiteralPath $Path -Raw

        ($content -cnotmatch 'Confidence\s*=\s*"Low"') | Should -BeTrue -Because "Only High and Medium are documented Confidence values"
    }
}

Describe "Test-UnifiedAuditLog output contract" {
    It "Docstring documents title-case Confidence values" -ForEach $unifiedAuditLogValidator {
        $Path | Should -Exist -Because "$Name should exist"
        $content = Get-Content -LiteralPath $Path -Raw

        ($content -cmatch 'Confidence:\s*High\s*\|\s*Medium') | Should -BeTrue -Because "Docstring should document title-case values"
    }
}

Describe "Test-PurviewRetention output contract" {
    It "Uses title-case Confidence values" -ForEach $purviewRetentionValidator {
        $Path | Should -Exist -Because "$Name should exist"
        $content = Get-Content -LiteralPath $Path -Raw

        ($content -cnotmatch 'Confidence\s*=\s*"HIGH"') | Should -BeTrue -Because "Should use 'High' not 'HIGH'"
    }
}

Describe "Test-MailboxAudit output contract" {
    It "Uses title-case Confidence values" -ForEach $mailboxAuditValidator {
        $Path | Should -Exist -Because "$Name should exist"
        $content = Get-Content -LiteralPath $Path -Raw

        ($content -cnotmatch 'Confidence\s*=\s*"HIGH"') | Should -BeTrue -Because "Should use 'High' not 'HIGH'"
    }
}

Describe "Tenant validator output shape includes RawValue" {
    # Verifies the orchestrator (Invoke-TenantAuditValidation) can access .RawValue
    # on results from all three tenant validators without silently falling back to N/A.
    It "<Name> includes RawValue property in return PSCustomObject" -ForEach $tenantValidators {
        $Path | Should -Exist -Because "$Name should exist"
        $content = Get-Content -LiteralPath $Path -Raw

        ($content -cmatch 'RawValue\s*=') | Should -BeTrue -Because "$Name must include a RawValue property so the orchestrator can record audit evidence to Dataverse"
    }
}

Describe "Validator script direct-invocation blocks" {
    It "<Name> has a direct-invocation block" -ForEach $privateScripts {
        $Path | Should -Exist -Because "$Name should exist"
        $content = Get-Content -LiteralPath $Path -Raw

        ($content -cmatch 'MyInvocation\.InvocationName\s+-ne\s+') | Should -BeTrue -Because "$Name should support direct invocation"
    }
}

Describe "Runbook wrapper auth currency" {
    It "<Name> uses Connect-PowerPlatform helper and avoids MSAL.PS" -ForEach $runbookWrappers {
        $Path | Should -Exist -Because "$Name should exist"
        $content = Get-Content -LiteralPath $Path -Raw

        ($content -cmatch 'Connect-PowerPlatform\.ps1') | Should -BeTrue -Because "$Name should load the shared Connect-PowerPlatform helper"
        ($content -cmatch '\bConnect-PowerPlatform\b') | Should -BeTrue -Because "$Name should acquire Dataverse drift tokens through Connect-PowerPlatform"
        ($content -cnotmatch 'MSAL\.PS') | Should -BeTrue -Because "$Name should not require the archived MSAL.PS module"
        ($content -cnotmatch 'Get-MsalToken') | Should -BeTrue -Because "$Name should not call Get-MsalToken"
    }
}

Describe "ExchangeOnlineManagement compatibility bounds" {
    It "<Name> caps ExchangeOnlineManagement at 3.9.2 for current runtime compatibility" -ForEach $exchangeBoundedScripts {
        $Path | Should -Exist -Because "$Name should exist"
        $content = Get-Content -LiteralPath $Path -Raw

        ($content -cmatch 'ModuleName\s*=\s*["'']ExchangeOnlineManagement["''][^\r\n]*MaximumVersion\s*=\s*["'']3\.9\.2["'']') | Should -BeTrue -Because "$Name should bound ExchangeOnlineManagement to <=3.9.2 for PowerShell 7.4 compatibility"
    }
}

Describe "Helper script load and invocation contracts" {
    BeforeAll {
        $script:helperArtifactsDir = Join-Path $PSScriptRoot '.pester-artifacts'
        $script:createdPowerAppsAccountStub = $false
        New-Item -ItemType Directory -Path $script:helperArtifactsDir -Force | Out-Null

        if (-not (Get-Command Add-PowerAppsAccount -ErrorAction SilentlyContinue)) {
            Set-Item -Path 'Function:\Add-PowerAppsAccount' -Value {
                [CmdletBinding()]
                param(
                    [string]$TenantID,
                    [string]$ApplicationId,
                    [string]$ClientSecret,
                    [string]$CertificateThumbprint
                )
            }
            $script:createdPowerAppsAccountStub = $true
        }

        function Get-SanitizedHelperScriptPath {
            param(
                [Parameter(Mandatory = $true)]
                [string]$SourcePath
            )

            $fileName = Split-Path -Path $SourcePath -Leaf
            $sanitizedPath = Join-Path $script:helperArtifactsDir "sanitized-$fileName"
            $content = Get-Content -LiteralPath $SourcePath -Raw
            $sanitizedContent = ($content -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#Requires\s+-Modules\b' }) -join [Environment]::NewLine

            Set-Content -LiteralPath $sanitizedPath -Value $sanitizedContent -Encoding UTF8
            return $sanitizedPath
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:helperArtifactsDir -Recurse -Force -ErrorAction SilentlyContinue
        if ($script:createdPowerAppsAccountStub) {
            Remove-Item -LiteralPath 'Function:\Add-PowerAppsAccount' -Force -ErrorAction SilentlyContinue
        }
    }

    It "Connect-PowerPlatform helper dot-sources and returns a client-secret auth result" {
        $connectHelperPath = Join-Path $PSScriptRoot 'private\Connect-PowerPlatform.ps1'
        if (Get-Command Connect-PowerPlatform -CommandType Function -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath 'Function:\Connect-PowerPlatform' -Force
        }

        $sanitizedConnectHelperPath = Get-SanitizedHelperScriptPath -SourcePath $connectHelperPath
        . $sanitizedConnectHelperPath

        Mock Add-PowerAppsAccount { } -Verifiable
        Mock Invoke-RestMethod { @{ access_token = 'dataverse-token-123' } } -Verifiable

        $clientSecret = [System.Security.SecureString]::new()
        'dev-only-secret'.ToCharArray() | ForEach-Object { $clientSecret.AppendChar($_) }
        $clientSecret.MakeReadOnly()
        $result = Connect-PowerPlatform `
            -TenantId 'contoso.onmicrosoft.com' `
            -DataverseUrl 'https://org.crm.dynamics.com' `
            -ClientId 'app-id' `
            -ClientSecret $clientSecret

        $result.PowerAppsAuthenticated | Should -BeTrue
        $result.DataverseAccessToken | Should -Be 'dataverse-token-123'
        $result.AuthMethod | Should -Be 'ServicePrincipal-Secret'
        Should -Invoke Add-PowerAppsAccount -Times 1
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -eq 'https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/v2.0/token' -and $Method -eq 'Post'
        }
    }

    It "Compare-ValidationBaseline helper dot-sources and handles first-run responses" {
        $compareHelperPath = Join-Path $PSScriptRoot 'private\Compare-ValidationBaseline.ps1'
        if (Get-Command Compare-ValidationBaseline -CommandType Function -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath 'Function:\Compare-ValidationBaseline' -Force
        }

        $sanitizedCompareHelperPath = Get-SanitizedHelperScriptPath -SourcePath $compareHelperPath
        . $sanitizedCompareHelperPath

        Mock Invoke-RestMethod { @{ value = @() } } -Verifiable

        $result = Compare-ValidationBaseline `
            -DataverseUrl 'https://org.crm.dynamics.com' `
            -DataverseToken 'token' `
            -Scope 'Tenant' `
            -CurrentStatus 'Passed'

        $result.IsFirstRun | Should -BeTrue
        $result.DriftDetected | Should -BeFalse
        Should -Invoke Invoke-RestMethod -Times 1
    }

    It "Get-ValidationResults helper dot-sources and follows @odata.nextLink pagination" {
        $getResultsHelperPath = Join-Path $PSScriptRoot 'private\Get-ValidationResults.ps1'
        if (Get-Command Get-ValidationResults -CommandType Function -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath 'Function:\Get-ValidationResults' -Force
        }

        $sanitizedGetResultsHelperPath = Get-SanitizedHelperScriptPath -SourcePath $getResultsHelperPath
        . $sanitizedGetResultsHelperPath

        $script:pageCallCount = 0
        Mock Invoke-RestMethod {
            $script:pageCallCount++
            if ($script:pageCallCount -eq 1) {
                return @{
                    value            = @([PSCustomObject]@{ fsi_name = 'page-1-row' })
                    '@odata.nextLink' = 'https://org.crm.dynamics.com/api/data/v9.2/fsi_auditvalidationhistories?$skiptoken=abc'
                }
            }

            return @{
                value            = @([PSCustomObject]@{ fsi_name = 'page-2-row' })
                '@odata.nextLink' = $null
            }
        } -Verifiable

        $rows = Get-ValidationResults `
            -DataverseUrl 'https://org.crm.dynamics.com' `
            -AccessToken 'token' `
            -Scope 'Tenant' `
            -FromDate (Get-Date).AddDays(-1) `
            -ToDate (Get-Date)

        $rows.Count | Should -Be 2
        $script:pageCallCount | Should -Be 2
        Should -Invoke Invoke-RestMethod -Times 2
    }

    It "Write-ValidationResult helper dot-sources and maps severity/scope option sets" {
        $writeResultHelperPath = Join-Path $PSScriptRoot 'private\Write-ValidationResult.ps1'
        if (Get-Command Write-ValidationResult -CommandType Function -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath 'Function:\Write-ValidationResult' -Force
        }

        $sanitizedWriteResultHelperPath = Get-SanitizedHelperScriptPath -SourcePath $writeResultHelperPath
        . $sanitizedWriteResultHelperPath

        $script:capturedWriteBody = $null
        Mock Invoke-RestMethod {
            $script:capturedWriteBody = $Body
            @{ fsi_auditvalidationhistoryid = 'record-123' }
        } -Verifiable

        $recordId = Write-ValidationResult `
            -DataverseUrl 'https://org.crm.dynamics.com' `
            -AccessToken 'token' `
            -RunId 'run-123' `
            -Scope 'Tenant' `
            -Severity 'Passed' `
            -ValidationType 'UnifiedAuditLog' `
            -RawValue 'UnifiedAuditLogIngestionEnabled=True' `
            -Reason 'Validated'

        $recordId | Should -Be 'record-123'
        $payload = $script:capturedWriteBody | ConvertFrom-Json
        $payload.fsi_scope | Should -Be 100000000
        $payload.fsi_severity | Should -Be 100000000
        $payload.fsi_validationtype | Should -Be 'UnifiedAuditLog'
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Method -eq 'Post' }
    }
}
