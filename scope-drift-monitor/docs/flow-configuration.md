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
| `fsi_SDM_TenantId` | Azure AD tenant ID (GUID format) | `12345678-1234-1234-1234-123456789012` |
| `fsi_SDM_DataverseEnvironment` | Dataverse environment URL | `https://contoso.crm.dynamics.com` |
| `fsi_SDM_TeamsGroupId` | Teams team ID for alerts | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `fsi_SDM_TeamsChannelId` | Teams channel ID for alerts | `19:xxxxx@thread.tacv2` |
| `fsi_SDM_SecurityTeamEmail` | Security team email for approvals | `security@contoso.com` |
| `fsi_SDM_DetectionWindowMinutes` | Detection lookback window | `15` (minutes) |
| `fsi_SDM_ClientId` | Azure AD application client ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `fsi_SDM_ClientSecret` | Azure AD application client secret | *(stored securely)* |
| `fsi_SDM_DefaultScopeOwner` | Systemuser GUID for auto-created placeholder scopes | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

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
| Lookback window | 15 minutes | Audit events to analyze (matches recurrence interval) |

**To modify detection frequency:**

1. Open the flow in edit mode
2. Select the **Recurrence** trigger
3. Change **Interval** to desired minutes
4. Update the `fsi_SDM_DetectionWindowMinutes` environment variable to match

**Detection sources:**

1. **Office 365 Management API** — CopilotInteraction events (RecordType 261)

> **Note:** The architecture supports additional detection sources (CloudAppEvents, SharePoint Audit, Dataverse Audit) but only the Unified Audit Log is implemented in v1.1.0. Additional sources are planned for future releases.

**Event processing cap:** Each detection cycle processes a maximum of **200 audit events**. If the audit window returns more than 200 events, additional events are skipped until the next cycle. The detection summary records `eventsReceived`, `eventsProcessed`, and `eventsSkipped` counts so administrators can monitor for overflow. If events are consistently being skipped, reduce `fsi_SDM_DetectionWindowMinutes` or increase detection frequency to reduce per-cycle volume.

**Graceful degradation:** If the Management API is unavailable, the flow logs a warning and skips the current detection cycle.

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

**Approval outcomes:**

| Outcome | Actions |
|---------|---------|
| **Approved** | Update agent scope, close violation (if linked), notify requestor |
| **Rejected** | Update request status, notify requestor with comments |
| **Timeout** | Update request to Cancelled (status 6), notify requestor of expiration |

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
.\scripts\Test-AlertDelivery.ps1 -Channel Both -TeamsWebhook "https://..." -EmailRecipient "security@contoso.com" -FromEmail "alerts@contoso.com"
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

*Scope Drift Monitor v1.1.0*
