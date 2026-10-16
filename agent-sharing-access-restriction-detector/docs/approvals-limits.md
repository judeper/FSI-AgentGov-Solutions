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

Microsoft's [Approvals known issues](https://learn.microsoft.com/en-us/power-automate/approvals-known-issues#abandoned-approvals-in-the-approval-action-center)
documents a **28-day** approval wait caveat; a failed flow can leave an abandoned approval
in the action center. Separately, [cloud-flow duration limits](https://learn.microsoft.com/en-us/power-automate/limits-and-config#duration-limits)
specify a **30-day total run duration**, including pending approvals. The two figures
are not interchangeable, and neither describes a 28-day run-history retention period.

ASARD configures a **7-day** per-approval timeout (`P7D`); this is a solution default,
not a Microsoft platform default. With concurrency = 1, four full waits consume 28 days
before other actions and retries; five require 35 days and exceed the total run limit.

**Build invariant:** keep each wait below the approval limit and size the batch so
`batch size × configured timeout + other work/retry allowance < 30 days`.
ASARD conservatively budgets cumulative waits **below 28 days** to leave headroom;
that is a local safety margin, not a Microsoft-documented cumulative-loop limit.
Handle timeout, rejection, and cancellation without changing agent access, and retain
the pending record for a subsequent run rather than reporting successful remediation.

## 2. `Create an approval` / `Wait for an approval` adjacency

Microsoft documents a race when a user responds after **Create an approval** but before
**Wait for an approval** starts. Its guidance is to call the two actions **close together**;
literal designer adjacency is not a Microsoft platform requirement.

**Build invariant:** place `Create an approval` immediately before `Wait for an approval`
for each remediation. Do not separate them with `Apply to each`, `Do until`, or
intermediate `Compose`/variable steps. This adjacency is a build-time requirement, not a
runtime tuning knob for ASARD. The single **Start and wait for an approval** action is
the alternative used by the lab build.

## 3. Sequential batch sizing and overflow

The sequential loop must not accept more work than the timeout budget in Section 1.
Do not treat four agents as an unconditional safe threshold: four full waits already
consume the entire conservative 28-day wait budget, before action/retry overhead.

**Build invariant:**

- Persist overflow in the existing compliance records for independently triggered later
  runs. Record which agents were deferred and why; do not silently truncate a query.
- A parent that synchronously waits for a child still consumes its own run-duration
  budget. A child-flow call alone is not a long-running-approval solution. Microsoft
  describes splitting creation and response processing in [long-running approvals](https://learn.microsoft.com/en-us/power-automate/modern-approvals#create-long-running-approvals).
- Verify the boundary with a short test timeout and a batch large enough to force
  deferral. Confirm no sharing writes occur on timed-out/rejected/canceled approvals,
  deferred records remain pending, and the next run can pick them up.
- These are build/verification requirements, not a claim that the staged Flow B overflow
  branch has executed successfully. The June lab used one fixture and did not prove
  multi-agent approval throughput.

## Ownership and where the build lives

| Item | Recorded here | Implemented (live) in |
|------|---------------|------------------------|
| Approval-wait and total-run budget | This doc (constraint) | Flow build — flows lane |
| Create/Wait adjacency | This doc (build invariant) | Flow build — flows lane |
| Budgeted batch / persisted overflow | This doc (build invariant) | Flow build — flows lane |

The live Remediation Approval flow is built and documented by the flows lane in
`docs/flow-configuration.md` and the lab `slice-build-runbook.md`. This document is the
constraints reference those build docs draw from; it intentionally does **not** prescribe
the designer step-by-step.

## Authoritative sources

- [Approvals known issues](https://learn.microsoft.com/en-us/power-automate/approvals-known-issues) — 28-day wait caveat and split-action race.
- [Cloud-flow duration limits](https://learn.microsoft.com/en-us/power-automate/limits-and-config#duration-limits) — 30-day total run duration and run retention.
- [Long-running approvals](https://learn.microsoft.com/en-us/power-automate/modern-approvals#create-long-running-approvals) — split-flow design for approvals outliving a single run.
