# Message Center Monitor

> **Status:** Completed

Monitor Microsoft 365 Message Center for platform changes that could impact AI agent deployments (Copilot Studio, Agent Builder).

## What This Solution Does

- Polls Microsoft Message Center daily for new announcements
- Stores posts in Dataverse for tracking and assessment
- Alerts your team via Teams when high-severity or action-required posts appear
- Lets you assess and document which changes impact your agents

**This is operational monitoring** - it helps your platform team stay informed about Microsoft updates. It is not a compliance or audit system.

## Who Should Use This

| Audience | Use Case |
|----------|----------|
| Agent Platform Team | Need to know about breaking changes |
| Agent Governance Committee | Transparency on platform changes |
| Power Platform Admins | Track M365 changes affecting environments |

## Prerequisites

### 1. Microsoft Entra ID App Registration

Create an app registration for Message Center access:

1. Go to [Microsoft Entra admin center](https://entra.microsoft.com) > **Applications** > **App registrations**
2. Create new registration (single tenant)
3. Under "API permissions":
   - Add permission > Microsoft Graph > **Application permissions**
   - Select `ServiceMessage.Read.All`
   - Click **Grant admin consent** (requires an administrator with permission to consent)
4. Under "Certificates & secrets", create a client secret
5. Note the Application (client) ID, Directory (tenant) ID, and client secret

### 2. Azure Key Vault (Recommended)

Store your client secret securely:

1. Create a Key Vault in Azure Portal
2. Add your client secret as a secret
3. Grant your Power Automate connection access

See [Secrets Management](docs/secrets-management.md) for detailed steps.

### 3. Power Platform Environment

- Dataverse environment (included with most Power Platform licenses)
- Power Automate Premium license (required for Dataverse and HTTP connectors)

### 4. Dataverse Application User (required for governance scripts)

The PowerShell governance scripts call the Dataverse Web API as the same app registration used for Microsoft Graph. Without an application user with read/write access to `fsi_messagecenterlog`, the scripts will fail with `401 Unauthorized` or `403 Forbidden`.

1. Power Platform admin center → **Environments** → select your environment → **Settings** → **Users + permissions** → **Application users** → **+ New app user**
2. Add the app from Step 1 by Application (client) ID
3. Assign a security role with read/write/append/append-to access to `fsi_messagecenterlog` (a custom role scoped to the table is recommended; **System Administrator** is acceptable for non-prod)
4. Confirm the application user appears under **Application users** with status **Enabled**

### 5. DLP Policy (If Applicable)

If your environment has DLP policies:

1. Go to Power Platform Admin Center > Data policies
2. Ensure HTTP connector can access `graph.microsoft.com`
3. Ensure Azure Key Vault connector is allowed (if using Key Vault for secrets)
4. Or add both connectors to the "Business" group

## Quick Start

### Step 1: Deploy the Dataverse Schema

The packaged schema uses the `fsi_` publisher prefix and is the **canonical deployment path** — the included PowerShell governance scripts (`Invoke-MessageCenterSync.ps1`, `Get-MessageCenterAssessmentStatus.ps1`, `Export-MessageCenterEvidence.ps1`) all target `fsi_messagecenterlog`. Manual table creation under a different publisher prefix (such as a tenant default `cr123_`) is **not supported** by the shipped automation.

Run the schema script to create the table, columns, option sets, and alternate key:

```bash
python scripts/create_mcm_dataverse_schema.py \
    --tenant-id <tenant-guid> \
    --client-id <app-id> \
    --client-secret <secret> \
    --environment-url https://<org>.crm.dynamics.com \
    --output-docs
```

The script provisions:

- Table: `fsi_messagecenterlog` (entity set `fsi_messagecenterlogs`)
- 20 columns (see `docs/dataverse-schema.md` for the auto-generated reference, including required columns, MaxLength, and option-set integer values)
- 3 global option sets: `fsi_MCM_messagecategory`, `fsi_MCM_messageseverity`, `fsi_MCM_assessmentstatus`
- Alternate key on `fsi_messagecenterid` (used by Sync upsert)

> **Naming Convention Note:** Dataverse uses two naming systems. **Display names** (in the schema script) are human-readable labels shown in Power Apps. **Logical names** are always all-lowercase with the publisher prefix (e.g., `fsi_messagecenterid` — Dataverse does NOT insert underscores between words). When configuring Power Automate, OData queries, or scripts, always use the logical name.

### Step 2: Create the Power Automate Flow

See [Flow Configuration](docs/flow-configuration.md) for complete flow creation instructions.

**Summary:**

1. Trigger: Daily recurrence (e.g., 9 AM)
2. HTTP action: GET `https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages`
3. Parse JSON: Extract message fields
4. For each message: Upsert to Dataverse using messagecenterid
5. Condition: If severity = high/critical OR actionRequiredByDateTime is set
6. Teams notification: Post adaptive card to your channel

### Step 3: Set Up Teams Notifications

See [Teams Integration](docs/teams-integration.md) for Teams setup.

**Summary:**

1. Create a Teams channel for platform alerts
2. Use the provided adaptive card template
3. Configure the flow to post high-severity alerts

> **Note on Office 365 Connectors Deprecation:** Microsoft is retiring Office 365 incoming webhook connectors on **March 31, 2026**. This solution uses the native **Power Automate "Post to Teams" connector**, which is unaffected by this deprecation. If you have other integrations using custom incoming webhooks, plan migration to Power Automate Workflows connector or Adaptive Card actions.

### Step 4: Verify It Works

1. Run the flow manually
2. Check Dataverse for imported posts
3. Verify Teams notifications appear for high-severity items

## Workflow

```
Microsoft Message Center
        │
        ▼
Daily Polling (9 AM)
        │
        ▼
Dataverse MessageCenterLog Table
        │
        ▼
Alert if severity=high/critical OR action-required
        │
        ▼
Agent Platform Team Review
        │
        ▼
Assess: "Does this affect our agents?"
        │
        ▼
Log assessment + take action if needed
```

## Data Model

### MessageCenterLog (Single Table)

This solution uses a single table design for simplicity:

```
MessageCenterLog
├── messagecenterid (PK, MC######)
├── title
├── category (Feature/Admin/Security)
├── severity (High/Normal/Critical)
├── services (comma-separated)
├── startDateTime
├── actionRequiredByDateTime
├── endDateTime
├── body (HTML)
├── assessmentStatus (enum)
├── assessment (notes)
├── impactsAgents (boolean)
├── assessedBy (text)
├── assessedDate
├── actionsTaken (notes)
├── tags (comma-separated)
├── hasAttachments (boolean)
└── notifiedOn (duplicate prevention)
```

### Permissions

Use standard Dataverse permissions:

| Role | Access |
|------|--------|
| Platform Ops Team | Full CRUD |
| Agent Governance Committee | Read + Edit assessments |
| Viewers | Read-only |

No custom security roles required.

## Polling Interval

Microsoft Message Center has no webhook/push notification. The solution polls Graph API.

| Interval | Use Case |
|----------|----------|
| Daily (recommended) | Standard operations - most posts aren't urgent |
| Every 6 hours | Higher urgency environments |
| Hourly | Not recommended - excessive API calls |

## Documentation

| Document | Description |
|----------|-------------|
| [Flow Configuration](docs/flow-configuration.md) | Step-by-step Power Automate flow build guide |
| [Secrets Management](docs/secrets-management.md) | Key Vault integration for secure credential storage |
| [Setup Checklist](docs/setup-checklist.md) | Quick 10-step deployment checklist |
| [Teams Integration](docs/teams-integration.md) | Teams channel notification setup |

## Customization

This solution is designed to be modified:

- **Add columns:** Track additional metadata
- **Change notifications:** Route to Slack, email, or ServiceNow
- **Add views:** Filter by service, category, or date
- **Integrate:** Connect to your change management system
- **Plain-text body:** The `body` field stores HTML from Microsoft. For search or cleaner display, add a `bodyPlainText` column and use Power Automate's `stripHtml()` expression or a custom function to convert content

> **Environment Promotion Tip:** When moving this solution between environments (dev → test → prod), use [Dataverse environment variables](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/environmentvariables) instead of hardcoding values in the flow. Store the polling schedule (recurrence interval), severity thresholds, and Teams channel ID as environment variables so they can be updated per-environment without editing the flow definition. This aligns with ALM best practices and simplifies managed solution deployments.

## Troubleshooting

### Flow fails with 401/403

- Verify app registration has `ServiceMessage.Read.All` permission
- Confirm admin consent was granted
- Check client secret hasn't expired

### No posts appearing

- Run flow manually and check run history
- Verify HTTP action is returning data
- Check Dataverse upsert action for errors

### Teams notifications not posting

- Verify Teams channel connector is configured
- Check flow condition logic for high-severity posts
- Review Teams action in flow run history

## Version

2.2.0 - April 2026

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## Related Controls

- [Control 2.3: Change Management and Release Planning](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.3-change-management-and-release-planning.md)
- [Control 2.10: Patch Management and System Updates](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.10-patch-management-and-system-updates.md)

## Playbook Reference

- [Platform Change Governance Playbook](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/platform-change-governance/index.md)

## License

MIT - See LICENSE in repository root
