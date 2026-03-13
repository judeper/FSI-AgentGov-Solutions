# Unified Evidence Export

This document describes the unified compliance evidence export pipeline that aggregates governance data from all Tier 2 solutions into auditor-ready packages.

---

## Overview

Financial services organizations require consolidated evidence packages for regulatory examinations. The unified export pipeline:

1. Queries validation and violation records from 6 Tier 2 solutions
2. Exports per-solution CSV files with standardized field sets
3. Generates a master manifest with SHA-256 hash chain
4. Produces a self-contained, tamper-evident evidence directory

---

## Export Package Structure

```
evidence-export-YYYY-MM-DD-HHmmss/
├── manifest.json
├── acv/
│   ├── validations.csv
│   └── violations.csv
├── ssc/
│   ├── validations.csv
│   └── violations.csv
├── aam/
│   ├── validations.csv
│   └── violations.csv
├── cmm/
│   ├── validations.csv
│   └── violations.csv
├── fus/
│   ├── validations.csv
│   └── violations.csv
└── caa/
    ├── validations.csv
    └── violations.csv
```

---

## Manifest Schema

```json
{
    "exportId": "GUID — unique export identifier",
    "exportDate": "ISO 8601 timestamp",
    "periodStart": "YYYY-MM-DD",
    "periodEnd": "YYYY-MM-DD",
    "framework": "FSI Agent Governance Framework",
    "frameworkVersion": "v1.2.38",
    "solutions": {
        "acv": {
            "validationCount": 150,
            "violationCount": 3,
            "exportedAt": "ISO 8601 timestamp"
        }
    },
    "fileHashes": {
        "acv/validations.csv": "SHA-256 hex",
        "acv/violations.csv": "SHA-256 hex"
    },
    "masterHash": "SHA-256 hex"
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `exportId` | GUID | Unique identifier for this export |
| `exportDate` | ISO 8601 | When the export was generated |
| `periodStart` | Date | Start of evidence period (inclusive) |
| `periodEnd` | Date | End of evidence period (inclusive) |
| `framework` | String | Framework name |
| `frameworkVersion` | String | Framework version at time of export |
| `solutions` | Object | Per-solution record counts and timestamps |
| `fileHashes` | Object | SHA-256 hash per evidence file |
| `masterHash` | String | SHA-256 of sorted concatenated file hashes |

---

## Hash Chain Algorithm

The hash chain provides tamper evidence:

1. Calculate SHA-256 for each evidence file (CSV)
2. Sort all hash values alphabetically
3. Concatenate sorted hashes into a single string
4. Calculate SHA-256 of the concatenated string → **master hash**

**Verification:** `Test-UnifiedEvidenceIntegrity.ps1` recalculates all hashes and compares against the manifest. Any modified file will cascade to a different master hash.

This approach is consistent with the per-solution evidence export pattern used by individual Tier 2 solutions (ACV, SSC, etc.) and extends it to the unified package level.

---

## Data Sources Per Solution

| Solution | Validation Table | Violation Table | Date Field | Key Fields |
|----------|-----------------|-----------------|------------|------------|
| ACV | `fsi_auditvalidationhistories` | `fsi_auditvalidationviolations` | `fsi_scannedon` / `fsi_detectedon` | settingName, expectedValue, actualValue, severity, zone |
| SSC | `fsi_validationhistories` | `fsi_driftviolations` | `fsi_scannedon` / `fsi_detectedon` | policyName, expectedValue, actualValue, severity |
| AAM | `fsi_accessvalidationhistories` | `fsi_accessviolations` | `fsi_scannedon` / `fsi_detectedon` | agentName, permissionType, expectedAccess, actualAccess |
| CMM | `fsi_moderationvalidationhistories` | `fsi_moderationviolations` | `fsi_scannedon` / `fsi_detectedon` | agentName, moderationPolicy, expectedConfig, actualConfig |
| FUS | `fsi_fileupload_validationhistories` | `fsi_fileupload_violations` | `fsi_scannedon` / `fsi_detectedon` | settingName, expectedValue, actualValue, severity |
| CAA | `fsi_capolicyvalidationhistories` | `fsi_capolicyviolations` | `fsi_scannedon` / `fsi_detectedon` | policyName, expectedValue, actualValue, severity |

---

## Usage

### Full Export (Interactive)

```powershell
.\Export-UnifiedComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "tenant-guid" `
    -OutputPath "C:\evidence" `
    -Interactive
```

### Filtered Export (Service Principal)

```powershell
.\Export-UnifiedComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "tenant-guid" `
    -OutputPath "C:\evidence" `
    -Solutions ACV,SSC `
    -StartDate "2026-01-01" `
    -EndDate "2026-01-31" `
    -ClientId "app-guid" `
    -ClientSecret (Get-AzKeyVaultSecret -VaultName "MyVault" -Name "IntClientSecret").SecretValue
```

### Dry Run

```powershell
.\Export-UnifiedComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "tenant-guid" `
    -DryRun -Interactive
```

### Verification

```powershell
.\Test-UnifiedEvidenceIntegrity.ps1 `
    -ExportPath ".\evidence-export-2026-02-01-140000" `
    -Detailed
```

---

## Regulatory Context

This evidence export pipeline supports compliance with:

| Regulation | Requirement | How Addressed |
|------------|-------------|---------------|
| **FINRA 4511** | Books and records retention | Timestamped CSV exports with hash chain integrity |
| **SEC 17a-3/17a-4** | Record creation and retention | Per-solution validation records with date ranges |
| **SOX 302/404** | Internal controls documentation | Comprehensive violation tracking across all governance solutions |
| **OCC 2011-12** | Model risk management | Evidence of configuration monitoring and baseline comparison |

**Note:** The export pipeline supports compliance with these regulations; organizations must ensure their overall records management program meets specific requirements.

---

## Scheduling Recommendations

| Frequency | Use Case |
|-----------|----------|
| **Monthly** | Standard governance reporting cycle |
| **Quarterly** | Aligned with FINRA examination periods |
| **On-demand** | Regulatory examination preparation |
| **Weekly** | Organizations with heightened monitoring requirements |

Automate with Task Scheduler or Azure Automation using service principal authentication.

---

*Evidence Export Guide v1.0.0 — February 2026*
