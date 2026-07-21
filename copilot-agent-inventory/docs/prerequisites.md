# Prerequisites - Copilot Agent Inventory

Requirements for deploying the Copilot Agent Inventory (CAI) solution and running
the discovery scanner. This solution targets the **US commercial Microsoft 365 /
Power Platform cloud**.

## Python Requirements

The schema deployment script and the discovery scanner are Python.

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Python | 3.9+ | Schema deployment and discovery scanner runtime |
| msal | 1.30+ | Microsoft Entra ID authentication (token acquisition) |
| requests | 2.32+ | ARG / BAP / Dataverse Web API HTTP client |
| azure-identity | 1.15+ | Managed-identity-first auth (`DefaultAzureCredential` / `ManagedIdentityCredential`) |

Install Python dependencies:

```bash
pip install -r scripts/requirements.txt
```

## Authentication (managed-identity-first)

All CAI scripts acquire tokens in the following priority order. Pick the
strongest method available in your environment; the scanner and the shared
Dataverse client accept a token from any source.

1. **System-assigned managed identity** when running inside an Azure-hosted
   runner or Function (`DefaultAzureCredential` / `ManagedIdentityCredential`).
   Recommended for production.
2. **User-assigned managed identity** for cross-resource scenarios (pass the
   client ID).
3. **Workload identity federation** (GitHub Actions OIDC → Entra app) for CI.
4. **Interactive / device-code** for one-off admin-workstation runs.
5. **Client secret** — dev-only fallback. Store the secret in **Azure Key Vault**
   and read it via the managed identity; never ship a client secret as the
   recommended production path.

## Microsoft Entra ID App Registration (scanner service principal)

A single-tenant app registration backs the discovery scanner's service
principal. Follow least-privilege: the scanner needs read access to enumerate
environments and read `bot` / `botcomponent` records — it does **not** need write
access to target environments.

### Registration Steps

1. Navigate to [Azure Portal](https://portal.azure.com) > **Microsoft Entra ID** >
   **App registrations** > **New registration**.
2. Name: `CAI-CopilotAgentInventory` (or your naming convention).
3. Supported account types: **Single tenant**.
4. For interactive runs, add redirect URI `http://localhost`.
5. Configure a **federated credential** (workload identity) for CI, or a
   certificate; use a client secret only for local development.

### Token Scopes

The scanner requests these resource scopes (all `/.default`, delegated or
application depending on the auth mode):

| Resource | Scope | Purpose |
|----------|-------|---------|
| Power Platform API (`https://api.powerplatform.com`) | `https://api.powerplatform.com/.default` | Layer 1 — ARG `resourcequery` against `PowerPlatformResources` |
| Power Platform Admin / BAP (`https://api.bap.microsoft.com`) | `https://api.bap.microsoft.com/.default` | Environment enumeration |
| Dataverse (per environment) | `https://<org>.crm.dynamics.com/.default` | Layer 2 — read `bot` / `botcomponent`; write the CAI inventory tables in the governance environment |
| Microsoft Graph (`https://graph.microsoft.com`) | `https://graph.microsoft.com/.default` | Layer 4 — Package Management API (`CopilotPackages.Read.All`); owner licensing queries (`User.Read.All`, `Organization.Read.All`, `GroupMember.Read.All`) |

> **Note:** After configuring permissions, a Microsoft Entra admin must grant
> tenant consent.

## Roles and Permissions (least privilege)

### Tenant / Power Platform (environment enumeration)

Environment enumeration is required for Layer 2 and Layer 3 and needs one of:

- Power Platform Admin role, **or**
- Dynamics 365 Service Admin role.

ARM access is also required for the Layer 1 ARG query. These admin roles are
required **only** for the enumeration and ARG steps.

> **Least-privilege note:** granting the scanner System Administrator in every
> environment ("sys-admin-everywhere") is a standing risk and is **not**
> recommended. Scope the scanner's application user to read-only roles on `bot` /
> `botcomponent` in target environments, and reserve write access to the
> governance environment that hosts the CAI tables.

### Dataverse (per environment)

| Role | Environment | Purpose |
|------|-------------|---------|
| Read-only role covering `bot`, `botcomponent` | Target environments | Layer 2 feature enumeration |
| Dataverse User with Create/Write on CAI tables | Governance environment | Write the inventory system-of-record |

Register the scanner app as an **application user** in each environment it reads,
and grant the minimum role that allows the reads above.

## Azure Key Vault (secret storage for dev fallback)

When a client secret is used (development only), store it in Azure Key Vault and
grant the managed identity `get` on secrets. The scanner reads the secret at
runtime via the managed identity rather than from an environment variable or a
file. This is required to keep secrets out of source control and CI logs.

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `login.microsoftonline.com` | HTTPS | OAuth token acquisition |
| `api.powerplatform.com` | HTTPS | Layer 1 — ARG `resourcequery` |
| `api.bap.microsoft.com` | HTTPS | Environment enumeration |
| `*.crm.dynamics.com` | HTTPS | Layer 2 — `bot` / `botcomponent` reads; CAI table writes |
| `graph.microsoft.com` | HTTPS | Layer 4 — Package Management API; owner licensing queries |
| `*.vault.azure.net` | HTTPS | Key Vault secret retrieval (dev fallback) |

> **Live-confirm (🔎):** `microsoft.copilotstudio/agents` is absent from the
> standard ARG supported-types reference. Before the first production run,
> confirm the type resolves with
> `az graph query -q "PowerPlatformResources | where type == 'microsoft.copilotstudio/agents'"`.
> If conditional access enforces ARM MFA, allow the PPAC client ID
> `00b46ad5-e4ae-43ac-a878-281fc03d0839` and "Microsoft Azure Management".

## Dataverse Schema Deployment

Deploy the canonical 8-table schema with the Python schema script. The script is
idempotent (it checks for existing tables, columns, and option sets) and supports
a dry run.

```bash
# Install Python dependencies
pip install -r scripts/requirements.txt

# Preview the schema deployment (reads hit the live tenant; no writes)
python scripts/create_cai_dataverse_schema.py \
    --environment-url https://governance.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive \
    --dry-run

# Deploy for real
python scripts/create_cai_dataverse_schema.py \
    --environment-url https://governance.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive

# Regenerate the schema documentation after any schema change
python scripts/create_cai_dataverse_schema.py --output-docs
```

The deployed schema is 8 tables, 11 solution-specific option sets, and 1 shared
option set. See [dataverse-schema.md](dataverse-schema.md) for the full reference.

## Package Management API — Layer 4 Prerequisites

The Package Management API layer (`--enable-package-api`) is **additive and
off by default**. It discovers `Microsoft 365 Copilot Agent Builder` packages
only; Copilot Studio agents are intentionally excluded because existing layers
(ARG, per-environment Dataverse, and PPAC) already cover Copilot Studio agents,
and package-to-bot joins are not strong enough to prevent duplicates. The layer
requires three separate gates — each must be satisfied independently, at
different administrative levels. Activate this layer only in the **US commercial
Microsoft 365 cloud** (see cloud scope note below).

> **Reference:** [List packages — Microsoft Learn](https://learn.microsoft.com/microsoft-365/copilot/extensibility/api/admin-settings/package/copilotpackages-list)
> · [copilotPackage resource type](https://learn.microsoft.com/microsoft-365/copilot/extensibility/api/admin-settings/package/resources/copilotpackage)

---

### Gate 1 — Microsoft Agent 365 License (tenant product gate)

The Package Management API is surfaced only when the tenant holds a
**Microsoft Agent 365** license. This is a tenant-level product gate; the API
endpoint returns `404` or an empty catalog for tenants without this license.

- **Who sets this up:** Microsoft licensing or enterprise agreement — not an
  admin configuration step.
- **How to verify:** Confirm the tenant has a Microsoft Agent 365 license
  assignment before enabling Layer 4.

---

### Gate 2 — `CopilotPackages.Read.All` Application Permission (API gate)

The scanner uses **application** (app-only) permission to read the package
catalog, which allows unattended automation without a signed-in user.

| Permission | Type | Purpose |
|-----------|------|---------|
| `CopilotPackages.Read.All` | Application | Read all Agent Builder packages from the catalog |

**Who grants this:** A Microsoft Entra **Global Admin** or **Privileged Role
Administrator** must grant tenant-wide admin consent.

**How to add the permission:**

1. In [Azure Portal](https://portal.azure.com) > **Microsoft Entra ID** >
   **App registrations**, open the CAI scanner app registration.
2. Navigate to **API permissions** > **Add a permission** >
   **Microsoft Graph** > **Application permissions**.
3. Search for and add `CopilotPackages.Read.All`.
4. Click **Grant admin consent for \<tenant\>** (requires Global Admin or
   Privileged Role Administrator).

**Additional Graph permissions for owner licensing queries** (required by
`resolve_owner_entitlement.py`):

| Permission | Type | Purpose |
|-----------|------|---------|
| `User.Read.All` | Application | Read owner profile and license assignments |
| `Organization.Read.All` | Application | Read tenant SKU information for entitlement classification |
| `GroupMember.Read.All` | Application | Resolve security-group memberships for sharing audience expansion |

Grant admin consent for these at the same time as `CopilotPackages.Read.All`.

---

### Gate 3 — AI Administrator Entra Role (portal / delegated gate)

The **AI Administrator** role in Microsoft Entra ID grants access to the
Copilot admin portal and is required for interactive/delegated workflows and
for granting consent to Copilot-scoped permissions in the portal. For the
**app-only scanner** running under a managed identity or service principal,
this role is **not required per-run** — Gate 2 (admin-consented application
permission) is sufficient for unattended automation.

- **When this role is needed:** Interactive portal workflows; granting
  Copilot-scoped admin consent via the M365 admin center; reviewing or
  managing the package catalog in the portal UI.
- **Who holds this role:** Typically the Copilot governance admin, not the
  scanner service principal.

---

### PowerShell Core (`pwsh`) Requirement

`resolve_owner_entitlement.py` invokes
`copilot-billing-governance/scripts/Get-CopilotEntitlement.ps1` as a
subprocess. **PowerShell Core (`pwsh`) must be installed** in the execution
environment (Azure Automation, GitHub Actions runner, or admin workstation).

Verify availability:

```bash
pwsh --version
```

Install from [aka.ms/install-powershell](https://aka.ms/install-powershell) if
not present.

---

```bash
# Dry run (no Dataverse writes; logs the calls that would be made)
python scripts/discover_agents.py \
    --tenant-id <your-tenant-id> \
    --dry-run \
    --output scan.json

# Production run (managed identity preferred)
python scripts/discover_agents.py \
    --tenant-id <your-tenant-id> \
    --auth-mode managed-identity

# Full integrated scan — Package API + registry correlation + entitlement
# (Global commercial cloud only; requires pwsh for entitlement resolution)
python scripts/discover_agents.py \
    --auth-mode managed-identity \
    --tenant-id <your-tenant-id> \
    --enable-package-api \
    --registry-export registry-export.xlsx \
    --columnmap templates/registry-columnmap.sample.json \
    --as-of 2026-07-20T18:00:00Z \
    --resolve-entitlement \
    --output scan.json
```

**Python Requirements:** Python 3.9+, packages listed in `scripts/requirements.txt`.
