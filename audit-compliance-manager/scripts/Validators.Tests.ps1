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
        $matches = [regex]::Matches($content, '(?:Confidence\s*=\s*"([^"]+)"|\$confidence\s*=\s*"([^"]+)")')

        $matches.Count | Should -BeGreaterThan 0 -Because "$Name should contain Confidence assignments"

        foreach ($match in $matches) {
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
