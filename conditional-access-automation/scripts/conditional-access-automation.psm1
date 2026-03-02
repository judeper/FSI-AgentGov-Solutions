# Root module for conditional-access-automation
# Dot-source each exported function script
$exportedScripts = @(
    'Deploy-CAPolicies.ps1',
    'Test-PolicyCompliance.ps1',
    'Register-ServicePrincipal.ps1',
    'Watch-PolicyDrift.ps1',
    'Export-PolicyBaseline.ps1',
    'Export-CAAComplianceEvidence.ps1',
    'Test-EvidenceIntegrity.ps1'
)

foreach ($script in $exportedScripts) {
    $scriptPath = Join-Path $PSScriptRoot $script
    if (Test-Path $scriptPath) {
        . $scriptPath
    }
}
