#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

<#
.SYNOPSIS
    Static guard tests for the message-center-monitor governance scripts.

.DESCRIPTION
    These tests prevent regressions where a future contributor:
      - Forgets to dot-source _Common.ps1 in a new governance script
      - Uses Invoke-RestMethod / Invoke-WebRequest directly outside of
        _Common.ps1 (bypassing retry/Retry-After/redaction)
      - Prints a secret with Write-Host directly
      - Adds an `az` CLI dependency (the lab automation standardised on
        Microsoft.Graph PowerShell + Az.KeyVault; see plan A5)

    These checks complement the behavioural tests by catching call-site
    regressions that unit tests alone cannot.
#>

BeforeAll {
    $script:governanceDir = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'governance')).Path
    $script:commonScript  = Join-Path $script:governanceDir '_Common.ps1'

    $script:governanceScripts = Get-ChildItem -LiteralPath $script:governanceDir -Filter '*.ps1' -File |
        Where-Object { $_.Name -ne '_Common.ps1' }
}

Describe 'Governance scripts dot-source _Common.ps1' {
    It 'every governance script that uses Invoke-McmRest dot-sources the helper' {
        # Test-EvidenceIntegrity.ps1 hashes files locally and makes no HTTP calls,
        # so it does not need _Common.ps1. Detect HTTP-using scripts dynamically by
        # presence of an Invoke-Mcm* call - this catches any new HTTP script added
        # in the future that forgets to dot-source the helper.
        foreach ($f in $script:governanceScripts) {
            $content = Get-Content -LiteralPath $f.FullName -Raw
            if ($content -notmatch '\bInvoke-Mcm(Rest|DvUpsertMessage)\b' -and
                $content -notmatch '\bGet-Mcm(AccessToken|DvHeaders)\b') {
                # Script makes no HTTP/auth calls - dot-source not required.
                continue
            }
            $content | Should -Match '\.\s+\$PSScriptRoot.*_Common\.ps1|\.\s+(?:["'']|Join-Path)[^\n]*_Common\.ps1' `
                -Because "$($f.Name) calls helpers from _Common.ps1 and must dot-source it"
        }
    }
}

Describe 'Direct REST cmdlets are confined to _Common.ps1' {
    It 'no governance script outside _Common.ps1 calls Invoke-RestMethod' {
        foreach ($f in $script:governanceScripts) {
            $content = Get-Content -LiteralPath $f.FullName -Raw
            # Strip comments before searching - a comment that mentions
            # "Invoke-RestMethod" is allowed (function comments may explain
            # what the helper wraps).
            $stripped = $content -replace '(?m)^\s*#.*$', '' -replace '<#[\s\S]*?#>', ''
            $stripped | Should -Not -Match '\bInvoke-RestMethod\b' `
                -Because "$($f.Name) must call Invoke-McmRest (the retry-aware wrapper), not Invoke-RestMethod directly"
            $stripped | Should -Not -Match '\bInvoke-WebRequest\b' `
                -Because "$($f.Name) must call Invoke-McmRest, not Invoke-WebRequest"
        }
    }
}

Describe 'Secret printing hygiene' {
    It 'no governance script prints a variable named *Secret* via Write-Host' {
        $files = @($script:governanceScripts) + (Get-Item $script:commonScript)
        foreach ($f in $files) {
            $content = Get-Content -LiteralPath $f.FullName -Raw
            # Match Write-Host on a single line containing $...Secret.
            $content | Should -Not -Match '(?i)Write-Host[^\r\n#]*\$\w*Secret\b' `
                -Because "$($f.Name) must not Write-Host a secret variable directly - use Write-McmRedacted"
            # ConvertFrom-SecureString -AsPlainText piped to Write-Host is a giveaway.
            $content | Should -Not -Match '(?i)ConvertFrom-SecureString[^\r\n]*-AsPlainText[^\r\n]*\|\s*Write-Host' `
                -Because "$($f.Name) must not pipe a converted SecureString to Write-Host"
        }
    }
}

Describe 'Tooling discipline' {
    It 'no governance script invokes the `az` CLI' {
        foreach ($f in $script:governanceScripts) {
            $content = Get-Content -LiteralPath $f.FullName -Raw
            $stripped = $content -replace '(?m)^\s*#.*$', '' -replace '<#[\s\S]*?#>', ''
            # Match `az ` followed by a known subcommand at start of line or
            # after whitespace. Avoids false positives like $azAccount.
            $stripped | Should -Not -Match '(?m)(^|[\s;`|&])az\s+(account|ad|keyvault|group|resource|login|logout|rest)\b' `
                -Because "$($f.Name) must use Microsoft.Graph PowerShell + Az.* modules (per plan A5), not the az CLI"
        }
    }
}
