# Troubleshooting

This guide covers common issues encountered during deployment and operation of the Model Risk Management Automation solution.

## Common Issues

### OptionSet Integer Value Mismatches

**Symptom:** OData filter queries in flows or scripts return unexpected results or no results.

**Cause:** OptionSet integer values are assigned at deployment time by Dataverse and may differ from expected defaults. For example, `fsi_mrmtier` may expect `0` for Tier 1 but the deployed environment assigns `100000000`.

**Resolution:**

1. Navigate to **Power Platform Admin Center** → **Tables** → select the affected table
2. Open the Choice column → note the integer value assigned to each option
3. Update flow conditions and script parameters with the confirmed integer values
4. Document confirmed values in DELIVERY-CHECKLIST.md

> **Tip:** Run the schema script with `--output-docs` to regenerate `dataverse-schema.md`, which lists expected OptionSet values. Compare these with deployed values.

---

### Entity Set Name Mismatch

**Symptom:** Dataverse API queries return `404 Not Found` errors.

**Cause:** Dataverse auto-generates entity set names (plural forms) that may differ from expected names, especially if tables are imported in a non-standard order or if publisher prefixes conflict.

**Resolution:**

1. Navigate to **Power Platform Admin Center** → **Tables**
2. Open table properties → note the **Entity Set Name** (plural name)
3. Expected entity set names:

| Table | Expected Entity Set Name |
|-------|-------------------------|
| `fsi_modelinventory` | `fsi_modelinventories` |
| `fsi_mrmriskrating` | `fsi_mrmriskratings` |
| `fsi_validationcycle` | `fsi_validationcycles` |
| `fsi_validationfinding` | `fsi_validationfindings` |
| `fsi_monitoringrecord` | `fsi_monitoringrecords` |
| `fsi_mrmcomplianceevent` | `fsi_mrmcomplianceevents` |

4. If actual names differ, update flows and scripts with the confirmed entity set names

---

### Word Online Connector Failure

**Symptom:** Flow 5 falls back to JSON format for all Agent Cards instead of generating Word documents.

**Cause:** The Word Online connector requires a valid template file deployed to the correct SharePoint location with appropriate permissions.

**Resolution:**

1. Verify `AgentCard-Template.docx` exists in the **Agent Cards** library root (not inside an agent subfolder)
2. Confirm `Sites.ReadWrite.All` permission is granted to the Managed Identity
3. Test the Word Online connector action independently in a new test flow
4. Check connector status in **Power Automate** → **Connections** — re-authenticate if status is "Error"
5. Verify the template contains valid content controls (Developer tab → Design Mode)

> **Note:** The JSON fallback is a designed safety mechanism — Agent Cards are still created in `.json` format. Check `fsi_agentcardformat` on the inventory record to confirm which format was used.

---

### Alternate Key Not Active

**Symptom:** Upsert operations in Flow 1 fail with `"Entity key not found"` or `"Alternate key not valid"` error.

**Cause:** Alternate keys can take several minutes to activate after creation. The key must be in **Active** status before upsert operations work.

**Resolution:**

1. Navigate to **Power Platform Admin Center** → **Tables** → **Model Inventory** → **Keys**
2. Check the status of `fsi_ModelInventoryUniqueKey`
3. If status is **Inactive** or **Creating**, wait 5–10 minutes and refresh the page
4. If status remains inactive after 15 minutes, delete and recreate the key
5. Do not activate Flow 1 until the key status is **Active**

---

### Validator Independence Check Fails Repeatedly

**Symptom:** Flow 3 rejects all validator assignments, logging independence check failures.

**Cause:** The dual AND independence check requires both conditions to pass:

- Validator UPN must differ from `fsi_ownerupn`
- Validator department (resolved via Graph API) must differ from `fsi_ownerdepartment`

**Resolution:**

1. Verify the proposed validator's UPN is different from `fsi_ownerupn` on the model inventory record
2. Verify the validator's department (from Graph API `User.Read.All`) differs from `fsi_ownerdepartment`
3. Both conditions must pass — a validator from the same department is rejected even with a different UPN
4. If `fsi_ownerdepartment` is null or empty, resolve it first:
   - Run Flow 1 to re-sync the agent record (Flow 1 populates department from Graph API)
   - Or manually update `fsi_ownerdepartment` on the inventory record
5. If the organization structure does not support cross-department validation, document the exception and consider adjusting the independence check logic

---

### SLA Breach Detection Not Working

**Symptom:** Flow 4 does not detect overdue validation phases even when deadlines have passed.

**Cause:** SLA calculation depends on correctly configured environment variables and populated date fields.

**Resolution:**

1. Verify the following environment variables are set with integer day values:
   - `ValidationSLA_Tier1_Assignment`, `ValidationSLA_Tier1_Review`, `ValidationSLA_Tier1_Completion`
   - `ValidationSLA_Tier2_Assignment`, `ValidationSLA_Tier2_Review`, `ValidationSLA_Tier2_Completion`
   - `ValidationSLA_Tier3_Assignment`, `ValidationSLA_Tier3_Review`, `ValidationSLA_Tier3_Completion`
2. Check that `fsi_submitteddate` is populated on the validation cycle record
3. For assignment SLA breaches: Flow 4 handles null `fsi_assigneddate` — if the assignment date is null and the deadline has passed, it is treated as a breach
4. Confirm the Flow 4 recurrence trigger is configured for **Monday at 08:00 UTC**
5. Check the flow run history for errors in the SLA calculation actions

---

### Dataverse Long-Term Retention Not Configured

**Symptom:** `fsi_mrmcomplianceevent` records may be purged before the 7-year regulatory retention period required for Fed SR 11-7 and OCC 2011-12 audit trail obligations.

**Resolution:**

1. Navigate to **Power Platform Admin Center** → **Environments** → select environment → **Settings**
2. Enable **Long-Term Retention** on the `fsi_mrmcomplianceevent` table
3. Configure a **7-year retention policy** to support regulatory record-keeping requirements
4. This step cannot be automated via solution XML — it requires manual configuration post-deployment
5. Document completion in DELIVERY-CHECKLIST.md

> **Important:** Without Long-Term Retention, Dataverse default retention policies apply. Organizations should verify that their retention configuration meets specific regulatory obligations for their jurisdiction.

---

## Flow-Specific Troubleshooting

### Flow 1 — Sync-AgentInventory-ToMRM

| Issue | Diagnostic Steps |
|-------|-----------------|
| "Inventory Sync Failed" compliance event logged | Check that `fsi_agentinventory` table is accessible and that `agent-registry-automation` is deployed and running |
| Agents not appearing in MRM inventory | Verify filter conditions — Flow 1 syncs only agents with `fsi_registrationstatus = "Registered"` and `fsi_lifecyclestatus` in (`Active`, `Under Review`) |
| Duplicate records created | Verify the alternate key `fsi_ModelInventoryUniqueKey` is active (see Alternate Key section above) |
| Agent 365 cross-reference not populating | Confirm `IsAgent365LifecycleEnabled = "true"` and `AgentRegistry.Read.All` permission is granted |

### Flow 2 — Score-ModelRisk-OnSubmission

| Issue | Diagnostic Steps |
|-------|-----------------|
| Scoring halts with null factor alert | Any null factor score causes Flow 2 to halt and notify `FlowAdministrators` — check data completeness on the model inventory record |
| Default data sensitivity score of 3 | This is expected behavior — a review note is included. Verify the data sensitivity value is appropriate for the agent |
| Composite score appears incorrect | Verify the weighting formula in the flow matches expected weights for each risk factor |

### Flow 3 — Execute-ValidationWorkflow

| Issue | Diagnostic Steps |
|-------|-----------------|
| Flow terminates immediately | Duplicate trigger protection — if an open cycle (status: Submitted, In Progress, or Assigned) already exists for the agent, Flow 3 terminates. Check for stale cycles |
| Rejected cycle cannot be restarted | Rejected cycles are permanently closed. A new cycle must be initiated via a new Flow 3 trigger (status change or manual trigger) |
| Approval notifications not received | Verify Microsoft Teams is available and Approvals is provisioned. Check the approver's Teams activity feed |

### Flow 4 — Monitor-ModelPerformance-Scheduled

| Issue | Diagnostic Steps |
|-------|-----------------|
| Monitoring records created with no data | Expected behavior when telemetry is unavailable — `fsi_datasource = "Not Available"` indicates no App Insights data was found for the agent |
| 30-day lookahead reminders not sent | Verify the Teams channel and `FlowAdministrators` group are configured. Check that `fsi_nextvalidationdue` is populated |
| Flow runs but creates no records | Verify the flow's agent filter — it processes only agents with `fsi_mrmstatus` in active states |

### Flow 5 — Generate-AgentCard-OnChange

| Issue | Diagnostic Steps |
|-------|-----------------|
| All Agent Cards generated as JSON | Word Online connector failure — see the Word Online Connector section above |
| Version number incorrect | Validation completion triggers a major version increment; material changes trigger a minor version increment. Check the trigger event type |
| Agent Card not generated | Verify the trigger condition — Flow 5 fires on validation status change or material change flag. Check that `IsMRMAutomationEnabled = "true"` |

### Flow 6 — Trigger-Revalidation-OnThreshold

| Issue | Diagnostic Steps |
|-------|-----------------|
| Deferral does not clear the material change flag | This is by design — `fsi_materialchangeflag` persists until a new validation cycle completes. Deferral only postpones the revalidation trigger |
| Deferral not appearing in audit trail | Deferral is logged as a compliance event (event type: `RevalidationDeferred`). Check `fsi_mrmcomplianceevent` for the record |
| Revalidation triggered immediately after deferral | Check the deferral period configuration. If the threshold breach persists past the deferral window, a new trigger fires |

## Diagnostic Queries

### Check MRM Inventory Status

```
GET {org}.crm.dynamics.com/api/data/v9.2/fsi_modelinventories?$select=fsi_modelid,fsi_mrmstatus,fsi_mrmtier,fsi_validationstatus&$orderby=fsi_modelid
```

### Find Agents Missing Risk Scores

```
GET {org}.crm.dynamics.com/api/data/v9.2/fsi_modelinventories?$filter=fsi_currentriskrating eq null and fsi_mrmstatus eq 100000001&$select=fsi_modelid,fsi_modelname
```

### List Open Validation Cycles

```
GET {org}.crm.dynamics.com/api/data/v9.2/fsi_validationcycles?$filter=fsi_cyclestatus ne 100000006 and fsi_cyclestatus ne 100000007&$select=fsi_cycleid,fsi_modelid,fsi_cyclestatus,fsi_submitteddate
```

### Recent Compliance Events

```
GET {org}.crm.dynamics.com/api/data/v9.2/fsi_mrmcomplianceevents?$orderby=fsi_eventtimestamp desc&$top=20&$select=fsi_eventtype,fsi_modelid,fsi_eventdetails,fsi_eventtimestamp
```

## Getting Help

If issues persist after following this guide:

1. Review flow run history in **Power Automate** → **My Flows** → select flow → **Run History**
2. Check Dataverse system jobs for background operation failures
3. Verify all environment variables match the expected values in the deployment guide
4. Consult DELIVERY-CHECKLIST.md to confirm all deployment steps were completed
