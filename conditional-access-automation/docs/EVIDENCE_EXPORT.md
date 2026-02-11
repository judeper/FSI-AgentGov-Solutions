# Evidence Export Guide

Export CA policy compliance evidence with SHA-256 integrity hashing for regulatory examinations.

## Overview

The evidence export system produces tamper-evident JSON packages containing Conditional Access policy validation results, active violations, and current baselines from the CAA Dataverse solution. Each export includes a companion SHA-256 hash file that supports integrity verification during FINRA/SEC regulatory examinations.

Evidence packages are designed to demonstrate:

- **Policy compliance status** — pass/fail results for each governance zone
- **Violation tracking** — individual policy violations with expected vs. actual values
- **Baseline integrity** — point-in-time policy snapshots with hash verification
- **Audit trail** — immutable validation history with timestamps and operator identity

## Quick Start

### Step 1: Connect to Dataverse

```powershell
# Authenticate to Azure (for Dataverse access token)
Connect-AzAccount -TenantId "<tenant-id>"
```

### Step 2: Export Evidence

```powershell
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence"
```

### Step 3: Verify Integrity

```powershell
.\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidencePath "./evidence/CAA-Evidence-20260210T120000Z.json"
```

---

## Command Reference

### Export-CAAComplianceEvidence.ps1

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-DataverseUrl` | String | *(required)* | Dataverse environment URL (e.g., `https://org.crm.dynamics.com`) |
| `-OutputPath` | String | *(required)* | Directory for evidence JSON and SHA-256 files |
| `-FromDate` | DateTime | 30 days ago | Start date for the evidence collection window |
| `-ToDate` | DateTime | Current time | End date for the evidence collection window |
| `-RunId` | String | *(all runs)* | Scope evidence to a specific validation run ID |
| `-IncludeBaselines` | Switch | `$true` | Include active CA policy baselines |
| `-IncludeViolations` | Switch | `$true` | Include active CA policy violations |
| `-WhatIf` | Switch | — | Preview the export without querying Dataverse |

### Examples

**Default 30-day export:**

```powershell
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence"
```

**Custom date range (January 2026):**

```powershell
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence" `
    -FromDate "2026-01-01" -ToDate "2026-01-31"
```

**Specific run ID:**

```powershell
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence" `
    -RunId "abc123-def456"
```

**Exclude baselines and violations (validation results only):**

```powershell
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence" `
    -IncludeBaselines:$false -IncludeViolations:$false
```

**Preview without executing:**

```powershell
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence" -WhatIf
```

---

## JSON Schema Reference

Each evidence package contains the following top-level sections:

### metadata

| Field | Type | Description |
|-------|------|-------------|
| `exportedAt` | ISO 8601 | UTC timestamp of the export |
| `scope` | String | Export scope (currently `"Tenant"`) |
| `tenantId` | String | Entra ID tenant GUID |
| `fromDate` | ISO 8601 | Start of the evidence window |
| `toDate` | ISO 8601 | End of the evidence window |
| `runId` | String | Specific run ID filter, or `null` for all runs |
| `exportVersion` | String | Evidence schema version (currently `"1.0.0"`) |
| `solutionVersion` | String | CAA solution version (currently `"1.1.0"`) |
| `recordCount` | Integer | Number of validation records |
| `violationCount` | Integer | Number of violation records |
| `baselineCount` | Integer | Number of baseline records |

### summary

| Field | Type | Description |
|-------|------|-------------|
| `overallStatus` | String | Worst severity across all validation records (Passed / Warning / GracePeriod / Failed / Error) |
| `validationsRun` | Integer | Total validation records in the window |
| `passed` | Integer | Count of passed validations |
| `failed` | Integer | Count of failed/error validations |
| `warning` | Integer | Count of warning/grace-period validations |
| `zoneBreakdown` | Object | Per-zone counts (`{ "Zone 1": { passed, failed, warning, total }, ... }`) |

### validations

Array of validation history records from `fsi_CAPolicyValidationHistory`. Each record includes run ID, validation timestamp, policy counts, severity, and the full results JSON.

### violations

Array of violation records from `fsi_CAPolicyViolation` (included when `-IncludeViolations` is `$true`). Each record includes policy ID, violation type, zone, severity, expected/actual values, and resolution status.

### baselines

Array of active baseline records from `fsi_CAPolicyBaseline` (included when `-IncludeBaselines` is `$true`). Each record includes the full policy snapshot with conditions, grant controls, session controls, and baseline hash.

### Example Structure

```json
{
  "metadata": {
    "exportedAt": "2026-02-10T15:30:00.0000000Z",
    "scope": "Tenant",
    "tenantId": "a1b2c3d4-...",
    "fromDate": "2026-01-11T15:30:00.0000000Z",
    "toDate": "2026-02-10T15:30:00.0000000Z",
    "runId": null,
    "exportVersion": "1.0.0",
    "solutionVersion": "1.1.0",
    "recordCount": 30,
    "violationCount": 2,
    "baselineCount": 8
  },
  "summary": {
    "overallStatus": "Warning",
    "validationsRun": 30,
    "passed": 27,
    "failed": 1,
    "warning": 2,
    "zoneBreakdown": {
      "Zone 1": { "passed": 10, "failed": 0, "warning": 0, "total": 10 },
      "Zone 2": { "passed": 9, "failed": 0, "warning": 2, "total": 11 },
      "Zone 3": { "passed": 8, "failed": 1, "warning": 0, "total": 9 }
    }
  },
  "validations": [ ... ],
  "violations": [ ... ],
  "baselines": [ ... ]
}
```

---

## Hash Verification

### Automated Verification

```powershell
# Verify a single evidence file
.\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidencePath "./evidence/CAA-Evidence-20260210T120000Z.json"

# Batch-verify all evidence files in a directory
Get-ChildItem ./evidence/*.json | ForEach-Object {
    .\scripts\Test-EvidenceIntegrity.ps1 -EvidencePath $_.FullName
} | Format-Table Path, Valid, ExpectedHash, ActualHash
```

The `Test-EvidenceIntegrity.ps1` script returns a result object:

| Property | Type | Description |
|----------|------|-------------|
| `Path` | String | Evidence file path |
| `Valid` | Boolean | Whether the SHA-256 hash matches |
| `ExpectedHash` | String | Hash from the companion `.sha256` file |
| `ActualHash` | String | Computed hash of the current file content |

Exit code `0` indicates integrity verified. Exit code `1` indicates a mismatch.

### Manual Verification

The companion `.sha256` file uses `sha256sum`-compatible format:

```
<hash>  <filename>
```

Verify manually on any platform:

```bash
# Linux / macOS
sha256sum -c CAA-Evidence-20260210T120000Z.json.sha256

# PowerShell (any platform)
$expected = (Get-Content ./evidence/CAA-Evidence-20260210T120000Z.json.sha256).Split(' ')[0]
$actual = (Get-FileHash ./evidence/CAA-Evidence-20260210T120000Z.json -Algorithm SHA256).Hash
if ($expected -eq $actual) { "Integrity verified" } else { "HASH MISMATCH" }
```

---

## Recommended Schedule

| Frequency | Action | Retention | Purpose |
|-----------|--------|-----------|---------|
| Daily | Automated validation scan via Power Automate flow | Dataverse (immutable) | Continuous compliance monitoring |
| Weekly | Review evidence summary and zone breakdown | — | Operational oversight |
| Monthly | Export evidence package for archival | 7 years (per FINRA 4511) | Regulatory examination readiness |
| Quarterly | Full evidence export with baselines and violations | 7 years | Quarterly compliance review and audit support |

### Archival Command

```powershell
# Monthly evidence archive (previous 30 days)
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence/archive/2026-01"

# Quarterly evidence archive (Q1 2026)
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence/archive/Q1-2026" `
    -FromDate "2026-01-01" -ToDate "2026-03-31"
```

---

## Integration with Unified Evidence

For organizations deploying multiple FSI-AgentGov solutions, the cross-solution `Export-UnifiedComplianceEvidence.ps1` script aggregates evidence from all solutions into a single examination package. The CAA evidence export integrates with this unified collector — CAA evidence files are automatically discovered and included when present in the configured evidence output directory.

See the [cross-solution integration guide](https://github.com/judeper/FSI-AgentGov-Solutions) for details on unified evidence aggregation.

---

*Version: 1.1.0 | Last Updated: February 2026*
