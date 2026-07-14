Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Lab harness gitignore protections' {
    BeforeAll {
        $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..\..'))
    }

    It 'ignores auth and runtime artifact paths' {
        $ignoredPaths = @(
            'lab-harness/playwright/.auth/storageState.json',
            'lab-harness/playwright/playwright-report/index.html',
            'lab-harness/playwright/test-results/result.json',
            'lab-harness/playwright/downloads/file.txt',
            'lab-harness/evidence/raw/artifact.json'
        )

        foreach ($pathValue in $ignoredPaths) {
            & git -C $script:repoRoot check-ignore -q $pathValue
            $LASTEXITCODE | Should -Be 0
        }
    }

    It 'does not ignore committed templates and schemas' {
        $trackedPaths = @(
            'lab-harness/templates/audit-compliance-manager.plan.json',
            'lab-harness/schema/solution-validation-plan.schema.json'
        )

        foreach ($pathValue in $trackedPaths) {
            & git -C $script:repoRoot check-ignore -q $pathValue
            $LASTEXITCODE | Should -Be 1
        }
    }
}
