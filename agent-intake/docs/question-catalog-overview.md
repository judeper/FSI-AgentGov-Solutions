# Intake question catalog overview

These intake catalogs are the source of truth for the `agent-intake` expansion from the current Express-only preview toward the three-path model. They support evidence collection for firm-level AI governance under OCC Bulletin 2026-13, keep SR 11-7-style tiering available where a firm uses it by policy, and preserve the books-and-records and supervision artifacts firms use for FINRA Rule 4511, FINRA Rule 3110, SEC Rules 17a-3 and 17a-4, CFTC Rule 1.31, and GLBA 501(b). They assume commercial Microsoft 365, generic US FSI defaults, and en-US maker-facing text. They do not certify compliance.

## Path comparison

| Path | Total maker-entered questions | Typical use | Default approval pattern | Primary docs |
|---|---:|---|---|---|
| Express | 13 | Personal-scope, lowest-risk requests where the maker can stay inside ADR-002 eligibility | Sponsor 1-click | `intake-questions-express.md` |
| Standard | 22 | Team or department use, moderate risk, broader sharing, connectors, or monitored action-taking | Sponsor + 2-of-3 reviewer quorum | `intake-questions-standard.md` |
| Full | 35 | Enterprise, customer-facing, MNPI/NPI, cross-border, autonomous, transaction-capable, or other Tier-1 requests | Sponsor + 5-reviewer parallel (default 3-of-5 plus Sponsor; MRM non-waivable for Tier-1) | `intake-questions-full.md` |

## Preview storage model

For v1.0.0-preview, the common baseline questions continue to map to first-class `fsi_intakerequest` columns, and every Standard-only or Full-only answer is stored in `fsi_intakerequest.fsi_standardfullquestionsjson.<jsonKey>`.

- Use stable lower-camel-case keys derived from the proposed v1.1 field names.
- Standard keys run from `s1AudienceExtension` through `s10MonitoringPlan`.
- Full keys run from `f1ExternalExposure` through `f13RegulatorNotificationPlan`.
- If v1.1 adds first-class `fsi_s*` or `fsi_f*` columns, treat them as mirrors of the preview JSON blob rather than a rename of the preview storage contract.

## Progressive disclosure model

The maker should not see every question on day one. The intended experience is progressive disclosure:

1. **Auto-prefill the identity block** from Microsoft Graph and system metadata (`fsi_maker*`, `fsi_sponsorupn`, `fsi_requestid`, `fsi_policyversionapplied`).
2. **Show the common baseline block** used by every path: agent name, business outcome, business justification, agent type, intended audience, and the six routing triggers.
3. **Compute the route immediately after the trigger screen** using the audience answer plus ADR-002 and ADR-005 logic.
4. **Show only the remaining section for the routed path**:
   - Express: stop after the 13-question baseline set.
   - Standard: show the 10 Standard additions only.
   - Full: show the 10 Standard additions and the 13 Full additions.
5. **Retain one decision pack shape regardless of path** so reviewers and auditors see the same canonical labels even when a maker answered fewer questions.

## Common routing baseline

All three catalogs share the same baseline fields and routing assumptions:

- `fsi_intendedaudience` drives the initial zone assumption.
- `fsi_t1initiatesfinancialtxn`, `fsi_t2customerfacing`, `fsi_t3autonomousunmonitored`, `fsi_t4handlesnpi`, `fsi_t5handlesmnpi`, and `fsi_t6crossborderdata` are the six gating triggers shown to every maker.
- `fsi_dataresidencycountry` becomes required whenever cross-border activity is possible.
- ADR-002 keeps Express conservative: personal scope plus all six triggers answered `No`.
- ADR-005 keeps cross-border handling conservative: if maker country and declared data residency differ, the request defaults to deny pending Privacy override.

## How downstream workstreams should use these files

- **Power Pages form workstream:** treat the question text, type, required-ness, and storage-reference columns as the canonical maker UI contract.
- **Foundation-schema workstream:** keep the existing Express logical names as-is. For v1.0.0-preview, store Standard/Full answers in `fsi_standardfullquestionsjson`; if v1.1 adds `fsi_s*` or `fsi_f*` columns, make them mirrors rather than replacements.
- **Classification engine workstream:** use the routing-impact text as the authoritative trigger semantics for reviewer activation, escalation, and default-deny behavior.
- **Reviewer app workstream:** use the question text here as the default reviewer-facing label set so sponsor, reviewer, and audit views stay aligned.
- **Flow build docs and customer training:** quote these catalogs rather than restating local copies of the question wording.

## Canonical preview storage families

| Family | Purpose | Canonical preview storage |
|---|---|---|
| Existing Express fields | Current MVP baseline that must stay stable | First-class `fsi_intakerequest` columns such as `fsi_agentdisplayname`, `fsi_businessoutcome`, `fsi_businessjustification`, `fsi_agenttype`, `fsi_intendedaudience`, `fsi_t1initiatesfinancialtxn`, `fsi_t2customerfacing`, `fsi_t3autonomousunmonitored`, `fsi_t4handlesnpi`, `fsi_t5handlesmnpi`, `fsi_t6crossborderdata`, `fsi_dataresidencycountry`, and `fsi_makerattestation` |
| Standard additions | Team-scope and moderate-risk routing | `fsi_intakerequest.fsi_standardfullquestionsjson.s1AudienceExtension` through `fsi_intakerequest.fsi_standardfullquestionsjson.s10MonitoringPlan` |
| Full additions | Enterprise, legal, model-risk, and resilience routing | `fsi_intakerequest.fsi_standardfullquestionsjson.f1ExternalExposure` through `fsi_intakerequest.fsi_standardfullquestionsjson.f13RegulatorNotificationPlan` |

## Customer override boundaries

Customers should tune reviewer quorums, retention classes, sensitivity label values, NY DFS enablement, training prerequisites, and monitoring thresholds through policy/configuration rather than by renaming canonical question fields or preview JSON keys. If a customer needs more granular UI controls than a composite question provides, the downstream workstreams can split the form into sub-controls while still writing back to the same canonical storage references and decision-pack structure.

## Relationship to current implementation docs

`portal-configuration.md` remains the current Express implementation guide until the downstream workstream refreshes it. If there is drift between the legacy portal guide and these catalogs, treat these catalogs as the authoritative source for question wording, required-ness, and routing semantics.
