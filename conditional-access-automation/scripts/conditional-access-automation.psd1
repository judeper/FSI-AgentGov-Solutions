@{
    # Script module or binary module file associated with this manifest
    RootModule = 'conditional-access-automation.psm1'
    
    # Version number of this module
    ModuleVersion     = '1.1.0'
    
    # Supported PSEditions
    CompatiblePSEditions = @('Core')
    
    # ID used to uniquely identify this module
    GUID              = 'a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d'
    
    # Author of this module
    Author            = 'FSI Agent Governance Framework'
    
    # Company or vendor of this module
    CompanyName       = 'Microsoft'
    
    # Copyright statement for this module
    Copyright         = '(c) 2026 FSI Agent Governance Framework. MIT License.'
    
    # Description of the functionality provided by this module
    Description       = 'FSI Agent Governance — Conditional Access Automation for Controls 1.11, 1.23, 1.18. Deploys and validates Conditional Access policies for Power Platform agent governance zones, detects policy drift, and supports break-glass account exclusion compliance.'
    
    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'
    
    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @(
        @{
            ModuleName    = 'Microsoft.Graph.Identity.SignIns'
            ModuleVersion = '2.0.0'
        },
        @{
            ModuleName    = 'Microsoft.Graph.Applications'
            ModuleVersion = '2.0.0'
        }
    )
    
    # Script files (.ps1) that are run in the caller's environment prior to importing this module
    # ScriptsToProcess = @()
    
    # Functions to export from this module
    # Public scripts are standalone .ps1 files with top-level param() blocks;
    # they are invoked directly, not as module-exported functions.
    # Private helper functions (e.g., Get-CAAPolicyBaseline, Compare-CAAPolicyBaseline)
    # are exported for use by the standalone scripts and advanced consumers.
    FunctionsToExport = @(
        'Get-CAAPolicyBaseline',
        'Compare-CAAPolicyBaseline',
        'Connect-CAAGraphSession',
        'Get-CAAZoneClassification',
        'Test-CAAConfigPath',
        'Get-CAAValidationResults'
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
                'ConditionalAccess',
                'Governance',
                'FSI',
                'MFA',
                'ZeroTrust',
                'PowerPlatform',
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
## 1.1.0 - 2026-02-10

### Added
- Export-CAAComplianceEvidence: SHA-256 integrity-hashed compliance evidence export
- Test-EvidenceIntegrity: Verify evidence file integrity via SHA-256 companion hash
- Dataverse OData query helper for validation histories, violations, and baselines
- Evidence schema with metadata, summary, zone breakdown, and record arrays

## 1.0.0 - 2026-02-10

### Added
- Deploy-CAPolicies: Deploy Conditional Access policies per governance zone
- Test-PolicyCompliance: Validate CA policy compliance against zone baselines
- Register-ServicePrincipal: Register service principal for automated CA management
- Zone classification via ELM Dataverse lookup with naming convention fallback
- Break-glass account exclusion validation
- Policy drift detection support
- Graph session management with scope validation

### Known Limitations
- Dataverse persistence not yet implemented (Phase 2)
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
