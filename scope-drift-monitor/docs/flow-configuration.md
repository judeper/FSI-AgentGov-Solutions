# Flow Configuration

Power Automate flow setup and configuration for the Scope Drift Monitor.

---

## Overview

The Scope Drift Monitor uses three Power Automate flows:

| Flow | Purpose | Trigger |
|------|---------|---------|
| **SDM-DriftDetector** | Detect scope drift violations | Scheduled (configurable) |
| **SDM-AlertDispatcher** | Send violation alerts | Dataverse record creation |
| **SDM-ExpansionProcessor** | Process expansion requests | Dataverse record creation |

```
┌───────────────────────┐
│  SDM-DriftDetector    │──────┐
│  (Scheduled scan)     │      │ Creates violation
└───────────────────────┘      ▼
                         ┌───────────────────────┐
                         │  fsi_scopeviolation   │
                         └───────────────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         ▼                                           ▼
┌───────────────────────┐               ┌───────────────────────┐
│  SDM-AlertDispatcher  │               │  User creates request │
│  (Teams + Email)      │               │                       │
└───────────────────────┘               └───────────────────────┘
                                                 │
                                                 ▼
                                        ┌───────────────────────┐
                                        │ fsi_expansionrequest  │
                                        └───────────────────────┘
                                                 │
                                                 ▼
                                        ┌───────────────────────┐
                                        │ SDM-ExpansionProcessor│
                                        │ (Approval workflow)   │
                                        └───────────────────────┘
```

---

## Connection References

Before importing the solution, configure connection references in your target environment.

| Connection Reference | Connector | Purpose |
|---------------------|-----------|---------|
| `fsi_cr_dataverse` | Dataverse | Read/write scope and violation records |
| `fsi_cr_outlook` | Office 365 Outlook | Send email notifications |
| `fsi_cr_teams` | Microsoft Teams | Post adaptive cards to channels |
| `fsi_cr_approvals` | Approvals | Process expansion approvals |
| `fsi_cr_http_azuread` | HTTP with Microsoft Entra ID | Query Office 365 Management API |

### Creating Connection References

1. Navigate to **Power Apps** > **Solutions**
2. Open the **Scope Drift Monitor** solution
3. Select **Connection References**
4. For each reference, click **Edit** and select or create a connection

---

## Environment Variables

Configure environment variables for your organization.

| Variable | Description | Example |
|----------|-------------|---------|
| `fsi_SDM_TenantId` | Microsoft Entra ID tenant ID | `12345678-1234-1234-1234-123456789012` |
| `fsi_SDM_DataverseEnvironment` | Dataverse environment URL | `https://contoso.crm.dynamics.com` |
| `fsi_SDM_TeamsGroupId` | Teams team ID for alerts | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `fsi_SDM_TeamsChannelId` | Teams channel ID for alerts | `19:xxxxx@thread.tacv2` |
| `fsi_SDM_SecurityTeamEmail` | Security team email for approvals | `security@contoso.com` |
| `fsi_SDM_DetectionWindowMinutes` | Detection lookback window in minutes | `15` (minutes) |
| `fsi_SDM_ClientId` | Microsoft Entra ID application client ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `fsi_SDM_ClientSecret` | Microsoft Entra ID application client secret | *(stored securely)* |
| `fsi_SDM_ActiveScopeStatus` | Option-set value for Active status on `fsi_agentscope` (default: `10002`) | `10002` |
| `fsi_SDM_ManagementApiEndpoint` | Office 365 Management API base URL | `https://manage.office.com` (commercial) |

> **Security:** The `fsi_SDM_ManagementApiEndpoint` value is validated at runtime against known Microsoft Management API endpoints (`manage.office.com`, `manage.office365.us`, `manage.office.eaglex.ic.gov`, `manage.protection.outlook.com`). Unrecognized values are replaced with the commercial default to prevent token leakage to untrusted endpoints.

### Configuring Environment Variables

1. Navigate to **Power Apps** > **Solutions**
2. Open the **Scope Drift Monitor** solution
3. Select **Environment Variables**
4. Set current values for each variable

### Finding Teams IDs

**Team ID:**
1. Open Teams > right-click the team > **Get link to team**
2. Extract the `groupId` parameter from the URL

**Channel ID:**
1. Open Teams > right-click the channel > **Get link to channel**
2. Extract the `channelId` parameter (URL-encoded)

---

## Flow Configuration

### SDM-DriftDetector

**Purpose:** Queries audit logs and creates violation records for scope drift.

**Configuration:**

| Setting | Default | Description |
|---------|---------|-------------|
| Recurrence | 15 minutes | How often to check for drift |
| Lookback window | 15 minutes | Audit events to analyze (overlap prevents gaps) |
| Pagination limit | 50 iterations | Max content blob pages fetched per run |

> **⚠ Concurrency constraint:** The `For_Each_Content_Blob` loop uses `SetVariable` with `union()` (in `Flatten_Filtered_Events`) to accumulate audit events. Its concurrency **must remain at 1**. Raising concurrency would cause lost-update data corruption because `SetVariable` is not atomic across parallel iterations.

> **Scaling consideration:** The `Update_Scope_LastValidated` step issues one Dataverse `UpdateRecord` call per active agent scope (N+1 pattern) at concurrency 5. This is adequate for most deployments, but environments with 200+ scopes will generate 200+ API calls every 15 minutes. For large deployments, consider increasing the recurrence interval or monitoring Dataverse API quota usage.

**To modify detection frequency:**

1. Open the flow in edit mode
2. Select the **Recurrence** trigger
3. Change **Interval** to desired minutes
4. Update the lookback window in **Initialize Lookback** to be slightly longer

**Detection sources:**

1. **Office 365 Management API** - CopilotInteraction events (RecordType 261)

> **Note:** The flow uses only the Office 365 Management API (Unified Audit Log) for detection. Ensure Management API subscriptions are configured per the [prerequisites](prerequisites.md).

> **Known limitation:** The detection summary (`Compose_Detection_Summary`) is built at the end of each cycle but is not persisted to Dataverse or any external store. Operational telemetry (events processed, violations created, source availability) is only available through Power Automate's 28-day run history. Organizations with FSI audit retention requirements should export flow run data to a long-term store (see [Troubleshooting > Export Flow Run Data](troubleshooting.md#export-flow-run-data)).

### SDM-AlertDispatcher

**Purpose:** Sends Teams and email alerts when violations are created.

**Configuration:**

| Setting | Default | Description |
|---------|---------|-------------|
| Teams channel | Environment variable | Where to post adaptive cards |
| Email recipients | Owner + Security team | Who receives email alerts |
| Severity filter | None (all severities) | Optionally filter alerts |

**To customize alert behavior:**

1. Open the flow in edit mode
2. To filter by severity, add a condition after **Get Violation Details**
3. To change email recipients, modify **Determine Email Recipients** compose action

**Alert content:**

- **Teams:** Adaptive card with violation details and action buttons
- **Email:** HTML email with severity styling and Dataverse links

### SDM-ExpansionProcessor

**Purpose:** Routes expansion requests through approval workflow.

**Configuration:**

| Setting | Default | Description |
|---------|---------|-------------|
| Approval type | Basic (single approver) | Power Automate Approvals type |
| Assigned to | Security team email | Who approves requests |
| Timeout | 7 days | How long before approval expires |

**To modify approval routing:**

1. Open the flow in edit mode
2. To add multiple approvers, change **approvalType** to `CustomResponse`
3. To add data owner approval, add a parallel approval action

> **Note:** All expansion requests are currently routed to the security team only. Dual-approval workflows (Data Owner + Security) are not yet implemented. The Dataverse schema includes `fsi_dataownerapproval`, `fsi_dataownerapprovedby`, and `fsi_dataowner` fields for future use.

**Approval outcomes:**

| Outcome | Actions |
|---------|---------|
| **Approved** | Update agent scope, close violation (if linked), notify requestor |
| **Rejected** | Update request status, notify requestor with comments |
| **Timeout** | Update request to timed out, notify requestor |

> **Known limitation:** Expansion requests of type 10005 (Increase Access Level) are approved through the workflow but require **manual scope configuration** by an administrator. The flow skips automatic scope list updates for this request type because access level changes cannot be expressed as list-append operations. The approval notification email instructs the requestor to contact the security team for manual configuration.

---

## Testing Flows

### Test SDM-DriftDetector

1. Create a test agent scope with limited allowed resources
2. Generate a test CopilotInteraction event (use an agent)
3. Run the flow manually
4. Verify a violation record is created

### Test SDM-AlertDispatcher

1. Create a test violation record manually in Dataverse
2. Verify Teams adaptive card appears in configured channel
3. Verify email is received by owner and security team

**Alternative:** Use `Test-AlertDelivery.ps1`:

```powershell
.\scripts\Test-AlertDelivery.ps1 -Channel Both -TeamsWebhook "https://your-webhook-url" -EmailRecipient "security@contoso.com" -FromEmail "alerts@contoso.com"
```

### Test SDM-ExpansionProcessor

1. Create a test expansion request in Dataverse
2. Check your approval inbox (Teams or Outlook)
3. Approve or reject the request
4. Verify:
   - Request status updated
   - Agent scope updated (if approved)
   - Email notification received

---

## Troubleshooting

For common issues and resolutions, see [Troubleshooting Guide](troubleshooting.md).

---

*Scope Drift Monitor v1.2.0*
