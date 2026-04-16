# Evidence Export Guide

Step-by-step instructions for exporting content moderation compliance evidence with SHA-256 integrity hashing.

## Overview

The Content Moderation Monitor produces JSON evidence files containing validation results, per-agent violation details, and optional baselines with SHA-256 companion hash files. These exports support regulatory examination workflows for FINRA, SEC, and GLBA by providing tamper-evident records of content moderation governance state.

**Key difference from environment-level monitors:** CMM evidence includes per-agent detail — each violation record identifies the specific Copilot Studio agent, its moderation level, the expected level for its zone, and severity classification.

## Prerequisites

- Dataverse deployed with CMM schema and at least one validation scan completed
- PowerShell 7.0+
- MSAL.PS module for authentication: `Install-Module MSAL.PS -Scope CurrentUser`
- Dataverse read permissions for `fsi_moderationvalidationhistory`, `fsi_moderationviolations`, and `fsi_moderationbaselines`

---

## Export Content Moderation Evidence

### Interactive Mode

For ad-hoc exports during investigations or audit preparation:

```powershell
.\scripts\Export-ContentModerationEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "your-tenant-id" `
    -OutputDirectory ".\exports" `
    -Interactive
```

### Service Principal Mode

For automated or scheduled exports:

```powershell
.\scripts\Export-ContentModerationEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "your-tenant-id" `
    -OutputDirectory ".\exports" `
    -ClientId "app-registration-client-id" `
    -CertificateThumbprint "certificate-thumbprint"
```

### Export with Zone Filter

Export evidence for a specific governance zone only:

```powershell
# Zone 3 (Enterprise Managed) agents only
.\scripts\Export-ContentModerationEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "your-tenant-id" `
    -OutputDirectory ".\exports" `
    -Zone 3 `
    -Interactive
```

### Export with Baseline Inclusion

Include active per-agent moderation baselines in the evidence package:

```powershell
.\scripts\Export-ContentModerationEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "your-tenant-id" `
    -OutputDirectory ".\exports" `
    -IncludeBaselines `
    -Interactive
```

### Export Specific Run

Export evidence from a single validation run by RunId:

```powershell
.\scripts\Export-ContentModerationEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "your-tenant-id" `
    -OutputDirectory ".\exports" `
    -RunId "a1b2c3d4-e5f6-7890-abcd-ef1234567890" `
    -Interactive
```

### Custom Date Range

Export evidence for a specific time period:

```powershell
.\scripts\Export-ContentModerationEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "your-tenant-id" `
    -OutputDirectory ".\exports" `
    -FromDate (Get-Date).AddDays(-90) `
    -ToDate (Get-Date) `
    -Interactive
```

---

## Parameters Reference

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `DataverseUrl` | String | Yes | — | Dataverse organization URL |
| `TenantId` | String | Yes | — | Microsoft Entra ID tenant ID |
| `OutputDirectory` | String | Yes | — | Directory for evidence files |
| `Zone` | String | No | All | Zone filter: All, 1, 2, or 3 |
| `RunId` | String | No | — | Export specific validation run |
| `FromDate` | DateTime | No | 30 days ago | Date range start (inclusive) |
| `ToDate` | DateTime | No | Now | Date range end (inclusive) |
| `IncludeBaselines` | Switch | No | — | Include active baselines in export |
| `Interactive` | Switch | No | — | Use interactive authentication |
| `ClientId` | String | No | — | App registration client ID |
| `CertificateThumbprint` | String | No | — | Certificate for service principal auth |

---

## Output Files

Each export produces two files:

| File | Format | Description |
|------|--------|-------------|
| `cmm-evidence-{zone}-{yyyyMMdd-HHmmss}.json` | JSON | Evidence data with metadata, summary, validations, violations, and baselines |
| `cmm-evidence-{zone}-{yyyyMMdd-HHmmss}.json.sha256` | Text | SHA-256 hash for integrity verification |

The `.sha256` file uses standard format: `{hash}  {filename}` (two spaces between hash and filename).

---

## Verify Evidence Integrity

### Single File Verification

```powershell
.\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidenceFilePath ".\exports\cmm-evidence-All-20260210-143022.json"
```

### Batch Verification

```powershell
Get-ChildItem .\exports\cmm-evidence-*.json | ForEach-Object {
    .\scripts\Test-EvidenceIntegrity.ps1 -EvidenceFilePath $_.FullName
}
```

### Quiet Mode (Automation)

```powershell
$isValid = .\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidenceFilePath ".\exports\cmm-evidence-All-20260210-143022.json" `
    -Quiet

if (-not $isValid) {
    Write-Error "Evidence integrity check failed"
}
```

### Cross-Platform Verification

On Linux/macOS, use standard SHA-256 tools:

```bash
sha256sum -c exports/cmm-evidence-All-20260210-143022.json.sha256
```

---

## Evidence JSON Schema

```json
{
  "metadata": {
    "exportedAt": "2026-02-10T14:30:22Z",
    "solution": "Content Moderation Governance Monitor",
    "solutionVersion": "1.0.3",
    "fromDate": "2026-01-11T00:00:00Z",
    "toDate": "2026-02-10T14:30:22Z",
    "runId": null,
    "zoneFilter": "All",
    "exportVersion": "1.0.0",
    "recordCount": 45,
    "violationCount": 3,
    "organizationUrl": "https://org.crm.dynamics.com"
  },
  "summary": {
    "overallStatus": "Failed",
    "totalScans": 30,
    "scansCompliant": 27,
    "scansWithViolations": 3,
    "totalAgents": 150,
    "totalViolations": 8,
    "criticalViolations": 1,
    "highViolations": 3,
    "mediumViolations": 2,
    "warningViolations": 2
  },
  "validations": [
    {
      "name": "Passed-2026-02-10T06:00:00Z",
      "runId": "guid",
      "validationTime": "2026-02-10T06:00:00Z",
      "totalAgents": 150,
      "compliantCount": 147,
      "violationCount": 3,
      "overallStatus": "Failed",
      "environmentsScanned": "env1,env2,env3",
      "summaryJson": "..."
    }
  ],
  "violations": [
    {
      "name": "SalesBot-3-2026-02-10",
      "environmentGuid": "guid",
      "environmentName": "Production-Sales-Z3",
      "agentId": "bot-guid",
      "agentName": "SalesBot",
      "zone": 3,
      "expectedLevel": "High",
      "actualLevel": "Low",
      "severity": "Critical",
      "regulatoryContext": "FINRA 3110 — Unmoderated customer-facing AI agent",
      "detectedAt": "2026-02-10T06:00:12Z",
      "runId": "guid"
    }
  ],
  "baselines": [
    {
      "baselineId": "guid",
      "agentId": "bot-guid",
      "agentName": "SalesBot",
      "environmentGuid": "guid",
      "environmentName": "Production-Sales-Z3",
      "zone": 3,
      "moderationLevel": "High",
      "capturedBy": "admin@contoso.com",
      "capturedAt": "2026-02-01T10:00:00Z",
      "isActive": true
    }
  ]
}
```

---

## Recommended Export Schedule

| Frequency | Use Case | Recommended Date Range |
|-----------|----------|----------------------|
| Monthly | Routine compliance monitoring | 30 days |
| Quarterly | Regulatory examination preparation | 90+ days |
| On-demand | Incident investigation or audit request | As needed |

For quarterly regulatory preparation, include baselines (`-IncludeBaselines`) to provide a complete picture of moderation governance state alongside validation history.

---

## Troubleshooting

| Issue | Cause | Resolution |
|-------|-------|------------|
| Empty evidence file | No validation scans in date range | Verify `FromDate`/`ToDate` range covers existing scan data |
| Authentication failure | Expired token or missing permissions | Re-authenticate or verify Dataverse read permissions |
| Hash mismatch after file copy | File modified or encoding changed during transfer | Re-export from source; verify UTF-8 encoding preserved |
| Missing baselines section | `-IncludeBaselines` not specified | Re-run with `-IncludeBaselines` switch |
| Truncated JSON | Default serialization depth | Script uses `-Depth 10`; if still truncated, check for nested objects beyond 10 levels |

---

*Content Moderation Governance Monitor — Evidence Export Guide v1.0.3*
