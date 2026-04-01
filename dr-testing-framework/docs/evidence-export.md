# Evidence Export

## Overview

Evidence export packages DR test results and audit logs for regulatory examination. The `Export-DREvidence.ps1` script collects local audit log files, generates a JSON metadata file with timestamps and file inventory, and copies everything into a portable evidence directory.

Currently supports local audit log collection; Dataverse-backed export is planned for a future release.

## Current Capabilities (v1.0.2)

| Capability | Status |
|---|---|
| Local audit log packaging from `logs/` directory | ✅ Implemented |
| JSON metadata generation with timestamps and file inventory | ✅ Implemented |
| Correlation ID filtering (`-TestRunId` parameter) | ✅ Implemented |
| SSRF-safe URL validation (commercial, GCC, GCC High, China clouds) | ✅ Implemented |
| Dataverse query for test execution results | 🔲 Planned |
| RTO/RPO measurement aggregation | 🔲 Planned |
| Gap list with remediation status | 🔲 Planned |

## Usage Examples

```powershell
# Export all evidence
.\scripts\Export-DREvidence.ps1 -Environment "https://contoso.crm.dynamics.com"

# Export for specific test run
.\scripts\Export-DREvidence.ps1 -Environment "https://contoso.crm.dynamics.com" -TestRunId "abc12345"

# Custom output directory
.\scripts\Export-DREvidence.ps1 -Environment "https://contoso.crm.dynamics.com" -OutputDir "C:\evidence\q1-2026"
```

### Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `-Environment` | Yes | — | Dataverse environment URL (e.g., `https://contoso.crm.dynamics.com`) |
| `-OutputDir` | No | `./evidence` | Directory to write evidence files to |
| `-TestRunId` | No | — | Correlation ID to filter results to a specific test run. Must match `^[0-9a-zA-Z\-]+$` |

When `-TestRunId` is provided, only audit logs matching the pattern `dr-audit-*-<TestRunId>.log` are included. When omitted, all `dr-audit-*.log` files are collected.

## Output Structure

```
evidence/
├── dr-evidence-20260315-143022.json    # Metadata file
└── audit-logs/                          # Copied audit logs
    ├── dr-audit-AgentRestore-abc12345.log
    └── dr-audit-FullDR-def67890.log
```

The output directory is created automatically if it does not exist.

## Metadata JSON Format

Each export generates a timestamped JSON file with the following structure:

```json
{
  "ExportedAt": "2026-03-15T14:30:22Z",
  "Environment": "https://contoso.crm.dynamics.com",
  "TestRunId": "abc12345",
  "AuditLogFiles": [
    "dr-audit-AgentRestore-abc12345.log"
  ],
  "TestResults": [],
  "Metrics": [],
  "Gaps": [],
  "Status": "stub — Dataverse query and full evidence packaging not yet implemented"
}
```

| Field | Type | Description |
|---|---|---|
| `ExportedAt` | string | UTC timestamp in ISO 8601 format |
| `Environment` | string | Validated Dataverse environment URL |
| `TestRunId` | string | Correlation ID used to filter, or `"all"` if not specified |
| `AuditLogFiles` | string[] | List of audit log filenames included in the package |
| `TestResults` | object[] | **Planned** — DR test execution results from Dataverse |
| `Metrics` | object[] | **Planned** — RTO/RPO measurements from test runs |
| `Gaps` | object[] | **Planned** — Identified gaps with remediation status |
| `Status` | string | Implementation status indicator |

## Planned Capabilities

The following features are not yet implemented and are planned for future releases:

- **Dataverse query for test execution results** — Query `fsi_drtestexecution` records and include pass/fail outcomes in the evidence package
- **RTO/RPO measurement aggregation** — Summarize recovery time and recovery point measurements across test runs
- **Gap list with remediation status** — Generate a list of identified gaps with current remediation tracking
- **Signed attestation template** — Produce a pre-filled attestation document for reviewer sign-off
- **SHA-256 integrity hashing** — Compute file hashes for tamper evidence on exported artifacts

## Regulatory Alignment

| Regulation | Relevance |
|---|---|
| OCC Heightened Standards | Evidence of DR testing execution aids in demonstrating operational resilience |
| FFIEC BCP Handbook | Documented test results support examiner review of business continuity planning |
| SEC Rule 17a-4 | Supports record recoverability requirements by packaging recovery test artifacts |
| FINRA Rule 4370 | Supports BCP documentation requirements with structured evidence packages |

> **Note:** No single export satisfies any regulation in isolation. Organizations should verify that evidence packages meet their specific examination requirements.

## Integration

- Evidence files are JSON and can be ingested by a compliance dashboard, SIEM, or archival system
- Audit logs use a structured format with timestamp, level, and message fields
- The `TestRunId` correlation ID links Dataverse records to local audit log files, enabling end-to-end traceability across the DR testing pipeline

## URL Validation

The script validates the `-Environment` parameter against an allowlist of Dataverse host patterns to help prevent SSRF and token exfiltration:

| Cloud | Accepted Pattern |
|---|---|
| Commercial | `https://<org>.crm.dynamics.com` |
| GCC | `https://<org>.crm9.dynamics.com` |
| GCC High | `https://<org>.crm.microsoftdynamics.us`, `https://<org>.crm.appsplatform.us` |
| China (21Vianet) | `https://<org>.crm.dynamics.cn` |

Invalid URLs cause the script to terminate before any file operations or network calls.
