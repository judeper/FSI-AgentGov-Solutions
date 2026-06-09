# Agent Eligibility Gateway Dataverse Schema

> Auto-generated from `scripts/create_aeg_dataverse_schema.py`. Do not edit manually.
> Regenerate with `python scripts/create_aeg_dataverse_schema.py --output-docs`.

## Overview

The Agent Eligibility Gateway uses a single optional Dataverse table, `fsi_aegdecisionlog`, to persist the per-decision audit trail emitted by the Azure API Management gateway. The table is organization-owned and audit-enabled so it can serve as an immutable record; remove Write/Delete privileges after deployment. Persisting decisions here is optional — the gateway emits the same record to its telemetry sink regardless — but doing so surfaces the decisions on the Copilot Hub / governance dashboard (control 3.8).

## Tables

| SchemaName | Logical Name | Entity Set | Ownership | Description |
|---|---|---|---|---|
| fsi_AegDecisionLog | fsi_aegdecisionlog | fsi_aegdecisionlogs | OrganizationOwned | Immutable per-decision audit log of Agent Eligibility Gateway allow/deny outcomes |

## Columns

### fsi_AegDecisionLog (`fsi_aegdecisionlog`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String (200) | Yes | Decision identifier (typically the correlation ID) |  |
| fsi_CorrelationId | fsi_correlationid | String (200) | Yes | Correlation ID stamped on the request and the governed response |  |
| fsi_DecisionTime | fsi_decisiontime | DateTime | Yes | UTC timestamp when the gateway rendered the decision |  |
| fsi_AgentId | fsi_agentid | String (200) | Yes | Identifier of the agent the request targeted |  |
| fsi_UserObjectId | fsi_userobjectid | String (100) | No | Microsoft Entra object ID (oid) of the caller; pseudonymous, not the UPN |  |
| fsi_Channel | fsi_channel | Option Set | No | Owned channel that the gateway fronted | `fsi_aeg_channel` |
| fsi_Pathway | fsi_pathway | Option Set | No | Classified pathway used by the entitlement contract | `fsi_aeg_pathway` |
| fsi_Decision | fsi_decision | Option Set | Yes | Allow or deny outcome | `fsi_aeg_decision` |
| fsi_DenyReason | fsi_denyreason | Option Set | No | Reason a decision resolved to deny (None for allow) | `fsi_aeg_denyreason` |
| fsi_HttpStatus | fsi_httpstatus | Integer | No | HTTP status code returned to the caller (200 allow, 401/403 deny) |  |
| fsi_Anomaly | fsi_anomaly | Boolean | No | True when the pathway could not be classified and the request was allowed fail-open | `1` = Yes, `0` = No |
| fsi_PolicyVersion | fsi_policyversion | String (50) | No | Version string of the gateway policy that rendered the decision |  |
| fsi_GatewayInstance | fsi_gatewayinstance | String (200) | No | API Management instance/region that rendered the decision |  |
| fsi_Zone | fsi_zone | Option Set | No | Governance zone classification | `fsi_acv_zone` |
| fsi_RawContext | fsi_rawcontext | Memo | No | JSON snapshot of the decision inputs for audit reconstruction |  |

## Option Sets

### Shared

#### fsi_acv_zone

Governance zone classification

| Value | Label |
|---|---|
| 100000000 | Unclassified |
| 100000001 | Zone 1 |
| 100000002 | Zone 2 |
| 100000003 | Zone 3 |

### Agent Eligibility Gateway

#### fsi_aeg_decision

Allow or deny decision rendered by the gateway

| Value | Label |
|---|---|
| 100000000 | Allow |
| 100000001 | Deny |

#### fsi_aeg_denyreason

Reason an allow/deny decision resolved to deny (None for allow)

| Value | Label |
|---|---|
| 100000000 | None |
| 100000001 | JwtValidationFailed |
| 100000002 | MissingRequiredClaim |
| 100000003 | OutOfPolicyAudience |
| 100000004 | NotInEligibleCohort |
| 100000005 | AgentNonCompliant |
| 100000006 | GovernanceStoreUnavailable |

#### fsi_aeg_pathway

Classified billing/runtime pathway used by the entitlement contract

| Value | Label |
|---|---|
| 100000000 | None |
| 100000001 | McpCopilotStudio |
| 100000002 | McpAgentBuilder |
| 100000003 | ApiDirect |
| 100000004 | Metered |
| 100000005 | Unmapped |

#### fsi_aeg_channel

Owned channel the gateway fronts (first-party surfaces are out of scope)

| Value | Label |
|---|---|
| 100000000 | CustomWeb |
| 100000001 | DirectLine |

