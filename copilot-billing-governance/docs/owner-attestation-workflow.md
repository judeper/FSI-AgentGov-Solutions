# Owner-Attestation Workflow (manifest-opaque FNF agents)

This workflow covers the FNF (Find-No-Filter) declarative agents whose `declarativeAgent.json`
manifest **cannot be read** by any supported admin API or telemetry signal. For those agents the
only path to a People (Org Chart & Profile) capability determination is **manual owner
attestation**. The attested determinations are converted into the same capability-row input the
FNF People-Sweep lens ([`Get-FnfPeopleSweepReport.ps1`](../scripts/Get-FnfPeopleSweepReport.ps1))
consumes for manifest-detected agents, so attestation-covered agents flow into one report.

This process **supports compliance with** oversight of Copilot agent reach (framework controls
**3.5**, **1.18**, **1.14**) and with the record-keeping expectations of **FINRA Rule 4511** and
**SEC Rule 17a-3/17a-4** by producing a dated, attributable evidence record of the capability
review. It does not by itself satisfy any regulation; organizations should verify the result
against their specific obligations and retain the attestation records per their schedule.

---

## Why attestation is necessary (the coverage gap)

The manifest-acquisition spike (`SPIKE-manifest-acquisition`) and the people-telemetry research
(`R6-people-telemetry-signal`) established two findings:

1. **No supported, scalable admin API returns the parsed `capabilities[]` array** (or the raw
   `declarativeAgent.json`) for tenant-deployed declarative agents. Microsoft Graph
   `teamsApp` / `teamsAppDefinition` expose metadata only.
2. **No documented runtime telemetry signal** (Purview Audit, Defender XDR, Application Insights,
   Microsoft Graph activity) identifies that a declarative agent's People capability fired.

The realistic automated, capability-readable coverage is therefore only the source-controlled /
Toolkit-published slice. Agent-Builder "shared by creator" agents - the long tail - are
**manifest-opaque** and require per-owner attestation.

### Coverage tiers

| Tier | Population (typical, **unmeasured** - validate per tenant) | How People-capability is determined | `peopleCapableSource` |
|---|---|---|---|
| **Manifest-detected** | ~5-20% (source-controlled / Toolkit-published) | Automated static scan of `declarativeAgent.json` `capabilities[]` by `detect_people_capability.py` | `manifest` |
| **Attestation-covered** | the responding share of the opaque tier | Owner confirms (or denies) the "Reference org chart and profile info" capability; converted by `Convert-AttestationToCapabilityRows.ps1` | `attested` |
| **Unknown (residual)** | the non-responding remainder of the opaque tier | Not determinable today | (no row emitted) |

> The percentages are industry-typical estimates, not measurements. Validate the actual provenance
> mix in the FNF population (Agent Registry CSV) before quoting any number in a deliverable.

---

## The workflow

### Step 1 - Build the owner list from the Agent Registry CSV export

The **Microsoft 365 Agent Registry** (M365 admin center) is the only surface that enumerates all
agent provenance types tenant-wide, **including** Agent-Builder "shared by creator" agents, and it
offers a **CSV export** that includes the agent's owner. This export is the source of the owner
outreach list and the real agent ids.

- Export the Agent Registry CSV (Microsoft 365 admin; see Microsoft's Agent Registry
  documentation). The export can take time at scale.
- Each row carries the agent's identity, owner, channel/platform, and status.
- Cross-reference against the manifest-detected set (the `detect_people_capability.py` artifact)
  and remove agents already covered there. The residual is the **opaque tier** to attest.
- **Key on the real agent id.** The agent id used downstream is the Registry's real bot / Entra
  Agent ID - never the provisional manifest stem `declarativeAgent` (which is identical across
  distinct Toolkit packages and must never be used as a join key).

### Step 2 - Outreach to owners

For each opaque agent, contact the owner (from the CSV) and ask them to confirm **one** of:

- **Confirm the toggle.** Open the agent in Agent Builder and report whether **"Reference org
  chart and profile info"** (the People capability) is **enabled** or **not enabled**; or
- **Export the package.** Use Agent Builder's Export to produce the app `.zip` and return it (the
  `declarativeAgent.json` inside can then be scanned by `detect_people_capability.py`, which moves
  the agent into the **manifest-detected** tier instead).

Keep the request to a single, unambiguous yes/no question plus an optional package export. Record
the responder (owner UPN), the response timestamp, and a ticket/survey id for traceability.

### Step 3 - Intake the responses

Collect responses into one of the response templates:

- [`templates/owner-attestation-responses.sample.csv`](../templates/owner-attestation-responses.sample.csv)
- [`templates/owner-attestation-responses.sample.json`](../templates/owner-attestation-responses.sample.json)

| Column / key | Required | Meaning |
|---|---|---|
| `agentId` | **yes** | The real Agent Registry bot / agent id. Not a provisional stem. |
| `peopleCapable` | **yes** | Owner's answer: `yes` / `no` (also `y`/`n`, `true`/`false`, `1`/`0`, `enabled`/`disabled`). |
| `agentName` | no | Display name (defaults to the id). |
| `environmentId` | no | Power Platform environment id, when known. |
| `attestedBy` | no | Owner UPN who attested. |
| `attestedAt` | no | ISO 8601 timestamp of the response. |
| `attestationId` | no | Ticket / survey response id for traceability. |
| `notes` | no | Free-text context. |

### Step 4 - Convert responses to capability rows

Run the converter to produce a capability artifact shape-compatible with
`detect_people_capability.py`:

```powershell
.\scripts\Convert-AttestationToCapabilityRows.ps1 `
    -ResponsePath .\owner-attestation-responses.csv `
    -OutputPath  .\cai-people-attested.json
```

The converter is defensive (mirroring the lens's never-silent posture):

- An **empty agent id**, or the provisional stem `declarativeAgent`, is **rejected**.
- An **unrecognized** `peopleCapable` answer is **rejected** - it is never silently coerced to
  "no" (which would under-report People-capable agents).
- **Conflicting** duplicate responses for one agent (one `yes`, one `no`) are **rejected**;
  agreeing duplicates are collapsed.
- All row errors are reported together so the response file can be fixed in one pass.

By default a `no` response is emitted as a declared-but-disabled row (`fsi_isenabled = false`) so
the artifact is a complete record of the campaign; the lens skips disabled rows. Use
`-PeopleCapableOnly` to emit only affirmative rows.

### Step 5 - Feed the attested artifact into the FNF lens

Pass the attested artifact to the People-Sweep lens exactly as a manifest artifact:

```powershell
.\scripts\Get-FnfPeopleSweepReport.ps1 `
    -CapabilityArtifactPath .\cai-people-attested.json `
    -AudienceArtifactPath   .\cai-audience.json `
    -AgentMasterPath        .\agent-master.json `
    -BillingPolicyInputPath .\billing-policies.json `
    -GraphAccessToken       $graphToken `
    -ReportOutputPath       .\fnf-people-sweep-attested.json
```

Each attested agent appears in the report with:

- `peopleCapable = true`, `peopleCapableSource = "attested"`;
- `coverageStatus = "Partial"` carrying the gap **`manifest-opaque-attestation-pending`** - an
  attested determination is deliberately **never reported as `Complete`**, because it rests on an
  owner's statement rather than a manifest read;
- per-user blocked scoring when the audience resolves (same engine path as manifest-detected
  agents); `blockedUserCount = null` (never a silent `0`) when the audience or engine output is
  not computable.

You can also merge the attested rows with the manifest-detected artifact's `features[]` /
`agents[]` before the lens run if a single combined input is preferred; the lens de-duplicates on
the real agent id.

### Step 6 - Cadence and SLA (decide late, set per campaign)

Durations are intentionally left to the campaign owner rather than hard-coded; suggested starting
points, to be tuned against the actual population and response rate:

- **Initial outreach window:** ~10 business days to first response.
- **Reminders:** at least two, spaced across the window.
- **Re-attestation cadence:** refresh on a recurring basis (for example quarterly) and on a
  material change to the agent, because a manifest-opaque agent can have its People toggle changed
  at any time. Treat an attestation older than the cadence as stale and re-collect.
- **Escalation:** non-responding owners after the window are escalated per the organization's
  agent-governance policy; their agents remain in the **Unknown (residual)** tier until answered.

Track outreach status (sent / responded / escalated / converted) in the campaign's own tracker;
the converter consumes only the final responses.

---

## Coverage-statement language for the deliverable

Use this FSI-compliant wording (no "ensures" / "guarantees" / "will prevent" / "eliminates risk")
when stating coverage in the deliverable. Fill the bracketed counts from the Agent Registry
reconciliation and the converter/lens summaries.

> **People-capability coverage.** Of **[N]** declarative agents in scope, **[A]** (~[a]%) were
> determined by automated manifest scan (`peopleCapableSource = manifest`), **[B]** (~[b]%) by
> documented owner attestation (`peopleCapableSource = attested`), and **[C]** (~[c]%) remain
> **undetermined** because their manifest is not readable by any supported API or telemetry and
> the owner has not yet attested. Automated manifest coverage is bounded by the share of agents
> whose source is controlled or Toolkit-published (typically a minority of the population).
> Attested determinations rest on owner statements, are reported as **Partial** coverage
> (`manifest-opaque-attestation-pending`), and are **not** equivalent to a verified manifest read.
> This review **supports compliance with** oversight of Copilot agent reach (controls 3.5, 1.18,
> 1.14) and with the record-keeping expectations of FINRA Rule 4511 and SEC Rule 17a-3/17a-4; it
> does not by itself satisfy any regulation. Organizations should verify results against their
> specific obligations and re-attest on a defined cadence.

### Honest framing notes

- State automated-manifest coverage as a **range or a measured count**, not a single confident
  figure - the typical ~5-20% is an estimate until the Registry reconciliation is done.
- Always distinguish the three tiers; never roll "attested" into "detected".
- Never present a `0 blocked` headline for an agent without checking its `coverageGaps`; the lens
  reports `null` (not `0`) whenever the blocked count is not computable.

---

## Related files

- [`scripts/Convert-AttestationToCapabilityRows.ps1`](../scripts/Convert-AttestationToCapabilityRows.ps1) - the converter.
- [`scripts/Get-FnfPeopleSweepReport.ps1`](../scripts/Get-FnfPeopleSweepReport.ps1) - the lens that consumes the attested rows.
- [`templates/owner-attestation-responses.sample.csv`](../templates/owner-attestation-responses.sample.csv) / [`.json`](../templates/owner-attestation-responses.sample.json) - response templates.
- [`tests/ConvertAttestationToCapabilityRows.Tests.ps1`](../tests/ConvertAttestationToCapabilityRows.Tests.ps1) - converter tests.
