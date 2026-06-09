# Work IQ Usage Detection — Prerequisites

> **Status:** 0.1.0-preview. Verify each item against your tenant before
> deployment. This solution helps support per-zone Work IQ feature-enablement
> governance and usage reporting; it does not by itself satisfy any regulation.

## Solution dependency

This solution depends on **[`copilot-agent-inventory`](../../copilot-agent-inventory/README.md)**,
the tier-1 system-of-record that owns the agent master `fsi_copilotagent`.
Deploy and populate `copilot-agent-inventory` first. Work IQ Usage Detection
reads `fsi_copilotagent` (including the Azure Resource Graph `createdIn` value
used to key the native-MCP pathway) and **does not** create or duplicate it.

The agent master carries `fsi_environmentid` (the source-environment GUID) but
not that environment's Dataverse URL. `Get-WorkIqConfigState.ps1` resolves the
per-environment URL from the sibling **`fsi_caienvironment`** table (entity set
`fsi_caienvironments`) by reading **`fsi_caienvironment.fsi_environmenturl`** for
the matching `fsi_environmentid`, then scopes the per-agent `botcomponent` sample
to that source environment. Work IQ Usage Detection therefore depends on
`copilot-agent-inventory` publishing `fsi_caienvironment.fsi_environmenturl`
(being added to the inventory schema in parallel). When that URL is absent for an
environment, the scanner skips that environment's component scan and marks the
affected agents `Exception-unknown` rather than scanning the governance
environment by mistake.

> ASSUMPTION: the exact column logical names on `fsi_copilotagent` and
> `fsi_caienvironment` resolve from the `copilot-agent-inventory` published
> schema. The `fsi_caienvironment.fsi_environmenturl` column is being added to
> the inventory in parallel; confirm it is published before relying on Tier-A
> environment scoping.

## Roles

Use canonical role names. Least privilege is recommended; the scanner identity
should hold only the roles required for the tier it runs.

| Role | Required for |
|------|--------------|
| **Power Platform Admin** | Tenant-wide environment enumeration and Dataverse `botcomponent` / `aipluginoperation` reads (Tier-A), plus writing `fsi_wiqstate` / `fsi_wiqkpi`. |
| **Security Admin** | Provisioning the least-privilege scanner identity and access to Microsoft Defender XDR Advanced Hunting (`CloudAppEvents`, `AgentsInfo`, `AgentToolsDetails`) and Purview Audit (`CopilotInteraction`, `AIPluginOperation`). |
| **Log Analytics Reader** | Reading the Copilot Studio Application Insights resource for the Tier-B `customEvents` query. |
| **Purview Compliance Admin** | Required for the Purview audit collection used as a Tier-B companion source (if enabled). |

## Licensing and platform

- A Dataverse environment with the **`fsi` publisher prefix** for the solution
  tables and option sets.
- **Microsoft Defender for Cloud Apps** connected to **Microsoft Defender XDR**
  for `CloudAppEvents` Advanced Hunting. This connector is in preview for some
  tenants at scaffold time — confirm availability before relying on it.
- **Application Insights** configured as the Copilot Studio agents' telemetry
  destination (see `agent-observability-foundation` for the foundation setup).
- **Microsoft Purview Audit** (Standard or Premium) for `CopilotInteraction` /
  `AIPluginOperation` records, if the Purview companion source is enabled.
- **Microsoft 365 Work IQ**, GA **2026-06-16**. The `use-work-iq` capability is
  still preview at scaffold time; the `WorkIqGa20260616` feature flag gates the
  short-lived preview-to-GA behaviour.

## Tooling

- **PowerShell 7.4+** for `Get-WorkIqConfigState.ps1`.
- **Az.Accounts** (managed-identity-first token acquisition) for the Dataverse
  Web API calls in the Tier-A detector.
- **Python 3.10+** with the repository's shared `scripts/shared/dataverse_client.py`
  (`msal`, `requests`) for `create_wiq_dataverse_schema.py`. `--output-docs`
  runs with the standard library only.

## Authentication

Managed-identity-first, per the repository standard:

1. System-assigned managed identity (Azure-hosted runner / Function).
2. User-assigned managed identity (pass the client ID).
3. Workload identity federation (GitHub Actions OIDC → Entra app) for CI.
4. Interactive / device-code for one-off admin-workstation runs.
5. Client secret **only** as a development fallback.

## Cloud scope

This content targets **US commercial-cloud Microsoft 365**. See the repository
[SCOPE.md](../../SCOPE.md) for the full cloud-scope statement.
