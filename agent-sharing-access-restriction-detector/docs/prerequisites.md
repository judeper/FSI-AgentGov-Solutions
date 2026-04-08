# Prerequisites

> **Solution:** Agent Sharing Access Restriction Detector (ASARD)
> **Version:** v1.0.3

## Required Licenses

| License | Purpose |
|---------|---------|
| Power Automate Premium | Required for approval workflows (Approvals connector) and HTTP connector usage |
| Microsoft 365 E3/E5 (or equivalent) | Teams adaptive card delivery and Entra ID integration |
| Power Platform environment with Dataverse | Storage for compliance records, exception tracking, and approved security group policies |

## Required Roles

| Role | Purpose |
|------|---------|
| Power Platform Admin (or Entra Global Admin) | BAP Admin API access for agent enumeration and sharing remediation |
| Dataverse System Administrator | Creating and managing ASARD Dataverse tables |
| Teams administrator (or delegated permissions) | Posting adaptive card notifications to Teams channels |

## Entra ID App Registration

An Entra ID app registration is required for the detection and remediation scripts:

| Permission | Type | Purpose |
|------------|------|---------|
| BAP Admin API — `Environment.Read.All` | Application | Enumerate Power Platform environments and agents |
| Microsoft Graph — `Group.Read.All` | Application | Resolve security group memberships for zone-based policy evaluation |
| Microsoft Graph — `User.Read.All` | Application | Resolve individual user sharing principals |

## Dataverse Tables

The following tables must be created before deploying the flows. Use the schema creation script in the companion FSI-AgentGov repository:

```bash
python scripts/create_asard_dataverse_schema.py
```

| Table | Logical Name | Purpose |
|-------|-------------|---------|
| Agent Sharing Compliances | `fsi_agentsharingcompliances` | Detected sharing policy violations with agent identity, zone, remediation status, and exception fields |
| Approved Security Group Policies | `fsi_approvedsecuritygrouppolicies` | Approved security group whitelist per governance zone |

Key columns on `fsi_agentsharingcompliances`:

- `fsi_agentid`, `fsi_agentname` — Agent identity
- `fsi_environmentid`, `fsi_environmentname` — Environment identity
- `fsi_zone` — Governance zone classification (1, 2, or 3)
- `fsi_compliancestatus` — Status choice (Compliant=100000000, NonCompliant=100000001, Exception=100000002, Error=100000003)
- `fsi_exceptionexpiresat`, `fsi_exceptionjustification`, `fsi_exceptionapprovedby` — Exception lifecycle fields
- `fsi_remediation*` — Immutable remediation action history

## Power Automate Connections

| Connection | Purpose |
|------------|---------|
| Microsoft Dataverse | Read/write compliance records and approved security group policies |
| Approvals | Governance-gated remediation approval requests |
| Microsoft Teams | Adaptive card notifications for alerts, approvals, and exception lifecycle |
| HTTP (Premium) | BAP Admin API calls for agent sharing remediation; adaptive card template loading |

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `api.bap.microsoft.com` | HTTPS 443 | BAP Admin API — agent enumeration and sharing management |
| `graph.microsoft.com` | HTTPS 443 | Microsoft Graph — security group and user resolution |
| `*.crm.dynamics.com` | HTTPS 443 | Dataverse Web API — compliance record management |
| Adaptive card template URL | HTTPS 443 | Configurable URL for template hosting (exception review flow) |

> **Sovereign clouds:** Override the BAP Admin API endpoint using the `fsi_ASARD_BAPAdminAPIBaseUrl` environment variable. See the [flow configuration guide](flow-configuration.md) for details.

## Python Dependencies (Detection and Remediation Scripts)

The supporting scripts in the companion FSI-AgentGov repository require:

- Python 3.9+
- `msal` — Microsoft Authentication Library for token acquisition
- `requests` — HTTP client for API calls
- `azure-identity` — Azure SDK credential support

Install with:

```bash
pip install msal requests azure-identity
```
