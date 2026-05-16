#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

<#
.SYNOPSIS
    Static guard tests for Get-MessageCenterAssessmentStatus.ps1 OData query shape.

.DESCRIPTION
    Prevents regression of the v2.4.0 bug where fsi_assessedby (a String column,
    StringAttributeMetadata with MaxLength 200) was queried as a Lookup via
    _fsi_assessedby_value, which returns 400 Bad Request from Dataverse.

    These tests assert the static content of the script — the $selectFields
    literal — matches the column-type contract. They complement the behavioural
    tests by catching call-site regressions that unit tests alone cannot.

    See .ralph-config.json for the column-type contract and history.
#>

BeforeAll {
    $script:scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'governance' 'Get-MessageCenterAssessmentStatus.ps1')).Path
    $script:content    = Get-Content -LiteralPath $script:scriptPath -Raw
}

Describe 'Get-MessageCenterAssessmentStatus.ps1 - OData query shape' {

    It '$selectFields uses fsi_assessedby (plain String column)' {
        $script:content | Should -Match '\$selectFields\s*=\s*"[^"]*\bfsi_assessedby\b'
    }

    It '$selectFields does NOT use _fsi_assessedby_value inside the literal (Lookup-only syntax)' {
        # The literal _fsi_assessedby_value must not appear inside the $selectFields
        # string. We allow it in adjacent comments as an anti-pattern warning.
        $blockMatch = [regex]::Match($script:content, '(?m)^\s*\$selectFields\s*=\s*"([^"]+)"')
        $blockMatch.Success | Should -BeTrue -Because 'script must define $selectFields as a single-line string literal'
        $blockMatch.Groups[1].Value | Should -Not -Match '_fsi_assessedby_value' `
            -Because '_fsi_assessedby_value OData syntax is Lookup-only; fsi_assessedby is a String column (MaxLength 200) per create_mcm_dataverse_schema.py:230-237 and returns 400 Bad Request when queried as a Lookup'
    }

    It 'still parses cleanly' {
        $tk = $null; $pe = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:scriptPath, [ref]$tk, [ref]$pe) | Out-Null
        $pe.Count | Should -Be 0
    }
}
