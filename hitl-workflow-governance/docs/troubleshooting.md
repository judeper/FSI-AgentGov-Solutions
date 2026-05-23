# Troubleshooting

Common issues and resolution procedures for the HITL Workflow Governance solution.

## Scan Issues

### No HITL Checkpoints Detected

**Symptom:** Scan completes successfully but reports zero checkpoints across all agents.

**Cause:** Agent flows may not use the `advancedapprovals` connector (Human in the Loop). The scan inspects `botcomponent` records for references to the **Request for Information** or **Run a Multistage Approval** actions. If agents use alternative approval patterns (e.g., direct Power Automate approval actions outside the HITL connector), the scan will not detect them.

**Resolution:**
1. Verify at least one agent in the scanned environments uses the Human in the Loop connector (`shared_advancedapprovals`)
2. Open Copilot Studio > Select an agent > Topics > Verify a topic contains a "Request for Information" (`RequestForInformation`) or "Run a Multistage Approval" (`StartAndWaitForAnApprovalProcess`) action node
3. If agents use alternative approval flows, consider extending the scan to cover those patterns
4. Run the scan with `-Verbose` to see which bot components are inspected:
   ```powershell
   .\Test-HitlWorkflowCompliance.ps1 -TenantId <id> -Verbose
   ```

---

### Unable to Enumerate Bot Components

**Symptom:**
```
Error: Insufficient privileges to complete the operation on botcomponent
```

**Cause:** The service principal or user account running the scan lacks read permissions on the `bot` and `botcomponent` Dataverse system tables.

**Resolution:**
1. Open Power Platform admin center > Environment > Settings > Users + permissions
2. Locate the service principal application user (or the scanning user)
3. Assign the **System Administrator** security role, or create a custom role with:
   - Read access on `bot` (Organization scope)
   - Read access on `botcomponent` (Organization scope)
4. Wait 5 minutes for role propagation
5. Re-run the scan

---

### Zone Classification Returns Unknown

**Symptom:** All agents report zone as "Unclassified" or "Unknown" despite environments having zone tags.

**Cause:** The Environment Lifecycle Management (ELM) solution is not deployed, or environment display names do not match the expected naming convention used by `Get-ZoneClassification.ps1`.

**Resolution:**
1. Verify ELM is deployed in the target tenant (check for `fsi_EnvironmentClassification` Dataverse table)
2. If ELM is not deployed, the scan defaults to Zone 3 (most restrictive) — verify this fallback is acceptable
3. If ELM is deployed but zones are not resolving:
   - Check environment display names match the pattern `[Zone X] - Environment Name`
   - Or verify Dataverse classification records exist in the ELM environment
4. Test zone classification independently:
   ```powershell
   . .\scripts\governance\Get-ZoneClassification.ps1
   Get-ZoneClassification -EnvironmentName "Contoso-Production"
   ```

---

## Dataverse Issues

### Dataverse Persistence Fails

**Symptom:**
```
Error: The user is not a member of the organization
```
or
```
Error: Access denied to table fsi_HitlCheckpointResult
```

**Cause:** Connection reference is misconfigured, or the service principal lacks the required Dataverse security role.

**Resolution:**
1. Verify the connection reference `fsi_cr_dataverse_hitlworkflowgovernance` is authenticated
2. In Power Platform admin center, verify the connection user has:
   - **System Administrator** role, or
   - A custom security role with Create/Read/Write on `fsi_HitlCheckpointResult`, `fsi_HitlCheckpointException`, and `fsi_HitlScanRun`
3. For service principal authentication:
   - Verify the application user exists in the target environment
   - Verify the security role is assigned to the application user
4. Test connectivity:
   ```powershell
   # Quick test — list scan runs
   Invoke-RestMethod -Uri "https://yourorg.crm.dynamics.com/api/data/v9.2/fsi_hitlscanruns?`$top=1" `
     -Headers @{ Authorization = "Bearer $token" }
   ```

---

### Choice Columns Not Created

**Symptom:** Tables created but choice columns (zone, severity, violation type) show as text fields.

**Cause:** Global option sets require additional permissions during schema deployment.

**Resolution:**
1. Manually create global option sets in Power Apps maker portal if automated deployment fails
2. Re-run the schema deployment script with `--tables-only` to skip option set creation
3. Or assign Solution.Add permissions to the deployment account
4. Verify option set values match those in `create_hwg_dataverse_schema.py`

---

## Preview Feature Limitations

### RFI Action Schema Changes

**Symptom:** Scan reports unexpected results or fails to parse bot component definitions after a platform update.

**Cause:** The **Request for Information** action entered public preview in July 2025. The `advancedapprovals` connector schema may change before general availability. Microsoft may update action parameter names, add new required fields, or modify the bot component representation.

**Resolution:**
1. Check the [Copilot Studio release notes](https://learn.microsoft.com/en-us/microsoft-copilot-studio/release-notes) for recent connector changes
2. Compare current `botcomponent` content against the expected patterns in `Test-HitlWorkflowCompliance.ps1`
3. If the connector schema has changed:
   - Update the scan script's action detection patterns to match the new schema
   - Test against a known agent with HITL actions configured
4. Open a GitHub issue in this repository if you encounter breaking changes not yet addressed

---

### Multistage Approval Limitations

**Symptom:** Multistage approval actions detected but checkpoint metadata is incomplete.

**Cause:** The **Run a Multistage Approval** action (`StartAndWaitForAnApprovalProcess`) is preview and may not expose all configuration metadata through the `botcomponent` API. Microsoft Learn also lists preview limitations including no attachments, no ALM/import sharing support, no duplicate approver across stages, and Copilot Credits for AI approval stages. Some stage details may only be visible in the Copilot Studio designer.

**Resolution:**
1. For Zone 3 agents, manually verify multistage approval configurations in Copilot Studio
2. Document any metadata gaps in the scan run notes
3. Consider supplementing automated scans with periodic manual reviews for high-risk agents

---

## Evidence Export Issues

### Purview Audit Logs Do Not Show Approval Payloads

**Symptom:** Microsoft Purview audit search shows Copilot Studio authoring, publish, or interaction events but not the full HITL approval decision details.

**Cause:** Copilot Studio audit logging captures events such as bot/component create, update, delete, publish, and interaction events. Full approval decision payloads and reviewer comments must be captured in Dataverse, Approvals records, or another approved evidence store.

**Resolution:**
1. Use Purview audit logs as supporting evidence that agent components changed or interactions occurred.
2. Use `fsi_HitlCheckpointResult`, `fsi_HitlCheckpointException`, and exported evidence manifests as the decision-level evidence source.
3. Verify the retention configuration for Dataverse and exported evidence meets your FINRA Rule 4511(a) and SEC Rule 17a-4 obligations.

---

### Evidence Export Hash Mismatch

**Symptom:** SHA-256 hash in the sidecar file does not match the exported evidence file.

**Cause:** The evidence file was modified after export (e.g., by antivirus software, encoding conversion, or manual editing). Alternatively, an older export script version may have embedded the hash inside the manifest (creating a bootstrapping impossibility).

**Resolution:**
1. Verify you are using the current export script, which writes the hash to a separate sidecar file (`manifest-*.sha256`) instead of embedding it inside the manifest JSON
2. If using the sidecar file, verify with:
   ```bash
   sha256sum -c manifest-<period>.sha256
   ```
3. If files were modified by antivirus or another process after export, re-run the export to regenerate
4. Check file encoding (should be UTF-8 without BOM)

---

## Flow Issues

### Teams Notifications Not Sending

**Symptom:** Flow succeeds but no Teams messages appear in the configured channel.

**Cause:** Teams connector authentication expired, channel/group ID misconfigured, or Teams admin policies block bot messages.

**Resolution:**
1. Verify the Teams connector connection is authenticated (Power Automate > Connections)
2. Check the flow-only settings holding the Teams group/channel GUIDs (stored as Azure Automation variables, secure flow configuration, or the alert flow's bound parameters — these are **not** Dataverse environment variables and are not created by `create_hwg_environment_variables.py`)
3. Verify the channel exists and the flow connection user has access
4. Check Teams admin policies allow bot messages and adaptive card posting
5. Test with a direct chat instead of channel to isolate the issue

---

### HITL-Violation-Alert Not Triggering

**Symptom:** Records added to `fsi_HitlCheckpointResult` but HITL-Violation-Alert flow does not run.

**Cause:** Trigger filter is using the wrong column type — `fsi_severity` is a string in this schema, not a picklist.

**Resolution:**
1. Verify the flow is turned on
2. Check the trigger filter is text-based: `fsi_severity eq 'Critical' or fsi_severity eq 'High'`
3. Severity values are case-sensitive strings (`Critical`, `High`, `Medium`, `Warning`)
4. Manually trigger the flow with a test record to verify

---

### Exception Approval Times Out

**Symptom:** Exception request expires after 14 days with no response.

**Cause:** Approver did not respond within the configured timeout period.

**Resolution:**
1. Verify the flow-only setting holding the approver email/UPN (Azure Automation variable, secure flow configuration, or alert flow parameter — this is **not** a Dataverse environment variable and is not created by `create_hwg_environment_variables.py`) points to an active, monitored mailbox
2. Consider using a distribution group or shared mailbox for approvals
3. Set up a reminder flow that re-notifies the approver at 7 days
4. After timeout, the exception record is automatically set to `fsi_isactive = false` — resubmit if still needed

---

## Performance Issues

### Rate Limiting with Large Tenant Scans

**Symptom:**
```
Error: Number of requests exceeded the limit of 6000 within time span of 300 seconds
```

**Cause:** Tenant has many environments and agents, causing the scan to exceed Dataverse or Power Platform API rate limits.

**Resolution:**
1. Add delays between environment scans:
   ```powershell
   # Add 2-second delay between environments
   Start-Sleep -Seconds 2
   ```
2. Batch environments into groups and scan across multiple runbook executions
3. Use the `-EnvironmentFilter` parameter to scan specific environments per run
4. Enable concurrent processing with throttling (max 5 parallel environment scans)
5. Contact Microsoft support to request rate limit increases for governance workloads

---

### PowerShell Module Version Conflicts

**Symptom:**
```
Error: The term 'Get-AdminPowerAppEnvironment' is not recognized
```
or
```
Error: Method not found: 'Void Microsoft.IdentityModel.Clients.ActiveDirectory...'
```

**Cause:** Conflicting versions of `Microsoft.PowerApps.Administration.PowerShell` or `MSAL.PS` modules installed.

**Resolution:**
1. Check installed module versions:
   ```powershell
   Get-Module -ListAvailable -Name Microsoft.PowerApps.Administration.PowerShell
   Get-Module -ListAvailable -Name MSAL.PS
   ```
2. Remove older versions:
   ```powershell
   Get-Module -ListAvailable -Name Microsoft.PowerApps.Administration.PowerShell |
     Where-Object { $_.Version -lt '2.0' } |
     ForEach-Object { Uninstall-Module -Name $_.Name -RequiredVersion $_.Version -Force }
   ```
3. Install the latest version:
   ```powershell
   Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force -AllowClobber
   Install-Module -Name MSAL.PS -Force -AllowClobber
   ```
4. If running in Azure Automation, update modules through the Automation Account > Modules blade

---

## Recovery Procedures

### Reset Scan Results (Test Environments Only)

For testing or recovery, clear scan results:

```powershell
# WARNING: Deletes all checkpoint results — use only in test environments
$results = Get-CrmRecords -EntityLogicalName fsi_hitlcheckpointresult
foreach ($result in $results.CrmRecords) {
    Remove-CrmRecord -EntityLogicalName fsi_hitlcheckpointresult -Id $result.fsi_hitlcheckpointresultid
}
```

> **Important:** `fsi_HitlScanRun` records are an immutable audit trail that supports compliance with FINRA Rule 4511 and SEC Rule 17a-3/4 recordkeeping requirements. Do not delete scan run records in production environments. If cleanup is needed for testing, delete and recreate the entire test environment instead.

### Reprocess Failed Scan

If a scan fails partway through:

1. Note the `RunId` from the failed scan run record
2. Check which environments were successfully scanned (from `fsi_environmentsscanned`)
3. Re-run the scan — the script generates a new `RunId` and rescans all environments
4. If repeated failures occur on specific environments, use `-EnvironmentFilter` to exclude them and investigate separately

---

## Getting Help

If issues persist:

1. Collect flow run history (last 10 runs) from Power Automate
2. Export error details from the failed flow run
3. Check [Microsoft 365 Service Health](https://admin.microsoft.com/Adminportal/Home#/servicehealth) for platform issues
4. Review [related FSI-AgentGov playbooks](https://github.com/judeper/FSI-AgentGov) for control 2.12, 2.17, and 1.10 guidance
5. Open a GitHub issue with:
   - Solution version
   - Error message and stack trace
   - Flow run history screenshot
   - Environment details (zone, agent count)
