# Drift-detection integration — wiring agent-intake to peer solutions

Once an Express-path request is approved, ongoing governance moves to the existing solution suite. This document records the handoff and drift-detection contract between `agent-intake` and the four solutions that own post-approval lifecycle monitoring.

## Why this matters

The intake decision is a point-in-time attestation. A maker can approve an Express-path agent today and later share it firm-wide, expand data sources, or attach it to a higher-risk connector. Peer solutions detect that drift and either remediate or escalate; this document tells them what to look for.

## Handoff contract

When Flow 3 creates the registry shell row in `agent-registry-automation`, it should stamp these values where the registry schema supports them. If a peer solution has not yet added a dedicated column, include the value in the registry evidence JSON and decision-pack JSON rather than inventing snake_case Dataverse columns.

| Suggested logical name | Value from intake | Used by |
|---|---|---|
| `fsi_originintakeid` | `fsi_intakerequestid` or `fsi_requestid` | All peers (audit trail) |
| `fsi_intaketier` | `fsi_risktier` | scope-drift-monitor, agent-access-monitor |
| `fsi_intakezone` | `fsi_zone` | unrestricted-agent-sharing-detector |
| `fsi_declareddatasourcesjson` | `fsi_declareddatasourcesjson` | scope-drift-monitor |
| `fsi_declaredaudience` | `fsi_intendedaudience` | unrestricted-agent-sharing-detector |
| `fsi_sponsorupn` | `fsi_sponsorupn` | agent-365-lifecycle-governance |
| `fsi_entraagentid` | Microsoft Entra Agent ID service principal ID | All peers |

## Peer-solution wiring

### 1. `unrestricted-agent-sharing-detector`

**Drift signal:** Agent shared with an audience wider than `fsi_intendedaudience`.

**Detection rule:** When the detector finds an agent shared with everyone in the firm but `fsi_declaredaudience` is `Just me`, `My team`, or `My department`, raise a High severity finding tagged `OriginIntake: Express-path overshare`.

**Remediation:** Revoke the share where policy allows, notify maker + sponsor, and append a `fsi_intakeauditevent` of type `PostApprovalDrift_Sharing` to the original intake record.

### 2. `scope-drift-monitor`

**Drift signal:** Agent reads/writes data outside the declared connector set.

**Detection rule:** Compare runtime data-access telemetry against `fsi_declareddatasourcesjson`. Any new connector triggers a finding.

**Remediation:** Append to the intake audit trail; if the connector falls in the Business data policy group and the intake was Express (Tier 3), force re-review per modification-cutoff policy.

### 3. `agent-access-monitor`

**Drift signal:** Agent acquires elevated permissions or additional Graph scopes post-intake.

**Detection rule:** Compare current Agent ID service principal permissions (`appRoleAssignments` and `oauth2PermissionGrants`) against the snapshot taken at handoff. Any new privileged role triggers a finding.

**Remediation:** If the new role is outside the Express allowlist, revoke where policy allows and force re-review.

### 4. `agent-365-lifecycle-governance`

**Drift signal:** Sponsor leaves the organization, changes role, or fails to re-attest.

**Detection rule:** Daily check against Microsoft Graph for sponsor account state (`accountEnabled`, `assignedLicenses`, manager or department change).

**Remediation:** Initiate sponsor-handoff workflow owned by `agent-365-lifecycle-governance`.

## Cross-solution audit trail

Every drift finding from peer solutions writes back to the originating intake record via schema-backed columns:

```text
INSERT fsi_intakeauditevents
  fsi_requestid = <original fsi_requestid>
  fsi_eventtype = 'PostApprovalDrift_<Sharing|Scope|Access|Lifecycle>'
  fsi_actorupn = '<peer-solution-name>'
  fsi_eventon = utcNow()
  fsi_eventpayloadjson = <peer-solution finding payload>
```

This gives compliance a single evidence trail: the intake decision, sponsor attestation, and subsequent drift events are linked.

## What v0.2.0-preview does not wire

- Real-time drift alerts to sponsor Teams.
- Automatic deletion or revocation of Agent ID on critical drift; use manual Entra admin workflow until a supported delete contract is validated.
- MRM re-tiering when scope expands; Tier-3 to Tier-2 promotion requires manual Compliance review.
