# Copilot Studio Agent Setup

Configure the Copilot Studio intake agent for environment requests.

## Overview

The intake agent provides a conversational interface for users to request new Power Platform environments. It:

- Collects environment requirements through guided conversation
- Auto-classifies requests into governance zones
- Validates naming conventions and security groups
- Submits structured requests to Power Automate

## Agent Configuration

### Create New Agent

1. Open [Copilot Studio](https://copilotstudio.microsoft.com)
2. Click **Create** > **New agent**
3. Configure basic settings:

| Setting | Value |
|---------|-------|
| Name | Environment Request Agent |
| Description | Request new Power Platform environments with automated governance classification |
| Instructions | Help users request Power Platform environments by collecting requirements and classifying into appropriate governance zones |

### Authentication Setup

1. Go to **Settings** > **Security**
2. Configure authentication:

| Setting | Value |
|---------|-------|
| Authentication | Authenticate with Microsoft |
| Require users to sign in | Yes |
| Access | Restricted to your organization |

---

## Topics

### Topic 1: Request Environment (Main)

#### Trigger Phrases

Add these trigger phrases:

- "I need a new environment"
- "Create an environment"
- "Request environment"
- "New Power Platform environment"
- "Provision environment"
- "Set up a new environment"

#### Conversation Flow

```
[Trigger] User requests environment
    |
    v
[Message] Welcome + explain process
    |
    v
[Question 1] Environment name
    |
    v
[Condition] Validate naming convention
    |-- Invalid --> [Message] Error, retry
    |
    v (Valid)
[Question 2] Environment type
    |
    v
[Question 3] Region
    |
    v
[Question 4] Business purpose
    |
    v
[Question 5] Expected users
    |
    v
[Question 6] Data sensitivity
    |
    v
[Question 7-9] Classification questions
    |
    v
[Calculate] Zone classification
    |
    v
[Message] Display zone + rationale
    |
    v
[Condition] Zone >= 2?
    |-- Yes --> [Question 10] Security group
    |
    v
[Condition] Zone = 3?
    |-- Yes --> [Question 11] Zone rationale
    |
    v
[Message] Summary + confirmation
    |
    v
[Action] Submit to Power Automate
    |
    v
[Message] Confirmation + request number
```

#### Slot Collection

##### Question 1: Environment Name

| Setting | Value |
|---------|-------|
| Question | What would you like to name this environment? Use the format: DEPT-Purpose-TYPE (e.g., FIN-Reporting-PROD) |
| Entity | User's entire response |
| Variable | `Topic.environmentName` |
| Required | Yes |

**Validation (Condition Node):**

```
Power Fx: IsMatch(Topic.environmentName, "^[A-Z]{2,4}-[A-Za-z0-9]+-[A-Z]+$")

If false: "Environment name must follow the pattern: DEPT-Purpose-TYPE (e.g., FIN-Reporting-PROD). Please try again."
```

##### Question 2: Environment Type

| Setting | Value |
|---------|-------|
| Question | What type of environment do you need? |
| Entity | Choice |
| Options | Sandbox, Production, Developer |
| Variable | `Topic.environmentType` |

##### Question 3: Region

| Setting | Value |
|---------|-------|
| Question | Which geographic region should host this environment? |
| Entity | Choice |
| Options | United States, Europe, United Kingdom, Australia |
| Variable | `Topic.region` |

##### Question 4: Business Purpose

| Setting | Value |
|---------|-------|
| Question | Please describe the business purpose for this environment (at least 20 characters). |
| Entity | User's entire response |
| Variable | `Topic.businessPurpose` |
| Required | Yes |

**Validation:**

```
Power Fx: Len(Topic.businessPurpose) >= 20

If false: "Please provide more detail about the business purpose (minimum 20 characters)."
```

##### Question 5: Expected Users

| Setting | Value |
|---------|-------|
| Question | How many users will use this environment? |
| Entity | Choice |
| Options | Just me (1), Small team (2-10), Large team (11-50), Department (50+) |
| Variable | `Topic.expectedUsers` |

##### Question 6: Data Sensitivity

| Setting | Value |
|---------|-------|
| Question | What's the highest data sensitivity level for data in this environment? |
| Entity | Choice |
| Options | Public, Internal, Confidential, Restricted |
| Variable | `Topic.dataSensitivity` |

##### Question 7: Customer Data

| Setting | Value |
|---------|-------|
| Question | Will this environment process customer or client data? |
| Entity | Boolean (Yes/No) |
| Variable | `Topic.hasCustomerData` |

##### Question 8: Financial Data

| Setting | Value |
|---------|-------|
| Question | Will this environment handle financial transaction data? |
| Entity | Boolean (Yes/No) |
| Variable | `Topic.hasFinancialData` |

##### Question 9: External Access

| Setting | Value |
|---------|-------|
| Question | Will external parties (clients, vendors) access this environment? |
| Entity | Boolean (Yes/No) |
| Variable | `Topic.hasExternalAccess` |

#### Zone Classification

**Add Variable node after classification questions:**

Variable: `Topic.zone`
Type: Number

**Power Fx Expression:**

```
If(
    Topic.dataSensitivity = "Restricted" ||
    Topic.hasCustomerData ||
    Topic.hasFinancialData ||
    Topic.hasExternalAccess,
    3,
    If(
        Topic.dataSensitivity = "Confidential" ||
        Topic.environmentType = "Production" ||
        Topic.expectedUsers <> "Just me (1)",
        2,
        1
    )
)
```

**Add Variable for auto flags:**

Variable: `Topic.zoneAutoFlags`
Type: Text

```
Concat(
    If(Topic.dataSensitivity = "Restricted", "RESTRICTED_DATA,", ""),
    If(Topic.hasCustomerData, "CUSTOMER_PII,", ""),
    If(Topic.hasFinancialData, "FINANCIAL_TRANSACTIONS,", ""),
    If(Topic.hasExternalAccess, "EXTERNAL_ACCESS,", ""),
    If(Topic.dataSensitivity = "Confidential", "CONFIDENTIAL_DATA,", ""),
    If(Topic.environmentType = "Production", "PRODUCTION_WORKLOAD,", ""),
    If(Topic.expectedUsers <> "Just me (1)", "TEAM_WORKLOAD,", "")
)
```

#### Display Classification

**Message node:**

```
Based on your responses, this environment has been classified as **Zone {Topic.zone}**.

**Classification triggers:**
{Topic.zoneAutoFlags}

**What this means:**
{If(Topic.zone = 1, "Zone 1 - Personal Productivity: Standard governance, self-service allowed.",
  If(Topic.zone = 2, "Zone 2 - Team Collaboration: Enhanced governance, manager approval required.",
    "Zone 3 - Enterprise Managed: Full governance, manager and compliance approval required."))}
```

##### Question 10: Security Group (Zone 2/3 Only)

**Condition:** `Topic.zone >= 2`

| Setting | Value |
|---------|-------|
| Question | What Entra security group should have access? Enter the exact group name. |
| Entity | User's entire response |
| Variable | `Topic.securityGroupName` |

##### Question 11: Zone Rationale (Zone 3 Only)

**Condition:** `Topic.zone = 3`

| Setting | Value |
|---------|-------|
| Question | Please provide a brief rationale explaining why this environment requires Zone 3 classification. |
| Entity | User's entire response |
| Variable | `Topic.zoneRationale` |

#### Summary and Confirmation

**Message node:**

```
**Environment Request Summary**

- **Name:** {Topic.environmentName}
- **Type:** {Topic.environmentType}
- **Region:** {Topic.region}
- **Zone:** Zone {Topic.zone}
- **Purpose:** {Topic.businessPurpose}

{If(Topic.zone >= 2, "- **Security Group:** " & Topic.securityGroupName, "")}

**Approval required:**
- Manager approval: {If(Topic.zone >= 2, "Yes", "No")}
- Compliance review: {If(Topic.zone = 3, "Yes", "No")}

Would you like to submit this request?
```

**Confirmation node:** Yes/No

#### Submit to Power Automate

**Action: Call an action**

Select the Power Automate flow that creates the EnvironmentRequest record.

**Input mapping:**

| Flow Input | Topic Variable |
|------------|----------------|
| environmentName | `Topic.environmentName` |
| environmentType | `Topic.environmentType` |
| region | `Topic.region` |
| zone | `Topic.zone` |
| zoneFlags | `Topic.zoneAutoFlags` |
| dataSensitivity | `Topic.dataSensitivity` |
| hasCustomerData | `Topic.hasCustomerData` |
| hasFinancialData | `Topic.hasFinancialData` |
| hasExternalAccess | `Topic.hasExternalAccess` |
| businessPurpose | `Topic.businessPurpose` |
| expectedUsers | `Topic.expectedUsers` |
| securityGroupName | `Topic.securityGroupName` |
| zoneRationale | `Topic.zoneRationale` |

#### Confirmation Message

**Message node:**

```
Your environment request has been submitted!

**Request Number:** {Topic.requestNumber}

**What happens next:**
{If(Topic.zone = 1,
  "Your request will be processed automatically. You'll receive an email when your environment is ready.",
  If(Topic.zone = 2,
    "Your request has been sent to your manager for approval. Once approved, the environment will be provisioned automatically.",
    "Your request requires both manager and compliance approval. You'll be notified at each stage."))}

You can check the status anytime by saying "Check request status" and providing your request number.
```

---

### Topic 2: Check Request Status

#### Trigger Phrases

- "Check request status"
- "Status of my request"
- "REQ-"
- "Where is my request"
- "Track my request"

#### Conversation Flow

**Question: Request Number**

| Setting | Value |
|---------|-------|
| Question | What is your request number? (e.g., REQ-00001) |
| Entity | User's entire response |
| Variable | `Topic.requestNumber` |

**Action: Query Dataverse**

Call flow or use Dataverse connector to query EnvironmentRequest by `fsi_requestnumber`.

**Display Status:**

```
**Request: {Topic.requestNumber}**

- **Environment:** {Flow.environmentName}
- **Status:** {Flow.state}
- **Zone:** Zone {Flow.zone}

{If(Flow.state = "Completed",
  "Your environment is ready! URL: " & Flow.environmentUrl,
  If(Flow.state = "PendingApproval",
    "Awaiting approval from: " & Flow.approverName,
    If(Flow.state = "Provisioning",
      "Your environment is being created. This typically takes 5-10 minutes.",
      If(Flow.state = "Failed",
        "There was an issue with your request. An administrator has been notified.",
        "Your request is being processed."))))}
```

---

### Topic 3: Cancel Request

#### Trigger Phrases

- "Cancel my request"
- "Withdraw request"
- "I don't need the environment anymore"

#### Conversation Flow

**Question: Request Number**

| Setting | Value |
|---------|-------|
| Question | Which request would you like to cancel? Enter the request number. |
| Entity | User's entire response |
| Variable | `Topic.requestNumber` |

**Action: Check Status**

Query request to verify it's in Draft or Submitted state.

**Condition:** State allows cancellation

- If Yes: Update state to Cancelled, confirm
- If No: "This request cannot be cancelled because it's already {state}."

---

### Topic 4: Help

#### Trigger Phrases

- "Help"
- "What can you do"
- "Commands"
- "Options"

#### Message

```
I can help you with Power Platform environment requests!

**Available commands:**

1. **Request a new environment** - Start the environment request process
2. **Check request status** - Look up the status of an existing request
3. **Cancel a request** - Cancel a pending request

**About governance zones:**

- **Zone 1** - Personal productivity, minimal governance
- **Zone 2** - Team collaboration, manager approval required
- **Zone 3** - Enterprise managed, full compliance review

**Naming convention:**

Environment names should follow: `DEPT-Purpose-TYPE`
Example: `FIN-QuarterlyReporting-PROD`

What would you like to do?
```

---

## System Topic Customization

### Greeting

Customize the default greeting:

```
Welcome to the Environment Request Agent!

I can help you:
- Request a new Power Platform environment
- Check the status of your requests
- Learn about our governance zones

What would you like to do today?
```

### Fallback

Customize fallback for unrecognized intents:

```
I'm not sure I understood that. I can help you with:

- **Request environment** - Start a new request
- **Check status** - Look up a request
- **Help** - See all options

Please try one of these, or rephrase your question.
```

### End of Conversation

```
Is there anything else I can help you with?

You can always come back to:
- Request another environment
- Check request status
- Get help

Have a great day!
```

---

## JSON Output Schema

When calling Power Automate, the agent sends this JSON structure:

```json
{
  "requestId": "guid-generated-by-flow",
  "timestamp": "2026-01-29T14:30:00Z",
  "requester": {
    "upn": "john.smith@contoso.com",
    "displayName": "John Smith",
    "department": "Finance"
  },
  "environment": {
    "name": "FIN-QuarterlyReporting-PROD",
    "type": "Production",
    "region": "unitedstates"
  },
  "classification": {
    "zone": 3,
    "autoFlags": ["CUSTOMER_PII", "FINANCIAL_TRANSACTIONS"],
    "dataSensitivity": "Confidential",
    "zoneRationale": "Environment will process quarterly financial reports containing customer account data."
  },
  "access": {
    "securityGroupId": "12345678-1234-1234-1234-123456789012",
    "securityGroupName": "FIN-QuarterlyReporting-Users",
    "expectedUserCount": 25
  },
  "businessContext": {
    "purpose": "Quarterly financial reporting automation for SEC 10-Q filings",
    "expectedUsers": "Finance reporting team, 25 users including 3 external auditors"
  },
  "approvalRequired": {
    "manager": true,
    "compliance": true,
    "zoneReviewRequired": false
  }
}
```

See [templates/json-output-schema.json](../templates/json-output-schema.json) for the complete schema.

---

## Testing

### Test Scenarios

| Scenario | Expected Zone | Approval |
|----------|---------------|----------|
| Personal sandbox, just me, internal data | Zone 1 | Auto |
| Team sandbox, 10 users, confidential | Zone 2 | Manager |
| Production, customer PII | Zone 3 | Manager + Compliance |
| Any environment with external access | Zone 3 | Manager + Compliance |

### Test Procedure

1. Open agent in test mode
2. Say "I need a new environment"
3. Walk through conversation
4. Verify zone classification
5. Confirm request submitted
6. Check EnvironmentRequest table

---

## Publishing

1. Complete testing
2. Click **Publish** in Copilot Studio
3. Configure channels:
   - Teams (recommended)
   - Web (optional)
4. Share agent URL with users

---

## Next Steps

After agent setup:

1. [Review troubleshooting guide](./troubleshooting.md)
2. Test end-to-end flow
3. Train users on agent usage
