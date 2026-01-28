# Notification Templates

Email and Teams notification templates for pipeline governance cleanup.

---

## Email Template: Owner Notification

Use this template when notifying pipeline owners of upcoming cleanup.

### Subject Line

```
Action Required: Pipeline Governance - [Pipeline Name] - Cleanup by [Date]
```

### Body

```html
Dear [Owner Name],

As part of our Power Platform governance initiative, we are consolidating all deployment pipelines to our designated pipelines host environment.

<strong>Your Pipeline:</strong> [Pipeline Name]
<strong>Created:</strong> [Creation Date]
<strong>Action Required By:</strong> [Enforcement Date]

<strong>What This Means:</strong>
Your pipeline was created outside of our centrally governed infrastructure. To maintain compliance with our IT governance policies, all deployment pipelines must use the designated pipelines host environment.

<strong>Your Options:</strong>

1. <strong>Migrate to Central Host (Recommended)</strong>
   - Contact the Platform Ops team to migrate your pipeline
   - Your deployment configurations will be preserved
   - Request via: [ServiceNow/Help Desk Link]

2. <strong>Request Exemption</strong>
   - If you have a business justification, submit an exemption request
   - Exemptions require approval from [Approving Authority]
   - Request via: [Exemption Form Link]

3. <strong>No Action Needed</strong>
   - If you no longer need this pipeline, no action is required
   - The pipeline will be deactivated on [Enforcement Date]

<strong>Questions?</strong>
Contact the Platform Operations team at [platform-ops@company.com] or [#platform-support in Teams].

Thank you for your cooperation in maintaining our governance standards.

Best regards,
Platform Operations Team
```

---

## Placeholder Reference

When using Power Automate to send notifications (if you have a custom tracking table), use these expressions:

| Placeholder | Dynamic Content | Expression |
|-------------|-----------------|------------|
| `[Owner Name]` | Owner display name | `outputs('Get_a_row_by_ID')?['fullname']` |
| `[Owner Email]` | Owner email address | `outputs('Get_a_row_by_ID')?['internalemailaddress']` |
| `[Pipeline Name]` | Pipeline/environment name | `items('Apply_to_each')?['name']` |
| `[Environment ID]` | Environment GUID | `items('Apply_to_each')?['environmentid']` |
| `[Enforcement Date]` | Scheduled enforcement date | `formatDateTime(items('Apply_to_each')?['scheduledremovaldate'], 'MMMM d, yyyy')` |

### Important: Resolving Owner Email

The owner ID (`_ownerid_value`) is a GUID, not an email address. To get the owner's email:

1. **Add "Get a row by ID" action** after your "List rows" action
2. **Table name:** Users (systemuser)
3. **Row ID:** Use the owner GUID from your tracking record:
   ```
   items('Apply_to_each')?['_ownerid_value']
   ```
4. **Select columns:** `fullname,internalemailaddress`

Then reference the email in your notification:
```
outputs('Get_a_row_by_ID')?['internalemailaddress']
```

### PowerShell Alternative (Recommended)

For simpler implementation, use the PowerShell notification script instead of Power Automate:

```powershell
.\src\Send-OwnerNotifications.ps1 `
    -InputPath ".\non-compliant-environments.csv" `
    -EnforcementDate "2026-03-01"
```

The CSV must include `OwnerEmail`, `EnvironmentName`, and `EnvironmentId` columns.

---

## Teams Adaptive Card Template

For Teams channel notifications, use this adaptive card JSON.

### Adaptive Card JSON

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.4",
  "body": [
    {
      "type": "TextBlock",
      "text": "Pipeline Governance Notice",
      "weight": "bolder",
      "size": "large",
      "color": "warning"
    },
    {
      "type": "TextBlock",
      "text": "Action required for your deployment pipeline",
      "wrap": true,
      "spacing": "small"
    },
    {
      "type": "FactSet",
      "facts": [
        {
          "title": "Pipeline:",
          "value": "${pipelineName}"
        },
        {
          "title": "Created:",
          "value": "${createdDate}"
        },
        {
          "title": "Action By:",
          "value": "${enforcementDate}"
        }
      ]
    },
    {
      "type": "TextBlock",
      "text": "This pipeline is not hosted in the designated pipelines host environment. Please migrate or request an exemption before the deadline.",
      "wrap": true,
      "spacing": "medium"
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "title": "Request Migration",
      "url": "https://company.service-now.com/pipeline-migration"
    },
    {
      "type": "Action.OpenUrl",
      "title": "Request Exemption",
      "url": "https://company.service-now.com/pipeline-exemption"
    },
    {
      "type": "Action.OpenUrl",
      "title": "Contact Support",
      "url": "https://teams.microsoft.com/l/channel/..."
    }
  ]
}
```

### Power Automate Configuration

In your flow, use **Post adaptive card in a chat or channel**:

1. Post as: Flow bot
2. Post in: Channel
3. Team: Your governance team
4. Channel: Platform Alerts (or similar)
5. Adaptive Card: Use the JSON above with dynamic content

Replace placeholders with expressions:

| Placeholder | Expression |
|-------------|------------|
| `${pipelineName}` | `@{items('Apply_to_each')?['pipelinename']}` |
| `${createdDate}` | `@{formatDateTime(items('Apply_to_each')?['createdon'], 'MMMM d, yyyy')}` |
| `${enforcementDate}` | `@{formatDateTime(items('Apply_to_each')?['scheduledremovaldate'], 'MMMM d, yyyy')}` |

---

## Escalation Email Template

Use when owner doesn't respond to initial notification.

### Subject Line

```
FINAL NOTICE: Pipeline [Pipeline Name] will be deactivated on [Date]
```

### Body

```html
Dear [Owner Name],

This is a final reminder regarding your deployment pipeline that requires action.

<strong>Pipeline:</strong> [Pipeline Name]
<strong>Deactivation Date:</strong> [Enforcement Date]
<strong>Days Remaining:</strong> [Days Until Deadline]

We previously notified you on [Original Notification Date] about the required migration of your pipeline to our centralized governance infrastructure.

<strong>If no action is taken, your pipeline will be automatically deactivated on [Enforcement Date].</strong>

To prevent disruption:
- Migrate to the central host: [Migration Link]
- Or submit an exemption request: [Exemption Link]

If you have questions or need assistance, please contact the Platform Operations team immediately.

Platform Operations Team
[platform-ops@company.com]
```

---

## Confirmation Email Template

Send after pipeline has been deactivated.

### Subject Line

```
Pipeline Deactivated: [Pipeline Name]
```

### Body

```html
Dear [Owner Name],

Your deployment pipeline has been deactivated as part of our governance cleanup.

<strong>Pipeline:</strong> [Pipeline Name]
<strong>Deactivated On:</strong> [Deactivation Date]
<strong>Previous Status:</strong> Active

<strong>What This Means:</strong>
- This pipeline can no longer be used for deployments
- Your deployment targets are unaffected
- Solutions previously deployed remain in place

<strong>Need to Restore?</strong>
If you need this pipeline restored, please submit a request with business justification:
[Restoration Request Link]

Thank you for your cooperation.

Platform Operations Team
```

---

## Admin Alert Template

Alert for Platform Ops team when violations are detected.

### Teams Adaptive Card

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.4",
  "body": [
    {
      "type": "TextBlock",
      "text": "Pipeline Governance Alert",
      "weight": "bolder",
      "size": "large",
      "color": "attention"
    },
    {
      "type": "TextBlock",
      "text": "${alertMessage}",
      "wrap": true
    },
    {
      "type": "FactSet",
      "facts": [
        {
          "title": "Violations Found:",
          "value": "${violationCount}"
        },
        {
          "title": "Scan Time:",
          "value": "${scanTimestamp}"
        }
      ]
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "title": "View Report",
      "url": "${reportUrl}"
    }
  ]
}
```

---

## Escalation Timeline

| Day | Action | Template |
|-----|--------|----------|
| 0 | Discovery | N/A (internal inventory) |
| 1 | Initial notification | Owner Notification |
| 14 | First reminder | Owner Notification (modified subject) |
| 28 | Final notice | Escalation Email |
| 30-60 | Deactivation | Confirmation Email |

---

## Best Practices

### Timing

- Send notifications during business hours (9 AM - 5 PM local)
- Avoid Fridays for initial notifications (weekend visibility issues)
- Send escalation on different day than original notification

### Tone

- Be clear and direct about requirements
- Provide specific deadlines
- Offer help and alternatives
- Avoid threatening language

### Tracking

- Log all notifications in tracking table
- Record delivery status (sent, bounced, opened if available)
- Track responses and exemption requests

### Accessibility

- Use clear, simple language
- Avoid jargon where possible
- Provide multiple contact methods
- Include links to detailed documentation
