# Evidence Export

## Overview

Evidence export packages DR validation results and audit logs for examiner review. The `Export-DREvidence.ps1` script collects local audit log files, queries Dataverse when authentication is supplied, writes a JSON metadata file, and creates a SHA-256 companion hash for tamper-evident packaging.

The export records **validation evidence** only. It does not prove that Power Platform backup, restore, or failover was executed end-to-end; pair the package with PPAC/Admin-module operation timestamps, Microsoft support records, and incident/runbook evidence.

## Current Capabilities (v2.0.2)

| Capability | Status |
|---|---|
| Local audit log packaging from `logs/` directory | ✅ Implemented |
| JSON metadata generation with timestamps and file inventory | ✅ Implemented |
| Correlation ID filtering (`-TestRunId` parameter) | ✅ Implemented |
| SSRF-safe URL validation (commercial, GCC, GCC High, China clouds) | ✅ Implemented |
| Dataverse query for validation results with pagination | ✅ Implemented |
| Probe-duration and validation-coverage aggregation | ✅ Implemented |
| Gap list for failed or missing validation types | ✅ Implemented |
| SHA-256 integrity hashing | ✅ Implemented |

## Usage Examples

```powershell
.\scripts\Export-DREvidence.ps1 `
    -Environment "https://contoso.crm.dynamics.com" `
    -AccessToken $env:DATAVERSE_ACCESS_TOKEN

.\scripts\Export-DREvidence.ps1 `
    -Environment "https://contoso.crm.dynamics.com" `
    -TestRunId "abc12345" `
    -AccessToken $env:DATAVERSE_ACCESS_TOKEN

.\scripts\Export-DREvidence.ps1 `
    -Environment "https://contoso.crm.dynamics.com" `
    -OutputDir "C:\evidence\q1-2026" `
    -AccessToken $env:DATAVERSE_ACCESS_TOKEN
```

Client-secret parameters remain available for local development only (`# legacy: dev-only — replace with managed identity in production`).

### Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `-Environment` | Yes | — | Dataverse environment URL (e.g., `https://contoso.crm.dynamics.com`) |
| `-OutputDir` | No | `./evidence` | Directory to write evidence files to |
| `-TestRunId` | No | — | Correlation ID to filter results to a specific validation run. Must match `^[0-9a-zA-Z\-]+$` |
| `-AccessToken` | No | `$env:DATAVERSE_ACCESS_TOKEN` | Dataverse token acquired through managed identity, workload identity federation, or another approved flow |
| `-TenantId` / `-ClientId` / `-ClientSecret` | No | Azure environment variables | Legacy local-development fallback when `-AccessToken` is not supplied |

When `-TestRunId` is provided, only audit logs matching the pattern `dr-audit-*-<TestRunId>.log` are included. When omitted, all `dr-audit-*.log` files are collected.

## Output Structure

```
evidence/
├── dr-evidence-20260315-143022.json
├── dr-evidence-20260315-143022.json.sha256
└── audit-logs/
    ├── dr-audit-20260315-130145-abc12345.log
    └── dr-audit-20260315-141507-abc12345.log
```

## Metadata JSON Format

```json
{
  "ExportedAt": "2026-03-15T14:30:22Z",
  "Environment": "https://contoso.crm.dynamics.com",
  "TestRunId": "abc12345",
  "AuditLogFiles": [
    "dr-audit-20260315-130145-abc12345.log",
    "dr-audit-20260315-141507-abc12345.log"
  ],
  "TestResults": [
    {
      "Id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "TestType": "AgentReadinessCheck",
      "ExecutedOn": "2026-03-15T13:00:00Z",
      "ProbeDurationHours": 0.03,
      "ProbeDurationTargetHours": 0.25,
      "ProbeWithinBudget": true,
      "Status": "Pass",
      "CorrelationId": "abc12345"
    }
  ],
  "Metrics": {
    "TotalTests": 1,
    "Passed": 1,
    "Failed": 0,
    "PassRate": 100.0,
    "AvgProbeDurationHours": 0.03,
    "ProbeWithinBudgetCount": 1,
    "ProbeWithinBudgetRate": 100.0
  },
  "Gaps": [],
  "Status": "Validated"
}
```

| Field | Type | Description |
|---|---|---|
| `ExportedAt` | string | UTC timestamp in ISO 8601 format |
| `Environment` | string | Validated Dataverse environment URL |
| `TestRunId` | string | Correlation ID used to filter, or `"all"` if not specified |
| `AuditLogFiles` | string[] | List of audit log filenames included in the package |
| `TestResults` | object[] | Validation results from `fsi_drtestresult` in Dataverse |
| `Metrics` | object | Probe-duration and validation-coverage metrics aggregated from validation runs |
| `Gaps` | object[] | Failed checks or missing validation types |
| `Status` | string | Overall export status (`Validated`, `ValidationFailures`, `IncompleteValidationCoverage`, `NoData`, `NoCredentials`, `QueryFailed`) |

## Planned Capabilities

- **Signed attestation template** — Produce a pre-filled attestation document for reviewer sign-off

## Regulatory Alignment

| Regulation | Relevance |
|---|---|
| OCC Heightened Standards | Evidence of DR validation execution aids in demonstrating operational resilience |
| FFIEC BCP Handbook | Documented validation results support examiner review of business continuity testing |
| SEC Rule 17a-4 | Supports record recoverability evidence packaging when exported to immutable storage |
| FINRA Rule 4370 | Supports BCP documentation requirements with structured evidence packages |

> **Note:** No single export satisfies any regulation in isolation. Organizations should verify that evidence packages meet their specific examination requirements.

## Integration

- Evidence files are JSON and can be ingested by a compliance dashboard, SIEM, or archival system
- Audit logs use a structured format with timestamp, level, and message fields
- The `TestRunId` correlation ID links Dataverse records to local audit log files, enabling end-to-end traceability across the DR validation pipeline

## URL Validation

The script validates the `-Environment` parameter against an allowlist of Dataverse host patterns to help prevent SSRF and token exfiltration:

| Cloud | Accepted Pattern |
|---|---|
| Commercial | `https://<org>.crm.dynamics.com` |
| GCC | `https://<org>.crm9.dynamics.com` |
| GCC High | `https://<org>.crm.microsoftdynamics.us`, `https://<org>.crm.appsplatform.us` |
| China (21Vianet) | `https://<org>.crm.dynamics.cn` |

Invalid URLs cause the script to terminate before any file operations or network calls.
