# Evidence Export Guide

## Overview

The File Upload Security Configurator generates tamper-evident compliance evidence packages for regulatory review. Each export includes validation history, violation records, and optional baselines with SHA-256 cryptographic integrity verification.

## Quick Start

```powershell
# Export all evidence (interactive auth)
.\scripts\Export-FileUploadEvidence.ps1 `
    -TenantId "contoso.onmicrosoft.com" `
    -DataverseUrl "https://governance.crm.dynamics.com" `
    -Interactive

# Export Q1 2026 evidence
.\scripts\Export-FileUploadEvidence.ps1 `
    -TenantId "contoso.onmicrosoft.com" `
    -DataverseUrl "https://governance.crm.dynamics.com" `
    -StartDate "2026-01-01" `
    -EndDate "2026-03-31" `
    -IncludeBaselines `
    -Interactive
```

## Evidence Package Structure

```json
{
  "metadata": {
    "evidenceId": "guid",
    "generatedAt": "ISO 8601 UTC",
    "generatedBy": "operator",
    "solution": "File Upload Security Configurator",
    "control": "1.14 - Data Minimization and Agent Scope Control",
    "filters": { "zone": "All", "startDate": null, "endDate": null }
  },
  "summary": {
    "validationCount": 30,
    "violationCount": 3,
    "baselineCount": 45
  },
  "validations": [ ... ],
  "violations": [ ... ],
  "baselines": [ ... ]
}
```

## Integrity Verification

Each evidence file is accompanied by a `.sha256` companion file:

```powershell
# Verify evidence file integrity
.\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidenceFilePath .\FUS-Evidence-20260210.json

# Output: VERIFIED: Evidence file integrity confirmed.
```

## Filtering Options

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-Zone` | Filter by governance zone | `-Zone Zone3` |
| `-StartDate` | Start of date range | `-StartDate "2026-01-01"` |
| `-EndDate` | End of date range | `-EndDate "2026-03-31"` |
| `-RunId` | Specific validation run | `-RunId "abc-123"` |
| `-IncludeBaselines` | Include baseline records | `-IncludeBaselines` |

## Regulatory Context

| Regulation | Evidence Support |
|-----------|-----------------|
| SEC 17a-4(f) | SHA-256 integrity hashing supports tamper-evident electronic records |
| FINRA 4511 | Immutable validation history provides required audit trail |
| SOX 404 | Evidence packages support internal control testing and documentation |
| GLBA 501(b) | Data access validation evidence for safeguards compliance |

## Retention Guidance

- Retain evidence exports per your organization's retention policy
- Minimum recommended: 7 years (aligns with SEC/FINRA requirements)
- Store in write-once or append-only storage to support regulatory compliance requirements
- Maintain chain of custody documentation for evidence files

---

*File Upload Security Configurator — Evidence Export Guide*
