# Troubleshooting Guide

Common issues and resolutions for the Scope Drift Monitor.

---

## Detection Issues

### No Violations Detected

**Symptoms:** SDM-DriftDetector runs without errors but creates no violations.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| No out-of-scope access occurred | Expected behavior - no violations to detect |
| Agent has no baseline defined | Create baseline with `New-AgentBaseline.ps1` or manually |
| Audit logging not enabled | Enable Unified Audit Log in Microsoft 365 |
| Wrong lookback window | Extend lookback in flow configuration |
| Office 365 Management API subscription inactive | Verify subscription is active (see below) |

**Verify audit subscription:**

```powershell
# Check subscription status
$token = Get-AccessToken -Scope "https://manage.office.com/.default"
$headers = @{ "Authorization" = "Bearer $token" }
$uri = "https://manage.office.com/api/v1.0/$TenantId/activity/feed/subscriptions/list"
Invoke-RestMethod -Uri $uri -Headers $headers
```

### Agent Not Matched to Baseline

**Symptoms:** Violations created with "No Baseline Defined" type.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Agent ID mismatch | Verify `fsi_agentid` matches Copilot Studio agent ID |
| Environment ID mismatch | Verify `fsi_environmentid` matches agent's environment |
| Baseline status not Active | Set `fsi_status` to 10002 (Active) |

**Verify agent ID:**

1. Open Copilot Studio > Select agent > **Settings** > **General**
2. Copy the Agent ID (GUID format)
3. Compare with `fsi_agentid` in Dataverse

### Office 365 Management API Errors

**Symptoms:** Flow fails with 401 or 403 errors.

**Resolution:**

1. Verify app registration has `ActivityFeed.Read` permission
2. Grant admin consent for the permission
3. Verify E5 or E5 Compliance license is assigned
4. Check audit log retention settings

**Common errors:**

| Error | Cause | Fix |
|-------|-------|-----|
| `401 Unauthorized` | Token expired or invalid | Re-authenticate connection |
| `403 Forbidden` | Missing permissions | Grant admin consent |
| `AF20024` | Subscription not started | Start subscription (see flow) |
| `AF20010` | Content not ready | Wait and retry (transient) |

---

## Alert Issues

### Teams Alerts Not Appearing

**Symptoms:** Violations created but no Teams adaptive card posted.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Wrong Team/Channel ID | Verify environment variables |
| Connection not authorized | Re-authorize Teams connection |
| Bot blocked in channel | Ensure Flow bot can post |
| Channel archived | Use active channel |

**Verify Teams IDs:**

```powershell
# Get Team ID from link
# Right-click team > Get link to team
# Example: https://teams.microsoft.com/l/team/...?groupId=XXXX
# The groupId parameter is the Team ID

# Get Channel ID from link
# Right-click channel > Get link to channel
# The channelId parameter is URL-encoded
```

### Email Notifications Not Received

**Symptoms:** Violations created but no email received.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Invalid recipient email | Verify owner email in Dataverse |
| Connection not authorized | Re-authorize Outlook connection |
| Email in spam/junk | Check spam folder |
| Mailbox full | Clear mailbox space |

**Check email action result:**

1. Open flow run history
2. Expand **Send Email Notification** action
3. Review outputs for error messages

### Duplicate Alerts

**Symptoms:** Multiple alerts for the same violation.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Duplicate violation records | SDM-DriftDetector includes audit-event-level deduplication; verify it is working |
| Flow retry on failure | Check flow run history for retries |
| Multiple trigger instances | Reduce detection frequency |

---

## Approval Issues

### Approval Not Received

**Symptoms:** Expansion request created but approver doesn't receive approval.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Wrong approver email | Verify `fsi_SDM_SecurityTeamEmail` |
| Approvals app not installed | Install Power Automate Approvals app |
| Connection not authorized | Re-authorize Approvals connection |
| Shared mailbox not enabled | Use individual mailbox or enable shared mailbox |

**Verify Approvals setup:**

1. Navigate to **flow.microsoft.com** > **Action items** > **Approvals**
2. Check if pending approvals appear
3. Alternatively, check **Outlook** > **Approvals** add-in

### Approval Timeout

**Symptoms:** Request status stays "Pending" after 7 days.

**Resolution:**

- Default timeout is 7 days
- After timeout, the flow automatically sets the request to Timed Out and notifies the requestor
- To resubmit, create a new expansion request

**To change timeout:**

1. Open SDM-ExpansionProcessor flow
2. Select **Start Approval** action
3. Modify the **limit/timeout** property (ISO 8601 format: `P7D` = 7 days)

### Scope Not Updated After Approval

**Symptoms:** Request approved but agent scope unchanged.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Update action failed | Check flow run history for errors |
| Invalid JSON in scope field | Verify existing scope has valid JSON array |
| Resource already in scope | No change needed (idempotent) |
| Dataverse connection error | Re-authorize connection |

**Verify scope update:**

1. Open flow run history
2. Expand **Update_Agent_Scope_List** action
3. Review inputs and outputs
4. Check Dataverse record directly

---

## Approver Lookup Fails

**Symptoms:** Expansion request approved or denied, but the request status remains "Under Review" and an admin notification email is sent.

**Background:**

The SDM-ExpansionProcessor flow binds `fsi_securityapprovedby` using `/systemusers(@{responder/id})` from the Approvals connector response. The `responder/id` value is the Azure AD Object ID of the approver. In most modern Power Platform online environments, `systemuserid` equals the Azure AD Object ID, so the lookup succeeds. However, in migrated or on-premises-derived environments, these IDs may differ, causing a 404 or 400 error on the UpdateRecord call.

**Resolution:**

- The error handlers (`Handle_Request_Approved_Failure`, `Handle_Denial_Update_Failure`) catch the failure and send admin notification emails via Outlook
- The core scope update still succeeds — only the request status update fails
- Manually update the request status in Dataverse after receiving the admin notification
- If this occurs frequently, consider customizing the flow to look up the system user by Azure AD Object ID instead of using a direct bind

**Affected environments:**

| Environment Type | Impact |
|-----------------|--------|
| Cloud-native (standard) | No issue — `systemuserid` equals AAD OID |
| Migrated from on-premises | May fail — IDs may differ |
| On-premises-derived | May fail — IDs may differ |

---

## Data Issues

### Duplicate Violation Records

**Symptoms:** Same violation detected multiple times.

**Resolution:**

The SDM-DriftDetector includes event-level deduplication based on `fsi_auditrecordid`. If duplicate violations still occur:

1. Verify the `List_Recent_Violations` action is returning existing records
2. Reduce detection frequency to minimize overlap
3. Archive resolved violations periodically

### Invalid JSON in Scope Fields

**Symptoms:** Errors parsing `fsi_allowedconnectors` or similar fields, or detection silently skipping certain resource categories.

**Background:**

The SDM-DriftDetector flow validates scope JSON fields on each run. If a scope field contains malformed JSON (e.g., `"SharePoint"` instead of `["SharePoint"]`), the flow:

1. Logs a warning to the detection summary identifying affected scopes
2. Falls back to an empty allowlist (`[]`) for that field, meaning **all** access of that resource type is treated as a violation
3. Continues processing remaining resource categories normally

This prevents silent suppression of detection but may generate false positives until the data is corrected.

**Resolution:**

Scope fields must contain valid JSON arrays:

```json
// Valid
["SharePoint", "Dataverse"]
[]

// Invalid
SharePoint, Dataverse
null
(empty string)
```

**Fix invalid data:**

1. Open agent scope record in Dataverse
2. Update field with valid JSON array
3. Use `[]` for empty lists

### Missing Audit Details

**Symptoms:** Violation created but `fsi_accessdetails` is empty.

**Resolution:**

- Some audit events have limited detail
- Office 365 Management API may not include all fields
- This is informational only - detection still works

---

## Performance Issues

### Flow Runs Slowly

**Symptoms:** SDM-DriftDetector takes > 5 minutes.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Large audit volume | Reduce lookback window |
| Many agents to check | Batch agent scope queries |
| Network latency | Check connection health |

**Optimization tips:**

1. Reduce detection frequency for Zone 1 agents
2. Use batch processing for multiple agents
3. Archive resolved violations periodically

### Flow Failures Due to Throttling

**Symptoms:** Flow fails with 429 Too Many Requests.

**Resolution:**

1. Add retry logic to HTTP actions
2. Reduce concurrent flow runs
3. Spread detection across time windows

---

## Shared Code

### Duplicate `Get-AccessToken` Function

`Get-AccessToken` is defined identically in both `Invoke-DriftScan.ps1` and `New-AgentBaseline.ps1`. When modifying token acquisition logic (e.g., adding token caching, changing credential handling), apply the change to both files. A future release may extract this into a shared module.

---

## Logging and Diagnostics

### Enable Verbose Logging

1. Open flow in edit mode
2. Select **Settings**
3. Enable **Secure Inputs** and **Secure Outputs** (turn OFF for debugging)
4. Run flow and check detailed outputs

### View Flow Run History

1. Navigate to **Power Automate** > **My flows**
2. Select the flow
3. Click **28-day run history**
4. Click individual run to see action details

### Export Flow Run Data

```powershell
# Use Power Platform CLI
pac flow list
pac flow run list --flow-id "xxxxx"
pac flow run show --flow-id "xxxxx" --run-id "yyyyy"
```

### Contact Support

For issues not covered here:

1. Review [flow-configuration.md](flow-configuration.md)
2. Check [GitHub Issues](https://github.com/judeper/FSI-AgentGov-Solutions/issues)
3. Submit new issue with:
   - Flow name
   - Error message
   - Run ID (if applicable)
   - Steps to reproduce

---

*Scope Drift Monitor v1.1.0*
