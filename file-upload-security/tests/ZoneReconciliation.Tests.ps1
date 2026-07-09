#Requires -Version 7.2
#Requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "5.0.0" }

<#
.SYNOPSIS
    Pester 5 unit assertions for the FUS canonical zone reconciliation
    (coordinator decision Option A) and the severity-String fix.

.DESCRIPTION
    Locks the canonical contract so a future half-done edit cannot silently
    re-invert the zone mapping:

      most-restrictive policy  <->  Zone 1 (Enterprise)  <->  100000001
      least-restrictive policy <->  Zone 3 (Personal)    <->  100000003

    Coverage:
      - Policy table (fileupload-baseline.json): strictest policy attaches to
        Zone 1, discretionary to Zone 3.
      - Integer mapping (ConvertTo-ZoneOptionValue, internal): Zone1 -> 100000001.
      - Naming classifier (scripts/shared/Get-ZoneClassification.ps1): an
        enterprise-named env resolves to the most-restrictive zone (Zone1).
      - Policy evaluation (Get-ExpectedFileUploadPolicy.ps1): file upload enabled
        in Zone 1 yields a Critical Zone1_* violation.
      - Severity is written as a free String label (no option-set integer
        conversion remains in the module).

.NOTES
    Run with:
        Invoke-Pester -Path .\ZoneReconciliation.Tests.ps1 -Output Detailed
#>

param()

BeforeAll {
    $script:SolutionRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:RepoRoot         = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:BaselinePath     = Join-Path $script:SolutionRoot 'templates' 'fileupload-baseline.json'
    $script:PolicyScript     = Join-Path $script:SolutionRoot 'scripts' 'private' 'Get-ExpectedFileUploadPolicy.ps1'
    $script:SharedClassifier = Join-Path $script:RepoRoot 'scripts' 'shared' 'Get-ZoneClassification.ps1'
    $script:ModulePath       = Join-Path $script:SolutionRoot 'scripts' 'private' 'FUSClient.psm1'

    $script:Baseline = Get-Content $script:BaselinePath -Raw | ConvertFrom-Json
    Import-Module $script:ModulePath -Force

    # ConvertTo-ZoneOptionValue is module-internal and self-contained. Extract its
    # source via the AST and dot-source it into the test scope so the integer
    # mapping can be asserted directly. (Invoking it in the module's session state
    # via & $mod {...} / InModuleScope trips a Pester scriptblock-instrumentation
    # quirk that surfaces as a spurious "'$-' is not recognized".)
    $moduleAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:ModulePath, [ref]$null, [ref]$null)
    $fnAst = $moduleAst.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $n.Name -eq 'ConvertTo-ZoneOptionValue' }, $true) | Select-Object -First 1
    . ([scriptblock]::Create($fnAst.Extent.Text))
    $script:ZoneInt_Zone1        = ConvertTo-ZoneOptionValue -Zone 'Zone1'
    $script:ZoneInt_Zone1_Spaced = ConvertTo-ZoneOptionValue -Zone 'Zone 1'
    $script:ZoneInt_Zone3        = ConvertTo-ZoneOptionValue -Zone 'Zone3'

    # Canonical contract under test (coordinator decision Option A).
    $script:MostRestrictiveInt  = 100000001
    $script:LeastRestrictiveInt = 100000003
}

AfterAll {
    Remove-Module FUSClient -Force -ErrorAction SilentlyContinue
}

Describe 'FUS canonical zone reconciliation (Option A)' {

    Context 'Policy table - strictest policy attaches to Zone 1' {
        It 'Zone 1 is the most-restrictive tier (file upload disabled, Highest moderation)' {
            $z1 = $script:Baseline.zoneRequirements.'Zone 1'
            $z1.fileUploadAllowed        | Should -BeFalse
            $z1.minimumModerationLevel   | Should -Be 'Highest'
        }

        It 'Zone 3 is the least-restrictive tier (file upload allowed at maker discretion)' {
            $z3 = $script:Baseline.zoneRequirements.'Zone 3'
            $z3.fileUploadAllowed        | Should -BeTrue
            $z3.requiresApproval         | Should -BeFalse
        }
    }

    Context 'Integer mapping - most-restrictive zone maps to Zone 1 and 100000001' {
        It 'maps Zone1 (unspaced) to 100000001' {
            $script:ZoneInt_Zone1 | Should -Be $script:MostRestrictiveInt
        }

        It 'maps Zone 1 (spaced) to 100000001' {
            $script:ZoneInt_Zone1_Spaced | Should -Be $script:MostRestrictiveInt
        }

        It 'maps Zone3 (least-restrictive) to 100000003' {
            $script:ZoneInt_Zone3 | Should -Be $script:LeastRestrictiveInt
        }
    }

    Context 'Naming classifier - enterprise resolves to the most-restrictive zone' {
        It 'classifies an enterprise-named environment as Zone1' {
            $zone = & $script:SharedClassifier -EnvironmentId 'env-ent' -EnvironmentDisplayName 'Contoso-Enterprise-Trading'
            $zone | Should -Be 'Zone1'
        }

        It 'classifies a personal/sandbox-named environment as Zone3' {
            $zone = & $script:SharedClassifier -EnvironmentId 'env-per' -EnvironmentDisplayName 'Jane-Personal-Sandbox'
            $zone | Should -Be 'Zone3'
        }
    }

    Context 'Policy evaluation - strictest zone yields a Critical Zone1_ violation' {
        It 'flags file upload enabled in Zone 1 with insufficient moderation as Critical' {
            $result = & $script:PolicyScript -Zone 'Zone1' -FileUploadEnabled $true -ContentModerationLevel 'Low' -BaselinePath $script:BaselinePath
            $result.Severity      | Should -Be 'Critical'
            $result.ViolationType | Should -Be 'Zone1_FileUploadEnabled_InsufficientModeration'
            $result.IsCompliant   | Should -BeFalse
        }

        It 'treats file upload enabled in Zone 3 (Personal) as a Warning at most, never Critical' {
            $result = & $script:PolicyScript -Zone 'Zone3' -FileUploadEnabled $true -ContentModerationLevel 'Unknown' -BaselinePath $script:BaselinePath
            $result.Severity | Should -Not -Be 'Critical'
        }
    }

    Context 'Severity is a free String label (no option-set integer conversion)' {
        It 'no longer defines ConvertTo-SeverityOptionValue in the module' {
            (Get-Content $script:ModulePath -Raw) | Should -Not -Match 'function ConvertTo-SeverityOptionValue'
        }

        It 'returns a non-numeric severity label' {
            $result = & $script:PolicyScript -Zone 'Zone1' -FileUploadEnabled $true -ContentModerationLevel 'Low' -BaselinePath $script:BaselinePath
            $result.Severity | Should -BeOfType ([string])
            $result.Severity | Should -Not -Match '^\d+$'
        }
    }
}
