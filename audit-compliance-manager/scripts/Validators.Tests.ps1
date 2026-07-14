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
    'PSUseDeclaredVarsMoreThanAssignments', 'environmentValidatorScripts',
    Justification = 'Variable feeds Pester -ForEach discovery for environment-validator direct-invocation and load-behavior checks; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'runbookWrappers',
    Justification = 'Variable feeds Pester -ForEach discovery for runbook currency checks; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'exchangeBoundedScripts',
    Justification = 'Variable feeds Pester -ForEach discovery for ExchangeOnlineManagement version-bound checks; PSSA static analysis misses Pester discovery scriptblock reads.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'sourceContractMatrix',
    Justification = 'Variable feeds Pester -ForEach discovery for dot-source parameter preservation contracts; PSSA static analysis misses Pester discovery scriptblock reads.'
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

    $environmentValidatorScripts = @(
        @{
            Name                = "Test-EnvironmentAudit.ps1"
            Path                = Join-Path $validatorRoot "Test-EnvironmentAudit.ps1"
            FunctionName        = "Test-EnvironmentAudit"
            MandatoryParameters = @("EnvironmentUrl", "AccessToken")
        }
        @{
            Name                = "Test-EnvironmentRetention.ps1"
            Path                = Join-Path $validatorRoot "Test-EnvironmentRetention.ps1"
            FunctionName        = "Test-EnvironmentRetention"
            MandatoryParameters = @("EnvironmentUrl", "AccessToken", "DataverseUrl", "CentralAccessToken", "Zone")
        }
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

    $sourceContractMatrix = @(
        @{
            Name             = 'Export-AuditValidationEvidence.ps1'
            Path             = Join-Path $validatorRoot 'Export-AuditValidationEvidence.ps1'
            ExpectedParams   = @('DataverseUrl', 'TenantId', 'Scope', 'OutputDirectory', 'RunId', 'FromDate', 'ToDate', 'Interactive', 'CertificateThumbprint', 'ClientId')
            AuthAnchorPattern = 'if\s*\(-not\s*\(Test-Path\s+-Path\s+\$OutputDirectory\)\)'
        }
        @{
            Name             = 'Invoke-EnvironmentAuditValidation.ps1'
            Path             = Join-Path $validatorRoot 'Invoke-EnvironmentAuditValidation.ps1'
            ExpectedParams   = @('TenantId', 'DataverseUrl', 'ClientId', 'ClientSecret', 'CertificateThumbprint', 'Interactive', 'IncludeTrialDev', 'GracePeriodHours', 'OutputPath', 'SkipDiscovery')
            AuthAnchorPattern = '\$authParams\s*=\s*@\{'
        }
        @{
            Name             = 'Invoke-TenantAuditValidation.ps1'
            Path             = Join-Path $validatorRoot 'Invoke-TenantAuditValidation.ps1'
            ExpectedParams   = @('Zone', 'OutputPath', 'SkipCanaryValidation', 'GracePeriodHours', 'CanaryWaitSeconds', 'DataverseUrl', 'Interactive', 'TenantId', 'ClientId', 'CertificateThumbprint', 'CertificateFilePath')
            AuthAnchorPattern = 'if\s*\(\$DataverseUrl\)'
        }
        @{
            Name             = 'Start-EnvironmentValidationRunbook.ps1'
            Path             = Join-Path $validatorRoot 'Start-EnvironmentValidationRunbook.ps1'
            ExpectedParams   = @('TenantId', 'DataverseUrl', 'ClientId', 'CertificateThumbprint', 'ClientSecret', 'IncludeTrialDev', 'GracePeriodHours', 'SkipDiscovery')
            AuthAnchorPattern = '\$envParams\s*=\s*@\{'
        }
        @{
            Name             = 'Start-TenantValidationRunbook.ps1'
            Path             = Join-Path $validatorRoot 'Start-TenantValidationRunbook.ps1'
            ExpectedParams   = @('Zone', 'DataverseUrl', 'TenantId', 'ClientId', 'CertificateThumbprint', 'SkipCanaryValidation', 'CanaryWaitSeconds')
            AuthAnchorPattern = '\$ualParams\s*=\s*@\{'
        }
        @{
            Name             = 'Test-MailboxAudit.ps1'
            Path             = Join-Path $validatorRoot 'Test-MailboxAudit.ps1'
            ExpectedParams   = @('Interactive', 'TenantId', 'ClientId', 'CertificateThumbprint', 'CertificateFilePath')
            AuthAnchorPattern = 'function\s+Test-MailboxAudit'
        }
        @{
            Name             = 'Test-PurviewRetention.ps1'
            Path             = Join-Path $validatorRoot 'Test-PurviewRetention.ps1'
            ExpectedParams   = @('Zone', 'Interactive', 'TenantId', 'ClientId', 'CertificateThumbprint', 'CertificateFilePath')
            AuthAnchorPattern = 'function\s+Test-PurviewRetention'
        }
        @{
            Name             = 'Test-UnifiedAuditLog.ps1'
            Path             = Join-Path $validatorRoot 'Test-UnifiedAuditLog.ps1'
            ExpectedParams   = @('SkipCanaryValidation', 'GracePeriodHours', 'CanaryWaitSeconds', 'Interactive', 'TenantId', 'ClientId', 'CertificateThumbprint', 'CertificateFilePath')
            AuthAnchorPattern = 'function\s+Test-UnifiedAuditLog'
        }
        @{
            Name             = 'Invoke-EnvironmentDiscovery.ps1'
            Path             = Join-Path $validatorRoot 'Invoke-EnvironmentDiscovery.ps1'
            ExpectedParams   = @('TenantId', 'DataverseUrl', 'ClientId', 'ClientSecret', 'CertificateThumbprint', 'Interactive', 'IncludeTrialDev', 'OutputPath')
            AuthAnchorPattern = 'function\s+Invoke-EnvironmentDiscovery'
        }
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

    It "<Name> has a direct-invocation block" -ForEach $environmentValidatorScripts {
        $Path | Should -Exist -Because "$Name should exist"
        $content = Get-Content -LiteralPath $Path -Raw

        ($content -cmatch 'MyInvocation\.InvocationName\s+-ne\s+') | Should -BeTrue -Because "$Name should support direct invocation"
        ($content -cmatch '@PSBoundParameters') | Should -BeTrue -Because "$Name direct invocation should forward script inputs via @PSBoundParameters"
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

Describe "Drift baseline wrapper wiring contracts" {
    It "Start-EnvironmentValidationRunbook passes CurrentRunId to Compare-ValidationBaseline" {
        $path = Join-Path $PSScriptRoot "Start-EnvironmentValidationRunbook.ps1"
        $path | Should -Exist
        $content = Get-Content -LiteralPath $path -Raw

        ($content -cmatch '-CurrentRunId\s+\$validationResults\.RunId') | Should -BeTrue -Because "Environment drift detection must exclude the current run ID from baseline selection."
    }

    It "Start-TenantValidationRunbook passes CurrentRunId to both Compare-ValidationBaseline call sites" {
        $path = Join-Path $PSScriptRoot "Start-TenantValidationRunbook.ps1"
        $path | Should -Exist
        $content = Get-Content -LiteralPath $path -Raw
        $currentRunIdMatches = [regex]::Matches($content, '-CurrentRunId\s+\$validationResults\.RunId')

        $currentRunIdMatches.Count | Should -Be 2 -Because "Tenant runbook must pass current run ID in both overall and per-validator drift checks."
    }

    It "Invoke-TenantAuditValidation exposes RunId in orchestrator output" {
        $path = Join-Path $PSScriptRoot "Invoke-TenantAuditValidation.ps1"
        $path | Should -Exist
        $content = Get-Content -LiteralPath $path -Raw

        ($content -cmatch 'RunId\s*=\s*\$runId') | Should -BeTrue -Because "Tenant orchestrator output must expose RunId for downstream drift exclusion."
    }
}

Describe "RunId source contracts" {
    It "Invoke-EnvironmentAuditValidation generates RunId after restore and before results initialization and first write" {
        $path = Join-Path $PSScriptRoot "Invoke-EnvironmentAuditValidation.ps1"
        $path | Should -Exist
        $content = Get-Content -LiteralPath $path -Raw

        $restoreMatch = [regex]::Match($content, 'foreach\s*\(\s*\$name\s+in\s+\$dotSourceSafeVars\.Keys\s*\)\s*\{')
        $runIdMatch = [regex]::Match($content, '\$runId\s*=\s*\[Guid\]::NewGuid\(\)')
        $timestampMatch = [regex]::Match($content, '\$timestamp\s*=\s*Get-Date\s+-AsUTC\s+-Format\s+"o"')
        $resultsMatch = [regex]::Match($content, '\$results\s*=\s*\[PSCustomObject\]\s*@\{')
        $firstWriteMatch = [regex]::Match($content, 'Write-ValidationResult\s+@(?:writeParams|orchParams)')

        $restoreMatch.Success | Should -BeTrue -Because "Environment orchestrator must restore script-scope params after dot-sourcing."
        $runIdMatch.Success | Should -BeTrue -Because "Environment orchestrator must generate a RunId."
        $timestampMatch.Success | Should -BeTrue -Because "Environment orchestrator must stamp a UTC timestamp alongside RunId."
        $resultsMatch.Success | Should -BeTrue -Because "Environment orchestrator must initialize a results object."
        $firstWriteMatch.Success | Should -BeTrue -Because "Environment orchestrator must persist validation rows."

        $runIdMatch.Index | Should -BeGreaterThan $restoreMatch.Index -Because "RunId generation must occur after the final dot-source restore loop."
        $timestampMatch.Index | Should -BeGreaterThan $runIdMatch.Index -Because "Timestamp must be generated after RunId to keep correlated banner order."
        $runIdMatch.Index | Should -BeLessThan $resultsMatch.Index -Because "RunId generation must occur before results initialization."
        $runIdMatch.Index | Should -BeLessThan $firstWriteMatch.Index -Because "RunId must exist before first Write-ValidationResult call."
    }

    It "Invoke-EnvironmentAuditValidation results and all Write-ValidationResult parameter sets retain RunId wiring" {
        $path = Join-Path $PSScriptRoot "Invoke-EnvironmentAuditValidation.ps1"
        $path | Should -Exist
        $content = Get-Content -LiteralPath $path -Raw

        $resultsBlock = [regex]::Match($content, '\$results\s*=\s*\[PSCustomObject\]\s*@\{(?<Body>.*?)\}\s*', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $resultsBlock.Success | Should -BeTrue -Because "Environment orchestrator should initialize a results object."
        ($resultsBlock.Groups['Body'].Value -cmatch 'RunId\s*=\s*\$runId') | Should -BeTrue -Because "Environment results object must expose RunId."

        $writeParamBlocks = [regex]::Matches($content, '\$writeParams\s*=\s*@\{(?<Body>.*?)\}\s*Write-ValidationResult\s+@writeParams', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $writeParamBlocks.Count | Should -Be 2 -Because "Environment orchestrator should keep both validator Write-ValidationResult writeParams blocks."
        foreach ($block in $writeParamBlocks) {
            ($block.Groups['Body'].Value -cmatch 'RunId\s*=\s*\$runId') | Should -BeTrue -Because "Each validator writeParams block must pass the shared RunId."
        }

        $orchBlock = [regex]::Match($content, '\$orchParams\s*=\s*@\{(?<Body>.*?)\}\s*Write-ValidationResult\s+@orchParams', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $orchBlock.Success | Should -BeTrue -Because "Environment orchestrator should keep the per-environment orchestrator Write-ValidationResult block."
        ($orchBlock.Groups['Body'].Value -cmatch 'RunId\s*=\s*\$runId') | Should -BeTrue -Because "Orchestrator write parameter set must pass the shared RunId."

        $writeInvocationCount = [regex]::Matches($content, 'Write-ValidationResult\s+@(?:writeParams|orchParams)').Count
        $writeInvocationCount | Should -Be 3 -Because "Environment orchestrator should continue writing two validator rows plus one orchestrator row per environment."
    }

    It "Start-TenantValidationRunbook final output includes RunId" {
        $path = Join-Path $PSScriptRoot "Start-TenantValidationRunbook.ps1"
        $path | Should -Exist
        $content = Get-Content -LiteralPath $path -Raw

        $outputBlock = [regex]::Match($content, '\$output\s*=\s*\[PSCustomObject\]\s*@\{(?<Body>.*?)\}\s*', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $outputBlock.Success | Should -BeTrue -Because "Tenant runbook should build a final output object."
        ($outputBlock.Groups['Body'].Value -cmatch 'RunType\s*=\s*"TenantValidation"') | Should -BeTrue -Because "Test should target tenant runbook final output object."
        ($outputBlock.Groups['Body'].Value -cmatch 'RunId\s*=\s*\$validationResults\.RunId') | Should -BeTrue -Because "Tenant runbook output must expose RunId for evidence correlation parity."
    }
}

Describe "Dot-source parameter-preservation source contracts" {
    It "<Name> snapshots and restores script-scope params around dot-sources" -ForEach $sourceContractMatrix {
        $Path | Should -Exist -Because "$Name should exist"
        $content = Get-Content -LiteralPath $Path -Raw

        $snapshotMatch = [regex]::Match($content, '\$dotSourceSafeVars\s*=\s*@\{(?<Body>.*?)\}\s*', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $snapshotMatch.Success | Should -BeTrue -Because "$Name must define a dot-source snapshot hashtable"

        $snapshotIndex = $snapshotMatch.Index
        $snapshotBody = $snapshotMatch.Groups['Body'].Value
        $snapshotKeys = [regex]::Matches($snapshotBody, '(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value }

        ($snapshotKeys | Sort-Object -Unique) | Should -Be ($ExpectedParams | Sort-Object) -Because "$Name must snapshot the full script parameter set"

        $dotSourceMatches = [regex]::Matches($content, '(?m)^\s*\.\s+.+$')
        $dotSourceMatches.Count | Should -BeGreaterThan 0 -Because "$Name must dot-source helper or validator scripts"
        $firstDotSourceIndex = $dotSourceMatches[0].Index
        $lastDotSourceIndex = $dotSourceMatches[$dotSourceMatches.Count - 1].Index

        $snapshotIndex | Should -BeLessThan $firstDotSourceIndex -Because "$Name snapshot block must appear before the first dot-source"

        $restoreMatch = [regex]::Match($content, 'foreach\s*\(\s*\$name\s+in\s+\$dotSourceSafeVars\.Keys\s*\)\s*\{')
        $restoreMatch.Success | Should -BeTrue -Because "$Name must restore script-scope params after dot-sourcing"
        $restoreIndex = $restoreMatch.Index

        $restoreIndex | Should -BeGreaterThan $lastDotSourceIndex -Because "$Name restore loop must run after the final dot-source"

        $anchorMatch = [regex]::Match($content, $AuthAnchorPattern)
        $anchorMatch.Success | Should -BeTrue -Because "$Name anchor pattern should exist to verify restore ordering"
        $restoreIndex | Should -BeLessThan $anchorMatch.Index -Because "$Name restore loop must execute before parameter-dependent logic"
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

                $null = $TenantID, $ApplicationId, $ClientSecret, $CertificateThumbprint
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

    It "preserves non-empty DataverseUrl in local scope when restoring after helper dot-source" {
        $connectHelperPath = Join-Path $PSScriptRoot 'private\Connect-PowerPlatform.ps1'
        $sanitizedConnectHelperPath = Get-SanitizedHelperScriptPath -SourcePath $connectHelperPath

        function Invoke-DotSourceRestoreProbe {
            param(
                [Parameter(Mandatory = $true)]
                [string]$DataverseUrl,

                [Parameter(Mandatory = $true)]
                [string]$HelperPath
            )

            $dotSourceSafeVars = @{
                DataverseUrl = $DataverseUrl
            }

            . $HelperPath

            foreach ($name in $dotSourceSafeVars.Keys) {
                Set-Variable -Name $name -Value $dotSourceSafeVars[$name] -Scope Local
            }

            [PSCustomObject]@{
                DataverseUrlValue = $DataverseUrl
                DataverseUrlType  = $DataverseUrl.GetType().FullName
                Length            = $DataverseUrl.Length
            }
        }

        $probeUrl = 'https://org.crm.dynamics.com'
        $probeResult = Invoke-DotSourceRestoreProbe -DataverseUrl $probeUrl -HelperPath $sanitizedConnectHelperPath

        $probeResult.DataverseUrlValue | Should -Be $probeUrl
        $probeResult.DataverseUrlType | Should -Be 'System.String'
        $probeResult.Length | Should -BeGreaterThan 0
    }

    It "<Name> dot-sources with no args, loads <FunctionName>, and preserves mandatory function contracts" -ForEach $environmentValidatorScripts {
        if (Get-Command $FunctionName -CommandType Function -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath "Function:\$FunctionName" -Force
        }

        $sanitizedValidatorPath = Get-SanitizedHelperScriptPath -SourcePath $Path
        $dotSourceError = $null
        try {
            . $sanitizedValidatorPath
        } catch {
            $dotSourceError = $_
        }
        $dotSourceError | Should -BeNullOrEmpty -Because "$Name should load by dot-sourcing with no script-scope arguments"

        $loadedFunction = Get-Command $FunctionName -CommandType Function -ErrorAction SilentlyContinue
        $loadedFunction | Should -Not -BeNullOrEmpty -Because "$FunctionName should be available after dot-sourcing $Name"

        foreach ($parameterName in $MandatoryParameters) {
            $parameterMetadata = $loadedFunction.Parameters[$parameterName]
            $parameterMetadata | Should -Not -BeNullOrEmpty -Because "$FunctionName should include parameter '$parameterName'"

            $parameterAttribute = $parameterMetadata.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -First 1

            $parameterAttribute | Should -Not -BeNullOrEmpty -Because "$FunctionName parameter '$parameterName' should include [Parameter()] metadata"
            $parameterAttribute.Mandatory | Should -BeTrue -Because "$FunctionName parameter '$parameterName' should remain mandatory at function scope"
        }
    }

    It "Compare-ValidationBaseline escapes CurrentRunId in URI and treats empty baseline as first run" {
        $compareHelperPath = Join-Path $PSScriptRoot 'private\Compare-ValidationBaseline.ps1'
        if (Get-Command Compare-ValidationBaseline -CommandType Function -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath 'Function:\Compare-ValidationBaseline' -Force
        }

        $sanitizedCompareHelperPath = Get-SanitizedHelperScriptPath -SourcePath $compareHelperPath
        . $sanitizedCompareHelperPath

        $script:lastBaselineUri = $null
        Mock Invoke-RestMethod {
            $script:lastBaselineUri = $Uri
            @{ value = @() }
        } -Verifiable

        $result = Compare-ValidationBaseline `
            -DataverseUrl 'https://org.crm.dynamics.com' `
            -DataverseToken 'token' `
            -Scope 'Tenant' `
            -CurrentStatus 'Passed' `
            -CurrentRunId "run'id-123"

        $script:lastBaselineUri | Should -Match "fsi_runid ne 'run''id-123'"
        $result.IsFirstRun | Should -BeTrue
        $result.DriftDetected | Should -BeFalse
        Should -Invoke Invoke-RestMethod -Times 1
    }

    It "Compare-ValidationBaseline omits CurrentRunId filter when CurrentRunId is not provided" {
        $compareHelperPath = Join-Path $PSScriptRoot 'private\Compare-ValidationBaseline.ps1'
        if (Get-Command Compare-ValidationBaseline -CommandType Function -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath 'Function:\Compare-ValidationBaseline' -Force
        }

        $sanitizedCompareHelperPath = Get-SanitizedHelperScriptPath -SourcePath $compareHelperPath
        . $sanitizedCompareHelperPath

        $script:lastBaselineUri = $null
        Mock Invoke-RestMethod {
            $script:lastBaselineUri = $Uri
            @{ value = @() }
        } -Verifiable

        $null = Compare-ValidationBaseline `
            -DataverseUrl 'https://org.crm.dynamics.com' `
            -DataverseToken 'token' `
            -Scope 'Tenant' `
            -CurrentStatus 'Passed'

        $script:lastBaselineUri | Should -Not -Match "fsi_runid ne"
        Should -Invoke Invoke-RestMethod -Times 1
    }

    It "Compare-ValidationBaseline omits CurrentRunId filter when CurrentRunId is whitespace" {
        $compareHelperPath = Join-Path $PSScriptRoot 'private\Compare-ValidationBaseline.ps1'
        if (Get-Command Compare-ValidationBaseline -CommandType Function -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath 'Function:\Compare-ValidationBaseline' -Force
        }

        $sanitizedCompareHelperPath = Get-SanitizedHelperScriptPath -SourcePath $compareHelperPath
        . $sanitizedCompareHelperPath

        $script:lastBaselineUri = $null
        Mock Invoke-RestMethod {
            $script:lastBaselineUri = $Uri
            @{ value = @() }
        } -Verifiable

        $null = Compare-ValidationBaseline `
            -DataverseUrl 'https://org.crm.dynamics.com' `
            -DataverseToken 'token' `
            -Scope 'Tenant' `
            -CurrentStatus 'Passed' `
            -CurrentRunId "  `t  "

        $script:lastBaselineUri | Should -Not -Match "fsi_runid ne"
        Should -Invoke Invoke-RestMethod -Times 1
    }

    It "Compare-ValidationBaseline detects drift for Failed current status against prior Passed baseline" {
        $compareHelperPath = Join-Path $PSScriptRoot 'private\Compare-ValidationBaseline.ps1'
        if (Get-Command Compare-ValidationBaseline -CommandType Function -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath 'Function:\Compare-ValidationBaseline' -Force
        }

        $sanitizedCompareHelperPath = Get-SanitizedHelperScriptPath -SourcePath $compareHelperPath
        . $sanitizedCompareHelperPath

        Mock Invoke-RestMethod {
            @{
                value = @(
                    [PSCustomObject]@{
                        fsi_severity  = 100000000
                        fsi_timestamp = '2026-07-14T12:00:00Z'
                    }
                )
            }
        } -Verifiable

        $result = Compare-ValidationBaseline `
            -DataverseUrl 'https://org.crm.dynamics.com' `
            -DataverseToken 'token' `
            -Scope 'Tenant' `
            -CurrentStatus 'Failed' `
            -CurrentRunId 'run-456'

        $result.IsFirstRun | Should -BeFalse
        $result.DriftDetected | Should -BeTrue
        $result.BaselineSeverity | Should -Be 100000000
        $result.BaselineStatus | Should -Be 'Passed'
        Should -Invoke Invoke-RestMethod -Times 1
    }

    It "Compare-ValidationBaseline reports no drift for Passed current status against prior Passed baseline" {
        $compareHelperPath = Join-Path $PSScriptRoot 'private\Compare-ValidationBaseline.ps1'
        if (Get-Command Compare-ValidationBaseline -CommandType Function -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath 'Function:\Compare-ValidationBaseline' -Force
        }

        $sanitizedCompareHelperPath = Get-SanitizedHelperScriptPath -SourcePath $compareHelperPath
        . $sanitizedCompareHelperPath

        Mock Invoke-RestMethod {
            @{
                value = @(
                    [PSCustomObject]@{
                        fsi_severity  = 100000000
                        fsi_timestamp = '2026-07-14T12:00:00Z'
                    }
                )
            }
        } -Verifiable

        $result = Compare-ValidationBaseline `
            -DataverseUrl 'https://org.crm.dynamics.com' `
            -DataverseToken 'token' `
            -Scope 'Tenant' `
            -CurrentStatus 'Passed' `
            -CurrentRunId 'run-789'

        $result.IsFirstRun | Should -BeFalse
        $result.DriftDetected | Should -BeFalse
        $result.BaselineSeverity | Should -Be 100000000
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
