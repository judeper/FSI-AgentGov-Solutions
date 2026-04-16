# Scheduling Guide — Audit Logging Compliance Automation (ALCA)

Configure automated scheduling for detection and optional remediation runbooks.

---

## Detection Schedule (Recommended)

### Weekly Audit Compliance Check

| Setting | Value |
|---------|-------|
| **Name** | `Weekly-Audit-Compliance-Check` |
| **Frequency** | Weekly |
| **Day** | Monday |
| **Time** | 6:00 AM ET (11:00 UTC) |
| **Timezone** | (UTC-05:00) Eastern Time |
| **Linked Runbook** | `Test-AuditLoggingCompliance` |

**Setup steps:**

1. Navigate to **Automation Account** → **Schedules** → **+ Add a schedule**
2. Configure:
   - **Name:** `Weekly-Audit-Compliance-Check`
   - **Description:** Weekly scan of all Power Platform environments for audit compliance
   - **Starts:** Next Monday, 11:00 UTC
   - **Recurrence:** Recurring — Every 1 week on Monday
   - **Set expiration:** No
3. Click **Create**

### Link Schedule to Runbook

1. Navigate to **Runbooks** → **Test-AuditLoggingCompliance** → **Schedules** → **+ Add a schedule**
2. Select **Link a schedule to your runbook** → Choose `Weekly-Audit-Compliance-Check`
3. Click **Configure parameters and run settings**
4. Enter:

| Parameter | Value |
|-----------|-------|
| `DataverseEnvironmentUrl` | `https://your-org.crm.dynamics.com` |
| `TenantDomain` | `yourdomain.onmicrosoft.com` |
| `SendEmail` | `true` |
| `NotificationFromAddress` | `powerplatform-governance@yourdomain.com` |
| `NotificationToAddresses` | `admin@yourdomain.com,compliance@yourdomain.com` |

5. Click **OK** → **OK**

---

## Optional: Daily Audit Validation

For organizations requiring more frequent monitoring:

| Setting | Value |
|---------|-------|
| **Name** | `Daily-Audit-Validation` |
| **Frequency** | Daily |
| **Time** | 7:00 AM ET (12:00 UTC) |
| **Linked Runbook** | `Test-AuditLoggingCompliance` |

**Setup:** Follow the same steps as the weekly schedule, but set:
- **Recurrence:** Recurring — Every 1 day
- Consider setting `SendEmail` to `false` for daily runs to avoid notification fatigue
- Use the Dataverse compliance table for daily monitoring instead

---

## Parameter Reference

### Test-AuditLoggingCompliance Parameters

| Parameter | Required | Type | Default | Description |
|-----------|----------|------|---------|-------------|
| `DataverseEnvironmentUrl` | Yes | String | — | Dataverse URL hosting compliance table |
| `TenantDomain` | Yes | String | — | Tenant domain (e.g., contoso.onmicrosoft.com) |
| `NotificationFromAddress` | No | String | — | Shared mailbox for sending notifications |
| `NotificationToAddresses` | No | String | — | Comma-separated recipient list |
| `SendEmail` | No | Switch | false | Enable email notification |

### Enable-AuditLogging Parameters

| Parameter | Required | Type | Default | Description |
|-----------|----------|------|---------|-------------|
| `DataverseEnvironmentUrl` | Yes | String | — | Dataverse URL hosting compliance table |
| `TenantDomain` | Yes | String | — | Tenant domain |
| `EnvironmentId` | No | String | — | Specific environment GUID, or omit for all non-compliant |
| `EnableTenantUnifiedAudit` | No | Switch | true | Enable tenant-wide Purview unified audit |
| `WhatIf` | No | Switch | false | Simulate remediation without making changes |

---

## Monitoring Scheduled Runs

### Check Job History

1. Navigate to **Automation Account** → **Jobs**
2. Filter by runbook name
3. Verify:
   - **Status:** Completed (not Failed or Suspended)
   - **Duration:** Expected range (detection: 5–15 min, depends on environment count)
   - **Output:** Review for compliance summary

### Set Up Alerts

Configure Azure Monitor alerts for failed runbook jobs:

1. Navigate to **Automation Account** → **Alerts** → **+ Create alert rule**
2. **Condition:** `Total Jobs` where Status = `Failed`
3. **Action group:** Send email to operations team
4. **Severity:** Sev 2 (Warning)

---

## Schedule Management Tips

- **Stagger schedules** if running both detection and remediation on schedules — detection should complete before remediation starts
- **Test in Test Pane first** before enabling schedules
- **Disable schedules** during maintenance windows or tenant migrations
- **Monitor job durations** — significant increases may indicate throttling or environment growth

---

*Updated: February 2026 | Version: v1.0.2*
