# Option-Set Integer Verification

> **Solution:** Agent Sharing Access Restriction Detector (ASARD)
> **Version:** v2.0.2
> **Scope:** The custom `100000000`-series integers ASARD reads and writes are **not**
> Microsoft schema. They must be **verified in-env** via `GlobalOptionSetDefinitions`
> before any flow or script trusts a hardcoded value — they must not be assumed.

## Principle

ASARD persists and reads several choice/code integers in the publisher `100000000` range.
These are publisher-prefix-namespaced **custom** values. The authoritative source of truth
at runtime is the value Dataverse actually returns from
`GlobalOptionSetDefinitions(Name='<set>')` in the **target environment** — not the number
hardcoded in a script, template, or this repo's generated `docs/dataverse-schema.md`.
Verifying these integers in-env is **required for** correct persistence and evidence
records; it does not by itself satisfy any regulation in isolation.

## Verified in-env value (lab tenant)

The shared zone set `fsi_acv_zone` was verified in the lab tenant via
`GlobalOptionSetDefinitions` as:

| Value | Label |
|---|---|
| 100000000 | Unclassified |
| 100000001 | Zone 1 |
| 100000002 | Zone 2 |
| 100000003 | Zone 3 |

## ✅ Zone-integer reconciliation complete (Coordinator Decision "Option A", 2026-06-13)

An earlier release of this doc disclaimed a pending zone-integer **drift** — the schema script, the
scan persistence path, and the generated `docs/dataverse-schema.md` were once assumed to use a
divergent `0`–`3` numbering for the zone set. **That reconciliation is now closed.** All three surfaces
use the canonical, in-env `fsi_acv_zone` integers, matching the four lab-validated sibling solutions
(FUS, CMM, GAC, ACA) and the live lab-tenant set:

| Surface | `fsi_acv_zone` values (current) |
|---|---|
| `scripts/create_asard_dataverse_schema.py` (option-set definition) | `100000000`–`100000003` (Unclassified, Zone 1, Zone 2, Zone 3) |
| `scripts/governance/Invoke-SharingComplianceScan.ps1` `$zoneMap` (writes `fsi_zone`) | `Zone1=100000001, Zone2=100000002, Zone3=100000003, Unknown=100000000` |
| Generated `docs/dataverse-schema.md` | `100000000`–`100000003` |

Canonical meaning (Zone 1 = Enterprise = most restrictive; Zone 3 = Personal = least restrictive;
Unclassified = fail-closed):

- **Zone 1 (Enterprise) = `100000001` = most restrictive (no group sharing)**
- Zone 2 (Team) = `100000002`
- **Zone 3 (Personal) = `100000003` = least restrictive**
- Unclassified / fail-closed = `100000000`

The schema-script comments now explicitly forbid reverting to `0`–`3`. The portfolio canonical-zone
decision — and the name-classifier behavioral change it carries (enterprise-named environments move to
the strictest tier; personal-named environments move to the least-restrictive tier) — is recorded in
[`LAB-VALIDATION.md`](../LAB-VALIDATION.md#canonical-zone-reconciliation--known-evidence-inversion).
Per-environment integers should still be **verified in-env** via `GlobalOptionSetDefinitions` before any
flow or script trusts a hardcoded value; verification is **required for** correct persistence and does
not by itself satisfy any regulation in isolation.

## Hardcoded `100000000`-series sites to verify

| File | What is hardcoded | Verify against |
|---|---|---|
| `scripts/create_asard_dataverse_schema.py` | `fsi_ASARD_compliancestatus` (`100000000` Compliant … `100000003` Error), `fsi_ASARD_remediationstatus` (`100000000` Pending … `100000004` Failed); `fsi_acv_zone` defined as `100000000`–`100000003` | `GlobalOptionSetDefinitions(Name='fsi_ASARD_compliancestatus')`, `…remediationstatus`, `…fsi_acv_zone` |
| `scripts/governance/Invoke-SharingComplianceScan.ps1` | `fsi_compliancestatus = 100000001` (NonCompliant); `$zoneMap` writes `fsi_zone` as `100000001`–`100000003` (Unknown → `100000000`) | `fsi_ASARD_compliancestatus`, `fsi_acv_zone` |
| `scripts/governance/Export-SharingComplianceEvidence.ps1` | `fsi_severity -eq 100000000` (Critical) and `-eq 100000001` (High) | severity codes (see note below) |
| `templates/adaptive-card-asard-exception-expired.json` | `100000001` (NonCompliant) and `100000002` (Exception) in user-facing card text | `fsi_ASARD_compliancestatus` |

> **Note on `fsi_severity`.** `docs/dataverse-schema.md` declares `fsi_severity` as a plain
> **Integer** column (not a picklist), storing `100000000`=Critical … `100000004`=Informational
> by **convention**. `GlobalOptionSetDefinitions` will not return it, so it is not subject to
> Dataverse renumbering — but the writer (`Get-SeverityCode` in the scan) and the reader
> (`Export-SharingComplianceEvidence.ps1`) must stay consistent on the same convention.

## How to verify in-env

For each global option set, GET its definition and read every `Options[].Value`:

```
GET {DataverseUrl}/api/data/v9.2/GlobalOptionSetDefinitions(Name='fsi_ASARD_compliancestatus')?$select=Name
    &$expand=Options
```

Repeat for `fsi_ASARD_remediationstatus` and `fsi_acv_zone`. Confirm the returned `Value`
integers match the values this repo assumes; where they differ, the in-env value wins and the
assuming surface must be reconciled.

## Authoritative sources

- **Copilot (bot) table reference / Dataverse option-set metadata** —
  https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/bot
- **GlobalOptionSetDefinitions (Dataverse Web API)** —
  https://learn.microsoft.com/power-apps/developer/data-platform/webapi/query-metadata-web-api
