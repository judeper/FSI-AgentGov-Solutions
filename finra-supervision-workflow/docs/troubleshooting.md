# Troubleshooting

Common issues and resolution procedures for the FINRA Supervision Workflow solution.

## Deployment Issues

### Deploy Script Fails with Authentication Error

**Symptom:**
```
Error: AADSTS65001: The user or administrator has not consented to use the application
```

**Cause:** App registration lacks required permissions or admin consent.

**Resolution:**
1. Open Entra ID > App registrations > FSW-Automation-SP
2. Go to API permissions
3. Verify all required permissions are added
4. Click "Grant admin consent for [tenant]"
5. Re-run deploy script

---

### Cannot Create Dataverse Tables

**Symptom:**
```
Error: User does not have Dataverse System Administrator role
```

**Cause:** Deployment account lacks System Administrator role.

**Resolution:**
1. Open Power Platform admin center
2. Navigate to environment > Settings > Users + permissions
3. Add deployment user to System Administrator role
4. Wait 5 minutes for role propagation
5. Re-run deploy script

---

### Choice Columns Not Created

**Symptom:** Tables created but choice columns show as text fields.

**Cause:** Global option sets require additional permissions.

**Resolution:**
1. Manually create global option sets in Power Apps maker portal
2. Re-run deploy script with `--tables-only` flag to skip option set creation
3. Or assign Solution.Add permissions to deployment account

---

## Flow Issues

### IngestFlow Not Picking Up Alerts

**Symptom:** Communication Compliance has alerts, but SupervisionQueue is empty.

**Cause:** Multiple possible causes.

**Resolution Checklist:**
1. Verify flow is turned on
2. Check flow run history for errors
3. Verify Graph API permissions (`SecurityEvents.Read.All`)
4. Check `lastRunTime` in Key Vault isn't in the future
5. Verify alert `alertType` matches filter condition

**Quick Fix:**
```powershell
# Reset lastRunTime to 1 hour ago
az keyvault secret set \
    --vault-name fsw-credentials-kv \
    --name FSW-LastRunTime \
    --value (Get-Date).AddHours(-1).ToString("o")
```

---

### Assignment Flow Fails to Find Supervisor

**Symptom:**
```
Error: No supervisor found for Zone 3, Tier 1
```

**Cause:** SupervisionConfig missing entry or default principal not set.

**Resolution:**
1. Open model-driven app (Supervision Manager)
2. Navigate to Configuration > Supervision Rules
3. Add/update entry for Zone 3, Tier 1
4. Set Default Principal to valid user
5. Save and test

---

### Escalation Flow Not Triggering

**Symptom:** Overdue items not being escalated.

**Cause:** Flow schedule may be paused or SLA calculation incorrect.

**Resolution:**
1. Verify flow is turned on and running hourly
2. Check flow run history for the past 24 hours
3. Verify SLA Due dates are in the past for test items
4. Manually trigger flow to test

**Manual Test:**
1. Create queue item with SLA Due = 1 hour ago
2. Manually run escalation flow
3. Verify item state changes to Escalated

---

### Teams Notifications Not Sending

**Symptom:** Flow succeeds but no Teams messages received.

**Cause:** Teams connector or user configuration issue.

**Resolution:**
1. Verify Teams connector is authenticated
2. Check recipient user has Teams license
3. Verify notification channel exists (if using channel post)
4. Check Teams admin policies allow bot messages
5. Test with direct chat instead of channel

---

## Data Issues

### Queue Items Missing Zone/Tier

**Symptom:** Items created with null Zone or Tier values.

**Cause:** Agent metadata lookup failed.

**Resolution:**
1. Check IngestFlow HTTP action for agent lookup
2. Verify Power Platform API permissions
3. Add fallback logic to set default Zone/Tier
4. Update existing records manually or via bulk update

**Bulk Fix:**
```powershell
# Set default Zone 2, Tier 2 for items missing values
$items = Get-CrmRecords -EntityLogicalName fsi_supervisionqueue -FilterAttribute fsi_zone -FilterOperator null

foreach ($item in $items) {
    Set-CrmRecord -EntityLogicalName fsi_supervisionqueue -Id $item.Id -Fields @{
        fsi_zone = 2
        fsi_tier = 2
    }
}
```

---

### SupervisionLog Has Gaps

**Symptom:** Some actions not appearing in log.

**Cause:** Log creation failing silently in flows.

**Resolution:**
1. Enable "Configure run after" for logging actions
2. Set to run even if previous action fails
3. Add error handling to create error log entry
4. Review flow run history for skipped actions

---

### Duplicate Queue Items

**Symptom:** Same alert creates multiple queue items.

**Cause:** IngestFlow running multiple times for same alert.

**Resolution:**
1. Add duplicate check before creating queue item:
```
Filter: fsi_sourceid eq '@{alert.id}'
If count > 0, skip creation
```
2. Update `lastRunTime` atomically at end of flow
3. Add unique constraint on fsi_sourceid (if possible)

---

## Performance Issues

### Flow Timeout on Large Alert Volume

**Symptom:**
```
Error: Action 'Apply_to_each' exceeded maximum duration
```

**Cause:** Too many alerts to process in single run.

**Resolution:**
1. Add `$top=100` to Graph API query
2. Process in batches
3. Reduce polling interval (process more frequently, fewer items)
4. Enable concurrency in Apply to each (Degree of Parallelism: 20)

---

### Power BI Dashboard Slow

**Symptom:** Dashboard takes >30 seconds to load.

**Cause:** Large data volume, inefficient queries.

**Resolution:**
1. Add date filters to limit data (last 90 days)
2. Create aggregated tables for summary metrics
3. Enable incremental refresh
4. Move to Power BI Premium for larger datasets

---

### Dataverse Query Throttling

**Symptom:**
```
Error: Number of requests exceeded the limit
```

**Cause:** Too many API calls in short period.

**Resolution:**
1. Add delays between API calls
2. Batch requests where possible
3. Cache supervisor list instead of looking up each time
4. Contact Microsoft support to increase limits

---

## Security Issues

### Supervisors See Other Users' Items

**Symptom:** FSW Supervisor can see items assigned to others.

**Cause:** Security role has Organization-level Read access.

**Resolution:**
1. Open Dataverse security role editor
2. Change SupervisionQueue Read from Organization to User
3. Save and test

---

### Cannot Access Queue After Role Assignment

**Symptom:** New supervisor cannot see assigned items.

**Cause:** Role assignment not propagated or cached.

**Resolution:**
1. Wait 15 minutes for propagation
2. Have user sign out and back in
3. Clear browser cache
4. Verify role assignment in Power Platform admin center

---

### Service Principal Cannot Write to Log

**Symptom:**
```
Error: Principal with id [guid] does not have privilege to write
```

**Cause:** FSW Admin role missing from service principal.

**Resolution:**
1. Open Power Platform admin center
2. Navigate to environment > Settings > Application users
3. Find or add service principal application user
4. Assign FSW Admin security role
5. Save and test

---

## Evidence Collection Issues

### Export Script Authentication Failure

**Symptom:**
```
Error: Interactive authentication required
```

**Cause:** Running in non-interactive context without proper credentials.

**Resolution:**
1. Use `--client-id` and `--client-secret` flags for service principal authentication
2. Or run interactively first to cache token
3. Verify token cache location is writable

---

### Export Missing Recent Data

**Symptom:** Export doesn't include items from last few hours.

**Cause:** Dataverse eventual consistency or filter issue.

**Resolution:**
1. Add 1-hour buffer to end date
2. Wait 30 minutes after last activity before export
3. Verify filter syntax in script

---

### SHA-256 Hash Mismatch

**Symptom:** Manifest hash doesn't match file hash.

**Cause:** File modified after export or encoding issue.

**Resolution:**
1. Re-run export to regenerate files and manifest
2. Verify files not modified by antivirus or other process
3. Check file encoding (should be UTF-8)
4. Compare hash algorithms (SHA256 vs SHA-256)

---

## Recovery Procedures

### Reset Queue to Clean State

For testing or recovery, clear all queue items:

```powershell
# WARNING: Deletes all queue items - use only in test environments
$items = Get-CrmRecords -EntityLogicalName fsi_supervisionqueue

foreach ($item in $items) {
    Remove-CrmRecord -EntityLogicalName fsi_supervisionqueue -Id $item.Id
}
```

> **Important:** SupervisionLog records must NOT be deleted. The SupervisionLog table is an immutable audit trail required for SEC 17a-3/4 compliance. Deleting log records would violate recordkeeping requirements and undermine regulatory evidence integrity. If log cleanup is needed in a test environment, delete and recreate the entire test environment instead.

### Reprocess Failed Items

To reprocess items that failed during ingestion:

1. Set `lastRunTime` to before the failure
2. Run IngestFlow manually
3. Monitor for duplicates

### Rollback Configuration Changes

If configuration changes cause issues:

1. Export current SupervisionConfig records
2. Restore from backup or recreate default values
3. Test with single Zone 3 item
4. Gradually enable other zones

---

## Getting Help

If issues persist:

1. Collect flow run history (last 10 runs)
2. Export error details from Power Automate
3. Check Microsoft 365 Service Health
4. Review [related FSI-AgentGov playbooks](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/control-implementations/2.12/troubleshooting.md)
5. Open GitHub issue with details
