#Requires -Version 7.2
#Requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "5.0.0" }

<#
.SYNOPSIS
    Pester 5 unit tests for Test-EligibilityPrecondition in
    Test-AgentEligibilityPrecondition.ps1.

.DESCRIPTION
    The script's top-level body resolves parameters and calls exit, so the file
    cannot be dot-sourced directly. This test extracts the pure
    Test-EligibilityPrecondition function via the PowerShell AST and loads only
    that function, then asserts the precondition contract: a precondition passes
    only when the agent uses a Microsoft Entra ID authentication mode (Integrated
    = 2 or Custom Azure Active Directory = 3) AND require-users-to-sign-in is
    enabled (authenticationtrigger Always = 1). No authentication (1), Generic
    OAuth2 (4), Unspecified (0), or an As-Needed trigger (0) all fail the
    precondition.

.NOTES
    Run with: Invoke-Pester -Path .\EligibilityPrecondition.Tests.ps1 -Output Detailed
#>

param()

BeforeAll {
    $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-AgentEligibilityPrecondition.ps1')).Path
    $parsedAst = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $functionAst = $parsedAst.FindAll(
        {
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Test-EligibilityPrecondition'
        },
        $true
    )
    if ($functionAst.Count -ne 1) {
        throw "Expected exactly one Test-EligibilityPrecondition definition, found $($functionAst.Count)."
    }
    # Load only the pure function, avoiding the script's exit-calling main body.
    . ([scriptblock]::Create($functionAst[0].Extent.Text))
}

Describe 'Test-EligibilityPrecondition' {
    It 'passes for Microsoft Entra ID mode <Mode> with require-sign-in Always' -ForEach @(
        @{ Mode = 2 }  # Integrated
        @{ Mode = 3 }  # Custom Azure Active Directory
    ) {
        $result = Test-EligibilityPrecondition -AuthModeValue $Mode -AuthTriggerValue 1
        $result.Pass | Should -BeTrue
    }

    It 'fails for non-Entra authentication mode <Mode> even with require-sign-in Always' -ForEach @(
        @{ Mode = 0 }  # Unspecified
        @{ Mode = 1 }  # None
        @{ Mode = 4 }  # Generic OAuth2
    ) {
        $result = Test-EligibilityPrecondition -AuthModeValue $Mode -AuthTriggerValue 1
        $result.Pass | Should -BeFalse
    }

    It 'fails when Entra ID auth is set but require-users-to-sign-in is As Needed' {
        $result = Test-EligibilityPrecondition -AuthModeValue 2 -AuthTriggerValue 0
        $result.Pass | Should -BeFalse
    }

    It 'returns a non-empty reason string for both the pass and fail paths' {
        (Test-EligibilityPrecondition -AuthModeValue 2 -AuthTriggerValue 1).Reason | Should -Not -BeNullOrEmpty
        (Test-EligibilityPrecondition -AuthModeValue 4 -AuthTriggerValue 1).Reason | Should -Not -BeNullOrEmpty
    }
}

Describe 'Test-AgentEligibilityPrecondition.ps1 end-to-end (exit-code contract)' {
    BeforeAll {
        $script:E2EScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-AgentEligibilityPrecondition.ps1')).Path
        # The script body calls exit, so it must run in a CHILD process or it would
        # terminate the Pester runner. Reuse the current PowerShell executable.
        $script:PwshExe = (Get-Process -Id $PID).Path
    }

    It 'exits 0 and reports Pass for an Entra ID mode with require-users-to-sign-in' {
        $out = & $script:PwshExe -NoProfile -NonInteractive -File $script:E2EScript -AuthenticationMode Integrated -RequireUsersToSignIn
        $exitCode = $LASTEXITCODE

        # The child renders the result object with ANSI color codes; strip them so
        # the Precondition line matches as plain text.
        $plain = ($out -join "`n") -replace '\x1b\[[0-9;]*m', ''
        $exitCode | Should -Be 0
        $plain | Should -Match 'Precondition\s*:\s*Pass'
    }

    It 'exits 1 and reports Fail for Generic OAuth2 (authenticated but not Microsoft Entra ID)' {
        # A non-zero native exit code must stay non-terminating so it does not abort
        # the runner under PS 7.4 PSNativeCommandUseErrorActionPreference.
        $PSNativeCommandUseErrorActionPreference = $false
        $out = & $script:PwshExe -NoProfile -NonInteractive -File $script:E2EScript -AuthenticationMode GenericOAuth2 -RequireUsersToSignIn 2>$null
        $exitCode = $LASTEXITCODE

        $plain = ($out -join "`n") -replace '\x1b\[[0-9;]*m', ''
        $exitCode | Should -Be 1
        $plain | Should -Match 'Precondition\s*:\s*Fail'
    }
}
