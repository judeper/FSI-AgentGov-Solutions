# Schema Contract — Cross-Solution Integration

This document defines the canonical Dataverse option set values and data contracts shared across all FSI Agent Governance solutions. All integration components reference this contract.

---

## Canonical Option Sets

### Zone Classification (`fsi_acv_zone`)

The zone option set classifies governance environments by security posture.

| Value | Label | Description |
|-------|-------|-------------|
| 1 | Zone 1 — Personal Productivity | Low-risk personal agents; standard M365 controls |
| 2 | Zone 2 — Team Collaboration | Team-scoped agents; enhanced controls, approval required |
| 3 | Zone 3 — Enterprise Managed | Enterprise-critical agents; maximum controls, change management |

**Owner:** Audit Configuration Validator (ACV) solution defines this global option set.

**Normalization Note:** Some solutions (ACV, SSC) may use internal values `100000001`, `100000002`, `100000003` for zone storage. The integration layer normalizes these to `1`, `2`, `3` via `Get-CanonicalZoneValue` in `IntegrationConfig.psm1`. All cross-solution queries and mappings use the canonical 1/2/3 values.

### Severity Classification (`fsi_acv_severity`)

The severity option set classifies validation results by compliance impact.

| Value | Label | Description |
|-------|-------|-------------|
| 1 | Passed | All checks met zone requirements |
| 2 | Warning | Minor deviations; advisory, no immediate action required |
| 3 | GracePeriod | Non-compliant but within grace window (new environments, config changes) |
| 4 | Failed | Compliance violation requiring remediation |
| 5 | Error | Validation could not complete (connectivity, permission issues) |

**Owner:** Audit Configuration Validator (ACV) solution defines this global option set.

**Per-Solution Severity Variants:**
- **ACV, SSC**: Use canonical 1-5 values directly
- **AAM**: Uses string-based status (`Compliant`, `Warning`, `NonCompliant`, `Critical`) — integration layer maps to canonical severity
- **CMM, FUS**: Use compliance percentage — integration layer converts to severity via thresholds

### Compliance Dashboard Status (`fsi_status`)

The Compliance Dashboard uses its own status option set for control assessments.

| Value | Label | Score | Description |
|-------|-------|-------|-------------|
| 1 | Compliant | 100 | Control fully meets requirements |
| 2 | Partial | 50 | Control partially implemented or minor gaps |
| 3 | Non-Compliant | 0 | Control not implemented or critical gaps |
| 4 | Not Applicable | — | Control not relevant for this zone |

**Owner:** Compliance Dashboard (CD) solution defines this option set.

---

## Cross-Solution Table Architecture

### Triple-Table Pattern

Every Tier 2 solution follows a consistent 3-table architecture:

| Table Purpose | Naming Convention | Ownership | Mutability |
|--------------|-------------------|-----------|------------|
| Baseline | `fsi_{solution}_baseline` | User-owned | Mutable (deactivate old, create new) |
| Validation History | `fsi_{solution}_validationhistory` | Org-owned | **Immutable** (append-only) |
| Violation | `fsi_{solution}_violation` | User-owned | Mutable (resolve, acknowledge) |

### Solution Table Names

| Solution | Baseline Table | History Table | Violation Table |
|----------|---------------|---------------|-----------------|
| ACV | — | `fsi_auditvalidationhistory` | — |
| SSC | — | `fsi_validationhistory` | `fsi_driftviolation` |
| AAM | `fsi_accessbaseline` | `fsi_accessvalidationhistory` | `fsi_accessviolation` |
| CMM | `fsi_moderationbaseline` | `fsi_moderationvalidationhistory` | `fsi_moderationviolation` |
| FUS | `fsi_fileupload_baseline` | `fsi_fileupload_validationhistory` | `fsi_fileupload_violation` |
| CAA | — | `fsi_capolicyvalidationhistory` | `fsi_capolicyviolation` |

### Correlation

All solutions correlate records via `fsi_runid` — a logical GUID generated per validation run. This is a string field, not a Dataverse lookup relationship.

---

## Evidence Export Contract

All Tier 2 solutions produce evidence packages with identical structure:

```json
{
  "metadata": {
    "exportedAt": "ISO 8601 timestamp",
    "scope": "Tenant|Environment",
    "exportVersion": "1.0.0",
    "solution": "ACV|SSC|AAM|CMM|FUS|CAA",
    "recordCount": 0
  },
  "summary": {
    "overallStatus": "Passed|Warning|Failed|...",
    "validationsRun": 0,
    "validationsPassed": 0,
    "validationsFailed": 0
  },
  "validations": [],
  "violations": [],
  "baselines": []
}
```

**Companion file:** `{filename}.sha256` containing `{hash}  {filename}` format.

**Verification:** `Test-EvidenceIntegrity.ps1` validates SHA-256 hash of evidence file matches companion hash file.

---

## Connection References

Each solution defines its own connection references (not shared):

| Prefix | Dataverse | Office 365 | Teams |
|--------|-----------|------------|-------|
| ACV | `fsi_cr_dataverse_acv` | `fsi_cr_office365_acv` | `fsi_cr_teams_acv` |
| SSC | `fsi_cr_dataverse_ssc` | `fsi_cr_office365_ssc` | `fsi_cr_teams_ssc` |
| AAM | `fsi_cr_dataverse_aam` | `fsi_cr_office365_aam` | `fsi_cr_teams_aam` |
| CMM | `fsi_cr_dataverse_cmm` | `fsi_cr_office365_cmm` | `fsi_cr_teams_cmm` |
| FUS | `fsi_cr_dataverse_fus` | `fsi_cr_office365_fus` | `fsi_cr_teams_fus` |
| INT | `fsi_cr_dataverse_int` | — | `fsi_cr_teams_int` |

**Integration** uses a single Dataverse connection reference (`fsi_cr_dataverse_int`) that has read access to all solution tables and write access to the Compliance Dashboard tables.

---

*Schema Contract v1.0.0 — February 2026*
