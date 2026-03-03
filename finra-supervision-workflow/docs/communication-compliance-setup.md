# Communication Compliance Setup

Configure Microsoft Purview Communication Compliance to flag AI agent outputs for supervisory review.

## Overview

Communication Compliance policies identify content in AI agent conversations that requires supervisory review based on:

- Regulatory keywords (investment advice, guarantees, performance claims)
- Sensitive information types (account numbers, NPI)
- Custom classifiers (firm-specific terminology)

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| License | Microsoft 365 E5 or E5 Compliance add-on |
| Role | Purview Compliance Admin or Communication Compliance Admin |
| Audit | Audit logging enabled (Control 1.7) |

---

## Step 1: Enable Communication Compliance

1. Navigate to [Microsoft Purview compliance portal](https://compliance.microsoft.com)
2. Select **Communication compliance** from left navigation
3. If first time, complete the setup wizard:
   - Accept terms
   - Configure reviewer permissions
   - Enable audit logging (if not already)

---

## Step 2: Create AI Agent Policy

### Policy Configuration

1. Click **Policies** > **Create policy**
2. Select **Custom policy**

### Policy Settings

| Setting | Value |
|---------|-------|
| Name | `AI Agent Supervision - Zone 3` |
| Description | Flag Zone 3 Copilot Studio agent outputs for FINRA 3110 review |
| Supervised users | Select security group containing Zone 3 agents |
| Direction | Inbound and Outbound |
| Locations | Microsoft 365 Copilot, Copilot Studio |

### Conditions

Configure one or more condition groups:

**Condition Group 1: Regulatory Keywords**

| Condition | Operator | Value |
|-----------|----------|-------|
| Message contains words | Any of these | investment advice, guaranteed return, risk-free, no risk, performance guarantee |

**Condition Group 2: Sensitive Information Types**

| Condition | Operator | Value |
|-----------|----------|-------|
| Content contains sensitive info | Any of these | U.S. Social Security Number, Credit Card Number, U.S. Bank Account Number |

**Condition Group 3: Custom Trainable Classifier (Optional)**

Create a custom classifier for firm-specific content:

1. Go to **Data classification** > **Trainable classifiers**
2. Create classifier for firm-specific regulatory terms
3. Add to policy conditions

### Review Settings

| Setting | Value |
|---------|-------|
| Reviewer | FSW Queue Manager security group |
| Escalation | CCO or Senior Compliance Officer |
| Retention | 7 years (firm policy; FINRA 4511 requires minimum 6 years) |

---

## Step 3: Create Zone-Specific Policies

Repeat policy creation for each zone with appropriate sampling:

### Zone 1 Policy

| Setting | Value |
|---------|-------|
| Name | `AI Agent Supervision - Zone 1 Sampling` |
| Sampling | 5–25% of messages (varies by tier) |
| Conditions | Same as Zone 3 |
| Reviewers | FSW Supervisor group |

### Zone 2 Policy

| Setting | Value |
|---------|-------|
| Name | `AI Agent Supervision - Zone 2` |
| Sampling | 10–50% of messages (varies by tier) |
| Conditions | Same as Zone 3 |
| Reviewers | FSW Supervisor group |

### Zone 3 Policy

| Setting | Value |
|---------|-------|
| Name | `AI Agent Supervision - Zone 3` |
| Sampling | 100% of messages |
| Conditions | Same as Zone 3 |
| Reviewers | FSW Queue Manager group |

---

## Step 4: Configure API Access

The FSW-IngestFlaggedItems flow needs API access to retrieve alerts.

### App Registration

1. Open [Entra ID portal](https://entra.microsoft.com)
2. Navigate to **App registrations** > **New registration**
3. Configure:
   - Name: `FSW-CommunicationCompliance-Reader`
   - Supported account types: Single tenant
   - Redirect URI: None (daemon app)

### API Permissions

Add these permissions:

| API | Permission | Type |
|-----|------------|------|
| Microsoft Purview | Compliance Administrator role | Application |
| Microsoft Graph | `User.Read.All` | Application |

Grant admin consent after adding permissions.

### Client Secret

1. Go to **Certificates & secrets**
2. Create new client secret
3. Copy value immediately (shown only once)
4. Store in Azure Key Vault as `FSW-CC-ClientSecret`

---

## Step 5: Get Policy IDs

The flow needs policy IDs to filter alerts:

### Via PowerShell

```powershell
Connect-IPPSSession

Get-SupervisoryReviewPolicy |
    Select-Object Name, Guid, Enabled |
    Format-Table
```

### Via Purview Compliance API

> **Note:** The `security/alerts_v2` Graph API endpoint serves Microsoft Defender
> alerts, not Communication Compliance alerts. Use PowerShell (shown above) or the
> Purview Compliance portal REST API to retrieve policy IDs.

Note the policy GUID values for flow configuration.

---

## Step 6: Test Policy Detection

### Create Test Message

1. Use a test agent in Zone 3 environment
2. Send message containing flagged content:
   ```
   This investment is guaranteed to return 20% annually with no risk.
   ```

### Verify Alert Creation

1. Wait 15-30 minutes for processing
2. Navigate to Communication Compliance > Alerts
3. Verify alert appears for test message

### Verify API Access

```powershell
# Test API access via PowerShell
Connect-IPPSSession

# Verify policies are visible
Get-SupervisoryReviewPolicy | Select-Object Name, Guid, Enabled | Format-Table

# Verify app registration token acquisition
$token = Get-MsalToken -ClientId $clientId -ClientSecret $secret -TenantId $tenantId
Write-Host "Token acquired successfully: $($token.AccessToken.Substring(0,20))..."
```

---

## Keyword Library

### Investment Advice Keywords

```
investment advice
investment recommendation
you should buy
you should sell
guaranteed return
risk-free investment
no risk
performance guarantee
double your money
high yield
hot stock
inside information
sure thing
can't lose
```

### Customer Complaint Keywords

```
complaint
dissatisfied
unhappy
escalate
manager
supervisor
sue
lawsuit
attorney
lawyer
regulator
FINRA
SEC
arbitration
```

### Suitability Keywords

```
suitable
appropriate
recommend
risk tolerance
investment objective
time horizon
financial situation
net worth
income
age
```

---

## Policy Tuning

### Reducing False Positives

1. **Add exclusions** for common business terms
2. **Increase confidence threshold** for sensitive info types
3. **Use trainable classifiers** trained on your firm's content
4. **Review false positives weekly** and adjust conditions

### Monitoring Policy Health

| Metric | Target | Action if Below |
|--------|--------|-----------------|
| False positive rate | < 20% | Tune conditions |
| Detection coverage | > 95% | Add conditions |
| Processing latency | < 30 min | Check service health |

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| No alerts generated | Policy not enabled | Enable policy |
| Alerts delayed > 1 hour | Service backlog | Wait or check service health |
| API returns 403 | Insufficient permissions | Grant admin consent |
| Missing agent messages | Agent not in scope | Add agent to supervised users |

---

## Related Resources

- [Microsoft Learn: Communication Compliance](https://learn.microsoft.com/en-us/purview/communication-compliance)
- [Control 1.10: Communication Compliance](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.10-communication-compliance-monitoring.md)
- [FINRA Notice 24-09: Gen AI Guidance](https://www.finra.org/rules-guidance/notices/24-09)
