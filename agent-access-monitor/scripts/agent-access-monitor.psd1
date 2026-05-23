@{
    # Script module or binary module file associated with this manifest
    RootModule = 'private\AAMClient.psm1'
    
    # Version number of this module
    ModuleVersion     = '1.1.2'
    
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
    PowerShellVersion = '7.0'
    
    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @(
        @{
            ModuleName    = 'Microsoft.PowerApps.Administration.PowerShell'
            ModuleVersion = '2.0.180'
        }
    )
    
    # Script files (.ps1) that are run in the caller's environment prior to importing this module
    # ScriptsToProcess = @()
    
    # Nested modules bundled with this module
    # NOTE: The .ps1 files under scripts/ (Test-AgentAccessCompliance, Get-EnvironmentAccessSettings,
    # Compare-ZoneCompliance, etc.) are stand-alone runnable scripts using `param(...)` blocks, not
    # function definitions. They cannot be exported as commands via FunctionsToExport. Run them
    # directly (e.g., `.\Test-AgentAccessCompliance.ps1`). The module exports the AAMClient helpers
    # listed below for re-use by other modules.
    NestedModules     = @()

    # Functions to export from this module — these are the helpers defined in private/AAMClient.psm1
    FunctionsToExport = @(
        'Connect-AAMDataverse',
        'Get-AAMConnection',
        'Get-ValidToken',
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
## 1.1.2 - 2026-05-22

### Fixed
- Bumped `AAMClient.psm1` module header version to match the solution version.
- `aam_client.py` now lazy-imports `azure.identity` and `azure.core.exceptions` so consumers using only `--access-token` or legacy client-secret auth do not require the Azure Identity packages.
- `aam_client.py` `get_global_optionset` now lowercases the option-set name for the existence probe, matching the shared client and preventing a 400 `SchemaNameisNotUnique` re-create on case-mismatched lookups.

## 1.1.1 - 2026-05-13

### Changed
- Added managed identity and workload identity support for Python Dataverse deployment scripts.
- Normalized broad-sharing aliases to the Managed Environment noLimit value during zone evaluation.
- Fixed runbook drift detection token propagation for ELM zone lookup.

## 1.0.0 - 2026-02-19

### Added — Phase 4: Evidence Export & Framework Integration
- Export-AgentAccessEvidence.ps1 — Zone-based filtering, date range, SHA-256 hashes
- Get-AAMValidationResults.ps1 — Dataverse query helper with OData pagination
- Test-EvidenceIntegrity.ps1 — SHA-256 hash verification utility
- dataverse-schema.md, evidence-export.md, troubleshooting.md documentation
- Framework integration: Control 3.8 tip, solutions-index.md catalog entry

### Known Limitations
- M365 Admin Center agent settings not queryable via API (portal-only)
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
