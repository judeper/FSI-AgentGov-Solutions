# Drift-detection integration — wiring agent-intake to peer solutions

Once an Express-path request is approved, ongoing governance moves to the existing 35-solution suite. This document records the **handoff and drift-detection contract** between `agent-intake` and the four solutions that own the post-approval lifecycle.

## Why this matters

The intake decision is a **point-in-time attestation**. A maker can approve an Express-path agent today and, a week later, share it firm-wide, expand its data sources, or attach it to a Tier-1 connector. The peer solutions detect that drift and either auto-remediate or escalate; this document tells them what to look for.

## Handoff contract

When Flow 3 (`docs/flow-configuration.md`) creates the registry shell row in `agent-registry-automation`, it stamps the following on the registry record:

| Registry column | Value from intake | Used by |
|---|---|---|
| `fsi_originintake_id` | `fsi_intakerequest.fsi_intakerequestid` | All four peers (audit trail) |
| `fsi_intaketier` | `fsi_intakerequest.fsi_tier` (1/2/3) | scope-drift-monitor, agent-access-monitor |
| `fsi_intakezone` | `fsi_intakerequest.fsi_zone` (1/2/3) | unrestricted-agent-sharing-detector |
| `fsi_declared_data_sources` | JSON list of connectors maker disclosed | scope-drift-monitor |
| `fsi_declared_audience` | `fsi_intendedaudience` | unrestricted-agent-sharing-detector |
| `fsi_sponsorupn` | `fsi_sponsorupn` | agent-365-lifecycle-governance |
| `fsi_entra_agentid` | minted Entra Agent ID | All four peers |

## Peer-solution wiring

### 1. `unrestricted-agent-sharing-detector`

**Drift signal:** Agent shared with `fsi_intendedaudience` wider than declared at intake.

**Detection rule:** When the detector finds an agent shared with `Everyone in the firm` but `fsi_declared_audience IN {"Just me", "My team", "My department"}`, raise a **High** severity finding tagged `OriginIntake: Express-path overshare`.

**Remediation:** Auto-revoke share, notify maker + sponsor, append `fsi_intakeauditevent` of type `PostApprovalDrift_Sharing` to the original intake record.

### 2. `scope-drift-monitor`

**Drift signal:** Agent reads/writes data outside the declared connector set.

**Detection rule:** Compare runtime data-access telemetry (App Insights / Purview audit log) against `fsi_declared_data_sources`. Any new connector triggers a finding.

**Remediation:** Append to the intake decision log; if connector falls in DLP `Confidential` group AND intake was Express (Tier 3), force re-review per locked decision #6 (modification cutoff: trigger changes = full re-review).

### 3. `agent-access-monitor`

**Drift signal:** Agent acquires elevated permissions (e.g., new app role, additional Graph scope) post-intake.

**Detection rule:** Compare current agent identity permissions against the snapshot taken at minting time (Entra Agent ID `appRoleAssignments`). Any new privileged role triggers a finding.

**Remediation:** If new role is in the `Tier-1-only` allowlist (configured via `policy-lookup-tables.yaml`), revoke immediately and force re-review.

### 4. `agent-365-lifecycle-governance`

**Drift signal:** Sponsor leaves the organisation, changes role, or fails to re-attest within `sponsor_sla.recertification_days` (configurable; default 365 per OQ-B).

**Detection rule:** Daily check against Microsoft Graph for sponsor account state (`accountEnabled`, `assignedLicenses`, `manager.id` change → cost-centre transfer).

**Remediation:** Initiate sponsor-handoff workflow (out of scope for v0.1.0-preview; depends on agent-365-lifecycle-governance v1.2.0+).

## Cross-solution audit trail

Every drift finding from peer solutions writes back to the originating intake record via:

```
INSERT fsi_intakeauditevent
  fsi_intakerequestid = <original>
  fsi_eventtype = 'PostApprovalDrift_<Sharing|Scope|Access|Lifecycle>'
  fsi_eventtimeutc = utcNow()
  fsi_evidencejson = <peer-solution finding payload>
  fsi_severity = <peer-solution severity>
```

This gives compliance a single pane to evidence FINRA 3110 ongoing supervision: the intake decision, the sponsor attestation, and every subsequent drift event are linked.

## What v0.1.0-preview does NOT wire

- **Real-time drift alerts to sponsor's Teams** — peer solutions today email the InfoSec queue; sponsor-routed alerts deferred to v0.2.0.
- **Auto-revocation of Entra Agent ID** on critical drift — manual today; planned v0.3.0 to call `DELETE /beta/identityGovernance/agentIdentities/{id}`.
- **MRM re-tiering** when scope expands — Tier-3 → Tier-2 promotion requires manual Compliance review.
