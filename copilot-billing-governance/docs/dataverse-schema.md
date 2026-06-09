# Dataverse Schema Reference

> Auto-generated from `create_cbg_dataverse_schema.py`. Do not edit manually.

All column logical names are the SchemaName lowercased (Dataverse never inserts underscores between words). Use the **Logical Name** column when writing OData `$select` / `$filter` queries.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_CbgBillingPolicy | fsi_cbgbillingpolicy | Pay-as-you-go (PAYG) Copilot billing policy backed by an Azure subscription. Tenant ceiling is 50 PAYG policies; PAYG provides budget alerts, not a hard-stop. | fsi_name |
| fsi_CbgCreditPolicy | fsi_cbgcreditpolicy | Prepaid Copilot credit policy (standalone hard-stop, no Azure subscription). Tenant ceiling is 10 credit policies; credit policies are Chat-only today. | fsi_name |
| fsi_CbgEntitlement | fsi_cbgentitlement | Policy-level entitlement rule keyed on agent pathway, used by the switch-on-pathway entitlement engine. | fsi_name |
| fsi_CbgEntitlementMaterialized | fsi_cbgentitlementmaterialized | Per-(agent, user) entitlement decision cache with a time-to-live, materialized to avoid recomputing the full decision tree on every read. | fsi_name |
| fsi_CbgCoverageGap | fsi_cbgcoveragegap | Per-agent coverage-gap aggregate produced by the pre-enforcement analysis (monitor-only first). One row per agent, with a capped sample of blocked UPNs. | fsi_name |
| fsi_CbgAgentCap | fsi_cbgagentcap | Per-agent monthly credit cap and month-to-date consumption. Enforcement mode degrades to detect-and-alert where a hard-stop write API is unavailable. | fsi_name |
| fsi_CbgApprovedGroupPolicy | fsi_cbgapprovedgrouppolicy | Admission-gated registry of Entra security groups approved as maker, audience, or billing groups. Adopts the hardened ASARD shape: groups that are not security-enabled, or that are mail-enabled, are rejected at admission time. | fsi_name |

## Columns

### fsi_CbgBillingPolicy (`fsi_cbgbillingpolicy`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Display name of the PAYG billing policy |  |
| fsi_PolicyType | fsi_policytype | String | No | Always PAYG for this table; retained for cross-table joins. |  |
| fsi_AzureSubscriptionId | fsi_azuresubscriptionid | String | Yes | Azure subscription GUID backing this PAYG billing policy. |  |
| fsi_BillingInstanceId | fsi_billinginstanceid | String | No | Power Platform admin center billing-policy identifier. |  |
| fsi_EnvironmentName | fsi_environmentname | String | No | Power Platform environment connected to this billing policy. |  |
| fsi_IsConnected | fsi_isconnected | Boolean | No | Whether the two-step add-then-connect flow has completed (environment connected). | `1` = Yes, `0` = No |
| fsi_SpendScope | fsi_spendscope | Picklist | No | Surface this PAYG policy covers (SharePoint grounding stays PAYG). | **fsi_cbg_spendscope**: `100000000` = Chat - Credit-eligible, `100000001` = SharePoint - PAYG-only, `100000002` = Mixed |
| fsi_BudgetAlertThreshold | fsi_budgetalertthreshold | Decimal | No | Budget-alert threshold in tenant currency. Informational alert only; PAYG has no hard-stop. |  |
| fsi_BudgetAlertConfigured | fsi_budgetalertconfigured | Boolean | No | Whether a budget alert has been configured for this policy. | `1` = Yes, `0` = No |
| fsi_PolicyCountSnapshot | fsi_policycountsnapshot | Integer | No | Observed number of PAYG billing policies in the tenant at last sync (ceiling is 50). |  |
| fsi_ZoneClassification | fsi_zoneclassification | Picklist | No | Governance zone this policy applies to. | **fsi_cbg_zoneclassification**: `100000000` = Team (Zone 2), `100000001` = Enterprise (Zone 3) |
| fsi_LastSyncedAt | fsi_lastsyncedat | DateTime | No | When this policy record was last reconciled from the platform. |  |
| fsi_Notes | fsi_notes | Memo | No | Free-text operational notes for this policy. |  |

### fsi_CbgCreditPolicy (`fsi_cbgcreditpolicy`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Display name of the prepaid credit policy |  |
| fsi_PolicyType | fsi_policytype | String | No | Always Credit for this table; retained for cross-table joins. |  |
| fsi_CreditPolicyId | fsi_creditpolicyid | String | Yes | Microsoft 365 admin center Copilot credit-policy identifier. |  |
| fsi_PrepaidCreditPack | fsi_prepaidcreditpack | Integer | No | Prepaid credit pack size per month (non-rolling pack is 25,000 credits/month). |  |
| fsi_CreditsConsumed | fsi_creditsconsumed | Integer | No | Credits consumed against this policy in the current billing period. |  |
| fsi_HardStopEnabled | fsi_hardstopenabled | Boolean | No | Whether the standalone prepaid hard-stop is active for this credit policy. | `1` = Yes, `0` = No |
| fsi_NonRolling | fsi_nonrolling | Boolean | No | Whether the credit pack is non-rolling (unused credits do not carry over). | `1` = Yes, `0` = No |
| fsi_SurfaceScope | fsi_surfacescope | Picklist | No | Surfaces covered. Credit policies are Chat-only today; SharePoint stays PAYG. | **fsi_cbg_spendscope**: `100000000` = Chat - Credit-eligible, `100000001` = SharePoint - PAYG-only, `100000002` = Mixed |
| fsi_AssignedGroupId | fsi_assignedgroupid | String | No | Entra security group object ID whose members are in this credit scope. |  |
| fsi_PolicyCountSnapshot | fsi_policycountsnapshot | Integer | No | Observed number of credit policies in the tenant at last sync (ceiling is 10). |  |
| fsi_ZoneClassification | fsi_zoneclassification | Picklist | No | Governance zone this policy applies to. | **fsi_cbg_zoneclassification**: `100000000` = Team (Zone 2), `100000001` = Enterprise (Zone 3) |
| fsi_LastSyncedAt | fsi_lastsyncedat | DateTime | No | When this policy record was last reconciled from the platform. |  |
| fsi_Notes | fsi_notes | Memo | No | Free-text operational notes for this policy. |  |

### fsi_CbgEntitlement (`fsi_cbgentitlement`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Display name of the entitlement rule |  |
| fsi_Pathway | fsi_pathway | Picklist | Yes | Agent pathway this entitlement rule applies to. | **fsi_cbg_pathway**: `100000000` = none, `100000001` = mcp-cs, `100000002` = mcp-agentbuilder, `100000003` = api-direct, `100000004` = metered, `100000005` = unmapped |
| fsi_PolicyType | fsi_policytype | Picklist | No | Billing or credit policy backing this entitlement. | **fsi_cbg_policytype**: `100000000` = PAYG, `100000001` = Credit |
| fsi_RequiresLicense | fsi_requireslicense | Boolean | No | Whether the user must hold a Microsoft 365 Copilot license under this rule. | `1` = Yes, `0` = No |
| fsi_RequiresBillingScope | fsi_requiresbillingscope | Boolean | No | Whether the user must also be in billing scope (mcp-cs generative/grounded answers bill even for licensed users). | `1` = Yes, `0` = No |
| fsi_ZeroRatingResolved | fsi_zeroratingresolved | Boolean | No | Whether the zero-rating conflict is resolved for this rule. Default false keeps the rule fail-closed pending the June 2026 Licensing Guide. | `1` = Yes, `0` = No |
| fsi_EligibleGroupId | fsi_eligiblegroupid | String | No | Entra security group object ID whose members are eligible under this rule. |  |
| fsi_SpendScope | fsi_spendscope | Picklist | No | Surface this entitlement governs. | **fsi_cbg_spendscope**: `100000000` = Chat - Credit-eligible, `100000001` = SharePoint - PAYG-only, `100000002` = Mixed |
| fsi_ZoneClassification | fsi_zoneclassification | Picklist | No | Governance zone this entitlement applies to. | **fsi_cbg_zoneclassification**: `100000000` = Team (Zone 2), `100000001` = Enterprise (Zone 3) |
| fsi_Notes | fsi_notes | Memo | No | Free-text notes describing the rule rationale and source. |  |

### fsi_CbgEntitlementMaterialized (`fsi_cbgentitlementmaterialized`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Composite agent/user cache key (agentid:userupn) |  |
| fsi_AgentId | fsi_agentid | String | Yes | Unique identifier of the agent for this materialized decision. |  |
| fsi_UserUpn | fsi_userupn | String | Yes | User principal name the decision was computed for. |  |
| fsi_Pathway | fsi_pathway | Picklist | No | Classified pathway used for this decision. | **fsi_cbg_pathway**: `100000000` = none, `100000001` = mcp-cs, `100000002` = mcp-agentbuilder, `100000003` = api-direct, `100000004` = metered, `100000005` = unmapped |
| fsi_Decision | fsi_decision | Picklist | No | Materialized entitlement decision. | **fsi_cbg_decision**: `100000000` = Allow, `100000001` = Block, `100000002` = Allow - Eligibility N/A, `100000003` = Fail-open - Anomaly, `100000004` = Fail-closed - Zero-rating Unresolved |
| fsi_DecisionReason | fsi_decisionreason | Picklist | No | Reason code when the decision is a block (nullable for allows). | **fsi_cbg_blockreason**: `100000000` = No eligible cohort, `100000001` = Missing license, `100000002` = Zero-rating unresolved - fail-closed, `100000003` = Not in credit scope, `100000004` = Policy cap exceeded, `100000005` = Unmapped pathway |
| fsi_SpendScope | fsi_spendscope | Picklist | No | Surface the decision applies to. | **fsi_cbg_spendscope**: `100000000` = Chat - Credit-eligible, `100000001` = SharePoint - PAYG-only, `100000002` = Mixed |
| fsi_SourcePolicyId | fsi_sourcepolicyid | String | No | Identifier of the policy that drove this decision. |  |
| fsi_EvaluatedAt | fsi_evaluatedat | DateTime | No | When this decision was computed. |  |
| fsi_TtlExpiresAt | fsi_ttlexpiresat | DateTime | No | When this cached decision expires and must be recomputed. |  |
| fsi_Notes | fsi_notes | Memo | No | Free-text notes or evaluation trace for this decision. |  |
| fsi_RelatedCoverageGapId | fsi_relatedcoveragegapid | Lookup | No | Optional link to the per-agent coverage-gap row this decision rolls up to. |  |

### fsi_CbgCoverageGap (`fsi_cbgcoveragegap`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Display name of the analyzed agent |  |
| fsi_AgentId | fsi_agentid | String | Yes | Unique identifier of the analyzed agent. |  |
| fsi_AgentName | fsi_agentname | String | No | Display name of the analyzed agent. |  |
| fsi_Pathway | fsi_pathway | Picklist | No | Classified pathway for the agent. | **fsi_cbg_pathway**: `100000000` = none, `100000001` = mcp-cs, `100000002` = mcp-agentbuilder, `100000003` = api-direct, `100000004` = metered, `100000005` = unmapped |
| fsi_EligibleUsers | fsi_eligibleusers | Integer | No | Count of users eligible to use the agent under current policies. |  |
| fsi_BlockedUsersCount | fsi_blockeduserscount | Integer | No | Count of otherwise-intended users who would be blocked by current policies. |  |
| fsi_BlockedSampleUpns | fsi_blockedsampleupns | Memo | No | Capped JSON sample of blocked user UPNs (sample size is bounded to avoid row blow-up). |  |
| fsi_BlockReasonSummary | fsi_blockreasonsummary | Picklist | No | Dominant block reason across the blocked cohort. | **fsi_cbg_blockreason**: `100000000` = No eligible cohort, `100000001` = Missing license, `100000002` = Zero-rating unresolved - fail-closed, `100000003` = Not in credit scope, `100000004` = Policy cap exceeded, `100000005` = Unmapped pathway |
| fsi_SpendScope | fsi_spendscope | Picklist | No | Surface-aware spend scope (Chat vs SharePoint) for this agent. | **fsi_cbg_spendscope**: `100000000` = Chat - Credit-eligible, `100000001` = SharePoint - PAYG-only, `100000002` = Mixed |
| fsi_GroupSizePartition | fsi_groupsizepartition | Integer | No | Total intended-audience size used to partition large groups above threshold T. |  |
| fsi_MonitorOnly | fsi_monitoronly | Boolean | No | Whether this gap row is monitor-only (no enforcement action taken). | `1` = Yes, `0` = No |
| fsi_AnalyzedAt | fsi_analyzedat | DateTime | No | When the coverage-gap analysis produced this row. |  |
| fsi_RetainUntil | fsi_retainuntil | DateTime | No | Retention horizon after which this aggregate row may be purged. |  |
| fsi_Notes | fsi_notes | Memo | No | Free-text notes for this coverage-gap row. |  |

### fsi_CbgAgentCap (`fsi_cbgagentcap`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Display name of the per-agent cap record |  |
| fsi_AgentId | fsi_agentid | String | Yes | Unique identifier of the capped agent. |  |
| fsi_MonthlyCreditCap | fsi_monthlycreditcap | Integer | No | Per-agent monthly credit ceiling. |  |
| fsi_CreditsConsumedMtd | fsi_creditsconsumedmtd | Integer | No | Credits consumed by this agent month-to-date. |  |
| fsi_EnforcementMode | fsi_enforcementmode | Picklist | No | Whether the cap is hard-stopped or degrades to detect-and-alert where no write API exists. | **fsi_cbg_enforcementmode**: `100000000` = Detect-and-alert, `100000001` = Hard-stop |
| fsi_CapEnforced | fsi_capenforced | Boolean | No | Whether enforcement is currently active for this agent. | `1` = Yes, `0` = No |
| fsi_ZoneClassification | fsi_zoneclassification | Picklist | No | Governance zone this cap applies to. | **fsi_cbg_zoneclassification**: `100000000` = Team (Zone 2), `100000001` = Enterprise (Zone 3) |
| fsi_LastEvaluatedAt | fsi_lastevaluatedat | DateTime | No | When this cap was last evaluated against consumption. |  |
| fsi_Notes | fsi_notes | Memo | No | Free-text notes for this cap record. |  |

### fsi_CbgApprovedGroupPolicy (`fsi_cbgapprovedgrouppolicy`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Display name of the approved Entra security group |  |
| fsi_GroupId | fsi_groupid | String | Yes | Entra security group object ID. |  |
| fsi_GroupLayer | fsi_grouplayer | Picklist | Yes | Governance layer this group serves (maker, audience, or billing). | **fsi_cbg_grouplayer**: `100000000` = Maker, `100000001` = Audience, `100000002` = Billing |
| fsi_SecurityEnabled | fsi_securityenabled | Boolean | Yes | Whether the Entra group has securityEnabled=true at admission. Groups with securityEnabled=false are rejected. | `1` = Yes, `0` = No |
| fsi_MailEnabled | fsi_mailenabled | Boolean | Yes | Whether the Entra group has mailEnabled at admission. Mail-enabled distribution groups are rejected. | `1` = Yes, `0` = No |
| fsi_GroupTypes | fsi_grouptypes | String | No | Comma-separated Entra groupTypes values at admission (e.g. DynamicMembership, Unified). |  |
| fsi_ZoneClassification | fsi_zoneclassification | Picklist | No | Governance zone this group applies to. | **fsi_cbg_zoneclassification**: `100000000` = Team (Zone 2), `100000001` = Enterprise (Zone 3) |
| fsi_IsActive | fsi_isactive | Boolean | Yes | Whether this group registration is currently active. | `1` = Yes, `0` = No |
| fsi_ApprovedBy | fsi_approvedby | String | No | UPN of the person who approved this group. |  |
| fsi_ApprovedAt | fsi_approvedat | DateTime | No | When this group was approved. |  |
| fsi_PolicyNotes | fsi_policynotes | Memo | No | Additional notes or context for this registration. |  |

## Option Sets

### fsi_cbg_pathway

Classified consumption pathway for an agent (evaluated before eligibility).

| Value | Label |
|---|---|
| 100000000 | none |
| 100000001 | mcp-cs |
| 100000002 | mcp-agentbuilder |
| 100000003 | api-direct |
| 100000004 | metered |
| 100000005 | unmapped |

### fsi_cbg_policytype

Whether a policy is pay-as-you-go (Azure subscription) or prepaid Copilot credit.

| Value | Label |
|---|---|
| 100000000 | PAYG |
| 100000001 | Credit |

### fsi_cbg_decision

Outcome of a switch-on-pathway entitlement evaluation for an (agent, user) pair.

| Value | Label |
|---|---|
| 100000000 | Allow |
| 100000001 | Block |
| 100000002 | Allow - Eligibility N/A |
| 100000003 | Fail-open - Anomaly |
| 100000004 | Fail-closed - Zero-rating Unresolved |

### fsi_cbg_spendscope

Surface a charge applies to. Chat is credit-eligible; SharePoint stays PAYG.

| Value | Label |
|---|---|
| 100000000 | Chat - Credit-eligible |
| 100000001 | SharePoint - PAYG-only |
| 100000002 | Mixed |

### fsi_cbg_blockreason

Dominant reason a user is blocked from a metered agent (coverage-gap summary).

| Value | Label |
|---|---|
| 100000000 | No eligible cohort |
| 100000001 | Missing license |
| 100000002 | Zero-rating unresolved - fail-closed |
| 100000003 | Not in credit scope |
| 100000004 | Policy cap exceeded |
| 100000005 | Unmapped pathway |

### fsi_cbg_grouplayer

Which governance layer a registered Entra security group serves.

| Value | Label |
|---|---|
| 100000000 | Maker |
| 100000001 | Audience |
| 100000002 | Billing |

### fsi_cbg_enforcementmode

Whether a per-agent cap is enforced via hard-stop or degrades to detect-and-alert.

| Value | Label |
|---|---|
| 100000000 | Detect-and-alert |
| 100000001 | Hard-stop |

### fsi_cbg_zoneclassification

Governance zone a billing or credit policy applies to.

| Value | Label |
|---|---|
| 100000000 | Team (Zone 2) |
| 100000001 | Enterprise (Zone 3) |

## Relationships

| SchemaName | Referenced Entity | Referencing Entity | Lookup Column |
|---|---|---|---|
| fsi_CbgCoverageGap_CbgEntitlementMaterialized | fsi_cbgcoveragegap | fsi_cbgentitlementmaterialized | fsi_RelatedCoverageGapId |

