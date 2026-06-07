# Power Automate flow configuration — Express, Standard, and Full paths

The repository intentionally does **not** ship exported Power Automate flow JSON. Build these flows manually inside the `FSIAgentIntake` unmanaged solution so each customer can bind the connection references, environment variables, Teams targets, and approval surfaces to its tenant.

Use Dataverse **logical names** in every OData filter, trigger condition, expression, and JSON payload. The schema name `fsi_RequestId` is referenced as `fsi_requestid`; Dataverse does **not** insert extra underscores between words.

## Read this first

- [Flow build prerequisites](./flow-build-prerequisites.md)
- [Classification rules](./classification-rules.md)
- [Maker form progressive disclosure](./maker-form-progressive-disclosure.md)
- [Portal configuration](./portal-configuration.md)
- [MRM integration](./mrm-integration.md)
- [Drift-detection integration](./drift-detection-integration.md)
- [Identity and records automation](./identity-records-automation.md)
- [Reviewer app build guide](./reviewer-app-build.md)

## Shared implementation notes

- Build every flow inside the **FSI Agent Intake** unmanaged solution created by `scripts/provision_solution_shell.ps1`.
- Every **Add a new row** step below sets `fsi_name` to a deterministic value such as `RouterDecided - <requestId>` because Dataverse still requires the primary name attribute even when the schema script lists only the custom columns.
- The current schema stores reviewer-board state on `fsi_intakerequest.fsi_parallelreviewersjson`; there is no dedicated reviewer-assignment table in v1.0.0-preview.
- `fsi_intakereview` stores the reviewer decision in `fsi_reviewoutcome`, not `fsi_reviewdecision`.
- `fsi_appealofid` stores the original request ID when Flow 11 creates an appealed intake request.
- Sponsor self-approval prevention is enforced in two places: the Power Pages submit experience blocks it before submission, and Flow 1 re-checks it defensively so imports or replayed events cannot bypass the rule.
- Keep the routing logic in Flow 1 and Flow 2 aligned with [`classification-rules.md`](./classification-rules.md) and `templates/policy-lookup-tables.yaml`. If you externalize the classifier behind HTTP or a custom connector, both flows should still consume the same request and response contract.

## Choice values used in trigger conditions

| Choice set | Label | Value |
|---|---|---:|
| `fsi_intake_pathused` | Express | `100000000` |
| `fsi_intake_pathused` | Standard | `100000001` |
| `fsi_intake_pathused` | Full | `100000002` |
| `fsi_intake_status` | Submitted | `100000001` |
| `fsi_intake_status` | AwaitingSponsor | `100000002` |
| `fsi_intake_status` | AwaitingReviewers | `100000003` |
| `fsi_intake_status` | Approved | `100000004` |
| `fsi_intake_status` | Denied | `100000005` |
| `fsi_intake_status` | Escalated | `100000007` |
| `fsi_intake_status` | SponsorTimeout | `100000010` |
| `fsi_intake_status` | InReview | `100000011` |
| `fsi_intake_status` | LiveTracking | `100000012` |
| `fsi_intake_reviewdecision` | Pending | `100000000` |
| `fsi_intake_reviewdecision` | Approved | `100000001` |
| `fsi_intake_reviewdecision` | Approved with conditions | `100000002` |
| `fsi_intake_reviewdecision` | Denied | `100000003` |
| `fsi_intake_reviewdecision` | Recused | `100000004` |
| `fsi_intake_reviewdecision` | Timeout | `100000005` |
| `fsi_intake_mrmhandoffstatus` | Pending | `100000000` |
| `fsi_intake_mrmhandoffstatus` | Handed off | `100000001` |
| `fsi_intake_mrmhandoffstatus` | NotApplicable | `100000002` |
| `fsi_intake_mrmhandoffstatus` | Failed | `100000003` |

> **Reviewer decision column.** The `fsi_intake_reviewdecision` option set above is bound to the **`fsi_reviewoutcome`** column on `fsi_intakereview` (there is no column named `fsi_reviewdecision`). Use `fsi_reviewoutcome` in OData filters and flow expressions — for example `$filter=fsi_reviewoutcome eq 100000001`.

## Logical build order

1. `fsi-intake-presubmit-classifier`
2. `fsi-intake-router`
3. `fsi-intake-sponsor-card`
4. `fsi-intake-parallel-reviewers`
5. `fsi-intake-reviewer-decision-handler`
6. `fsi-intake-mrm-handoff`
7. `fsi-intake-decision-pack-writer`
8. `fsi-intake-registry-handoff`
9. `fsi-intake-drift-handoff`
10. `fsi-intake-denial-appeal`
11. `fsi-intake-escalation`
12. `fsi-intake-retention-tagger`

---

### Flow 1: `fsi-intake-router`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Microsoft Dataverse connector — **When a row is added, modified or deleted**. Configure **Change type = Added and Modified**, **Table name = Intake Requests (`fsi_intakerequests`)**, and **Scope = Organization**. Guard the trigger with `fsi_status = Submitted (100000001)` and a blank or stale `fsi_decisionpath` so replays do not fan out duplicate reviewer work.

**Path scope.** All.

**Inputs.** `fsi_intakerequest` row with the baseline maker fields, `fsi_standardfullquestionsjson`, `fsi_declareddatasourcesjson`, and the policy defaults from `templates/policy-lookup-tables.yaml`.

**Outputs.** `fsi_pathused`, `fsi_decisionpath`, `fsi_risktier`, `fsi_zone`, `fsi_quorumrequired`, `fsi_parallelreviewersjson`, `fsi_mrmrequired`, `fsi_mrmhandoffstatus`, `fsi_triggerhitcount`, and an updated request status (`InReview` for routed requests or `Denied` for default-deny outcomes).

**Steps.**

1. Trigger: Microsoft Dataverse — **When a row is added, modified or deleted**.
   - In the trigger card, set **Change type = Added and Modified**, **Table = Intake Requests**, **Scope = Organization**.
   - Note: the router should run only after the maker has moved the request to `Submitted`; keep drafts out of the reviewer queue.
2. Action: Microsoft Dataverse — **Get a row by ID**.
   - Read the full `fsi_intakerequest` row so the flow has `fsi_requestid`, the T1-T6 answers, `fsi_intendedaudience`, `fsi_makerupn`, `fsi_sponsorupn`, `fsi_makercountry`, `fsi_dataresidencycountry`, `fsi_privacyoverride`, and the Standard/Full JSON blob.
3. Action: HTTP with Microsoft Entra ID connector — **HTTP**.
   - Method: `POST`
   - URI: the classifier endpoint that implements Flow 2's contract (either the Flow 2 request URL stored in your secured configuration or an HTTP/custom-connector wrapper that both Flow 1 and Power Pages call).
   - Body:

   ```json
   {
     "requestId": "@{outputs('Get_a_row_by_ID')?['body/fsi_requestid']}",
     "recordId": "@{outputs('Get_a_row_by_ID')?['body/fsi_intakerequestid']}",
     "draft": {
       "fsi_agentdisplayname": "@{outputs('Get_a_row_by_ID')?['body/fsi_agentdisplayname']}",
       "fsi_businessoutcome": "@{outputs('Get_a_row_by_ID')?['body/fsi_businessoutcome']}",
       "fsi_businessjustification": "@{outputs('Get_a_row_by_ID')?['body/fsi_businessjustification']}",
       "fsi_agenttype": "@{outputs('Get_a_row_by_ID')?['body/fsi_agenttype@OData.Community.Display.V1.FormattedValue']}",
       "fsi_intendedaudience": "@{outputs('Get_a_row_by_ID')?['body/fsi_intendedaudience']}",
       "fsi_t1initiatesfinancialtxn": "@{outputs('Get_a_row_by_ID')?['body/fsi_t1initiatesfinancialtxn']}",
       "fsi_t2customerfacing": "@{outputs('Get_a_row_by_ID')?['body/fsi_t2customerfacing']}",
       "fsi_t3autonomousunmonitored": "@{outputs('Get_a_row_by_ID')?['body/fsi_t3autonomousunmonitored']}",
       "fsi_t4handlesnpi": "@{outputs('Get_a_row_by_ID')?['body/fsi_t4handlesnpi']}",
       "fsi_t5handlesmnpi": "@{outputs('Get_a_row_by_ID')?['body/fsi_t5handlesmnpi']}",
       "fsi_t6crossborderdata": "@{outputs('Get_a_row_by_ID')?['body/fsi_t6crossborderdata']}",
       "fsi_makerupn": "@{outputs('Get_a_row_by_ID')?['body/fsi_makerupn']}",
       "fsi_sponsorupn": "@{outputs('Get_a_row_by_ID')?['body/fsi_sponsorupn']}",
       "fsi_makercountry": "@{outputs('Get_a_row_by_ID')?['body/fsi_makercountry']}",
       "fsi_dataresidencycountry": "@{outputs('Get_a_row_by_ID')?['body/fsi_dataresidencycountry']}",
       "fsi_privacyoverride": "@{outputs('Get_a_row_by_ID')?['body/fsi_privacyoverride']}"
     }
   }
   ```

   - Note: if the tenant does not want a shared HTTP endpoint, inline the exact Flow 2 decision logic in `Compose`, `Condition`, and `Switch` actions and keep the returned contract identical.
4. Branch: **Condition**.
   - If `tolower(fsi_makerupn) = tolower(fsi_sponsorupn)`, override the classifier result to `decisionPath = DefaultDeny` and set `routingReason = sponsor_self_approval`.
   - If the classifier already returned `decisionPath = DefaultDeny` because of unresolved cross-border routing, keep that result and preserve the returned `routingReason`.
5. Action: Microsoft Dataverse — **Update a row**.
   - Write back `fsi_pathused`, `fsi_decisionpath`, `fsi_risktier`, `fsi_zone`, `fsi_quorumrequired`, `fsi_parallelreviewersjson`, `fsi_mrmrequired`, `fsi_mrmhandoffstatus`, `fsi_triggerhitcount`, `fsi_submittedon`, and `fsi_policyversionapplied`.
   - Set `fsi_status = InReview (100000011)` when `fsi_decisionpath <> DefaultDeny`, keep `fsi_pathused` as the downstream branch key, and set `fsi_status = Denied (100000005)` when `fsi_decisionpath = DefaultDeny`.
   - If the implementation also writes `fsi_intakerisksignal` rows, do it in the same scope so each T1-T6 answer is captured before reviewers receive a card.
6. Audit event: Microsoft Dataverse — **Add a new row** to `fsi_intakeauditevent` with:
   - `fsi_name = RouterDecided - @{outputs('Get_a_row_by_ID')?['body/fsi_requestid']}`
   - `fsi_requestid = @{outputs('Get_a_row_by_ID')?['body/fsi_requestid']}`
   - `fsi_eventtype = RouterDecided`
   - `fsi_pathphase = Routing`
   - `fsi_actorupn = system`
   - `fsi_eventpayloadjson` containing the classifier response, `routingReason`, and the schema-compatible status value that was written.

**Failure handling.** Wrap the HTTP call and row update in a `Try/Catch`-style scope. On failure, write `RouterFailed` to `fsi_intakeauditevent`, keep the request out of reviewer fan-out, and route the exception to the governance-admin mailbox instead of partially updating the row.

**SLA / timing.** Start within one minute of submission and complete before reviewer or sponsor notifications begin.

**Per-customer override.** Audience mapping, quorum, reviewer boards, and default-deny behavior come from [`classification-rules.md`](./classification-rules.md) and `templates/policy-lookup-tables.yaml`. Keep the flow contract stable even if a customer changes the reviewer board.

---

### Flow 2: `fsi-intake-presubmit-classifier`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Request connector — **When an HTTP request is received**.

**Path scope.** All.

**Inputs.** Power Pages Step 1 draft payload, or the pair `requestId` + `recordId` so the flow can read the draft row from Dataverse without writing to it.

**Outputs.** HTTP `200` response with `pathUsed`, `decisionPath`, `reviewerRoles`, `quorumRequired`, `parallelReviewers`, `mrmRequired`, `mrmHandoffStatus`, `triggerHitCount`, and the routing banner text used by the maker form.

**Steps.**

1. Trigger: Request — **When an HTTP request is received**.
   - Paste the request schema that matches the Step 1 payload. Start from the shape documented in [`maker-form-progressive-disclosure.md`](./maker-form-progressive-disclosure.md).
2. Branch: **Condition**.
   - If `triggerBody()?['draft']` is present, use it directly.
   - Otherwise call Microsoft Dataverse — **Get a row by ID** on `fsi_intakerequest` using `recordId` and compose the same normalized draft object that Flow 1 posts.
3. Action: **Compose** / **Condition** / **Switch**.
   - Treat `Yes` and `Not sure` as positive trigger hits.
   - Map `fsi_intendedaudience` to zone using `audience_to_zone` from `templates/policy-lookup-tables.yaml`.
   - Compute `pathUsed`, `decisionPath`, `triggerHitCount`, `reviewerRoles`, `parallelReviewers`, `quorumRequired`, `mrmRequired`, and `mrmHandoffStatus` using the rules in [`classification-rules.md`](./classification-rules.md).
   - Keep the sponsor self-approval and cross-border deny gates in the stateless classifier response even though Flow 1 also re-checks them.
4. Action: **Response**.
   - Status code: `200`
   - Body:

   ```json
   {
     "pathUsed": "Standard",
     "decisionPath": "Standard",
     "triggerHitCount": 2,
     "zone": "Zone 2 (Team)",
     "riskTier": "Tier 2 (Medium)",
     "quorumRequired": 2,
     "reviewerRoles": ["InfoSec", "Privacy", "Compliance"],
     "parallelReviewers": [
       {
         "role": "InfoSec",
         "upn": "infosec-agent-review@contoso.com",
         "slaDays": 5,
         "quorumWeight": 1
       },
       {
         "role": "Privacy",
         "upn": "privacy@contoso.com",
         "slaDays": 5,
         "quorumWeight": 1
       }
     ],
     "mrmRequired": false,
     "mrmHandoffStatus": "NotApplicable",
     "routingBanner": "This request needs review by InfoSec, Privacy, and Compliance. Expected response within 5 business days."
   }
   ```

5. Audit event: none. This flow is intentionally stateless and writes nothing.

**Failure handling.** Return `400` when a required field is missing, `422` when the payload contains an unsupported audience or malformed trigger answer, and `500` only for unexpected runtime failures. Do not create or update Dataverse rows from this flow.

**SLA / timing.** Return the routing decision synchronously in under five seconds so the Power Pages multistep form can gate the Standard and Full steps without a manual refresh loop.

**Per-customer override.** Keep the response shape stable. Customers can change reviewer targets, SLA days, or quorum thresholds, but the HTTP response keys should stay the same so the maker form does not need a tenant-specific JavaScript fork.

---

### Flow 3: `fsi-intake-sponsor-card`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Microsoft Dataverse connector — **When a row is added, modified or deleted** on `fsi_intakerequest` where `fsi_pathused = Express (100000000)` and `fsi_status = InReview (100000011)`.

**Path scope.** Express.

**Inputs.** Express-path request row, `templates/sponsor-approval-card.json`, sponsor UPN, and the backup group in `fsi_intake_sponsorbackupgroup` when a timeout or escalation path is needed.

**Outputs.** `fsi_intakeapproval` row, `fsi_intakesponsorship` row, request status update, optional denial notification card, and `SponsorDecided` or timeout audit events.

**Steps.**

1. Trigger: Microsoft Dataverse — **When a row is added, modified or deleted**.
   - Set **Change type = Added and Modified**, **Table = Intake Requests**, and guard on `fsi_pathused = Express` plus `fsi_status = InReview`.
2. Action: Microsoft Dataverse — **Get a row by ID**.
   - Pull the Express request row, including `fsi_requestid`, `fsi_agentdisplayname`, `fsi_makerdisplayname`, `fsi_makerupn`, `fsi_intendedaudience`, `fsi_submittedon`, `fsi_risktier`, `fsi_zone`, `fsi_sponsorupn`, and `fsi_businessjustification`.
3. Action: Microsoft Teams — **Post adaptive card and wait for a response**.
   - Recipient: `fsi_sponsorupn`
   - Card template: `templates/sponsor-approval-card.json`
   - Map the `${...}` tokens directly from the request row.
   - Timeout: use the sponsor SLA from `templates/policy-lookup-tables.yaml` and the backup target from `fsi_intake_sponsorbackupgroup`.
4. Action: Microsoft Dataverse — **Add a new row** to `fsi_intakeapproval`.
   - Set `fsi_name = Sponsor approval - <requestId>`.
   - Set `fsi_requestid`, `fsi_approverrole = Sponsor`, `fsi_approverupn`, `fsi_decisionoutcome`, `fsi_decidedon`, `fsi_decisionmethod = TeamsAdaptiveCard`, and `fsi_decisioncontexthash = sha256(rendered sponsor card JSON)`.
   - Note: Teams does not provide a durable client IP in this pattern, so leave `fsi_clientipaddress` blank unless your tenant wraps the response in a gateway that records it.
5. Action: Microsoft Dataverse — **Add a new row** to `fsi_intakesponsorship`.
   - Set `fsi_name = Sponsor attestation - <requestId>`.
   - Set `fsi_requestid`, `fsi_sponsorupn`, `fsi_sponsorrole = LineOfBusinessSponsor`, `fsi_attestationtext` from `templates/policy-lookup-tables.yaml.sponsor_attestation.card_text`, `fsi_attestedon`, `fsi_attestationmethod = TeamsAdaptiveCard`, and `fsi_renderedcardhash`.
6. Branch: **Condition**.
   - **Approved**: run Flow 8 (`fsi-intake-decision-pack-writer`) as a child flow, then update `fsi_intakerequest.fsi_status = Approved (100000004)` and `fsi_decidedon = utcNow()`.
   - **Denied**: run Flow 8 with `decisionOutcome = Denied`, update `fsi_intakerequest.fsi_status = Denied (100000005)`, and post the maker denial card that includes the `Appeal` action payload used by Flow 11.
   - **Timeout**: update `fsi_status = SponsorTimeout (100000010)` or `Escalated (100000007)` per customer policy, then notify `fsi_intake_sponsorbackupgroup`.
7. Audit event: Microsoft Dataverse — **Add a new row** to `fsi_intakeauditevent` with `fsi_pathphase = SponsorAttestation` and `fsi_eventtype = SponsorDecided` for approve/deny or `SponsorTimeout` / `SponsorEscalated` for the timeout branch.

**Failure handling.** If the Teams wait action fails after the approval row was created, terminate the run and log `SponsorCardFailed` in `fsi_intakeauditevent` so an operator can replay the step safely. Do not mint the decision pack or advance the request until the sponsor outcome is persisted.

**SLA / timing.** Deliver the card immediately after routing. The default bundled policy is three days to respond, with escalation after the configured threshold.

**Per-customer override.** Customers can replace the Teams card with Outlook or a custom supervisor workbench, but Express should still keep a single sponsor approval as the only reviewer evidence path.

---

### Flow 4: `fsi-intake-parallel-reviewers`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Microsoft Dataverse connector — **When a row is added, modified or deleted** on `fsi_intakerequest` where `fsi_pathused in {Standard, Full}` and `fsi_status = InReview (100000011)`.

**Path scope.** Standard / Full.

**Inputs.** `fsi_parallelreviewersjson`, `templates/reviewer-notification-card.json`, `fsi_intake_reviewerappurl`, and the reviewer-routing defaults from `templates/policy-lookup-tables.yaml`.

**Outputs.** One `fsi_intakereview` row per routed reviewer, Teams reviewer card delivery, Outlook reminder, and `ReviewerQueued` audit events.

**Steps.**

1. Trigger: Microsoft Dataverse — **When a row is added, modified or deleted**.
   - Guard on `fsi_pathused = Standard or Full`, `fsi_status = InReview`, and non-empty `fsi_parallelreviewersjson`.
2. Action: Microsoft Dataverse — **Get a row by ID**.
   - Pull the request row and parse `fsi_parallelreviewersjson` into an array shaped like:

   ```json
   [
     {
       "role": "InfoSec",
       "upn": "infosec-agent-review@contoso.com",
       "slaDays": 5,
       "quorumWeight": 1
     }
   ]
   ```

3. Branch: **Apply to each** reviewer.
   - Action: Microsoft Dataverse — **Add a new row** to `fsi_intakereview`.
   - Populate `fsi_name = <role> - <requestId>`, `fsi_requestid`, `fsi_reviewerrole`, `fsi_reviewerupn`, `fsi_reviewtype = Standard or Full`, `fsi_reviewoutcome = Pending (100000000)`, `fsi_quorumweight`, `fsi_dueon = addDays(utcNow(), slaDays)`, and `fsi_startedon = utcNow()`.
   - Note: if the reviewer app uses **My open reviews**, assign ownership of the row to the reviewer or a reviewer team at creation time.
4. Action: Microsoft Teams — **Post adaptive card in a chat or channel**.
   - Use `templates/reviewer-notification-card.json`.
   - Populate the two card-template placeholders (neither is a Dataverse column): set `${fsi_reviewerattestation}` from the `fsiRoleAttestationCatalog` keyed by reviewer role inside `templates/reviewer-notification-card.json`, and set `${fsi_reviewerappurl}` from the environment variable `fsi_intake_reviewerappurl`.
   - Note: keep the action payload fields `requestId`, `reviewId`, and `reviewerRole` unchanged because Flow 5 uses them as its correlation keys.
5. Action: Office 365 Outlook — **Create event (V4)** or **Send an email (V2)**.
   - Create a reviewer reminder that ends on `fsi_dueon` and includes the request ID, agent display name, and reviewer-app deep link.
6. Audit event: Microsoft Dataverse — **Add a new row** to `fsi_intakeauditevent` with `fsi_pathphase = ReviewerQueued` and `fsi_eventtype = ReviewerQueued` for each reviewer row created.

**Failure handling.** Use a `Try/Catch` scope inside the `Apply to each`. If one reviewer row fails, log a `ReviewerQueueFailed` event for that reviewer and continue the remaining fan-out so the board is only partially degraded instead of fully blocked.

**SLA / timing.** Run immediately after routing and complete the full reviewer fan-out in a single pass.

**Per-customer override.** Reviewer roles, SLA days, weights, and escalation contacts come from `templates/policy-lookup-tables.yaml`. The reviewer card text can be customized, but the payload keys should stay unchanged.

---

### Flow 5: `fsi-intake-reviewer-decision-handler`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Microsoft Teams connector — **When someone responds to an adaptive card** where `data.action = reviewerDecision`.

**Path scope.** Standard / Full.

**Inputs.** `requestId`, `reviewId`, `reviewerRole`, `decision`, `fsi_conditionstext`, `fsi_reviewnotes`, and the current state of all `fsi_intakereview` rows for the same request.

**Outputs.** Updated `fsi_intakereview` row, optional `fsi_intakeapproval` evidence row, request status and `fsi_nonmrmquorummet` transitions, Flow 8 hand-off when decisions are final, and reviewer/quorum audit events.

**Steps.**

1. Trigger: Microsoft Teams — **When someone responds to an adaptive card**.
   - Filter the trigger to reviewer cards by checking `triggerBody()?['data']?['action'] = reviewerDecision`.
2. Action: Microsoft Dataverse — **Get a row by ID** on `fsi_intakereview` and **Get a row by ID** on `fsi_intakerequest`.
   - Use `reviewId` for the review row.
   - Pull the request row so the flow can read `fsi_quorumrequired`, `fsi_pathused`, `fsi_mrmrequired`, `fsi_nonmrmquorummet`, and `fsi_parallelreviewersjson`.
3. Action: Microsoft Dataverse — **Update a row** on `fsi_intakereview`.
   - Set `fsi_reviewoutcome` to `Approved`, `Approved with conditions`, `Denied`, or `Recused`.
   - Set `fsi_conditionstext` when the card submits conditions.
   - Set `fsi_reviewnotes` and `fsi_completedon = utcNow()`.
4. Action: Microsoft Dataverse — **Add a new row** to `fsi_intakeapproval` (optional but recommended for a single per-approver evidence surface).
   - Set `fsi_name = Reviewer approval - <reviewId>`.
   - Set `fsi_requestid`, `fsi_approverrole`, `fsi_approverupn`, `fsi_decidedon`, and `fsi_decisionmethod = TeamsAdaptiveCard`.
   - If the reviewer chose `Approved with conditions`, store `fsi_decisionoutcome = Approved` on `fsi_intakeapproval` and keep the actual conditional nuance in `fsi_intakereview.fsi_reviewoutcome` plus `fsi_conditionstext`.
5. Action: Microsoft Dataverse — **List rows** on `fsi_intakereviews` filtered by `fsi_requestid`.
   - Recompute quorum using the current review board state:
     - read all `fsi_intakereview` rows for the request
     - filter to rows where `fsi_reviewoutcome in {Approved, Approved with conditions, Denied, Recused}`
     - compute weighted approvals as the sum of `fsi_quorumweight` for rows with `Approved` or `Approved with conditions`
     - compare that total to `fsi_intakerequest.fsi_quorumrequired`
     - if any reviewer row is `Denied`, deny the request immediately with no override
     - recusals do not count for or against approval; if the remaining available reviewers can no longer satisfy quorum, escalate the request
6. Branch: **Condition**.
   - **Any deny**: update `fsi_intakerequest.fsi_status = Denied (100000005)`, run Flow 8 with `decisionOutcome = Denied`, and send the maker denial card with the `Appeal` button that Flow 11 listens for.
   - **Recusal makes quorum impossible**: update `fsi_status = Escalated (100000007)` and notify the governance lead or escalation target from policy.
   - **Quorum met and `fsi_pathused = Full` and `fsi_mrmrequired = true` and the MRM review is not yet complete**: update `fsi_intakerequest.fsi_nonmrmquorummet = true`, leave `fsi_status = InReview (100000011)`, and let Flow 7 trigger on the request update.
   - **Quorum met and no MRM wait remains**: call Flow 8.
   - **Quorum not yet met**: leave `fsi_status = InReview (100000011)` and `fsi_nonmrmquorummet = false`.
7. Audit event: Microsoft Dataverse — **Add a new row** to `fsi_intakeauditevent` with `fsi_pathphase = ReviewerDecided` and `fsi_eventtype = ReviewerDecided`, `QuorumReached`, or `RequestDenied` depending on the branch taken.

**Failure handling.** Protect the Dataverse row update and quorum recomputation inside a single `Try/Catch` scope. If the decision row updates but the quorum logic fails, write `ReviewerDecisionHandlerFailed` to `fsi_intakeauditevent` and stop before any final status transition runs.

**SLA / timing.** Process reviewer responses immediately so the request status reflects the new quorum state without a nightly batch.

**Per-customer override.** Customers can change quorum weights, required reviewers, or condition-handling text, but a reviewer denial still ends the request immediately and should not be softened in the flow.

---

### Flow 6: `fsi-intake-escalation`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Schedule connector — **Recurrence**.

**Path scope.** Standard / Full.

**Inputs.** Open `fsi_intakereview` rows where `fsi_reviewoutcome = Pending (100000000)` and `fsi_dueon < utcNow()`, plus `reviewer_routing.<role>.escalation_contact` from `templates/policy-lookup-tables.yaml`.

**Outputs.** Escalation card or email to the escalation target, optional request status update to `Escalated`, and `ReviewerEscalated` audit events.

**Steps.**

1. Trigger: Schedule — **Recurrence**.
   - Recommended default: daily at the start of the reviewer business day.
2. Action: Microsoft Dataverse — **List rows** on `fsi_intakereviews`.
   - Filter for `fsi_reviewoutcome = Pending`, `fsi_dueon < utcNow()`, and the parent request not already final.
3. Branch: **Apply to each** overdue review row.
   - Read `fsi_reviewerrole`, `fsi_reviewerupn`, `fsi_dueon`, and `fsi_requestid`.
   - Resolve the escalation target from `templates/policy-lookup-tables.yaml` or a mirrored config table.
4. Action: Microsoft Teams — **Post card in a chat or channel** or Office 365 Outlook — **Send an email (V2)**.
   - Include the request ID, reviewer role, original due date, and reviewer-app deep link.
   - If the role-specific escalation contact is blank, fall back to `fsi_intake_sponsorbackupgroup` or a governance mailbox.
5. Action: Microsoft Dataverse — **Update a row** on `fsi_intakerequest` when the parent is still `InReview`.
   - Set `fsi_status = Escalated (100000007)` if the customer wants the request-level queue to highlight overdue work.
6. Audit event: Microsoft Dataverse — **Add a new row** to `fsi_intakeauditevent` with `fsi_pathphase = Escalated` and `fsi_eventtype = ReviewerEscalated`.

**Failure handling.** Keep the escalation loop idempotent by including the overdue review ID and the reviewer's due date in the audit payload. If the notification branch fails, log `ReviewerEscalationFailed` and retry on the next schedule rather than mutating the review row.

**SLA / timing.** Daily is the bundled default. Customers that want tighter reviewer follow-up can run this hourly.

**Per-customer override.** The escalation target, cadence, and whether `fsi_status` is updated to `Escalated` are customer policy choices.

---

### Flow 7: `fsi-intake-mrm-handoff`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Microsoft Dataverse connector — **When a row is added, modified or deleted** on `fsi_intakerequest` where `fsi_pathused = Full (100000002)`, `fsi_status = InReview (100000011)`, `fsi_mrmrequired = true`, `fsi_nonmrmquorummet = true`, and `fsi_mrmhandoffstatus` is `Pending (100000000)` or `Failed (100000003)`.

**Path scope.** Full.

**Inputs.** Full-path request row, related reviewer evidence, `fsi_mrmrequired = true`, `fsi_nonmrmquorummet = true`, `fsi_mrmhandoffstatus`, and the payload contract in [`mrm-integration.md`](./mrm-integration.md) plus `templates/mrm-handoff-payload-schema.json`.

**Outputs.** Upsert to `model-risk-management-automation`, updated `fsi_mrmhandoffstatus`, local fallback audit event when the downstream solution is absent, and a pending or completed `MRM` review row.

**Steps.**

1. Trigger: Microsoft Dataverse — **When a row is added, modified or deleted**.
   - Guard on `fsi_pathused = Full`, `fsi_status = InReview`, `fsi_mrmrequired = true`, `fsi_nonmrmquorummet = true`, and `fsi_mrmhandoffstatus = Pending or Failed`.
2. Action: Microsoft Dataverse — **Get a row by ID** on `fsi_intakerequest` and **List rows** on `fsi_intakereviews`.
   - Confirm `fsi_pathused = Full`, `fsi_mrmrequired = true`, `fsi_nonmrmquorummet = true`, and `fsi_mrmhandoffstatus = Pending or Failed` before proceeding.
3. Action: **Compose** the payload required by `templates/mrm-handoff-payload-schema.json`.
   - Reference [`mrm-integration.md`](./mrm-integration.md) for the field-level mapping.
   - Body excerpt:

   ```json
   {
     "payloadVersion": "1.0.0",
     "intake": {
       "requestId": "<fsi_requestid>",
       "pathUsed": "Full",
       "riskTier": "Tier 1 (High)",
       "zone": "Zone 1 (Enterprise)",
       "mrmRequired": true
     },
     "agent": {
       "displayName": "<fsi_agentdisplayname>",
       "platformAgentId": "<platform-agent-id-or-placeholder>",
       "environmentId": "<target-environment-id>",
       "intendedAudience": "<fsi_intendedaudience>",
       "businessOutcome": "<fsi_businessoutcome>"
     },
     "decisionPackHash": "<sha256>",
     "policyVersion": "<fsi_policyversionapplied>"
   }
   ```

4. Action: **Either/or transport step**.
   - **Option A (recommended)**: call an HTTP/custom-connector wrapper that implements the same behavior as `scripts/handoff_mrm.py`.
   - **Option B**: do the writes directly in the flow by using the Dataverse connector or Web API pattern documented in [`mrm-integration.md`](./mrm-integration.md): upsert `fsi_modelinventory` by alternate key (`fsi_agentid` + `fsi_environmentid`) and create `fsi_mrmcomplianceevent` as the sidecar marker.
5. Action: Microsoft Dataverse — **Update a row** on `fsi_intakerequest`.
   - Set `fsi_mrmhandoffstatus = Handed off (100000001)` on success or `Failed (100000003)` on hard failure.
   - If no existing `MRM` review row exists, create one with `fsi_reviewoutcome = Pending` so the downstream committee decision has a row to update later.
6. Audit event: Microsoft Dataverse — **Add a new row** to `fsi_intakeauditevent` with `fsi_pathphase = HandedOff` and `fsi_eventtype = MrmHandoffSubmitted`.
   - If the MRM solution is absent, follow the local fallback in [`mrm-integration.md`](./mrm-integration.md) and log `MRMHandoffPending` instead.

**Failure handling.** If the downstream MRM solution is not deployed, keep the intake request in a recoverable state by logging the fallback payload locally and leaving `fsi_mrmhandoffstatus = Pending` or `Failed` per customer policy. Do not finalize the decision pack until the MRM dependency has been resolved.

**SLA / timing.** Submit the handoff within minutes of the non-MRM quorum completing. Committee turnaround remains a customer process decision.

**Per-customer override.** The transport can point to the default Dataverse target or to a customer-specific MRM queue, but the JSON schema and field names should stay unchanged.

---

### Flow 8: `fsi-intake-decision-pack-writer`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Child flow called from Flow 3, Flow 5, or Flow 7 when the required decisions are in.

**Path scope.** All.

**Inputs.** `requestId`, `decisionOutcome`, `decisionSource`, and the latest sponsor/reviewer evidence rows.

**Outputs.** Immutable `fsi_intakedecisionlog` row, SHA-256 decision-pack hash, updated `fsi_decidedon`, and a `DecisionPackWritten` audit event.

**Steps.**

1. Trigger: child flow input parameters.
   - Minimum input shape:

   ```json
   {
     "requestId": "<fsi_requestid>",
     "decisionOutcome": "Approved | Denied",
     "decisionSource": "Sponsor | ReviewerQuorum | MRM"
   }
   ```

2. Action: Microsoft Dataverse — **Get a row by ID** on `fsi_intakerequest`, then **List rows** for `fsi_intakeapproval`, `fsi_intakesponsorship`, `fsi_intakereview`, `fsi_intakedatasource`, `fsi_intakerisksignal`, and the latest routing audit events.
3. Action: **Compose** the decision-pack JSON.
   - Use the field names expected by `templates/drift-handoff-payload-schema.json` as the envelope for the decision pack so the registry and drift handoff flows can reuse it without re-shaping the payload later.
   - Include the sponsor chain, `reviewerAttestations`, `mrmHandoffStatus`, `declaredDataSources`, `connectorAllowlist`, and any Standard/Full JSON blob carried in `fsi_standardfullquestionsjson`.
4. Action: **Compose** the SHA-256 hash.
   - Use the workflow expression `sha256(outputs('Compose_DecisionPackJson'))`.
5. Action: Microsoft Dataverse — **Add a new row** to `fsi_intakedecisionlog`.
   - Set `fsi_name = Decision pack - <requestId>`.
   - Set `fsi_requestid`, `fsi_decisionoutcome`, `fsi_risktier`, `fsi_zone`, `fsi_pathused`, `fsi_policyversionapplied`, `fsi_decisionpackjson`, `fsi_decisionpackhash`, `fsi_decidedon`, and `fsi_retentionlabelapplied` when the label is already known.
6. Action: Microsoft Dataverse — **Update a row** on `fsi_intakerequest`.
   - Stamp `fsi_decidedon = utcNow()` if it is still blank.
7. Audit event: Microsoft Dataverse — **Add a new row** to `fsi_intakeauditevent` with `fsi_pathphase = DecisionPack` and `fsi_eventtype = DecisionPackWritten`.

**Failure handling.** Before inserting the decision-log row, query `fsi_intakedecisionlog` for the same `fsi_requestid` and `fsi_decisionpackhash`. If the hash already exists, treat the call as idempotent and exit without inserting a duplicate immutable row.

**SLA / timing.** Write the decision pack before Flow 9 or Flow 10 attempts downstream handoff.

**Per-customer override.** Customers can append extra fields inside the decision-pack JSON, but keep the top-level keys used by the drift and registry contracts stable.

---

### Flow 9: `fsi-intake-registry-handoff`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Microsoft Dataverse connector — **When a row is added, modified or deleted** on `fsi_intakerequest` where `fsi_status = Approved (100000004)` and the latest decision-pack row already exists.

**Path scope.** All.

**Inputs.** Approved request row, latest decision-pack JSON/hash, sponsor evidence, reviewer evidence for Standard and Full, and the Microsoft Entra Agent ID prerequisites in [`identity-records-automation.md`](./identity-records-automation.md).

**Outputs.** Microsoft Entra Agent ID, registry handoff payload, updated `fsi_entraagentid`, updated `fsi_registryrecordid`, updated `fsi_status = LiveTracking`, and `EntraAgentIdMinted` / `RegistryHandoffComplete` audit events.

**Steps.**

1. Trigger: Microsoft Dataverse — **When a row is added, modified or deleted**.
   - Guard on `fsi_status = Approved` and a blank `fsi_registryrecordid` so the handoff fires once per approved request.
2. Action: Microsoft Dataverse — **Get a row by ID** on `fsi_intakerequest` and **List rows** on `fsi_intakedecisionlog` sorted by `createdon desc`.
3. Action: HTTP with Microsoft Entra ID or Graph custom connector — mint the Microsoft Entra Agent ID.
   - Recommended wrapper body when you expose `setup_entra_agent_id.py` through an internal HTTPS endpoint:

   ```json
   {
     "intakeRequestId": "<fsi_requestid>",
     "displayName": "<fsi_agentdisplayname>",
     "sponsorUpn": "<fsi_sponsorupn>",
     "approvalPath": "<fsi_pathused>",
     "blueprintId": "<agentIdentityBlueprintId>",
     "reviewerAttestations": [
       {
         "role": "InfoSec",
         "upn": "infosec-agent-review@contoso.com",
         "decidedOnUtc": "2026-05-16T12:34:56Z",
         "decisionPackHash": "<sha256>"
       }
     ]
   }
   ```

   - Note: the blueprint setup is owned by [`identity-records-automation.md`](./identity-records-automation.md); the shell script does not create a solution environment variable for the blueprint ID.
4. Action: Microsoft Dataverse — **Update a row** on `fsi_intakerequest`.
   - Write the returned service principal object ID to `fsi_entraagentid`.
5. Action: HTTP with Microsoft Entra ID — **HTTP** or a customer-specific custom connector.
   - POST the registry handoff payload expected by `agent-registry-automation`. Reuse the decision-pack envelope from Flow 8 and include `pathUsed`, `riskTier`, `zone`, `retentionLabel`, `decisionPackHash`, and `entraAgentId`.
6. Action: Microsoft Dataverse — **Update a row** on `fsi_intakerequest`.
   - Set `fsi_registryrecordid` from the registry response and `fsi_status = LiveTracking (100000012)` so Flow 10 can key off the completed registry handoff.
7. Audit event: Microsoft Dataverse — **Add a new row** to `fsi_intakeauditevent` with `fsi_eventtype = EntraAgentIdMinted` after the Graph call succeeds and `fsi_eventtype = RegistryHandoffComplete` after the registry call succeeds.

**Failure handling.** If Agent ID creation fails, stop before the registry call and log the exception payload to `fsi_intakeauditevent`. If the registry call fails after the Agent ID exists, keep `fsi_entraagentid` on the request row and mark only the registry step for retry.

**SLA / timing.** Run immediately after the decision pack is written so the approved request reaches downstream governance quickly.

**Per-customer override.** Customers can call Microsoft Graph directly, wrap `setup_entra_agent_id.py` in an internal API, or hand the request to an internal orchestration service, but the same sponsor and reviewer evidence should be preserved.

---

### Flow 10: `fsi-intake-drift-handoff`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Microsoft Dataverse connector — **When a row is added, modified or deleted** on `fsi_intakerequest` where `fsi_status = LiveTracking (100000012)`, `fsi_entraagentid` is populated, `fsi_registryrecordid` is populated, and no prior `DriftHandoffSubmitted` audit event exists for the request.

**Path scope.** All.

**Inputs.** Live-tracking request row, latest decision-pack JSON, sponsor and reviewer evidence, and the drift target in `fsi_intake_driftdetectorenv`.

**Outputs.** Drift-detector handoff payload and `DriftHandoffSubmitted` audit event.

**Steps.**

1. Trigger: Microsoft Dataverse — **When a row is added, modified or deleted**.
   - Guard on `fsi_status = LiveTracking`, populated `fsi_entraagentid`, populated `fsi_registryrecordid`, and no prior `DriftHandoffSubmitted` event for the request.
2. Action: Microsoft Dataverse — **Get a row by ID** on `fsi_intakerequest` and **List rows** on `fsi_intakedecisionlog` for the latest immutable decision pack.
3. Action: **Compose** the payload defined by `templates/drift-handoff-payload-schema.json`.
   - At minimum include `payloadVersion`, `originIntakeId`, `pathUsed`, `riskTier`, `zone`, `declaredAudience`, `intendedAudience`, `declaredDataSourcesJson`, `declaredDataSources`, `connectorAllowlist`, `sponsorUpn`, `sponsor`, `reviewerAttestations`, `mrmHandoffStatus`, `policyVersion`, `retentionLabel`, `decisionPackHash`, and `entraAgentId`.
4. Action: HTTP with Microsoft Entra ID — **HTTP** or a custom connector.
   - POST the drift payload to the endpoint configured in `fsi_intake_driftdetectorenv`.
   - Reference [`drift-detection-integration.md`](./drift-detection-integration.md) for downstream consumers and field usage.
5. Audit event: Microsoft Dataverse — **Add a new row** to `fsi_intakeauditevent` with `fsi_pathphase = HandedOff` and `fsi_eventtype = DriftHandoffSubmitted`.

**Failure handling.** Leave the request in place and retry only the downstream call if the target endpoint is unavailable. Do not remove `fsi_entraagentid` or `fsi_registryrecordid` after a drift-hand-off failure.

**SLA / timing.** Fire after the registry handoff succeeds. Most tenants run this in the same approval-processing window so the peer drift detectors see the request before go-live broadens the scope.

**Per-customer override.** Customers can point the handoff to the default drift solution, to another detector, or to a message bus, but the JSON schema should stay stable.

---

### Flow 11: `fsi-intake-denial-appeal`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Microsoft Teams connector — **When someone responds to an adaptive card** where `data.action = denialAppeal`.

**Path scope.** All.

**Inputs.** Original `requestId`, maker response from the denial card, optional appeal notes, and `denial_appeal.max_resubmissions` from `templates/policy-lookup-tables.yaml`.

**Outputs.** New `fsi_intakerequest` row, preserved appeal lineage, and `AppealSubmitted` audit events on the original and appealed request.

**Steps.**

1. Trigger: Microsoft Teams — **When someone responds to an adaptive card**.
   - The denial card action payload should follow this shape:

   ```json
   {
     "action": "denialAppeal",
     "requestId": "${fsi_requestid}",
     "decisionPackHash": "${fsi_decisionpackhash}"
   }
   ```

2. Action: Microsoft Dataverse — **List rows** on `fsi_intakeauditevent` and **Get a row by ID** on the original `fsi_intakerequest`.
   - Count prior appeal submissions for the original request and compare the total to `denial_appeal.max_resubmissions.<path>`.
3. Branch: **Condition**.
   - If the customer-specific appeal cap has been reached, post a maker message explaining that the denial remains closed and log `AppealRejected`.
4. Action: Microsoft Dataverse — **Add a new row** to `fsi_intakerequest` when the appeal is allowed.
   - Set `fsi_name = Appeal - <newRequestId>`.
   - Copy the original request's maker, sponsor, audience, trigger answers, and Standard/Full JSON blob.
   - Set a new `fsi_requestid`, `fsi_status = Submitted (100000001)`, `fsi_appealofid = <original request ID>`, and preserve any customer-specific appeal narrative in `fsi_standardfullquestionsjson`.
5. Action: Microsoft Dataverse — **Add a new row** to `fsi_intakeauditevent` on both requests.
   - Original request: `fsi_eventtype = AppealSubmitted`, `fsi_pathphase = Submitted`.
   - New request: `fsi_eventtype = AppealSubmitted`, `fsi_pathphase = Submitted`, with the original request ID in the payload.
6. Trigger hand-off: do nothing else. Flow 1 naturally picks up the new request once it reaches `Submitted`.

**Failure handling.** If the new appeal request cannot be created, log `AppealCreateFailed` against the original request and do not mutate the original decision state.

**SLA / timing.** Submit the appealed request immediately so it re-enters the same router and reviewer flow as a first-class request.

**Per-customer override.** The appeal cap, appeal text, and whether the appealed request auto-copies the original Standard/Full JSON blob are customer policy choices, but the flow should always preserve lineage.

---

### Flow 12: `fsi-intake-retention-tagger`

> Prerequisites: complete [`flow-build-prerequisites.md`](./flow-build-prerequisites.md) before building this flow.

**Trigger.** Logical retention flow pattern for newly created `fsi_intakedecisionlog`, `fsi_intakeauditevent`, and final-state `fsi_intakerequest` rows.

**Path scope.** All.

**Inputs.** The row ID and table name, `fsi_intake_retentionlabelid`, and the retention strategy documented in [`identity-records-automation.md`](./identity-records-automation.md).

**Outputs.** `fsi_intakeretentionrecord` evidence row, optional retention-wrapper/API call, and `RetentionLabelApplied` audit event.

**Steps.**

1. Trigger: one of the following patterns.
   - **Preferred logical pattern**: one child flow that accepts `tableName` + `recordId`, plus thin per-table trigger flows that call it.
   - **Direct trigger pattern**: separate Dataverse create triggers for `fsi_intakedecisionlog`, `fsi_intakeauditevent`, and final-state `fsi_intakerequest` rows.
   - Note: Power Automate does not let one cloud flow listen to multiple Dataverse tables with a single trigger, so treat Flow 12 as a logical pattern even though the inventory lists it once.
2. Action: Microsoft Dataverse — **Get a row by ID** on the triggering table.
   - Read the request ID and any existing retention metadata.
3. Branch: **Condition**.
   - If the tenant uses table-level Purview auto-labeling, skip the direct label call and only log evidence.
   - If the tenant uses a supported retention wrapper or API, call it with `fsi_intake_retentionlabelid`, the table name, and the row ID.
4. Action: Microsoft Dataverse — **Add a new row** to `fsi_intakeretentionrecord`.
   - Set `fsi_name = Retention stamp - <requestId>`.
   - Set `fsi_requestid`, `fsi_labelname` or label identifier text, `fsi_retentionyears`, `fsi_stampedon`, `fsi_stampedby`, and `fsi_regulatorybasis`.
5. Audit event: Microsoft Dataverse — **Add a new row** to `fsi_intakeauditevent` with `fsi_pathphase = Retention` and `fsi_eventtype = RetentionLabelApplied`.

**Failure handling.** If the direct label-application call fails, keep the evidence row and the audit event together so operators can see the gap clearly. Do not delete the immutable decision pack or audit row because the retention wrapper was unavailable.

**SLA / timing.** Stamp retention evidence as close to row creation as the tenant allows. Table-level Purview auto-labeling is acceptable when the row-level API path is not available.

**Per-customer override.** Customers can use table-level Purview auto-labeling, a wrapper around Records Management PowerShell, or another supported records-management path, but the flow should always leave a Dataverse evidence trail.

---

## Cross-flow reminders

- Keep the card payloads stable: `requestId`, `reviewId`, `reviewerRole`, and `decisionPackHash` are the correlation keys reused across the reviewer, decision-pack, appeal, registry, and drift flows.
- Keep the maker/sponsor separation rule active in both the portal and Flow 1.
- When you create or update flow trigger conditions, use the numeric choice values from the table above rather than the display labels.
- Build every flow in the `FSIAgentIntake` unmanaged solution; do not export and commit runtime JSON.
