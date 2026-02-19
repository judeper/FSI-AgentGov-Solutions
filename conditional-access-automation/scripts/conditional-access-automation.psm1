<#
.SYNOPSIS
    Root module for Conditional Access Automation.

.DESCRIPTION
    Dot-sources all public scripts and private helpers to make functions
    available when the module is imported via Import-Module.
#>

# Import private helpers
$privatePath = Join-Path $PSScriptRoot 'private'
Get-ChildItem -Path $privatePath -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

# Public scripts (Deploy-CAPolicies.ps1, Test-PolicyCompliance.ps1, etc.) are
# standalone scripts with top-level param() blocks and imperative execution code.
# They must be invoked directly (e.g., .\scripts\Deploy-CAPolicies.ps1), not
# dot-sourced, because dot-sourcing would evaluate their mandatory parameters
# and execute their body at import time.
