# Flow Configuration

Power Automate flow specifications for the Model Risk Management Automation solution. This document provides step-by-step instructions for manually building all 6 flows in the Power Automate designer.

---

## Flow Overview

| Flow | Trigger | Purpose | Frequency |
|------|---------|---------|-----------|
| **Sync-AgentInventory-ToMRM** | Scheduled | Sync agent inventory into MRM model inventory | Daily (05:00 UTC) |
| **Score-ModelRisk-OnSubmission** | Instant | Apply 7-factor automated risk scoring | On submission or manual |
| **Execute-ValidationWorkflow** | Instant | Orchestrate end-to-end validation lifecycle | On risk scoring or revalidation |
| **Monitor-ModelPerformance-Scheduled** | Scheduled | Weekly performance monitoring and SLA checks | Weekly (Monday 08:00 UTC) |
| **Generate-AgentCard-OnChange** | Instant | Generate SR 11-7 Agent Card document | On new, material change, or validation |
| **Trigger-Revalidation-OnThreshold** | Instant | Revalidation approval workflow | On monitoring breach or material change |

---

## Prerequisites

### Connection References

All flows use connection references deployed by `create_mrm_connection_references.py`. Configure these before building flows.

| Logical Name | Display Name | Connector | Purpose |
|---|---|---|---|
| `fsi_cr_dataverse_mrm` | Dataverse - MRM | Common Data Service | Model inventory CRUD, risk ratings, validation cycles, findings, monitoring, compliance events |
| `fsi_cr_teams_mrm` | Teams - MRM | Microsoft Teams | Risk scoring cards, validation alerts, SLA breach alerts, revalidation requests |
| `fsi_cr_approvals_mrm` | Approvals - MRM | Approvals | Validator assignment approval, revalidation confirmation, examiner alert choices |
| `fsi_cr_http_mrm` | HTTP with Microsoft Entra ID - MRM | HTTP with Microsoft Entra ID | Power Platform Bots API, Graph API user resolution, Entra Agent Registry |
| `fsi_cr_sharepoint_mrm` | SharePoint - MRM | SharePoint Online | Agent Card upload, folder creation, metadata updates |
| `fsi_cr_wordonline_mrm` | Word Online - MRM | Word Online (Business) | Agent Card document generation from template |

### Environment Variables

All flows read configuration from environment variables deployed by `create_mrm_environment_variables.py`. Key variables referenced across flows:

| Variable | Type | Default | Used By |
|----------|------|---------|---------|
| `fsi_MRM_IsMRMAutomationEnabled` | String | `"false"` | All flows — master kill switch |
| `fsi_MRM_IsAgent365LifecycleEnabled` | String | `"false"` | Flow 1 — gates Entra Agent Registry calls |
| `fsi_MRM_GovernanceTeamEmail` | String | — | Flows 1–6 — fallback notification target |
| `fsi_MRM_FlowAdministrators` | String | — | Flows 1, 5 — API failure / fallback alerts |
| `fsi_MRM_EscalationApproverUPN` | String | — | Flow 4 — skip-level approver for SLA breaches |
| `fsi_MRM_DataverseEnvironmentUrl` | String | — | Flow 1 — HTTP calls to Dataverse OData |
| `fsi_MRM_MRMSiteUrl` | String | — | Flow 5 — SharePoint site for Agent Cards |
| `fsi_MRM_MRMAgentCardLibrary` | String | `"Agent Cards"` | Flow 5 — document library name |
| `fsi_MRM_FSI_FRAMEWORK_VERSION` | String | `"FSI-AgentGov-v1.1"` | Flow 5 — framework version tag in Agent Card |
| `fsi_MRM_MaterialChangeTextDiffThreshold` | Decimal | `30` | Flow 1 — business function diff threshold (%) |
| `fsi_MRM_ValidationApproachingDaysLookahead` | Decimal | `30` | Flow 4 — days before due date for reminders |

See `create_mrm_environment_variables.py` for the full list of 27 variables including monitoring thresholds and per-tier validation SLAs.

### Dataverse Tables

All tables are created by `create_mrm_dataverse_schema.py`. Flows reference these entity sets:

| Table | Entity Set | Primary Use |
|-------|-----------|-------------|
| fsi_ModelInventory | `fsi_modelinventories` | Master MRM record per agent |
| fsi_MrmRiskRating | `fsi_mrmriskratings` | Risk scoring evidence |
| fsi_ValidationCycle | `fsi_validationcycles` | End-to-end validation tracking |
| fsi_ValidationFinding | `fsi_validationfindings` | Individual findings from validation |
| fsi_MonitoringRecord | `fsi_monitoringrecords` | Post-validation monitoring results |
| fsi_MrmComplianceEvent | `fsi_mrmcomplianceevents` | Immutable audit log |

> **OptionSet integer values:** The integer values shown in this document (e.g., `100000000` for "Pending Submission") are the values defined in `create_mrm_dataverse_schema.py`. After deployment, verify the actual values in your environment — Dataverse may assign different integers if option sets were created in a different order or merged with existing ones. Always reference `docs/dataverse-schema.md` (generated via `python create_mrm_dataverse_schema.py --output-docs`) as the source of truth.

---

## Flow 1: Sync-AgentInventory-ToMRM

Synchronizes registered agents from the Agent Registry (`fsi_agentinventory`) into the MRM Model Inventory (`fsi_modelinventory`), enriching records with platform and owner data, and detecting material changes that require revalidation.

### Trigger

**Recurrence**
- Frequency: Day
- Interval: 1
- Start time: 05:00 UTC
- Time zone: UTC
- Concurrency Control: On (Degree of Parallelism: 1) — prevents duplicate sync if a run exceeds 24 hours

### Connection References

| Connection Reference | Purpose |
|---------------------|---------|
| `fsi_cr_dataverse_mrm` | Read agent inventory, upsert model inventory, create compliance events |
| `fsi_cr_http_mrm` | Power Platform Bots API enrichment, Graph API owner resolution, Entra Agent Registry cross-reference |
| `fsi_cr_teams_mrm` | API failure alerts to FlowAdministrators |

### Step-by-Step Build Instructions

```
1. Initialize variable: IsMRMEnabled (String)
   - Get environment variable: fsi_MRM_IsMRMAutomationEnabled
   - Condition: IsMRMEnabled == "true"
     - If No: Terminate (Status: Cancelled, Message: "MRM automation disabled")

2. Scope: Verify Agent Inventory Access
   2.1 HTTP - GET fsi_agentinventories?$top=1
       Connection: fsi_cr_dataverse_mrm
       Purpose: Verify table accessibility before processing

   2.2 Configure Run After: If step 2.1 fails
       2.2.1 Create row in fsi_mrmcomplianceevents
             - fsi_eventtype: Inventory Sync Failed
             - fsi_complianceimpact: Critical
             - fsi_eventdetails: "Agent inventory table not accessible"
             - fsi_eventtimestamp: @{utcNow()}
       2.2.2 Send Teams message to FlowAdministrators
             - Subject: "[MRM] Agent Inventory Sync Failed — Table Inaccessible"
             - Body: Error details, timestamp, environment URL
       2.2.3 Terminate (Status: Failed)

3. List rows: Get all registered agents
   Table: fsi_agentinventory (from agent-registry-automation solution)
   Filter: fsi_registrationstatus eq 'Registered'
            and fsi_status in ('Active', 'Under Review')
   Note: Cross-solution dependency — the agent-registry-automation solution
         must be deployed first. If fsi_agentinventory does not exist, step 2
         catches the failure.

4. Apply to each: Process Agent
   Input: Value from step 3

   4.1 Scope: Check Existing Model Inventory Record
       - List rows: fsi_modelinventories
         Filter: fsi_agentid eq '@{items('Apply_to_each')?['fsi_agentid']}'
         Top: 1
       - Initialize variable: IsNewRecord (Boolean)
         Value: @{equals(length(outputs('List_MRM_Records')?['body/value']), 0)}

   4.2 HTTP - Enrich with PPAC Bots API
       Connection: fsi_cr_http_mrm
       Method: GET
       URI: https://api.powerplatform.com/appmanagement/environments/@{agent.environmentid}/bots/@{agent.agentid}?api-version=2022-03-01-preview
       Headers: Authorization: Bearer (from connection)
       Configure Run After: Continue on failure (enrichment is best-effort)

   4.3 HTTP - Resolve owner from Microsoft Graph
       Connection: fsi_cr_http_mrm
       Method: GET
       URI: https://graph.microsoft.com/v1.0/users/@{agent.ownerid}?$select=displayName,mail,userPrincipalName,department
       Configure Run After: Continue on failure

   4.4 Condition: IsAgent365LifecycleEnabled == "true"
       If Yes:
         4.4.1 HTTP - Cross-reference Entra Agent Registry
               Purpose: Retrieve agent-365-lifecycle-governance metadata
               Configure Run After: Continue on failure
       If No: Skip

   4.5 Scope: Material Change Detection (existing records only)
       Condition: IsNewRecord == false
       If Yes (existing record):
         4.5.1 Compare 5 criteria against stored values:
               a. Underlying model changed:
                  @{not(equals(enrichedAgent.modelProvider, existingRecord.fsi_modelprovider))}
               b. Business function >30% diff:
                  Calculate character-level diff percentage of fsi_businessfunction
                  Compare against fsi_MRM_MaterialChangeTextDiffThreshold env var
               c. Data inputs changed:
                  @{not(equals(enrichedAgent.dataInputs, existingRecord.fsi_datainputs))}
               d. Governance zone changed:
                  @{not(equals(agent.zone, existingRecord.fsi_governancezone))}
               e. Owner changed:
                  @{not(equals(agent.ownerid, existingRecord.fsi_ownerupn))}

         4.5.2 Compose: MaterialChangeDetected
               @{or(criterion_a, criterion_b, criterion_c, criterion_d, criterion_e)}

   4.6 Upsert Model Inventory Record
       Action: Update or create row (Dataverse)
       Table: fsi_modelinventories
       Alternate Key: fsi_agentid (match on agent ID)
       Values:
         - fsi_agentname: @{agent.displayName}
         - fsi_agentid: @{agent.agentid}
         - fsi_environmentid: @{agent.environmentid}
         - fsi_environmentname: @{agent.environmentname}
         - fsi_governancezone: @{agent.zone}
         - fsi_ownerupn: @{graphUser.userPrincipalName}
         - fsi_ownerdisplayname: @{graphUser.displayName}
         - fsi_ownerdepartment: @{graphUser.department}
         - fsi_modelprovider: @{enrichedAgent.modelProvider} (if available)
         - fsi_datainputs: @{enrichedAgent.dataInputs} (if available)
       Note: Preserve MRM-managed fields on update (do NOT overwrite):
             fsi_mrmtier, fsi_currentriskrating, fsi_validationcadence,
             fsi_validationstatus, fsi_mrmstatus (except as set below)

   4.7 Condition: IsNewRecord == true
       If Yes:
         4.7.1 Update row: fsi_modelinventories
               - fsi_firstsubmitted: @{utcNow()}
               - fsi_mrmstatus: Pending Submission
         4.7.2 Create row: fsi_mrmcomplianceevents
               - fsi_eventtype: Inventory Submitted
               - fsi_complianceimpact: Low
         4.7.3 Run child flow: Score-ModelRisk-OnSubmission
               Pass: Model Inventory record ID

   4.8 Condition: MaterialChangeDetected == true (existing records)
       If Yes:
         4.8.1 Update row: fsi_modelinventories
               - fsi_materialchangeflag: true
               - fsi_materialchangedesc: Compose criteria summary
         4.8.2 Run child flow: Generate-AgentCard-OnChange
               Pass: Model Inventory record ID
         4.8.3 Condition: MRM Tier in (Tier 1, Tier 2)
               If Yes: Run child flow: Trigger-Revalidation-OnThreshold
                        Pass: Record ID, Reason: "Material change detected during sync"
         4.8.4 Create row: fsi_mrmcomplianceevents
               - fsi_eventtype: Material Change Detected
               - fsi_complianceimpact: High
               - fsi_eventdetails: JSON with all 5 change criteria results
```

### Error Handling

- **Agent inventory inaccessible (step 2):** Creates Critical compliance event, alerts FlowAdministrators, terminates — no partial sync
- **PPAC Bots API failure (step 4.2):** Continue processing with available data; enrichment fields left null
- **Graph API failure (step 4.3):** Continue; owner fields populated from agent inventory source data
- **Individual agent failure (within step 4):** Log error to compliance events, continue processing remaining agents
- **All errors:** Configure `Scope` run-after to catch failures and log to `fsi_mrmcomplianceevents`

### Related Environment Variables

| Variable | Step | Purpose |
|----------|------|---------|
| `fsi_MRM_IsMRMAutomationEnabled` | 1 | Feature flag gate |
| `fsi_MRM_IsAgent365LifecycleEnabled` | 4.4 | Entra Agent Registry gate |
| `fsi_MRM_FlowAdministrators` | 2.2.2 | API failure notification target |
| `fsi_MRM_MaterialChangeTextDiffThreshold` | 4.5.1b | Business function diff threshold |
| `fsi_MRM_DataverseEnvironmentUrl` | 2.1 | Dataverse HTTP endpoint |

---

## Flow 2: Score-ModelRisk-OnSubmission

Applies a 7-factor automated risk scoring algorithm to a model inventory record, assigns an MRM tier and validation cadence, and creates an immutable risk rating record.

### Trigger

**Instant (Manual trigger)**
- Input: ModelInventoryRecordId (Text, required)
- Called by: Flow 1 (new record at step 4.7.3) or manually by MRM officer

### Connection References

| Connection Reference | Purpose |
|---------------------|---------|
| `fsi_cr_dataverse_mrm` | Read model inventory, create risk rating, update inventory, mark previous ratings, create compliance events |
| `fsi_cr_teams_mrm` | Risk scoring notification to MRM officer |

### Step-by-Step Build Instructions

```
1. Initialize variable: IsMRMEnabled (String)
   - Get environment variable: fsi_MRM_IsMRMAutomationEnabled
   - Condition: IsMRMEnabled == "true"
     - If No: Terminate (Status: Cancelled)

2. Get row: fsi_modelinventories(@{triggerBody()['ModelInventoryRecordId']})
   Expand: All columns needed for scoring

3. Scope: 7-Factor Automated Risk Scoring

   3.1 Decision Impact Score (based on fsi_decisionoutputtype)
       Compose:
       @{if(equals(model.fsi_decisionoutputtype, 'Quantitative Estimate'), 5,
         if(equals(model.fsi_decisionoutputtype, 'Decision Support'), 3,
         if(equals(model.fsi_decisionoutputtype, 'Information Retrieval'), 2,
         1)))}

       Note: Use OptionSet integer values for comparison in production:
       Quantitative Estimate = 100000000, Decision Support = 100000001,
       Information Retrieval = 100000002, Productivity = 100000003

   3.2 Data Sensitivity Score (keyword analysis of fsi_datainputs)
       Compose:
       @{if(or(
           contains(toLower(model.fsi_datainputs), 'pii'),
           contains(toLower(model.fsi_datainputs), 'ssn'),
           contains(toLower(model.fsi_datainputs), 'social security'),
           contains(toLower(model.fsi_datainputs), 'account number'),
           contains(toLower(model.fsi_datainputs), 'credit'),
           contains(toLower(model.fsi_datainputs), 'financial')), 5,
         if(or(
           contains(toLower(model.fsi_datainputs), 'customer'),
           contains(toLower(model.fsi_datainputs), 'client')), 3,
         if(or(
           contains(toLower(model.fsi_datainputs), 'internal'),
           contains(toLower(model.fsi_datainputs), 'policy')), 1,
         3)))}

       Note: Default score is 3 when no keywords match. Append review note
       to rationale: "Data sensitivity scored by keyword match — manual
       review recommended to verify classification."

   3.3 User Population Score (based on fsi_governancezone)
       @{if(equals(model.fsi_governancezone, 'Zone 3'), 5,
         if(equals(model.fsi_governancezone, 'Zone 2'), 3, 1))}

   3.4 Model Complexity Score (based on fsi_modelprovider)
       @{if(or(
           equals(model.fsi_modelprovider, 'Custom'),
           equals(model.fsi_modelprovider, 'Third-Party')), 5,
         if(and(
           equals(model.fsi_modelprovider, 'Microsoft'),
           contains(toLower(model.fsi_underlyingmodel), 'llm')), 4,
         if(or(
           equals(model.fsi_modelprovider, 'Anthropic'),
           equals(model.fsi_modelprovider, 'OpenAI')), 4,
         if(and(
           equals(model.fsi_modelprovider, 'Microsoft'),
           not(contains(toLower(model.fsi_underlyingmodel), 'llm'))), 2,
         3))))}

   3.5 Explainability Score (based on fsi_decisionoutputtype)
       @{if(equals(model.fsi_decisionoutputtype, 'Quantitative Estimate'), 5,
         if(equals(model.fsi_decisionoutputtype, 'Decision Support'), 4,
         if(equals(model.fsi_decisionoutputtype, 'Information Retrieval'), 2,
         1)))}

   3.6 Regulatory Exposure Score (based on fsi_governancezone)
       @{if(equals(model.fsi_governancezone, 'Zone 3'), 5,
         if(equals(model.fsi_governancezone, 'Zone 2'), 3, 1))}

   3.7 Change Frequency Score
       - List rows: fsi_mrmcomplianceevents
         Filter: fsi_modelinventoryid eq '@{model.id}'
                 and fsi_eventtype in (Material Change Detected, Risk Rating Changed)
                 and fsi_eventtimestamp ge @{addDays(utcNow(), -90)}
       - Count results
       @{if(greater(changeCount, 4), 5,
         if(greaterOrEquals(changeCount, 2), 3, 1))}

4. Calculate Composite Score and Rating
   4.1 Compose: TotalScore
       @{add(decisionImpact, dataSensitivity, userPopulation,
             modelComplexity, explainability, regulatoryExposure,
             changeFrequency)}
       Range: 7 (minimum) to 35 (maximum)

   4.2 Compose: CompositeRating
       @{if(greaterOrEquals(TotalScore, 29), 'Critical',
         if(greaterOrEquals(TotalScore, 22), 'High',
         if(greaterOrEquals(TotalScore, 15), 'Medium', 'Low')))}

       | Total Score | Composite Rating |
       |-------------|-----------------|
       | 29–35 | Critical |
       | 22–28 | High |
       | 15–21 | Medium |
       | 7–14 | Low |

5. Assign MRM Tier
   Logic (evaluated in order — first match wins):
   5.1 IF DecisionOutputType == Quantitative Estimate → Tier 1 (always)
   5.2 IF CompositeRating in (Critical, High) → Tier 1
   5.3 IF CompositeRating == Medium AND DecisionOutputType == Decision Support → Tier 2
   5.4 IF CompositeRating == Medium → Tier 3
   5.5 ELSE → Tier 4

   | Condition | MRM Tier |
   |-----------|----------|
   | Quantitative Estimate (any rating) | Tier 1 - Full MRM |
   | Critical or High rating | Tier 1 - Full MRM |
   | Medium + Decision Support | Tier 2 - Enhanced MRM |
   | Medium (other output types) | Tier 3 - Standard MRM |
   | Low rating | Tier 4 - Minimal MRM |

6. Assign Validation Cadence
   @{if(equals(mrmTier, 'Tier 1'), 'Annual',
     if(or(equals(mrmTier, 'Tier 2'), equals(mrmTier, 'Tier 3')), 'Biennial',
     'Triennial'))}

   | MRM Tier | Cadence | Months |
   |----------|---------|--------|
   | Tier 1 | Annual | 12 |
   | Tier 2 | Biennial | 24 |
   | Tier 3 | Biennial | 24 |
   | Tier 4 | Triennial | 36 |

7. Mark Previous Ratings as Not Current
   - List rows: fsi_mrmriskratings
     Filter: fsi_modelinventoryid eq '@{model.id}' and fsi_iscurrent eq true
   - Apply to each: Update row
     - fsi_iscurrent: false

8. Create Risk Rating Record
   Create row: fsi_mrmriskratings
   - fsi_modelinventoryid: @{model.id} (lookup)
   - fsi_compositerating: @{CompositeRating}
   - fsi_totalscore: @{TotalScore}
   - fsi_score_decisionimpact: @{decisionImpact}
   - fsi_score_datasensitivity: @{dataSensitivity}
   - fsi_score_userpopulation: @{userPopulation}
   - fsi_score_complexity: @{modelComplexity}
   - fsi_score_explainability: @{explainability}
   - fsi_score_regulatoryexposure: @{regulatoryExposure}
   - fsi_score_changefrequency: @{changeFrequency}
   - fsi_iscurrent: true
   - fsi_scoringdate: @{utcNow()}
   - fsi_scoringrationale: Compose min 100 chars including all 7 factor scores,
     composite calculation, tier assignment reason, and zone weight rationale
   - fsi_zoneweightrationale: "Zone @{zone}: User Population score=@{up},
     Regulatory Exposure score=@{re}. Zone-based factors contribute
     @{add(up,re)} of @{TotalScore} total (@{div(mul(add(up,re),100),TotalScore)}%)."

9. Update Model Inventory
   Update row: fsi_modelinventories
   - fsi_currentriskrating: @{CompositeRating}
   - fsi_mrmtier: @{mrmTier}
   - fsi_validationcadence: @{cadence}
   - fsi_nextvalidationdue: @{addMonths(utcNow(), cadenceMonths)}
   - fsi_mrmstatus: Risk Scored

10. Send Teams Notification
    Connection: fsi_cr_teams_mrm
    To: Model owner (fsi_ownerupn) and MRM officer (fsi_mrmofficerupn,
        fallback to fsi_MRM_GovernanceTeamEmail)
    Subject: "[MRM] Risk Scored — @{model.fsi_agentname}"
    Body: Composite rating, total score, tier assignment, next validation due

11. Condition: MRM Tier in (Tier 1, Tier 2)
    If Yes: Run child flow: Execute-ValidationWorkflow
            Pass: Model Inventory record ID, Type: Initial

12. Create Compliance Event
    Create row: fsi_mrmcomplianceevents
    - fsi_eventtype: Risk Scored
    - fsi_complianceimpact: @{if(equals(CompositeRating, 'Critical'), 'High',
        if(equals(CompositeRating, 'High'), 'Medium', 'Low'))}
    - fsi_eventdetails: JSON with all 7 scores, total, rating, tier
```

### Error Handling

- On model inventory read failure (step 2): Terminate with error — cannot score without source data
- On Dataverse write failure (steps 7–9): Retry 3 times with exponential backoff; on persistent failure, send alert to FlowAdministrators
- On Teams notification failure (step 10): Log to compliance events, continue — scoring is the critical path
- All scoring calculations use deterministic logic with no external API calls — failures are limited to Dataverse operations

### Related Environment Variables

| Variable | Step | Purpose |
|----------|------|---------|
| `fsi_MRM_IsMRMAutomationEnabled` | 1 | Feature flag gate |
| `fsi_MRM_GovernanceTeamEmail` | 10 | Fallback notification target |

---

## Flow 3: Execute-ValidationWorkflow

Orchestrates the end-to-end validation lifecycle: validator assignment with dual independence check, findings issuance, remediation tracking, and cycle closure. This flow manages the longest-running process in the MRM system — a single validation cycle may span weeks to months.

### Trigger

**Instant (Manual trigger)**
- Inputs:
  - ModelInventoryRecordId (Text, required)
  - ValidationType (Text, required) — "Initial", "Periodic", "Material Change", or "Ad Hoc"
- Called by: Flow 2 (Tier 1/2 at step 11), Flow 6 (revalidation at step 4), or manually by MRM officer

### Connection References

| Connection Reference | Purpose |
|---------------------|---------|
| `fsi_cr_dataverse_mrm` | Validation cycle CRUD, findings, model inventory updates, compliance events |
| `fsi_cr_teams_mrm` | Validator assignment notifications, findings alerts, remediation notifications |
| `fsi_cr_approvals_mrm` | Validator assignment approval, cycle closure decisions |
| `fsi_cr_http_mrm` | Graph API for validator profile resolution and department lookup |

### Step-by-Step Build Instructions

```
1. Initialize variable: IsMRMEnabled (String)
   - Get environment variable: fsi_MRM_IsMRMAutomationEnabled
   - Condition: IsMRMEnabled == "true"
     - If No: Terminate (Status: Cancelled)

2. Scope: Check for Existing Open Validation Cycle
   - List rows: fsi_validationcycles
     Filter: fsi_modelinventoryid eq '@{ModelInventoryRecordId}'
             and fsi_cyclestatus ne 100000006    // not Validated
             and fsi_cyclestatus ne 100000007    // not Rejected
   - Condition: length(results) > 0
     If Yes:
       - Create row: fsi_mrmcomplianceevents
         - fsi_eventtype: Validation Cycle Opened
         - fsi_complianceimpact: Low
         - fsi_eventdetails: "Duplicate cycle request blocked —
           existing open cycle @{existingCycle.id}"
       - Terminate (Status: Cancelled, Message: "Open cycle exists")

3. Get row: fsi_modelinventories(@{ModelInventoryRecordId})
   Expand: Current risk rating (fsi_mrmriskratings, filter: fsi_iscurrent eq true)

4. Create Validation Cycle
   Create row: fsi_validationcycles
   - fsi_modelinventoryid: @{ModelInventoryRecordId} (lookup)
   - fsi_validationtype: @{ValidationType}
   - fsi_mrmtieratstart: @{model.fsi_mrmtier}
   - fsi_ratingatstart: @{model.fsi_currentriskrating}
   - fsi_cyclestatus: Not Started
   - fsi_cycleopeneddate: @{utcNow()}

5. Update Model Inventory Status
   Update row: fsi_modelinventories
   - fsi_mrmstatus: Validation Scheduled
   - fsi_validationstatus: Submitted

6. STEP A — Validator Assignment
   6.1 Send approval (Start and wait for an approval)
       Connection: fsi_cr_approvals_mrm
       Type: Approve/Reject - First to respond
       Title: "[MRM] Assign Validator — @{model.fsi_agentname}"
       Assigned to: MRM officer (fsi_mrmofficerupn, fallback to
                    fsi_MRM_GovernanceTeamEmail)
       Details: Agent name, tier, risk rating, validation type
       Item link: Deep link to model inventory record
       Custom response: Include "Validator UPN" text field

   6.2 Condition: Approval outcome == "Approve"
       If Reject:
         - Update cycle: fsi_cyclestatus = Rejected
         - Log compliance event, terminate
       If Approve:
         6.2.1 Parse validator UPN from approval response

         6.2.2 HTTP - Resolve validator profile from Graph
               Connection: fsi_cr_http_mrm
               Method: GET
               URI: https://graph.microsoft.com/v1.0/users/@{validatorUPN}
                    ?$select=userPrincipalName,department,displayName

         6.2.3 Dual Independence Check
               Condition A: validatorUPN != model.fsi_ownerupn
               Condition B: validatorDepartment != model.fsi_ownerdepartment

               If EITHER fails:
                 - Respond to approval: "Rejected — validator independence
                   check failed: [specific reason]"
                 - Specific reasons:
                   * "Validator UPN matches model owner UPN"
                   * "Validator department '@{dept}' matches owner department"
                 - Return to step 6.1 (loop — send new approval request)
                 Note: To prevent infinite loops, add a retry counter
                 (max 3 attempts). After 3 failed independence checks,
                 alert fsi_MRM_EscalationApproverUPN and terminate.

               If BOTH pass:
                 6.2.4 Update cycle:
                       - fsi_validatorupn: @{validatorUPN}
                       - fsi_validatordisplayname: @{validatorDisplayName}
                       - fsi_cyclestatus: In Progress
                       - fsi_assigneddate: @{utcNow()}
                 6.2.5 Update model inventory:
                       - fsi_validationstatus: In Progress
                       - fsi_mrmstatus: In Validation
                 6.2.6 Send Teams notification to validator
                       Subject: "[MRM] Validation Assignment —
                                @{model.fsi_agentname}"
                       Body: Agent details, tier, risk rating,
                             SLA deadline, validation workbench link
                 6.2.7 Create compliance event: Validation Assigned

7. STEP B — Findings Issued (triggered by Validation Workbench submission)
   Note: This step runs when the validator submits findings via the
   model-driven app. Implement as a separate flow triggered by
   "When a row is added" on fsi_validationfindings, OR use a
   "When a row is modified" trigger on fsi_validationcycles when
   fsi_cyclestatus changes to Findings Issued.

   7.1 Update cycle:
       - fsi_findingsissueddate: @{utcNow()}
       - fsi_cyclestatus: Findings Issued

   7.2 Count critical findings
       - List rows: fsi_validationfindings
         Filter: fsi_validationcycleid eq '@{cycle.id}'
                 and fsi_severity eq 100000001  // Critical

   7.3 Condition: Critical findings count > 0
       If Yes:
         - Send urgent Teams alert to MRM officer and
           fsi_MRM_EscalationApproverUPN
         - Subject: "[MRM] CRITICAL Findings — @{model.fsi_agentname}"

   7.4 Send Teams notification to model owner (fsi_ownerupn)
       Subject: "[MRM] Validation Findings Issued —
                @{model.fsi_agentname}"
       Body: Finding count by severity, remediation SLA deadline,
             MRM Submission Portal link

   7.5 Update model inventory: fsi_validationstatus = Findings Issued

8. STEP C — Remediation Submitted (triggered by MRM Submission Portal)
   Note: Implement as trigger on fsi_validationcycles when
   fsi_cyclestatus changes to Remediated.

   8.1 Update cycle:
       - fsi_remediationsubmitteddate: @{utcNow()}
       - fsi_cyclestatus: Remediated

   8.2 Update model inventory: fsi_validationstatus = Remediated

   8.3 Send Teams notification to validator
       Subject: "[MRM] Remediation Submitted for Review —
                @{model.fsi_agentname}"

9. STEP D — Validator Closes Cycle
   Note: Implement as trigger on fsi_validationcycles when
   fsi_validationoutcome is set (not null).

   9.1 Condition: ValidationOutcome in (Validated - No Findings,
       Validated - Findings Resolved, Conditionally Approved)

       If Yes (Validated/Conditionally Approved):
         9.1.1 Update cycle:
               - fsi_cyclecloseddate: @{utcNow()}
               - fsi_cyclestatus: Validated
         9.1.2 Update model inventory:
               - fsi_validationstatus: Validated
               - fsi_mrmstatus: @{if(outcome == 'Conditionally Approved',
                   'Conditionally Approved', 'Validated')}
               - fsi_lastvalidateddate: @{utcNow()}
               - fsi_materialchangeflag: false  // reset
               - fsi_nextvalidationdue: @{addMonths(utcNow(), cadenceMonths)}
         9.1.3 Run child flow: Generate-AgentCard-OnChange
               Pass: Model Inventory record ID (validation completed)
         9.1.4 Create compliance event: Validation Completed

       If No (Rejected):
         9.1.5 Update cycle:
               - fsi_cyclecloseddate: @{utcNow()}
               - fsi_cyclestatus: Rejected
               Note: Do NOT modify any other fields on the rejected
               cycle record — preserve it as-is for audit trail
         9.1.6 Update model inventory:
               - fsi_validationstatus: Not Started
               - fsi_mrmstatus: Rejected
               Note: Reset validationstatus to Not Started so a new
               cycle can be opened. Do NOT reset materialchangeflag.
         9.1.7 Create compliance event: Validation Rejected
               - fsi_complianceimpact: High
```

### Error Handling

- **Approval timeout (step 6.1):** Approvals connector has a 30-day default timeout. Configure timeout in approval action settings. On timeout, log compliance event and alert fsi_MRM_EscalationApproverUPN
- **Graph API failure (step 6.2.2):** Cannot proceed without independence check — retry 3 times, then alert FlowAdministrators. Do not assign validator without independence verification
- **Independence check loop (step 6.2.3):** Maximum 3 retry attempts. After 3 failures, escalate to fsi_MRM_EscalationApproverUPN
- **Findings/Remediation steps (7–9):** These are separate trigger-based flows. Each should have its own scope-based error handler that logs failures to fsi_mrmcomplianceevents

### Related Environment Variables

| Variable | Step | Purpose |
|----------|------|---------|
| `fsi_MRM_IsMRMAutomationEnabled` | 1 | Feature flag gate |
| `fsi_MRM_GovernanceTeamEmail` | 6.1 | Fallback approval recipient |
| `fsi_MRM_EscalationApproverUPN` | 6.2.3, 7.3 | Independence check escalation, critical findings alert |
| `fsi_MRM_ValidationSLA_Tier1_Assignment` | 6.2.6 | Tier 1 assignment SLA deadline |
| `fsi_MRM_ValidationSLA_Tier1_Findings` | 7.4 | Tier 1 findings delivery SLA |
| `fsi_MRM_ValidationSLA_Tier1_Remediation` | 8.3 | Tier 1 remediation SLA |
| `fsi_MRM_ValidationSLA_Tier2_*` | 6–8 | Tier 2 SLA deadlines |
| `fsi_MRM_ValidationSLA_Tier3_*` | 6–8 | Tier 3 SLA deadlines |

---

## Flow 4: Monitor-ModelPerformance-Scheduled

Performs weekly performance monitoring across all validated models, checks monitoring thresholds, detects SLA breaches in active validation cycles, and sends approaching-validation reminders.

### Trigger

**Recurrence**
- Frequency: Week
- Interval: 1
- Start time: Monday 08:00 UTC
- Time zone: UTC
- Concurrency Control: On (Degree of Parallelism: 1)

### Connection References

| Connection Reference | Purpose |
|---------------------|---------|
| `fsi_cr_dataverse_mrm` | Read model inventory, create monitoring records, read validation cycles, create compliance events |
| `fsi_cr_teams_mrm` | Monitoring alerts, SLA breach notifications, approaching-validation reminders |
| `fsi_cr_approvals_mrm` | Tier 1 MRM officer choice card (Monitor vs. Trigger Revalidation) |

### Step-by-Step Build Instructions

```
1. Initialize variable: IsMRMEnabled (String)
   - Get environment variable: fsi_MRM_IsMRMAutomationEnabled
   - Condition: IsMRMEnabled == "true"
     - If No: Terminate (Status: Cancelled)

2. Initialize monitoring threshold variables
   Get environment variables:
   - ErrorRate_Warning, ErrorRate_Revalidation
   - EscalationRate_Warning, EscalationRate_Revalidation
   - OutOfScope_Warning, OutOfScope_Revalidation
   - ValidationApproachingDaysLookahead

3. List rows: Get models for monitoring
   Table: fsi_modelinventories
   Filter: fsi_mrmstatus in (100000005, 100000006)    // Validated, Conditionally Approved
            and fsi_mrmtier in (100000001, 100000002, 100000003)  // Tier 1, 2, 3
   Note: Tier 4 (Minimal MRM) is excluded from active monitoring

4. Apply to each: Monitor Model
   Input: Value from step 3

   4.1 Create Monitoring Record (always — even with no data)
       Create row: fsi_monitoringrecords
       - fsi_modelinventoryid: @{model.id}
       - fsi_monitoringdate: @{utcNow()}
       - fsi_datasource: @{if(dataAvailable, sourceType, 'Not Available')}
       - fsi_errorrate: @{errorRate} (null if unavailable)
       - fsi_escalationrate: @{escalationRate} (null if unavailable)
       - fsi_outofscopecount: @{outOfScopeCount} (null if unavailable)
       Note: Always create a record — null metrics indicate data
       unavailability, which is itself a monitoring signal.

   4.2 Scope: Evaluate Thresholds
       Note: Only evaluate if metrics are not null

       4.2.1 Condition: Error Rate >= Revalidation threshold
             If Yes: Set ThresholdBreached = "Revalidation"
             If No:
               Condition: Error Rate >= Warning threshold
               If Yes: Set ThresholdBreached = "Warning"

       4.2.2 Condition: Escalation Rate >= Revalidation threshold
             If Yes: Set ThresholdBreached = "Revalidation"
             (similar pattern for Warning)

       4.2.3 Condition: Out-of-Scope Count >= Revalidation threshold
             If Yes: Set ThresholdBreached = "Revalidation"
             (similar pattern for Warning)

   4.3 Condition: ThresholdBreached == "Warning" AND Tier == Tier 1
       If Yes:
         4.3.1 Send approval (Start and wait for an approval)
               Connection: fsi_cr_approvals_mrm
               Type: Custom Responses
               Title: "[MRM] Performance Alert — @{model.fsi_agentname}"
               Assigned to: MRM officer
               Responses: "Continue Monitoring", "Trigger Revalidation"
               Details: Metric values, threshold values, model details

         4.3.2 Condition: Response == "Trigger Revalidation"
               If Yes: Run child flow: Trigger-Revalidation-OnThreshold

   4.4 Condition: ThresholdBreached == "Revalidation"
       If Yes: Run child flow: Trigger-Revalidation-OnThreshold
              Pass: Record ID, Reason: "Monitoring threshold breached:
                    @{breachedMetric} = @{value} (threshold: @{threshold})"

   4.5 Update monitoring record with threshold evaluation results
       - fsi_thresholdbreached: @{ThresholdBreached} (or null)

5. Scope: SLA Breach Detection
   5.1 List rows: fsi_validationcycles
       Filter: fsi_cyclestatus in (100000001, 100000002, 100000003,
               100000004, 100000005)
               // Not Started, Submitted, In Progress, Findings Issued, Remediated

   5.2 Apply to each: Check SLA
       5.2.1 Get tier-specific SLA from environment variables
             Based on fsi_mrmtieratstart

       5.2.2 Check Assignment SLA
             Condition: fsi_assigneddate is null
                        AND dateDiff('Day', fsi_cycleopeneddate, utcNow())
                        > AssignmentSLA
             Note: Null-safe — a null assignment date when the deadline
             has passed IS a breach (validator was never assigned)
             If Yes: Log SLA breach, notify MRM officer and
                     fsi_MRM_EscalationApproverUPN

       5.2.3 Check Findings SLA
             Condition: fsi_findingsissueddate is null
                        AND fsi_assigneddate is not null
                        AND dateDiff('Day', fsi_assigneddate, utcNow())
                        > FindingsSLA
             If Yes: Log SLA breach, notify validator and MRM officer

       5.2.4 Check Remediation SLA
             Condition: fsi_remediationsubmitteddate is null
                        AND fsi_findingsissueddate is not null
                        AND dateDiff('Day', fsi_findingsissueddate, utcNow())
                        > RemediationSLA
             If Yes: Log SLA breach, notify model owner and MRM officer

6. Scope: Approaching Validation Due Dates
   6.1 List rows: fsi_modelinventories
       Filter: fsi_nextvalidationdue le @{addDays(utcNow(), LookaheadDays)}
               and fsi_nextvalidationdue ge @{utcNow()}
               and fsi_mrmstatus in (100000005, 100000006)  // Validated, Cond. Approved

   6.2 Apply to each: Send Reminder
       - Send Teams notification to model owner and MRM officer
         Subject: "[MRM] Validation Due in @{daysDiff} Days —
                  @{model.fsi_agentname}"
         Body: Next validation due date, current tier, last validated date
```

### Error Handling

- **Empty monitoring data (step 4.1):** Always create monitoring record even with null metrics — null values are a valid monitoring signal
- **Approval timeout (step 4.3.1):** Default to "Continue Monitoring" if approval times out after 7 days
- **SLA date arithmetic (step 5):** All date comparisons must be null-safe. A null date field combined with a passed deadline constitutes a breach, not an error
- **Per-model failure (step 4):** Log error to compliance events, continue processing remaining models

### Related Environment Variables

| Variable | Step | Purpose |
|----------|------|---------|
| `fsi_MRM_IsMRMAutomationEnabled` | 1 | Feature flag gate |
| `fsi_MRM_MonitoringThreshold_ErrorRate_Warning` | 4.2.1 | Error rate warning threshold |
| `fsi_MRM_MonitoringThreshold_ErrorRate_Revalidation` | 4.2.1 | Error rate revalidation threshold |
| `fsi_MRM_MonitoringThreshold_EscalationRate_Warning` | 4.2.2 | Escalation rate warning threshold |
| `fsi_MRM_MonitoringThreshold_EscalationRate_Revalidation` | 4.2.2 | Escalation rate revalidation threshold |
| `fsi_MRM_MonitoringThreshold_OutOfScope_Warning` | 4.2.3 | Out-of-scope warning threshold |
| `fsi_MRM_MonitoringThreshold_OutOfScope_Revalidation` | 4.2.3 | Out-of-scope revalidation threshold |
| `fsi_MRM_ValidationSLA_Tier1_Assignment` | 5.2.2 | Tier 1 assignment SLA (business days) |
| `fsi_MRM_ValidationSLA_Tier1_Findings` | 5.2.3 | Tier 1 findings SLA (business days) |
| `fsi_MRM_ValidationSLA_Tier1_Remediation` | 5.2.4 | Tier 1 remediation SLA (business days) |
| `fsi_MRM_ValidationSLA_Tier2_Assignment` | 5.2.2 | Tier 2 assignment SLA |
| `fsi_MRM_ValidationSLA_Tier2_Findings` | 5.2.3 | Tier 2 findings SLA |
| `fsi_MRM_ValidationSLA_Tier2_Remediation` | 5.2.4 | Tier 2 remediation SLA |
| `fsi_MRM_ValidationSLA_Tier3_Assignment` | 5.2.2 | Tier 3 assignment SLA |
| `fsi_MRM_ValidationSLA_Tier3_Findings` | 5.2.3 | Tier 3 findings SLA |
| `fsi_MRM_ValidationSLA_Tier3_Remediation` | 5.2.4 | Tier 3 remediation SLA |
| `fsi_MRM_EscalationApproverUPN` | 5.2.2 | SLA breach escalation target |
| `fsi_MRM_ValidationApproachingDaysLookahead` | 6.1 | Days before due date for reminders |

---

## Flow 5: Generate-AgentCard-OnChange

Generates an SR 11-7 Agent Card document containing model risk evidence across all three pillars (Development, Validation, Governance). Supports Word document generation with a JSON fallback when the Word Online connector is unavailable.

### Trigger

**Instant (Manual trigger)**
- Input: ModelInventoryRecordId (Text, required)
- Called by: Flow 1 (new record at step 4.7, material change at step 4.8.2), Flow 3 (validation completed at step 9.1.3), or manually by MRM officer

### Connection References

| Connection Reference | Purpose |
|---------------------|---------|
| `fsi_cr_dataverse_mrm` | Read model inventory, risk rating, validation cycle; update Agent Card metadata; create compliance events |
| `fsi_cr_wordonline_mrm` | PRIMARY — Populate Word template and convert to document |
| `fsi_cr_sharepoint_mrm` | Upload Agent Card to document library, create folders, update metadata |
| `fsi_cr_teams_mrm` | Fallback notification to FlowAdministrators when Word fails |

### Step-by-Step Build Instructions

```
1. Initialize variable: IsMRMEnabled (String)
   - Get environment variable: fsi_MRM_IsMRMAutomationEnabled
   - Condition: IsMRMEnabled == "true"
     - If No: Terminate (Status: Cancelled)

2. Scope: Gather Agent Card Data
   2.1 Get row: fsi_modelinventories(@{ModelInventoryRecordId})

   2.2 List rows: fsi_mrmriskratings
       Filter: fsi_modelinventoryid eq '@{model.id}'
               and fsi_iscurrent eq true
       Top: 1

   2.3 List rows: fsi_validationcycles
       Filter: fsi_modelinventoryid eq '@{model.id}'
               and fsi_cyclestatus eq 100000006  // Validated
       Order by: fsi_cyclecloseddate desc
       Top: 1

3. Determine Agent Card Version
   3.1 Get current version from model inventory (fsi_agentcardversion)

   3.2 Compose: NewVersion
       Logic:
       - If fsi_agentcardversion is null or empty → "v1.0"
         (new record, first Agent Card)
       - If trigger source is "Validation Completed" → major increment
         (e.g., v1.0 → v2.0, v2.1 → v3.0)
       - If first-time Critical rating → major increment
       - Else → minor increment (e.g., v1.0 → v1.1, v2.0 → v2.1)

       Expression example for major increment:
       @{concat('v', string(add(int(first(split(
         replace(model.fsi_agentcardversion, 'v', ''), '.'))), 1)), '.0')}

4. Compose Agent Card JSON
   Compose action with all SR 11-7 pillar evidence fields:
   {
     "metadata": {
       "cardVersion": "@{NewVersion}",
       "generatedDate": "@{utcNow()}",
       "frameworkVersion": "@{env.fsi_MRM_FSI_FRAMEWORK_VERSION}",
       "generatedBy": "MRM Automation"
     },
     "modelIdentification": {
       "agentName": "@{model.fsi_agentname}",
       "agentId": "@{model.fsi_agentid}",
       "environmentName": "@{model.fsi_environmentname}",
       "governanceZone": "@{model.fsi_governancezone}",
       "mrmTier": "@{model.fsi_mrmtier}",
       "modelProvider": "@{model.fsi_modelprovider}",
       "decisionOutputType": "@{model.fsi_decisionoutputtype}",
       "owner": "@{model.fsi_ownerdisplayname}",
       "ownerDepartment": "@{model.fsi_ownerdepartment}"
     },
     "pillar1_Development": {
       "businessFunction": "@{model.fsi_businessfunction}",
       "dataInputs": "@{model.fsi_datainputs}",
       "modelProvider": "@{model.fsi_modelprovider}",
       "stochasticBehaviorAcknowledgment": "This agent uses a large
         language model (LLM) that produces non-deterministic outputs.
         Identical inputs may yield different responses across
         invocations. Validation and monitoring account for this
         inherent variability.",
       "limitations": "@{model.fsi_limitations}"
     },
     "pillar2_Validation": {
       "riskRating": "@{rating.fsi_compositerating}",
       "totalScore": @{rating.fsi_totalscore},
       "scoringDimensions": {
         "decisionImpact": @{rating.fsi_score_decisionimpact},
         "dataSensitivity": @{rating.fsi_score_datasensitivity},
         "userPopulation": @{rating.fsi_score_userpopulation},
         "modelComplexity": @{rating.fsi_score_complexity},
         "explainability": @{rating.fsi_score_explainability},
         "regulatoryExposure": @{rating.fsi_score_regulatoryexposure},
         "changeFrequency": @{rating.fsi_score_changefrequency}
       },
       "lastValidatedDate": "@{model.fsi_lastvalidateddate}",
       "validationOutcome": "@{cycle.fsi_validationoutcome}",
       "validatorName": "@{cycle.fsi_validatordisplayname}",
       "validationCadence": "@{model.fsi_validationcadence}",
       "nextValidationDue": "@{model.fsi_nextvalidationdue}"
     },
     "pillar3_Governance": {
       "mrmStatus": "@{model.fsi_mrmstatus}",
       "firstSubmitted": "@{model.fsi_firstsubmitted}",
       "materialChangeFlag": @{model.fsi_materialchangeflag},
       "complianceEventCount": @{complianceEventCount}
     }
   }

5. Scope: PRIMARY — Word Document Generation
   5.1 Word Online - Populate a Microsoft Word template
       Connection: fsi_cr_wordonline_mrm
       Location: @{env.fsi_MRM_MRMSiteUrl}
       Document Library: @{env.fsi_MRM_MRMAgentCardLibrary}
       File: /Templates/AgentCard-Template.docx
       Map Agent Card JSON fields to template content controls

   5.2 Create file: Upload generated document to SharePoint
       Connection: fsi_cr_sharepoint_mrm
       Site Address: @{env.fsi_MRM_MRMSiteUrl}
       Folder Path: /@{env.fsi_MRM_MRMAgentCardLibrary}/@{model.fsi_agentid}
       File Name: AgentCard-@{model.fsi_agentid}-@{NewVersion}.docx
       File Content: @{outputs('Populate_Word_Template')?['body']}

   5.3 Set AgentCardFormat = "Word"

6. Scope: FALLBACK — JSON File Upload
   Configure Run After: Run only if step 5 fails

   6.1 Create file: Upload JSON to SharePoint
       Connection: fsi_cr_sharepoint_mrm
       Site Address: @{env.fsi_MRM_MRMSiteUrl}
       Folder Path: /@{env.fsi_MRM_MRMAgentCardLibrary}/@{model.fsi_agentid}
       File Name: AgentCard-@{model.fsi_agentid}-@{NewVersion}.json
       File Content: @{outputs('Compose_AgentCard_JSON')}

   6.2 Set AgentCardFormat = "JSON"

   6.3 Create row: fsi_mrmcomplianceevents
       - fsi_eventtype: Agent Card Fallback Used
       - fsi_complianceimpact: Medium
       - fsi_eventdetails: "Word Online connector failed —
         Agent Card generated as JSON. Error: @{result('Word_Template')}"

   6.4 Send Teams notification to FlowAdministrators
       Subject: "[MRM] Agent Card Fallback — @{model.fsi_agentname}"
       Body: Word connector error, JSON file location

7. Update Model Inventory
   Update row: fsi_modelinventories
   - fsi_agentcardversion: @{NewVersion}
   - fsi_agentcardurl: @{uploadedFileUrl}
   - fsi_agentcardformat: @{AgentCardFormat}
   - fsi_agentcardgenerateddate: @{utcNow()}

8. Create Compliance Event
   Create row: fsi_mrmcomplianceevents
   - fsi_eventtype: Agent Card Generated
   - fsi_complianceimpact: None
   - fsi_eventdetails: "Version @{NewVersion}, format: @{AgentCardFormat}"
```

### Error Handling

- **Word Online failure (step 5):** Falls back to JSON upload at step 6. Word Online connector may fail if the template file is missing, the connector license is unavailable, or the document library does not exist. The JSON fallback provides equivalent data for audit purposes
- **SharePoint folder missing:** The "Create file" action auto-creates subfolders in SharePoint Online. If the document library itself does not exist, both primary and fallback paths will fail — verify `fsi_MRM_MRMAgentCardLibrary` exists before enabling automation
- **Both Word and JSON fail:** The step 6 scope has its own error handler that alerts FlowAdministrators. The compliance event is logged regardless

### Related Environment Variables

| Variable | Step | Purpose |
|----------|------|---------|
| `fsi_MRM_IsMRMAutomationEnabled` | 1 | Feature flag gate |
| `fsi_MRM_MRMSiteUrl` | 5.1, 5.2, 6.1 | SharePoint site URL |
| `fsi_MRM_MRMAgentCardLibrary` | 5.1, 5.2, 6.1 | Document library name |
| `fsi_MRM_FSI_FRAMEWORK_VERSION` | 4 | Framework version tag in card metadata |
| `fsi_MRM_FlowAdministrators` | 6.4 | Fallback notification target |

---

## Flow 6: Trigger-Revalidation-OnThreshold

Sends an approval request to the MRM officer when a monitoring threshold is breached or a material change is detected on a Tier 1/2 model. On approval, triggers Flow 3 (Execute-ValidationWorkflow) with type "Material Change".

### Trigger

**Instant (Manual trigger)**
- Inputs:
  - ModelInventoryRecordId (Text, required)
  - RevalidationReason (Text, required) — e.g., "Monitoring threshold breached: ErrorRate = 18% (threshold: 15%)" or "Material change detected during sync"
- Called by: Flow 4 (monitoring breach at step 4.4), Flow 1 (material change on Tier 1/2 at step 4.8.3), or manually by MRM officer

### Connection References

| Connection Reference | Purpose |
|---------------------|---------|
| `fsi_cr_dataverse_mrm` | Read model inventory, check for open cycles, create compliance events |
| `fsi_cr_teams_mrm` | Revalidation notification |
| `fsi_cr_approvals_mrm` | MRM officer approval for revalidation |

### Step-by-Step Build Instructions

```
1. Initialize variable: IsMRMEnabled (String)
   - Get environment variable: fsi_MRM_IsMRMAutomationEnabled
   - Condition: IsMRMEnabled == "true"
     - If No: Terminate (Status: Cancelled)

2. Get row: fsi_modelinventories(@{ModelInventoryRecordId})
   Expand: Current risk rating

3. Scope: Check for Existing Open Validation Cycle
   - List rows: fsi_validationcycles
     Filter: fsi_modelinventoryid eq '@{ModelInventoryRecordId}'
             and fsi_cyclestatus ne 100000006    // not Validated
             and fsi_cyclestatus ne 100000007    // not Rejected
   - Condition: length(results) > 0
     If Yes:
       - Create row: fsi_mrmcomplianceevents
         - fsi_eventtype: Revalidation Triggered
         - fsi_complianceimpact: Low
         - fsi_eventdetails: "Revalidation request suppressed —
           existing open cycle @{existingCycle.id}"
       - Terminate (Status: Cancelled,
         Message: "Open validation cycle exists — revalidation deferred")

4. Send Approval to MRM Officer
   Send approval (Start and wait for an approval)
   Connection: fsi_cr_approvals_mrm
   Type: Approve/Reject - First to respond
   Title: "[MRM] Revalidation Request — @{model.fsi_agentname}"
   Assigned to: MRM officer (fsi_mrmofficerupn,
                fallback to fsi_MRM_GovernanceTeamEmail)
   Details:
     - Reason: @{RevalidationReason}
     - Agent: @{model.fsi_agentname}
     - Current Tier: @{model.fsi_mrmtier}
     - Current Rating: @{model.fsi_currentriskrating}
     - Last Validated: @{model.fsi_lastvalidateddate}
     - Next Due: @{model.fsi_nextvalidationdue}
     - Material Change Flag: @{model.fsi_materialchangeflag}
   Item link: Deep link to model inventory record

5. Condition: Approval outcome == "Approve"
   5.1 If Approve:
       5.1.1 Run child flow: Execute-ValidationWorkflow
             Pass: ModelInventoryRecordId, ValidationType: "Material Change"

       5.1.2 Create row: fsi_mrmcomplianceevents
             - fsi_eventtype: Revalidation Triggered
             - fsi_complianceimpact: Medium
             - fsi_eventdetails: "Revalidation approved by @{approver}.
               Reason: @{RevalidationReason}"

   5.2 If Reject:
       5.2.1 Create row: fsi_mrmcomplianceevents
             - fsi_eventtype: Revalidation Triggered
             - fsi_complianceimpact: Low
             - fsi_eventdetails: "Revalidation deferred by @{approver}.
               Reason: @{RevalidationReason}. Rejection comment:
               @{approval.comments}"
             Note: The materialchangeflag on fsi_modelinventory is NOT
             reset on rejection. It persists until the next successful
             validation cycle closes (Flow 3 step 9.1.2). This means
             subsequent sync runs (Flow 1) will continue detecting
             the material change and may re-trigger this flow.

       5.2.2 Send Teams notification
             To: fsi_MRM_GovernanceTeamEmail
             Subject: "[MRM] Revalidation Deferred — @{model.fsi_agentname}"
             Body: Rejection reason, approver comments, material change
                   flag status, next scheduled validation date
```

### Error Handling

- **Approval timeout (step 4):** Default to "Reject" on 14-day timeout. Log deferral compliance event. The materialchangeflag persists, so the next monitoring cycle (Flow 4) or inventory sync (Flow 1) will re-trigger revalidation
- **Child flow failure (step 5.1.1):** Log error to compliance events with impact "High". The approval was granted but validation could not start — this requires manual intervention by FlowAdministrators
- **Open cycle check failure (step 3):** If Dataverse query fails, do NOT proceed with approval — terminate with error to prevent duplicate cycles

### Related Environment Variables

| Variable | Step | Purpose |
|----------|------|---------|
| `fsi_MRM_IsMRMAutomationEnabled` | 1 | Feature flag gate |
| `fsi_MRM_GovernanceTeamEmail` | 4, 5.2.2 | Fallback approval recipient, deferral notification |

---

## Cross-Flow Dependencies

```
Flow 1 (Sync)
  ├──→ Flow 2 (Score) ── new records
  ├──→ Flow 5 (Agent Card) ── material changes
  └──→ Flow 6 (Revalidation) ── material change on Tier 1/2
            └──→ Flow 3 (Validation) ── on approval

Flow 2 (Score)
  └──→ Flow 3 (Validation) ── Tier 1/2 auto-trigger

Flow 3 (Validation)
  └──→ Flow 5 (Agent Card) ── validation completed

Flow 4 (Monitor)
  └──→ Flow 6 (Revalidation) ── threshold breach
            └──→ Flow 3 (Validation) ── on approval
```

---

## Deployment Order

Deploy and test flows in this order due to child flow dependencies:

| Order | Flow | Reason |
|-------|------|--------|
| 1 | Generate-AgentCard-OnChange (Flow 5) | No child flow dependencies |
| 2 | Execute-ValidationWorkflow (Flow 3) | Calls Flow 5 |
| 3 | Score-ModelRisk-OnSubmission (Flow 2) | Calls Flow 3 |
| 4 | Trigger-Revalidation-OnThreshold (Flow 6) | Calls Flow 3 |
| 5 | Monitor-ModelPerformance-Scheduled (Flow 4) | Calls Flow 6 |
| 6 | Sync-AgentInventory-ToMRM (Flow 1) | Calls Flows 2, 5, 6 |

> **Important:** Set `fsi_MRM_IsMRMAutomationEnabled` to `"false"` during deployment. Enable it only after all 6 flows are deployed, connection references are configured, and environment variables are set. This prevents partial execution during staged deployment.

---

## Testing Checklist

- [ ] Feature flag gate: All flows terminate cleanly when `fsi_MRM_IsMRMAutomationEnabled` = `"false"`
- [ ] Flow 1: New agent creates model inventory record with status "Pending Submission"
- [ ] Flow 1: Material change detection triggers Agent Card and revalidation for Tier 1/2
- [ ] Flow 1: API failures (PPAC, Graph) do not block sync — enrichment is best-effort
- [ ] Flow 2: 7-factor scoring produces correct composite rating across all tier boundaries
- [ ] Flow 2: Tier 1/2 auto-triggers validation workflow
- [ ] Flow 3: Dual independence check rejects same-UPN and same-department validators
- [ ] Flow 3: Duplicate cycle detection prevents concurrent validation cycles
- [ ] Flow 3: Rejected validation resets validationstatus to Not Started
- [ ] Flow 4: Monitoring records created even with null metrics
- [ ] Flow 4: SLA breach detection handles null assignment dates correctly
- [ ] Flow 4: Approaching validation reminders sent within lookahead window
- [ ] Flow 5: Word document generated successfully from template
- [ ] Flow 5: JSON fallback activates when Word connector fails
- [ ] Flow 5: Version numbering increments correctly (major vs. minor)
- [ ] Flow 6: Revalidation deferred when open cycle exists
- [ ] Flow 6: Material change flag persists after rejection
- [ ] Compliance events logged for all significant state transitions

---

## Known Limitations

### Business Day Calculation

SLA environment variables are specified in business days, but Power Automate's `addDays()` function counts calendar days. For accurate business day calculation, implement a custom expression that accounts for weekends, or use a helper flow that queries a Dataverse holiday calendar table. The current implementation uses calendar days as an approximation — actual SLA enforcement should account for this difference.

### Approval Connector Timeout

The Power Automate Approvals connector has a default timeout of 30 days. Validation cycles that span longer than 30 days require either:
- Configuring extended timeout in the approval action settings
- Splitting Flow 3 into multiple trigger-based sub-flows (Steps A–D) rather than a single long-running flow

### Pagination on Large Inventories

All `List rows` actions use Power Automate's default pagination settings. Environments with more than 5,000 model inventory records should enable pagination in action settings (`Settings` → `Pagination` → `On`, Threshold: 100,000) to avoid silent result truncation.

### Word Template Dependency

Flow 5 requires a pre-deployed Word template at `/Templates/AgentCard-Template.docx` in the Agent Card Library. The template must contain content controls mapped to the Agent Card JSON fields. If the template is missing or malformed, the Word path fails silently and the JSON fallback activates.

---

*Model Risk Management Automation v1.0.0*
