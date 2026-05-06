# Power Automate flow configuration — Express path

The repository intentionally does **not** ship exported Power Automate flow JSON. Build these flows manually in the Power Automate designer so each customer can bind the connections, environment variables, and maker/checker approvals to its tenant.

Use Dataverse **logical names** in all OData filters and expressions. For example, the schema name `fsi_AgentDisplayName` is referenced as `fsi_agentdisplayname`.

## Environment variables

| Name | Example | Used by |
|---|---|---|
| `AGENT_INTAKE_POLICY_VERSION` | `0.2.0-preview` | Flow 1 decision pack |
| `AGENT_INTAKE_RETENTION_LABEL` | `FSI-AgentIntake-7yr` | Flow 1/3 retention stamping |
| `AGENT_INTAKE_WORM_LABEL` | `FSI-AgentIntake-7yr-WORM` | Flow 3 decision log |
| `AGENT_INTAKE_AGENT_BLUEPRINT_ID` | `<agentIdentityBlueprintId>` | Flow 3 Agent ID creation |
| `AGENT_INTAKE_INFOSEC_QUEUE` | `infosec-agent-review@contoso.com` | Flow 1 sample audit |
| `AGENT_INTAKE_SPONSOR_SLA_DAYS` | `3` | Flow 2 timeout |

## Flow 1 — `fsi-intake-router`

**Trigger:** Microsoft Dataverse connector — **When a row is added, modified or deleted**.

- Change type: **Added**
- Table name: **Intake Requests** (`fsi_intakerequests`)
- Scope: Organization
- Trigger condition: `fsi_status` is `Submitted` or the request transitions from Draft to Submitted

**Processing steps:**

1. Initialize an array with the six trigger logical names:
   - `fsi_t1initiatesfinancialtxn`
   - `fsi_t2customerfacing`
   - `fsi_t3autonomousunmonitored`
   - `fsi_t4handlesnpi`
   - `fsi_t5handlesmnpi`
   - `fsi_t6crossborderdata`
2. Count answers equal to `Yes` or `Not sure` and store the count in `fsi_triggerhitcount`.
3. Map `fsi_intendedaudience` through `templates/policy-lookup-tables.yaml`:
   - `Just me` → Zone 3
   - `My team` / `My department` → Zone 2
   - `Anyone in the firm` / `External users` → Zone 1
4. Compute the decision path:
   - `Express` only when all six trigger answers are `No` **and** audience maps to Zone 3
   - `DeferredOutOfScope` when any trigger is `Yes`/`Not sure` or audience maps to Zone 1/2
   - `DefaultDeny` when cross-border data is declared and maker country differs from data residency country without a Privacy override
5. Update the parent `fsi_intakerequest` row:
   - `fsi_decisionpath`
   - `fsi_triggerhitcount`
   - `fsi_risktier` (`Tier 3 (Low)` for Express; `Tier 2 (Medium)` for 1–2 trigger hits; `Tier 1 (High)` for 3+ trigger hits)
   - `fsi_zone`
   - `fsi_status` (`AwaitingSponsor`, `DeferredOutOfScope`, or `Denied`)
   - `fsi_policyversionapplied`
6. Append a `fsi_intakedecisionlog` row using schema-backed columns:
   - `fsi_requestid`
   - `fsi_decisionoutcome` = `AutoApproved` for Express routing eligibility, or `Denied` for default-deny
   - `fsi_risktier`, `fsi_zone`, `fsi_pathused`
   - `fsi_decisionpackjson` = serialized trigger answers, audience, environment, DLP, retention, and policy version
   - `fsi_decisionpackhash` = SHA-256 of `fsi_decisionpackjson`
   - `fsi_decidedon` = `utcNow()`
   - `fsi_retentionlabelapplied` and `fsi_retentionlabelappliedon`
7. Branch:
   - `Express` → trigger Flow 2
   - `DeferredOutOfScope` → notify maker that Standard/Full intake is required in a follow-up release
   - `DefaultDeny` → notify maker and Privacy queue with rationale

**Definition of done:** Insert a smoke-test row with all six triggers = `No` and `fsi_intendedaudience = Just me`; verify `fsi_decisionpath = Express`, `fsi_status = AwaitingSponsor`, and a decision-log entry exists.

## Flow 2 — `fsi-intake-sponsor-card`

**Trigger:** Child-flow or Dataverse trigger when `fsi_status` becomes `AwaitingSponsor`.

**Action:** Microsoft Teams connector — **Post adaptive card and wait for a response**.

- Recipient: `fsi_sponsorupn`
- Adaptive card template: `templates/sponsor-approval-card.json`
- Populate all `${...}` tokens from `fsi_intakerequest` and computed routing fields
- Timeout: `AGENT_INTAKE_SPONSOR_SLA_DAYS`

**Important:** The card uses `Action.Submit` because the Teams Power Automate wait-for-response action returns submitted data directly to the flow. Do not use card-initiated HTTP callbacks in this pattern. If a future bot-based Teams app is introduced, migrate to Universal Actions (`Action.Execute`) with an `Action.Submit` fallback for older Teams clients.

**Response mapping:**

| Card field | Flow variable |
|---|---|
| `data.requestId` | `requestId` |
| `data.decision` | `decision` (`Approved` or `Denied`) |
| `fsi_sponsornotes` | `notes` |
| Teams responder UPN | `sponsorUpn` |

**On timeout:** set `fsi_status = SponsorTimeout`, send a reminder, and escalate according to `sponsor_sla.escalate_to` in `templates/policy-lookup-tables.yaml`.

## Flow 3 — `fsi-intake-handoff`

**Trigger:** Flow 2 returns an `Approved` or `Denied` decision.

**Input payload:**

```json
{
  "requestId": "<fsi_requestid>",
  "decision": "Approved | Denied",
  "notes": "<sponsor notes>",
  "sponsorUpn": "<responder UPN>",
  "renderedCardJson": "<card as sent>"
}
```

**Processing steps:**

1. Validate that `requestId` matches one open `fsi_intakerequest` row with `fsi_status = AwaitingSponsor`.
2. Create a `fsi_intakeapproval` row:
   - `fsi_requestid`
   - `fsi_approverrole = Sponsor`
   - `fsi_approverupn = sponsorUpn`
   - `fsi_decisionoutcome = Approved` or `Denied`
   - `fsi_decidedon = utcNow()`
   - `fsi_decisionmethod = TeamsAdaptiveCard`
   - `fsi_decisioncontexthash` = SHA-256 of `renderedCardJson`
3. Create a `fsi_intakesponsorship` row with the exact attestation text from `templates/policy-lookup-tables.yaml`, `fsi_attestationmethod = TeamsAdaptiveCard`, and `fsi_renderedcardhash`.
4. Append a final `fsi_intakedecisionlog` row with the sponsor decision, notes, evidence hash, and retention label.
5. Branch:
   - `Approved`:
     - Update `fsi_intakerequest.fsi_status = Approved` and `fsi_decidedon = utcNow()`.
     - Call `scripts/setup_entra_agent_id.py` with `--blueprint-id` from `AGENT_INTAKE_AGENT_BLUEPRINT_ID`.
     - Write returned service-principal `id` to `fsi_entraagentid`.
     - Create the shell row in `agent-registry-automation` (or queue handoff if that solution is not deployed).
     - Notify maker and sponsor.
   - `Denied`:
     - Update `fsi_intakerequest.fsi_status = Denied`.
     - Notify maker with sponsor notes.

**Definition of done:** Approving a test request writes rows to `fsi_intakeapproval`, `fsi_intakesponsorship`, and `fsi_intakedecisionlog`, then stamps `fsi_entraagentid` when the Graph create action succeeds.
