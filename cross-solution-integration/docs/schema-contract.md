# Schema Contract — Cross-Solution Integration

This document defines the canonical Dataverse option set values and data contracts shared across all FSI Agent Governance solutions. All integration components reference this contract.

---

## Canonical Option Sets

### Zone Classification (`fsi_acv_zone`)

The zone option set classifies governance environments by security posture.

| Value | Label | Description |
|-------|-------|-------------|
| 100000000 | Unclassified | Environments not yet zone-tagged; integration writes no Compliance Dashboard zone when possible |
| 100000001 | Zone 1 — Personal Productivity | Low-risk personal agents; standard M365 controls |
| 100000002 | Zone 2 — Team Collaboration | Team-scoped agents; enhanced controls, approval required |
| 100000003 | Zone 3 — Enterprise Managed | Enterprise-critical agents; maximum controls, change management |

**Owner:** Audit Configuration Validator (ACV) solution defines this global option set (`fsi_acv_zone`). The legacy name `fsi_acvzone` does NOT exist.

**Normalization:** Tier 2 source tables commonly store ACV-style `100000000`-based values. Compliance Dashboard assessments use `1`/`2`/`3` zone values. `IntegrationConfig.psm1` maps both conventions for assessment sync and uses `ConvertTo-AcvZoneValue` when writing ACV `fsi_environmentregistries`.

### Environment Type (`fsi_acv_environmenttype`)

ACV registry writes must use ACV environment-type values: Production `100000000`, Sandbox `100000001`, Developer `100000002`, Trial `100000003`, Default `100000004`. ELM request rows use a different option set for Production and Developer, so map ELM `100000002` Production to ACV `100000000`, and ELM `100000003` Developer to ACV `100000002`. `Register-ProvisionedEnvironment.ps1` defaults to ELM/legacy interpretation and exposes `-EnvironmentTypeFormat Acv` for direct ACV values.

### Severity Classification (`fsi_acv_severity`)

The severity option set classifies validation results by compliance impact.

| Value | Label | Description |
|-------|-------|-------------|
| 100000000 | Passed | All checks met zone requirements |
| 100000001 | Warning | Minor deviations; advisory, no immediate action required |
| 100000002 | GracePeriod | Non-compliant but within grace window (new environments, config changes) |
| 100000003 | Failed | Compliance violation requiring remediation |
| 100000004 | Error | Validation could not complete (connectivity, permission issues) |

**Owner:** Audit Configuration Validator (ACV) solution defines this global option set (`fsi_acv_severity`). The legacy name `fsi_acvseverity` does NOT exist.

**Per-Solution Severity Variants:**
- **ACV, SSC, CAA**: Use the canonical `100000000`-based values directly via this global option set.
- **AAM**: Uses string-based status (`Compliant`, `Warning`, `NonCompliant`, `Critical`) on `fsi_overallstatus` — integration layer maps to canonical severity.
- **CMM, FUS**: Use compliance percentage (`fsi_compliancerate` / `compliantcount`/`totalagents`) — integration layer converts to severity via thresholds.

### Compliance Dashboard Status (`fsi_status`)

The Compliance Dashboard uses its own status option set for control assessments.

| Value | Label | Score | Description |
|-------|-------|-------|-------------|
| 1 | Compliant | 100 | Control fully meets requirements |
| 2 | Partial | 50 | Control partially implemented or minor gaps |
| 3 | Non-Compliant | 0 | Control not implemented or critical gaps |
| 4 | Not Applicable | — | Control not relevant for this zone |

**Nullability:** When `fsi_status` = 4 (Not Applicable), `fsi_score` is set to `null`. The `Map_CMM_Status` expression in the CD-SolutionFeedCollector flow produces `score: null` for this case. If the Dataverse schema for `fsi_controlassessment.fsi_score` is changed to non-nullable, the flow's `Upsert_CMM_Assessment` scope will fail; add an error handler or default value (e.g., `-1`) to handle this scenario.

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

| Solution | Baseline Table | History Table | History EntitySet (REST) | Violation Table |
|----------|---------------|---------------|--------------------------|-----------------|
| ACV | — | `fsi_auditvalidationhistory` | `fsi_auditvalidationhistories` | *(not implemented — flagged for ACV roadmap)* |
| SSC | — | `fsi_validationhistory` | `fsi_validationhistories` | `fsi_driftviolation` |
| AAM | `fsi_accessbaseline` | `fsi_accessvalidationhistory` | **`fsi_accessvalidationhistory`** (singular — explicit `EntitySetName` in schema) | `fsi_accessviolation` |
| CMM | `fsi_moderationbaseline` | `fsi_moderationvalidationhistory` | **`fsi_moderationvalidationhistory`** (singular — explicit `EntitySetName` in schema) | `fsi_moderationviolation` |
| FUS | `fsi_fileuploadbaseline` | `fsi_fileuploadvalidationhistory` | `fsi_fileuploadvalidationhistories` | `fsi_fileuploadviolation` |
| CAA | — | `fsi_capolicyvalidationhistory` | `fsi_capolicyvalidationhistories` | `fsi_capolicyviolation` |

> ⚠️ **AAM / CMM are exceptions.** Their schema scripts (`agent-access-monitor/scripts/create_dataverse_schema.py` and `content-moderation-monitor/scripts/create_dataverse_schema.py`) declare an explicit `EntitySetName` equal to the table logical name (singular). All other solutions accept the Dataverse default plural. Hard-coding the wrong plural results in a 404 from the Web API.

> ⚠️ **ACV `fsi_environmentregistry`.** The default plural is `fsi_environmentregistries` (consonant + y → ies). `Register-ProvisionedEnvironment.ps1` uses this form.

> **Microsoft Learn Web API guidance:** Confirm entity set names from the Dataverse service document (`/api/data/v9.2/`) and use `$select` for the columns listed below to reduce payload size and avoid 400 responses from nonexistent columns.

### Per-Solution History Run-Level Columns

| Solution | Status (run) | Timestamp | RunId | Notes |
|----------|--------------|-----------|-------|-------|
| ACV | `fsi_severity` (choice) | `fsi_timestamp` | `fsi_runid` | ACV history uses `fsi_timestamp` |
| SSC | `fsi_severity` (choice) | `fsi_timestamp` | `fsi_runid` | — |
| AAM | `fsi_overallstatus` (string) | `fsi_validationtime` | `fsi_runid` | String status — see mapping in `STATUS_MAPPING.md` |
| CMM | `fsi_overallstatus` (string) **and** `fsi_compliantcount`/`fsi_totalagents` | `fsi_validationtime` | `fsi_runid` | Status derived from rate |
| FUS | `fsi_compliancerate` (% int) | `fsi_validationtime` (also `fsi_runtimestamp`) | `fsi_runid` | Status derived from rate |
| CAA | `fsi_overallseverity` (choice) | `fsi_validationtime` | `fsi_runid` | CAA v2.0.1+ follows standard logical-name convention |

### Validation-Type Filter

The integration layer **does not** filter history rows by `fsi_validationtype`. That column does not exist on ACV, SSC, or CAA history tables. Any historical filter that relies on it must be removed before deploying v2.0.2.

### Violation Tables

The integration **registers run-level evidence only** as of v2.0.2. Per-finding violation rows are no longer exported through `Export-UnifiedComplianceEvidence.ps1` — they remain visible in each owning solution's own dashboards. This avoids exposing PII (agent names, owner UPNs) in the consolidated package and prevents drift between mutable violation records and immutable evidence hashes.

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

**Verification:** `Test-UnifiedEvidenceIntegrity.ps1` validates SHA-256 hash of evidence file matches companion hash file.

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

*Schema Contract v2.0.2 — May 2026*
