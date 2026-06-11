# Prerequisites

Requirements for deploying Copilot Billing Governance (CBG).

---

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Microsoft 365 Copilot** | Licensed users are an input to the entitlement decision |
| **Copilot consumption billing** (PAYG and/or prepaid credits) | The policy objects this solution governs |
| **Azure subscription** | Backs the pay-as-you-go (PAYG) billing policy |
| **Power Platform Premium** | Power Automate sync and coverage-gap flows |
| **Dataverse capacity** | Policy, entitlement, cache, and coverage-gap storage |

> **Upstream dependency:** Copilot Credits consumption billing applies from **June 16
> 2026**, and credit policies are **Chat-only today** (SharePoint grounding stays
> PAYG). Verify current availability with Microsoft before relying on credit-policy
> enforcement.

---

## Permissions

### Microsoft Entra ID roles

| Role | Required for |
|------|--------------|
| **Microsoft 365 Admin** | Read and configure Copilot billing and credit policies in the Microsoft 365 admin center |
| **Entra Global Admin** *(or delegated group admin)* | Register maker / audience / billing security groups in the admission-gated registry |

### Azure roles

| Role | Required for |
|------|--------------|
| **Subscription Owner or Contributor** | The Azure subscription backing the PAYG billing policy and its budget alerts |

### Power Platform roles

| Role | Required for |
|------|--------------|
| **Power Platform Admin** | Environment configuration and solution import |
| **System Administrator** | Dataverse table creation and application-user role assignment |

### Microsoft Graph permissions

| Permission | Type | Purpose |
|------------|------|---------|
| `User.Read.All` | Application | Read user Copilot license assignment via `licenseDetails`, including transitive group-based licenses (entitlement input) |
| `Group.Read.All` | Application | Read Entra group `securityEnabled` / `mailEnabled` / `groupTypes` at admission time, and group **transitive members** for PAYG group-scope and cohort resolution |
| `Organization.Read.All` | Application | Read `subscribedSkus` to build the tenant SKU dictionary (resolves undocumented Copilot-bearing SKUs — e.g. "E7", "Copilot Premium" — by construction) |

> Grant admin consent to the managed identity or app registration used by the
> scripts. Request the least privilege your environment allows.

### Power Platform billing-policy REST (PAYG / credit coverage)

The per-user resolver ([`Get-CopilotEntitlement.ps1`](../scripts/Get-CopilotEntitlement.ps1))
maps **PAYG / credit coverage** to the engine's `inCreditScopeGroup` input. There is **no
Microsoft Graph endpoint** for billing-policy membership, so coverage is read from the
Power Platform billing-policy admin REST
(`https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/billingPolicies`)
using a token for the `https://api.bap.microsoft.com/` audience, acquired via the same
managed-identity-first model. The calling principal needs **Power Platform Admin** (or an
equivalent billing-policy reader) rights.

> **Unproven schema.** This REST shape is not yet proven. Prefer supplying the resolver an
> explicit `-BillingPolicyInputPath` / `-BillingPolicy` — for example the normalized output
> of [`Get-BillingPolicyInventory.ps1`](../scripts/Get-BillingPolicyInventory.ps1) — and
> treat the live read as best-effort.

---

## Authentication model (managed-identity-first)

Use a managed identity for Azure-hosted automation:

1. Enable a **system-assigned managed identity** on the Azure Automation account,
   Function, VM, or container host running the scripts.
2. For shared automation, configure a **user-assigned managed identity** and pass its
   client ID.
3. For CI, use **workload identity federation** (GitHub Actions OIDC → Entra app).
4. Use **interactive / device-code** for one-off admin-workstation runs.
5. Use a **client secret only as a legacy development fallback**; rotate and remove it
   before production. Do not prescribe client secrets as the recommended path.

The shared `DataverseClient` (`../scripts/shared/dataverse_client.py`) accepts a token
from any of the above, so the strongest available method can be selected without
changing the scripts. The PowerShell scripts request a managed-identity token first
and fall back only when one is not available.

---

## Identity setup

1. Configure a managed identity for production script hosts, or register an
   application for local development fallback.
2. Grant the Graph permissions above and admin consent.
3. Create a Dataverse application user for the identity and assign the least-privilege
   role needed to read agents and write the CBG tables.
4. If a client secret is used for development, store it in Azure Key Vault, restrict
   access, and remove it before production.

> **Security note:** secret environment-variable values without Key Vault backing are
> accessible to Dataverse System Administrators. Prefer managed identity for any
> non-development run.

---

## Validation checklist

- [ ] Microsoft 365 Copilot licensing available for evaluated users
- [ ] PAYG billing policy connected (two-step add → connect) **and/or** prepaid credit
      policy configured
- [ ] Azure subscription budget alert configured for PAYG spend
- [ ] Power Platform Premium for the flow author
- [ ] Dataverse environment ready; CBG schema deployed
      (`python scripts/create_cbg_dataverse_schema.py`)
- [ ] Managed identity configured for the production script host
- [ ] Graph admin consent granted (`User.Read.All`, `Group.Read.All`, `Organization.Read.All`)
- [ ] Maker / audience / billing groups registered (security-enabled, not
      mail-enabled) in `fsi_cbgapprovedgrouppolicy`
- [ ] Per-user entitlement inputs resolved (`Get-CopilotEntitlement.ps1`); billing-policy
      coverage supplied via `-BillingPolicyInputPath` while the REST schema is unproven
- [ ] Coverage-gap analysis run in monitor-only mode; rows present in
      `fsi_cbgcoveragegap`

---

*Copilot Billing Governance v0.1.0-preview*
