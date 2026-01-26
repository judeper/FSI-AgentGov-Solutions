# Teams Integration Guide

This guide explains how to configure Microsoft Teams notifications for Message Center alerts.

## Overview

The solution sends adaptive card notifications to a Teams channel when:
- A Message Center post has **high severity**
- A post has an **action required deadline**

## Prerequisites

- Microsoft Teams channel for alerts
- Power Automate flow with Teams connector
- Adaptive card template (`teams-notification-card.json`)

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

1. Add action: **Microsoft Teams - Post adaptive card in a chat or channel**
2. Sign in with your Microsoft 365 account
3. Configure:
   - **Post as:** Flow bot
   - **Post in:** Channel
   - **Team:** Select your team
   - **Channel:** Select your alerts channel

## Step 3: Use the Adaptive Card Template

The file `teams-notification-card.json` contains the notification template.

### Option A: Copy-Paste Method

1. Open `teams-notification-card.json`
2. Copy the entire JSON content
3. In Power Automate, paste into the **Adaptive Card** field
4. Replace placeholders with dynamic content (see below)

### Option B: Expression Method

Build the card dynamically using expressions:

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.4",
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
| `{services}` | `@{join(items('Apply_to_each')?['services'], ', ')}` |
| `{startDateTime}` | `@{items('Apply_to_each')?['startDateTime']}` |
| `{actionRequiredByDateTime}` | `@{items('Apply_to_each')?['actionRequiredByDateTime']}` |
| `{id}` | `@{items('Apply_to_each')?['id']}` |

## Step 4: Configure Notification Conditions

Only send notifications for important posts. In your flow:

1. Add a **Condition** action before the Teams action
2. Configure the condition:

**High Severity OR Action Required:**

```
@or(
  equals(items('Apply_to_each')?['severity'], 'high'),
  not(equals(items('Apply_to_each')?['actionRequiredByDateTime'], null))
)
```

Or use the visual editor:
- Condition 1: `severity` equals `high`
- OR
- Condition 2: `actionRequiredByDateTime` is not equal to `null`

## Step 5: Add User Mentions (Optional)

To @mention specific users for urgent posts:

1. In the adaptive card, add a mention entity:

```json
{
  "type": "AdaptiveCard",
  "version": "1.4",
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
  "version": "1.4",
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
      "url": "https://admin.microsoft.com/Adminportal/Home#/MessageCenter/{id}"
    }
  ]
}
```

### Full Card (Default)

See `teams-notification-card.json` for the complete template with:
- Color-coded severity indicator
- All key metadata
- Services affected
- Action deadline (if any)
- Direct link to Admin Center

## Notification Routing

### By Severity

Route different severity levels to different channels:

```
High Severity → #platform-alerts-urgent (with @mentions)
Normal Severity → #platform-alerts (no notification)
```

### By Service

Route by affected service:

```
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
2. Set the input to: `@{outputs('Upsert_a_row')?['body/cr123_messagecenterlogid']}`
   - Replace `cr123_` with your environment's publisher prefix
3. Use this value for `{recordId}` in the adaptive card URL

### URL Format

The Dataverse record URL follows this pattern:

```
https://[your-environment].crm.dynamics.com/main.aspx?appid=[app-id]&pagetype=entityrecord&etn=[table-logical-name]&id=[record-guid]
```

**Components:**

| Component | Description | Example |
|-----------|-------------|---------|
| `[your-environment]` | Your Dataverse environment name | `contoso` |
| `[app-id]` | GUID of your model-driven app | `12345678-1234-1234-1234-123456789abc` |
| `[table-logical-name]` | Logical name of MessageCenterLog table | `cr123_messagecenterlog` |
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
  "url": "https://contoso.crm.dynamics.com/main.aspx?appid=12345678-1234-1234-1234-123456789abc&pagetype=entityrecord&etn=cr123_messagecenterlog&id=@{outputs('Upsert_a_row')?['body/cr123_messagecenterlogid']}"
}
```

**Note:** If you don't have a model-driven app deployed, you can remove this action from the card template or leave it as a placeholder for future use.

### Finding Your Publisher Prefix

Dataverse column logical names include a publisher prefix (e.g., `cr123_messagecenterlogid`). To find your prefix:

**Method 1: Via Power Apps Tables**

1. Go to [make.powerapps.com](https://make.powerapps.com)
2. Select your environment (top right)
3. Navigate to **Tables** > **MessageCenterLog**
4. Click on any custom column (e.g., `messagecenterId`)
5. In the column details panel, find **Logical name**
6. The prefix is everything before the underscore (e.g., `cr123_` in `cr123_messagecenterId`)

**Method 2: Via Solution Publisher**

1. Go to [make.powerapps.com](https://make.powerapps.com) > **Solutions**
2. Open the solution containing your table
3. Click **Settings** (gear icon) > **Publishers**
4. Find your publisher and note the **Prefix** value

**Method 3: Via Dataverse Upsert Response**

1. Run your flow with the Dataverse upsert action
2. Check the flow run history
3. Look at the upsert action output—the returned field names show the prefix

> **Common prefixes:** Default environments often use `cr...` prefixes (e.g., `cr123_`). Custom publishers use the prefix you specified when creating the publisher.

### Monitor Flow Health

- Set up a separate alert if the flow fails
- Check flow run history weekly
- Ensure the client secret doesn't expire unnoticed

## Troubleshooting

### Card Not Displaying

- Validate JSON at [adaptivecards.io/designer](https://adaptivecards.io/designer)
- Ensure version is "1.4" or compatible with Teams
- Check for unsupported features in Teams

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
