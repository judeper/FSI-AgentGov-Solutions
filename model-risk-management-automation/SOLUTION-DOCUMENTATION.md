# Solution Documentation — Model Risk Management Automation

**Version:** 1.0.1
**Solution Name:** `model-risk-management-automation`
**Repository:** FSI-AgentGov-Solutions

---

## 1. Solution Overview

### 1.1 Problem Statement

OCC 2011-12 and Federal Reserve SR 11-7 are the primary supervisory frameworks for model risk management at all US banks and many insurance companies. Both have been explicitly confirmed to apply to AI and machine learning systems, including large language models and agentic AI deployed in customer-facing or decision-support roles.

This solution automates three operational gaps examiners consistently cite:

- **Gap 1 — Incomplete model inventories:** Agents enter production without being formally submitted to the model inventory
- **Gap 2 — No automated validation status tracking:** Independent validation is manual and undocumented
- **Gap 3 — No risk-rating evidence collection:** Risk ratings exist in spreadsheets or are absent entirely

**The core examiner question this solution answers:** *"Show me your complete model inventory, the current validation status of each model, and the documented basis for each model's risk rating."*

### 1.2 SR 11-7 Three-Pillar Mapping

| SR 11-7 Pillar | Examiner Requirement | Solution Component |
|----------------|---------------------|--------------------|
| Pillar 1: Model Development | Documented model purpose, design, inputs, limitations | `fsi_modelinventory` + Agent Card (Flow 5) |
| Pillar 2: Model Validation | Independent validation, ongoing monitoring | `fsi_validationcycle` + Flow 3 + Flow 4 |
| Pillar 3: Governance & Controls | Comprehensive inventory, risk tiering, roles | `fsi_mrmriskrating` + Flow 2 + Power BI |

### 1.3 Control Mapping

| Field | Value |
|-------|-------|
| **Primary Control** | Control 2.6 — Model Risk Management (OCC 2011-12 / SR 11-7) |
| **Secondary Controls** | 2.5, 2.9, 2.11, 2.13, 3.1, 1.2 |
| **Pillar** | Pillar 2: Management |
| **Solution Type** | Detective + Preventive |
| **Automation Level** | Event-Triggered + Scheduled + Approval-Gated |

### 1.4 MRM Scope Decision Matrix

| Agent Function | MRM Tier | Validation Cadence |
|---------------|----------|-------------------|
| Quantitative decision output | Tier 1 — Full MRM | Annual |
| Decision support with human review | Tier 2 — Enhanced MRM | Biennial |
| Information retrieval/summarization | Tier 3 — Standard MRM | Biennial |
| Internal productivity | Tier 4 — Minimal MRM | Triennial |

> **Cadence rationale:** Tier 2 and Tier 3 share Biennial cadence. The human-in-the-loop design of Tier 2 reduces autonomous risk exposure to a level comparable with Tier 3 for scheduling purposes, while validation scope remains more rigorous. Document this rationale in DELIVERY-CHECKLIST.md.

---

## 2. Solution Architecture

### 2.1 Components

| Component | Name | Type | Purpose |
|-----------|------|------|---------|
| Flow 1 | Sync-AgentInventory-ToMRM | Scheduled (Daily) | Pull agents from fsi_agentinventory, sync to MRM inventory |
| Flow 2 | Score-ModelRisk-OnSubmission | Instant | Apply 7-factor risk scoring, assign MRM tier |
| Flow 3 | Execute-ValidationWorkflow | Approval-gated | Full SR 11-7 validation lifecycle |
| Flow 4 | Monitor-ModelPerformance-Scheduled | Scheduled (Weekly) | Ongoing monitoring, SLA enforcement |
| Flow 5 | Generate-AgentCard-OnChange | Instant | Agent Card document generation (Word + JSON fallback) |
| Flow 6 | Trigger-Revalidation-OnThreshold | Instant | Threshold-triggered revalidation approval |
| Table 1 | fsi_modelinventory | Dataverse | Master MRM record per agent |
| Table 2 | fsi_mrmriskrating | Dataverse | Risk scoring evidence history |
| Table 3 | fsi_validationcycle | Dataverse | Validation cycle tracking |
| Table 4 | fsi_validationfinding | Dataverse | Individual validation findings |
| Table 5 | fsi_monitoringrecord | Dataverse | Weekly monitoring results |
| Table 6 | fsi_mrmcomplianceevent | Dataverse | Immutable audit log |
| App 1 | MRM Submission Portal | Canvas App | Owner submission and MRM team management |
| App 2 | Validation Workbench | Model-Driven App | Independent validator interface |
| Dashboard | MRM Compliance Dashboard | Power BI | Examiner-ready reporting |

### 2.2 Dependencies

This solution requires `agent-registry-automation` to be deployed in the same Dataverse environment. Flow 1 reads from `fsi_agentinventory` as the authoritative source of registered agents.

---

## 3. API Endpoints

### Required APIs

1. **Power Platform Bots API** — `GET https://api.powerplatform.com/powervirtualagents/environments/{envId}/bots/{botId}?api-version=2022-03-01-preview`
2. **Microsoft Graph — Agent Registry** — `GET https://graph.microsoft.com/beta/agentRegistry/agents/{agentId}` (feature-flagged)
3. **Microsoft Graph — User Profile** — `GET https://graph.microsoft.com/v1.0/users/{userUPN}?$select=id,displayName,mail,jobTitle,department`
4. **SharePoint REST API** — Agent Card list items and document upload
5. **Dataverse Web API** — Upsert via alternate key `(fsi_agentid, fsi_environmentid)`

### Authentication

All flows and scripts use **System-Assigned Managed Identity**. No client secrets, no personal tokens. Tokens acquired via `Get-AzAccessToken`.

---

## 4. Dataverse Schema

Full schema details are in [docs/dataverse-schema.md](docs/dataverse-schema.md).

The schema is defined programmatically in `scripts/create_mrm_dataverse_schema.py` — this is the single source of truth for column names. To regenerate the schema documentation:

```bash
python scripts/create_mrm_dataverse_schema.py --output-docs
```

### Summary

- **6 tables** with `fsi_` prefix
- **~20 option sets** with `fsi_mrm_` prefix
- **1 alternate key** on fsi_modelinventory: `(fsi_agentid, fsi_environmentid)`
- **Immutable table:** fsi_mrmcomplianceevent (no delete for non-admins, 7-year LTR)

---

## 5. Flow Specifications

Full step-by-step build instructions are in [docs/flow-configuration.md](docs/flow-configuration.md).

### Key Design Rules

1. All flows check `IsMRMAutomationEnabled` at entry and terminate gracefully if false
2. Flow 1 verifies fsi_agentinventory accessibility before processing — emits Critical compliance event on failure
3. Flow 2 scoring covers all 5 model provider values without fall-through
4. Flow 3 validation status transitions are strictly one-directional within a cycle
5. Flow 3 validator independence is a dual AND condition (UPN ≠ owner UPN AND department ≠ owner department)
6. Flow 4 SLA breach detection handles null assignment dates
7. Flow 5 implements Word document generation with JSON fallback
8. Flow 6 deferral does not clear fsi_materialchangeflag
9. All Teams notifications use Adaptive Cards v1.2 with Action.Submit (not Action.Execute)
10. All approval decisions use Power Automate Approvals connector

---

## 6. Environment Variables

27 environment variables with `fsi_MRM_*` prefix. Deployed via `scripts/create_mrm_environment_variables.py`.

See [templates/mrm-config.sample.json](templates/mrm-config.sample.json) for all defaults.

---

## 7. SharePoint Configuration

Agent Card Library setup instructions are in [docs/sharepoint-setup.md](docs/sharepoint-setup.md).

---

## 8. Power Apps

Build instructions for both apps are in [docs/power-apps-configuration.md](docs/power-apps-configuration.md).

- **MRM Submission Portal** (Canvas App) — 4 screens for agent submission, status, finding response, MRM team inventory
- **Validation Workbench** (Model-Driven App) — Validator workflow interface with views and forms

---

## 9. Power BI Dashboard

Build instructions are in [docs/powerbi-dashboard.md](docs/powerbi-dashboard.md).

5 report pages: Inventory Overview, Validation Status, Findings & Remediation, Monitoring Trends, Compliance Events.

---

## 10. PowerShell Scripts

| Script | Purpose | Location |
|--------|---------|----------|
| Deploy-MRM-Baseline.ps1 | Initial agent inventory export for MRM team review | scripts/ |
| Test-MRMCompliance.ps1 | Examiner-ready compliance posture report | scripts/ |

Both scripts authenticate via System-Assigned Managed Identity and parameterize OptionSet integer values.

---

## 11. File Structure

```
model-risk-management-automation/
├── README.md
├── CHANGELOG.md
├── DELIVERY-CHECKLIST.md
├── SOLUTION-DOCUMENTATION.md
├── docs/
│   ├── dataverse-schema.md
│   ├── flow-configuration.md
│   ├── power-apps-configuration.md
│   ├── powerbi-dashboard.md
│   ├── sharepoint-setup.md
│   ├── prerequisites.md
│   └── troubleshooting.md
├── scripts/
│   ├── mrm_client.py
│   ├── create_mrm_dataverse_schema.py
│   ├── create_mrm_environment_variables.py
│   ├── create_mrm_connection_references.py
│   ├── deploy.py
│   ├── requirements.txt
│   ├── Deploy-MRM-Baseline.ps1
│   └── Test-MRMCompliance.ps1
└── templates/
    ├── mrm-config.sample.json
    ├── agent-card-content.sample.json
    └── adaptive-card-templates/
        ├── risk-scoring-notification.json
        ├── validation-assignment.json
        ├── sla-breach-alert.json
        └── revalidation-approval.json
```

---

## 12. Success Criteria

### Functional Requirements

- Flow 1 syncs all Registered agents daily; new agents trigger Flow 2 automatically
- Flow 1 detects all 5 material change criteria; does not overwrite MRM-managed fields
- Flow 2 produces complete 7-factor risk scores; handles all provider values
- Flow 2 auto-triggers Flow 3 for Tier 1/2 agents
- Flow 3 enforces dual AND independence check
- Flow 3 validation status transitions are one-directional
- Flow 4 creates monitoring records every week even with no data
- Flow 4 SLA breach detection uses null-safe logic
- Flow 5 implements Word + JSON fallback; logs fallback events
- Flow 6 preserves material change flag on deferral
- All flows check IsMRMAutomationEnabled at entry

### Known Limitations

See README.md Known Limitations section.

---

*This solution supports compliance with OCC 2011-12, Fed SR 11-7, SOX 302/404, and FINRA Rule 3110. Organizations should verify all configurations meet their specific regulatory obligations.*
