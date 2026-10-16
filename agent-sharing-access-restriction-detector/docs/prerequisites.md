# Prerequisites

> **Solution:** Agent Sharing Access Restriction Detector (ASARD)
> **Version:** v2.0.2

## Required Licenses

| License | Purpose |
|---------|---------|
| Power Automate Premium or appropriate Process licensing | Required for the premium Microsoft Dataverse and HTTP connector usage in these flows; Approvals itself is a standard connector, not the reason for Premium |
| Microsoft 365 E3/E5 (or equivalent) | Teams adaptive card delivery and Entra ID integration |
| Power Platform environment with Dataverse | Storage for compliance records, exception tracking, and approved security group policies |

Confirm the flow owner's or flow-assigned license against the [Power Automate licensing FAQ](https://learn.microsoft.com/en-us/power-platform/admin/power-automate-licensing/faqs). The [Approvals prerequisites](https://learn.microsoft.com/en-us/power-automate/get-started-approvals#prerequisites) explicitly permit standard-connector licenses for approval flows; that does not license ASARD's separate [Dataverse connector](https://learn.microsoft.com/en-us/connectors/commondataserviceforapps/) usage.

## Required Roles

| Role | Purpose |
|------|---------|
| Power Platform Admin (or Entra Global Admin) | Power Platform admin cmdlet access for environment enumeration and Managed Environment sharing-limit configuration |
| Dataverse System Administrator | Creating and managing ASARD Dataverse tables |
| Teams administrator (or delegated permissions) | Posting adaptive card notifications to Teams channels |

## Microsoft Entra Workload Identity

Use managed identity or workload identity federation for production automation where available. Certificate-based service principals are the recommended fallback for unattended administrative workstations. Client secrets are a legacy development-only fallback and should not be used for production deployments.

A Microsoft Entra app registration or managed identity is required for the detection and remediation scripts:

> **Implementation boundary:** Managed identity/federation is the production authentication target, not a claim that every shipped command accepts it. The current scan exposes a legacy development-only client-secret path; the evidence exporter supports device-code authentication and the legacy secret path, and rejects `-CertificateThumbprint`. A production token-acquisition integration requires implementation work; do not pass unsupported identity switches. The June lab also recorded an admin-module authentication failure under PowerShell 7; see [LAB-VALIDATION.md](../LAB-VALIDATION.md#environmental-boundary--add-powerappsaccount-admin-module-with-sp-secret-under-powershell-7).

| Permission | Type | Purpose |
|------------|------|---------|
| Power Platform admin APIs | Application / service principal registration | Enumerate Power Platform environments and Managed Environment sharing settings |
| Dataverse Web API | Application user or managed identity with table privileges | Read and update Copilot Studio `bot` rows (`accesscontrolpolicy`, `authorizedsecuritygroupids`) and ASARD evidence tables |
| Microsoft Graph — `Group.Read.All` or `GroupMember.Read.All` | Application | Resolve security group metadata or memberships when validating approved group policies |
| Microsoft Graph — `User.Read.All` | Application | Resolve individual user sharing principals when workflows include user-level review |

Register the application for the legacy admin module as described in [Power Platform management applications](https://learn.microsoft.com/en-us/power-platform/admin/powershell-create-service-principal), and provision a [Dataverse application user with security roles](https://learn.microsoft.com/en-us/power-platform/admin/manage-application-users) in each target environment. Microsoft Graph permissions do not grant Dataverse table access. The shipped scan compares group IDs with stored policies; live Graph resolution and individual-recipient enumeration are not implemented by that scan.

## Dataverse Tables

The following tables must be created before deploying the flows. Use the schema creation script in this solution's `scripts/` folder (run from the solution root):

```bash
python scripts/create_asard_dataverse_schema.py
```

| Table | Logical Name | Entity Set Name (OData) | Purpose |
|-------|-------------|-------------------------|---------|
| Agent Sharing Compliances | `fsi_agentsharingcompliance` | `fsi_agentsharingcompliances` | Detected sharing policy violations with agent identity, zone, remediation status, and exception fields |
| Approved Security Group Policies | `fsi_approvedsecuritygrouppolicy` | `fsi_approvedsecuritygrouppolicies` | Approved security group whitelist per governance zone |

Key columns on `fsi_agentsharingcompliance`:

- `fsi_agentid`, `fsi_agentname` — Agent identity
- `fsi_environmentid`, `fsi_environmentname` — Environment identity
- `fsi_zone` — Governance zone choice (`100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3); verify the target environment using [Option-Set Integer Verification](option-set-integers.md)
- `fsi_compliancestatus` — Status choice (Compliant=100000000, NonCompliant=100000001, Exception=100000002, Error=100000003)
- `fsi_exceptionexpiresat`, `fsi_exceptionjustification`, `fsi_exceptionapprovedby` — Exception lifecycle fields
- `fsi_remediation*` — Remediation status, approver, timestamp, and notes; these columns do not provide immutable storage by themselves

## Power Automate Connections

| Connection | Purpose |
|------------|---------|
| Microsoft Dataverse | Read/write compliance records and approved security group policies |
| Approvals | Governance-gated remediation approval requests |
| Microsoft Teams | Adaptive card notifications for alerts, approvals, and exception lifecycle |
| HTTP (Premium) | Power Platform admin API calls for Managed Environment settings; adaptive card template loading |

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `api.bap.microsoft.com` | HTTPS 443 | Power Platform admin APIs and Managed Environment sharing-limit configuration |
| `graph.microsoft.com` | HTTPS 443 | Microsoft Graph — security group and user resolution |
| `*.crm.dynamics.com` | HTTPS 443 | Dataverse Web API — Copilot Studio `bots` table and compliance record management |
| Adaptive card template URL | HTTPS 443 | Configurable URL for template hosting (exception review flow) |

## Python Dependencies (Detection and Remediation Scripts)

The supporting scripts in this solution's `scripts/` folder require:

- Python 3.9+
- `msal` — Microsoft Authentication Library for token acquisition
- `requests` — HTTP client for API calls
- `azure-identity` — Azure SDK credential support

Install with:

```bash
pip install -r scripts/requirements.txt
```
