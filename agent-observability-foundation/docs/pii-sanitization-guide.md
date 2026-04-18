# PII Sanitization Guide

Decision framework for handling personally identifiable information (PII) in Copilot Studio telemetry.

## Overview

Copilot Studio agents emit telemetry to Application Insights via the customEvents table. This telemetry may contain PII in the `customDimensions` field, particularly when "Log sensitive Activity properties" is enabled in the agent configuration. FSI organizations must handle this data appropriately to meet GLBA 501(b) customer data protection requirements and state privacy laws.

This guide provides a decision framework and field-level recommendations for sanitizing PII in Copilot Studio telemetry.

## Decision Framework

Use this 4-step decision tree to determine how to handle each telemetry field:

```
Step 1: Does field contain customer-identifiable data?
        |
        +-- NO --> RETAIN the field as-is
        |
        +-- YES --> Step 2: Is field needed for analytics/troubleshooting?
                    |
                    +-- NO --> DROP the field entirely
                    |
                    +-- YES --> Step 3: Is reversibility required for compliance audit?
                                |
                                +-- YES --> ENCRYPT (reversible with key management)
                                |
                                +-- NO --> Step 4: Default action
                                           |
                                           +-- HASH (one-way, preserves cardinality)
```

### Decision Summary

| Decision | When to Use | Trade-offs |
|----------|-------------|------------|
| **Retain** | Non-PII fields needed for analytics | No privacy impact |
| **Drop** | PII not needed for any analytics or troubleshooting | Lose data for correlation |
| **Hash** | PII needed for cardinality/correlation, reversibility not required | Cannot recover original value |
| **Encrypt** | PII needed AND must be recoverable for compliance audit | Requires key management infrastructure |

---

## Field-Level Recommendations

The following table documents known Copilot Studio telemetry fields in the customDimensions payload and recommended handling:

| Field | Contains PII? | Recommendation | Rationale |
|-------|---------------|----------------|-----------|
| `customDimensions.text` | **YES** | Drop or hash | Customer prompts may contain names, account numbers, SSNs, and other sensitive data |
| `customDimensions.speak` | **YES** | Drop or hash | Speech output may echo PII from conversation context |
| `customDimensions.fromName` | **YES** | Hash (one-way) | User display name; not needed for analytics but useful for correlation |
| `customDimensions.recipientName` | **YES** | Hash (one-way) | Agent or user identity; agent ID is sufficient for most analytics |
| `customDimensions.channelId` | **NO** | Retain | Channel type (msteams, webchat, directline) is not PII |
| `customDimensions.locale` | **NO** | Retain | Language preference (en-US, es-MX) is not PII |
| `customDimensions.designMode` | **NO** | Retain | Boolean flag indicating test vs production mode |
| `customDimensions.TopicName` | **NO** | Retain | Intent classification topic; does not contain PII |

### PII Field Details

**`customDimensions.text`** - Contains the actual user input text. This is the highest-risk field for PII exposure. Users may enter:
- Full names, addresses, phone numbers
- Social Security numbers
- Bank account or credit card numbers
- Medical information
- Other sensitive personal data

**`customDimensions.speak`** - Contains the agent's spoken response text. May echo back user-provided PII or generate PII from knowledge sources.

**`customDimensions.fromName`** - User's display name from the channel (e.g., Teams display name). While this identifies the user, it typically doesn't contain sensitive data beyond the name itself.

**`customDimensions.recipientName`** - Name of the message recipient (usually the agent). May contain user identity information in some channel configurations.

---

## Implementation Options

### Option 1: Drop Sensitive Fields (Recommended Default)

**Implementation:** Disable "Log sensitive Activity properties" in Copilot Studio.

**Steps:**
1. Open Copilot Studio
2. Navigate to Settings > Application Insights
3. Ensure "Log sensitive Activity properties" is **disabled**
4. Save configuration

**Pros:**
- Simplest implementation
- No sensitive data reaches Application Insights
- No ongoing maintenance required

**Cons:**
- Lose conversation content for troubleshooting
- Cannot analyze user input patterns

**Recommendation:** Use this option unless you have a specific business requirement for conversation content in telemetry.

---

### Option 2: Hash Fields (Post-Ingestion)

**Implementation:** Use KQL transformation or Logic App to hash PII fields after ingestion.

**Note:** Copilot Studio telemetry is server-side; SDK-level telemetry processors are not available. Hashing must occur post-ingestion.

**Approach A: KQL Transform (Log Analytics Workspace Transformation)**

```kusto
// Example transformation rule (configure at workspace level)
source
| extend customDimensions = dynamic_to_json(
    bag_merge(
        bag_remove_keys(todynamic(customDimensions), dynamic(["text", "speak", "fromName"])),
        bag_pack(
            "text_hash", hash_sha256(tostring(customDimensions.text)),
            "fromName_hash", hash_sha256(tostring(customDimensions.fromName))
        )
    )
)
```

**Approach B: Logic App Preprocessing**

Create a Logic App triggered by Event Grid that:
1. Receives telemetry events before ingestion
2. Hashes specified fields using built-in hash functions
3. Forwards sanitized events to Application Insights

**Pros:**
- Preserves cardinality for analytics (same input = same hash)
- Enables user session correlation without exposing identity
- One-way transformation meets privacy requirements

**Cons:**
- Requires additional infrastructure
- Adds processing latency
- Cannot recover original values

---

### Option 3: Encrypt Fields (Complex - Phase 2+ Consideration)

**Implementation:** Use Azure Key Vault for reversible encryption of PII fields.

**Note:** This approach is complex and typically not recommended for Phase 1. Consider only if you have a regulatory requirement to recover original values from telemetry.

**High-Level Architecture:**
1. Logic App receives telemetry events
2. Encrypts PII fields using Key Vault managed key
3. Stores encrypted telemetry in Application Insights
4. Authorized compliance reviewers can decrypt using Key Vault access

**Pros:**
- Reversible for compliance audit
- Strong encryption with key management
- Audit trail of decryption operations

**Cons:**
- Complex infrastructure
- Key rotation complexity
- Higher operational overhead
- Potential compliance risk if keys are compromised

---

## Default Recommendation

For Phase 1 deployment, we recommend **Option 1: Drop Sensitive Fields** by disabling sensitive logging in Copilot Studio.

**Rationale:**
1. Simplest to implement and maintain
2. Eliminates PII exposure risk in telemetry
3. Session metrics and interaction patterns are still captured
4. Conversation content can be captured separately in a compliance-managed system if needed

If your organization requires conversation content in telemetry:
- Implement Option 2 (hashing) in Phase 2 when KQL query library is established
- Document the business justification and obtain compliance approval
- Ensure appropriate access controls are in place for hashed telemetry

---

## Verification

To verify PII handling configuration:

1. **Check Copilot Studio settings:**
   - Confirm "Log sensitive Activity properties" is disabled

2. **Query Application Insights for PII:**
   ```kusto
   customEvents
   | where name == "CopilotInteraction"
   | project timestamp, customDimensions
   | take 10
   ```
   - Review `customDimensions` payload
   - Confirm `text` and `speak` fields are absent or hashed

3. **Audit existing telemetry:**
   ```kusto
   customEvents
   | where isnotempty(customDimensions.text)
   | summarize count() by bin(timestamp, 1d)
   ```
   - If count > 0, sensitive logging may have been enabled historically
   - Consider purging historical data if compliance concern

---

## Regulatory Alignment

| Regulation | Requirement | How This Guide Supports |
|------------|-------------|------------------------|
| **GLBA 501(b)** | Safeguard customer NPI | Drop or hash fields containing customer data |
| **CCPA/CPRA** | Data minimization | Retain only fields needed for stated purpose |
| **State Privacy Laws** | PII protection | Framework for identifying and handling PII |

---

*PII Sanitization Guide version: 1.2.0*
*Last updated: February 2026*
