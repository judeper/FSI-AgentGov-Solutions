# Changelog

All notable changes to FSI-AgentGov-Solutions are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Council Review] - 2026-04-16

### Council Review — Autonomous Multi-Agent Audit

- Processed **34 solutions** via dual-model council review (GPT-5.4 + Claude Opus 4.6)
- Applied fixes to **31 solutions** (2 solutions had no issues, 1 partially fixed)
- **189 total fixes** across **136 files modified**
- Key fix categories:
  - **Dataverse column name mismatches** — Fixed dozens of schema-script misalignments (fsi_scantime → fsi_validationtime, entity set pluralization, snake_case → logical names)
  - **Product naming** — Updated "Azure AD" → "Microsoft Entra ID" across 60+ files
  - **Compliance language** — Replaced 20+ prohibited phrases ("ensures", "guarantees") with hedging language ("supports", "helps maintain")
  - **Missing schema columns** — Added exception audit trail columns (rejection notes, approval notes)
  - **Functional bugs** — Fixed KQL query bug (ResolutionRate always 0% for autonomous agents), exception expiration enforcement, resolution tracking
  - **Domain facts** — Created `.ralph-config.json` files for 8 solutions documenting key design decisions
- 0 items logged to REVIEW_NEEDED.md (all fixes applied directly)
- 0 GitHub Issues opened (no LOW confidence items requiring human review)

---

## Documentation Updates — 2026-04-09

### Changed
- **site-docs/index.md** — Fixed homepage metrics count from 33 to 35 solutions
- **unrestricted-agent-sharing-detector** — Added Native Agent Sharing Rules (GA May 2025) section referencing platform controls and positioning UASD as complementary audit/evidence layer
- **agent-sharing-access-restriction-detector** — Added Native Agent Sharing Rules (GA May 2025) section referencing platform controls and positioning ASARD for zone-based compliance auditing
- **agent-365-lifecycle-governance** — Added Relationship to Native Agentic Center of Enablement (2026 Wave 1) section explaining FSI-specific lifecycle enforcement beyond native CoE
- **environment-lifecycle-management** — Added Relationship to Native Agentic Center of Enablement (2026 Wave 1) section distinguishing provisioning-time governance from tenant monitoring
- **scope-drift-monitor** — Added Microsoft Purview Sensitivity Labels (2026 Wave 1) forward-looking note on complementary data classification
- **file-upload-security** — Added Microsoft Purview Sensitivity Labels (2026 Wave 1) forward-looking note on complementary data classification

---

## credential-oversharing-detector v1.0.0 — 2026-04-01

### Added
- Full solution release: scanning scripts, Dataverse schema, zone policies, evidence export, documentation
- 5 Dataverse tables with auto-generated schema documentation
- 6 PowerShell governance scripts for credential scope scanning and compliance
- Zone-based credential policy templates
- Teams adaptive card alert template
- Graduated from v0.1.0-preview placeholder to complete solution

---

## hitl-workflow-governance v1.0.0 — 2026-04-02

### Added

- **HITL Workflow Governance v1.0.0** — Full solution for zone-based governance of Human in the Loop checkpoints in Copilot Studio agent flows
  - Dataverse schema: 3 tables — fsi_HitlCheckpointResult (per-agent scan results), fsi_HitlCheckpointException (approved exceptions), fsi_HitlScanRun (immutable audit trail)
  - Python deployment: create_hwg_dataverse_schema.py (with --output-docs), create_hwg_environment_variables.py, create_hwg_connection_references.py, deploy.py
  - PowerShell scan scripts: Get-AgentHitlSettings.ps1, Test-HitlWorkflowCompliance.ps1, Start-HitlValidationRunbook.ps1
  - Evidence export: Export-HitlGovernanceEvidence.ps1 (JSON + SHA-256 sidecar), Test-EvidenceIntegrity.ps1
  - Governance validation: Test-HitlCheckpointConfiguration.ps1 for zone-based HITL policy enforcement
  - Private helper modules: HWGClient.psm1, Connect-EnvironmentDataverse.ps1, Get-ExpectedHitlPolicy.ps1, zone classification
  - Templates: hitl-zone-policy.json (zone requirements), adaptive-card-hitl-alert.json (Teams notification)
  - Documentation: prerequisites, flow configuration (manual build), Dataverse schema, troubleshooting
  - 6 environment variables, 2 connection references (Dataverse + Human in the Loop connector)
  - Supports Controls 2.12, 2.17, 1.10
- **Cross-Tenant External Sharing Governance v1.0.0** — Three-layer cross-tenant access governance for AI agents in FSI environments
  - Dataverse schema: 5 tables — fsi_approvedexternaltenant (allow list with alternate key), fsi_externalsharefinding (violations with composite dedup key), fsi_tenantisolationrecord (daily Layer 1 audit), fsi_entractarecord (weekly Layer 2 audit), fsi_crosstenantcomplianceevent (LTR-enabled immutable audit log)
  - Python deployment: create_ctsg_dataverse_schema.py, create_ctsg_environment_variables.py, create_ctsg_connection_references.py, deploy.py
  - PowerShell scripts: Deploy-CrossTenantBaseline.ps1, Validate-CrossTenantCompliance.ps1
  - Power Automate flows (documentation-only): tenant isolation validation, external agent share detection (5-value guest detection method), Entra CTA audit, tenant onboarding (dual-approval with Expired timeout), remediation (approval-gated), annual review reminders (90/30/overdue)
  - Two Managed Identities: MI-CrossTenantReadOnly (Flows 1-3, 6), MI-CrossTenantReadWrite (Flows 4-5)
  - 12 environment variables including feature flag and CTA baseline configuration
  - Templates: approved tenant sample, Adaptive Card v1.2 templates
  - Feature-flagged via IsCrossTenantGovernanceEnabled; depends on agent-registry-automation and unrestricted-agent-sharing-detector
  - Supports Controls 1.1, 1.18 (primary), 2.1, 2.8, 3.1, 1.11
- **Model Risk Management Automation v1.0.0**— Automated OCC 2011-12 / SR 11-7 model risk management for AI agents
  - Dataverse schema: 6 tables — fsi_modelinventory (with alternate key), fsi_mrmriskrating, fsi_validationcycle, fsi_validationfinding, fsi_monitoringrecord, fsi_mrmcomplianceevent (LTR-enabled immutable)
  - Python deployment: mrm_client.py, create_mrm_dataverse_schema.py, create_mrm_environment_variables.py, create_mrm_connection_references.py, deploy.py
  - PowerShell scripts: Deploy-MRM-Baseline.ps1, Validate-MRM-Compliance.ps1
  - Power Automate flows (documentation-only): inventory sync, risk scoring, validation workflow, performance monitoring, Agent Card generation, revalidation trigger
  - Power Apps (documentation-only): MRM Submission Portal (Canvas, 4 screens), Validation Workbench (Model-Driven)
  - Power BI dashboard (documentation-only): MRM Compliance Dashboard with 5 report pages
  - SharePoint: Agent Card Library with Word template + JSON fallback
  - Templates: 4 Adaptive Card v1.2 templates, sample config, Agent Card content structure
  - Feature-flagged via IsMRMAutomationEnabled; depends on agent-registry-automation
  - Supports Controls 2.6 (primary), 2.5, 2.9, 2.11, 2.13, 3.1, 1.2
- **Agent 365 Lifecycle Governance v1.1.0** — Automated lifecycle governance for AI agents using Microsoft Agent 365, Entra ID Governance, and Power Platform
  - Dataverse schema: 5 tables — fsi_agentlifecyclerecord (with alternate key), fsi_sponsorassignment, fsi_accessreview, fsi_deactivationrequest, fsi_lifecyclecomplianceevent (LTR-enabled immutable)
  - Python deployment: create_alg_dataverse_schema.py, create_alg_environment_variables.py, create_alg_connection_references.py
  - PowerShell scripts: Deploy-LifecycleGovernance-Baseline.ps1, Validate-LifecycleCompliance.ps1
  - Power Automate flows (documentation-only): sponsor enforcement, access reviews, inactivity detection, deactivation, sponsor monitoring, deletion hold
  - Templates: Adaptive Card v1.2 sponsor assignment notification, sample lifecycle configuration
  - Feature-flagged via IsAgent365LifecycleEnabled (gates all Agent 365 API calls until GA)
  - Supports Controls 2.3 (primary), 1.2, 1.11, 2.1, 2.8, 2.12, 3.1
- **Agent Registry Automation v1.0.0**— Automated discovery, registration, approval, and lifecycle governance of AI agents
  - Dataverse schema: fsi_agentinventory (with alternate key), fsi_registrationrequest, fsi_agentcomplianceevent (LTR-enabled), fsi_ownershipaudit
  - Python deployment: ara_client.py, create_dataverse_schema.py, create_environment_variables.py, create_connection_references.py, deploy.py
  - PowerShell scripts: Deploy-AgentRegistry-Baseline.ps1, Validate-AgentRegistry-Compliance.ps1
  - Power Automate flows (documentation-only): daily discovery, registration approval, Entra sync, orphan detection
  - Supports Controls 1.2 (primary), 1.7, 2.1, 2.13
- **Agent Knowledge Source Scanner v1.0.0** — New solution for item-level permission scanning in agent knowledge source SharePoint libraries
  - `Get-KnowledgeSourceItemPermissions.ps1` — PnP PowerShell script enumerating item-level permissions with agent-context-aware risk scoring (CRITICAL/HIGH/MEDIUM/LOW)
  - Sensitivity label cross-reference with configurable tier mapping
  - Agent user scope comparison via security group or UPN list
  - CSV/JSON input support for multi-library scanning from prior scan output
  - `item-scope-config.sample.json` configuration template
- **Compliance Dashboard — Exchange Coverage** — Extended with Exchange Online compliance signal collection
  - `Get-ExchangeComplianceData.ps1` — Graph API script collecting external forwarding rules, DLP alerts, shared mailbox access, distribution list external membership
  - `exchange-config.sample.json` configuration template with scan scope, risk thresholds, domain allow-list
  - Updated architecture diagram, data sources, and documentation to include Exchange as a data source
  - Updated dataverse-schema.md with Exchange evidence mapping to fsi_complianceevidence
  - Updated flow-configuration.md with Exchange API calls for CD-EvidenceCollector planned flow

- **Action Confirmation Auditor** — New `Test-UserDefinedActionMessages.ps1` governance script validates the Copilot Studio "User-Defined Action Messages" toggle per zone policy (Zone 3 required, Zone 2 recommended, Zone 1 optional). Supports Control 1.23.
- **Generative AI Config Auditor** — Two new compliance rules:
  - Rule 5 (`UnauthorizedModelKnowledge`): Validates "Use AI general knowledge" / Model Knowledge toggle against zone policy (Zone 3 disabled, Zone 2 requires approval, Zone 1 allowed)
  - Rule 6 (`UnauthorizedSemanticSearch`): Validates Semantic Search toggle against zone policy (Zone 3 requires approval, Zone 2 allowed with logging, Zone 1 allowed)
  - Updated `Get-ExpectedGenAIPolicy.ps1`, `Get-AgentGenAISettings.ps1`, `Compare-GenAIConfigCompliance.ps1`, and Dataverse schema
- **Unrestricted Agent Sharing Detector** — New `Test-AgentSharingCompliance.ps1` and `Get-ExpectedSharingPolicy.ps1` governance scripts for zone-based sharing compliance validation; new `uasd_client.py` Dataverse client

### Fixed

- **Compliance Dashboard documentation drift:** Corrected stale 62-control / 71-control references in active docs to the validated 78-control baseline across README, deployment checklist, Power BI template guidance, troubleshooting, and control master table expectations
- **UASD Adaptive Card:** Corrected "Run Audit Script" URL to match actual deployment guide path; corrected "View Documentation" URL to point to Control 1.1 (was incorrectly referencing Control 2.24)

### Previously Added

- **UASD v1.0.2** — Flow 4 (`UASD-Exception-Expiration-Monitor`) build instructions: proactive exception expiration handling with configurable warning threshold and Teams alerts
- **Deployment Guide v0.1** — Use-case mapping, solution layers, and Compliance Dashboard integration sequencing

- **DR Testing Framework v1.0.0** - Automated disaster recovery testing for AI agents
  - 4 test scenarios: Agent Restore, Environment Failover, Data Recovery, Full DR
  - RTO/RPO measurement and comparison
  - Validation checks for agent, connector, data, and security
  - PowerShell script: Invoke-DRTest.ps1
  - Gap identification and tracking
  - Evidence export for compliance
  - Supports Controls 2.4, 2.1, 1.9

- **Hallucination Tracker v1.0.0** - Feedback aggregation for hallucination pattern analysis
  - Multi-source feedback collection (user, supervisor, automated)
  - 5 hallucination categories with severity scoring
  - Pattern detection and clustering
  - Agent accuracy scoring and rating
  - Python script: analyze_patterns.py
  - Supports Controls 3.10, 2.9, 2.12

- **COI Testing Framework v1.0.0** - Conflict of interest testing for agent recommendations
  - Test categories: Proprietary bias (3), Suitability (3), Fee transparency (2), Cross-selling (2)
  - Python test runner: run_coi_tests.py
  - Scheduled and on-demand test execution
  - FINRA Supervision Workflow integration
  - Supports Controls 2.18, 2.11, 2.5

- **RAG Source Validator v1.0.0** - Integrity validation for RAG knowledge sources
  - Dataverse schema: fsi_knowledgesource, fsi_validationresult, fsi_sourcechange
  - Security roles: RSV Viewer, RSV Validator, RSV Admin
  - PowerShell script: Invoke-SourceValidation.ps1
  - SHA-256 hash validation, schema drift detection, freshness monitoring
  - Supports SharePoint, Dataverse, Azure Blob sources
  - Supports Controls 2.16, 1.7, 2.13

- **Scope Drift Monitor v1.0.0** - Detect agent data access beyond declared scope
  - Dataverse schema: fsi_agentscope, fsi_scopeitem, fsi_scopeviolation, fsi_expansionrequest
  - Security roles: SDM Viewer, SDM Analyst, SDM Admin
  - PowerShell script: New-AgentBaseline.ps1
  - Scope expansion workflow with data owner and security approval
  - Complete documentation: prerequisites, schema, baseline configuration
  - Supports Controls 1.14, 1.4, 1.5

- **Segregation of Duties Detector v1.0.0** - Role conflict detection for Maker/Checker enforcement
  - Dataverse schema: fsi_conflictrule, fsi_sodviolation, fsi_sodexception, fsi_sodauditlog
  - Security roles: SoD Viewer, SoD Analyst, SoD Admin
  - PowerShell scripts: Invoke-SoDScan.ps1, Import-ConflictRules.ps1
  - Default rule sets: Maker/Checker (4), Segregation (3), Privileged Access (3)
  - Complete documentation: prerequisites, schema, conflict rules, troubleshooting
  - Supports Controls 2.8, 2.1, 2.3

- **Compliance Dashboard v1.0.0-beta** - Aggregated compliance reporting across 71 controls
  - Dataverse schema: fsi_controlmaster, fsi_controlassessment, fsi_compliancescore, fsi_complianceexception, fsi_complianceevidence
  - Security roles: CD Viewer, CD Assessor, CD Admin
  - Power Automate flows: CD-ScoreCalculator, CD-ExceptionMonitor, CD-EvidenceCollector
  - Python script: load_sample_data.py for demo data
  - Complete documentation: prerequisites, schema, flows, Power BI setup, DAX measures, troubleshooting
  - Control master data: All 71 controls with zone applicability and weights
  - Supports Controls 3.3, 3.1, 3.2
  - **Note:** Beta release - documentation and schemas complete, Power BI template requires manual creation

- **Conditional Access Automation v1.0.0** - CA policy deployment and compliance monitoring for AI workloads
  - 8 policy templates for Copilot Studio, Agent Builder, and M365 Copilot
  - PowerShell scripts: Deploy-CAPolicies.ps1, Test-PolicyCompliance.ps1, Register-ServicePrincipal.ps1
  - Zone-based policy requirements (Zone 1: risk-based, Zone 2: always MFA, Zone 3: MFA + compliant device)
  - Policy drift detection and compliance monitoring
  - Break-glass account exclusion enforcement
  - ELM integration for automated policy deployment on environment provisioning
  - Complete documentation: prerequisites, templates, deployment guide, compliance monitoring, troubleshooting
  - Supports Controls 1.11, 1.23, 1.18

- **FINRA Supervision Workflow v1.0.0** - Automated supervision queue for AI agent outputs (FINRA 3110)
  - Dataverse schema: SupervisionQueue, SupervisionLog, SupervisionConfig tables
  - Security roles: FSW Supervisor, FSW Queue Manager, FSW Admin, FSW Auditor
  - Python scripts: deploy.py, export_supervision_evidence.py
  - Complete documentation: prerequisites, schema, security roles, flow configuration, Communication Compliance setup, Power BI dashboard, troubleshooting
  - Integration with Communication Compliance API for flagged content ingestion
  - Zone/tier-based SLA configuration with automatic escalation
  - Evidence export with SHA-256 integrity hashing for regulatory examination
  - Supports Controls 2.12, 1.10, 1.7

- **Environment Lifecycle Management v1.0.1** - Automated Power Platform environment provisioning
  - Python scripts: Service Principal registration, quarterly evidence export, role verification, immutability validation
  - Complete documentation: prerequisites, Dataverse schema, security roles, flow configuration, Copilot setup
  - Templates: EnvironmentRequest JSON sample, Copilot Studio output schema
  - SETUP_CHECKLIST.md for phased deployment

### Changed

- **Catalog reconciliation:** Updated root README.md and `site-docs/solutions/index.md` to align the published inventory to 33 live solutions and the validated 78-control framework baseline, bringing existing live entries and current version labels back in sync without rewriting historical release notes
- **Preview/live boundary:** Both `hitl-workflow-governance` and `credential-oversharing-detector` have since graduated to v1.0.0 live solutions
- **Entra terminology cleanup:** Active documentation now uses Microsoft Entra ID naming for app registrations, connector labels, licensing references, and resource URI tables where current product terminology applies
- **Agent 365 governance boundary:** Clarified that Agent 365 Lifecycle Governance complements — rather than duplicates — native Agent 365 Admin Center inventory, pending request, ownerless-agent, and overview analytics surfaces
- Updated root README.md to include Environment Lifecycle Management
- Enhanced boundary-check.py hook with cross-repository access to FSI-AgentGov
- Added Python/pip permissions to settings.json
- Added hooks configuration to settings.json (previously only in settings.local.json)

---

## Previous Releases

Individual solution changelogs:

- [DR Testing Framework](./dr-testing-framework/CHANGELOG.md) - v1.0.0
- [Hallucination Tracker](./hallucination-tracker/CHANGELOG.md) - v1.0.0
- [COI Testing Framework](./coi-testing/CHANGELOG.md) - v1.0.0
- [RAG Source Validator](./rag-source-validator/CHANGELOG.md) - v1.0.0
- [Scope Drift Monitor](./scope-drift-monitor/CHANGELOG.md) - v1.0.0
- [Segregation of Duties Detector](./segregation-detector/CHANGELOG.md) - v1.0.0
- [Compliance Dashboard](./compliance-dashboard/CHANGELOG.md) - v1.0.0-beta
- [Conditional Access Automation](./conditional-access-automation/CHANGELOG.md) - v1.0.0
- [FINRA Supervision Workflow](./finra-supervision-workflow/CHANGELOG.md) - v1.0.0
- [Environment Lifecycle Management](./environment-lifecycle-management/CHANGELOG.md) - v1.1.2
- [Message Center Monitor](./message-center-monitor/CHANGELOG.md) - v2.1.1
- [Pipeline Governance Cleanup](./pipeline-governance-cleanup/CHANGELOG.md) - v1.0.8
- [Deny Event Correlation Report](./deny-event-correlation-report/CHANGELOG.md) - v2.0.0
