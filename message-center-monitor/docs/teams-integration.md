# Teams Integration Guide

This guide explains how to configure Microsoft Teams notifications for Message Center alerts.

## Overview

The solution sends adaptive card notifications to a Teams channel when:
- A Message Center post has **high** or **critical** severity
- A post has an **action required deadline**

## Prerequisites

- Microsoft Teams channel for alerts
- Power Automate flow with Teams connector
- Adaptive card template (`templates/teams-notification-card.json`)

## Step 1: Create an Alerts Channel

1. Open Microsoft Teams
2. Navigate to your team (e.g., "Platform Operations")
3. Click **+ Add channel**
4. Configure:
   - Name: `Platform Alerts` or `Message Center Alerts`
   - Description: "Automated alerts from M365 Message Center"
   - Privacy: Standard (accessible to team members)
5. Click **Add**

## Step 2: Connect Power Automate to Teams

In your Power Automate flow:

1. Add action: **Microsoft Teams - Post card in a chat or channel**
2. Sign in with your Microsoft 365 account
3. Configure:
   - **Post as:** Flow bot
   - **Post in:** Channel
   - **Team:** Select your team
   - **Channel:** Select your alerts channel

> **Action Name Update:** Microsoft has renamed several Teams connector actions. The current action is "Post card in a chat or channel". If you have existing flows using "Post adaptive card in a chat or channel", they will continue to work, but new flows should use the current name.

> **Office 365 Connectors retirement:** Microsoft retired Office 365 connectors (including incoming webhook connectors) within Microsoft Teams, with the final deprecation rollout beginning **May 18, 2026** and completing **May 22, 2026** (after earlier extensions through March 31, 2026 and April 30, 2026). This solution does not use Office 365 connectors — Phase 1 posts Adaptive Cards to a Teams Workflows incoming webhook (Power Automate Workflows app) and Phase 3 uses the native "Post card in a chat or channel" Teams connector. If you have other integrations using Office 365 webhooks, migrate them to the Workflows app. See Microsoft's [Retirement of Office 365 connectors within Microsoft Teams](https://devblogs.microsoft.com/microsoft365dev/retirement-of-office-365-connectors-within-microsoft-teams/).

> **Body field handling (security):** The `fsi_body` field stores raw HTML from Microsoft Graph. Do **not** render it directly in custom HTML web resources or canvas-app HTML controls without sanitization. The shipped Teams adaptive card intentionally excludes the body field. If you customize the card to include body content, sanitize it first or render only the `bodyPlainText` derivation.

## Step 3: Use the Adaptive Card Template

The file `templates/teams-notification-card.json` contains the notification template.

### Adaptive Card Version Compatibility

Teams broadly supports Adaptive Cards versions 1.0 through 1.5, and Universal Actions guidance is based on schema 1.5. This solution uses version 1.5 while keeping simple `Action.OpenUrl` actions for connector compatibility. Use 1.6-only elements only after validating support in your target Teams clients.

### Option A: Copy-Paste Method

1. Open `templates/teams-notification-card.json`
2. Copy the entire JSON content
3. In Power Automate, paste into the **Adaptive Card** field
4. Replace placeholders with dynamic content (see below)

### Option B: Expression Method

Build the card dynamically using expressions:

```json
{
  "type": "AdaptiveCard",
  "$schema": "https://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.5",
  "body": [
    {
      "type": "TextBlock",
      "text": "@{items('Apply_to_each')?['title']}",
      "weight": "Bolder",
      "size": "Medium",
      "wrap": true
    }
  ]
}
```

### Placeholder Reference

| Placeholder | Replace With |
|-------------|--------------|
| `{title}` | `@{items('Apply_to_each')?['title']}` |
| `{severity}` | `@{items('Apply_to_each')?['severity']}` |
| `{category}` | `@{items('Apply_to_each')?['category']}` |
| `{services}` | `@{join(coalesce(items('Apply_to_each')?['services'], json('[]')), ', ')}` |
| `{startDateTime}` | `@{formatDateTime(items('Apply_to_each')?['startDateTime'], 'MMM dd, yyyy')}` |
| `{actionRequiredByDateTime}` | `@{if(equals(items('Apply_to_each')?['actionRequiredByDateTime'], null), 'None', formatDateTime(items('Apply_to_each')?['actionRequiredByDateTime'], 'MMM dd, yyyy'))}` |
| `{id}` | `@{items('Apply_to_each')?['id']}` |
| `{recordId}` | `@{outputs('Upsert_a_row')?['body/fsi_messagecenterlogid']}` |
| `{environment}` | The Dataverse host portion of your environment URL (e.g., `contoso` for `https://contoso.crm.dynamics.com`). |
| `{appId}` | The Application ID GUID of the model-driven app (visible in the URL when the app is open in `make.powerapps.com`). |
| `{publisherPrefix}` | The publisher prefix used when the schema script created the table — `fsi` by default. |

## Step 4: Configure Notification Conditions

Only send notifications for important posts. In your flow:

1. Add a **Condition** action before the Teams action
2. Configure the condition:

**High Severity OR Action Required (with duplicate prevention):**

```text
@and(
  equals(outputs('Upsert_a_row')?['body/fsi_notifiedon'], null),
  or(
    equals(items('Apply_to_each')?['severity'], 'high'),
    equals(items('Apply_to_each')?['severity'], 'critical'),
    not(equals(items('Apply_to_each')?['actionRequiredByDateTime'], null))
  )
)
```

> **Note:** The `notifiedOn` check uses the Dataverse upsert response (not the Graph API message) to prevent re-notifying posts that were already sent to Teams. See [Flow Configuration Step 7](flow-configuration.md#step-7-teams-notification-for-high-severity) for full details and alternative expressions.

Or use the visual editor:
- Condition 1: `@{outputs('Upsert_a_row')?['body/fsi_notifiedon']}` is equal to `null`
- **AND** (click "Add group" → **OR group** for the conditions below):
  - Condition 2: `severity` equals `high`
  - **OR**
  - Condition 3: `severity` equals `critical`
  - **OR**
  - Condition 4: `actionRequiredByDateTime` is not equal to `null`

> **Grouping matters:** You must nest Conditions 2–4 inside an OR group, then AND that group with Condition 1 (the null check). Without explicit grouping, the default evaluation would be `(notifiedOn == null AND severity == 'high') OR severity == 'critical' OR actionRequired != null`, which bypasses duplicate prevention for critical-severity and action-required posts. See [Flow Configuration Step 7](flow-configuration.md#step-7-teams-notification-for-high-severity) for full details.

## Step 5: Add User Mentions (Optional)

To @mention specific users for urgent posts:

1. In the adaptive card, add a mention entity:

```json
{
  "type": "AdaptiveCard",
  "version": "1.5",
  "body": [
    {
      "type": "TextBlock",
      "text": "<at>Platform Team</at> - Action Required!",
      "wrap": true
    }
  ],
  "msteams": {
    "entities": [
      {
        "type": "mention",
        "text": "<at>Platform Team</at>",
        "mentioned": {
          "id": "your-team-id-or-user-id",
          "name": "Platform Team"
        }
      }
    ]
  }
}
```

### Getting User/Team IDs

**For users:**
- Use Microsoft Graph: `GET /users/{user-principal-name}`
- The `id` field is the user's GUID

**For teams:**
- Use Microsoft Graph: `GET /groups?$filter=resourceProvisioningOptions/Any(x:x eq 'Team')`
- The `id` field is the team's GUID

## Card Design Options

### Minimal Card

Shows just the essentials:

```json
{
  "type": "AdaptiveCard",
  "version": "1.5",
  "body": [
    {
      "type": "TextBlock",
      "text": "{title}",
      "weight": "Bolder",
      "wrap": true
    },
    {
      "type": "TextBlock",
      "text": "Severity: {severity}",
      "spacing": "Small"
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "title": "View in Admin Center",
      "url": "https://admin.microsoft.com/Adminportal/Home#/MessageCenter/:/messages/{id}"
    }
  ]
}
```

### Full Card (Default)

See `templates/teams-notification-card.json` for the complete template with:
- Color-coded severity indicator
- All key metadata
- Services affected
- Action deadline (if any)
- Direct link to Admin Center

## Notification Routing

### By Severity

Route different severity levels to different channels:

```text
High Severity → #platform-alerts-urgent (with @mentions)
Normal Severity → #platform-alerts (no notification)
```

### By Service

Route by affected service:

```text
Power Platform → #powerplatform-team
Microsoft 365 → #m365-team
Azure → #azure-team
```

**Implementation:**

Use a **Switch** action based on the services array, or multiple conditions.

## Best Practices

### Don't Over-Notify

- Only alert on high severity and action-required posts
- Most Message Center posts are informational (normal severity)
- Too many notifications = notification fatigue

### Use Actionable Cards

- Include a direct link to the Admin Center post
- Include a link to your Dataverse record (for assessment) - see [Dataverse Record Link](#dataverse-record-link-optional) below
- Consider adding quick actions (e.g., "Mark as Reviewed")

## Dataverse Record Link (Optional)

The adaptive card template includes an "Assess Record" button that links directly to the Dataverse record. This enables faster triage by letting your team jump straight to the assessment form.

### Prerequisites

To use this feature, you need:
- A model-driven app or canvas app that displays MessageCenterLog records
- The Dataverse row GUID from the upsert operation in your flow

### Getting the Record ID

After upserting to Dataverse, the response includes the row GUID:

1. In your flow, after the Dataverse upsert action, add a **Compose** action
2. Set the input to: `@{outputs('Upsert_a_row')?['body/fsi_messagecenterlogid']}`
3. Use this value for `{recordId}` in the adaptive card URL

### URL Format

The Dataverse record URL follows this pattern:

```text
https://[your-environment].crm.dynamics.com/main.aspx?appid=[app-id]&pagetype=entityrecord&etn=[table-logical-name]&id=[record-guid]
```

**Components:**

| Component | Description | Example |
|-----------|-------------|---------|
| `[your-environment]` | Your Dataverse environment name | `contoso` |
| `[app-id]` | GUID of your model-driven app | `12345678-1234-1234-1234-123456789abc` |
| `[table-logical-name]` | Logical name of MessageCenterLog table | `fsi_messagecenterlog` |
| `[record-guid]` | Row GUID from upsert response | Dynamic from flow |

### Finding Your App ID

1. Open Power Apps (make.powerapps.com)
2. Navigate to your model-driven app
3. Click **...** > **Details**
4. Copy the **App ID** (GUID)

Or use the URL when the app is open - the `appid` parameter is in the URL.

### Example Card Configuration

In your Power Automate flow, replace the placeholder URL:

```json
{
  "type": "Action.OpenUrl",
  "title": "Assess Record",
  "url": "https://{environment}.crm.dynamics.com/main.aspx?appid={appId}&pagetype=entityrecord&etn={publisherPrefix}_messagecenterlog&id=@{outputs('Upsert_a_row')?['body/{publisherPrefix}_messagecenterlogid']}"
}
```

**Note:** If you don't have a model-driven app deployed, you can remove this action from the card template or leave it as a placeholder for future use.

### Finding Your Publisher Prefix

Dataverse column logical names include a publisher prefix (e.g., `fsi_messagecenterlogid`). To find your prefix:

**Method 1: Via Power Apps Tables**

1. Go to [make.powerapps.com](https://make.powerapps.com)
2. Select your environment (top right)
3. Navigate to **Tables** > **MessageCenterLog**
4. Click on any custom column (e.g., `messagecenterid`)
5. In the column details panel, find **Logical name**
6. The prefix is everything before the underscore (e.g., `fsi_` in `fsi_messagecenterid`)

**Method 2: Via Solution Publisher**

1. Go to [make.powerapps.com](https://make.powerapps.com) > **Solutions**
2. Open the solution containing your table
3. Click **Settings** (gear icon) > **Publishers**
4. Find your publisher and note the **Prefix** value

**Method 3: Via Dataverse Upsert Response**

1. Run your flow with the Dataverse upsert action
2. Check the flow run history
3. Look at the upsert action output—the returned field names show the prefix

> **Publisher prefix:** This solution requires the `fsi_` prefix produced by `create_mcm_dataverse_schema.py`. Tenants that previously deployed under a default `cr…` publisher prefix must redeploy via the script to align with the shipped governance scripts and flow expressions.

### Monitor Flow Health

- Set up a separate alert if the flow fails
- Check flow run history weekly
- Ensure the client secret doesn't expire unnoticed

## Troubleshooting

### Card Not Displaying

- Validate JSON at [adaptivecards.io/designer](https://adaptivecards.io/designer)
- Ensure version is "1.5" and avoid 1.6-only elements unless your target Teams clients support them
- Check for unsupported features in Teams (some Adaptive Card features are desktop-only)

### Mentions Not Working

- Verify the user/team ID is correct
- The `text` field must match exactly (e.g., `<at>Name</at>`)
- User must be a member of the channel

### Notifications Not Appearing

- Verify flow ran successfully (check run history)
- Confirm channel ID is correct
- Check Teams connector permissions
- Ensure the bot has permission to post to the channel

### Rate Limiting

Teams has rate limits for incoming messages:
- Per-channel: 1 message per second
- Per-app: 50 messages per minute

Daily polling is well within these limits.

