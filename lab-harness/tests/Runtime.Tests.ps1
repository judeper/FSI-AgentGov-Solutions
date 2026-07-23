Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\runtime\LabHarness.Runtime.psm1'
Import-Module -Name $modulePath -Force

Describe 'Lab harness runtime foundation' {
    BeforeAll {
        $script:repoRoot = (Get-LabHarnessRepoRoot -StartPath (Join-Path -Path $PSScriptRoot -ChildPath '..\runtime'))
        $script:workspace = Join-Path -Path $PSScriptRoot -ChildPath '.tmp-runtime-tests'
        if (Test-Path -LiteralPath $script:workspace) {
            Remove-Item -LiteralPath $script:workspace -Recurse -Force
        }
        New-Item -Path $script:workspace -ItemType Directory | Out-Null
        $script:evidenceRoot = Join-Path -Path $script:workspace -ChildPath 'evidence'
        New-Item -Path $script:evidenceRoot -ItemType Directory | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:workspace) {
            Remove-Item -LiteralPath $script:workspace -Recurse -Force
        }
    }

    It 'rejects path traversal outside allowed roots' {
        { Resolve-LabConstrainedPath -Path '..\..\Windows\System32' -BasePath $script:repoRoot -AllowedRoots @($script:repoRoot, $script:evidenceRoot) } | Should -Throw
    }

    It 'enforces typed adapter allow-list during plan validation' {
        $planPath = Join-Path -Path $script:workspace -ChildPath 'invalid.plan.json'
        $ownershipPath = Join-Path -Path $script:workspace -ChildPath 'ownership.json'
        @'
{
  "schemaVersion": "1.0.0",
  "solution": "audit-compliance-manager",
  "resourceOwner": "Power Platform Admin",
  "cleanupActions": [
    {
      "id": "cleanup",
      "resourceType": "filesystem",
      "location": "lab-harness/evidence/redacted",
      "cleanupAdapter": "manual-review-then-delete"
    }
  ],
  "rollbackActions": [
    {
      "id": "rollback",
      "description": "Rollback action."
    }
  ]
}
'@ | Set-Content -LiteralPath $ownershipPath -Encoding utf8NoBOM

        @"
{
  "schemaVersion": "1.0.0",
  "solution": "audit-compliance-manager",
  "ownershipManifestPath": "$([System.IO.Path]::GetRelativePath($script:repoRoot, $ownershipPath).Replace('\','/'))",
  "steps": [
    {
      "id": "invalid",
      "channel": "runtime",
      "adapter": "runtime.shell.command",
      "testPaths": [
        "audit-compliance-manager/scripts/Validators.Tests.ps1"
      ]
    }
  ]
}
"@ | Set-Content -LiteralPath $planPath -Encoding utf8NoBOM

        { Test-LabValidationPlan -Solution 'audit-compliance-manager' -PlanPath $planPath -RepoRoot $script:repoRoot -EvidenceRoot $script:evidenceRoot } | Should -Throw
    }

    It 'returns plan-only result without executing steps' {
        $planPath = Join-Path -Path $script:repoRoot -ChildPath 'lab-harness\templates\audit-compliance-manager.plan.json'
        $result = Invoke-LabValidation -Solution 'audit-compliance-manager' -PlanPath $planPath -PlanOnly -EvidenceRoot $script:evidenceRoot

        $result.ExitCode | Should -Be 2
        $result.Result | Should -Be 'PlanValidatedNotExecuted'
        $result.StepResults.Count | Should -BeGreaterThan 0
        foreach ($step in $result.StepResults) {
            $step.status | Should -Be 'not-run-planonly'
        }

        $summary = Get-Content -LiteralPath $result.SummaryPath -Raw | ConvertFrom-Json -AsHashtable
        $summary.result | Should -Be 'PlanValidatedNotExecuted'
        $summary.executionMode | Should -Be 'PlanOnly'
    }

    It 'validates the copilot-agent-inventory templates PlanOnly against schemas and path confinement' {
        $planPath = Join-Path -Path $script:repoRoot -ChildPath 'lab-harness\templates\copilot-agent-inventory.plan.json'
        $result = Invoke-LabValidation -Solution 'copilot-agent-inventory' -PlanPath $planPath -PlanOnly -EvidenceRoot $script:evidenceRoot

        $result.ExitCode | Should -Be 2
        $result.Result | Should -Be 'PlanValidatedNotExecuted'
        $result.StepResults.Count | Should -Be 2
        foreach ($step in $result.StepResults) {
            $step.status | Should -Be 'not-run-planonly'
        }

        # Adapters used must all be in the existing allow-list (no new adapter).
        $catalog = Get-LabValidationAdapterCatalog
        foreach ($step in $result.StepResults) {
            $catalog.ContainsKey($step.adapter) | Should -BeTrue
        }
    }
}
