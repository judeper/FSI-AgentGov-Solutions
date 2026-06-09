# APIM Gateway Setup

Step-by-step build instructions for the Agent Eligibility Gateway in Azure API Management (APIM). The two policy fragments in [`../templates/`](../templates/) are Azure infrastructure (APIM policy XML), not Power Platform flow artifacts. Build the **reference gateway in a non-production environment first**, validate the entitlement contract end to end, and only then consider an optional, conditional production deployment.

> Throughout, replace placeholder values (tenant GUID, environment URL, group object IDs) with your own. Commands use the Azure CLI (`az`) and `az apim` extensions; the portal equivalents are noted where relevant.

## Prerequisites recap

Complete [prerequisites.md](prerequisites.md) first. In particular you need: an APIM instance with a system-assigned managed identity, the gateway audience value and tenant ID, the audience (Viewers) security group object ID, network access from APIM to the Dataverse Web API and Event Hub, and a governance store populated by the sibling solutions.

## Step 1 — Provision the API Management instance and managed identity

1. Create (or reuse) an API Management instance:

   ```bash
   az apim create \
     --name apim-fsi-gateway \
     --resource-group rg-fsi-governance \
     --publisher-name "FSI Governance" \
     --publisher-email governance@example.com \
     --sku-name Developer
   ```

   Use the Developer SKU for the non-production reference gateway; choose a production SKU with an SLA for a production deployment.

2. Enable the **system-assigned managed identity** (this is the identity the gateway uses to read the governance store):

   ```bash
   az apim update \
     --name apim-fsi-gateway \
     --resource-group rg-fsi-governance \
     --set identity.type=SystemAssigned
   ```

   Record the resulting **principal (object) ID** and the managed identity's **application (client) ID** — you bind the latter to a Dataverse application user in Step 5.

## Step 2 — Create named values

The policy fragments reference these named values. Create them under **API Management > Named values** (or with `az apim nv create`). Mark secrets as secured where appropriate; none below is itself a credential.

| Named value | Example | Used by | Meaning |
|---|---|---|---|
| `aeg-tenant-id` | `00000000-0000-0000-0000-000000000000` | validate-jwt | Microsoft Entra tenant GUID for the OpenID config, issuer, and `tid` claim |
| `aeg-audience` | `api://agent-eligibility-gateway` | validate-jwt | Expected token audience (gateway app ID URI or protected API client ID) |
| `aeg-audience-group-id` | `11111111-2222-3333-4444-555555555555` | eligibility-check | Object ID of the audience / Viewers security group |
| `aeg-dataverse-resource` | `https://org.crm.dynamics.com` | eligibility-check | Governance-store resource URL (also the managed-identity token resource) |
| `aeg-decision-logger` | `aeg-decision-eventhub` | eligibility-check | API Management logger ID for the decision telemetry sink |
| `aeg-policy-version` | `2026.06.09` | eligibility-check | Policy version string stamped on every decision |
| `aeg-channel` | `custom-web` | eligibility-check | Owned channel label for this API (`custom-web` or `direct-line`) |
| `aeg-agent-id` | `contoso-kb-assistant` | eligibility-check | Default agent identifier when the request omits the `X-Agent-Id` header |

Example for one value:

```bash
az apim nv create \
  --resource-group rg-fsi-governance \
  --service-name apim-fsi-gateway \
  --named-value-id aeg-tenant-id \
  --display-name aeg-tenant-id \
  --value 00000000-0000-0000-0000-000000000000
```

Repeat for each row. For a multi-agent gateway, set `aeg-agent-id` as a per-API or per-operation default and have clients send the `X-Agent-Id` header to override it.

## Step 3 — Import the policy fragments

Author both fragments as reusable **policy fragments** (API Management > Policy fragments), using the XML from [`../templates/`](../templates/):

1. `aeg-validate-jwt` — from [apim-validate-jwt.policy.xml](../templates/apim-validate-jwt.policy.xml). Validates the Microsoft Entra ID token, pins the tenant, and stores the token in the `jwt` context variable. Returns **401** on failure.
2. `aeg-eligibility-check` — from [apim-eligibility-check.policy.xml](../templates/apim-eligibility-check.policy.xml). Stamps a correlation ID, applies the audience gate, reads the governance store with the managed identity, applies the switch-on-pathway entitlement contract, emits decision telemetry, and returns a governed **403** on deny.

Portal: paste the fragment body (the content inside `<fragment>...</fragment>`) into the fragment editor. CLI / IaC: deploy via `az apim` policy-fragment operations or an ARM/Bicep `Microsoft.ApiManagement/service/policyFragments` resource.

## Step 4 — Wire the fragments into the API `<inbound>` section

On the API (or operation) that fronts the owned-channel agent backend, reference the fragments in order — token validation first, eligibility second:

```xml
<inbound>
  <include-fragment fragment-id="aeg-validate-jwt" />
  <include-fragment fragment-id="aeg-eligibility-check" />
  <base />
</inbound>
```

The backend (`<backend>` / set-backend-service) points at the agent endpoint — the Copilot Studio Direct Line endpoint or the custom agent backend for the owned channel. Order matters: a request that fails `validate-jwt` (401) never reaches the eligibility check, and a request denied by the eligibility check (403) never reaches the backend.

## Step 5 — Grant the managed identity read access to the governance store

The eligibility fragment reads `fsi_copilotagent` (and `fsi_cbgentitlementmaterialized` on a metered pathway) using `<authentication-managed-identity resource="{{aeg-dataverse-resource}}" />`. Authorize that identity in Dataverse:

1. In the governance-store environment, create an **application user** bound to the APIM managed identity's **application (client) ID** (Power Platform admin center > Environment > Settings > Users + permissions > Application users > New app user).
2. Create or reuse a **security role** granting **Read** on `fsi_copilotagent` and `fsi_cbgentitlementmaterialized`. Grant **Create** on `fsi_aegdecisionlog` only if the same identity writes decision rows directly (most deployments write through the telemetry sink instead — see Step 6).
3. Assign that role to the application user.

This keeps the gateway to least privilege: read-only on the governance tables it consults, no write access to the source-of-truth inventory or billing tables.

> Cross-solution column names were reconciled against the sibling schema scripts on 2026-06-09: compliance posture = `fsi_caicompliancestate.fsi_risklevel` (keyed on `fsi_agentid`); entitlement decision = `fsi_cbgentitlementmaterialized` (`fsi_decision` / `fsi_pathway` / `fsi_decisionreason`, keyed on `fsi_agentid` + `fsi_userupn`). Re-verify against live tenant metadata before production use.

## Step 6 — Configure the decision telemetry sink

1. Create an **Event Hub** and register it as an API Management **logger** whose ID matches the `aeg-decision-logger` named value:

   ```bash
   az apim logger create \
     --resource-group rg-fsi-governance \
     --service-name apim-fsi-gateway \
     --logger-id aeg-decision-eventhub \
     --logger-type azureEventHub \
     --description "AEG per-decision telemetry" \
     --credentials connectionString="$EVENTHUB_CONNECTION_STRING"
   ```

   Prefer a managed-identity-based Event Hub connection where your APIM tier supports it, rather than a connection string.

2. Stand up a downstream component (Azure Function, Stream Analytics, or Logic App) that consumes the Event Hub and writes each record into `fsi_aegdecisionlog`. Map the JSON fields the policy emits (`correlationId`, `decisionTime`, `agentId`, `userObjectId`, `channel`, `pathway`, `decision`, `denyReason`, `anomaly`, `httpStatus`, `policyVersion`) to the table's logical columns. See [dataverse-schema.md](dataverse-schema.md) and the illustrative rows in [../templates/decision-log.sample.json](../templates/decision-log.sample.json).

3. Create the table if you have not already:

   ```bash
   python scripts/create_aeg_dataverse_schema.py --output-docs
   ```

Writing decisions to Dataverse is optional but recommended: it surfaces gateway decisions on the Copilot Hub / governance dashboard (control 3.8). The synchronous request path stays fast because logging is off-path via the Event Hub.

## Step 7 — Validate the reference gateway (non-production first)

Exercise the entitlement contract end to end against representative agents and cohorts, and confirm each expected outcome:

| Scenario | Expected decision | Expected HTTP | Expected `denyReason` |
|---|---|---|---|
| Authorized caller, pathway `none` | Allow | 200 | None |
| Authorized caller, pathway `metered`, in eligible cohort | Allow | 200 | None |
| Authorized caller, pathway `metered`, in no eligible cohort | Deny | 403 | NotInEligibleCohort |
| Caller not in audience / Viewers group | Deny | 403 | OutOfPolicyAudience |
| Agent non-compliant in governance store | Deny | 403 | AgentNonCompliant |
| Pathway unmapped / unknown | Allow (anomaly) | 200 | None |
| Missing / invalid / wrong-tenant token | Deny | 401 | (returned by validate-jwt) |

For each scenario, confirm a decision record reaches the telemetry sink and lands in `fsi_aegdecisionlog` with the correlation ID echoed in the response `X-AEG-Correlation-Id` header. This validation is the primary deliverable of the preview; a production deployment is optional and conditional on the customer operating owned custom-web / Direct Line channels.

## Step 8 — Harden the audience gate for large-group tenants (groups overage)

When a caller belongs to more than ~200 groups, Microsoft Entra ID omits the `groups` claim and emits a `_claim_names` / `_claim_sources` overage indicator instead. The audience gate in the eligibility fragment fails **closed** in that case (the caller is treated as not in the audience). For tenants where overage is common, add a managed-identity Microsoft Graph fallback:

- On overage, call `POST https://graph.microsoft.com/v1.0/users/{oid}/checkMemberGroups` (or `getMemberGroups`) from a `<send-request>` authenticated with `<authentication-managed-identity resource="https://graph.microsoft.com" />`, passing the audience group ID, and treat a positive result as audience membership.
- Grant the gateway managed identity the appropriate Microsoft Graph application permission (for example `GroupMember.Read.All`) and admin consent.

Keep the fail-closed default unless this fallback is in place, so that an omitted `groups` claim never silently grants access.

## Operational notes

- **401 vs. 403 split.** Token problems return 401 in `aeg-validate-jwt`; authenticated-but-not-eligible requests return a governed 403 in `aeg-eligibility-check`. Keep this split so clients can distinguish a sign-in problem from an authorization decision.
- **Correlation IDs.** Clients may supply `X-AEG-Correlation-Id`; otherwise the gateway generates one. It is echoed on responses and stamped on every decision record for end-to-end tracing.
- **Fail-closed defaults.** Audience gate, compliance check, and metered-cohort lookup all fail closed; an unmapped pathway fails open with an anomaly flag. Review these defaults against the customer's risk posture during ratification.
- **Least privilege.** The gateway managed identity holds read-only access to the governance tables and (optionally) create on `fsi_aegdecisionlog`; it has no write access to the inventory or billing source tables.
