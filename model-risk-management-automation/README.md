---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P4, P5, P6]
applicable_drivers:
  - ai_governance
  - ai_strategy
coe_function: govern
---
# Model Risk Management Automation

> **Version:** v1.0.4
> **Status:** Live
> **Validated against framework version:** v1.6.0
> **Last Verified:** 2026-10-16

Technical verification sources, discrepancies, and downstream review: [2026-10-16 verification record](docs/verification-2026-10-16.md). This is a documentation re-check, not a live-tenant validation or a compliance assessment.

Automated model risk management workflows for AI agents deployed on Power Platform, aligned to OCC Bulletin 2026-13 (formerly OCC Bulletin 2011-12) and Fed SR 26-2 (formerly Fed SR 11-7) principles where applicable. This solution automates model inventory submission, risk scoring, independent validation workflows, ongoing monitoring, and examiner-facing Agent Card generation.

## Overview

OCC Bulletin 2026-13 (formerly OCC Bulletin 2011-12) and Fed SR 26-2 (formerly Fed SR 11-7) are the current supervisory frameworks for traditional model risk management at US financial institutions. This solution uses those frameworks as the baseline for model inventory, validation, and ongoing monitoring workflows on Power Platform.

> **Scope note**: SR 26-2 / OCC Bulletin 2026-13 (issued April 17, 2026) explicitly excludes generative AI and agentic AI models from its scope. This automation reflects analogous sound risk management principles applied to GenAI/agentic AI scenarios; for those scenarios the citation is informational rather than a direct regulatory obligation. For traditional ML models (algorithmic credit scoring, fraud detection, statistical models), SR 26-2 / OCC 2026-13 applies directly per the guidance.

This solution addresses three operational gaps that examiners consistently cite:

1. **Incomplete model inventories** — Agents enter production without formal MRM submission
2. **No automated validation tracking** — Independent validation is manual and undocumented
3. **No risk-rating evidence collection** — Risk ratings exist in spreadsheets or are absent entirely

**The core examiner question this solution answers:** *"Show me your complete model inventory, the current validation status of each model, and the documented basis for each model's risk rating."*

> **Note:** This is the most full-stack solution in FSI-AgentGov-Solutions — it includes two Power Apps (Canvas + Model-Driven), a Power BI dashboard, and SharePoint integration. It requires `agent-registry-automation` as a pre-deployment dependency.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    SUBMISSION LAYER                              │
│   Power Apps Canvas — MRM Submission Portal                      │
│   (Agent owners submit agents; MRM team manages inventory)       │
└────────────────────────┬─────────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────────┐
│                 ORCHESTRATION LAYER                              │
│              Power Automate Cloud Flows                          │
│  (Inventory Sync, Risk Scoring, Validation Workflow,             │
│   Monitoring, Agent Card Generation, Revalidation Trigger)       │
└────────────────────────┬─────────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────────┐
│                 PERSISTENCE LAYER                                │
│              Dataverse — 6 Custom Tables                         │
│  (ModelInventory, MRMRiskRating, ValidationCycle,                │
│   ValidationFinding, MonitoringRecord, MRMComplianceEvent)       │
└────────────────────────┬─────────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────────┐
│                    EVIDENCE LAYER                                │
│  SharePoint — Agent Card Library (examiner-facing documents)     │
│  Power BI — MRM Compliance Dashboard                             │
│  Teams Notifications — Validation workflow actions               │
└──────────────────────────────────────────────────────────────────┘
```

## Control Mapping

| Control | Description | Coverage |
|---------|-------------|----------|
| **2.6** | Model Risk Management (OCC Bulletin 2026-13 (formerly OCC 2011-12) / Fed SR 26-2 (formerly Fed SR 11-7)) | Primary |
| **2.5** | Testing, Validation, and Quality Assurance | Secondary |
| **2.9** | Agent Performance Monitoring | Secondary |
| **2.11** | Bias Testing and Fairness Assessment | Secondary |
| **2.13** | Documentation and Record Keeping | Secondary |
| **3.1** | Agent Inventory and Metadata Management | Secondary |
| **1.2** | Agent Registry | Secondary |

## MRM Three-Pillar Coverage

| Supervisory Pillar | Examiner Requirement | Solution Component |
|----------------|---------------------|--------------------|
| **Pillar 1: Model Development** | Documented model purpose, design, inputs, limitations | `fsi_modelinventory` + Agent Card generation |
| **Pillar 2: Model Validation** | Independent validation, ongoing monitoring, outcomes analysis | `fsi_validationcycle` + Flow 3 + Flow 4 |
| **Pillar 3: Governance & Controls** | Comprehensive inventory with tiering, defined roles, escalation | `fsi_mrmriskrating` + Flow 2 + Power BI Dashboard |

## MRM Scope Decision Matrix

| Agent Function | MRM Tier | Validation Cadence |
|---------------|----------|-------------------|
| Quantitative decision output (credit scoring, pricing, fraud detection) | Tier 1 — Full MRM | Annual |
| Decision support with human review (compliance screening, loan officer assist) | Tier 2 — Enhanced MRM | Biennial |
| Information retrieval and summarization (document Q&A, policy lookup) | Tier 3 — Standard MRM | Biennial |
| Internal productivity (meeting notes, email drafting) | Tier 4 — Minimal MRM | Triennial |

## Regulatory Alignment

| Regulation | How This Solution Helps |
|------------|------------------------|
| OCC Bulletin 2026-13 (formerly OCC 2011-12) / Fed SR 26-2 (formerly Fed SR 11-7) | Supports comprehensive model inventory, independent validation, and ongoing monitoring automation |
| SOX 302/404 | Aids in documenting IT model controls with 7-year retention via Dataverse LTR and versioned Agent Cards |
| FINRA Rule 3110 | Supports supervision and oversight of AI systems by separating maker (model owner), checker (independent validator), and approver (MRM officer) roles in the validation workflow |
| NIST AI RMF | Helps address risk identification, measurement, and management for AI systems |

> **Note:** No single control or solution satisfies a regulation in isolation. Organizations should verify that their overall control environment meets specific regulatory obligations.

## Prerequisites

### Dependencies

| Dependency | Required | Notes |
|-----------|----------|-------|
| `agent-registry-automation` | **Yes (mandatory)** | Must be deployed first — Flow 1 reads from `fsi_agentinventory` |
| `agent-365-lifecycle-governance` | No (optional) | Enables Agent 365 / Microsoft Entra Agent ID cross-reference. The package inventory API documents both v1.0 and beta endpoints, application and delegated `CopilotPackages.Read.All`, and a Microsoft Agent 365 license requirement. Delegated administrators require AI Administrator or Global Administrator; keep enrichment disabled until tenant access is verified |

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Automate Premium or Process licensing** | Premium-connector cloud flows (Dataverse, HTTP, Word Online (Business)); license by owner, invoking user, or flow as applicable |
| **Power Apps entitlement for Dataverse apps** | Users of the Canvas submission portal and model-driven validation workbench need appropriate Power Apps licensing |
| **Dataverse capacity** | 6 custom tables for MRM data |
| **Managed Environment** | Required for Dataverse Long-Term Retention (LTR) |
| **Teams and SharePoint Online service entitlements** | Verify the assigned plan includes each service; Teams is available in qualifying Microsoft 365 plans or as a standalone SKU. Graph access separately requires the API-specific permissions in the prerequisites |

See the [Power Automate licensing FAQ](https://learn.microsoft.com/power-platform/admin/power-automate-licensing/faqs), [Power Apps licensing FAQ](https://learn.microsoft.com/power-platform/admin/powerapps-flow-licensing-faq), and [Teams service description](https://learn.microsoft.com/office365/servicedescriptions/teams-service-description). Responding to an approval alone does not require Power Automate Premium.

### Roles

| Role | Required For |
|------|--------------|
| **Power Platform Admin** | Environment administration; Dataverse `bot` data access separately requires an appropriate Dataverse security role |
| **System Administrator** | Dataverse table creation and security role configuration |
| **Microsoft Entra Global Administrator** or **Privileged Role Administrator** | Granting tenant-wide admin consent for the managed identity's Microsoft Graph *application* permissions. Application Administrator, Cloud Application Administrator and AI Administrator can consent to any other API, but not to Microsoft Graph app roles |

See [Prerequisites](docs/prerequisites.md) for complete details.

An Entra service-admin role does not automatically assign Dataverse System Administrator in each environment; use the documented [self-elevation process](https://learn.microsoft.com/power-platform/admin/use-service-admin-role-manage-tenant) when required.

## Solution Components

| Component | File | Type |
|-----------|------|------|
| Dataverse schema deployment | `scripts/create_mrm_dataverse_schema.py` | Python |
| Environment variable deployment | `scripts/create_mrm_environment_variables.py` | Python |
| Connection reference deployment | `scripts/create_mrm_connection_references.py` | Python |
| Deployment orchestrator | `scripts/deploy.py` | Python |
| Baseline inventory export | `scripts/Deploy-MRM-Baseline.ps1` | PowerShell |
| Compliance validation | `scripts/Test-MRMCompliance.ps1` | PowerShell |
| Flow build instructions | `docs/flow-configuration.md` | Documentation |
| Power Apps build guide | `docs/power-apps-configuration.md` | Documentation |
| Power BI build guide | `docs/powerbi-dashboard.md` | Documentation |
| SharePoint setup | `docs/sharepoint-setup.md` | Documentation |
| Dataverse schema reference | `docs/dataverse-schema.md` | Documentation |

## Quick Start

Install Python dependencies first:

```powershell
python -m pip install -r scripts/requirements.txt
```

### 1. Deploy Dataverse Schema

```powershell
# Preferred for Azure-hosted runners/functions: managed identity or workload identity
# Set AZURE_CLIENT_ID first when using a user-assigned managed identity.
python scripts/create_mrm_dataverse_schema.py `
    --environment-url "https://your-org.crm.dynamics.com"
```

For an admin workstation, use interactive authentication instead:

```powershell
python scripts/create_mrm_dataverse_schema.py `
    --environment-url "https://your-org.crm.dynamics.com" `
    --tenant-id "your-tenant-id" `
    --interactive
```

> **Legacy fallback:** `--client-id` with `--client-secret` remains available for development-only validation. Replace client secrets with managed identity or workload identity in production.

### 2. Deploy Environment Variables

```powershell
python scripts/create_mrm_environment_variables.py `
    --environment-url "https://your-org.crm.dynamics.com"
```

### 3. Deploy Connection References

```powershell
python scripts/create_mrm_connection_references.py `
    --environment-url "https://your-org.crm.dynamics.com"
```

### 4. Configure SharePoint

Follow [SharePoint Setup](docs/sharepoint-setup.md) to create the Agent Card Library and deploy the Word template.

### 5. Build Power Automate Flows

Follow [Flow Configuration](docs/flow-configuration.md) to build all 6 flows in Power Automate designer.

### 6. Run Baseline Export

```powershell
.\scripts\Deploy-MRM-Baseline.ps1 `
    -DataverseEnvironmentUrl "https://your-org.crm.dynamics.com" `
    -OutputPath "C:\Reports"
```

### 7. Complete Delivery Checklist

Review and complete all items in [DELIVERY-CHECKLIST.md](DELIVERY-CHECKLIST.md) before setting `IsMRMAutomationEnabled` to `"true"`.

## Documentation

| Document | Description |
|----------|-------------|
| [Dataverse Schema](docs/dataverse-schema.md) | Table definitions, option sets, alternate keys, and lookup relationships |
| [Flow Configuration](docs/flow-configuration.md) | Step-by-step build instructions for all 6 flows |
| [Power Apps Configuration](docs/power-apps-configuration.md) | Build guides for MRM Submission Portal and Validation Workbench |
| [Power BI Dashboard](docs/powerbi-dashboard.md) | MRM Compliance Dashboard build guide |
| [SharePoint Setup](docs/sharepoint-setup.md) | Agent Card Library configuration |
| [Prerequisites](docs/prerequisites.md) | Licensing, roles, API permissions, and dependencies |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and resolutions |
| [Delivery Checklist](DELIVERY-CHECKLIST.md) | Pre-deployment validation items |

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.6 — Model Risk Management (SR 26-2)](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.6-model-risk-management-sr-26-2.md) | Primary — model inventory, risk scoring, validation workflow |
| [2.5 — Testing, Validation, and Quality Assurance](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.5-testing-validation-and-quality-assurance.md) | Secondary — independent validation cycles |
| [2.9 — Agent Performance Monitoring and Optimization](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Secondary — ongoing monitoring with threshold detection |
| [2.11 — Bias Testing and Fairness Assessment](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.11-bias-testing-and-fairness-assessment.md) | Secondary — finding category includes Bias/Fairness |
| [2.13 — Documentation and Record Keeping](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.13-documentation-and-record-keeping.md) | Secondary — Agent Cards and immutable compliance events |
| [3.1 — Agent Inventory and Metadata Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.1-agent-inventory-and-metadata-management.md) | Secondary — fsi_modelinventory + fsi_mrmcomplianceevent provide MRM-scoped inventory and metadata |
| [1.2 — Agent Registry](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.2-agent-registry-and-integrated-apps-management.md) | Secondary — reads from agent-registry-automation inventory |

## Platform Update Notes

### AI-Powered Self-Healing for Desktop Flows (preview since March 2026)

Microsoft has introduced an AI-powered self-healing capability for Power Automate desktop flows (preview; introduced with Power Automate for desktop build 2603), which uses GPT-4.1 mini and Claude Sonnet 4.5 to recover from runtime UI errors (e.g., "Element not found" and "Window not found" failures) in actions that interact with a single UI element.

The [current self-healing documentation](https://learn.microsoft.com/power-automate/desktop-flows/self-healing) limits this to supported single-element actions on Power Automate for desktop 2.66 or later. It applies to console/cloud runs, not designer runs, and requires an organization premium account and the documented admin settings, including Anthropic enablement. It can identify an unintended element; it is not deterministic error recovery.

**Impact on this solution:** Self-healing desktop flows represent an emerging AI capability that may require MRM inventory tracking under institution-specific policies informed by OCC Bulletin 2026-13 (formerly OCC 2011-12) / Fed SR 26-2 (formerly Fed SR 11-7):

- **Model inventory scope:** Organizations should evaluate whether self-healing-enabled desktop flows meet the threshold for "model" classification under their MRM policy framework
- **Risk rating considerations:** Self-healing introduces runtime AI decision-making that operates outside the original flow design — this may warrant a higher risk rating than standard RPA flows
- **Validation requirements:** Microsoft documents GPT-4.1 mini and Claude Sonnet 4.5 in combination, with administrator enablement and per-action configuration — validation should focus on outcomes and error recovery accuracy

> **Note:** This solution currently governs Copilot Studio and Agent Builder agents only. Desktop flow AI capabilities (including self-healing) are not yet within scope. Organizations with significant desktop flow deployments should evaluate whether their MRM framework requires separate inventory and validation processes for AI-enabled RPA.

## Agent ID Migration Evidence

### Background

Microsoft Entra Agent ID (Control 2.26) introduces a new identity model for AI agents. Organizations migrating from legacy Copilot Studio app registrations to Entra Agent IDs must maintain an auditable trail of the migration for model risk examinations informed by OCC Bulletin 2026-13 (formerly OCC 2011-12) / Fed SR 26-2 (formerly Fed SR 11-7).

For the standard harness, Copilot Studio automatically creates a Microsoft Entra Agent ID when a new agent is created; for the GitHub Copilot harness it is provisioned on first publication, not when saving a draft. The identity documentation dates the standard-harness rollout and removal of opt-out to May 2026. Existing app-registration agents are being migrated automatically; optional manual migration is preview. Governance capabilities work with both identity types during the transition. Retrieve the identity **GUID** in **Settings** → **Advanced** → **Metadata** → **Entra Agent ID**. Agent Builder agents currently do not use or require these identities. Sources: [identity behavior](https://learn.microsoft.com/microsoft-copilot-studio/govern-agents-identities-overview), [rollout and metadata](https://learn.microsoft.com/microsoft-copilot-studio/admin-use-entra-agent-identities), [migration](https://learn.microsoft.com/microsoft-copilot-studio/govern-migrate-api-entra-agent-identity).

The MRM model inventory stores the **Power Platform Bot ID** in `fsi_agentid` and the environment GUID in `fsi_environmentid`; together these form its alternate key. Store the separate Entra identity GUID in `fsi_entraagentid`. Do not replace `fsi_agentid` with an Entra identity or application ID. Microsoft documents in-place migration with the application (client) ID preserved; record the before/after identity metadata against the same inventory row rather than assuming every migration replaces that identifier.

### Migration Evidence Requirements

Examiners require documentation showing:

1. **Complete mapping** — Every legacy Agent ID mapped to its replacement Entra Agent ID
2. **Temporal continuity** — Validation history before and after migration linked to the same logical agent
3. **Authorization chain** — Who approved the migration and when
4. **No inventory gaps** — No agents lost during the transition

### Evidence Format

Store the advisory `AgentIdMigration` evidence envelope below as serialized JSON in `fsi_mrmcomplianceevent.fsi_eventdetails`, linked to the existing inventory row. It is **not** a Dataverse row-create payload: `fsi_eventtype` is an integer Choice and the deployed schema has no `AgentIdMigration` option. Use the existing **Material Change Detected** value (`100000010`) for this change record, populate required `fsi_eventtimestamp` and `fsi_triggeredby`, select valid `fsi_sr117pillar` and `fsi_complianceimpact` values per institution policy, and bind `fsi_ModelInventory_Lookup` to the existing row. Keep `eventType = "AgentIdMigration"` inside the JSON envelope. See [schema](docs/dataverse-schema.md). Export for examiner review using the sample formats below.

#### JSON Evidence Record

```json
{
  "eventType": "AgentIdMigration",
  "timestamp": "2026-06-15T14:30:00Z",
  "agentName": "Customer Service Assistant",
  "details": {
    "powerPlatformBotId": "19d87065-7909-41de-a4ad-436f74712854",
    "environmentId": "b636a48c-d37a-4121-9b2d-b63066d49db4",
    "legacyAppRegistrationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "applicationClientIdAfterMigration": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "newEntraAgentId": "7f3c1d92-4a8b-4e6f-9c25-3b81d0a4f612",
    "migrationDate": "2026-06-15T14:30:00Z",
    "approvedBy": "mrm-officer@contoso.com",
    "approvalTicket": "CHG-2026-0451",
    "validationHistoryPreserved": true,
    "preMigrationValidationCount": 4,
    "postMigrationVerification": "Passed"
  },
  "outcome": "Success",
  "zone": 3
}
```

#### CSV Export Format (Examiner-Facing)

```csv
AgentName,PowerPlatformBotId,EnvironmentId,LegacyAppRegistrationId,ApplicationClientIdAfterMigration,NewEntraAgentId,MigrationDate,ApprovedBy,ApprovalTicket,ValidationHistoryPreserved,PreMigrationValidations,PostMigrationVerification
Customer Service Assistant,19d87065-7909-41de-a4ad-436f74712854,b636a48c-d37a-4121-9b2d-b63066d49db4,a1b2c3d4-e5f6-7890-abcd-ef1234567890,a1b2c3d4-e5f6-7890-abcd-ef1234567890,7f3c1d92-4a8b-4e6f-9c25-3b81d0a4f612,2026-06-15T14:30:00Z,mrm-officer@contoso.com,CHG-2026-0451,true,4,Passed
Loan Officer Assist,ac1078da-7a48-44fa-98e5-69f44acb183b,b636a48c-d37a-4121-9b2d-b63066d49db4,b2c3d4e5-f6a7-8901-bcde-f12345678901,b2c3d4e5-f6a7-8901-bcde-f12345678901,2c9e4b17-63da-4f80-8a55-91c7e2d6b043,2026-06-15T15:00:00Z,mrm-officer@contoso.com,CHG-2026-0451,true,2,Passed
```

### Generating Migration Evidence

1. **Before migration**: Export inventory row IDs, `fsi_agentid`, `fsi_environmentid`, `fsi_entraagentid`, application/client IDs, and linked validation-cycle IDs/counts.
2. **During migration**: Log the `AgentIdMigration` envelope as described above; retain the same inventory row and Bot ID/environment alternate key.
3. **After migration**: Compare the before/after identifiers and linked validation rows, confirm the preserved application/client ID, and test channels, connectors, authentication, and Entra sign-in/Conditional Access results per Microsoft's [migration validation guidance](https://learn.microsoft.com/microsoft-copilot-studio/govern-migrate-api-entra-agent-identity#validate-migrated-agents). `Test-MRMCompliance.ps1` reports aggregate MRM status only; it does **not** validate Entra identities or migration-history continuity.

### MRM Alignment

| MRM Requirement | How Migration Evidence Helps |
|---------------------|------------------------------|
| Complete model inventory | Migration records help demonstrate no agents were lost during identity transition |
| Audit trail for model changes | `fsi_mrmcomplianceevent` uses Material Change Detected (`fsi_eventtype = 100000010`), with the `AgentIdMigration` envelope serialized in `fsi_eventdetails`, to provide timestamped change records |
| Ongoing monitoring continuity | `validationHistoryPreserved` flag helps confirm pre-migration validation cycles remain linked |
| Governance approval | `approvedBy` and `approvalTicket` fields help document authorization chain |

> **Note:** The migration evidence format is advisory. Organizations should adapt the schema to match their specific MRM policy requirements and examiner expectations.

## Known Limitations

- **Copilot Studio telemetry:** Agent usage telemetry may not expose granular error and escalation rates via Power Platform API. Flow 4 creates monitoring records with `fsi_datasource = "Not Available"` to preserve cadence evidence.
- **Keyword-based data sensitivity scoring:** Flow 2 Step 3b uses keyword analysis which may mis-score agents with unusual terminology. MRM officer review and override mechanism is built in.
- **Word Online connector dependency:** Flow 5 requires a deployed `AgentCard-Template.docx`. JSON fallback is fully implemented with `fsi_agentcardformat` field and compliance event logging.
- **MRM monitoring thresholds:** Current supervisory guidance does not prescribe explicit quantitative thresholds for AI models. All thresholds are exposed as environment variables for institution-specific calibration.
- **Power Platform scope:** This solution governs Copilot Studio and Agent Builder agents only — Azure ML models, custom-trained models, and third-party AI APIs require separate MRM processes.
- **Shared biennial cadence:** Tier 2 and Tier 3 share a Biennial validation cadence — rationale documented in DELIVERY-CHECKLIST.md.

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | March 2026 | Initial release |
| 1.0.1 | April 2026 | Option set defaults + PowerShell verb rename |
| 1.0.2 | April 2026 | AI Council technical-accuracy review — column-drift fixes (lookup columns, picklist integers), regulatory language softening (FINRA 25-07 framing, examiner-facing wording), control mapping corrections (3.1 title + pillar paths), Agent Card schema alignment, deployment script auth parameters |
| 1.0.3 | May 2026 | Microsoft Learn 2026-Q2 refresh — managed-identity-first Python auth, Agent 365 registry API alignment, MRM governance-zone mapping fix, configurable scoring thresholds, and Agent Card evidence updates |
| 1.0.4 | May 2026 | Council review remediation — shared `DataverseClient` adoption (`mrm_client.py` is now a deprecation stub); flow doc and troubleshooting lookup-column fixes; integer OptionSet notes for Flow 2 steps 3.4/3.5; `create_alternate_keys()` uses `ensure_entity_key()` instead of raw session access |

## Support

For issues and feature requests, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*This solution is provided as a reference implementation. Organizations should validate all configurations against their specific regulatory obligations and environment requirements. This solution does not constitute legal or compliance advice.*

---

*FSI Agent Governance Framework — Model Risk Management Automation v1.0.4*
