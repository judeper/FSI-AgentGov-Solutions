# Status Mapping Reference — Cross-Solution Integration

This document defines the per-solution logic for translating Tier 2 governance solution validation results into Compliance Dashboard `fsi_controlassessment` records.

---

## Solution-to-Control Mapping

| Solution | Control ID(s) | Control Name(s) | Assessment Frequency |
|----------|--------------|------------------|---------------------|
| ACV | 1.7 | Comprehensive Audit Logging and Compliance | Daily |
| SSC | 1.23 | Step-Up Authentication for Agent Operations | Daily |
| SSC | 1.11 | Conditional Access and Phishing-Resistant MFA | Daily |
| AAM | 3.8 | Copilot Hub and Governance Dashboard | Daily |
| CMM | 1.8 | Runtime Protection and External Threat Detection | Daily |
| FUS | 1.14 | Data Minimization and Agent Scope Control | Daily |
| CAA | 1.11 | Conditional Access and Phishing-Resistant MFA | Daily |
| CAA | 1.23 | Step-Up Authentication for Agent Operations | Daily |
| CAA | 1.18 | RBAC and Least-Privilege for Agent Identities | Daily |

**Total:** 6 solutions → 9 control assessments (SSC and CAA share Controls 1.11 and 1.23)

---

## Status Translation Logic

### ACV → Control 1.7

**Source table:** `fsi_auditvalidationhistories`
**Source field:** `fsi_severity` (Choice: 100000000-based)
**Query:** Latest record ordered by `fsi_timestamp desc` (ACV uses `fsi_timestamp`, not `fsi_validationtime`)

| ACV Severity | CD Status | CD Score | Logic |
|-------------|-----------|----------|-------|
| 100000000 (Passed) | 1 (Compliant) | 100 | All audit checks passed |
| 100000001 (Warning) | 2 (Partial) | 50 | Minor audit gaps (e.g., retention below recommended) |
| 100000002 (GracePeriod) | 2 (Partial) | 50 | New environment within grace window |
| 100000003 (Failed) | 3 (Non-Compliant) | 0 | Critical audit configuration failure |
| 100000004 (Error) | 3 (Non-Compliant) | 0 | Validation could not complete |

**Score formula:** Direct mapping based on worst-case severity from latest orchestrator run.

---

### SSC → Controls 1.23, 1.11

**Source table:** `fsi_validationhistories`
**Source field:** `fsi_severity` (Choice: 100000000-based)
**Query:** Latest record ordered by `fsi_timestamp desc`

SSC validates 6 dimensions. For dashboard purposes, the orchestrator-level severity is used.

**Control 1.23 (Step-Up Authentication):**
Maps dimensions: SessionControls, AuthStrength, PIM

| SSC Severity | CD Status | CD Score |
|-------------|-----------|----------|
| 100000000 (Passed) | 1 (Compliant) | 100 |
| 100000001 (Warning) | 2 (Partial) | 50 |
| 100000002 (GracePeriod) | 2 (Partial) | 50 |
| 100000003 (Failed) | 3 (Non-Compliant) | 0 |
| 100000004 (Error) | 3 (Non-Compliant) | 0 |

**Control 1.11 (Conditional Access and MFA):**
Same mapping — SSC orchestrator covers both controls. Both controls get the same assessment status from each SSC run.

---

### AAM → Control 3.8

**Source table:** `fsi_accessvalidationhistory` *(singular entity set)*
**Source field:** `fsi_overallstatus` (String)
**Query:** Latest record ordered by `fsi_validationtime desc`

| AAM Status | CD Status | CD Score | Logic |
|-----------|-----------|----------|-------|
| Compliant | 1 (Compliant) | 100 | All environments meet zone access policies |
| Warning | 2 (Partial) | 50 | Some environments in grace period or minor gaps |
| NonCompliant | 3 (Non-Compliant) | 0 | Environments failing access governance checks |
| Critical | 3 (Non-Compliant) | 0 | Critical access violations detected |

**Note:** AAM uses string-based status, not Choice values. Integration layer performs case-insensitive string matching.

---

### CMM → Control 1.8

**Source table:** `fsi_moderationvalidationhistory` *(singular entity set)*
**Source fields:** `fsi_compliantcount` (Integer), `fsi_totalagents` (Integer)
**Query:** Latest record ordered by `fsi_validationtime desc`

**Compliance Rate Calculation:**
```
compliance_rate = (fsi_compliantcount / fsi_totalagents) * 100
```

| Compliance Rate | CD Status | CD Score | Logic |
|----------------|-----------|----------|-------|
| 100% | 1 (Compliant) | 100 | All agents meet zone moderation requirements |
| ≥ 80% | 2 (Partial) | 80–99 | Most agents compliant, some gaps |
| < 80% | 3 (Non-Compliant) | 0–79 | Significant moderation policy gaps |
| 0 agents | 4 (Not Applicable) | — | No agents to validate |

**Score formula:** `fsi_score = compliance_rate` (direct percentage, not threshold-based). The `fsi_status` derivation uses thresholds above; `fsi_score` preserves the actual rate for trend analysis.

---

### FUS → Control 1.14

**Source table:** `fsi_fileuploadvalidationhistories`
**Source field:** `fsi_compliancerate` (Decimal)
**Query:** Latest record ordered by `fsi_validationtime desc`

| Compliance Rate | CD Status | CD Score | Logic |
|----------------|-----------|----------|-------|
| 100% | 1 (Compliant) | 100 | All agents meet zone file upload policy |
| ≥ 80% | 2 (Partial) | 80–99 | Most agents compliant, some with unauthorized uploads |
| < 80% | 3 (Non-Compliant) | 0–79 | Significant file upload policy violations |

**Score formula:** Same as CMM — direct compliance rate for `fsi_score`, threshold-based for `fsi_status`.

---

### CAA → Controls 1.11, 1.23, 1.18

**Source table:** `fsi_capolicyvalidationhistories`
**Source field:** `fsi_overallseverity` (Choice: 100000000-based)
**Query:** Latest record ordered by `fsi_validationtime desc`

| CAA Severity | CD Status | CD Score | Logic |
|-------------|-----------|----------|-------|
| 100000000 (Passed) | 1 (Compliant) | 100 | All CA policies meet zone requirements |
| 100000001 (Warning) | 2 (Partial) | 50 | Minor policy gaps (e.g., report-only mode) |
| 100000002 (GracePeriod) | 2 (Partial) | 50 | New environment within grace window |
| 100000003 (Failed) | 3 (Non-Compliant) | 0 | CA policy compliance failure |
| 100000004 (Error) | 3 (Non-Compliant) | 0 | Validation could not complete |

**Control Mapping:**

| Control | Role | Notes |
|---------|------|-------|
| 1.11 | Primary | Dual-feed with SSC (worst-of-two resolution) |
| 1.23 | Secondary | CA session controls complement |
| 1.18 | Secondary | RBAC policy complement |

**Dual-Feed Resolution (Control 1.11):**
SSC validates session security (inactivity timeouts, persistent browser). CAA validates CA policy compliance (MFA enforcement, break-glass exclusions, policy drift). Both are complementary compliance signals. The Compliance Dashboard uses worst-of-two status: if either solution reports Non-Compliant, Control 1.11 shows Non-Compliant.

**Implementation Note — Dual-Feed Resolution Strategy Differences:**
The CD-SolutionFeedCollector flow performs inline worst-of-two merge during the CAA upsert action (comparing the incoming CAA status with the existing SSC-written assessment in a single expression). `Sync-SolutionAssessments.ps1` uses a separate post-processing pass: it first writes SSC and CAA assessments independently, then queries all same-day assessments for Controls 1.11 and 1.23 and overwrites them with the worst-of-two result. Both strategies produce the same final state, but the script briefly writes CAA-only assessments before the post-processing overwrite. If the script is interrupted between the individual writes and the post-processing pass, the dashboard may temporarily show a non-worst-of-two value.

---

## Assessment Record Structure

When creating/updating `fsi_controlassessment` records:

```json
{
  "fsi_controlmasterid@odata.bind": "/fsi_controlmasters({control_guid})",
  "fsi_assessmentdate": "2026-02-10T06:00:00Z",
  "fsi_status": 1,
  "fsi_score": 100,
  "fsi_notes": "Automated: Audit Configuration Validator v1.0.4. Run ID: {guid}. Status: Compliant. Source: fsi_auditvalidationhistories, Timestamp: 2026-02-10T06:00:00.000Z.",
  "fsi_nextreviewdate": "2026-02-11T06:00:00Z",
  "fsi_evidencecount": 1
}

```

> **Note:** The `fsi_evidencecount` field is a placeholder. Neither the CD-SolutionFeedCollector flow nor `Sync-SolutionAssessments.ps1` currently sets this field; the evidence pipeline (`evidence/` directory) is not yet implemented. Remove or update this value once evidence registration is operational.

**Key behaviors:**
- **Upsert logic:** Match on `fsi_controlmasterid` + date. Create new if no same-day record exists; update if exists.
- **Zone handling:** If a source validation row includes `fsi_zone`, normalize ACV-style values (`100000001..100000003`) to Compliance Dashboard zone values (`1..3`) before writing `fsi_controlassessments`. If the source omits zone, write a run-level assessment without `fsi_zone`.
- **Notes field:** Include solution name, version, run ID, and raw status for audit trail.
- **Next review date:** Set to tomorrow (daily feed cadence).

---

## Evidence Registration

When Tier 2 solutions export evidence packages, register them in `fsi_complianceevidence`:

```json
{
  "fsi_name": "ACV Evidence Export — 2026-02-10",
  "fsi_controlassessmentid@odata.bind": "/fsi_controlassessments({assessment_guid})",
  "fsi_evidencetype": 5,
  "fsi_evidencedescription": "Automated evidence from Audit Configuration Validator. SHA-256 verified.",
  "fsi_collecteddate": "2026-02-10T06:00:00Z",
  "fsi_hash": "a1b2c3d4..."
}
```

**Evidence Type:** Always `5` (Test Result) for automated solution evidence.

---

*Status Mapping Reference v2.0.2 — May 2026*
