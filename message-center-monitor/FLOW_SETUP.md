# Power Automate Flow Setup

This guide walks through creating the Message Center Monitor flow in Power Automate.

## Overview

The flow:
1. Runs on a daily schedule
2. Calls Microsoft Graph API to get Message Center posts
3. Upserts posts to Dataverse
4. Sends Teams notifications for high-severity posts

## Prerequisites

Before starting, ensure you have:

- [ ] Azure AD app registration with `ServiceMessage.Read.All` permission
- [ ] Admin consent granted for the app
- [ ] Client ID, Tenant ID, and Client Secret ready
- [ ] Dataverse table created (see README.md)
- [ ] Azure Key Vault with client secret stored (recommended)

## Step 1: Create a New Flow

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. Click **Create** > **Scheduled cloud flow**
3. Name: `Message Center Monitor`
4. Set schedule:
   - Start: Today
   - Repeat every: 1 Day
   - At: 9:00 AM (or your preferred time)
5. Click **Create**

## Step 2: Get Client Secret from Key Vault (Recommended)

If using Azure Key Vault:

1. Add action: **Azure Key Vault - Get secret**
2. Configure:
   - Vault name: Your Key Vault name
   - Secret name: Your client secret name
3. The output `value` contains your client secret

If not using Key Vault, you'll enter the secret directly in the HTTP action (less secure).

## Step 3: Call Microsoft Graph API

Add action: **HTTP**

Configure:
- **Method:** GET
- **URI:** `https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages`
- **Authentication:** Active Directory OAuth
  - **Authority:** `https://login.microsoftonline.com`
  - **Tenant:** Your tenant ID (GUID)
  - **Audience:** `https://graph.microsoft.com`
  - **Client ID:** Your app registration client ID
  - **Credential Type:** Secret
  - **Secret:** From Key Vault output, or entered directly

### Authentication Screenshot Reference

```
┌─────────────────────────────────────────────┐
│ Authentication                              │
├─────────────────────────────────────────────┤
│ Authentication type: Active Directory OAuth │
│                                             │
│ Authority:   https://login.microsoftonline.com
│ Tenant:      xxxxxxxx-xxxx-xxxx-xxxx-xxxx   │
│ Audience:    https://graph.microsoft.com    │
│ Client ID:   xxxxxxxx-xxxx-xxxx-xxxx-xxxx   │
│ Credential Type: Secret                     │
│ Secret:      [Key Vault output or direct]   │
└─────────────────────────────────────────────┘
```

## Step 4: Parse JSON Response

Add action: **Parse JSON**

- **Content:** `@{body('HTTP')}`
- **Schema:** Click "Generate from sample" and paste this sample:

```json
{
  "@odata.context": "https://graph.microsoft.com/v1.0/$metadata#admin/serviceAnnouncement/messages",
  "value": [
    {
      "id": "MC123456",
      "title": "Sample Message Center Post",
      "category": "planForChange",
      "severity": "normal",
      "services": ["Microsoft 365 suite"],
      "startDateTime": "2026-01-01T00:00:00Z",
      "endDateTime": "2026-02-01T00:00:00Z",
      "lastModifiedDateTime": "2026-01-01T12:00:00Z",
      "isMajorChange": false,
      "actionRequiredByDateTime": null,
      "body": {
        "contentType": "html",
        "content": "<p>Message content here</p>"
      },
      "tags": ["Feature update"],
      "hasAttachments": false
    }
  ]
}
```

## Step 5: Loop Through Messages

Add action: **Apply to each**

- **Select an output from previous steps:** `@{body('Parse_JSON')?['value']}`

Inside the loop, add these actions:

### 5a: Compose Message ID

Add action: **Compose**
- **Inputs:** `@{items('Apply_to_each')?['id']}`

### 5b: Compose Severity

Add action: **Compose**
- **Inputs:** `@{items('Apply_to_each')?['severity']}`

### 5c: Upsert to Dataverse

Add action: **Dataverse - Update a row**

If the row doesn't exist, use **Add a row** first, or use this pattern:

1. Add action: **Dataverse - List rows**
   - Table: MessageCenterLog
   - Filter: `messagecenterId eq '@{items('Apply_to_each')?['id']}'`

2. Add **Condition**: Check if row exists
   - If yes: **Update a row**
   - If no: **Add a row**

**Field mappings for Add/Update:**

| Dataverse Column | Expression |
|------------------|------------|
| messagecenterId | `@{items('Apply_to_each')?['id']}` |
| title | `@{items('Apply_to_each')?['title']}` |
| category | Map to choice value (see below) |
| severity | Map to choice value (see below) |
| services | `@{join(items('Apply_to_each')?['services'], ', ')}` |
| startDateTime | `@{items('Apply_to_each')?['startDateTime']}` |
| actionRequiredByDateTime | `@{items('Apply_to_each')?['actionRequiredByDateTime']}` |
| body | `@{items('Apply_to_each')?['body']?['content']}` |

**Category mapping:**
- planForChange → Feature
- stayInformed → Admin
- preventOrFixIssues → Security

**Severity mapping:**
- high → High
- normal → Normal

## Step 6: Teams Notification for High Severity

Inside the Apply to each loop, after the Dataverse action:

Add **Condition**:
- `@{items('Apply_to_each')?['severity']}` is equal to `high`

OR

- `@{items('Apply_to_each')?['actionRequiredByDateTime']}` is not equal to `null`

**If yes:**

Add action: **Microsoft Teams - Post adaptive card in a chat or channel**

- **Post as:** Flow bot
- **Post in:** Channel
- **Team:** Your team
- **Channel:** Your alerts channel
- **Adaptive Card:** Use the template from [teams-notification-card.json](./teams-notification-card.json)

Replace placeholders in the card with dynamic content:
- `{title}` → `@{items('Apply_to_each')?['title']}`
- `{severity}` → `@{items('Apply_to_each')?['severity']}`
- `{category}` → `@{items('Apply_to_each')?['category']}`
- `{services}` → `@{join(items('Apply_to_each')?['services'], ', ')}`
- `{actionRequiredByDateTime}` → `@{items('Apply_to_each')?['actionRequiredByDateTime']}`
- `{id}` → `@{items('Apply_to_each')?['id']}`

## Step 7: Error Handling

### Configure Run After

For the Apply to each action:
1. Click the three dots (...) > **Configure run after**
2. Ensure it runs after HTTP succeeds

### Add Scope for Error Handling

Wrap the HTTP and Parse JSON in a **Scope** action:

1. Add **Scope** action (call it "Try")
2. Move HTTP and Parse JSON inside
3. Add another **Scope** after (call it "Catch")
4. Configure "Catch" to run after "Try" has failed
5. In "Catch", add a Teams notification for errors:
   - Post a message: "Message Center Monitor flow failed. Check run history."

## Step 8: Save and Test

1. Click **Save**
2. Click **Test** > **Manually** > **Test**
3. Wait for the flow to complete
4. Check:
   - Dataverse table has new rows
   - Teams channel received notifications (if high-severity posts exist)

## Complete Flow Structure

```
┌─ Recurrence (Daily at 9 AM)
│
├─ [Scope: Try]
│   ├─ Get secret (Azure Key Vault)
│   ├─ HTTP (GET Message Center)
│   └─ Parse JSON
│
├─ Apply to each (messages)
│   ├─ List rows (check if exists)
│   ├─ Condition (exists?)
│   │   ├─ Yes: Update a row
│   │   └─ No: Add a row
│   │
│   └─ Condition (high severity OR action required?)
│       └─ Yes: Post adaptive card to Teams
│
└─ [Scope: Catch] (runs on failure)
    └─ Post error notification to Teams
```

## Troubleshooting

### HTTP action fails with 401

- Verify app registration has `ServiceMessage.Read.All`
- Confirm admin consent was granted
- Check tenant ID and client ID are correct
- Verify client secret hasn't expired

### HTTP action fails with 403

- `ServiceMessage.Read.All` requires **Application** permission, not Delegated
- Admin consent must be granted by a Global Administrator

### Parse JSON fails

- Check HTTP response for error messages
- Verify the schema matches the actual response
- Use "Generate from sample" with real API response

### Dataverse actions fail

- Verify table and column names match exactly
- Check that choice values are mapped correctly
- Ensure the connection has sufficient permissions

### Teams notifications not appearing

- Verify the Teams connector is properly authenticated
- Check that the team and channel exist
- Review the adaptive card JSON for syntax errors

## Rate Limits

Microsoft Graph API has rate limits:
- Per-app: 10,000 requests per 10 minutes
- Per-tenant: 150,000 requests per 5 minutes

Daily polling is well within these limits. Even hourly polling (not recommended) would only use ~24 requests/day.
