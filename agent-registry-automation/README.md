# Agent Registry Automation

> **Status:** Production Ready (v1.0.0)

Automated discovery, registration, approval, and lifecycle governance of AI agents across Power Platform environments, supporting FSI agent inventory and record-keeping requirements.

## Overview

Many organizations deploy AI agents across multiple Power Platform environments without a centralized registry. This creates governance blind spots — agents may operate without documented ownership, risk classification, or regulatory approval. The Agent Registry Automation solution addresses this gap by continuously scanning environments for unregistered agents, enforcing zone-based registration and approval workflows, and maintaining an immutable compliance event log for examiner reporting.

## Features

| Feature | Description |
|---------|-------------|
| **Daily Discovery** | Scans all Power Platform environments via Bots API for unregistered agents |
| **Auto-Quarantine** | Zone 3 agents without committee approval are automatically quarantined |
| **Registration Workflow** | Teams-based approval with configurable SLA tracking and escalation |
| **Entra Sync** | Syncs registered agents to Entra Agent Registry (feature-flagged) |
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
│  Bots API        │  │  Microsoft       │  │  Entra Agent     │
│  (2022-03-01-    │  │  Graph API       │  │  Registry        │
│   preview)       │  │                  │  │  (feature-flagged)│
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
| **Power Platform Admin** | Environment enumeration and Bots API access |
| **System Administrator** | Dataverse table creation and solution import |
| **Entra Global Admin** or **Application Administrator** | Service principal registration and API permission grants |

### Environment

- Target environment must be a **Managed Environment** (required for Dataverse Long-Term Retention)
- Service principal must have Bots API and Graph API permissions (see [Prerequisites](docs/prerequisites.md))

## Solution Components

| Component | File | Type |
|-----------|------|------|
| Dataverse schema deployment | `scripts/create_dataverse_schema.py` | Python |
| Environment variable deployment | `scripts/create_environment_variables.py` | Python |
| Connection reference deployment | `scripts/create_connection_references.py` | Python |
| Deployment orchestrator | `scripts/deploy.py` | Python |
| Baseline inventory export | `scripts/Deploy-AgentRegistry-Baseline.ps1` | PowerShell |
| Compliance validation | `scripts/Validate-AgentRegistry-Compliance.ps1` | PowerShell |
| Flow build instructions | `docs/flow-configuration.md` | Documentation |
| Dataverse schema reference | `docs/dataverse-schema.md` | Documentation |

## Quick Start

### 1. Deploy Dataverse Schema

```powershell
# Deploy tables, option sets, and alternate keys
python scripts/create_dataverse_schema.py `
    --environment "https://your-org.crm.dynamics.com" `
    --tenant-id "your-tenant-id" `
    --client-id "your-client-id" `
    --client-secret "your-client-secret"
```

### 2. Deploy Environment Variables

```powershell
# Create environment variables in the target environment
python scripts/create_environment_variables.py `
    --environment "https://your-org.crm.dynamics.com" `
    --tenant-id "your-tenant-id"
```

### 3. Deploy Connection References

```powershell
# Create connection references for the 4 flows
python scripts/create_connection_references.py `
    --environment "https://your-org.crm.dynamics.com" `
    --tenant-id "your-tenant-id"
```

### 4. Build Power Automate Flows

Follow the step-by-step instructions in [Flow Configuration](docs/flow-configuration.md) to manually build the 4 flows in Power Automate designer.

### 5. Run Baseline Export

```powershell
# Export existing agents to seed the inventory
.\scripts\Deploy-AgentRegistry-Baseline.ps1 `
    -TenantId "your-tenant-id" `
    -EnvironmentUrl "https://your-org.crm.dynamics.com"
```

### 6. Validate Deployment

```powershell
# Verify schema, variables, connections, and flow status
.\scripts\Validate-AgentRegistry-Compliance.ps1 `
    -EnvironmentUrl "https://your-org.crm.dynamics.com" `
    -TenantId "your-tenant-id"
```

## Key Configuration Notes

- **Entra Agent Registry (Flow 3):** Disabled by default via the `fsi_ARA_EntraRegistrySyncEnabled` environment variable. Enable only after confirming Entra Agent Registry API availability (requires Agent 365 / Frontier licensing).
- **BotFrameworkEndpoint field name:** The `properties.botFrameworkEndpoint` field from the Bots API response needs live API confirmation. Verify the exact field path in your environment before enabling Flow 1.
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
| [1.7 — Comprehensive Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-monitoring.md) | Secondary — immutable compliance event log |
| [2.1 — Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-governance/2.1-managed-environments-for-power-platform.md) | Secondary — environment governance |
| [2.13 — Documentation and Record Keeping](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-governance/2.13-documentation-and-record-keeping.md) | Secondary — ownership and lifecycle records |

## Platform Update Notes

### M365 Copilot Agent Store (April 2026)

Microsoft has introduced the [M365 Copilot Agent Store](https://learn.microsoft.com/en-us/microsoft-365/copilot/copilot-agent-store), a centralized marketplace for discovering, deploying, and managing agents within Microsoft 365 Copilot. The Agent Store supports three deployment paths:

| Path | Source | Governance Implication |
|------|--------|----------------------|
| **Prebuilt** | Microsoft-provided agents | Require admin-level deployment approval; should be inventoried alongside custom agents |
| **Copilot Studio** | Organization-built agents via Copilot Studio | Already covered by this solution's Bots API discovery |
| **External Platforms** | Third-party agents via Teams Bot or custom integrations | May not be discoverable via the Bots API; require alternative inventory mechanisms |

**Impact on this solution:** The current discovery mechanism uses the Power Platform Bots API (`2022-03-01-preview`) to scan for agents within Power Platform environments. This does not cover:

- **Prebuilt agents** deployed from the Agent Store, which may not appear in the Bots API response
- **External platform agents** registered through Teams Bot manifests or custom engine agents
- **Agent Store admin controls** for blocking or allowing agent deployment at the tenant level

Future enhancements should consider:

- Adding Graph API queries for the [M365 Agents admin guide](https://learn.microsoft.com/en-us/microsoft-365/copilot/agent-essentials/m365-agents-admin-guide) endpoints to discover Agent Store deployments
- Extending the `fsi_agentsource` choice set to include Agent Store (Prebuilt) and External Platform categories
- Monitoring the Agent Store admin center for new agent deployments as a supplementary discovery channel

> **Note:** Agent Store discovery integration is not yet implemented. Organizations should manually inventory prebuilt and external agents until automated discovery support is added.

## Known Limitations

- **Bots API preview:** The Power Platform Bots API (`2022-03-01-preview`) may change at GA. Monitor Microsoft documentation for breaking changes to the endpoint schema.
- **Entra Agent Registry:** Flow 3 (Entra Sync) requires Agent 365 / Frontier licensing and is feature-flagged off by default. API availability should be confirmed before enabling.
- **BotFrameworkEndpoint field:** The exact field path (`properties.botFrameworkEndpoint`) in the Bots API response needs live API confirmation. The flow includes error handling for missing fields.
- **Sandbox environments:** By default, sandbox environments are excluded from discovery scans. Set `fsi_ARA_IncludeSandboxEnvironments` to `true` to include them.

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | March 2026 | Initial release |

## Support

For issues and feature requests, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*This solution is provided as a reference implementation. Organizations should validate all configurations against their specific regulatory obligations and environment requirements. This solution does not constitute legal or compliance advice.*

---

*FSI Agent Governance Framework — Agent Registry Automation v1.0.0*
