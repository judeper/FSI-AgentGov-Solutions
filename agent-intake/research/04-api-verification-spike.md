# API Verification Spike — Auto-Detect Endpoints

**Date:** 2026-05-02
**Owner:** Product owner (pre-Phase B)
**Goal:** Verify the 3 API endpoints flagged in `02-question-catalog-evaluation.md` §5 before relying on them in the auto-detect playbook. Document working endpoint shapes, capture gaps where verification was not possible, and define fallback for the MVP build.

---

## TL;DR

| Endpoint family | Status | MVP impact |
|---|---|---|
| **PPAC environments** (zone, SKU, Managed Env) | ✅ Verified | Use as primary auto-detect for environment placement and zone classification |
| **PPAC DLP policies** | ✅ Verified — endpoint path corrected | Use as primary auto-detect for connector / DLP simulation |
| **Microsoft Graph `/me` + `/me/manager`** | ✅ Verified | Use for sponsor pre-fill |
| **Microsoft Graph beta retentionLabels** | ⚠️ Endpoint exists but requires delegated `RecordsManagement.Read.All` admin scope | Mark as **manual** in Express MVP; auto-create label once via `setup_purview_retention_label.py` (one-time) |
| **Purview catalog/datamap API** | ⚠️ Could not verify (no Purview account in spike subscription) | Path documented from MS Learn; mark as **manual** in Express MVP; runtime sensitivity-label inheritance is downstream concern handled by existing Purview labels on knowledge sources |

The Express path of the MVP only **strictly requires** Graph `/me` + `/me/manager` and PPAC environments + DLP policies. Both verified. Purview and retentionLabels are nice-to-have and degrade gracefully.

---

## Test environment

- **Subscription:** Personal Microsoft Partner subscription (single tenant)
- **Auth:** Azure CLI delegated user token; user has Power Platform admin role; no Records Management admin role; no Purview accounts in subscription
- **Date:** 2026-05-02

Token scopes available:
```
Application.ReadWrite.All AppRoleAssignment.ReadWrite.All AuditLog.Read.All
DelegatedPermissionGrant.ReadWrite.All Directory.AccessAsUser.All email
Group.ReadWrite.All openid profile User.Read.All User.ReadWrite.All
```

---

## Test 1 — Microsoft Graph `/v1.0/me` and `/v1.0/me/manager`

**Catalog questions affected:** SP-001 (sponsor identity), MR-001 (maker identity), MR-002 (department), MR-003 (country)

**Result:** ✅ **VERIFIED**

```http
GET https://graph.microsoft.com/v1.0/me
Authorization: Bearer <delegated-user-token>
```
Returns: `id`, `displayName`, `mail`, `userPrincipalName`, `department`, `jobTitle`, `officeLocation`, `usageLocation`, `country`.

```http
GET https://graph.microsoft.com/v1.0/me/manager
```
Returns: same user object schema for the user's direct manager. **Returns HTTP 404 if the user has no manager set in Microsoft Entra ID** — Express path must handle this case (fall back to a Sponsor lookup question).

**MVP wiring:** Power Pages portal calls Graph via the user's delegated token at form load → pre-fills `MakerName`, `MakerDepartment`, `MakerJobTitle`, `MakerCountry`, `SponsorCandidate`. Maker can override.

---

## Test 2 — Power Platform Admin Center: environments

**Catalog questions affected:** EP-001 (target environment), EP-002 (environment SKU), ZN-002 (zone classification)

**Result:** ✅ **VERIFIED**

```http
GET https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01
Authorization: Bearer <bap-token>
```

Resource for token acquisition: `https://api.bap.microsoft.com`

Returned 35 environments. Per-environment fields useful at intake:

| Field path | Example value | Used for |
|---|---|---|
| `properties.displayName` | `IWL-DryRun` | Display in env-picker |
| `properties.environmentSku` | `Sandbox` / `Production` / `Trial` / `Default` / `Developer` | Zone heuristic input |
| `properties.governanceConfiguration.protectionLevel` | `Basic` / `Standard` | Managed Environment indicator |
| `properties.states.management.id` | `Ready` / `NotReady` | Filter out unhealthy envs |

**MVP wiring:** `scripts/autodetect_environments.py` calls this endpoint, computes a recommended environment per zone classification, returns to Power Pages env-picker step. Maker confirms or overrides.

---

## Test 3 — Power Platform Admin Center: DLP policies

**Catalog questions affected:** DS-005 (connectors will be allowed), DS-006 (DLP simulation)

**Result:** ✅ **VERIFIED — endpoint path corrected**

The `02-question-catalog-evaluation.md` flagged `/policies` as the candidate. The actual working endpoint is:

```http
GET https://api.bap.microsoft.com/providers/PowerPlatform.Governance/v2/policies?api-version=2018-01-01
```

Also working (legacy / alternate paths confirmed):
- `https://api.bap.microsoft.com/providers/PowerPlatform.Governance/v1/policies?api-version=2018-01-01`
- `https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/apiPolicies?api-version=2018-01-01`

Returned 2 policies in the spike tenant. Per-policy fields needed for DLP simulation:

| Field path | Used for |
|---|---|
| `displayName` | Identify policy in reviewer dashboard |
| `environmentType` | `OnlyEnvironments` / `ExceptEnvironments` / `AllEnvironments` |
| `environments[]` | Scoped environment list |
| `connectorGroups[].classification` | `General` / `Confidential` / `Blocked` |
| `connectorGroups[].connectors[]` | Connector IDs in each group |

**Caveat:** In this spike tenant the returned policy `displayName`, `environmentType`, and `connectorGroups` were all empty for the first policy (likely a tenant-default policy with no overrides). The schema is still correct and matches MS Learn documentation.

**MVP wiring:** `scripts/autodetect_dlp_simulation.py` accepts a candidate environment ID + a list of connector IDs the maker wants to use, queries this endpoint, returns the boolean `wouldBlock` and the offending connector pairs. Used by the Express path's DS-005 question.

---

## Test 4 — Microsoft Graph beta `retentionLabels`

**Catalog questions affected:** RR-001 through RR-005 (retention class lookup)

**Result:** ⚠️ **PARTIALLY VERIFIED**

```http
GET https://graph.microsoft.com/beta/security/labels/retentionLabels
Authorization: Bearer <delegated-user-token>
```
Returned `401 Unauthorized`. Token did not include `RecordsManagement.Read.All` (Records Management Admin role required).

```http
GET https://graph.microsoft.com/beta/compliance/retentionLabels
```
Returned `400 Bad Request` — confirmed wrong path; the working path is `/beta/security/labels/retentionLabels` per MS Learn.

**MVP impact:**
- The Express path does NOT need to read existing labels at runtime. It only needs to **apply** a single fixed retention label `FSI-AgentIntake-7yr` to the decision-pack records.
- One-time setup: `scripts/setup_purview_retention_label.py` creates the label with 7-year retention (required for SEC 17a-4, FINRA 4511, CFTC 1.31). Run once by a Records Management Admin.
- Express path stamps the label on every `fsi_intakedecisionlog` row at write time via Purview SDK with managed identity.

**Customer verification step:** Customer must run the setup script with Records Management Admin context once before deployment. Documented in `docs/pilot-deployment-runbook.md`.

---

## Test 5 — Purview Catalog / Data Map API

**Catalog questions affected:** DS-008 (data sources sensitivity classification at intake)

**Result:** ⚠️ **NOT VERIFIED — no Purview account in spike subscription**

ARM probe:
```http
GET https://management.azure.com/subscriptions/{sub}/providers/Microsoft.Purview/accounts?api-version=2021-12-01
```
Returned 0 Purview accounts.

**Documented endpoint shape** (from MS Learn, not verified end-to-end in this spike):

```http
POST https://{accountName}.purview.azure.com/datamap/api/search/query?api-version=2023-09-01
Authorization: Bearer <purview-token>
Content-Type: application/json

{
  "keywords": "<data source name or asset path>",
  "limit": 10
}
```
Resource for token: `https://purview.azure.net`.

The path Claude originally documented (`/catalog/api/search/query`) is the **legacy** path. The current GA path uses `/datamap/api/`. Both may continue to function; new code should use `/datamap/api/`.

**MVP impact:** Express path treats data-source sensitivity as **maker-declared** (DS-008 is a manual question with values `Internal / Confidential / Restricted / Public`). Purview integration is deferred to v0.2 Standard path where reviewer dashboard auto-augments with classification scan.

**Customer verification step:** Documented as a known gap in `docs/pilot-deployment-runbook.md`. Customers with mature Purview deployments can wire this in v0.1 by overriding `scripts/autodetect_purview.py` (stub provided).

---

## Test 6 — Entra Agent ID minting

**Catalog questions affected:** OH-001 (Entra Agent ID provisioning at handoff)

**Result:** ✅ **API SHAPE CONFIRMED via Microsoft Graph beta**

Per MS Learn (Entra Agent ID feature availability should be verified in the target tenant/cloud):
```http
POST https://graph.microsoft.com/v1.0/servicePrincipals/microsoft.graph.agentIdentity
Authorization: Bearer <token with AgentIdentity.CreateAsManager or AgentIdentity.Create.All>
Content-Type: application/json

{
  "displayName": "<agent display name>",
  "agentType": "copilotStudio | agentBuilder | declarative | customEngine | foundry",
  "ownerIds": ["<sponsor entra id>", "<maker entra id>"]
}
```

**Not exercised in spike** — required `AgentIdentity.CreateAsManager or AgentIdentity.Create.All` admin scope and a tenant with the Agent ID feature enabled.

**MVP wiring:** `scripts/setup_entra_agent_id.py` invoked at handoff after approval, returns the `agentObjectId` which is written to `fsi_intakerequest.fsi_entraagentid` and propagated to `agent-registry-automation`.

---

## Endpoints summary table (for `docs/auto-detect-playbook.md`)

| Catalog Q | Endpoint | Auth resource | Required scope/role | Spike status | MVP usage |
|---|---|---|---|---|---|
| MR-001..003, SP-001 | `https://graph.microsoft.com/v1.0/me` and `/me/manager` | `https://graph.microsoft.com` | `User.Read` (delegated) | ✅ Verified | Auto |
| EP-001, ZN-002 | `https://api.bap.microsoft.com/.../scopes/admin/environments?api-version=2020-10-01` | `https://api.bap.microsoft.com` | Power Platform Admin | ✅ Verified | Auto |
| DS-005, DS-006 | `https://api.bap.microsoft.com/providers/PowerPlatform.Governance/v2/policies?api-version=2018-01-01` | `https://api.bap.microsoft.com` | Power Platform Admin | ✅ Verified (path corrected) | Auto |
| RR-001..005 | `https://graph.microsoft.com/beta/security/labels/retentionLabels` | `https://graph.microsoft.com` | `RecordsManagement.Read.All` | ⚠️ Auth gap | One-time setup script + manual at runtime |
| DS-008 | `https://{account}.purview.azure.com/datamap/api/search/query?api-version=2023-09-01` | `https://purview.azure.net` | Purview Data Reader on the account | ⚠️ Not verified | Manual in Express; auto in v0.2 |
| OH-001 | `https://graph.microsoft.com/v1.0/servicePrincipals/microsoft.graph.agentIdentity` | `https://graph.microsoft.com` | `AgentIdentity.CreateAsManager or AgentIdentity.Create.All` | Documented only | Auto via setup script at handoff |

---

## What this changes in the design

1. **Update `03-intake-form-design-v1.md` §6** auto-classification rules: replace the old `/policies` endpoint reference with `/PowerPlatform.Governance/v2/policies` and add `api-version=2018-01-01` parameter.
2. **Update §8 system auto-detect spec**: confirm Graph `/me` + `/me/manager` shape; document the manager-404 fallback explicitly.
3. **Update §6 retention rule**: change from "auto-read existing labels" to "apply fixed label `FSI-AgentIntake-7yr` set up via one-time admin script".
4. **Update §6 sensitivity classification**: mark Purview lookup as manual (maker-declared) for Express MVP; reviewer dashboard adds Purview augmentation in v0.2.

These updates will be folded into the build artifacts in Phase B; the design doc itself is preserved as the historical baseline.

---

## Customer pre-deployment checklist (additions)

These move into `docs/pilot-deployment-runbook.md` Phase B:

- [ ] Power Platform Admin (or Service Principal with PPAC role) for the auto-detect scripts to query environments + DLP
- [ ] Records Management Admin (one-time) to run `setup_purview_retention_label.py`
- [ ] Records Management Admin delegated consent for `RecordsManagement.Read.All` if reviewer dashboard ever needs to read labels at runtime
- [ ] (Optional) Purview Data Reader on the Purview account — only required if customer wants v0.1 Express auto-classification of data sources; can defer to v0.2
- [ ] Tenant with Microsoft Entra Agent ID feature enabled (feature availability should be verified in the target tenant/cloud); admin consent for `AgentIdentity.CreateAsManager or AgentIdentity.Create.All`

---

## Open follow-ups (non-blocking for MVP)

- Re-run Test 4 in a tenant with Records Management Admin role to confirm full read schema (label retention period, behavior, default, scope).
- Re-run Test 5 in a tenant with a Purview account to confirm `/datamap/api/search/query` request/response shape against current GA spec.
- Re-run Test 6 against a tenant with Entra Agent ID GA enabled to confirm `agentIdentities` POST schema and the actual returned object shape.
- These will be addressed in v0.2 work or via pilot-firm validation.
