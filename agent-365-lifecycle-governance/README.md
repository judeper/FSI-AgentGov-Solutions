# Agent 365 Lifecycle Governance

> **Status:** v1.1.1 — GA (Agent 365 GA: May 1, 2026)

Automated lifecycle governance for AI agents using Microsoft Agent 365, Entra ID Governance, and Power Platform. Covers the full lifecycle loop: sponsor assignment, access reviews, inactivity detection, deactivation workflows, and deletion holds with zone-based policy enforcement.

See [CHANGELOG](./CHANGELOG.md) for version history.

## Overview

As FSI organizations deploy AI agents at scale through Copilot Studio, Agent Builder, and Azure AI Foundry, the agent fleet grows faster than governance processes can keep pace. Agents are onboarded without sponsors, run indefinitely without access reviews, accumulate stale permissions, and persist after their business purpose has ended.

This solution automates enforcement on top of Agent 365 and Entra ID Governance to address the core FSI examiner question: *"How do you verify that every AI agent has an accountable owner, operates under least-privilege access, is reviewed on a defined cadence, and is decommissioned when no longer needed?"*

> **Important:** All Entra Agent 365 API calls are gated by the `IsAgent365LifecycleEnabled` feature flag. Set to `"true"` after deployment validation — Agent 365 is now GA for OBO agents (May 2026). When disabled, flows terminate gracefully without calling external APIs.
>
> **Boundary:** This solution complements the native Agent 365 Admin Center governance surfaces. Use the Agent 365 Admin Center and the related FSI framework guidance for Agent Registry inventory, pending requests, ownerless-agent queues, and overview analytics. There is no separate live Agent 365 governance-monitor solution in this repository. Use this solution for automated sponsor enforcement, access reviews, inactivity handling, deactivation workflows, and deletion holds.

## Features

| Capability | Description |
|-----------|-------------|
| **Sponsor Enforcement** | Hourly detection and assignment of sponsors to unsponsored agents via Entra Agent Registry |
| **Zone-Based Access Reviews** | Quarterly (Zone 3), semi-annual (Zone 2), or annual (Zone 1) Entra access reviews with default-deny |
| **Inactivity Detection** | Daily scan using Entra sign-in logs and PPAC activity data with conservative handling of missing data |
| **Deactivation Workflows** | Approval-gated agent disabling with zone-based deletion hold periods (30 or 90 days) |
| **Sponsor Monitoring** | Weekly validation of sponsor account status with auto-reassignment on departure |
| **Deletion Hold Enforcement** | Daily enforcement of mandatory hold periods before permanent identity deletion |
| **Audit Trail** | All lifecycle events logged to append-only Dataverse table (requires no-delete security roles and 7-year LTR configuration for immutability) |

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    POLICY LAYER                                  │
│    Microsoft Entra ID Governance + Agent 365 Admin Center        │
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
| **Agent 365** | GA licensing ($15/user/month or M365 E7) |
| **Entra ID Governance P2** | Access reviews, lifecycle workflows |
| **Power Automate Premium** | HTTP connector, Power Platform Admin connector |
| **Dataverse** | Managed Environment with system administrator role |
| **Entra Security Groups** | `FSI-AllAgentIdentities`, `FSI-Zone3-Agents` |
| **API Permissions** | 7 application permissions on Managed Identity |

Full requirements: [docs/prerequisites.md](./docs/prerequisites.md)

## Quick Start

1. Complete [DELIVERY-CHECKLIST.md](./DELIVERY-CHECKLIST.md) Phase 0 (licensing verification)
2. Create Entra security groups and lifecycle workflows ([docs/prerequisites.md](./docs/prerequisites.md))
3. Deploy Dataverse schema:
   ```bash
   python scripts/create_alg_dataverse_schema.py --tenant-id <id> --environment-url <url> --client-id <app-id> --interactive
   python scripts/create_alg_environment_variables.py --tenant-id <id> --environment-url <url> --client-id <app-id> --interactive
   python scripts/create_alg_connection_references.py --tenant-id <id> --environment-url <url> --client-id <app-id> --interactive
   ```
4. Run baseline assessment:
   ```powershell
   .\scripts\Deploy-LifecycleGovernance-Baseline.ps1 -DataverseEnvironmentUrl "https://org.crm.dynamics.com" -DefaultSponsorUPN "governance@contoso.com"
   ```
5. Build flows in Power Automate designer following [docs/flow-configuration.md](./docs/flow-configuration.md)
6. Set `IsAgent365LifecycleEnabled` to `"true"` after deployment validation (Agent 365 is now GA for OBO agents)
7. Validate compliance:
   ```powershell
   .\scripts\Test-LifecycleCompliance.ps1 -DataverseEnvironmentUrl "https://org.crm.dynamics.com"
   ```

## Regulatory Alignment

| Regulation | Requirement | How This Solution Helps |
|-----------|-------------|------------------------|
| **OCC 2011-12 / Fed SR 11-7** | Model risk management — models must have designated owners | Sponsor assignment enforced at onboarding; access reviews on defined cadence |
| **FINRA Rule 3110** | Supervisory procedures for all systems | Lifecycle workflow automation helps maintain active supervisors for every agent |
| **FINRA Rule 4511** | Books and records — lifecycle events must be logged and retained | Append-only Dataverse compliance event log (supports 7-year LTR when no-delete security roles configured) |
| **SEC 17a-3/4** | 7-year retention for broker-dealer records | Dataverse Long-Term Retention policy on lifecycle event table |
| **GLBA 501(b)** | Access to customer data must be controlled and revoked when no longer needed | Automated access expiration and deactivation workflows |
| **SOX 302/404** | Access rights must be periodically reviewed and certified | Zone-based access review workflows with certifier accountability |

## Known Limitations

### Relationship to Native Agentic Center of Enablement (2026 Wave 1)

Microsoft's [Agentic Center of Enablement](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/power-platform-governance-administration/automate-governance-agentic-center-enablement) (Agentic CoE) introduces three AI-powered agents to the Power Platform admin center: a **Highlights agent** for daily tenant activity snapshots, an **Insights agent** for continuous governance issue scanning (ownerless resources, default environment activity), and an **Action Plan agent** for automated remediation plans.

**Relationship to this solution:** The Agentic CoE provides **tenant-wide visibility and general governance automation**. This solution provides **FSI-specific lifecycle enforcement** that goes beyond what the native CoE covers:

- Zone-based access review cadences (quarterly/semi-annual/annual) aligned to regulatory requirements
- Sponsor enforcement with auto-reassignment on departure
- Mandatory deletion hold periods (30/90 days) before permanent identity removal
- Immutable compliance event logging with 7-year LTR for FINRA 4511 / SEC 17a-4
- Integration with Entra ID Governance lifecycle workflows and conditional access

FSI organizations should use the Agentic CoE for tenant-level visibility and general governance, and deploy this solution for the regulatory-grade lifecycle controls that financial services examiners require.

| Limitation | Impact | Mitigation |
|-----------|--------|------------|
| Agent 365 GA for OBO agents (May 2026); autonomous agents with full Entra identities remain in Frontier preview | Lifecycle workflow tasks may not be available for autonomous agents | Feature flag disables gracefully; Dataverse-only tracking remains active |
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

1.1.1

## License

[MIT](../LICENSE)
