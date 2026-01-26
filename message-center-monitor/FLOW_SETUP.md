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

## Step 5: Handle Pagination (Important)

Microsoft Graph API returns paged results. Without handling pagination, you may only get the first page (~100 posts) and miss older messages.

### Understanding `@odata.nextLink`

When more results exist than fit in one response, Graph API includes `@odata.nextLink` - a URL to fetch the next page. You must loop until this value is absent.

### Pattern: Do Until Loop

1. **Initialize variable** `nextLink` (String) = `https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages`
2. **Initialize variable** `allMessages` (Array) = `[]`
3. **Do Until** `@empty(variables('nextLink'))`:
   - HTTP GET to `@{variables('nextLink')}` (with same authentication)
   - **Append to array** `allMessages`: `@{body('HTTP')?['value']}`
   - **Set variable** `nextLink` = `@{coalesce(body('HTTP')?['@odata.nextLink'], '')}`
4. Process `allMessages` in the Apply to each loop

### Simplified Flow Diagram

```
┌─ Initialize nextLink = Graph URL
├─ Initialize allMessages = []
│
├─ Do Until (nextLink is empty)
│   ├─ HTTP GET nextLink
│   ├─ Append value to allMessages
│   └─ Set nextLink = @odata.nextLink (or empty)
│
└─ Apply to each (allMessages)
    └─ Process message...
```

> **Note:** For new deployments, this pattern is recommended. However, if you're processing daily and your tenant has fewer than 100 active posts, the basic single-request approach will work.

---

## Step 6: Loop Through Messages

Add action: **Apply to each**

- **Select an output from previous steps:** `@{variables('allMessages')}` (if using pagination) or `@{body('Parse_JSON')?['value']}` (basic)

Inside the loop, add these actions:

### 6a: Compose Message ID

Add action: **Compose**
- **Inputs:** `@{items('Apply_to_each')?['id']}`

### 6b: Compose Severity

Add action: **Compose**
- **Inputs:** `@{items('Apply_to_each')?['severity']}`

### 6c: Upsert to Dataverse

**Recommended: Alternate Key Approach**

If you can configure an alternate key on your Dataverse table, use the simpler "Upsert a row" action:

1. In Power Apps > Tables > MessageCenterLog > Keys
2. Create a new key using `messagecenterId` column
3. In your flow, use **Dataverse - Update or insert (upsert) a row**
   - Table: MessageCenterLog
   - Alternate Key: messagecenterId = `@{items('Apply_to_each')?['id']}`

This eliminates the need for List + Condition logic.

**Alternative: Manual Check Pattern**

If you cannot modify the table schema, use this pattern:

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

## Step 7: Teams Notification for High Severity

Inside the Apply to each loop, after the Dataverse action:

Add **Condition** to notify when action is truly needed:

**Option A: Basic Check**
- `@{items('Apply_to_each')?['severity']}` is equal to `high`

OR

- `@{items('Apply_to_each')?['actionRequiredByDateTime']}` is not equal to `null`

**Option B: Refined Check (Recommended)**

Use an expression to only notify when `actionRequiredByDateTime` is in the future:

```
@or(
  equals(items('Apply_to_each')?['severity'], 'high'),
  and(
    not(equals(items('Apply_to_each')?['actionRequiredByDateTime'], null)),
    greater(items('Apply_to_each')?['actionRequiredByDateTime'], utcNow())
  )
)
```

This prevents notifications for posts with past deadlines.

**Optional Enhancement:** Also check `isMajorChange`:

```
@or(
  equals(items('Apply_to_each')?['severity'], 'high'),
  equals(items('Apply_to_each')?['isMajorChange'], true),
  and(
    not(equals(items('Apply_to_each')?['actionRequiredByDateTime'], null)),
    greater(items('Apply_to_each')?['actionRequiredByDateTime'], utcNow())
  )
)
```

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

## Step 8: Error Handling

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

## Step 9: Save and Test

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
│   ├─ Initialize variables (nextLink, allMessages)
│   │
│   ├─ Do Until (nextLink is empty)
│   │   ├─ HTTP GET nextLink
│   │   ├─ Append to allMessages
│   │   └─ Set nextLink = @odata.nextLink
│   │
│   └─ Parse JSON (optional, for schema validation)
│
├─ Apply to each (allMessages)
│   ├─ Upsert row (alternate key)
│   │   OR
│   │   ├─ List rows (check if exists)
│   │   └─ Condition → Add or Update
│   │
│   └─ Condition (high severity OR future action required?)
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

---

## Optional Optimizations

### Delta Tracking with lastModifiedDateTime

After your first sync, you can filter to only retrieve recently modified posts. This reduces processing time and API payload size.

**Pattern:**

1. Store the timestamp of your last successful sync (options):
   - Dataverse config table row
   - Environment variable
   - Flow variable persisted to a file/SharePoint

2. On subsequent runs, filter the API call:
   ```
   https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages?$filter=lastModifiedDateTime ge 2025-01-25T00:00:00Z
   ```

3. Update the stored timestamp after successful processing

**Expression for filter:**
```
$filter=lastModifiedDateTime ge @{variables('lastSyncTime')}
```

**First Run vs. Subsequent Runs:**

- First run: No filter, retrieve all posts
- Subsequent runs: Filter by `lastModifiedDateTime`
- Suggested: Also run a full sync weekly to catch any edge cases

### Combining Optimizations

For busy tenants, combine pagination with delta tracking:

```
┌─ Get lastSyncTime from config
├─ Set API URL with $filter parameter
├─ Do Until (pagination loop)
│   └─ Process new/updated messages
└─ Update lastSyncTime in config
```

This approach minimizes both API calls and processing time while ensuring you don't miss any posts.
