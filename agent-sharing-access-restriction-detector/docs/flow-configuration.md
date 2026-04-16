# Flow Configuration Guide

> **Solution:** Agent Sharing Access Restriction Detector (ASARD)
> **Version:** v1.0.2

This document provides an overview of the two Power Automate cloud flows required by the ASARD solution. For detailed step-by-step build instructions, see the [README](../README.md) and the [ASARD Deployment Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-deployment-guide/) in FSI-AgentGov.

## Flows Overview

### 1. Remediation Approval Workflow

**Purpose:** Governance-gated remediation of agent sharing violations. When the detection engine identifies agents shared with unauthorized security groups, this flow routes each violation through an approval process before applying sharing corrections.

**Key behaviors:**

- Queries `fsi_agentsharingcompliances` for agents with `fsi_compliancestatus = NonCompliant`
- Paginates results using `@odata.nextLink` (up to 5,000 records per page)
- Processes agents sequentially (concurrency = 1) with configurable approval timeout (default: 7 days)
- Queries approved security groups from `fsi_approvedsecuritygrouppolicies` per agent zone
- Builds remediation plan (principals to remove/add) and sends approval request to governance lead
- On approval: applies sharing corrections via BAP Admin API PATCH, runs post-remediation validation
- On rejection: records rejection with 7-day cooldown to prevent repeated requests

**Known limitation:** The sequential approval loop with 7-day timeouts means >4 agents may exceed Power Automate's 30-day maximum runtime limit. For environments with >4 non-compliant agents, consider a batch approval or child flow pattern.

### 2. Exception Review Workflow

**Purpose:** Automated lifecycle management for time-bound sharing exceptions. Runs on a daily schedule to identify expiring and expired exceptions, notify governance leads, and auto-reset expired records.

**Key behaviors:**

- Runs daily via recurrence trigger
- Queries exceptions expiring within the next 14 days → sends warning notification via Teams adaptive card
- Queries exceptions past their expiration date → resets `fsi_compliancestatus` from `Exception` (2) to `NonCompliant` (1), clears expiration fields (preserves justification and audit trail), and sends expired notification
- Loads adaptive card templates via HTTP GET from configurable URL (`fsi_ASARD_AdaptiveCardTemplateUrl`)
- Retrieves up to 5,000 records per query (Dataverse maximum per request)

## Adaptive Card Templates

The following adaptive card templates are available in `templates/` for use with these flows and external integrations:

| Template | File | Purpose |
|----------|------|---------|
| **Compliance Alert** | `adaptive-card-asard-alert.json` | Summary notification after detection scans — shows violation counts, top violations, and scan metadata |
| **Remediation Approval** | `adaptive-card-asard-remediation-approval.json` | Approval request card — displays current sharing, proposed changes, zone context, and impact analysis |
| **Remediation Result** | `adaptive-card-asard-remediation-result.json` | Outcome notification — supports success, rejection, and error states with conditional sections |
| **Exception Expiring** | `adaptive-card-asard-exception-expiring.json` | Warning card for exceptions expiring within 14 days — includes renewal instructions |
| **Exception Expired** | `adaptive-card-asard-exception-expired.json` | Notification for expired exceptions auto-reset to NonCompliant status |

### Template Rendering

Templates use two rendering pipelines:

- **String replacement** (`{{variable}}`): Used by the alert and exception cards. Rendered via Power Automate `replace()` functions.
- **Adaptive Cards Templating SDK** (`${variable}`): Used by the remediation approval and result cards. Rendered via the Adaptive Cards Templating SDK.

Do not mix the two syntaxes within a single card. See each template's `_metadata.renderingPipeline` field for the correct pipeline.

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `fsi_ASARD_AdaptiveCardTemplateUrl` | URL for adaptive card template hosting (exception review flow loads templates via HTTP GET) |
| `fsi_ASARD_BAPAdminAPIBaseUrl` | BAP Admin API base URL — override for GCC, GCC-High, or DoD sovereign cloud deployments |
| `fsi_ASARD_ApprovalTimeoutDays` | Number of days before an unanswered approval request times out (default: 7) |
| `fsi_ASARD_GovernanceLeadEmail` | Email address for the governance lead who receives approval requests and exception notifications |

## Related Resources

- [README — Full Solution Documentation](../README.md)
- [ASARD Deployment Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-deployment-guide/)
- [ASARD Exception Management](https://judeper.github.io/FSI-AgentGov/playbooks/asard-exception-management/)
- [ASARD Troubleshooting Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-troubleshooting-guide/)
