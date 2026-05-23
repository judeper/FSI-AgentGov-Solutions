#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

<#
.SYNOPSIS
    Static guard tests for Export-MessageCenterEvidence.ps1 OData query shape and
    output record schema hygiene.

.DESCRIPTION
    Prevents regression of the v2.4.0 bug where fsi_assessedby (a String column,
    StringAttributeMetadata with MaxLength 200) was queried as a Lookup via
    _fsi_assessedby_value, returning 400 Bad Request. The same bug introduced a
    dead annotation-reading block (looking for the @OData.Community.Display.V1.FormattedValue
    annotation, which only exists on Lookup columns) and a redundant assessedById
    output field. Both must stay removed.

    See .ralph-config.json for the column-type contract and history.
#>

BeforeAll {
    $script:scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'governance' 'Export-MessageCenterEvidence.ps1')).Path
    $script:content    = Get-Content -LiteralPath $script:scriptPath -Raw
}

Describe 'Export-MessageCenterEvidence.ps1 - OData query shape' {

    It '$selectFields uses fsi_assessedby (plain String column)' {
        $script:content | Should -Match '\$selectFields\s*=\s*"[^"]*\bfsi_assessedby\b'
    }

    It '$selectFields does NOT use _fsi_assessedby_value inside the literal (Lookup-only syntax)' {
        $blockMatch = [regex]::Match($script:content, '(?m)^\s*\$selectFields\s*=\s*"([^"]+)"')
        $blockMatch.Success | Should -BeTrue -Because 'script must define $selectFields as a single-line string literal'
        $blockMatch.Groups[1].Value | Should -Not -Match '_fsi_assessedby_value' `
            -Because '_fsi_assessedby_value OData syntax is Lookup-only; fsi_assessedby is a String column (MaxLength 200) per create_mcm_dataverse_schema.py:230-237 and returns 400 Bad Request when queried as a Lookup'
    }
}

Describe 'Export-MessageCenterEvidence.ps1 - record schema hygiene' {

    It 'does not read the _fsi_assessedby_value FormattedValue annotation (dead code post-fix)' {
        # The @OData.Community.Display.V1.FormattedValue annotation only appears on
        # Lookup columns. For a String column it is always absent. Pre-fix code had
        # an annotation-reading block at Export:262-268 that silently returned $null.
        # Re-introducing this block would be a regression — the v2.4.0 mistake.
        $script:content | Should -Not -Match '_fsi_assessedby_value@OData\.Community\.Display\.V1\.FormattedValue'
    }

    It 'does not expose assessedById output property (Lookup-only alias)' {
        # Pre-fix, the output PSCustomObject had two fields:
        #   assessedBy   = $assessedByDisplay        (always $null on a String column)
        #   assessedById = $_._fsi_assessedby_value  (always $null on a String column)
        # Post-fix, both collapse to one field: assessedBy = $_.fsi_assessedby.
        # Re-introducing assessedById would be a regression.
        $script:content | Should -Not -Match '\bassessedById\s*='
    }

    It 'reads assessedBy directly as $_.fsi_assessedby in the output object' {
        $script:content | Should -Match 'assessedBy\s*=\s*\$_\.fsi_assessedby\b'
    }

    It 'still parses cleanly' {
        $tk = $null; $pe = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:scriptPath, [ref]$tk, [ref]$pe) | Out-Null
        $pe.Count | Should -Be 0
    }
}
