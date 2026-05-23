@{
    # Script module or binary module file associated with this manifest
    RootModule = 'conditional-access-automation.psm1'
    
    # Version number of this module
    ModuleVersion     = '2.0.2'
    
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
## 2.0.2 - Council review remediation

### Fixed
- compliance-monitoring.md: removed Teams incoming-webhook sample that contradicted the documented Teams-connector flow approach; replaced with a Teams-connector / environment-variable shape (council review MAJ-02).
- .ralph-config.json: refreshed stale domain facts about fsi_overallstatus and Get-ZoneClassification column names; both code paths have used the correct logical names since v2.0.0 (council review MAJ-03).
- templates/CA-RiskBased-Zone3-Block.json: standardised break-glass placeholders to <break-glass-1>/<break-glass-2> to match the other nine baseline templates and added the _metadata block for governance traceability (council review MIN-01, MIN-02).
- docs/policy-templates.md: removed empty signInRiskLevels/userRiskLevels arrays from the CA-CopilotStudio-Zone3 spec so the doc matches the deployed template (council review MIN-03).

### Changed
- scripts/requirements.txt: pinned azure-identity for managed-identity / workload-identity / certificate auth modes used by scripts/shared/dataverse_client.py (council review MIN-04).

### Notes
- Council review MAJ-01 (persistentBrowser missing from CA-AgentBuilder-Zone3.json) is a FALSE POSITIVE; the block has been present since v1.x. No change.

## 2.0.1 - 2026-Q2 Microsoft Learn refresh

### Fixed
- Managed identity-first guidance for unattended runbooks.
- Authentication-strength-aware compliance and drift checks.
- Microsoft Entra ID branding cleanup outside historical changelog text.

## 1.2.2 - 2026-04-22

### Fixed
- Get-ZoneClassification: ELM lookup now queries fsi_environmentrequests / fsi_environmentid / fsi_zone (the ELM source-of-truth table); previous columns did not exist and the lookup always silently failed.
- Connect-CAAGraphSession: added Certificate and ManagedIdentity parameter sets so unattended runbook usage no longer requires interactive auth.
- Get-CAAPolicyBaseline: removed SupportsShouldProcess wrap; -WhatIf was returning $null for callers that depend on baseline output.
- Test-PolicyCompliance: drift counter now credits clean policies as passed and routes the current baseline through Get-CAAPolicyBaseline so Zone-derived severity escalation works.
- Compare-CAAPolicyBaseline: removed-risk-level branch now elevates severity to 4 (was identical to the no-op arm).
- Get-CAAValidationResults: OData $filter datetime literals are URL-encoded.
- Export-CAAComplianceEvidence: requires a real Entra tenant GUID (no more org-name fallback) and resolves the zone breakdown via the picklist FormattedValue annotation.
- Schema script: GlobalOptionSet payloads now include @odata.type discriminators on the OptionSetMetadata root and each OptionMetadata entry; UTC audit datetime columns flipped to TimeZoneIndependent.
- Runbook env-var contract: Start-CAAValidationRunbook reads the actual fsi_CAA_* SchemaName values created by create_caa_environment_variables.py.
- Register-ServicePrincipal: certificate parameter set added; client-secret expiry is now a parameter (default 90 days).
- Watch-PolicyDrift / Test-EvidenceIntegrity: dot-sourced invocation no longer kills the calling runspace.

### Changed
- README zone-policy table rewritten to match the actual templates (Zone 2/3 ship without sign-in risk levels by default; Entra ID P2 add-on template included).
- New optional template: CA-RiskBased-Zone3-Block.json for tenants with Entra ID P2 that want risk-based blocking on Zone 3 workloads.
- Removed legacy Microsoft Entra ID parenthetical branding from PowerShell help blocks.

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
