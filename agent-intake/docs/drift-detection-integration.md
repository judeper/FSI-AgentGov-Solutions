# Drift-detection integration — wiring agent-intake to peer solutions

Once an approved intake request is handed off, ongoing governance moves to the existing solution suite. The v0.2.0-preview live contract covered the Express path only; this v1.0.0-preview update keeps those wire fields intact and adds Standard / Full reviewer evidence, path-aware drift signals, and a machine-readable payload schema for downstream consumers.

## Why this matters

The intake decision is a point-in-time attestation. A maker can approve an agent today and later share it firm-wide, expand data sources, or attach it to a higher-risk connector. Peer solutions detect that drift and either remediate or escalate; the path now matters because Standard and Full approvals carry broader reviewer evidence and tighter re-review thresholds.

## Per-path handoff contract

| Path | Reviewer attestation chain | Handoff payload version | Required additional fields | Drift signal escalation policy |
|---|---|---|---|---|
| Express | 1 total attestation (sponsor only; `reviewerAttestations` stays empty) | `0.2.0-preview` live contract, `1.0.0-preview` when additive fields are emitted | `payloadVersion`, `pathUsed`, `sponsor`, `policyVersion`, `retentionLabel`, `originIntakeId`, `entraAgentId` | Notify maker + sponsor; preserve the finding on the originating intake record |
| Standard | 2-3 reviewer attestations (`InfoSec` + `Privacy`, with `Compliance` added when `fsi_t4handlesnpi` is positive) plus sponsor evidence | `1.0.0-preview` | Express fields plus `reviewerAttestations[]`, `connectorAllowlist[]`, `mrmHandoffStatus`, and named team / department scope carried in `fsi_intakedecisionlog.fsi_decisionpackjson` or `fsi_declaredteamscopejson` (field added by foundation-schema workstream) | Notify the reviewer board; keep maker + sponsor on the evidence trail |
| Full | 5 reviewer attestations (`InfoSec`, `Privacy`, `Compliance`, `Legal`, `MRM`) plus sponsor evidence | `1.0.0-preview` | Standard fields plus full reviewer quorum evidence, Tier-1 audience boundary carried in `fsi_intakedecisionlog.fsi_decisionpackjson`, and any reviewer conditions in `reviewerAttestations[].conditionsText` | Notify the reviewer board + MRM and escalate CRITICAL findings to InfoSec on-call; auto-revoke only when the customer's policy allows |

## Handoff contract

When Flow 3 creates the registry shell row in `agent-registry-automation`, it should stamp these values where the registry schema supports them. If a peer solution has not yet added a dedicated column, include the value in the registry evidence JSON and decision-pack JSON rather than inventing snake_case Dataverse columns.

> **Note:** The table below remains the simple v0.2.0-preview summary. Path-specific additions for Standard and Full are documented in [Per-path handoff contract](#per-path-handoff-contract). Existing field names stay unchanged to preserve the live Express-path contract.

| Suggested logical name | Value from intake | Used by |
|---|---|---|
| `fsi_originintakeid` | `fsi_intakerequestid` or `fsi_requestid` | All peers (audit trail) |
| `fsi_intaketier` | `fsi_risktier` | scope-drift-monitor, agent-access-monitor |
| `fsi_intakezone` | `fsi_zone` | unrestricted-agent-sharing-detector |
| `fsi_declareddatasourcesjson` | `fsi_declareddatasourcesjson` | scope-drift-monitor |
| `fsi_declaredaudience` | `fsi_intendedaudience` | unrestricted-agent-sharing-detector |
| `fsi_sponsorupn` | `fsi_sponsorupn` | agent-365-lifecycle-governance |
| `fsi_entraagentid` | Microsoft Entra Agent ID service principal ID | All peers |

## Path-aware drift signals

### 1. `unrestricted-agent-sharing-detector`

**Dataverse fields read:** Registry `fsi_originintakeid`, `fsi_declaredaudience`, and `fsi_intakezone`; intake source-of-truth `fsi_intakerequest.fsi_pathused`, `fsi_intakerequest.fsi_intendedaudience`, and `fsi_intakedecisionlog.fsi_decisionpackjson`; named team or department scope from `fsi_declaredteamscopejson` (field added by foundation-schema workstream) when Standard / Full routing binds access to a specific group.

- **Express-path rule:** When the detector finds an agent shared with everyone in the firm but `fsi_declaredaudience` is `Just me`, `My team`, or `My department`, raise a High severity finding tagged `OriginIntake: Express-path overshare`.
- **Standard-path rule:** Compare actual share targets against the team or department boundary recorded in `fsi_intakedecisionlog.fsi_decisionpackjson` and, when available, `fsi_declaredteamscopejson` (field added by foundation-schema workstream). A share that expands from the declared team to another team, department, or tenant-wide audience remains High and routes to the reviewer board.
- **Full-path rule:** Treat any post-approval audience expansion beyond the declared Tier-1 audience in `fsi_declaredaudience` and `fsi_intakedecisionlog.fsi_decisionpackjson` as CRITICAL. If the customer's sharing policy allows automatic rollback, revoke first and then notify the reviewer board + MRM + InfoSec on-call.

### 2. `scope-drift-monitor`

**Dataverse fields read:** Registry `fsi_originintakeid`, `fsi_intaketier`, and `fsi_declareddatasourcesjson`; intake source-of-truth `fsi_intakerequest.fsi_pathused`, `fsi_intakerequest.fsi_dataresidencycountry`, `fsi_intakerequest.fsi_policyversionapplied`, and `fsi_intakedecisionlog.fsi_decisionpackjson`; connector baseline from `fsi_connectorallowlistjson` (field added by foundation-schema workstream) when the Standard / Full decision pack separates connectors from the broader data-source JSON.

- **Express-path rule:** Compare runtime data-access telemetry against `fsi_declareddatasourcesjson`. Any new connector triggers a finding.
- **Standard-path rule:** Compare runtime telemetry against both `fsi_declareddatasourcesjson` and the broader connector baseline in `fsi_connectorallowlistjson` (field added by foundation-schema workstream) or `fsi_intakedecisionlog.fsi_decisionpackjson`. A new connector, site, table, or API outside the declared team-scope baseline is a High finding routed to the reviewer board.
- **Full-path rule:** Any access outside the approved connector allowlist, declared data-source set, or approved residency boundary in `fsi_intakerequest.fsi_dataresidencycountry` / `fsi_intakedecisionlog.fsi_decisionpackjson` is CRITICAL. If the customer's policy allows automatic containment, suspend the expanded path first and then notify the reviewer board + MRM + InfoSec on-call.

### 3. `agent-access-monitor`

**Dataverse fields read:** Registry `fsi_originintakeid`, `fsi_intaketier`, and `fsi_entraagentid`; intake source-of-truth `fsi_intakerequest.fsi_pathused`, `fsi_intakerequest.fsi_targetenvironmentid`, `fsi_intakerequest.fsi_targetenvironmentname`, and `fsi_intakedecisionlog.fsi_decisionpackjson`; connector-to-permission baseline from `fsi_connectorallowlistjson` (field added by foundation-schema workstream) when the approval board narrowed access to named connectors or Graph scopes.

- **Express-path rule:** Compare current Agent ID service principal permissions (`appRoleAssignments` and `oauth2PermissionGrants`) against the snapshot taken at handoff. Any new privileged role triggers a finding.
- **Standard-path rule:** Treat any post-approval permission grant that falls outside the approved environment, connector allowlist, or reviewer conditions in `fsi_intakedecisionlog.fsi_decisionpackjson` as a High finding routed to the reviewer board.
- **Full-path rule:** Treat any new privileged role, application permission, or environment move beyond the approved Tier-1 baseline as CRITICAL. If the customer's policy allows automatic rollback, disable or revoke the newly granted access first and then notify the reviewer board + MRM + InfoSec on-call.

### 4. `agent-365-lifecycle-governance`

**Dataverse fields read:** Registry `fsi_originintakeid`, `fsi_sponsorupn`, and `fsi_entraagentid`; intake source-of-truth `fsi_intakerequest.fsi_pathused`, `fsi_intakerequest.fsi_policyversionapplied`, `fsi_intakesponsorship.fsi_attestedon`, `fsi_intakesponsorship.fsi_renderedcardhash`, `fsi_intakereview.fsi_reviewerrole`, `fsi_intakereview.fsi_reviewerupn`, `fsi_intakereview.fsi_reviewoutcome`, `fsi_intakereview.fsi_completedon`, `fsi_intakeapproval.fsi_approverrole`, `fsi_intakeapproval.fsi_approverupn`, `fsi_intakeapproval.fsi_decisionoutcome`, `fsi_intakeapproval.fsi_decidedon`, `fsi_intakeapproval.fsi_decisioncontexthash`, and `fsi_intakedecisionlog.fsi_retentionlabelapplied`; MRM completion state from `fsi_mrmhandoffstatus` (field added by foundation-schema workstream) when Standard / Full routing requires downstream model-governance evidence.

- **Express-path rule:** Daily check against Microsoft Graph for sponsor account state (`accountEnabled`, `assignedLicenses`, manager or department change). If the sponsor leaves the organization or loses the required role, initiate the sponsor-handoff workflow owned by `agent-365-lifecycle-governance`.
- **Standard-path rule:** If the sponsor departs, changes supervisory role, or misses a required re-confirm, route the case to the reviewer board and preserve the full sponsor + reviewer evidence chain in the lifecycle finding.
- **Full-path rule:** If the sponsor chain breaks, a required reviewer attestation becomes stale, or `fsi_mrmhandoffstatus` remains `Pending` / `Failed` beyond the firm's grace period, raise a High or CRITICAL lifecycle finding. Notify the reviewer board + MRM, and escalate to InfoSec on-call when the agent no longer has an accountable owner or a valid review quorum.

## Multi-reviewer attestation chain

Express approvals continue to carry only the sponsor attestation. Standard and Full approvals add a `reviewerAttestations[]` array in the registry handoff, while the `agent-intake` source-of-truth remains the combination of `fsi_intakereview`, `fsi_intakeapproval`, `fsi_intakesponsorship`, and `fsi_intakedecisionlog`. This preserves proportional FINRA Rule 3110 supervisory evidence in the same payload downstream drift detectors consume.

Each reviewer attestation carries `role`, `upn`, `decidedOnUtc`, `decisionPackHash`, and `conditionsText`. Drift detectors should preserve the full chain unchanged in any finding payload, remediation ticket, or escalation message so the receiving reviewer can see who approved the original request and under what conditions. The machine-readable shape is defined in [`../templates/drift-handoff-payload-schema.json`](../templates/drift-handoff-payload-schema.json).

## Quorum-aware modification cutoff

ADR-009 still governs the change split: trigger-question edits are major, descriptive edits are minor. For Standard and Full, the re-review target is now quorum-aware rather than sponsor-only.

| Change type | Express | Standard | Full |
|---|---|---|---|
| Trigger-question change (ADR-009 major) | Fresh classification, new sponsor card, and new routing | Fresh full-quorum re-review; prior reviewer evidence becomes historical only | Fresh full-quorum re-review; prior five-reviewer quorum becomes historical only |
| Descriptive change (ADR-009 minor) | Sponsor re-confirm only | Sponsor + InfoSec re-confirm | Sponsor + InfoSec + Privacy re-confirm |

Drift detectors that observe post-approval modifications should route according to this table. If a nominally descriptive change expands audience, connector allowlist, residency boundary, or reviewer conditions, treat it as a major change and require a fresh quorum.

## JSON Schema for the handoff payload

Use [`../templates/drift-handoff-payload-schema.json`](../templates/drift-handoff-payload-schema.json) as the machine-readable contract for the registry handoff payload. The schema uses JSON Schema Draft 2020-12, keeps the v0.2.0-preview live field names intact, and adds the Standard / Full contract fields described above. Downstream drift detectors are encouraged, but not required for v1.0.0-preview, to validate the payload at ingestion so contract drift is detected early rather than after remediation routing begins.

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

This gives compliance a single evidence trail: the intake decision, sponsor attestation, reviewer quorum where present, and subsequent drift events are linked. For Standard and Full, include `payloadVersion`, `pathUsed`, `sponsor`, and `reviewerAttestations` in `fsi_eventpayloadjson` or an attached decision-pack reference rather than collapsing the finding to a single reviewer name.

## What v0.2.0-preview does not wire

- Real-time drift alerts to sponsor Teams.
- Automatic deletion or revocation of Agent ID on critical drift; use manual Entra admin workflow until a supported delete contract is validated.
- MRM re-tiering when scope expands; Tier-3 to Tier-2 promotion requires manual Compliance review.
