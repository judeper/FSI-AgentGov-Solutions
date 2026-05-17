---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P5]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# Cross-Tenant and External Sharing Governance

> **Version:** v1.0.3
> **Status:** Live
> **Validated against framework version:** v1.6.0

Automated detection, validation, and remediation of cross-tenant access for Power Platform AI agents in FSI environments.

See [CHANGELOG](./CHANGELOG.md) for version history.

## Overview

Power Platform Tenant Isolation is **OFF by default**, meaning any tenant can establish inbound or outbound connector connections unless explicitly blocked. This is a critical governance gap for financial services organizations subject to GLBA, OCC, and SOX requirements for controlling third-party data access. Without active governance, agents can silently access external tenant resources — or external users can invoke internal agents — with no audit trail or approval workflow.

This solution governs cross-tenant access across three distinct layers: **Power Platform Tenant Isolation** (connector-level blocking/allowing at the tenant boundary), **Entra Cross-Tenant Access Policies** (identity-level B2B inbound/outbound controls), and **Copilot Studio Agent Shares** (agent-level sharing with external guest users). Each layer operates independently and addresses a distinct risk surface; a defensible posture validates all three together along with adjacent controls (Conditional Access, Tenant Restrictions v2, SharePoint external sharing).

The solution continuously detects unauthorized cross-tenant configurations, maintains an authoritative allow list of approved external tenants with dual-approval onboarding, and writes append-only compliance events to a Dataverse long-term retention plan (configure 7-year retention to support SEC 17a-4 and FINRA 4511 record-keeping requirements). Note: SEC 17a-4 WORM/non-rewriteable storage requirements are met by the underlying Azure Storage immutability policy; Dataverse LTR provides retention but customers must validate WORM characteristics with their counsel.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.1 - Restrict Agent Publishing](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.1-restrict-agent-publishing-by-authorization/) | Publishing authorization enforcement for externally shared agents |
| [1.18 - RBAC and Access Control](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.18-rbac-and-access-control/) | Role-based access control for cross-tenant governance workflows |
| [2.1 - Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-governance/2.1-managed-environments/) | Environment-level governance for cross-tenant policy enforcement |
| [2.8 - Access Control and Segregation of Duties](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-governance/2.8-access-control-and-segregation-of-duties/) | Dual-approval separation for tenant onboarding |
| [1.7 - Audit Logging and Monitoring](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.7-audit-logging-and-monitoring/) | Append-only compliance event logging for cross-tenant activity |
| [1.11 - Conditional Access](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.11-conditional-access/) | Conditional Access policy alignment for external access |

## Regulatory Alignment

| Regulation | Requirement |
|------------|-------------|
| GLBA 501(b) | Safeguards against unauthorized cross-boundary data access |
| OCC 2011-12 / Fed SR 11-7 | Helps support model risk management requirements where AI agents are governed as models; consult internal model risk management for applicability |
| SOX 302/404 (ICFR scope) | Helps support IT general controls for external party access to systems within ICFR scope |
| FINRA 3110 | Helps meet supervision requirements for cross-tenant agent activity |
| FINRA 4370 | Business continuity considerations for restoration of allow lists |
| NYDFS 23 NYCRR 500.11 | Helps support third-party service provider security policies |
| FFIEC | Third-party risk due diligence and ongoing monitoring |

> **Note:** No single control satisfies any regulation in isolation. This solution supports compliance with these requirements when deployed as part of a comprehensive governance program.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    DETECTION LAYER                               │
│   Flow 1: Validate-TenantIsolation-Daily (MI-ReadOnly)           │
│   Flow 2: Detect-ExternalAgentShares-Daily (MI-ReadOnly)         │
│   Flow 3: Audit-EntraCrossTenantSettings-Weekly (MI-ReadOnly)    │
└────────────────────────┬─────────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────────┐
│                 GOVERNANCE LAYER                                 │
│   Flow 4: Execute-ExternalTenantOnboarding (MI-ReadWrite)        │
│   Flow 5: Remediate-UnauthorizedExternalAccess (MI-ReadWrite)    │
│   Flow 6: Send-AnnualReviewReminders-Daily (MI-ReadOnly)         │
└────────────────────────┬─────────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────────────┐
│                 PERSISTENCE LAYER                                │
│   Dataverse — 5 Custom Tables                                    │
└──────────────────────────────────────────────────────────────────┘
```

## Three-Layer Governance Model

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 1: Power Platform Tenant Isolation                       │
│  Scope: Connector-level blocking/allowing at tenant boundary    │
│  API: PPAC / Get-PowerAppTenantIsolationPolicy                  │
│  Detection: Flow 1 — Validate-TenantIsolation-Daily             │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 2: Entra Cross-Tenant Access Policies                    │
│  Scope: Identity-level B2B inbound/outbound controls            │
│  API: MS Graph /policies/crossTenantAccessPolicy                │
│  Detection: Flow 3 — Audit-EntraCrossTenantSettings-Weekly      │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 3: Copilot Studio Agent Shares                           │
│  Scope: Agent-level sharing with external/guest users           │
│  API: GET .../bots/{botId}/roleAssignments                      │
│  Detection: Flow 2 — Detect-ExternalAgentShares-Daily           │
└─────────────────────────────────────────────────────────────────┘
```

## Dependencies

| Solution | Purpose |
|----------|---------|
| `agent-registry-automation` | Provides `fsi_agentinventory.fsi_zone` for severity assignment |
| `unrestricted-agent-sharing-detector` | Covers internal oversharing; this solution covers external |

> **Both solutions must be deployed before activating this solution.** The `fsi_agentinventory` table from agent-registry-automation is required for zone-based severity classification. The unrestricted-agent-sharing-detector handles internal sharing violations while this solution handles cross-tenant external sharing.

## Components

| Component | Type | Description |
|-----------|------|-------------|
| Flow 1: Validate-TenantIsolation-Daily | Power Automate (documentation-only) | Daily tenant isolation status audit via PPAC API |
| Flow 2: Detect-ExternalAgentShares-Daily | Power Automate (documentation-only) | Guest user detection across agent role assignments (5-value method) |
| Flow 3: Audit-EntraCrossTenantSettings-Weekly | Power Automate (documentation-only) | Weekly Entra CTA policy baseline comparison |
| Flow 4: Execute-ExternalTenantOnboarding | Power Automate (documentation-only) | Dual-approval onboarding with Expired timeout |
| Flow 5: Remediate-UnauthorizedExternalAccess | Power Automate (documentation-only) | Approval-gated remediation of unauthorized external access |
| Flow 6: Send-AnnualReviewReminders-Daily | Power Automate (documentation-only) | Annual review reminders at 90/30/overdue thresholds |
| `fsi_approvedexternaltenant` | Dataverse Table | Authoritative external tenant allow list |
| `fsi_externalsharefinding` | Dataverse Table | External sharing violations per agent |
| `fsi_tenantisolationrecord` | Dataverse Table | Daily tenant isolation audit snapshots |
| `fsi_entractarecord` | Dataverse Table | Weekly Entra CTA audit snapshots |
| `fsi_crosstenantcomplianceevent` | Dataverse Table | Immutable compliance event log (7-year LTR) |
| Registry Portal | Canvas App (documentation-only) | Approved tenant management and review interface |
| Cross-Tenant Dashboard | Power BI (documentation-only) | Compliance posture and trend reporting |

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate cloud flows with Dataverse |
| **Dataverse capacity** | 5 custom tables for governance data |
| **Microsoft Entra ID P1** | Cross-tenant access policy management |
| **Power BI Pro** *(optional)* | Cross-tenant compliance dashboard |

### Permissions

| Role | Required For |
|------|--------------|
| **Power Platform Admin** | Tenant isolation settings and PPAC API access |
| **Entra Global Admin** | Cross-tenant access policy read/write and MI permission grants |
| **System Administrator** | Dataverse table creation and environment variable configuration |

### Managed Identities

| Identity | Assigned To | Permissions |
|----------|-------------|-------------|
| **MI-CrossTenantReadOnly** | Flows 1, 2, 3, 6 | Policy.Read.All, User.Read.All, CrossTenantInformation.ReadBasic.All, Organization.Read.All, PowerPlatform.Admin.Read.All |
| **MI-CrossTenantReadWrite** | Flows 4, 5 | Policy.ReadWrite.CrossTenantAccess, User.Read.All, CrossTenantInformation.ReadBasic.All, PowerPlatform.Admin.ReadWrite.All |

> **Note:** `Policy.ReadWrite.CrossTenantAccess` requires Entra Global Admin approval. See [Prerequisites](docs/prerequisites.md) for the consent workflow.

## Quick Start

1. Preview Dataverse schema (dry-run): `python scripts/create_ctsg_dataverse_schema.py --tenant-id <tenant-id> --environment-url https://org.crm.dynamics.com --interactive --dry-run`
2. Deploy Dataverse schema: `python scripts/create_ctsg_dataverse_schema.py --tenant-id <tenant-id> --environment-url https://org.crm.dynamics.com --interactive`
3. Create environment variables: `python scripts/create_ctsg_environment_variables.py --tenant-id <tenant-id> --environment-url https://org.crm.dynamics.com --interactive`
4. Create connection references: `python scripts/create_ctsg_connection_references.py --tenant-id <tenant-id> --environment-url https://org.crm.dynamics.com --interactive`
5. Run baseline audit: `.\scripts\governance\Deploy-CrossTenantBaseline.ps1 -DataverseEnvironmentUrl <url>`
6. Populate `fsi_approvedexternaltenant` for all existing cross-tenant relationships
7. Set `fsi_CTSG_IsCrossTenantGovernanceEnabled = "true"`
8. Build flows following [Flow Configuration Guide](docs/flow-configuration.md)

> **Warning:** Complete ALL items in the [Delivery Checklist](DELIVERY-CHECKLIST.md) before setting `fsi_CTSG_IsCrossTenantGovernanceEnabled = "true"`. Activating governance flows without a fully populated approved tenant list may trigger false-positive remediation actions.

> **Adjacent controls to consider alongside this solution:** Tenant Restrictions v2 (TRv2) for outbound authentication-plane enforcement, SharePoint/OneDrive external sharing settings (`Set-SPOTenant -SharingCapability`, `Get-SPOSite -Detailed | Select SharingCapability`), Conditional Access policies for guest sessions, and Copilot Studio managed-environment sharing limits. Cross-tenant governance is necessary but not sufficient on its own — sharing surfaces outside Power Platform require their own governance.

## Documentation

| Document | Purpose |
|----------|---------|
| [Flow Configuration](docs/flow-configuration.md) | Manual build instructions for all 6 flows |
| [Dataverse Schema](docs/dataverse-schema.md) | Table and column specifications |
| [Prerequisites](docs/prerequisites.md) | Managed Identity setup and permissions |
| [Power Apps Configuration](docs/power-apps-configuration.md) | Registry Portal manual build instructions |
| [Power BI Setup](docs/power-bi-setup.md) | Dashboard configuration |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and resolution |
| [Delivery Checklist](DELIVERY-CHECKLIST.md) | Pre-deployment validation items |

## Known Limitations

- **Detection latency**: Tenant isolation and agent share detection runs on daily schedules. Changes between scan windows are not detected until the next scheduled run. Organizations should evaluate whether daily frequency meets their risk tolerance.
- **PPAC API write endpoint availability**: The Power Platform Admin Center API for programmatic tenant isolation allow-list management may not be generally available. If the write endpoint is unavailable, Flow 4 onboarding requires manual PPAC portal steps. See [Delivery Checklist](DELIVERY-CHECKLIST.md) API validation section.
- **Guest detection method limitations**: The 5-value guest detection method (`EXT# Parsing`, `Mail Field`, `CreationType`, `Multi-Method Agreed`, `Unresolved`) relies on user profile attributes that may not be consistently populated across all tenants. The `Unresolved` status indicates cases where no single method produced a definitive result.
- **IAM approval delays**: Dual-approval onboarding (Flow 4) depends on timely approver responses. Approvals that exceed the configured timeout transition to `Expired` status and must be re-initiated.
- **Entra CTA baseline drift**: Weekly CTA audits (Flow 3) compare against a point-in-time baseline. Organizations with frequent CTA policy changes should consider increasing scan frequency.
- **No real-time blocking**: This solution detects and remediates but does not provide real-time blocking of cross-tenant access attempts. Real-time blocking requires controls such as Conditional Access, Tenant Restrictions v2, and workload-specific sharing restrictions configured separately.
- **SharePoint and OneDrive are adjacent surfaces**: Power Platform tenant isolation does not govern standalone SharePoint or OneDrive external sharing. Validate `Set-SPOTenant` tenant settings and `Get-SPOSite -Detailed` site `SharingCapability` separately.
- **Copilot Studio sharing limits are forward-looking**: Managed Environment sharing rules restrict future agent shares; existing agent access should be reviewed and removed through inventory/remediation workflows.

## Version

- **Current:** v1.0.3
- **Framework:** FSI-AgentGov v1.1

## License

MIT License — see [LICENSE](../LICENSE)
