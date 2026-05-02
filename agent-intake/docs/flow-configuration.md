# Power Automate flow configuration — Express path

> Step-by-step build instructions. **No exported flow JSON is shipped** (per repo Solution Content Policy). Build each flow in the Power Automate designer in your target environment, bind to the `fsi_intakerequest` Dataverse table created by the schema script, and validate with the smoke test in `scripts/smoke_test.ps1`.

There are **3 flows** for v0.1.0-preview Express path. All run in the same Power Platform environment as the `agent-intake` Dataverse tables.

---

## Flow 1 — `fsi-intake-router`

**Purpose:** When a new `fsi_intakerequest` row is inserted, evaluate the 6 trigger answers and route to Express, deferred, or default-deny.

**Trigger:** Dataverse — *When a row is added* (table `fsi_intakerequest`, scope: organisation).

**Steps:**

1. **Initialize variable** `triggerHits` (Integer, default `0`).
2. **For each trigger column** (`fsi_t1_initiates_financial_txn`, `fsi_t2_customer_facing`, `fsi_t3_autonomous_unmonitored`, `fsi_t4_handles_npi`, `fsi_t5_handles_mnpi`, `fsi_t6_crossborder_data`):
   - Condition: `value == 'Yes' OR value == 'Not sure'` → increment `triggerHits` by 1.
3. **Initialize variable** `decisionPath` (String).
4. **Compose** classification call: invoke a child flow `fsi-classify-tier-zone` (or run inline expression) that mirrors `scripts/seed_classification_rules.py`. For Express-path determination, the rule is simply:
   - `triggerHits == 0` → `decisionPath = 'Express'`, `tier = 3`, `zone = 3`
   - `triggerHits >= 1` → `decisionPath = 'DeferredOutOfScope'` (v0.2.0 will compute Standard/Full)
5. **Cross-border default-deny check** (per `research/04-open-questions-resolved.md` OQ-D):
   - If `fsi_t6_crossborder_data == 'Yes'` AND `fsi_makercountry != fsi_dataresidencycountry` (computed from connector inventory; for v0.1.0-preview default to maker country) → set `decisionPath = 'DefaultDeny'`, populate `fsi_intakedecisionlog` with `Reason = 'Cross-border data without Privacy override'`.
6. **Update `fsi_intakerequest`** row: `fsi_decisionpath = decisionPath`, `fsi_status = case decisionPath of Express:'PendingSponsor', Deferred:'DeferredOutOfScope', DefaultDeny:'Rejected'`.
7. **Append `fsi_intakedecisionlog`** entry (immutable; create-only): `fsi_decision = decisionPath`, `fsi_actor = 'system'`, `fsi_decisiontimeutc = utcNow()`, `fsi_evidencejson = <serialized trigger answers + computed tier/zone>`.
8. **Conditional branch** on `decisionPath`:
   - `Express` → call Flow 2 (`fsi-intake-sponsor-card`) passing `requestId`.
   - `DeferredOutOfScope` → send email to maker explaining v0.2.0 scope.
   - `DefaultDeny` → send email to maker with reason + Privacy team contact.

**Definition of done:** Insert a smoke-test row with all 6 triggers = "No"; verify `fsi_decisionpath = 'Express'`, `fsi_status = 'PendingSponsor'`, and a decision-log entry exists.

---

## Flow 2 — `fsi-intake-sponsor-card`

**Purpose:** Post the Teams adaptive card from `templates/sponsor-approval-card.json` to the named sponsor and persist their decision.

**Trigger:** *Manually triggered from Flow 1* (HTTP child flow) with input `requestId` (string).

**Steps:**

1. **Get a row by ID** — Dataverse: `fsi_intakerequest` where id = `requestId`.
2. **Compose** the adaptive card payload:
   - Load JSON from a Compose action (paste contents of `templates/sponsor-approval-card.json`).
   - Substitute tokens (`${fsi_agentname}` etc.) using `replace()` expressions.
   - Set `${flowEndpointApprove}` and `${flowEndpointReject}` to the HTTP-trigger URL of Flow 3.
   - Set `${portalRequestUrl}` to the Power Pages status page URL with the request ID query param.
3. **Post adaptive card and wait for a response** — Teams connector, recipient = `fsi_sponsorupn`. Timeout: 7 days (per OQ-J: sponsor SLA).
4. **On timeout:** update `fsi_status = 'SponsorTimeout'`; send reminder; escalate to sponsor's manager (Graph `/users/{upn}/manager`).
5. **On response:** Flow 3's HTTP trigger handles the persistence; this flow exits after Teams card is posted.

**Definition of done:** Sponsor receives card in Teams; clicking either button updates the request status within 30 seconds.

---

## Flow 3 — `fsi-intake-handoff`

**Purpose:** When a sponsor approves an Express-path request, persist the decision, mint an Entra Agent ID, and hand off to `agent-registry-automation`.

**Trigger:** *When an HTTP request is received* (POST). Body schema:
```json
{
  "requestId": "string",
  "decision": "Approved | Rejected",
  "notes": "string",
  "sponsorUpn": "string"
}
```

**Steps:**

1. **Get a row by ID** — `fsi_intakerequest` where id = `requestId`.
2. **Append `fsi_intakedecisionlog`** entry (immutable): `fsi_decision = decision`, `fsi_actor = sponsorUpn`, `fsi_decisiontimeutc = utcNow()`, `fsi_evidencejson = <full card payload + sponsor notes>`.
3. **Append `fsi_intakeapproval`** row: `fsi_approvertype = 'Sponsor'`, `fsi_approverupn = sponsorUpn`, `fsi_outcome = decision`, `fsi_attestationtext = <FINRA 3110 attestation copied from the card>`.
4. **Conditional branch** on `decision`:
   - `Approved`:
     - Update `fsi_intakerequest`: `fsi_status = 'Approved'`.
     - **Call** `scripts/setup_entra_agent_id.py` via Azure Function or HTTP-trigger Logic App; capture returned `agentId` into `fsi_entra_agentid`.
     - **Append `fsi_intakeauditevent`** row: `fsi_eventtype = 'AgentIDMinted'`.
     - **Insert into `agent-registry-automation` Dataverse** (cross-solution): create the registry shell row referencing `fsi_intakerequest.fsi_intakerequestid` for traceability.
     - **Send email** to maker: "Approved — your environment is being prepared. Watch for a follow-up from the Power Platform team."
     - **Passive InfoSec sample-log** (per OQ-A 10% sample): with 10% probability (`if(equals(rand(0,9),0), true, false)`), append `fsi_intakeauditevent` with `fsi_eventtype = 'InfoSecSampleSelected'` for offline review.
   - `Rejected`:
     - Update `fsi_intakerequest`: `fsi_status = 'Rejected'`.
     - **Send email** to maker with sponsor's notes and appeal-path instructions.

**Definition of done:** End-to-end smoke test: sponsor clicks Approve → request status flips to `Approved` within 30s; Entra Agent ID column populated; registry-shell row exists in `agent-registry-automation` table.

---

## Connection references required

| Connection | Type | Auth | Notes |
|---|---|---|---|
| Microsoft Dataverse | First-party | Service principal (managed-identity-first; client-secret legacy fallback) | Required for all 3 flows |
| Microsoft Teams | First-party | Service account or app-only | Posting adaptive cards |
| Office 365 Outlook | First-party | Service account | Maker / sponsor email notifications |
| HTTP with Microsoft Entra ID | Generic | Managed identity | For calling `setup_entra_agent_id.py` Function endpoint |

## Environment variables required

| Name | Type | Purpose |
|---|---|---|
| `fsi_intake_portal_base_url` | String | Power Pages portal base URL for status links |
| `fsi_intake_function_endpoint_agentid` | String | HTTPS endpoint for Entra Agent ID minting Function |
| `fsi_intake_registry_environment_id` | String | Target environment for `agent-registry-automation` cross-solution write |
| `fsi_intake_infosec_sample_rate` | Decimal | InfoSec passive-sample rate (default `0.10`) |

## Out of scope for v0.1.0-preview

- Standard / Full path review workflows (parallel reviewer routing)
- Sponsor escalation past first manager hop
- Reviewer queue Power App
- Slack / external notification channels
