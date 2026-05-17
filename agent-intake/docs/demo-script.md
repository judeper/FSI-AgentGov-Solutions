# Demo script — agent-intake customer architecture walkthrough

## 1. Audience & format

**Audience:** Customer architects, governance leads, InfoSec, Compliance, Privacy, and platform owners.

**Format:** One 20-25 minute live walkthrough in a working lab tenant.

**Goal:** Show that `agent-intake` can route low-risk requests quickly, force richer review when risk increases, preserve a defensible denial path, and hand approved requests into downstream governance with a retained decision pack.

### Demo timing at a glance

| Scene | Topic | Target time |
|---|---|---:|
| 1 | Express happy path | 3 min |
| 2 | Standard with conditions | 5 min |
| 3 | Full board + MRM handoff | 8 min |
| 4 | Default-deny and appeal | 2 min |
| 5 | Teardown | 1 min |
| Q&A | Expected questions | 5-6 min |

## 2. Pre-demo checklist

Run this list 5-10 minutes before the session.

- `deploy.ps1 -SeedTestData` already completed in the demo tenant
- `smoke_test.ps1 -IncludeSeededDataChecks -PathScope All` is green
- you know the demo environment URL, maker portal URL, and reviewer app URL
- Teams is open for the sponsor account and at least one reviewer account
- the operator has one browser for the maker portal and one for admin/reviewer surfaces
- the stage log from the deploy run is easy to reach in case someone asks about the build steps
- a wall clock or on-screen timer is visible so the story stays inside 25 minutes

### Demo data used in this script

The seeded lab fixtures are in `scripts/seed-test-data\`:

- `request-express-happy.json`
- `request-standard-conditional.json`
- `request-full-parallel-board.json`
- `request-cross-border-deny.json`

> **Operator note for Scene 3:** the stock Full fixture demonstrates the Full board, MNPI, quorum, MRM handoff, Agent ID mint, and drift handoff. If you also want an **approved cross-border** Full example in the same scene, prepare a lab copy of that fixture with the Privacy override recorded before the demo. If you do not prepare that variant, keep Scene 3 focused on the Full/MNPI/MRM path and use Scene 4 for the explicit cross-border deny.

## 3. Scene 1 (3 min): Express happy path

**Fixture:** `request-express-happy.json`

### Operator actions

1. Open the maker portal.
2. Either enter the values from `request-express-happy.json` live or open the already seeded request row and explain that it mirrors the same data.
3. Call out the important inputs:
   - audience = `Just me`
   - T1-T6 = `No`
   - data residency = same country as maker
4. Submit the request.
5. Switch to the sponsor Teams session.
6. Show the sponsor card and click **Approve**.
7. Switch to the admin or reviewer app view and show:
   - the decision-log row
   - the approved request row
   - the Microsoft Entra Agent ID field once the handoff completes

### What to say

- “This is the lowest-friction lane: one maker, one sponsor, and all six routing triggers are clean.”
- “The card is not the only evidence. The real audit artifact is the decision pack written behind the scenes.”
- “This is the path that helps the customer avoid sending every low-risk personal request through the full committee.”

### What the audience should see

- the baseline form fields
- an immediate route to Express
- a Teams sponsor card with request facts and attestation text
- approval recorded without opening a separate workbench
- a decision-pack row and Microsoft Entra Agent ID soon after approval

### Regulator outcome demonstrated

- proportional supervision under FINRA Rule 3110
- books-and-records support under FINRA Rule 4511(a), SEC Rules 17a-3(a)(17) and 17a-4(f), and CFTC Rule 1.31
- retained business sponsor accountability without overburdening low-risk requests

## 4. Scene 2 (5 min): Standard with conditions

**Fixture:** `request-standard-conditional.json`

### Operator actions

1. Submit the Standard scenario live or open the seeded request row.
2. Call out the routing signals:
   - audience = `My team`
   - NPI trigger = `Yes`
   - expected path = `Standard`
3. Open the reviewer Teams card or the reviewer app queue.
4. Show the Standard board composition and due dates.
5. Open the InfoSec decision and record **Approve with conditions**.
6. Show the condition text from the seeded plan: “Quarterly access review required before widening beyond the named sales-operations team.”
7. Show the Privacy and Compliance approvals.
8. Refresh the request and show that quorum is met and the decision pack is written.

### What to say

- “Standard is where the customer starts seeing policy-driven parallel review without jumping straight to the full enterprise board.”
- “The important thing here is not only that reviewers approve. It is that they can attach conditions that become part of the retained evidence.”
- “This is the right shape for a team-scale use case that touches customer data but stays inside a bounded internal audience.”

### What the audience should see

- reviewer cards arrive in parallel
- the reviewer app shows role-based queues
- one reviewer approves with conditions and the other two approve cleanly
- the request reaches quorum and the condition text is preserved in the decision evidence

### Regulator outcome demonstrated

- supervisory evidence beyond sponsor-only approval for FINRA Rule 3110
- recordkeeping support under FINRA Rule 4511(a), SEC Rule 17a-4(f), and CFTC Rule 1.31
- privacy and safeguard review aligned to GLBA Section 501(b)

## 5. Scene 3 (8 min): Full with MNPI + MRM handoff

**Fixture:** `request-full-parallel-board.json` (or a prepared Privacy-approved cross-border variant of it)

### Operator actions

1. Open the Full scenario.
2. Point to the high-risk routing facts:
   - audience = `Anyone in the firm`
   - financial-action trigger = `Yes`
   - customer-facing trigger = `Yes`
   - NPI trigger = `Yes`
   - MNPI trigger = `Yes`
   - Tier = `Tier 1 (High)`
3. Open the reviewer board and show all five roles: InfoSec, Privacy, Compliance, Legal, and MRM.
4. Walk through the reviewer queue or card summary for each role.
5. Apply the seeded decision pattern from `reviewer-decisions-full-board.json`:
   - InfoSec = Approved
   - Privacy = Approved
   - Compliance = Approved
   - Legal = Recused
   - MRM = Recused or remains queue-ready depending on your lab setup
6. Refresh the request and show that the 3-of-5 quorum is achieved.
7. Show that the request remains in review long enough to fire the MRM handoff logic.
8. Open the MRM payload or target record and show the queue-ready row in `fsi_modelinventory` if the downstream solution is present.
9. Refresh again and show:
   - decision pack written
   - Microsoft Entra Agent ID minted
   - registry handoff complete
   - drift handoff submitted

### What to say

- “Full is not just a bigger form. It is a different governance posture.”
- “Three approvals can satisfy the board quorum, but Tier-1 MRM handling still has to be addressed before the case is truly complete.”
- “This is how the intake record becomes the baseline for registry, MRM, and drift monitoring instead of dying in a ticket queue.”

### What the audience should see

- a five-role parallel board
- the request status changing as quorum is reached
- a decision pack that contains reviewer attestations
- an MRM handoff payload or queue row
- Agent ID minting and drift handoff after approval processing finishes

### Regulator outcome demonstrated

- richer books-and-records support under FINRA Rule 4511(a) and SEC Rule 17a-4(f)
- supervisory and reviewer evidence for FINRA Rule 3110 and FINRA 25-07-style governance expectations
- model-risk governance language many firms map to OCC Bulletin 2011-12 and Federal Reserve SR 11-7
- retained path into downstream MRM and drift tooling

## 6. Scene 4 (2 min): Default-deny

**Fixture:** `request-cross-border-deny.json`

### Operator actions

1. Open the deny scenario.
2. Point to the important facts:
   - audience = `My team`
   - cross-border trigger = `Yes`
   - maker country and declared data-residency country do not match
   - no Privacy override is present
3. Submit or open the seeded request row.
4. Show the request going to `DefaultDeny` without reviewer fan-out.
5. Open the denial card or appeal action payload and show how the maker would resubmit.

### What to say

- “A good governance tool has to say no cleanly, not only approve cleanly.”
- “The denial is immediate, explainable, and still gives the maker a structured appeal path.”
- “This is the default-deny rule from ADR-005 doing exactly what it was designed to do.”

### What the audience should see

- denial without committee delay
- a clear routing reason tied to cross-border handling
- preserved lineage for the appeal workflow

### Regulator outcome demonstrated

- conservative privacy and data-residency posture
- explainable denial basis that can be retained and later reviewed
- customer control over whether Privacy can override the default through policy

## 7. Scene 5 (1 min): Teardown

### Operator actions

1. Open a PowerShell session in `agent-intake\scripts`.
2. Run:

```powershell
pwsh .\deploy.ps1 -EnvironmentUrl https://<your-env>.crm.dynamics.com -Teardown
```

3. Read the teardown summary out loud.

### What to say

- “This is a lab-friendly solution. We can rebuild quickly because the deployment is idempotent and teardown is scripted.”
- “The teardown is intentionally conservative: shared Purview labels, shared Agent ID blueprints, and some classic Power Pages artifacts may remain for manual review.”

### What the audience should see

- teardown summary rows for the solution footprint
- an operator experience that supports rapid lab reset

### Regulator outcome demonstrated

- controlled rebuild capability for pilot environments
- explicit manual-follow-up items instead of silent leftovers

## 8. Q&A guidance

Use these answers as short, repeatable responses.

| Expected question | Suggested answer |
|---|---|
| **1. What if our tenant does not have Microsoft Entra Agent ID enabled yet?** | The readiness check warns, deployment can still continue, and the identity handoff completes once the tenant flag and permissions are available. |
| **2. Why do you not ship exported Power Automate flows?** | The repo policy intentionally avoids brittle runtime artifacts. Customers build the 12 flows from `flow-configuration.md` so connection references, approvals, and tenant bindings stay under customer control. |
| **3. Can we change quorum?** | Yes. Update `templates/policy-lookup-tables.yaml > quorum`, rerun policy hydration, and retest the reviewer path. |
| **4. Can Legal approve with conditions?** | The shipped policy sets Legal `conditional_approval_allowed` to `false`, but the customer can change that policy if their governance model supports it. |
| **5. What happens if a sponsor or reviewer ignores the card?** | Sponsor and reviewer SLAs are policy-driven. The shipped defaults use reminder and escalation paths, and overdue cases are visible in the reviewer workflow. |
| **6. Can we add another reviewer role?** | Yes. Extend the reviewer role choice set, security role, app views, card attestation text, and reviewer-routing policy together. |
| **7. Where is the retained record?** | In the decision pack and audit tables, with retention tagging aligned to the Purview label strategy. |
| **8. How does drift monitoring know what changed later?** | The registry and drift handoff carry the approved audience, data sources, sponsor, reviewer attestation chain, and Agent ID so peer solutions can compare runtime behavior to the approved baseline. |
| **9. Does Full always mean formal MRM?** | The shipped Tier-1 Full path includes MRM handoff logic. Customers can tailor the routing target, but the demo shows the stricter default because that is the safer preview posture. |
| **10. Can we localize or change the wording later?** | Yes. The customer can change card wording, SLAs, and policy values, but the payload keys and routing contract should stay stable so downstream flows and evidence remain consistent. |

## 9. Closing line for the operator

End with this sentence:

> “What you saw today is not only an intake form. It is a repeatable governance chain: maker input, sponsor accountability, reviewer evidence where needed, retained decision records, and downstream monitoring after approval.”
