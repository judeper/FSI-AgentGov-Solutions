# CD-ScoreCalculator Flow Update — Automated Assessment Weighting

This document describes the required update to the existing Compliance Dashboard `CD-ScoreCalculator` flow to properly handle automated assessments from Tier 2 governance solutions alongside manual assessments from human assessors.

---

## Background

The `CD-ScoreCalculator` flow runs daily at 6:00 AM UTC and calculates weighted compliance scores per pillar and zone. Currently, it treats all `fsi_controlassessment` records equally. With the integration of Tier 2 solutions, the flow must distinguish between:

- **Automated assessments** — sourced from solution validation (ACV, SSC, AAM, CMM, FUS)
- **Manual assessments** — entered by human assessors during review cycles

## Identification Method

Automated assessments are identified by their `fsi_notes` field content:

```
fsi_notes LIKE 'Automated:%'
```

All automated assessments include notes beginning with `Automated:` followed by the solution name and version. This avoids adding new columns to the existing CD schema.

## Weighting Rules

### Default Behavior (No Change Required)

The simplest approach is to treat automated and manual assessments equally in scoring. Since automated assessments are always current (daily), they naturally reflect the latest compliance state.

**Recommendation:** No weighting change in v1.0.0. Automated assessments have same weight as manual.

### Future Enhancement (v1.1.0+)

If differentiation is desired:

| Assessment Source | Weight | Rationale |
|------------------|--------|-----------|
| Automated (≤ 24h old) | 1.0 | Current validation data |
| Automated (> 24h old) | 0.8 | Stale automated data |
| Manual (≤ 30d old) | 1.0 | Recent human review |
| Manual (> 30d old) | 0.5 | Stale manual assessment |

### Score Calculation Update

Current formula (unchanged for v1.0.0):
```
pillar_score = SUM(control_score * control_weight) / SUM(control_weight)
```

Where:
- `control_score` = `fsi_score` from latest assessment (automated or manual)
- `control_weight` = `fsi_weight` from `fsi_controlmaster`

### Priority Rules

When both automated and manual assessments exist for the same control on the same day:

1. **Automated assessment takes precedence** for score calculation (more current data)
2. **Manual assessment preserved** for audit trail and human override capability
3. If manual assessment is **more restrictive** (lower score), use the manual score (conservative approach)

## Implementation Steps

### v1.0.0 (Current Release)

No changes to CD-ScoreCalculator flow required. The flow already:
1. Queries all assessments grouped by control
2. Uses the latest assessment per control
3. Calculates weighted scores

Automated assessments naturally appear as the latest records since they run daily.

### v1.1.0 (Future)

1. Add filter logic in ScoreCalculator to check `fsi_notes` content
2. Apply age-based weighting per the table above
3. Handle conflict resolution between automated and manual assessments
4. Add `fsi_assessmentsource` column to `fsi_controlassessment` (Choice: 1=Manual, 2=Automated)

---

*Score Calculator Update Guide v2.0.0 — February 2026*
