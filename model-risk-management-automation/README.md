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
> **Last Verified:** 2026-07-26

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
| `agent-365-lifecycle-governance` | No (optional) | Enables Agent 365 / Microsoft Entra Agent ID cross-reference. The Agent 365 agent registry Graph APIs are in preview and require the AI Administrator or Global Administrator role |

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Automate Premium** | Power Automate cloud flows using premium connectors (Dataverse, HTTP) |
| **Dataverse capacity** | 6 custom tables for MRM data |
| **Managed Environment** | Required for Dataverse Long-Term Retention (LTR) |
| **Microsoft 365 E3+** | Teams notifications and Graph API access |

### Roles

| Role | Required For |
|------|--------------|
| **Power Platform Admin** | Environment enumeration and Dataverse `bot` table access |
| **System Administrator** | Dataverse table creation and security role configuration |
| **Microsoft Entra Global Administrator** or **Privileged Role Administrator** | Granting tenant-wide admin consent for the managed identity's Microsoft Graph *application* permissions. Application Administrator and Cloud Application Administrator can consent to any other API, but not to Microsoft Graph app roles |

See [Prerequisites](docs/prerequisites.md) for complete details.

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

### AI-Powered Self-Healing for Desktop Flows (April 2026)

Microsoft has introduced an AI-powered self-healing capability for Power Automate desktop flows (preview), which uses GPT-4.1 mini and Claude Sonnet 4.5 to recover from runtime UI errors (e.g., "Element not found" failures) in single-element UI/web actions.

**Impact on this solution:** Self-healing desktop flows represent an emerging AI capability that may require MRM inventory tracking under institution-specific policies informed by OCC Bulletin 2026-13 (formerly OCC 2011-12) / Fed SR 26-2 (formerly Fed SR 11-7):

- **Model inventory scope:** Organizations should evaluate whether self-healing-enabled desktop flows meet the threshold for "model" classification under their MRM policy framework
- **Risk rating considerations:** Self-healing introduces runtime AI decision-making that operates outside the original flow design — this may warrant a higher risk rating than standard RPA flows
- **Validation requirements:** The self-healing AI models (GPT-4.1 mini, Claude Sonnet 4.5) are managed by Microsoft and not configurable by the organization — validation should focus on outcomes and error recovery accuracy

> **Note:** This solution currently governs Copilot Studio and Agent Builder agents only. Desktop flow AI capabilities (including self-healing) are not yet within scope. Organizations with significant desktop flow deployments should evaluate whether their MRM framework requires separate inventory and validation processes for AI-enabled RPA.

## Agent ID Migration Evidence

### Background

Microsoft Entra Agent ID (Control 2.26) introduces a new identity model for AI agents. Organizations migrating from legacy Copilot Studio app registrations to Entra Agent IDs must maintain an auditable trail of the migration for model risk examinations informed by OCC Bulletin 2026-13 (formerly OCC 2011-12) / Fed SR 26-2 (formerly Fed SR 11-7).

Copilot Studio automatically creates a Microsoft Entra Agent ID for each new agent created after the Entra Agent ID rollout in July 2026. Agents created before that rollout continue to use app registrations and are scheduled for migration to Agent IDs by Microsoft; governance capabilities work for both Agent IDs and App Registration IDs during the transition period. The Entra Agent ID is a **GUID** — retrieve it in Copilot Studio under **Settings** → **Advanced** → **Metadata** → **Entra Agent ID**, then use that GUID in the Microsoft Entra admin center.

The MRM model inventory (`fsi_modelinventory`) stores an `fsi_agentid` column that references the agent's identity. When migrating from a legacy Bot Framework app registration to an Entra Agent ID, the old and new identifiers must be linked to preserve the validation history chain.

### Migration Evidence Requirements

Examiners require documentation showing:

1. **Complete mapping** — Every legacy Agent ID mapped to its replacement Entra Agent ID
2. **Temporal continuity** — Validation history before and after migration linked to the same logical agent
3. **Authorization chain** — Who approved the migration and when
4. **No inventory gaps** — No agents lost during the transition

### Evidence Format

Store migration evidence as JSON records in `fsi_mrmcomplianceevent` with `fsi_eventtype = "AgentIdMigration"`. Export for examiner review using the sample formats below.

#### JSON Evidence Record

```json
{
  "fsi_eventtype": "AgentIdMigration",
  "fsi_timestamp": "2026-06-15T14:30:00Z",
  "fsi_agentname": "Customer Service Assistant",
  "fsi_details": {
    "legacyAgentId": "cr8a5_customerServiceBot",
    "legacyAppRegistrationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "newEntraAgentId": "7f3c1d92-4a8b-4e6f-9c25-3b81d0a4f612",
    "migrationDate": "2026-06-15T14:30:00Z",
    "approvedBy": "mrm-officer@contoso.com",
    "approvalTicket": "CHG-2026-0451",
    "validationHistoryPreserved": true,
    "preMigrationValidationCount": 4,
    "postMigrationVerification": "Passed"
  },
  "fsi_outcome": "Success",
  "fsi_zone": 3
}
```

#### CSV Export Format (Examiner-Facing)

```csv
AgentName,LegacyAgentId,LegacyAppRegistrationId,NewEntraAgentId,MigrationDate,ApprovedBy,ApprovalTicket,ValidationHistoryPreserved,PreMigrationValidations,PostMigrationVerification
Customer Service Assistant,cr8a5_customerServiceBot,a1b2c3d4-e5f6-7890-abcd-ef1234567890,7f3c1d92-4a8b-4e6f-9c25-3b81d0a4f612,2026-06-15T14:30:00Z,mrm-officer@contoso.com,CHG-2026-0451,true,4,Passed
Loan Officer Assist,cr8a5_loanOfficerAssist,b2c3d4e5-f6a7-8901-bcde-f12345678901,2c9e4b17-63da-4f80-8a55-91c7e2d6b043,2026-06-15T15:00:00Z,mrm-officer@contoso.com,CHG-2026-0451,true,2,Passed
```

### Generating Migration Evidence

1. **Before migration**: Export current `fsi_modelinventory` records with `fsi_agentid` values
2. **During migration**: Log each Agent ID change as an `AgentIdMigration` compliance event
3. **After migration**: Run `Test-MRMCompliance.ps1` to verify all inventory records have valid Entra Agent IDs and linked validation history

### MRM Alignment

| MRM Requirement | How Migration Evidence Helps |
|---------------------|------------------------------|
| Complete model inventory | Migration records help demonstrate no agents were lost during identity transition |
| Audit trail for model changes | `fsi_mrmcomplianceevent` with `AgentIdMigration` type provides timestamped change records |
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
