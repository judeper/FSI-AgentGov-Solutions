# Classification rules reference

This reference explains how `scripts/seed_classification_rules.py` routes an `fsi_intakerequest` into the **Express**, **Standard**, **Full**, or **DefaultDeny** outcomes for the `agent-intake` v1.0.0-preview workstream.

It summarizes the locked decisions in [ADR-002](./decisions.md#adr-002--express-eligibility--t1t6-all-no--tier-3--zone-3), [ADR-005](./decisions.md#adr-005--default-deny-when-maker-country-differs-from-data-residency-country), [ADR-007](./decisions.md#adr-007--sponsor-1-click-is-sufficient-finra-3110-evidence-for-express-only), [ADR-008](./decisions.md#adr-008--sponsor-cannot-self-approve), [ADR-009](./decisions.md#adr-009--major-modification-triggers-fresh-review-minor-does-not), and the product-owner defaults in [`research/04-open-questions-resolved.md`](../research/04-open-questions-resolved.md).

> These defaults support compliance with FINRA Rule 3110, FINRA Rule 4511, SEC Rule 17a-4, GLBA 501(b), and SR 11-7 when combined with the downstream reviewer, retention, and handoff workflows. Organizations should confirm reviewer assignments, quorum thresholds, and country-routing policy before production rollout.

## Inputs used by the classifier

The classifier reads the following `fsi_intakerequest` fields:

- Trigger answers: `fsi_t1initiatesfinancialtxn` through `fsi_t6crossborderdata`
- Audience: `fsi_intendedaudience` (or its label aliases)
- Identity controls: `fsi_makerupn`, `fsi_sponsorupn`
- Residency controls: `fsi_makercountry`, `fsi_dataresidencycountry`, `fsi_privacyoverride`

If a required field is missing, the classifier raises `ValueError` with the field name so the upstream flow can stop with a clear remediation message.

## Trigger questions and why they matter

| Field | Plain-language meaning | Why the rule exists |
|---|---|---|
| `fsi_t1initiatesfinancialtxn` | The agent initiates, recommends, or approves a financial transaction. | Supports higher scrutiny for supervisory evidence and operational-risk review under FINRA Rule 3110 and SR 11-7 principles. |
| `fsi_t2customerfacing` | The agent will interact directly with customers or external-facing journeys. | Supports review of customer-impact, disclosure, and escalation controls before the request can stay in the low-risk path. |
| `fsi_t3autonomousunmonitored` | The agent can run without a human checkpoint or routine monitoring. | Supports review of human oversight expectations and escalation design for autonomous behavior. |
| `fsi_t4handlesnpi` | The agent will use non-public personal information. | Supports privacy and GLBA 501(b) review. The Standard path adds Compliance when this trigger is positive. |
| `fsi_t5handlesmnpi` | The agent will use material non-public information. | Routes to **Full** by default because MNPI handling needs the highest review depth in the locked pilot defaults. |
| `fsi_t6crossborderdata` | The agent will move data across country boundaries. | Supports ADR-005: unresolved cross-border routing defaults to deny unless Privacy records an override in `fsi_privacyoverride`. |

`Yes` and `Not sure` both count as positive trigger hits. The locked design is intentionally conservative: uncertainty still routes the request out of Express.

## Audience-to-zone mapping

The audience answer maps to the governance zone through `templates/policy-lookup-tables.yaml`.

| `fsi_intendedaudience` value | Zone | Meaning |
|---|---|---|
| `Just me` | Zone 3 | Personal scope |
| `My team` | Zone 2 | Team scope |
| `My department` | Zone 2 | Business-unit scope |
| `Anyone in the firm` | Zone 1 | Enterprise scope |
| `External users` | Zone 1 | External-facing scope |

The classifier treats the policy file as the source of truth. If the file or the `audience_to_zone` section is missing, it falls back to the bundled defaults above.

## Three-path decision tree

### Step 1 — Count trigger hits

`triggerHits` is the count of T1-T6 answers equal to `Yes` or `Not sure`.

### Step 2 — Compute the provisional path

| Provisional path | When it is used | Resulting tier / zone | Reviewer model |
|---|---|---|---|
| **Express** | `triggerHits == 0` **and** the audience maps to Zone 3 | Tier 3 / Zone 3 | Sponsor only; `quorumRequired = 1`; `parallelReviewers = []` |
| **Standard** | Everything that is not Express or Full, including Zone-2 audiences and Zone-3 requests with 1-2 non-MNPI trigger hits | Tier 2 / Zone 2 | `InfoSec` + `Privacy`; add `Compliance` when `fsi_t4handlesnpi` is positive |
| **Full** | Zone-1 audience, `triggerHits >= 3`, any positive `fsi_t5handlesmnpi`, or a Privacy-approved cross-border mismatch | Tier 1 / Zone 1 | `InfoSec`, `Privacy`, `Compliance`, `Legal`, and `MRM` |

### Step 3 — Apply deny gates

`decisionPath` is usually the same as `pathUsed`, but two defensive gates can replace it with `DefaultDeny`:

1. **Sponsor self-approval** — ADR-008 denies the request when `fsi_sponsorupn == fsi_makerupn`.
2. **Cross-border default-deny** — ADR-005 denies the request when `fsi_t6crossborderdata = Yes`, `fsi_makercountry != fsi_dataresidencycountry`, and `fsi_privacyoverride` is empty or false.

When a deny gate fires, `pathUsed` still records the provisional route (`Express`, `Standard`, or `Full`) so the downstream flow, logs, and analytics have a stable path value. `routingReason` captures the deny cause as either `sponsor_self_approval` or `cross_border_data`.

## Reviewer quorum defaults

The policy file can override quorum and reviewer-routing behavior, but the bundled defaults are:

| Tier | Default quorum | Default routing mode | Reviewer board |
|---|---|---|---|
| Tier 3 | 1 of 1 | Sequential | Sponsor only |
| Tier 2 | 2 of 3 | Parallel | `InfoSec`, `Privacy`, plus `Compliance` when `fsi_t4handlesnpi` is positive |
| Tier 1 | 3 of 5 | Parallel | `InfoSec`, `Privacy`, `Compliance`, `Legal`, `MRM` |

The classifier returns:

- `quorumRequired` — the effective number of approvals required for the reviewer board
- `parallelReviewers` — the reviewer set for Standard or Full
- `mrmRequired` — `true` for Tier 1 when the `mrm.required_when_tier_1` policy flag stays enabled
- `mrmHandoffStatus` — `Pending` for Tier 1; `NotApplicable` for non-Tier-1 outcomes

## Cross-border behavior and Privacy override

ADR-005 remains in force across all three paths:

- If `fsi_t6crossborderdata = Yes` and the maker country does not match the declared data-residency country, the request defaults to `DefaultDeny`.
- Privacy can override that gate by setting `fsi_privacyoverride = true` on the intake record.
- A Privacy-approved mismatch still routes to **Full**, not Standard, because the request remains high-risk even after the override.
- If the country pair is explicitly allow-listed in policy, the request can continue through Standard or Full without a deny outcome.

## Sponsor self-approval prevention

ADR-008 requires the sponsor to be a different person from the maker. The Power Pages experience should block that combination at submit time, but the classifier re-checks it so that imports, bulk updates, or replayed flow runs do not create an unsupported approval chain.

## Policy override path

Customer-specific overrides live in `templates/policy-lookup-tables.yaml`. The classifier reads these sections defensively and falls back to bundled defaults if a section is absent:

- `audience_to_zone`
- `data_residency`
- `quorum`
- `parallel_routing`
- `reviewer_routing`
- `mrm`
- `retention_labels`
- `managed_environment`
- `dlp_connector_group`

The implementation also tolerates minor key-shape drift (for example, `parallelRouting` vs. `parallel_routing`) so the router can keep classifying requests while the parallel schema workstream lands.

## Operational notes for downstream docs

- `flow-configuration.md` should treat `decisionPath` as the branch key and `pathUsed` as the reporting key.
- `admin-onboarding-guide.md` should call out that Express is the only sponsor-only path.
- Standard and Full require additional reviewer evidence; OQ-J explicitly treats the sponsor click as necessary but not sufficient outside Express.
- Any change to T1-T6 still counts as a major modification under ADR-009 and should trigger re-classification.
