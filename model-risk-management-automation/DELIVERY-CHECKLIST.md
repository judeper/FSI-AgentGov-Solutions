# Delivery Checklist — Model Risk Management Automation

> Complete all items before setting `IsMRMAutomationEnabled` to `"true"`.

## Pre-Deployment Validation

### Entity Set Name Confirmation

Dataverse auto-generates entity set names (plural forms) at deployment time. Confirm each name matches the values used in flows and scripts.

| Table | Expected Entity Set Name | Confirmed | Confirmed Value |
|-------|--------------------------|-----------|-----------------|
| fsi_modelinventory | `fsi_modelinventories` | [ ] | |
| fsi_mrmriskrating | `fsi_mrmriskratings` | [ ] | |
| fsi_validationcycle | `fsi_validationcycles` | [ ] | |
| fsi_validationfinding | `fsi_validationfindings` | [ ] | |
| fsi_monitoringrecord | `fsi_monitoringrecords` | [ ] | |
| fsi_mrmcomplianceevent | `fsi_mrmcomplianceevents` | [ ] | |
| fsi_agentinventory (from ARA) | `fsi_agentinventories` | [ ] | |

**How to confirm:** Navigate to Power Platform admin center → Tables → select table → Properties → Entity Set Name.

### OptionSet Integer Value Confirmation

OptionSet integer values are defined in `scripts/create_mrm_dataverse_schema.py` (source of truth). The values below match that schema and start at 100000000 (Dataverse global option set base). Confirm against the deployed solution before going live.

| Choice Column | Expected Values | Confirmed |
|--------------|-----------------|-----------|
| fsi_cyclestatus | Not Started=100000001, Submitted=100000002, In Progress=100000003, Findings Issued=100000004, Remediated=100000005, Validated=100000006, Rejected=100000007 (option set `fsi_mrm_cyclestatus`, 1-based) | [ ] |
| fsi_severity | Critical=100000001, High=100000002, Medium=100000003, Low=100000004 (option set `fsi_mrm_severity`, 1-based) | [ ] |
| fsi_remediationstatus | Open=100000001, In Progress=100000002, Submitted for Review=100000003, Closed=100000004 (option set `fsi_mrm_remediationstatus`, 1-based) | [ ] |
| fsi_validationstatus | Not Started=100000001, Submitted=100000002, In Progress=100000003, Findings Issued=100000004, Remediated=100000005, Validated=100000006 (option set `fsi_mrm_validationstatus`, 1-based) | [ ] |
| fsi_mrmtier | Tier 1=100000001, Tier 2=100000002, Tier 3=100000003, Tier 4=100000004 (option set `fsi_mrm_mrmtier`, 1-based) | [ ] |
| fsi_mrmstatus | Pending Submission=100000000, Submitted=100000001, Risk Scored=100000002, Validation Scheduled=100000003, In Validation=100000004, Validated=100000005, Conditionally Approved=100000006, Rejected=100000007, Retired=100000008 (option set `fsi_mrm_mrmstatus`, 0-based) | [ ] |
| fsi_compositerating | Critical=100000000, High=100000001, Medium=100000002, Low=100000003 (option set `fsi_mrm_compositerating`, 0-based — note: DIFFERENT BASE from `fsi_severity` which is 1-based) | [ ] |

**How to confirm:** Navigate to Power Platform admin center → Tables → select table → Columns → select Choice column → View options with integer values.

### API Field Confirmation

| API | Field | Expected | Confirmed |
|-----|-------|----------|-----------|
| Power Platform Bots API (2022-03-01-preview) | ownerObjectId | Present in response | [ ] |
| Power Platform Bots API | displayName | Present in response | [ ] |
| Power Platform Bots API | lastModifiedTime | Present in response | [ ] |

### Infrastructure Setup

| Item | Status |
|------|--------|
| SharePoint MRM Governance site created | [ ] |
| "Agent Cards" document library created | [ ] |
| AgentCard-Template.docx deployed to library root | [ ] |
| Metadata columns added to Agent Cards library | [ ] |
| Library permissions configured per docs/sharepoint-setup.md | [ ] |
| Sites.ReadWrite.All granted to Managed Identity | [ ] |
| MRMSiteUrl environment variable set | [ ] |
| MRMAgentCardLibrary environment variable set | [ ] |

### Connection References Bound

| Connection Reference | Connector | Bound |
|---------------------|-----------|-------|
| fsi_cr_dataverse_mrm | Dataverse | [ ] |
| fsi_cr_teams_mrm | Microsoft Teams | [ ] |
| fsi_cr_approvals_mrm | Approvals | [ ] |
| fsi_cr_http_mrm | HTTP with Microsoft Entra ID | [ ] |
| fsi_cr_sharepoint_mrm | SharePoint | [ ] |
| fsi_cr_wordonline_mrm | Word Online (Business) | [ ] |

### Security Configuration

| Item | Status |
|------|--------|
| fsi_mrmcomplianceevent: Delete privilege removed for all roles except System Administrator | [ ] |
| Dataverse Long-Term Retention enabled on fsi_mrmcomplianceevent (7-year policy) | [ ] |
| Alternate key fsi_ModelInventoryUniqueKey status is Active | [ ] |

### Dependency Verification

| Item | Status |
|------|--------|
| agent-registry-automation deployed in same environment | [ ] |
| fsi_agentinventory table accessible via Dataverse Web API | [ ] |
| Test query succeeds: GET fsi_agentinventories?$top=1 | [ ] |

---

## Design Rationale Documentation

### Validation Cadence Rationale

Tier 2 (Enhanced MRM — decision support with human review) and Tier 3 (Standard MRM — information retrieval) share a **Biennial** validation cadence. This is intentional:

- The human-in-the-loop design of Tier 2 reduces autonomous risk exposure to a level comparable with Tier 3 for **scheduling** purposes
- The validation **scope** for Tier 2 remains more rigorous than Tier 3 (full conceptual soundness and ongoing monitoring vs. simplified review)
- Tier 4 (Minimal MRM) uses a **Triennial** cadence — inventory registration and annual review only

Present this rationale to examiners if the shared Tier 2/Tier 3 cadence is questioned. The MRM tier at cycle start is captured in `fsi_validationcycle.fsi_mrmtieratstart` for historical reference.

### Zone Scoring Rationale

`fsi_governancezone` drives **two** of the seven risk scoring factors:

1. **User Population Score** (fsi_score_userpopulation): Zone 3=5, Zone 2=3, Zone 1=1
2. **Regulatory Exposure Score** (fsi_score_regulatoryexposure): Zone 3=5, Zone 2=3, Zone 1=1

This double weighting is intentional:

- Governance zone is the strongest single governance signal available at inventory time
- Zone classification reflects both the breadth of user exposure and the intensity of regulatory examination
- The double weighting means Zone 3 agents start with a 10-point head start (out of 35) toward higher-risk classification
- This design choice is disclosed and documented in `fsi_zoneweightrationale` on every scoring record

Present this rationale to examiners reviewing the scoring matrix. The `fsi_zoneweightrationale` field on every `fsi_mrmriskrating` record provides the per-record documentation.

---

## Post-Activation Monitoring

After setting `IsMRMAutomationEnabled` to `"true"`:

1. Monitor Flow 1 first run — verify agents sync from fsi_agentinventory
2. Verify Flow 2 triggers automatically for new agents — check risk scores are complete (all 7 factors populated)
3. Verify Flow 3 triggers for Tier 1/2 agents — check Teams approval cards arrive
4. Monitor Flow 4 first Monday run — verify monitoring records are created
5. Verify Flow 5 generates Agent Cards — check SharePoint library for documents
6. Review fsi_mrmcomplianceevent for expected event types

---

*This checklist supports institution-specific model risk management programs informed by OCC Bulletin 2026-13 (formerly OCC 2011-12) / Fed SR 26-2 (formerly Fed SR 11-7). Organizations should verify all configurations meet their specific regulatory obligations.*
