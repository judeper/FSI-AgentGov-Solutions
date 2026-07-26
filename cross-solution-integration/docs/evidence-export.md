# Unified Evidence Export

This document describes the unified compliance evidence export pipeline that aggregates governance data from all Tier 2 solutions into regulatory examination packages.

---

## Overview

Financial services organizations require consolidated evidence packages for regulatory examinations. The unified export pipeline:

1. Queries run-level validation records from 6 Tier 2 solutions
2. Exports per-solution CSV files with standardized field sets
3. Generates a master manifest with SHA-256 hash chain
4. Produces a self-contained evidence directory with SHA-256 tamper-evidence metadata

---

## Export Package Structure

```
evidence-export-YYYY-MM-DD-HHmmss/
├── manifest.json
├── acv/
│   └── validations.csv
├── ssc/
│   └── validations.csv
├── aam/
│   └── validations.csv
├── cmm/
│   └── validations.csv
├── fus/
│   └── validations.csv
└── caa/
    └── validations.csv
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
    "frameworkVersion": "v1.6.0",
    "solutions": {
        "acv": {
            "validationCount": 150,
            "exportedAt": "ISO 8601 timestamp"
        }
    },
    "fileHashes": {
        "acv/validations.csv": "SHA-256 hex",
        "ssc/validations.csv": "SHA-256 hex"
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

## Data Sources Per Solution (v2.0.2 — validations only)

> **Breaking change retained from v2.0.0:** v2.0.2 exports **run-level validation rows only**. Per-finding violation rows are intentionally excluded — they live in each owning solution's own dashboards and frequently contain agent owner UPNs and other PII that should not be redistributed in a consolidated package.

| Solution | Validation Table EntitySet | Status Field | Timestamp Field | RunId Field |
|----------|----------------------------|--------------|-----------------|-------------|
| ACV | `fsi_auditvalidationhistories` | `fsi_severity` (choice, 100000000-based) | `fsi_timestamp` | `fsi_runid` |
| SSC | `fsi_validationhistories` | `fsi_severity` (choice, 100000000-based) | `fsi_timestamp` | `fsi_runid` |
| AAM | **`fsi_accessvalidationhistory`** *(singular — explicit `EntitySetName`)* | `fsi_overallstatus` (string) | `fsi_validationtime` | `fsi_runid` |
| CMM | **`fsi_moderationvalidationhistory`** *(singular — explicit `EntitySetName`)* | `fsi_overallstatus` + `fsi_compliantcount`/`fsi_totalagents` | `fsi_validationtime` | `fsi_runid` |
| FUS | `fsi_fileuploadvalidationhistories` | `fsi_compliancerate` (% int) | `fsi_validationtime` (also `fsi_runtimestamp`) | `fsi_runid` |
| CAA | `fsi_capolicyvalidationhistories` | `fsi_overallseverity` (choice, 100000000-based) | `fsi_validationtime` | `fsi_runid` |

> ⚠️ `fsi_scannedon` / `fsi_detectedon` columns referenced in v1.x docs **do not exist** on history tables. Use the per-solution timestamp column shown above.

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

### Full Export (Managed Identity)

```powershell
.\Export-UnifiedComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "tenant-guid" `
    -OutputPath "C:\evidence" `
    -ManagedIdentity
```

### Filtered Export (Legacy Dev-Only Service Principal)

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

## Microsoft Purview and Power BI Notes

- Store exported packages in your organization's governed records repository. Hashes provide tamper evidence, but SEC 17a-4(f) / FINRA 4511 retention still depends on downstream immutable retention configuration.
- Microsoft Purview eDiscovery review set exports package review-set content and reports; use this integration export as a governance evidence input, not as a replacement for Purview case export workflows.
- For reporting, Power BI and Dataflows can use the Dataverse connector for curated tables. For bulk history extraction, evaluate Synapse Link or Fabric patterns rather than repeatedly pulling large Web API result sets.

---

## Scheduling Recommendations

| Frequency | Use Case |
|-----------|----------|
| **Monthly** | Standard governance reporting cycle |
| **Quarterly** | Aligned with FINRA examination periods |
| **On-demand** | Regulatory examination preparation |
| **Weekly** | Organizations with heightened monitoring requirements |

Automate with Azure Automation or an Azure-hosted worker using managed identity. Use service principal secrets only as a legacy dev-only fallback.

---

*Evidence Export Guide v2.0.2 — May 2026*
