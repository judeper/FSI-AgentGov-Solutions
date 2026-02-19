@{
    # Script module or binary module file associated with this manifest
    RootModule = 'private/AAMClient.psm1'
    
    # Version number of this module
    ModuleVersion     = '1.0.0'
    
    # Supported PSEditions
    CompatiblePSEditions = @('Core')
    
    # ID used to uniquely identify this module
    GUID              = '8f3a2b1c-4d5e-6f7a-8b9c-0d1e2f3a4b5c'
    
    # Author of this module
    Author            = 'FSI Agent Governance Framework'
    
    # Company or vendor of this module
    CompanyName       = 'Microsoft'
    
    # Copyright statement for this module
    Copyright         = '(c) 2026 FSI Agent Governance Framework. MIT License.'
    
    # Description of the functionality provided by this module
    Description       = 'Agent Access Governance Monitor for Power Platform environments. Validates agent sharing and authoring settings against FSI governance zone requirements. Part of the FSI Agent Governance Framework.'
    
    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.1'
    
    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @(
        @{
            ModuleName    = 'Microsoft.PowerApps.Administration.PowerShell'
            ModuleVersion = '2.0.180'
        }
    )
    
    # Script files (.ps1) that are run in the caller's environment prior to importing this module
    # ScriptsToProcess = @()
    
    # Functions to export from this module
    FunctionsToExport = @(
        'Connect-AAMDataverse',
        'Get-AAMConnection',
        'Get-ValidToken',
        'Invoke-DataverseRequest',
        'Get-AAMEnvironmentVariable',
        'Get-AAMActiveBaseline',
        'Write-AAMValidationHistory',
        'Write-AAMViolation',
        'Save-AAMBaseline',
        'Get-AAMLastValidation'
    )
    
    # Cmdlets to export from this module
    CmdletsToExport   = @()
    
    # Variables to export from this module
    VariablesToExport = @()
    
    # Aliases to export from this module
    AliasesToExport   = @()
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData       = @{
        PSData = @{
            # Tags applied to this module for discoverability in online galleries
            Tags         = @(
                'PowerPlatform',
                'Governance',
                'Compliance',
                'FSI',
                'AgentAccess',
                'CopilotStudio',
                'Security'
            )
            
            # A URL to the license for this module
            LicenseUri   = 'https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/LICENSE'
            
            # A URL to the main website for this project
            ProjectUri   = 'https://github.com/judeper/FSI-AgentGov-Solutions'
            
            # A URL to an icon representing this module
            # IconUri = ''
            
            # ReleaseNotes of this module
            ReleaseNotes = @'
## 1.0.0 - 2026-02-19

### Added — Phase 4: Evidence Export & Framework Integration
- Export-AgentAccessEvidence.ps1 — Zone-based evidence export with SHA-256 hashing
- Get-AAMValidationResults.ps1 (private) — Dataverse query helper with OData pagination
- Test-EvidenceIntegrity.ps1 — SHA-256 hash verification utility
- SCHEMA.md, EVIDENCE_EXPORT.md, TROUBLESHOOTING.md documentation
- Framework integration: Control 3.8 tip admonition, solutions-index.md catalog entry

## 0.3.0 - 2026-02-17

### Added
- Start-AccessValidationRunbook.ps1 — Azure Automation runbook wrapper
- Invoke-AccessBaselineCapture.ps1 — Operator-initiated baseline capture
- adaptive-card-access-alert.json — Teams adaptive card template
- access-validation-flow.json — Power Automate cloud flow for daily validation
- FLOW_SETUP.md — Flow deployment and configuration guide
- Save-AAMBaseline, Get-AAMLastValidation, Get-ValidToken functions in AAMClient.psm1

## 0.2.0 - 2026-02-09

### Added
- Dataverse integration: aam_client.py, schema deployment, environment variables, connection references
- deploy.py orchestrator with full/selective/dry-run support
- -DataverseToken, -PersistResults parameters for Test-AgentAccessCompliance.ps1
- Validation result and violation persistence to Dataverse

## 0.1.0 - 2026-02-09

### Added
- Initial solution scaffold
- Get-EnvironmentAccessSettings, Compare-ZoneCompliance, Test-AgentAccessCompliance
- Zone classification, severity classification, regulatory context, grace period filtering
'@
            
            # Prerelease string of this module
            # Prerelease = ''
            
            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false
            
            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        }
    }
    
    # HelpInfo URI of this module
    # HelpInfoURI = ''
}
