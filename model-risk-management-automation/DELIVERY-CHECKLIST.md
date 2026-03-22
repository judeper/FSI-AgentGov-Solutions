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

OptionSet integer values are assigned at deployment time. Confirm each value against the deployed solution and update flow conditions and script parameters.

| Choice Column | Expected Values | Confirmed |
|--------------|-----------------|-----------|
| fsi_cyclestatus | Not Started=1, Submitted=2, In Progress=3, Findings Issued=4, Remediated=5, Validated=6, Rejected=7 | [ ] |
| fsi_severity | Critical=1, High=2, Medium=3, Low=4 | [ ] |
| fsi_remediationstatus | Open=1, In Progress=2, Submitted for Review=3, Closed=4 | [ ] |
| fsi_validationstatus | Not Started=1, Submitted=2, In Progress=3, Findings Issued=4, Remediated=5, Validated=6 | [ ] |
| fsi_mrmtier | Tier 1=1, Tier 2=2, Tier 3=3, Tier 4=4 | [ ] |
| fsi_mrmstatus | Pending Submission=0, Submitted=1, Risk Scored=2, ... (9 values) | [ ] |
| fsi_compositerating | Critical=0, High=1, Medium=2, Low=3 | [ ] |

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

*This checklist supports compliance with OCC 2011-12 / Fed SR 11-7 model risk management requirements. Organizations should verify all configurations meet their specific regulatory obligations.*
