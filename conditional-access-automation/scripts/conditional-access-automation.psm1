<#
.SYNOPSIS
    Root module for conditional-access-automation — loads private helpers.

.DESCRIPTION
    Imports internal helper functions from the private/ directory so that
    top-level scripts can dot-source or Import-Module this manifest.

    NOTE: The top-level scripts (Deploy-CAPolicies.ps1, Test-PolicyCompliance.ps1,
    Register-ServicePrincipal.ps1, Watch-PolicyDrift.ps1, Export-PolicyBaseline.ps1,
    Export-CAAComplianceEvidence.ps1, Test-EvidenceIntegrity.ps1) are standalone
    entry points with their own param() blocks and #Requires directives.
    Run them directly (e.g., .\scripts\Test-PolicyCompliance.ps1 -TenantId ...),
    do NOT import them as module functions.
#>


# Dot-source private helper functions (.ps1 files that define reusable functions)
$privatePath = Join-Path $PSScriptRoot 'private'
foreach ($helper in Get-ChildItem -Path $privatePath -Filter '*.ps1' -ErrorAction SilentlyContinue) {
    . $helper.FullName
}
