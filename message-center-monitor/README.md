# Message Center Monitor

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

See [SECRETS_MANAGEMENT.md](./SECRETS_MANAGEMENT.md) for detailed steps.

### 3. Power Platform Environment

- Dataverse environment (included with most Power Platform licenses)
- Power Automate license (standard is sufficient)

### 4. DLP Policy (If Applicable)

If your environment has DLP policies:

1. Go to Power Platform Admin Center > Data policies
2. Ensure HTTP connector can access `graph.microsoft.com`
3. Ensure Azure Key Vault connector is allowed (if using Key Vault for secrets)
4. Or add both connectors to the "Business" group

## Quick Start

### Step 1: Create the Dataverse Table

Create a table named `MessageCenterLog` with these columns:

| Column | Type | Description |
|--------|------|-------------|
| messagecenterId | Text (Primary) | MC###### format |
| title | Text (500) | Post title |
| category | Choice | Feature, Admin, Security |
| severity | Choice | High, Normal, Critical |
| services | Text (2000) | Comma-separated service names |
| startDateTime | DateTime | When post was published |
| actionRequiredByDateTime | DateTime | Deadline for action (if any) |
| lastModifiedDateTime | DateTime | When Microsoft last updated this post |
| isMajorChange | Yes/No | Microsoft's flag for significant changes |
| body | Multiline Text | Full post content (HTML) |
| assessmentStatus | Choice | Not Assessed, Reviewed, Impacts Agents, No Impact |
| assessment | Multiline Text | Your team's assessment notes |
| impactsAgents | Yes/No | Does this affect your agents? |
| assessedBy | Lookup (User) | Who reviewed this post |
| assessedDate | DateTime | When it was reviewed |
| actionsTaken | Multiline Text | Notes on response/remediation |

> **Naming Convention Note:** Dataverse uses two naming systems. **Display names** (shown in the table above) are human-readable labels you see in Power Apps. **Logical names** (used in flows and code) include your environment's publisher prefix, e.g., `cr123_messagecenterId`. When configuring Power Automate, use the logical names. Your publisher prefix (e.g., `cr123_`) is specific to your environment—see [TEAMS_INTEGRATION.md](./TEAMS_INTEGRATION.md#finding-your-publisher-prefix) for how to find it.

### Step 2: Create the Power Automate Flow

See [FLOW_SETUP.md](./FLOW_SETUP.md) for complete flow creation instructions.

**Summary:**

1. Trigger: Daily recurrence (e.g., 9 AM)
2. HTTP action: GET `https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages`
3. Parse JSON: Extract message fields
4. For each message: Upsert to Dataverse using messagecenterId
5. Condition: If severity = high OR actionRequiredByDateTime is set
6. Teams notification: Post adaptive card to your channel

### Step 3: Set Up Teams Notifications

See [TEAMS_INTEGRATION.md](./TEAMS_INTEGRATION.md) for Teams setup.

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
Alert if severity=high OR action-required
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
├── messagecenterId (PK, MC######)
├── title
├── category (Feature/Admin/Security)
├── severity (high/normal)
├── services (comma-separated)
├── startDateTime
├── actionRequiredByDateTime
├── body (HTML)
├── assessmentStatus (enum)
├── assessment (notes)
├── impactsAgents (boolean)
├── assessedBy (User lookup)
├── assessedDate
└── actionsTaken (notes)
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

| Guide | Description |
|-------|-------------|
| [FLOW_SETUP.md](./FLOW_SETUP.md) | Complete Power Automate flow setup |
| [TEAMS_INTEGRATION.md](./TEAMS_INTEGRATION.md) | Teams notification configuration |
| [SECRETS_MANAGEMENT.md](./SECRETS_MANAGEMENT.md) | Azure Key Vault setup |
| [SETUP_CHECKLIST.md](./SETUP_CHECKLIST.md) | Quick 10-step checklist |

## Customization

This solution is designed to be modified:

- **Add columns:** Track additional metadata
- **Change notifications:** Route to Slack, email, or ServiceNow
- **Add views:** Filter by service, category, or date
- **Integrate:** Connect to your change management system
- **Plain-text body:** The `body` field stores HTML from Microsoft. For search or cleaner display, add a `bodyPlainText` column and use Power Automate's `stripHtml()` expression or a custom function to convert content

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

2.1.1 - January 2026

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## Related Controls

- [Control 2.3: Change Management and Release Planning](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.3-change-management-and-release-planning.md)
- [Control 2.10: Patch Management and System Updates](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.10-patch-management-and-system-updates.md)

## Playbook Reference

- [Platform Change Governance Playbook](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/platform-change-governance/index.md)

## License

MIT - See LICENSE in repository root
