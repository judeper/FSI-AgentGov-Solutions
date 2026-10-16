# Prerequisites

Requirements for deploying Copilot Billing Governance (CBG).

---

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Microsoft 365 Copilot** | Licensed users are an input to the entitlement decision |
| **Copilot consumption billing** (PAYG and/or prepaid credits) | The policy objects this solution governs |
| **Azure subscription** | Backs the pay-as-you-go (PAYG) billing policy |
| **Power Automate Premium**, or an applicable **Power Automate Process** license | Premium-connector sync and coverage-gap flows; license the scheduled flow appropriately |
| **Dataverse capacity** | Policy, entitlement, cache, and coverage-gap storage |

> **Verified 2026-10-16:** **June 16, 2026** is the Work IQ API GA / consumption-pricing
> date, not the start of all Copilot Credits billing. Chat credit policies remain
> Chat-only; SharePoint agents use PAYG. Work IQ API uses separate spending policies
> under **Copilot > Cost management**. CBG does not yet evaluate those policies.
> Sources: [PAYG setup](https://learn.microsoft.com/microsoft-365/copilot/pay-as-you-go/setup),
> [capacity packs](https://learn.microsoft.com/microsoft-365/copilot/pay-as-you-go/copilot-capacity-packs),
> [usage-based billing](https://learn.microsoft.com/microsoft-365/copilot/usage-based-billing-overview-copilot-credits),
> [Power Automate licensing](https://learn.microsoft.com/power-platform/admin/power-automate-licensing/faqs).

---

## Permissions

### Microsoft Entra ID roles

| Role | Required for |
|------|--------------|
| **Billing Administrator**, **AI Administrator**, or **Entra Global Admin** | Configure PAYG billing in the Microsoft 365 admin center |
| **Entra Global Admin** | Enable capacity-pack usage and create Copilot credit policies; purchasing packs also supports Billing Administrator |
| **Entra Global Admin** *(or delegated group admin)* | Register maker / audience / billing security groups in the admission-gated registry |

### Azure roles

| Role | Required for |
|------|--------------|
| **Owner or Contributor** | Both the Azure subscription and resource group backing the PAYG billing policy; the subscription must be in the Microsoft 365 tenant |

### Power Platform roles

| Role | Required for |
|------|--------------|
| **Power Platform Admin** | Environment configuration and solution import |
| **System Administrator** | Dataverse table creation and application-user role assignment |

### Microsoft Graph permissions

| Permission | Type | Purpose |
|------------|------|---------|
| `LicenseAssignment.Read.All` (least privileged; delegated `User.Read.All` is also supported) | **Delegated only** for `licenseDetails` | Read direct and group-assigned user licenses; the signed-in user also needs a supported Entra role, such as Directory Readers |
| `Group.Read.All` | Delegated or Application, according to the operation/host | Read group metadata and transitive membership; grant access to user properties needed for UPN expansion and verify no limited-information member rows |
| `LicenseAssignment.Read.All` (least privileged; `Organization.Read.All` is a supported higher privilege) | Delegated or Application for `subscribedSkus` | Read tenant SKU/service-plan mappings without inferring entitlement from display names |

> **Current resolver restriction:** Microsoft documents **no application permission**
> for `GET /users/{id}/licenseDetails`. A managed-identity or client-credentials token
> with `User.Read.All` cannot make this a supported unattended license-read path.
> Use a delegated diagnostic run with the permission and Entra role above; do not
> schedule the existing resolver as app-only. An unattended replacement needs a
> separately validated implementation. A license-read failure is unresolved coverage,
> not evidence that the user lacks a license. Sources:
> [licenseDetails](https://learn.microsoft.com/graph/api/user-list-licensedetails?view=graph-rest-1.0),
> [transitive members](https://learn.microsoft.com/graph/api/group-list-transitivemembers?view=graph-rest-1.0),
> [subscribedSkus](https://learn.microsoft.com/graph/api/subscribedsku-list?view=graph-rest-1.0).

### Power Platform billing-policy REST (PAYG / credit coverage)

The per-user resolver ([`Get-CopilotEntitlement.ps1`](../scripts/Get-CopilotEntitlement.ps1))
maps **PAYG / credit coverage** to the engine's `inCreditScopeGroup` input. There is **no
Microsoft Graph endpoint** for billing-policy membership, so coverage is read from the
Power Platform licensing REST
(`https://api.powerplatform.com/licensing/billingPolicies?api-version=2024-10-01`)
using a token for the `https://api.powerplatform.com/` audience. The
[Power Platform API reference](https://learn.microsoft.com/rest/api/power-platform/)
documents a Licensing namespace, but does not establish that this particular list
version returns Microsoft 365 Chat credit-policy scope or Work IQ spending policies.
Validate endpoint-specific permissions and response fields before relying on a live
read; a generic admin role or HTTP 200 is not evidence of complete policy coverage.

> **Summary-only list view.** The live list response (verified HTTP 200 against a test
> tenant) is a summary that omits per-policy scope and capability detail, so live-read
> policies route to manual review (fail-closed). A live-read failure degrades to a warning
> and a manual-review flag rather than aborting the report. Prefer supplying the resolver an
> explicit `-BillingPolicyInputPath` / `-BillingPolicy` — for example the normalized output
> of [`Get-BillingPolicyInventory.ps1`](../scripts/Get-BillingPolicyInventory.ps1) — and
> treat the live read as best-effort.

---

## Authentication model (managed-identity-first)

Use a managed identity for Azure-hosted automation **where the target API supports
application access**. The current `licenseDetails` resolver is the delegated-only
exception described above; a client secret is not a workaround.

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
changing the scripts. The resolver accepts `-GraphAccessToken`; supply a suitable
delegated token for license reads rather than relying on its app-only
authentication guidance.

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

- [ ] Paid Microsoft 365 Copilot license state recorded for evaluated users;
      unlicensed users are not automatically excluded from all metered scenarios
- [ ] PAYG billing policy connected to the intended service (create then connect)
      **and/or** Chat credit policy configured, with credits allocated to the
      Microsoft Copilot Chat environment under **Licensing > Copilot Studio**
- [ ] Record prepaid capacity and overage settings; standalone exhaustion behavior
      must not be mistaken for an instantaneous per-agent cap
- [ ] Work IQ API consumers reviewed separately in **Copilot > Cost management**;
      do not infer Work IQ coverage from a Chat/SharePoint billing policy
- [ ] Azure subscription budget alert configured for PAYG spend
- [ ] Power Automate Premium for the scheduled flow owner, or applicable Process licensing
- [ ] Dataverse environment ready; CBG schema deployed
      (`python scripts/create_cbg_dataverse_schema.py`)
- [ ] Managed identity configured for the production script host
- [ ] Delegated license-read permission, supported signed-in Entra role, and consent
      verified; app-only `licenseDetails` is not used
- [ ] Maker / audience / billing groups registered (security-enabled, not
      mail-enabled) in `fsi_cbgapprovedgrouppolicy`
- [ ] Per-user entitlement inputs resolved (`Get-CopilotEntitlement.ps1`); billing-policy
      coverage supplied via `-BillingPolicyInputPath` while the REST schema is unproven
- [ ] Coverage-gap analysis run in monitor-only mode; rows present in
      `fsi_cbgcoveragegap`
- [ ] Preserve unresolved-user / uncertain-policy evidence; row presence alone
      does not establish complete coverage or authorize enforcement
- [ ] Native agent limits reviewed in **Licensing > Copilot Studio > Summary >
      Manage Agents**; record notification/hard-stop settings, enforcement latency,
      and separately billed agent flows before treating a cap as effective

---

*Copilot Billing Governance v0.1.0-preview*
