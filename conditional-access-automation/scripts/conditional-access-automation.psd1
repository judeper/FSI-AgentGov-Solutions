@{
    # Script module or binary module file associated with this manifest
    RootModule = 'conditional-access-automation.psm1'
    
    # Version number of this module
    ModuleVersion     = '1.2.0'
    
    # Supported PSEditions
    CompatiblePSEditions = @('Core')
    
    # ID used to uniquely identify this module
    GUID              = 'b7f3e2a9-4c1d-48e5-9a6b-d8f2c7e50134'
    
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
    
    # Nested modules bundled with this module
    NestedModules     = @('private\CAAClient.psm1')
    
    # Functions to export from this module
    # NOTE: Top-level scripts (Deploy-CAPolicies.ps1, Test-PolicyCompliance.ps1, etc.)
    # are standalone entry points — run them directly, not via Import-Module.
    # The exported functions below are internal helpers from private/*.ps1 and CAAClient.psm1.
    FunctionsToExport = @(
        'Connect-CAAGraphSession',
        'Test-CAAGraphConnection',
        'Get-CAAPolicyBaseline',
        'Compare-CAAPolicyBaseline',
        'Get-CAAZoneClassification',
        'Get-CAAValidationResults',
        'Test-CAAConfigPath',
        'Test-CAATemplateSet',
        'Test-CAABreakGlassAccounts',
        'Connect-CAADataverse',
        'Get-CAAConnection',
        'Get-CAAEnvironmentVariable',
        'Get-CAAActiveBaseline',
        'Write-CAAValidationHistory',
        'Write-CAAViolation',
        'Save-CAABaseline',
        'Get-CAALastValidation'
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

        # Connection references used by Power Automate flows in this solution:
        #   - fsi_cr_dataverse_*   (Dataverse)
        #   - fsi_cr_office365_*   (Office 365 / email alerts)
        #   - fsi_cr_teams_*       (Teams adaptive card alerts)
        #   - Microsoft Graph connector: NOT YET ADDED — flows use HTTP actions with MSI auth.
        #     Planned for Phase 2 when Graph connector support is available.
    }
    
    # HelpInfo URI of this module
    # HelpInfoURI = ''
}
