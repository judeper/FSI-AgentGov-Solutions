---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P4, P5, P6]
applicable_drivers:
  - ai_governance
  - ai_strategy
  - technology_data
coe_function: enable
---
# Agent 365 Lifecycle Governance

> **Version:** v1.1.5
> **Status:** Live
> **Validated against framework version:** v1.6.0
> **Upstream Microsoft dependency:** Mixed — Microsoft Agent 365 is generally available for commercial tenants, but Agent Registry and package-management APIs remain preview and should be validated before the feature flag is enabled.

Automated lifecycle governance for AI agents using Microsoft Agent 365, Entra ID Governance, and Power Platform. Covers the full lifecycle loop: sponsor assignment, access reviews, inactivity detection, deactivation workflows, and deletion holds with zone-based policy enforcement.

See [CHANGELOG](./CHANGELOG.md) for version history.

## Overview

As FSI organizations deploy AI agents at scale through Copilot Studio, Agent Builder, and Azure AI Foundry, the agent fleet grows faster than governance processes can keep pace. Agents are onboarded without sponsors, run indefinitely without access reviews, accumulate stale permissions, and persist after their business purpose has ended.

This solution automates lifecycle governance on top of Microsoft Agent 365, Microsoft Entra Agent ID, and Microsoft Entra ID Governance to address the core FSI examiner question: *"How do you verify that every AI agent has an accountable owner, operates under least-privilege access, is reviewed on a defined cadence, and is decommissioned when no longer needed?"*

> **Important:** All Microsoft Agent 365 / Microsoft Entra Agent ID API calls are gated by the `IsAgent365LifecycleEnabled` feature flag. Microsoft Agent 365 is generally available for the Commercial segment, while Agent Registry API surfaces remain beta/preview and subject to change. Set the flag to `"true"` only after tenant licensing, permissions, and API validation are complete. When disabled, flows terminate gracefully without calling external APIs.
>
> **Boundary:** This solution complements the native Microsoft Agent 365 governance surfaces. Use the Microsoft 365 admin center (where Agent 365 surfaces appear) and the related FSI framework guidance for Agent Registry inventory, pending requests, ownerless-agent queues, and overview analytics. There is no separate live Agent 365 governance-monitor solution in this repository. Use this solution for automated sponsor enforcement, access reviews, inactivity handling, deactivation workflows, and deletion holds.

## Features

| Capability | Description |
|-----------|-------------|
| **Sponsor Enforcement** | Hourly detection and owner assignment for ownerless agent instances via the Microsoft Agent 365 / Microsoft Entra Agent Registry `agentInstances` API |
| **Zone-Based Access Reviews** | Quarterly (Zone 3), semi-annual (Zone 2), or annual (Zone 1) Entra access reviews with default-deny |
| **Inactivity Detection** | Daily scan using Entra sign-in logs and PPAC activity data with conservative handling of missing data |
| **Deactivation Workflows** | Approval-gated agent disabling with zone-based deletion hold periods (30 or 90 days) |
| **Sponsor Monitoring** | Weekly validation of sponsor account status with auto-reassignment on departure |
| **Deletion Hold Enforcement** | Daily validation of hold periods before permanent identity deletion |
| **Audit Trail** | All lifecycle events logged to an append-only Dataverse table when no-delete security roles and appropriate retention policies are configured |

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    POLICY LAYER                                  │
│    Microsoft Entra ID Governance + Microsoft Agent 365 (registry, identity)        │
│  (Lifecycle Workflows, Access Reviews, Conditional Access)       │
└────────────────────────┬─────────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────────┐
│                 ORCHESTRATION LAYER                              │
│              Power Automate Cloud Flows (6 flows)                │
│  Flow 1: Sponsor Enforcement       Flow 4: Deactivation         │
│  Flow 2: Access Reviews            Flow 5: Sponsor Monitoring   │
│  Flow 3: Inactivity Detection      Flow 6: Deletion Hold        │
└────────────────────────┬─────────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────────┐
│                 PERSISTENCE LAYER                                │
│              Dataverse — 5 Custom Tables                         │
│  AgentLifecycleRecord · SponsorAssignment · AccessReview         │
│  DeactivationRequest · LifecycleComplianceEvent (append-only)    │
└────────────────────────┬─────────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────────┐
│                    ACTION LAYER                                  │
│  Teams Notifications · Power Automate Approvals                  │
│  Entra Lifecycle Workflows · Power Platform Admin                │
└──────────────────────────────────────────────────────────────────┘
```

## Control Mapping

| Type | Controls |
|------|----------|
| **Primary** | Control 2.3 — Change Management and Release Planning |
| **Secondary** | Control 1.2 (Agent Registry), Control 1.11 (Conditional Access), Control 2.1 (Managed Environments), Control 2.8 (Access Control and Segregation of Duties), Control 2.12 (Supervision and Oversight — FINRA 3110), Control 3.1 (Audit Logging) |
| **Pillar** | Pillar 2: Management |
| **Solution Type** | Detective + Preventive + Corrective |

## Zone Applicability

| Zone | Sponsor | Review Cadence | Inactivity Threshold | Deletion Hold | CA Policy |
|------|---------|---------------|---------------------|---------------|-----------|
| Zone 1 (Personal) | Recommended | Annual | 180 days | 30 days | Not required |
| Zone 2 (Team/Departmental) | Required | Semi-Annual | 90 days | 30 days | Not required |
| Zone 3 (Enterprise/Customer-Facing) | Required at onboarding | Quarterly | 30 days | 90 days | Required |

## Data Model

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `fsi_agentlifecyclerecord` | Master lifecycle state per agent | fsi_agentid, fsi_governancezone, fsi_lifecyclestage, fsi_sponsorupn |
| `fsi_sponsorassignment` | Sponsor history and accountability | fsi_sponsorupn, fsi_assignmentreason, fsi_iscurrent |
| `fsi_accessreview` | Access review records and decisions | fsi_entrareviewid, fsi_reviewstatus, fsi_certifierdecision |
| `fsi_deactivationrequest` | Deactivation approvals and outcomes | fsi_triggerreason, fsi_approvalstatus, fsi_deletionholduntil |
| `fsi_lifecyclecomplianceevent` | Append-only lifecycle event log (configure no-delete security roles for immutability) | fsi_eventtype, fsi_complianceimpact, fsi_timestamp |

Full schema reference: [docs/dataverse-schema.md](./docs/dataverse-schema.md)

## Prerequisites

| Requirement | Details |
|------------|---------|
| **Microsoft Agent 365** | Per-user Microsoft Agent 365 licensing or Microsoft 365 E7; verify current pricing and SKU eligibility in Microsoft licensing guidance |
| **Microsoft Entra ID Governance or Microsoft Entra Suite** | Access reviews and sponsor-user lifecycle workflows |
| **Power Automate Premium** | HTTP connector, Power Platform Admin connector |
| **Dataverse** | Managed Environment with system administrator role |
| **Entra Security Groups** | `FSI-AllAgentIdentities`, `FSI-Zone3-Agents` |
| **API Permissions** | Graph application permissions on managed identity or workload identity, including `AgentInstance.ReadWrite.All` |

Full requirements: [docs/prerequisites.md](./docs/prerequisites.md)

## Quick Start

1. Complete [DELIVERY-CHECKLIST.md](./DELIVERY-CHECKLIST.md) Phase 0 (licensing verification)
2. Create Entra security groups and lifecycle workflows ([docs/prerequisites.md](./docs/prerequisites.md))
3. Deploy Dataverse schema:
   ```bash
   python scripts/create_alg_dataverse_schema.py --tenant-id <id> --environment-url <url> --auth-mode managed-identity
   python scripts/create_alg_environment_variables.py --tenant-id <id> --environment-url <url> --auth-mode managed-identity
   python scripts/create_alg_connection_references.py --tenant-id <id> --environment-url <url> --auth-mode managed-identity
   # For admin-workstation setup, use --interactive --client-id <app-id> instead.
   ```
4. Run baseline assessment:
   ```powershell
   .\scripts\Deploy-LifecycleGovernance-Baseline.ps1 -DataverseEnvironmentUrl "https://org.crm.dynamics.com" -DefaultSponsorUPN "governance@example.com"
   ```
5. Build flows in Power Automate designer following [docs/flow-configuration.md](./docs/flow-configuration.md)
6. Set `IsAgent365LifecycleEnabled` to `"true"` after tenant licensing, Graph beta endpoint, and flow validation
7. Validate compliance:
   ```powershell
   .\scripts\Test-LifecycleCompliance.ps1 -DataverseEnvironmentUrl "https://org.crm.dynamics.com"
   ```

## Environment Variables

All configurable thresholds and settings are stored as Dataverse environment variables, deployed by `scripts/create_alg_environment_variables.py`. Key variables:

| SchemaName | Type | Default | Purpose |
|-----------|------|---------|---------|
| `fsi_ALG_IsAgent365LifecycleEnabled` | String | `false` | Feature flag gating all Agent 365 API calls |
| `fsi_ALG_InactivityThresholdZone1` | Decimal | 180 | Inactivity threshold (days) for Zone 1 agents |
| `fsi_ALG_InactivityThresholdZone2` | Decimal | 90 | Inactivity threshold (days) for Zone 2 agents |
| `fsi_ALG_InactivityThresholdZone3` | Decimal | 30 | Inactivity threshold (days) for Zone 3 agents |
| `fsi_ALG_DeletionHoldDays` | Decimal | 30 | Grace period (days) before agent deletion executes after deactivation approval. Zone 3 agents typically override to 90. |
| `fsi_ALG_AgentRegistryApiVersion` | String | `v1.0` | Graph API version pinning for Agent Registry (`agentInstances`) calls. Pin to a known-good version to avoid breaking changes during preview-to-GA transitions. |

> **Tip:** To override `fsi_ALG_DeletionHoldDays` for Zone 3 agents, the deactivation flow reads this variable as the default and applies the zone-specific override (90 days for Zone 3) from the zone applicability table above. Adjust the variable value when your organization's retention policy differs from the default.

> **Tip:** Pin `fsi_ALG_AgentRegistryApiVersion` to `beta` only during non-production validation of preview Agent Registry API features. In production, use `v1.0` or the latest GA version.

## Regulatory Alignment

| Regulation | Requirement | How This Solution Helps |
|-----------|-------------|------------------------|
| **OCC 2011-12 / Fed SR 11-7** | Model risk management — designated owners, documented oversight | If an agent is within the firm's model inventory, sponsor assignment and access reviews on a defined cadence support OCC 2011-12 / SR 11-7 governance expectations. Firms determine which agents qualify as "models." |
| **FINRA Rule 3110** | Reasonably designed supervisory system | Lifecycle workflow automation supports firm-defined supervisory procedures, ownership accountability, and review evidence for agent operations; firms set the substance of their WSPs. |
| **FINRA Rule 4511** | Books and records — lifecycle events must be created, preserved, and retrievable | Append-only Dataverse compliance event log captures lifecycle events; firms should validate SEC 17a-4 storage/format requirements and use a SEC 17a-4-compliant archive where required. |
| **SEC 17a-3/4** | Record creation and preservation requirements vary by record category | Dataverse with Long-Term Retention captures lifecycle records; retention periods (commonly 3 years for communications, 6 years for books and records) should be configured per the firm's record schedule and validated with legal/compliance. |
| **GLBA 501(b)** | Customer information security — access controlled and revoked when no longer needed | Automated access expiration and deactivation workflows support timely revocation per the firm's information security program. |
| **SOX 302/404** | Periodic access reviews and certifier accountability | Zone-based access review workflows with certifier accountability aid in periodic certification of access to financially significant systems. |

> **Note:** This solution provides controls and evidence that *support* meeting these regulations. It does not by itself constitute compliance. Firms must validate their full control posture with legal, compliance, and external auditors.

## Known Limitations

### Relationship to Native Agentic Center of Enablement (2026 Wave 1)

Microsoft's [Agentic Center of Enablement](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/power-platform-governance-administration/automate-governance-agentic-center-enablement) (Agentic CoE) introduces three AI-powered agents to the Power Platform admin center: a **Highlights agent** for daily tenant activity snapshots, an **Insights agent** for continuous governance issue scanning (ownerless resources, default environment activity), and an **Action Plan agent** for automated remediation plans.

**Relationship to this solution:** The Agentic CoE provides **tenant-wide visibility and general governance automation**. This solution provides **FSI-specific lifecycle enforcement** that goes beyond what the native CoE covers:

- Zone-based access review cadences (quarterly/semi-annual/annual) aligned to zone policy, firm risk assessment, and written supervisory procedures
- Sponsor enforcement with auto-reassignment on departure
- Configurable deletion hold periods (default 30 days, 90 days for Zone 3) before permanent identity removal
- Append-only compliance event logging with Dataverse Long-Term Retention when no-delete roles are configured (firms should map evidence to FINRA 4511 / SEC 17a-4 schedules and add a compliant archive where required)
- Integration with Entra ID Governance lifecycle workflows (for sponsor/user lifecycle) and conditional access

FSI organizations should use the Agentic CoE for tenant-level visibility and general governance, and deploy this solution for the lifecycle controls that financial services examiners typically expect.

| Limitation | Impact | Mitigation |
|-----------|--------|------------|
| Microsoft Agent 365 is GA for the Commercial segment, but Agent Registry and Package Management Graph APIs remain beta/preview and include May 2026 convergence notices | API shape or permissions may change before v1.0 | Feature flag disables gracefully; validate `agentInstances` and package APIs in a non-production tenant before enabling |
| `AuditLog.Read.All` may be restricted | Inactivity detection falls back to PPAC timestamps | Flow 3 handles gracefully — sets source to "Unknown", does not trigger deactivation |
| Daily polling scales poorly past 100 agents | Flow 2 Part C may run long | Consider Graph change notifications (webhooks) as agent count grows |
| Agentic user deletion is automatic | Deleting agent instance also deletes mailbox and OneDrive | 90-day deletion hold for Zone 3 provides investigation window |

## Cross-Solution Dependencies

| Dependency | Solution | Purpose |
|-----------|----------|---------|
| `fsi_environment_policy` table | [agent-registry-automation](../agent-registry-automation/) | Zone detection for new agents (defaults to Zone 2 if not deployed) |

## Documentation

| Document | Description |
|----------|-------------|
| [docs/prerequisites.md](./docs/prerequisites.md) | Licensing, Entra groups, API permissions, lifecycle workflows |
| [docs/dataverse-schema.md](./docs/dataverse-schema.md) | Auto-generated schema reference (tables, columns, option sets) |
| [docs/flow-configuration.md](./docs/flow-configuration.md) | Step-by-step build instructions for all 6 flows |
| [docs/canvas-app-guide.md](./docs/canvas-app-guide.md) | Agent Lifecycle Admin Portal build guide |
| [docs/power-bi-dashboard.md](./docs/power-bi-dashboard.md) | Compliance dashboard measures and layout |
| [docs/troubleshooting.md](./docs/troubleshooting.md) | Common issues and resolutions |
| [DELIVERY-CHECKLIST.md](./DELIVERY-CHECKLIST.md) | Pre-deployment validation and post-deployment verification |

## Related Controls

- [Control 2.3 — Change Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/2.3-change-management.md)
- [Control 1.2 — Agent Registry](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/1.2-agent-registry.md)
- [Control 1.11 — Conditional Access](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/1.11-conditional-access.md)
- [Control 2.1 — Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/2.1-managed-environments.md)
- [Control 2.8 — Access Control](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/2.8-access-control.md)
- [Control 2.12 — Supervision](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/2.12-supervision.md)
- [Control 3.1 — Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/3.1-audit-logging.md)

## Version

1.1.5

## License

[MIT](../LICENSE)
