Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\evidence\LabHarness.Evidence.psm1'
Import-Module -Name $modulePath -Force

Describe 'Lab evidence tooling' {
    BeforeAll {
        $workspace = Join-Path -Path $PSScriptRoot -ChildPath '.tmp-evidence-tests'
        if (Test-Path -LiteralPath $workspace) {
            Remove-Item -LiteralPath $workspace -Recurse -Force
        }
        New-Item -Path $workspace -ItemType Directory | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $workspace) {
            Remove-Item -LiteralPath $workspace -Recurse -Force
        }
    }

    It 'redacts sensitive values from evidence content' {
        $inputPath = Join-Path -Path $workspace -ChildPath 'sample.txt'
        $outputPath = Join-Path -Path $workspace -ChildPath 'sample.redacted.txt'
        @'
User: alex.smith@contoso.com
Tenant: contoso.onmicrosoft.com
Environment: https://contoso.crm.dynamics.com
RecordId: 123e4567-e89b-12d3-a456-426614174000
Webhook: https://workflow.contoso.com/webhook/endpoint?sig=abc123
SharePoint: https://contoso.sharepoint.com/sites/AgentGov/Shared%20Documents
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signaturevalue
Storage: AccountKey=topsecretvalue;EndpointSuffix=core.windows.net
EvidenceHash: bb90e859a61d8e65f77b3092bc74e29d38581a785c2847980c7fe9c68dbe84d3
'@ | Set-Content -LiteralPath $inputPath -Encoding utf8NoBOM

        $result = Invoke-LabEvidenceRedaction -InputPath $inputPath -OutputPath $outputPath
        $content = Get-Content -LiteralPath $outputPath -Raw

        $content | Should -Not -Match 'alex\.smith@contoso\.com'
        $content | Should -Not -Match 'contoso\.onmicrosoft\.com'
        $content | Should -Not -Match '123e4567-e89b-12d3-a456-426614174000'
        $content | Should -Not -Match 'contoso\.sharepoint\.com'
        $content | Should -Not -Match 'eyJhbGci'
        $content | Should -Not -Match 'topsecretvalue'
        $content | Should -Match '<redacted:upn>'
        $content | Should -Match '<redacted:webhook-url>'
        $content | Should -Match '<redacted:sharepoint-url>'
        $content | Should -Match 'Authorization: Bearer <redacted:token>'
        $content | Should -Match 'AccountKey=<redacted:token>'
        $content | Should -Match 'bb90e859a61d8e65f77b3092bc74e29d38581a785c2847980c7fe9c68dbe84d3'
        $result.Replacements.upn | Should -BeGreaterThan 0
    }

    It 'generates deterministic sha256 manifest entries' {
        $artifactRoot = Join-Path -Path $workspace -ChildPath 'artifacts'
        $manifestPath = Join-Path -Path $workspace -ChildPath 'manifest.json'
        New-Item -Path $artifactRoot -ItemType Directory | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $artifactRoot -ChildPath 'a.txt') -Value 'alpha' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path -Path $artifactRoot -ChildPath 'b.txt') -Value 'beta' -Encoding utf8NoBOM

        $result = New-LabEvidenceManifest -ArtifactRoot $artifactRoot -ManifestPath $manifestPath
        $result.FileCount | Should -Be 2
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable

        $entryA = $manifest.files | Where-Object { $_.path -eq 'a.txt' } | Select-Object -First 1
        $entryB = $manifest.files | Where-Object { $_.path -eq 'b.txt' } | Select-Object -First 1

        $expectedA = (Get-FileHash -Path (Join-Path -Path $artifactRoot -ChildPath 'a.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
        $expectedB = (Get-FileHash -Path (Join-Path -Path $artifactRoot -ChildPath 'b.txt') -Algorithm SHA256).Hash.ToLowerInvariant()

        $entryA.sha256 | Should -Be $expectedA
        $entryB.sha256 | Should -Be $expectedB
    }
}
