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

BeforeAll {
    $script:validatorDir = $PSScriptRoot
}

Describe "Validator Confidence value consistency" {
    # All validators must use title-case Confidence values: High, Medium, or N/A (error only)
    $validConfidenceValues = @("High", "Medium", "N/A")

    $validatorFiles = @(
        "Test-UnifiedAuditLog.ps1",
        "Test-MailboxAudit.ps1",
        "Test-PurviewRetention.ps1",
        "Test-EnvironmentAudit.ps1",
        "Test-EnvironmentRetention.ps1"
    )

    foreach ($file in $validatorFiles) {
        Context "$file" {
            It "Uses only valid Confidence values (High, Medium, or N/A)" {
                $filePath = Join-Path $script:validatorDir $file
                $content = Get-Content $filePath -Raw

                # Find all Confidence assignments (code lines, not comments/docstrings)
                $matches = [regex]::Matches($content, '(?:Confidence\s*=\s*"([^"]+)"|\$confidence\s*=\s*"([^"]+)")')

                $matches.Count | Should -BeGreaterThan 0 -Because "$file should contain Confidence assignments"

                foreach ($match in $matches) {
                    $value = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
                    $value | Should -BeIn $validConfidenceValues -Because "Confidence value '$value' in $file must be title-case (High, Medium, or N/A)"
                }
            }
        }
    }
}

Describe "Test-EnvironmentRetention output contract" {
    It "Does not use undocumented Confidence value 'Low'" {
        $filePath = Join-Path $script:validatorDir "Test-EnvironmentRetention.ps1"
        $content = Get-Content $filePath -Raw

        $content | Should -Not -Match 'Confidence\s*=\s*"Low"' -Because "Only High and Medium are documented Confidence values"
    }
}

Describe "Test-UnifiedAuditLog output contract" {
    It "Docstring documents title-case Confidence values" {
        $filePath = Join-Path $script:validatorDir "Test-UnifiedAuditLog.ps1"
        $content = Get-Content $filePath -Raw

        $content | Should -Match 'Confidence:\s*High\s*\|\s*Medium' -Because "Docstring should document title-case values"
    }
}

Describe "Test-PurviewRetention output contract" {
    It "Uses title-case Confidence values" {
        $filePath = Join-Path $script:validatorDir "Test-PurviewRetention.ps1"
        $content = Get-Content $filePath -Raw

        $content | Should -Not -Match 'Confidence\s*=\s*"HIGH"' -Because "Should use 'High' not 'HIGH'"
    }
}

Describe "Test-MailboxAudit output contract" {
    It "Uses title-case Confidence values" {
        $filePath = Join-Path $script:validatorDir "Test-MailboxAudit.ps1"
        $content = Get-Content $filePath -Raw

        $content | Should -Not -Match 'Confidence\s*=\s*"HIGH"' -Because "Should use 'High' not 'HIGH'"
    }
}

Describe "Tenant validator output shape includes RawValue" {
    # Ensures the orchestrator (Invoke-TenantAuditValidation) can access .RawValue
    # on results from all three tenant validators without silently falling back to N/A.

    $tenantValidators = @(
        "Test-UnifiedAuditLog.ps1",
        "Test-MailboxAudit.ps1",
        "Test-PurviewRetention.ps1"
    )

    foreach ($file in $tenantValidators) {
        Context "$file" {
            It "Includes RawValue property in return PSCustomObject" {
                $filePath = Join-Path $script:validatorDir $file
                $content = Get-Content $filePath -Raw

                $content | Should -Match 'RawValue\s*=' -Because "$file must include a RawValue property so the orchestrator can record audit evidence to Dataverse"
            }
        }
    }
}

Describe "Validator script direct-invocation blocks" {
    $privateDir = Join-Path $script:validatorDir "private"

    $privateScripts = @(
        "New-CanaryEvent.ps1",
        "Connect-AuditServices.ps1",
        "Connect-PowerPlatform.ps1",
        "Get-ValidationResults.ps1"
    )

    foreach ($script in $privateScripts) {
        It "$script has a direct-invocation block" {
            $filePath = Join-Path $privateDir $script
            $content = Get-Content $filePath -Raw

            $content | Should -Match 'MyInvocation\.InvocationName\s+-ne\s+' -Because "$script should support direct invocation"
        }
    }
}
