#
# PSScriptAnalyzer settings for FSI-AgentGov-Solutions
#
# Loaded by `Invoke-ScriptAnalyzer -Settings ./PSScriptAnalyzerSettings.psd1`
# in `.github/workflows/ci-powershell.yml` and during local development.
#
# Two rules are globally excluded. Both exclusions are deliberate and reviewed:
#
#   PSAvoidUsingWriteHost
#     The .ps1 scripts in this repo are operator-facing CLI tools (governance
#     scans, evidence exports, compliance runbooks). Their user-visible output
#     surface is the colored console banner, status lines, and progress
#     reporting that `Write-Host` produces. They are NOT library functions
#     whose output is consumed by other scripts via the pipeline. Per the
#     PowerShell team guidance (https://docs.microsoft.com/powershell/module/
#     microsoft.powershell.utility/write-host), `Write-Host` is the correct
#     choice for "the only thing the user is supposed to see" output. Replacing
#     these with `Write-Information -InformationAction Continue` would alter
#     observable script behavior (default `$InformationPreference = 'SilentlyContinue'`
#     means operators would see no output unless they explicitly opt in) without
#     improving correctness.
#
#   PSUseSingularNouns
#     Several existing public-surface script and function names use plural nouns
#     (e.g. `Get-AgentSkillRegistrations`, `Get-AAMValidationResults`,
#     `Get-DataverseHeaders`). These names are referenced by customer
#     deployment runbooks, scheduled task definitions, and downstream
#     integrations. Renaming them constitutes a breaking surface change that
#     would require coordinated `[BREAKING DEPLOY]` CHANGELOG entries across
#     many solutions for cosmetic gain only. Singular-noun convention is
#     enforced for net-new cmdlets via code review; not retroactively.
#
# See AGENTS.md "PowerShell Coding Patterns" for the formal policy. Any
# additional exclusion must justify itself with the same rigor.
#

@{
    # Run all built-in rules except those listed below.
    IncludeDefaultRules = $true

    # Gate at Warning + Error only. Information-severity findings (style
    # suggestions like trailing whitespace, missing [OutputType()], positional
    # parameter use) remain visible when developers invoke PSSA without
    # `-Severity` filters, but are NOT part of the CI-enforced "no tech debt"
    # bar. This matches the convention used by the PowerShell Standard Library
    # and most Microsoft-published modules.
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseSingularNouns'
    )
}
