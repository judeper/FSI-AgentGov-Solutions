---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P2, P4]
applicable_drivers:
  - ai_governance
  - ai_strategy
  - technology_data
coe_function: enable
---
# Agent Registry Automation

> **Version:** v2.1.1
> **Status:** Live
> **Validated against framework version:** v1.6.0

Automated discovery, registration, approval, and lifecycle governance of AI agents across Power Platform environments, supporting FSI agent inventory and record-keeping requirements.

## Overview

Many organizations deploy AI agents across multiple Power Platform environments without a centralized registry. This creates governance blind spots — agents may operate without documented ownership, risk classification, or regulatory approval. The Agent Registry Automation solution addresses this gap by continuously scanning environments for unregistered agents, applying zone-based registration and approval workflows, and maintaining an immutable compliance event log for examiner reporting.

## Features

| Feature | Description |
|---------|-------------|
| **Daily Discovery** | Scans all Power Platform environments and reads each environment's Dataverse `bot` table for unregistered agents |
| **Auto-Quarantine** | Zone 3 agents without committee approval are automatically quarantined |
| **Registration Workflow** | Teams-based approval with configurable SLA tracking and escalation |
| **Agent ID Sync** | Syncs registered agents to Microsoft Entra Agent ID when the preview API is enabled (feature-flagged) |
| **Orphan Detection** | Weekly check for agents whose owners have departed or become inactive |
| **Examiner Dashboard** | Compliance reporting with zone-filtered inventory and audit trail |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Agent Registry Automation                         │
├─────────────────┬─────────────────┬──────────────┬──────────────────┤
│  Flow 1:        │  Flow 2:        │  Flow 3:     │  Flow 4:         │
│  Daily          │  Registration   │  Entra       │  Orphan          │
│  Discovery      │  Approval Gate  │  Sync        │  Detection       │
└────────┬────────┴────────┬────────┴──────┬───────┴────────┬─────────┘
         │                 │               │                │
         ▼                 ▼               ▼                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Dataverse (Agent Registry)                        │
├─────────────────┬─────────────────┬──────────────┬──────────────────┤
│ Agent           │ Registration    │ Compliance   │ Ownership        │
│ Inventory       │ Request         │ Event        │ Audit            │
└────────┬────────┴────────┬────────┴──────────────┴──────────────────┘
         │                 │
         ▼                 ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  BAP admin API + │  │  Microsoft       │  │  Entra Agent ID  │
│  Dataverse `bot` │  │  Graph API       │  │  (feature-       │
│  table per env   │  │                  │  │   flagged)       │
└──────────────────┘  └──────────────────┘  └──────────────────┘
         │                 │
         ▼                 ▼
┌─────────────────────────────────────────┐
│  Microsoft Teams (Notifications)        │
│  Adaptive Cards + Approval Requests     │
└─────────────────────────────────────────┘
```

## Control Mapping

| Control | Description | Coverage |
|---------|-------------|----------|
| **1.2** | Agent Registry and Integrated Apps Management | Primary |
| **1.7** | Comprehensive Audit Logging | Secondary |
| **2.1** | Managed Environments | Secondary |
| **2.13** | Documentation and Record Keeping | Secondary |

## Zone Applicability

| Zone | Enforcement Level |
|------|-------------------|
| Zone 1 (Personal) | Inventory only — no approval gate |
| Zone 2 (Team/Departmental) | Registration required before sharing |
| Zone 3 (Enterprise/Customer-Facing) | Registration + committee approval required; auto-quarantine on violation |

## Regulatory Alignment

| Regulation | How This Solution Helps |
|------------|------------------------|
| FINRA Rule 4511 | Supports books and records requirements for AI agent systems — agent metadata is captured and retained |
| SEC Rule 17a-3/4 | Supports 7-year immutable retention of agent lifecycle events via Dataverse Long-Term Retention (LTR) |
| OCC Bulletin 2011-12 | Aids in model inventory management with documented ownership and risk classification |
| Fed SR 11-7 | Supports comprehensive inventory with zone-based risk classification and periodic owner validation |
| GLBA 501(b) | Helps meet safeguards requirements — ongoing owner validation and orphan detection reduce unauthorized access risk |

> **Note:** No single control or solution satisfies a regulation in isolation. Organizations should verify that their overall control environment meets specific regulatory obligations.

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows with Dataverse and HTTP connectors |
| **Dataverse capacity** | Agent inventory and compliance event storage |
| **Managed Environment** | Required for Dataverse Long-Term Retention (LTR) |
| **Microsoft 365 E3+** | Microsoft Teams notifications and Graph API access |

### Roles

| Role | Required For |
|------|--------------|
| **Power Platform Admin** | Environment enumeration (BAP admin API) and `bot`-table read access |
| **System Administrator** | Dataverse table creation and solution import |
| **Entra Global Admin** or **Application Administrator** | Service principal registration and API permission grants |

### Environment

- Target environment must be a **Managed Environment** (required for Dataverse Long-Term Retention)
- Identity must have Power Platform Admin (for BAP environment enumeration), Dataverse `bot`-table read in each scanned environment, and Microsoft Graph permissions (see [Prerequisites](docs/prerequisites.md))

## Solution Components

| Component | File | Type |
|-----------|------|------|
| Dataverse schema deployment | `scripts/create_dataverse_schema.py` | Python |
| Environment variable deployment | `scripts/create_environment_variables.py` | Python |
| Connection reference deployment | `scripts/create_connection_references.py` | Python |
| Deployment orchestrator | `scripts/deploy.py` | Python |
| Baseline inventory export | `scripts/Deploy-AgentRegistry-Baseline.ps1` | PowerShell |
| Compliance validation | `scripts/Test-AgentRegistryCompliance.ps1` | PowerShell |
| Flow build instructions | `docs/flow-configuration.md` | Documentation |
| Dataverse schema reference | `docs/dataverse-schema.md` | Documentation |

## Quick Start

### 1. Deploy Dataverse Schema

```powershell
# Deploy tables, option sets, and alternate keys with managed identity or workload identity federation
python scripts/create_dataverse_schema.py `
    --environment-url "https://your-org.crm.dynamics.com" `
    --tenant-id "your-tenant-id"

# Certificate auth fallback for admin workstations
python scripts/create_dataverse_schema.py `
    --environment-url "https://your-org.crm.dynamics.com" `
    --tenant-id "your-tenant-id" `
    --client-id "your-client-id" `
    --client-certificate-path ".\certs\ara-app.pem" `
    --client-certificate-thumbprint "your-cert-thumbprint"
```

### 2. Deploy Environment Variables

```powershell
# Create environment variables in the target environment
python scripts/create_environment_variables.py `
    --environment-url "https://your-org.crm.dynamics.com" `
    --tenant-id "your-tenant-id"
```

### 3. Deploy Connection References

```powershell
# Create connection references for the 4 flows
python scripts/create_connection_references.py `
    --environment-url "https://your-org.crm.dynamics.com" `
    --tenant-id "your-tenant-id"
```

### 4. Build Power Automate Flows

Follow the step-by-step instructions in [Flow Configuration](docs/flow-configuration.md) to manually build the 4 flows in Power Automate designer.

### 5. Run Baseline Export

```powershell
# Export existing agents to seed the inventory
.\scripts\Deploy-AgentRegistry-Baseline.ps1 `
    -DataverseUrl "https://your-org.crm.dynamics.com"
```

### 6. Validate Deployment

```powershell
# Verify schema, variables, connections, and flow status
.\scripts\Test-AgentRegistryCompliance.ps1 `
    -DataverseUrl "https://your-org.crm.dynamics.com"
```

## Key Configuration Notes

- **Microsoft Entra Agent ID (Flow 3):** Disabled by default via the `fsi_ARA_IsEntraRegistrySyncEnabled` environment variable. Enable only after confirming the current Microsoft Graph beta endpoint, Agent ID permissions, and Microsoft Agent 365 or Microsoft 365 E7 licensing in your tenant.
- **Agent endpoint URL:** The Dataverse `bot` table does not expose a Bot Framework endpoint column, so `fsi_agentendpointurl` is not populated during discovery. Populate it from channel configuration post-discovery if your governance process requires it.
- **Office 365 connector for SLA:** The SLA calculation in Flow 2 uses the Office 365 Users connector to determine the approver's time zone for business-day calculations. If DLP policies block this connector, configure a fallback time zone in the `fsi_ARA_DefaultTimeZone` environment variable.
- **7-year retention (LTR):** The `fsi_agentcomplianceevent` table is designed for Dataverse Long-Term Retention. Enable LTR policies after deployment to support SEC 17a-3/4 retention requirements.

## Documentation

| Document | Description |
|----------|-------------|
| [Dataverse Schema](docs/dataverse-schema.md) | Table definitions, option sets, and alternate keys |
| [Flow Configuration](docs/flow-configuration.md) | Step-by-step build instructions for all 4 flows |
| [Prerequisites](docs/prerequisites.md) | Licensing, roles, API permissions, and environment setup |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and resolutions |

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.2 — Agent Registry and Integrated Apps Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.2-agent-registry-and-integrated-apps-management.md) | Primary — centralized agent inventory |
| [1.7 — Comprehensive Audit Logging and Compliance](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) | Secondary — immutable compliance event log |
| [2.1 — Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.1-managed-environments.md) | Secondary — environment governance |
| [2.13 — Documentation and Record Keeping](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.13-documentation-and-record-keeping.md) | Secondary — ownership and lifecycle records |

## Platform Update Notes

### Microsoft 365 Copilot Agent Store (April 2026)

Microsoft has introduced the [Microsoft 365 Copilot Agent Store](https://learn.microsoft.com/en-us/microsoft-365/copilot/copilot-agent-store), a centralized marketplace for discovering, deploying, and managing agents within Microsoft 365 Copilot. The Agent Store supports three deployment paths:

| Path | Source | Governance Implication |
|------|--------|----------------------|
| **Prebuilt** | Microsoft-provided agents | Require admin-level deployment approval; should be inventoried alongside custom agents |
| **Copilot Studio** | Organization-built agents via Copilot Studio | Already covered by this solution's Dataverse `bot`-table discovery |
| **External Platforms** | Third-party agents via Teams Bot or custom integrations | May not appear in the Dataverse `bot` table; require alternative inventory mechanisms |

**Impact on this solution:** The current discovery mechanism enumerates environments via the BAP admin API and reads each environment's Dataverse `bot` table to find agents. This does not cover:

- **Prebuilt agents** deployed from the Agent Store, which may not appear as rows in the Dataverse `bot` table
- **External platform agents** registered through Teams Bot manifests or custom engine agents
- **Agent Store admin controls** for blocking or allowing agent deployment at the tenant level

Future enhancements should consider:

- Adding Graph API queries for the [Microsoft 365 Agents admin guide](https://learn.microsoft.com/en-us/microsoft-365/copilot/agent-essentials/m365-agents-admin-guide) endpoints to discover Agent Store deployments
- Adding an `fsi_agentsource` choice column to distinguish Copilot Studio, Agent Store (Prebuilt), and External Platform categories
- Monitoring the Agent Store admin center for new agent deployments as a supplementary discovery channel

> **Note:** Agent Store discovery integration is not yet implemented. Organizations should manually inventory prebuilt and external agents until automated discovery support is added.

## Known Limitations

- **Environment enumeration (BAP admin API):** Discovery lists environments via the Business Application Platform admin API (`api-version=2020-10-01`). Monitor the [Power Platform REST API documentation](https://learn.microsoft.com/rest/api/power-platform/) for version changes.
- **Microsoft Entra Agent ID:** Flow 3 (Entra Sync) requires Microsoft Agent 365 or Microsoft 365 E7 licensing and is feature-flagged off by default. Confirm the current preview endpoint and permission names before enabling.
- **Agent discovery (Dataverse `bot` table):** Discovery reads each environment's `bot` table, which requires `bot`-table read access in every scanned environment. The owner-expand path (`owninguser.domainname`) and `statecode` semantics should be confirmed against the live table in your tenant. The `bot` table has no Bot Framework endpoint column.
- **Sandbox environments:** By default, sandbox environments are excluded from discovery scans. Set `fsi_ARA_IncludeSandboxEnvironments` to `true` to include them.

## Version History

See [CHANGELOG](./CHANGELOG.md) for version history.

| Version | Date | Changes |
|---------|------|---------|
| 2.1.0 | 2026-Q2 | Microsoft Learn refresh for authentication, paging, and Agent ID preview guidance |
| 2.0.0 | 2026-04-30 | Schema-generated docs and flow alignment fixes |
| 1.0.2 | 2026-04-16 | Data integrity fixes, parameter corrections |
| 1.0.1 | 2026-04-15 | Schema alignment fixes, verb corrections |
| 1.0.0 | 2026-03-15 | Initial release |

## Support

For issues and feature requests, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*This solution is provided as a reference implementation. Organizations should validate all configurations against their specific regulatory obligations and environment requirements. This solution does not constitute legal or compliance advice.*

---

*FSI Agent Governance Framework — Agent Registry Automation v2.1.1*
