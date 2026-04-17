# Model Risk Management Automation

> **Status:** Production Ready (v1.0.2)

Automated OCC 2011-12 / Fed SR 11-7 model risk management for AI agents deployed on Power Platform. This solution automates model inventory submission, risk scoring, independent validation workflows, ongoing monitoring, and examiner-facing Agent Card generation.

## Overview

OCC 2011-12 and Federal Reserve SR 11-7 are the primary supervisory frameworks for model risk management at US financial institutions. The 2021 Interagency Request for Information confirmed these frameworks apply to traditional machine learning systems; their application to large language models and agentic AI is an active area of supervisory guidance and institutions should consult their legal and compliance teams when applying MRM to LLM-based agents.

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
| **2.6** | Model Risk Management (OCC 2011-12 / SR 11-7) | Primary |
| **2.5** | Testing, Validation, and Quality Assurance | Secondary |
| **2.9** | Agent Performance Monitoring | Secondary |
| **2.11** | Bias Testing and Fairness Assessment | Secondary |
| **2.13** | Documentation and Record Keeping | Secondary |
| **3.1** | Agent Inventory and Metadata Management | Secondary |
| **1.2** | Agent Registry | Secondary |

## SR 11-7 Three-Pillar Coverage

| SR 11-7 Pillar | Examiner Requirement | Solution Component |
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
| OCC 2011-12 / Fed SR 11-7 | Supports comprehensive model inventory, independent validation, and ongoing monitoring automation |
| SOX 302/404 | Aids in documenting IT model controls with 7-year retention via Dataverse LTR and versioned Agent Cards |
| FINRA Rule 3110 | Supports supervision and oversight of AI systems by separating maker (model owner), checker (independent validator), and approver (MRM officer) roles in the validation workflow |
| NIST AI RMF | Helps address risk identification, measurement, and management for AI systems |

> **Note:** No single control or solution satisfies a regulation in isolation. Organizations should verify that their overall control environment meets specific regulatory obligations.

## Prerequisites

### Dependencies

| Dependency | Required | Notes |
|-----------|----------|-------|
| `agent-registry-automation` | **Yes (mandatory)** | Must be deployed first — Flow 1 reads from `fsi_agentinventory` |
| `agent-365-lifecycle-governance` | No (optional) | Enables Entra Agent Registry cross-reference |

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows with Dataverse and HTTP connectors |
| **Dataverse capacity** | 6 custom tables for MRM data |
| **Managed Environment** | Required for Dataverse Long-Term Retention (LTR) |
| **Microsoft 365 E3+** | Teams notifications and Graph API access |

### Roles

| Role | Required For |
|------|--------------|
| **Power Platform Admin** | Environment enumeration and Bots API access |
| **System Administrator** | Dataverse table creation and security role configuration |
| **Entra Global Admin** or **Application Administrator** | Managed Identity API permission grants |

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

### 1. Deploy Dataverse Schema

```powershell
# Deploy tables, option sets, and alternate keys
python scripts/create_mrm_dataverse_schema.py `
    --environment-url "https://your-org.crm.dynamics.com" `
    --tenant-id "your-tenant-id" `
    --client-id "your-client-id" `
    --client-secret "your-client-secret"
```

### 2. Deploy Environment Variables

```powershell
python scripts/create_mrm_environment_variables.py `
    --environment-url "https://your-org.crm.dynamics.com" `
    --tenant-id "your-tenant-id" `
    --client-id "your-client-id" `
    --client-secret "your-client-secret"
```

### 3. Deploy Connection References

```powershell
python scripts/create_mrm_connection_references.py `
    --environment-url "https://your-org.crm.dynamics.com" `
    --tenant-id "your-tenant-id" `
    --client-id "your-client-id" `
    --client-secret "your-client-secret"
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
| [2.6 — Model Risk Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.6-model-risk-management.md) | Primary — model inventory, risk scoring, validation workflow |
| [2.5 — Testing, Validation, and Quality Assurance](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.5-testing-validation-and-quality-assurance.md) | Secondary — independent validation cycles |
| [2.9 — Agent Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring.md) | Secondary — ongoing monitoring with threshold detection |
| [2.11 — Bias Testing and Fairness Assessment](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.11-bias-testing-and-fairness-assessment.md) | Secondary — finding category includes Bias/Fairness |
| [2.13 — Documentation and Record Keeping](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.13-documentation-and-record-keeping.md) | Secondary — Agent Cards and immutable compliance events |
| [3.1 — Agent Inventory and Metadata Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.1-agent-inventory-and-metadata-management.md) | Secondary — fsi_modelinventory + fsi_mrmcomplianceevent provide MRM-scoped inventory and metadata |
| [1.2 — Agent Registry](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.2-agent-registry-and-integrated-apps-management.md) | Secondary — reads from agent-registry-automation inventory |

## Platform Update Notes

### AI-Powered Self-Healing for Desktop Flows (April 2026)

Microsoft has introduced an AI-powered self-healing capability for Power Automate desktop flows (preview), which uses GPT-4.1 mini and Claude Sonnet 4.5 to recover from runtime UI errors (e.g., "Element not found" failures) in single-element UI/web actions.

**Impact on this solution:** Self-healing desktop flows represent an emerging AI capability that may require MRM inventory tracking under OCC 2011-12 / SR 11-7:

- **Model inventory scope:** Organizations should evaluate whether self-healing-enabled desktop flows meet the threshold for "model" classification under their MRM policy framework
- **Risk rating considerations:** Self-healing introduces runtime AI decision-making that operates outside the original flow design — this may warrant a higher risk rating than standard RPA flows
- **Validation requirements:** The self-healing AI models (GPT-4.1 mini, Claude Sonnet 4.5) are managed by Microsoft and not configurable by the organization — validation should focus on outcomes and error recovery accuracy

> **Note:** This solution currently governs Copilot Studio and Agent Builder agents only. Desktop flow AI capabilities (including self-healing) are not yet within scope. Organizations with significant desktop flow deployments should evaluate whether their MRM framework requires separate inventory and validation processes for AI-enabled RPA.

## Known Limitations

- **Copilot Studio telemetry:** Agent usage telemetry may not expose granular error and escalation rates via Power Platform API. Flow 4 creates monitoring records with `fsi_datasource = "Not Available"` to preserve cadence evidence.
- **Keyword-based data sensitivity scoring:** Flow 2 Step 3b uses keyword analysis which may mis-score agents with unusual terminology. MRM officer review and override mechanism is built in.
- **Word Online connector dependency:** Flow 5 requires a deployed `AgentCard-Template.docx`. JSON fallback is fully implemented with `fsi_agentcardformat` field and compliance event logging.
- **SR 11-7 monitoring thresholds:** No explicit quantitative thresholds exist in SR 11-7 for AI models. All thresholds are exposed as environment variables for institution-specific calibration.
- **Power Platform scope:** This solution governs Copilot Studio and Agent Builder agents only — Azure ML models, custom-trained models, and third-party AI APIs require separate MRM processes.
- **Shared biennial cadence:** Tier 2 and Tier 3 share a Biennial validation cadence — rationale documented in DELIVERY-CHECKLIST.md.

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | March 2026 | Initial release |
| 1.0.1 | April 2026 | Option set defaults + PowerShell verb rename |
| 1.0.2 | April 2026 | AI Council technical-accuracy review — column-drift fixes (lookup columns, picklist integers), regulatory language softening (FINRA 25-07 framing, examiner-facing wording), control mapping corrections (3.1 title + pillar paths), Agent Card schema alignment, deployment script auth parameters |

## Support

For issues and feature requests, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*This solution is provided as a reference implementation. Organizations should validate all configurations against their specific regulatory obligations and environment requirements. This solution does not constitute legal or compliance advice.*

---

*FSI Agent Governance Framework — Model Risk Management Automation v1.0.1*
