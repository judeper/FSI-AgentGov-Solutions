@{
    RootModule        = 'IntegrationConfig.psm1'
    ModuleVersion     = '1.0.1'
    GUID              = 'f8e3a1b2-c4d5-6e7f-8a9b-0c1d2e3f4a5b'
    Author            = 'FSI Agent Governance Framework'
    Description       = 'Shared integration constants, mappings, and translation functions for cross-solution governance integration.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Connect-DataverseApi'
        'Get-SolutionControlMapping'
        'Get-SolutionTableConfig'
        'ConvertTo-DashboardStatus'
        'Get-CanonicalZoneValue'
        'Get-EvidenceTypeId'
        'Get-EvidenceExportScripts'
        'Get-SolutionDirectories'
        'Get-DashboardTableConfig'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('FSI', 'Governance', 'Integration', 'ComplianceDashboard')
            ProjectUri = 'https://github.com/judeper/FSI-AgentGov-Solutions'
        }
    }
}
