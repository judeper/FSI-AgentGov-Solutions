# Evidence Export Guide

## Overview

The evidence export workflow produces JSON files with SHA-256 integrity hashes for compliance examinations. Each export generates a pair of files — one JSON evidence file and one `.sha256` companion file — suitable for FINRA, SEC, and GLBA regulatory submissions.

## Prerequisites

- AAM Dataverse schema deployed with validation history records
- PowerShell 7.0+
- MSAL.PS module installed (`Install-Module MSAL.PS -Scope CurrentUser`)
- Dataverse User role (minimum) on the governance environment

## Export Compliance Evidence

### Interactive Mode

```powershell
./scripts/Export-AgentAccessEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "contoso.onmicrosoft.com" `
    -OutputDirectory "./exports" `
    -Interactive
```

### Service Principal Mode

```powershell
./scripts/Export-AgentAccessEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "contoso.onmicrosoft.com" `
    -OutputDirectory "C:\compliance\evidence" `
    -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
    -CertificateThumbprint "ABCDEF1234567890..."
```

### Export with Zone Filter

```powershell
# Export Zone 3 violations only
./scripts/Export-AgentAccessEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "contoso.onmicrosoft.com" `
    -OutputDirectory "./exports" `
    -Zone "3" `
    -Interactive
```

### Export with Baselines

```powershell
./scripts/Export-AgentAccessEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "contoso.onmicrosoft.com" `
    -OutputDirectory "./exports" `
    -IncludeBaselines `
    -FromDate (Get-Date).AddDays(-90) `
    -Interactive
```

## Parameters Reference

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-DataverseUrl` | Yes | — | Dataverse organization URL |
| `-TenantId` | Yes | — | Microsoft Entra ID tenant ID |
| `-OutputDirectory` | Yes | — | Output path (created if needed) |
| `-Zone` | No | All | Zone filter: All, 1, 2, or 3 |
| `-RunId` | No | — | Export a specific validation run |
| `-FromDate` | No | 30 days ago | Start of date range (inclusive) |
| `-ToDate` | No | Now | End of date range (inclusive) |
| `-IncludeBaselines` | No | false | Include active baselines in export |
| `-Interactive` | No | false | Use browser-based authentication |
| `-ClientId` | Cond. | — | Required for service principal auth |
| `-CertificateThumbprint` | Cond. | — | Required for service principal auth |

## Output Files

Each export produces two files:

- **JSON evidence file**: `aam-evidence-{Zone}-{yyyyMMdd-HHmmss}.json`
- **SHA-256 companion file**: `aam-evidence-{Zone}-{yyyyMMdd-HHmmss}.json.sha256`

### JSON Structure

```json
{
  "metadata": {
    "exportedAt": "2026-02-09T14:30:22Z",
    "solution": "Agent Access Governance Monitor",
    "solutionVersion": "1.0.0",
    "fromDate": "...", "toDate": "...",
    "zoneFilter": "All",
    "recordCount": 30, "violationCount": 5
  },
  "summary": {
    "overallStatus": "NonCompliant",
    "totalScans": 30,
    "criticalViolations": 2,
    "highViolations": 3
  },
  "validations": [ ... ],
  "violations": [ ... ],
  "baselines": [ ... ]
}
```

## Verify Evidence Integrity

### Single File

```powershell
./scripts/Test-EvidenceIntegrity.ps1 `
    -EvidenceFilePath "./exports/aam-evidence-All-20260209-143022.json"
```

### Batch Verification

```powershell
Get-ChildItem ./exports/aam-evidence-*.json | ForEach-Object {
    $result = ./scripts/Test-EvidenceIntegrity.ps1 -EvidenceFilePath $_.FullName
    [PSCustomObject]@{ File = $_.Name; Valid = $result }
} | Format-Table
```

### Cross-Platform (Linux/macOS)

```bash
cd exports
sha256sum -c aam-evidence-All-20260209-143022.json.sha256
```

## Recommended Export Schedule

| Frequency | Use Case |
|-----------|----------|
| Monthly | Ongoing compliance monitoring and evidence retention |
| Quarterly | Regulatory examination preparation (FINRA, SEC) |
| On-demand | Incident investigations and ad-hoc auditor requests |

> **Tip:** Use service principal authentication with Azure Automation for scheduled exports. See [FLOW_SETUP.md](FLOW_SETUP.md) for automation patterns.

## Troubleshooting

| Issue | Cause | Resolution |
|-------|-------|------------|
| Empty export (0 records) | No validation data in date range | Verify FromDate/ToDate range; run a validation first |
| Authentication failed | Expired token or missing permissions | Re-authenticate; verify Dataverse User role |
| Hash mismatch on verify | File modified after export | Re-export from Dataverse; check for encoding changes |
| Truncated JSON objects | ConvertTo-Json depth insufficient | Script uses `-Depth 10` by default; verify PowerShell 7.0+ |
| Output directory error | Insufficient file system permissions | Run as administrator or choose a writable path |

## Related Documentation

- [SCHEMA.md](SCHEMA.md) — Dataverse table and column definitions
- [PREREQUISITES.md](PREREQUISITES.md) — Module and permission requirements
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Extended troubleshooting guide
