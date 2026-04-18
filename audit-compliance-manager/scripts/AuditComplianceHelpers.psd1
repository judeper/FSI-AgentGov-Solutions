@{
    # Module manifest for AuditComplianceHelpers
    # Audit Logging Compliance Automation (ALCA) - Shared helper module

    RootModule        = 'AuditComplianceHelpers.psm1'
    ModuleVersion     = '1.0.2'
    GUID              = 'b4e7c3a1-8f2d-4e5b-9c6a-1d3f5e7a9b2c'
    Author            = 'FSI-AgentGov'
    CompanyName       = 'FSI Agent Governance Framework'
    Copyright         = '(c) FSI-AgentGov. All rights reserved.'
    Description       = 'Shared helper functions for Audit Logging Compliance Automation (ALCA) runbooks. Provides retry logic, Managed Identity authentication, Dataverse Web API operations, compliance record upsert, and email notification capabilities for Azure Automation.'

    # Minimum PowerShell version
    PowerShellVersion = '7.2'

    # Functions to export
    FunctionsToExport = @(
        'Invoke-WithRetry',
        'Get-ManagedIdentityToken',
        'Get-DataverseToken',
        'Invoke-DataverseRequest',
        'Write-DataverseComplianceRecord',
        'Send-ComplianceNotification'
    )

    # Cmdlets, variables, and aliases — restrict exports
    CmdletsToExport   = @()
    VariablesToExport  = @(
        'ComplianceStatusMap',
        'ComplianceStatusReverseMap'
    )
    AliasesToExport    = @()

    # Private data
    PrivateData = @{
        PSData = @{
            Tags         = @('Audit', 'Compliance', 'PowerPlatform', 'Dataverse', 'ManagedIdentity', 'FSI')
            ProjectUri   = 'https://github.com/judeper/FSI-AgentGov-Solutions'
            LicenseUri   = 'https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/LICENSE'
            ReleaseNotes = 'v1.0.2 — token-cache fix and other defects; original v1.0.0 release shipped 6 helper functions for ALCA detection and remediation runbooks. Initial release — 6 helper functions for ALCA detection and remediation runbooks.'
        }
    }
}
