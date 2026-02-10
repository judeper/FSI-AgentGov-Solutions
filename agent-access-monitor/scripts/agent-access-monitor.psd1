@{
    # Script module or binary module file associated with this manifest
    # RootModule = ''
    
    # Version number of this module
    ModuleVersion     = '0.1.0'
    
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
    
    # Functions to export from this module
    FunctionsToExport = @(
        'Test-AgentAccessCompliance',
        'Get-EnvironmentAccessSettings',
        'Compare-ZoneCompliance'
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
## 0.1.0 - 2026-02-09

### Added
- Get-EnvironmentAccessSettings: Query Power Platform environments for agent access settings
- Compare-ZoneCompliance: Compare settings against zone-specific baselines
- Test-AgentAccessCompliance: Orchestrator with dry-run mode and multiple output formats
- Zone classification via ELM Dataverse lookup with naming convention fallback
- Severity classification (Critical/High/Warning/Info) per zone and violation type
- Regulatory context (FINRA 4511, SOX 404) in violation output
- Grace period filtering for newly provisioned environments
- Environment group support for group-level rule visibility

### Known Limitations
- Dataverse persistence not yet implemented (Phase 2)
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
