# Prerequisites

The Agent Eligibility Gateway is optional infrastructure. Provision the items below only if you operate **owned custom-web / Direct Line agent channels** and intend to stand up a reference gateway (recommended) or a production gateway (optional and conditional). A tenant whose agents run only on first-party Teams / Microsoft 365 Copilot / SharePoint surfaces does not need this solution — see [architecture.md](architecture.md).

## Roles required

| Role | Where | Why |
|---|---|---|
| Azure contributor (or owner) | The resource group hosting API Management | Deploy the APIM instance, named values, policy fragments, and the Event Hub telemetry sink |
| Microsoft Entra ID Security Administrator (or Application Administrator) | Microsoft Entra ID | Register the gateway app, create / manage the audience (Viewers) security groups, and grant the gateway managed identity read access to the governance store |
| Dataverse System Administrator | The governance-store environment | Create the application user for the gateway managed identity and assign it a read-only security role |
| Power Platform agent maker / admin | The agent's environment | Confirm each target agent satisfies the Entra-ID-auth precondition |

These map to the `azure-admin` and `security-admin` prerequisites declared in `manifest.yaml`.

## 1. Azure API Management instance

- An **API Management instance** in a region appropriate for your data-residency requirements. The Developer tier is sufficient for the non-production reference gateway; choose a production tier with an SLA for a production deployment.
- **System-assigned managed identity** enabled on the instance. The gateway uses it to read the governance store via `<authentication-managed-identity>` — this is the managed-identity-first authentication path and the recommended approach. No client secret is stored in the policy.
- Outbound network access from APIM to the Dataverse Web API endpoint of the governance store and to the Event Hub used for decision telemetry.

## 2. Gateway Entra ID app registration and token audience

- A **gateway app registration** (or an Application ID URI on the protected agent API) whose value becomes the expected **audience** that `validate-jwt` checks. Client tokens presented to the gateway must carry this audience.
- The **tenant ID** (GUID) for the OpenID configuration and the `tid` required-claim.
- Client applications on the owned channel must acquire tokens for this audience using the Microsoft Entra ID sign-in flow.

## 3. Audience (Viewers) security groups

- One or more **Microsoft Entra ID security groups** that define each agent's audience. Membership in the agent's group is the audience gate that supports controls 1.1 and 1.18. These groups act as **Viewers (chat)** — they govern who may chat with the agent, not authoring rights.
- The **object ID** of the audience group is referenced by the gateway policy (named value `aeg-audience-group-id`).
- For tenants where callers may belong to more than ~200 groups, plan for the **groups-overage** case: the `groups` claim is omitted from large-membership tokens, and the audience gate fails closed. The setup guide documents an optional managed-identity Microsoft Graph `checkMemberGroups` fallback for this case.

## 4. Per-agent Entra-ID-auth precondition

Every agent placed behind the gateway must present a signed-in Microsoft Entra ID user context. Confirm, per agent:

- `bot.authenticationmode` is **Integrated** (`2`) or **Custom Azure Active Directory** (`3`) — the Microsoft Entra ID modes.
- `bot.authenticationtrigger` is **Always** (`1`) — require users to sign in is ON.

**No-authentication (`1`) and Generic OAuth2 (`4`) agents do not qualify**: a non-Microsoft identity provider being "authenticated" is not sufficient, because sharing-based audience control is unavailable. Assert this with:

```powershell
# Offline (explicit) assertion
.\scripts\Test-AgentEligibilityPrecondition.ps1 -AuthenticationMode Integrated -RequireUsersToSignIn

# Live read of the bot table (dev-only token fallback shown; prefer a managed
# identity or workload-identity token where the host supports it)
$token = (Get-AzAccessToken -ResourceUrl 'https://org.crm.dynamics.com' -AsSecureString).Token | ConvertFrom-SecureString -AsPlainText
.\scripts\Test-AgentEligibilityPrecondition.ps1 -EnvironmentUrl 'https://org.crm.dynamics.com' -AgentSchemaName 'contoso_kbAssistant' -AccessToken $token
```

The live path requires the **Az.Accounts** module for the dev-only `Get-AzAccessToken` fallback. In an Azure-hosted runner, prefer a system-assigned or user-assigned managed identity instead of an interactive token.

## 5. Governance store (sibling solutions)

The gateway **reads** governance state populated by two sibling solutions; it does not create or populate those tables:

| Table | Owning solution | Fields the gateway reads (reconciled 2026-06-09) |
|---|---|---|
| `fsi_caicompliancestate` | `copilot-agent-inventory` | `fsi_risklevel` (keyed on `fsi_agentid`) |
| `fsi_cbgentitlementmaterialized` | `copilot-billing-governance` | `fsi_decision`, `fsi_pathway`, `fsi_decisionreason` (keyed on `fsi_agentid` + `fsi_userupn`) |

Re-verify these logical names against live tenant metadata before production use; the OData `$select` / `$filter` clauses in [../templates/apim-eligibility-check.policy.xml](../templates/apim-eligibility-check.policy.xml) already target them.

The gateway managed identity needs an **application user** in the governance-store environment with a security role granting **Read** on those two tables (and Create on `fsi_aegdecisionlog` if the telemetry sink writes through the same identity — see below).

## 6. Decision telemetry sink (optional but recommended)

- An **Event Hub** (or equivalent) registered as an API Management **logger**, referenced by the named value `aeg-decision-logger`. The gateway emits one structured decision record per request to this logger off the request path.
- A downstream component (Azure Function, Stream Analytics, or Logic App) that reads the Event Hub and writes rows into `fsi_aegdecisionlog`. This keeps the synchronous request path fast while still landing a per-decision audit trail for control 3.8.
- The optional `fsi_aegdecisionlog` table, created with:

```bash
python scripts/create_aeg_dataverse_schema.py --output-docs
```

See [dataverse-schema.md](dataverse-schema.md) for the table shape. Persisting decisions in Dataverse is optional — the gateway emits the same record to the telemetry sink regardless — but it surfaces decisions on the Copilot Hub / governance dashboard.

## Summary checklist

- [ ] API Management instance with system-assigned managed identity enabled
- [ ] Gateway app registration / audience value and tenant ID recorded
- [ ] Audience (Viewers) security group(s) created; object IDs recorded
- [ ] Groups-overage approach decided (claim vs. Graph fallback)
- [ ] Each target agent passes `Test-AgentEligibilityPrecondition.ps1`
- [ ] Governance store reachable; managed-identity application user has read on `fsi_copilotagent` and `fsi_cbgentitlementmaterialized`
- [ ] Event Hub logger and downstream sink to `fsi_aegdecisionlog` configured (optional)
- [ ] Non-production reference gateway planned before any production deployment
