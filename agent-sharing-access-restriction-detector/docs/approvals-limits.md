# Approvals Limits and Flow-Build Invariants

> **Solution:** Agent Sharing Access Restriction Detector (ASARD)
> **Version:** v2.0.2
> **Scope:** Power Automate **Approvals** constraints that the Remediation Approval flow
> must honor. This document records the constraints; the live flow build that implements
> them is owned by the flows lane (see `docs/flow-configuration.md` and the lab runbook).

ASARD routes every sharing-remediation through a human approval before any change is
written to the Dataverse `bots` table. The Power Automate Approvals service carries
platform limits that the flow must be built around. Honoring these limits is **required
for** the approval gate to behave predictably; it does not by itself satisfy any
regulation in isolation.

## 1. 28-day approval-wait ceiling

Microsoft Learn documents that an approval flow can wait for up to **28 days**; if the
wait time exceeds 28 days, that flow run fails. ASARD's Remediation Approval flow uses a
sequential (concurrency = 1) loop with a 7-day per-approval timeout, so the cumulative
wait can approach the ceiling once several non-compliant agents queue behind one another.

**Build invariant:** size the per-approval timeout and the per-run agent batch so the
**cumulative** wait across the sequential loop stays well under 28 days. Treat 28 days as
a hard platform ceiling, not a target.

## 2. `Create an approval` / `Wait for an approval` adjacency

The Approvals pattern is reliable only when the **`Create an approval`** action and its
matching **`Wait for an approval`** action are **adjacent** designer actions for the same
approval — with no intervening variable assignments, scopes, or loop boundaries that can
delay the wait registration.

**Build invariant:** place `Create an approval` immediately before `Wait for an approval`
for each remediation. Do not separate them with `Apply to each`, `Do until`, or
intermediate `Compose`/variable steps. This adjacency is a build-time requirement, not a
runtime tuning knob.

## 3. More than 4 non-compliant agents per scan — batch / child-flow overflow

Because the loop is sequential with 7-day timeouts, **more than ~4 non-compliant agents in
a single scan** can drive the cumulative wait past the 28-day ceiling (Section 1). The
flow must short-circuit rather than serially walk past that ceiling.

**Build invariant:**

- For **> 4** non-compliant agents in a run, queue the overflow to a **child flow** (or a
  staged dataset processed across runs) instead of extending one sequential loop.
- Skeletonize the **batch / child-flow overflow branch** in the flow even when the lab
  fixture seeds a single non-compliant bot, so the path exists and is testable before it
  is first exercised under load.
- This is the documented mitigation for the README "28-day approval wait limit" known
  limitation. The lab may seed exactly one non-compliant bot so this branch is not
  exercised in v1 validation, but the skeleton must be present.

## Ownership and where the build lives

| Item | Recorded here | Implemented (live) in |
|------|---------------|------------------------|
| 28-day ceiling sizing | This doc (constraint) | Flow build — flows lane |
| Create/Wait adjacency | This doc (build invariant) | Flow build — flows lane |
| > 4-agent batch/child overflow | This doc (build invariant) | Flow build — flows lane |

The live Remediation Approval flow is built and documented by the flows lane in
`docs/flow-configuration.md` and the lab `slice-build-runbook.md`. This document is the
constraints reference those build docs draw from; it intentionally does **not** prescribe
the designer step-by-step.

## Authoritative sources

- **Approvals / flow run retention (Power Automate)** —
  https://learn.microsoft.com/power-automate/ (approval wait ceiling and the 28-day flow
  run retention window). Mirrors the caveat captured in `LAB-VALIDATION.md` and the README
  "Known Limitations".
