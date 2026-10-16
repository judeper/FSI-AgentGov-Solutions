# Flow Configuration Guide

> **Solution:** Agent Sharing Access Restriction Detector (ASARD)
> **Version:** v2.0.2

This document provides an overview of the two Power Automate cloud flows required by the ASARD solution. For detailed step-by-step build instructions, see the [README](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/agent-sharing-access-restriction-detector/README.md) and the [ASARD Deployment Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-deployment-guide/) in FSI-AgentGov.

> **Compatibility warning (2026-10-16):** The companion deployment, exception, and troubleshooting playbooks describe legacy `gov_asard*` tables and Python commands and refer to exported `src/` flows that are not shipped here. Use this guide, `prerequisites.md`, and `dataverse-schema.md` for this implementation. Build flows manually; see the [technical verification record](technical-verification-2026-10-16.md#companion-playbooks-outside-this-worktree) for the exact mismatches.

## Flows Overview

### 1. Remediation Approval Workflow

**Purpose:** Governance-gated remediation of agent sharing violations. When the detection engine identifies agents shared with unauthorized security groups, this flow routes each violation through an approval process before applying sharing corrections.

**Key behaviors:**

- Queries `fsi_agentsharingcompliances` for agents with `fsi_compliancestatus = NonCompliant`
- For manual Web API paging, follows the complete server-issued `@odata.nextLink` unchanged until absent (up to 5,000 standard-table rows per page); Dataverse does not support `$skip`. For the Dataverse **List rows** connector action, configure pagination and its threshold instead. See [Web API paging](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/query/page-results) and [List rows pagination](https://learn.microsoft.com/en-us/power-automate/dataverse/list-rows#turn-on-pagination).
- Processes agents sequentially (concurrency = 1) with configurable approval timeout (default: 7 days)
- Queries approved security groups from `fsi_approvedsecuritygrouppolicies` per agent zone
- Builds remediation plan (principals to remove/add) and sends approval request to governance lead
- On approval: applies the sharing correction to the `bots` table by writing `accesscontrolpolicy = 2` (Group membership) **and** `authorizedsecuritygroupids` in the **same** request, then reads the row back and asserts both values stuck before recording success (see **Remediation build requirements** below)
- On rejection: records rejection with 7-day cooldown to prevent repeated requests

**Known limitation:** The [28-day approval wait caveat](https://learn.microsoft.com/en-us/power-automate/approvals-known-issues) is distinct from the [30-day total run limit](https://learn.microsoft.com/en-us/power-automate/limits-and-config#duration-limits). Seven days is ASARD's configured per-approval timeout. Four sequential full waits consume 28 days plus overhead; five need 35 days. Bound the batch and persist overflow for a later run. Do not rely on a synchronously awaited child flow to extend the parent run. Keep **Create an approval** and **Wait for an approval** close together to reduce the documented early-response race (the lab build uses **Start and wait for an approval**). See [approval build invariants](approvals-limits.md).

#### Remediation build requirements — chat-ACL plane (C1/C2)

ASARD remediation targets the **runtime chat ACL** plane only — `bot.accesscontrolpolicy` plus `bot.authorizedsecuritygroupids`. The authoring-share plane (`PrincipalObjectAccess` Editor/Viewer assignments) and the M365 Copilot Agent Store plane are out of scope (see [`LAB-VALIDATION.md`](../LAB-VALIDATION.md)). Flow builders **must** implement the following, which support compliance with the Control 1.18 (RBAC) and 2.8 (Segregation of Duties) record-keeping and access-control expectations behind FINRA Rule 4511, SOX Section 404, and GLBA Section 501(b):

1. **Single-write policy + groups (C1).** When restricting an over-shared agent, set `accesscontrolpolicy = 2` (Group membership) **and** the comma-delimited `authorizedsecuritygroupids` (up to 20 Entra group GUIDs, ≤739 characters) in the **same** "Update a row" request. The [bot reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/bot#authorizedsecuritygroupids) states that the group list is ignored unless the policy is Group membership. This is a field-usage semantic, not a data-layer write rejection: the lab persisted a group list under policy `1`, without proving runtime access changed. Do **not** split these into two writes.
2. **Read-back assertion (C1).** Immediately after the write, GET `bots(<botid>)?$select=accesscontrolpolicy,authorizedsecuritygroupids` and assert (a) `accesscontrolpolicy = 2` and (b) the returned `authorizedsecuritygroupids` equals the requested list (case-normalized; sort before comparing in production). If either check fails, record `fsi_compliancestatus = Error (100000003)` and `fsi_remediationstatus = Failed (100000004)` — never `Completed`. This verifies metadata persistence, not chat-time enforcement.
3. **Create/Wait adjacency and timeout (H3).** Keep approval creation and the wait adjacent as ASARD's conservative build convention, or use **Start and wait for an approval** as in the lab. Microsoft recommends keeping split actions close together, not mandatory designer adjacency. Configure `P7D` from `fsi_ASARD_ApprovalTimeoutDays` (default 7), handle timeout/rejection/cancellation without writing sharing changes, and bound total work using [approvals-limits.md](approvals-limits.md). Sequential processing (concurrency = 1) alone does not bound cumulative run duration.
4. **First-class messages vs. direct write (C2).** The `bot` table exposes first-class `GrantAccess` / `ModifyAccess` / `RevokeAccess` messages for **record sharing** (`PrincipalObjectAccess`), not for setting chat-ACL columns. ASARD's documented chat-ACL remediation updates the fields in requirement 1, including policy changes such as `3` → `2`. Document this split; do not substitute `ModifyAccess` for the chat-ACL field update or PATCH `principalobjectaccess` rows directly.
5. **Empirical enforcement (C1/C2).** Direct-write enforcement and propagation lag are not assumed. Verify on a disposable **published** agent with real groups and test users: confirm an allowed user's chat succeeds, remove the test user's group through the approval-gated change, and test denied access on each intended channel. Record channel, authentication settings, group membership, write/read-back times, and observed access outcomes in [`LAB-VALIDATION.md`](../LAB-VALIDATION.md). Microsoft's up-to-one-hour window concerns **new Managed Environment sharing rules**, not a documented SLA for direct bot-column PATCH propagation; do not use it as the runtime pass criterion.

### 2. Exception Review Workflow

**Purpose:** Automated lifecycle management for time-bound sharing exceptions. Runs on a daily schedule to identify expiring and expired exceptions, notify governance leads, and auto-reset expired records.

**Key behaviors:**

- Runs daily via recurrence trigger
- Queries exceptions expiring within the next 14 days → sends warning notification via Teams adaptive card
- Queries exceptions past their expiration date → resets `fsi_compliancestatus` from `Exception` (100000002) to `NonCompliant` (100000001), clears expiration fields (preserves justification and audit trail), and sends expired notification
- Loads adaptive card templates via HTTP GET from configurable URL (`fsi_ASARD_AdaptiveCardTemplateUrl`)
- A single standard-table page returns up to 5,000 rows; configure **List rows** pagination/threshold or exhaust every Web API `@odata.nextLink` separately for expiring and expired queries. Verify a multi-page fixture and record total retrieved/processed counts; views alone do not establish completeness.

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
| `fsi_ASARD_BAPAdminAPIBaseUrl` | BAP Admin API base URL for administrative calls — override the default if needed; bot sharing detection/remediation uses the Dataverse Web API `bots` table |
| `fsi_ASARD_ApprovalTimeoutDays` | Number of days before an unanswered approval request times out (default: 7) |
| `fsi_ASARD_GovernanceLeadEmail` | Email address for the governance lead who receives approval requests and exception notifications |

## Current Microsoft Learn Sharing Guidance

- Managed Environment agent sharing limits control new **Editor** and **Viewer** sharing assignments; existing access is not removed automatically when limits are configured.
- **Editor** permissions are individual-only. **Viewer** permissions can be granted to individuals or security groups unless Managed Environment rules restrict security group sharing.
- ASARD evaluates the [Dataverse `bot.accesscontrolpolicy`](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/bot#accesscontrolpolicy) values (`0` = Any; `1` = Agent readers; `2` = Group membership; `3` = Any (multi-tenant)) and `authorizedsecuritygroupids` rather than a `sharingtype` column. Older documentation called value `1` "Copilot readers"; the numeric value is unchanged. These labels alone do not prove effective channel access; verify authentication and runtime behavior separately.
- Power Automate adaptive card data templating is not fully supported in all hosts; use the documented string replacement or templating SDK pipeline per template and validate JSON in the Adaptive Card designer.

## Related Resources

- [README — Full Solution Documentation](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/agent-sharing-access-restriction-detector/README.md)
- [ASARD Deployment Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-deployment-guide/)
- [ASARD Exception Management](https://judeper.github.io/FSI-AgentGov/playbooks/asard-exception-management/)
- [ASARD Troubleshooting Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-troubleshooting-guide/)
