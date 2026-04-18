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

- [ ] Microsoft Entra ID app registration with `ServiceMessage.Read.All` permission
- [ ] Admin consent granted for the app (any administrator with permission to consent)
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

> **Concurrency Control:** To prevent duplicate processing when a manual test run overlaps with a scheduled run, configure the Recurrence trigger's concurrency setting. Click the trigger's **...** menu > **Settings** > enable **Concurrency Control** and set **Degree of Parallelism** to `1`. This means only one instance of the flow runs at a time — if a second run is triggered while one is in progress, it queues instead of running in parallel.

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
- **URI:** `https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages?$select=id,title,category,severity,services,startDateTime,endDateTime,lastModifiedDateTime,isMajorChange,actionRequiredByDateTime,body,tags,hasAttachments`
- **Authentication:** Active Directory OAuth
  - **Authority:** `https://login.microsoftonline.com`
  - **Tenant:** Your tenant ID (GUID)
  - **Audience:** `https://graph.microsoft.com`
  - **Client ID:** Your app registration client ID
  - **Credential Type:** Secret
  - **Secret:** From Key Vault output, or entered directly
- **Retry policy:** Change from default to **Fixed interval** — Count: `3`, Interval: `PT30S` (30 seconds). This handles transient Graph API errors (429 throttling, 503 service unavailable) without manual re-runs.

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
  "@odata.nextLink": "https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages?$skip=100",
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

> **Note:** The `@odata.nextLink` field appears when there are more results. Include it in your schema so Parse JSON doesn't fail when pagination is present.

## Step 5: Handle Pagination (Important)

Microsoft Graph API returns paged results. Without handling pagination, you may only get the first page (~100 posts) and miss older messages.

### Understanding `@odata.nextLink`

When more results exist than fit in one response, Graph API includes `@odata.nextLink` - a URL to fetch the next page. You must loop until this value is absent.

> **Page Size:** The default page size is 100 items. You can request up to 1000 items per page by adding the `Prefer: odata.maxpagesize=1000` header to your HTTP request. This reduces the number of API calls needed for tenants with many posts.

### Pattern: Do Until Loop

1. **Initialize variable** `nextLink` (String) = `https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages?$select=id,title,category,severity,services,startDateTime,endDateTime,lastModifiedDateTime,isMajorChange,actionRequiredByDateTime,body,tags,hasAttachments`
2. **Initialize variable** `allMessages` (Array) = `[]`
3. **Do Until** `@empty(variables('nextLink'))`:
   - HTTP GET to `@{variables('nextLink')}` (with same authentication and **retry policy: Fixed interval, Count: 3, Interval: PT30S** — same as the Step 3 HTTP action, to handle transient 429/503 errors during pagination)
   - **Set variable** `allMessages` = `@{union(variables('allMessages'), body('HTTP_2')?['value'])}`

> **Warning:** Do NOT use "Append to array" here. `Append to array` adds a single element, so it would create a nested array `[[page1_msgs], [page2_msgs]]` instead of a flat list. Use `Set variable` with `union()` to merge page results correctly.

> **Action naming:** If you already added an HTTP action in Step 3, Power Automate auto-renames this second HTTP action to `HTTP_2`. The expressions above use `body('HTTP_2')` to reflect this. If you delete the Step 3 HTTP action and use only the Do Until pattern, rename references back to `body('HTTP')`. Always verify the action name in your flow matches the expressions.

> **Loop Limits:** Configure the Do Until's **Limits** settings (click the **…** menu > **Settings** on the Do Until action). Set **Count** to `60` (maximum iterations) and **Timeout** to `PT1H` (1 hour). While these are Power Automate's defaults, setting them explicitly prevents runaway execution if the API returns malformed `@odata.nextLink` values that never resolve to empty.

   - **Set variable** `nextLink` = `@{coalesce(body('HTTP_2')?['@odata.nextLink'], '')}`
4. Process `allMessages` in the Apply to each loop

### Simplified Flow Diagram

```
┌─ Initialize nextLink = Graph URL
├─ Initialize allMessages = []
│
├─ Do Until (nextLink is empty)
│   ├─ HTTP GET nextLink
│   ├─ Set allMessages = union(allMessages, value)
│   └─ Set nextLink = @odata.nextLink (or empty)
│
└─ Apply to each (allMessages)
    └─ Process message...
```

> **Note:** For new deployments, this pattern is recommended. However, if you're processing daily and your tenant has fewer than 100 active posts, the basic single-request approach will work.

### Parse JSON with Pagination

When using the pagination pattern above, the `allMessages` variable is a flat array of message objects (not wrapped in a `{ "value": [...] }` envelope). If you want to validate the flat array with Parse JSON, use this schema instead:

```json
{
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "id": { "type": "string" },
      "title": { "type": "string" },
      "category": { "type": "string" },
      "severity": { "type": "string" },
      "services": { "type": "array", "items": { "type": "string" } },
      "startDateTime": { "type": "string" },
      "endDateTime": { "type": ["string", "null"] },
      "lastModifiedDateTime": { "type": "string" },
      "isMajorChange": { "type": "boolean" },
      "actionRequiredByDateTime": { "type": ["string", "null"] },
      "body": {
        "type": "object",
        "properties": {
          "contentType": { "type": "string" },
          "content": { "type": "string" }
        }
      },
      "tags": { "type": "array", "items": { "type": "string" } },
      "hasAttachments": { "type": "boolean" }
    }
  }
}
```

> **Tip:** Parse JSON is optional when using pagination—the `Apply to each` loop can directly iterate over `allMessages`. Use Parse JSON only if you want schema validation or IntelliSense for field names in subsequent actions.

---

## Step 6: Loop Through Messages

Add action: **Apply to each**

> **⚠️ Keep execution sequential (default).** Do not enable parallel execution ("Concurrency Control") on this Apply to each loop. The loop uses a non-atomic read-then-update pattern: it reads `notifiedOn` from the upsert response, checks if null, then sends a Teams notification and updates `notifiedOn`. If parallel execution is enabled, two iterations could both read `notifiedOn == null` for the same post before either writes the update, causing duplicate Teams notifications.

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

**Creating the Alternate Key:**

1. Go to [make.powerapps.com](https://make.powerapps.com)
2. Select your environment from the environment picker (top right)
3. Navigate to **Tables** in the left menu
4. Find and open **MessageCenterLog** table
5. Click **Keys** in the left submenu (under Schema)
6. Click **+ New key**
7. Configure:
   - **Display name:** `messagecenterid Key`
   - **Name:** (auto-generated, or customize)
   - **Columns:** Select `messagecenterid`
8. Click **Save**
9. Wait for the key to be created (status changes from "In Progress" to "Active")

**Using the Alternate Key in Power Automate:**

1. In your flow, use **Dataverse - Update or insert (upsert) a row**
   - Table: MessageCenterLog
   - Alternate Key: messagecenterid = `@{items('Apply_to_each')?['id']}`

This replaces the List + Condition logic.

**Alternative: Manual Check Pattern**

If you cannot modify the table schema, use this pattern:

1. Add action: **Dataverse - List rows**
   - Table: MessageCenterLog
   - Filter: `messagecenterid eq '@{items('Apply_to_each')?['id']}'`

2. Add **Condition**: Check if row exists
   - If yes: **Update a row**
   - If no: **Add a row**

> **Duplicate prevention with List rows:** When using this pattern instead of upsert, check the `notifiedOn` field from the List rows response in your notification condition: `equals(first(outputs('List_rows')?['body/value'])?['fsi_notifiedon'], null)`.  If no row exists yet (new post), `first()` returns null and the condition is satisfied, allowing the first notification.

**Field mappings for Add/Update:**

| Dataverse Column | Expression |
|------------------|------------|
| messagecenterid | `@{items('Apply_to_each')?['id']}` |
| title | `@{items('Apply_to_each')?['title']}` |
| category | Map to choice value (see below) |
| severity | Map to choice value (see below) |
| services | `@{join(coalesce(items('Apply_to_each')?['services'], json('[]')), ', ')}` |
| startDateTime | `@{items('Apply_to_each')?['startDateTime']}` |
| actionRequiredByDateTime | `@{items('Apply_to_each')?['actionRequiredByDateTime']}` |
| lastModifiedDateTime | `@{items('Apply_to_each')?['lastModifiedDateTime']}` |
| isMajorChange | `@{items('Apply_to_each')?['isMajorChange']}` |
| body | `@{coalesce(items('Apply_to_each')?['body']?['content'], '')}` |

**Category mapping:**
- planForChange → Feature
- stayInformed → Admin
- preventOrFixIssue → Security

**Severity mapping:**
- high → High
- normal → Normal
- critical → Critical

### Choice Field Implementation with Switch

Category and severity columns are Dataverse Choice (Picklist) fields backed by global option sets — they reject text labels and require the integer values defined in `create_mcm_dataverse_schema.py` (and reflected in `docs/dataverse-schema.md`). Use a **Switch** action to map the Microsoft Graph API enum values to the option-set integers, then write the integer to the Choice column.

**Category Switch (writes to `fsi_category`, option set `fsi_MCM_messagecategory`):**

1. Add action: **Switch**
2. On: `@{items('Apply_to_each')?['category']}`
3. Add cases:
   - Case `planForChange`: Set variable `categoryValue` = `100000000` (Feature)
   - Case `stayInformed`: Set variable `categoryValue` = `100000001` (Admin)
   - Case `preventOrFixIssue`: Set variable `categoryValue` = `100000002` (Security)
   - Default: Set variable `categoryValue` = `100000001` (Admin)

**Severity Switch (writes to `fsi_severity`, option set `fsi_MCM_messageseverity`):**

1. Add action: **Switch**
2. On: `@{items('Apply_to_each')?['severity']}`
3. Add cases:
   - Case `high`: Set variable `severityValue` = `100000000` (High)
   - Case `normal`: Set variable `severityValue` = `100000001` (Normal)
   - Case `critical`: Set variable `severityValue` = `100000002` (Critical)
   - Default: Set variable `severityValue` = `100000001` (Normal)

The variables are typed as **Integer** so the Update Row action can write them directly to the Choice column. See `docs/dataverse-schema.md` for the canonical option-set definitions, or `create_mcm_dataverse_schema.py:OPTION_SETS` for the source of truth.

## Step 7: Teams Notification for High Severity

Inside the Apply to each loop, after the Dataverse action:

Add **Condition** to notify when action is truly needed:

**Notification Condition (includes duplicate prevention):**

> **Important:** The flow runs daily and re-evaluates ALL posts. Without duplicate prevention, previously notified posts trigger alerts again on every run. The `notifiedOn` column (added in Step 1) tracks which posts have already been notified.

**Option A: Basic Check**
```
@and(
  equals(outputs('Upsert_a_row')?['body/fsi_notifiedon'], null),
  or(
    equals(items('Apply_to_each')?['severity'], 'high'),
    equals(items('Apply_to_each')?['severity'], 'critical')
  )
)
```

> **Note:** The `Upsert_a_row` response body returns the full Dataverse record, including the existing `notifiedOn` value. Do **not** use `items('Apply_to_each')?['notifiedOn']` — Graph API messages do not contain this field.

OR (visual editor equivalent):

In the condition editor, create the following structure:
- Row 1: `@{outputs('Upsert_a_row')?['body/fsi_notifiedon']}` **is equal to** `null`
- **AND** (click "Add group" → **OR group**):
  - Row 2a: `@{items('Apply_to_each')?['severity']}` **is equal to** `high`
  - **OR**
  - Row 2b: `@{items('Apply_to_each')?['severity']}` **is equal to** `critical`

> **Grouping matters:** You must nest the two severity rows inside an OR group, then AND that group with the null check. Without explicit grouping, the default evaluation would be `(notifiedOn == null AND severity == 'high') OR severity == 'critical'`, which bypasses duplicate prevention for critical-severity posts.

**Option B: Refined Check (Recommended)**

Use an expression to only notify when `actionRequiredByDateTime` is in the future:

```
@and(
  equals(outputs('Upsert_a_row')?['body/fsi_notifiedon'], null),
  or(
    equals(items('Apply_to_each')?['severity'], 'high'),
    equals(items('Apply_to_each')?['severity'], 'critical'),
    and(
      not(equals(items('Apply_to_each')?['actionRequiredByDateTime'], null)),
      greater(items('Apply_to_each')?['actionRequiredByDateTime'], utcNow())
    )
  )
)
```

> **Note:**  See the Option A note above for details.

This prevents notifications for posts with past deadlines and means each post triggers at most one notification.

**After sending a Teams notification**, add a **Dataverse - Update a row** action to set `notifiedOn` to `@{utcNow()}`. This marks the post as notified so it won't trigger again on the next run. If you later want to re-notify (e.g., deadline approaching), reset `notifiedOn` to null or add a separate reminder condition.

**Optional Enhancement:** Also check `isMajorChange`:

```
@and(
  equals(outputs('Upsert_a_row')?['body/fsi_notifiedon'], null),
  or(
    equals(items('Apply_to_each')?['severity'], 'high'),
    equals(items('Apply_to_each')?['severity'], 'critical'),
    equals(items('Apply_to_each')?['isMajorChange'], true),
    and(
      not(equals(items('Apply_to_each')?['actionRequiredByDateTime'], null)),
      greater(items('Apply_to_each')?['actionRequiredByDateTime'], utcNow())
    )
  )
)
```

> **Note:** 

**If yes:**

Add action: **Microsoft Teams - Post card in a chat or channel**

> **Note:** The action was previously called "Post adaptive card in a chat or channel" but has been renamed. If you see the old name in your flow, it will continue to work.

- **Post as:** Flow bot
- **Post in:** Channel
- **Team:** Your team
- **Channel:** Your alerts channel
- **Adaptive Card:** Use the template from [teams-notification-card.json](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/message-center-monitor/templates/teams-notification-card.json)

Replace placeholders in the card with dynamic content:
- `{title}` → `@{items('Apply_to_each')?['title']}`
- `{severity}` → `@{items('Apply_to_each')?['severity']}`
- `{category}` → `@{items('Apply_to_each')?['category']}`
- `{services}` → `@{join(coalesce(items('Apply_to_each')?['services'], json('[]')), ', ')}`
- `{startDateTime}` → `@{formatDateTime(items('Apply_to_each')?['startDateTime'], 'MMM dd, yyyy')}`
- `{actionRequiredByDateTime}` → `@{if(equals(items('Apply_to_each')?['actionRequiredByDateTime'], null), 'None', formatDateTime(items('Apply_to_each')?['actionRequiredByDateTime'], 'MMM dd, yyyy'))}`
- `{id}` → `@{items('Apply_to_each')?['id']}`
- `{recordId}` → `@{outputs('Upsert_a_row')?['body/fsi_messagecenterlogid']}`

## Step 8: Error Handling

### Configure Run After

For the Apply to each action:
1. Click the three dots (...) > **Configure run after**
2. Ensure it runs after HTTP succeeds

### Add Scope for Error Handling

Wrap the main processing logic in a **Scope** action for better error handling:

1. Add **Scope** action (call it "Try")
2. Move inside the Try scope:
   - HTTP action (or Do Until loop for pagination)
   - Parse JSON action
   - Apply to each loop (including Dataverse upsert and Teams notification)
3. Add another **Scope** after (call it "Catch")
4. Configure "Catch" to run after "Try" has failed
5. In "Catch", add a Teams notification for errors:
   - Post a message using this expression to include the error details and timestamp:
     ```
     Message Center Monitor flow failed at @{utcNow()}.
     Error: @{result('Try')?[0]?['error']?['message']}
     Check run history for details.
     ```
   - This enables faster operational triage without requiring manual navigation to flow run history.

> **Why include Apply to each in Try?** If a single message fails to process (e.g., malformed data), the entire loop stops. Wrapping it in Try means you get notified of partial failures. For even more granular handling, you can add a nested Try/Catch inside the Apply to each loop to handle individual message failures without stopping the entire run.

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
│   │   ├─ Set allMessages = union(allMessages, value)
│   │   └─ Set nextLink = @odata.nextLink
│   │
│   ├─ Parse JSON (optional, for schema validation)
│   │
│   └─ Apply to each (allMessages)
│       ├─ Upsert row (alternate key)
│       │   OR
│       │   ├─ List rows (check if exists)
│       │   └─ Condition → Add or Update
│       │
│       └─ Condition (high severity OR future action required? AND not yet notified)
│           └─ Yes: Post adaptive card to Teams
│                   Update notifiedOn = utcNow()
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
- Admin consent must be granted by an administrator with permission to consent to enterprise applications

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

## Environment Variables for ALM Portability

The steps above hardcode the polling schedule, severity thresholds, and Teams channel ID directly in the flow. For single-environment use this is fine, but when promoting the solution across environments (dev → test → prod), use [Dataverse environment variables](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/environmentvariables) so values can be updated per-environment without editing the flow definition.

**Recommended environment variables:**

| Display Name | Schema Name | Type | Example Value |
|-------------|-------------|------|---------------|
| Polling Interval (days) | `fsi_PollingIntervalDays` | Integer | `1` |
| Notification Severity Threshold | `fsi_NotifySeverities` | Text | `high,critical` |
| Teams Channel ID | `fsi_TeamsChannelId` | Text | `19:abc123@thread.tacv2` |
| Teams Team ID | `fsi_TeamsTeamId` | Text | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

> **Note:**  Create these in your solution via **Solutions** > your solution > **Add** > **Environment variable**.

To reference an environment variable in the flow, use the **Dataverse - List rows** action to query the `Environment Variable Values` table, or use the `@{outputs('Get_Environment_Variable')?['body/value']}` pattern after adding a dedicated lookup action. This aligns with ALM best practices and simplifies managed solution deployments.

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
