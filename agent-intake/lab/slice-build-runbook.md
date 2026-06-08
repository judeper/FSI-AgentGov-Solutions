# Agent-Intake — Vertical-Slice Flow Build Runbook

Follow **this** document to hand-build the slice flows in the Power Automate designer. It is the **lean, lab/slice** version (Option C: the submission helper pre-stamps classification, so the flows orchestrate without re-running the proven classifier). The **canonical, full** customer spec is `agent-intake/docs/flow-configuration.md`; the cross-cutting mechanics are in `agent-intake/AGENTS.md` → "Power Automate flow-build mechanics".

## Build order (child flows first — a parent can't see a child until it's saved **and** turned on)
1. **F8 — `fsi-intake-decision-pack-writer`** ← start here (this doc)
2. F3 — `fsi-intake-sponsor-card`
3. F4 — `fsi-intake-parallel-reviewers`
4. F5 — `fsi-intake-reviewer-decision-handler`
5. F1 — `fsi-intake-router` (the Dataverse-triggered head — last)

## Mechanics that apply to every flow (from the 3-report consensus)
- **Choice columns:** always set the **integer** option value (or an expression that returns one), never the label, or Dataverse silently stores NULL.
- **List rows → one record:** use `first(outputs('List_rows')?['body/value'])`; **guard with `empty(...)`** before using it.
- **Child flows:** trigger = "Manually trigger a flow"; the **Respond to a Power App or flow** action must be the **last** action on **every** branch, or the parent call hangs.
- **After building any flow: Save → Turn on.**

---

## F8 — `fsi-intake-decision-pack-writer` (child flow)

**Purpose:** write the immutable decision-pack row + hash + a `DecisionPackWritten` audit event. Called later by F3/F5.

**Create:** Solutions → **FSI Agent Intake** → **New → Automation → Cloud flow → Instant** → trigger **"Manually trigger a flow"**. Name it `fsi-intake-decision-pack-writer`.
**Trigger inputs** (click *+ Add an input* → **Text** each): `requestId`, `decisionOutcome`, `decisionSource`.

> All Dataverse actions below use the bound **Dataverse - Agent Intake** connection. Tables are shown as **Display name** (`logical entity set`).

### Steps

1. **List rows** → Table **Intake Requests** (`fsi_intakerequests`)
   - **Filter rows:** `fsi_requestid eq '@{triggerBody()?['text']}'`
     > ⚠️ **The value MUST be wrapped in single quotes** — it is a string OData filter. Easiest reliable way: type `fsi_requestid eq '`, then **Add dynamic content → requestId**, then type the closing `'`. Without the surrounding single quotes the filter is invalid and the designer silently will not keep it (the "it doesn't stick" symptom). (`?['text']` is the first Text input; confirm the 3 trigger inputs exist so the token binds.)
   - **Row count:** `1`

2. **Condition** — *not-found guard*
   - Expression: `empty(outputs('List_rows')?['body/value'])`
   - **If yes** → add **Respond to a Power App or flow** returning `decisionPackHash = "not-found"`, then stop. *(Do not use Terminate here — a child flow must reach a **Respond** on every branch, or the parent's "Run a Child Flow" call hangs until timeout.)*
   - **If no** → continue with the steps below.

3. **Compose** — name it `RequestRow`
   - Inputs: `first(outputs('List_rows')?['body/value'])`

4. **Compose** — name it `DecisionPackJson`

   ```json
   {
     "requestId": "@{triggerBody()['text']}",
     "decisionOutcome": "@{triggerBody()['text_1']}",
     "decisionSource": "@{triggerBody()['text_2']}",
     "pathUsed": @{outputs('RequestRow')?['fsi_pathused']},
     "riskTier": @{outputs('RequestRow')?['fsi_risktier']},
     "zone": @{outputs('RequestRow')?['fsi_zone']},
     "decisionPath": "@{outputs('RequestRow')?['fsi_decisionpath']}",
     "mrmRequired": @{outputs('RequestRow')?['fsi_mrmrequired']},
     "maker": "@{outputs('RequestRow')?['fsi_makerupn']}",
     "sponsor": "@{outputs('RequestRow')?['fsi_sponsorupn']}",
     "decidedOnUtc": "@{utcNow()}"
   }
   ```
   *(`text`, `text_1`, `text_2` are the three trigger inputs in order — confirm the tokens via the dynamic-content picker.)*

5. **Compose** — name it `DecisionPackHash`
   - Inputs: `concat('sha256-pending:', guid())`
   - *Slice placeholder — real SHA-256 is deferred (no native flow function; see flow-configuration.md step 4).*

6. **Add a new row** → Table **Decision Logs** (`fsi_intakedecisionlogs`)
   > ⚠️ This table has **11 application-required fields** — Create will fail validation if any are missing. All of the rows below are required (plus the auto `…id`).

   | Field (display) | Value |
   |---|---|
   | **Name** (`fsi_name`) | `@{concat('Decision pack - ', triggerBody()['text'])}` |
   | **Request ID** (`fsi_requestid`) | `@{triggerBody()['text']}` |
   | **Decision Outcome** (`fsi_decisionoutcome`) | `if(equals(triggerBody()['text_1'],'Denied'),100000002,100000000)` *(must return an integer; **verified live in this env**: Approved=100000000, Denied=100000002. If you redeploy to another environment, re-check the `fsi_intake_decisionoutcome` option set in the maker portal — Dataverse can assign different integers.)* |
   | **Risk Tier** (`fsi_risktier`) | `outputs('RequestRow')?['fsi_risktier']` |
   | **Zone** (`fsi_zone`) | `outputs('RequestRow')?['fsi_zone']` |
   | **Path Used** (`fsi_pathused`) | `outputs('RequestRow')?['fsi_pathused']` |
   | **Policy Version Applied** (`fsi_policyversionapplied`) | `coalesce(outputs('RequestRow')?['fsi_policyversionapplied'], '1.0.0')` *(required)* |
   | **Retention Label Applied** (`fsi_retentionlabelapplied`) | `FSI-AgentIntake-7yr` *(required)* |
   | **Retention Label Applied On** (`fsi_retentionlabelappliedon`) | `utcNow()` *(required)* |
   | **Decision Pack JSON** (`fsi_decisionpackjson`) | `string(outputs('DecisionPackJson'))` |
   | **Decision Pack Hash** (`fsi_decisionpackhash`) | `outputs('DecisionPackHash')` |
   | **Decided On** (`fsi_decidedon`) | `utcNow()` |

7. **Update a row** → Table **Intake Requests** (`fsi_intakerequests`)
   - **Row ID:** `outputs('RequestRow')?['fsi_intakerequestid']`
   - **Decided On** (`fsi_decidedon`): `utcNow()`

8. **Add a new row** → Table **Audit Events** (`fsi_intakeauditevents`)
   | Field | Value |
   |---|---|
   | **Name** (`fsi_name`) | `@{concat('DecisionPackWritten - ', triggerBody()['text'])}` |
   | **Request ID** (`fsi_requestid`) | `@{triggerBody()['text']}` |
   | **Event Type** (`fsi_eventtype`) | `DecisionPackWritten` |
   | **Path Phase** (`fsi_pathphase`) | `DecisionPack` |
   | **Actor UPN** (`fsi_actorupn`) | `system` |
   | **Event On** (`fsi_eventon`) | `utcNow()` |

9. **Respond to a Power App or flow** *(must be the LAST action)*
   - Add output **Text** `decisionPackHash` = `outputs('DecisionPackHash')`

**Finish:** **Save → Turn on.**

### Test F8 (after Save + Turn on)
Run **Test → Manually**, supply:
- `requestId` = `3b758bf8-1c28-4f43-8683-55e19fa85f3a`  *(a pre-staged Express row)*
- `decisionOutcome` = `Approved`
- `decisionSource` = `Sponsor`

Then tell the coordinator — it verifies in Dataverse that the `fsi_intakedecisionlog` row and the `DecisionPackWritten` audit event were written with the correct integer choice values (no silent NULLs).

---

## F1 — `fsi-intake-router` ✅ BUILT (programmatic POST-create) + VERIFIED both branches

**Trigger:** Dataverse **When a row is added** on `fsi_intakerequest`, scope **Organization** (`OpenApiConnectionWebhook` / `SubscribeWebhookTrigger`, `subscriptionRequest/message=1`, `scope=4`), with trigger **condition** `@equals(triggerOutputs()?['body/fsi_status'], 100000001)` (Submitted). Change-type **Added** (not Added+Modified) — `New-IntakeSubmission` creates one row per run, so Added fires only on creation and the router's own status Update (a Modify) can't self-retrigger; **no loop guard needed** for the slice.

> Trigger + all action `authentication` use `@parameters('$authentication')` (the Dataverse-triggered-flow form) — **not** the `X-MS-APIM-Tokens` form that F8's manual/Request trigger uses.

1. **Update a row** → **Intake Requests** (`fsi_intakerequests`)
   - **Row ID:** `triggerOutputs()?['body/fsi_intakerequestid']`
   - **Status** (`fsi_status`): `@if(or(equals(toLower(coalesce(triggerOutputs()?['body/fsi_makerupn'],'')), toLower(coalesce(triggerOutputs()?['body/fsi_sponsorupn'],''))), equals(coalesce(triggerOutputs()?['body/fsi_decisionpath'],''),'DefaultDeny')), 100000005, 100000011)` — Denied if sponsor self-approval **or** pre-stamped DefaultDeny, else InReview.
   - **Decision Path** (`fsi_decisionpath`): `@if(equals(toLower(coalesce(triggerOutputs()?['body/fsi_makerupn'],'')), toLower(coalesce(triggerOutputs()?['body/fsi_sponsorupn'],''))), 'DefaultDeny', coalesce(triggerOutputs()?['body/fsi_decisionpath'],''))` — force DefaultDeny on self-approval, else keep the pre-stamped path.

2. **Add a new row** → **Audit Events** (`fsi_intakeauditevents`)
   | Field | Value |
   |---|---|
   | **Name** (`fsi_name`) | `@{concat('RouterDecided - ', triggerOutputs()?['body/fsi_requestid'])}` |
   | **Request ID** (`fsi_requestid`) | `@{triggerOutputs()?['body/fsi_requestid']}` |
   | **Event Type** (`fsi_eventtype`) | `RouterDecided` |
   | **Path Phase** (`fsi_pathphase`) | `Routing` |
   | **Actor UPN** (`fsi_actorupn`) | `system` |
   | **Event On** (`fsi_eventon`) | `utcNow()` |

**Build method (programmatic):** created from scratch via Dataverse Web API **POST `/workflows`** (`category=5`, `type=1`, `primaryentity="none"`, `clientdata`=definition string) with header `MSCRM.SolutionUniqueName: FSIAgentIntake`, then **activated** via PATCH `statecode=1; statuscode=2`. **The activation registered the Dataverse webhook and the trigger fired in <10s** — proving POST-create (not just PATCH-update) works for a Dataverse-triggered flow. `workflowid` `c1a6d6c2-8663-f111-ab0c-7ced8d3b3597` (pinned).

**Verified live (2026-06-08):**
- `express-happy` (maker≠sponsor, decisionpath=`Express`) → status **InReview (100000011)**, decisionpath unchanged, one `RouterDecided` audit. ✅
- `sponsor-self-approval-deny` (maker==sponsor, decisionpath=`DefaultDeny`) → status **Denied (100000005)**, decisionpath `DefaultDeny`, one `RouterDecided` audit. ✅

---

## F3 / F4 / F5
*Added to this runbook as each is built. F3 (sponsor card) next — needs admin's Teams approval to test (lab recipient = `admin@M365CPI57786004`).*
