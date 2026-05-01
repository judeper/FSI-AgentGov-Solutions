#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

<#
.SYNOPSIS
    Pester 5 orchestration tests for Invoke-MessageCenterSync.ps1.

.DESCRIPTION
    The C1 branching is unit-tested in Upsert.Tests.ps1 (against the extracted
    Invoke-McmDvUpsertMessage function). This file covers the remaining sync
    script responsibilities that are best validated by static-content checks
    against the script source: refactor wiring, body-truncation constant,
    category/severity defaults, and that admin-owned columns never appear in
    the $record literal.
#>

BeforeAll {
    $script:syncScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'governance' 'Invoke-MessageCenterSync.ps1')).Path
    $script:syncContent = Get-Content -LiteralPath $script:syncScript -Raw
}

Describe 'Invoke-MessageCenterSync.ps1 - refactor wiring' {
    It 'dot-sources _Common.ps1' {
        $script:syncContent | Should -Match '\.\s+\$PSScriptRoot.*_Common\.ps1|\.\s+(?:["'']|Join-Path)[^\n]*_Common\.ps1'
    }
    It 'invokes Invoke-McmDvUpsertMessage (C1 logic was extracted)' {
        $script:syncContent | Should -Match 'Invoke-McmDvUpsertMessage'
    }
    It 'no longer constructs the create payload inline (logic moved to helper)' {
        $script:syncContent | Should -Not -Match "createPayload\['fsi_assessmentstatus'\]"
    }
    It 'still parses cleanly' {
        $tk = $null; $pe = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:syncScript, [ref]$tk, [ref]$pe) | Out-Null
        $pe.Count | Should -Be 0
    }
}

Describe 'Invoke-MessageCenterSync.ps1 - $record literal hygiene' {

    It 'the $record hashtable does not assign any admin-owned column' {
        # Locate the $record = @{ ... } block and verify no admin-owned
        # column key appears inside it.
        $admin = @(
            'fsi_assessmentstatus'
            'fsi_assessment'
            'fsi_assessedby'
            'fsi_assesseddate'
            'fsi_actionstaken'
            'fsi_impactsagents'
            'fsi_notifiedon'
        )

        $blockMatch = [regex]::Match($script:syncContent, '(?ms)\$record\s*=\s*@\{(.+?)^\s*\}')
        $blockMatch.Success | Should -BeTrue -Because 'sync script must define a $record hashtable'

        $block = $blockMatch.Groups[1].Value
        foreach ($col in $admin) {
            $block | Should -Not -Match "\b$col\s*=" -Because "the per-message `$record literal must not include admin-owned column $col (it would be sent on the update path and clobber assessments)"
        }
    }
}

Describe 'Invoke-MessageCenterSync.ps1 - constants and defaults' {
    It 'body truncation upper bound is 99990' {
        $script:syncContent | Should -Match '\$bodyMaxLength\s*=\s*99990'
    }
    It 'category default falls back to Admin (100000001) when category not in map' {
        $script:syncContent | Should -Match 'categoryValue\s*=\s*100000001'
    }
    It 'severity default falls back to Normal (100000001) when severity not in map' {
        $script:syncContent | Should -Match 'severityValue\s*=\s*100000001'
    }
    It 'truncation marker preserves original length' {
        $script:syncContent | Should -Match 'truncated.+original length'
    }
}
