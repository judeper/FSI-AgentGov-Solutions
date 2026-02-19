# Evidence Export Guide — Audit Configuration Validator

## Overview

The evidence export feature produces JSON files with SHA-256 integrity hashes for compliance examinations. These files contain structured validation history records from Dataverse that help support audit documentation requirements under FINRA 4511, SEC 17a-3/4, and SOX 404.

## Prerequisites

- Dataverse infrastructure deployed (`deploy.py` completed)
- Validation history records exist (at least one validation run completed)
- PowerShell 7.0 or later
- MSAL.PS module for authentication (`Install-Module MSAL.PS`)

## Export Compliance Evidence

### Interactive Mode (Manual Export)

For ad-hoc exports during compliance reviews or examinations:

```powershell
# Export last 30 days of tenant validation evidence
.\scripts\Export-AuditValidationEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId <your-tenant-id> `
    -Scope Tenant `
    -OutputDirectory .\exports `
    -Interactive

# Export environment validation evidence for a specific environment
.\scripts\Export-AuditValidationEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId <your-tenant-id> `
    -Scope Environment `
    -EnvironmentId <environment-guid> `
    -OutputDirectory .\exports `
    -Interactive

# Export evidence for a specific date range
.\scripts\Export-AuditValidationEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId <your-tenant-id> `
    -Scope Tenant `
    -FromDate "2026-01-01" `
    -ToDate "2026-01-31" `
    -OutputDirectory .\exports `
    -Interactive
```

### Service Principal Mode (Automated Export)

For scheduled monthly or quarterly evidence collection:

```powershell
# Export using service principal authentication
.\scripts\Export-AuditValidationEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId <your-tenant-id> `
    -ClientId <app-registration-id> `
    -CertificateThumbprint <cert-thumbprint> `
    -Scope Tenant `
    -OutputDirectory \\fileserver\compliance\audit-evidence
```

### Export Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `DataverseUrl` | Yes | — | Dataverse organization URL (e.g., https://org.crm.dynamics.com) |
| `TenantId` | Yes | — | Microsoft Entra tenant ID |
| `Scope` | Yes | — | Tenant or Environment |
| `OutputDirectory` | No | Current directory | Where to write JSON evidence files |
| `Interactive` | No | — | Use browser-based authentication (cannot combine with ClientId/CertificateThumbprint) |
| `ClientId` | No | — | Service principal app registration ID |
| `CertificateThumbprint` | No | — | Certificate thumbprint for service principal authentication |
| `EnvironmentId` | No | — | Required when Scope=Environment, filters to specific environment |
| `FromDate` | No | 30 days ago | Start of date range filter (YYYY-MM-DD or parseable date string) |
| `ToDate` | No | Today | End of date range filter (YYYY-MM-DD or parseable date string) |

### Output Files

Each export produces two files:

**JSON Evidence File** - Contains metadata, summary statistics, and all validation records:

```
tenant-validation-20260206-143500.json
environment-12345678-20260206-143500.json
```

**SHA-256 Hash File** - Companion file with standard two-space delimiter format:

```
tenant-validation-20260206-143500.json.sha256
environment-12345678-20260206-143500.json.sha256
```

Example hash file content:
```
a3f5d8e2... tenant-validation-20260206-143500.json
```

## Verify Evidence Integrity

### Single File Verification

```powershell
# Verify a single evidence file
.\scripts\Test-EvidenceIntegrity.ps1 -EvidenceFilePath .\exports\tenant-validation-20260206-143500.json
```

Output:
```
PASS: tenant-validation-20260206-143500.json
```

### Batch Verification

```powershell
# Verify all evidence files in a directory
Get-ChildItem .\exports\*.json | .\scripts\Test-EvidenceIntegrity.ps1

# Quiet mode for automation (exit code 0=pass, 1=fail)
.\scripts\Test-EvidenceIntegrity.ps1 -EvidenceFilePath .\exports\tenant-validation-20260206-143500.json -Quiet
```

### Cross-Platform Verification

The SHA-256 hash files use standard two-space delimiter format compatible with Linux/macOS verification tools:

```bash
# Linux/macOS verification
sha256sum -c tenant-validation-20260206-143500.json.sha256
```

## Evidence Schema

### JSON Structure

```json
{
  "metadata": {
    "exportTimestamp": "2026-02-06T14:35:00Z",
    "scope": "Tenant",
    "dateRange": {
      "from": "2026-01-07T00:00:00Z",
      "to": "2026-02-06T23:59:59Z"
    },
    "dataverseUrl": "https://org.crm.dynamics.com",
    "schema": "AuditConfigurationValidator-v1.0"
  },
  "summary": {
    "totalRecords": 180,
    "validationRuns": 30,
    "severityCounts": {
      "Passed": 150,
      "Warning": 20,
      "GracePeriod": 5,
      "Failed": 3,
      "Error": 2
    },
    "overallStatus": "Failed"
  },
  "validations": [
    {
      "name": "TENANT-20260206-140000",
      "runId": "12345678-1234-1234-1234-123456789012",
      "scope": "Tenant",
      "environmentId": null,
      "zone": "Zone3",
      "severity": "Passed",
      "validationType": "UnifiedAuditLog",
      "rawValue": "AuditEnabled=true,RetentionDays=730",
      "reason": "Unified Audit Log meets Zone 3 retention (730 days)",
      "timestamp": "2026-02-06T14:00:00Z"
    }
  ]
}
```

### Field Descriptions

**metadata**
- `exportTimestamp` - When evidence file was created (UTC)
- `scope` - Tenant or Environment
- `dateRange` - Validation records included (from/to dates in UTC)
- `dataverseUrl` - Source Dataverse organization
- `schema` - Evidence format version

**summary**
- `totalRecords` - Count of validation records in file
- `validationRuns` - Count of distinct RunIds (orchestrator executions)
- `severityCounts` - Breakdown by severity (Passed, Warning, GracePeriod, Failed, Error)
- `overallStatus` - Worst severity across all records (Error > Failed > GracePeriod > Warning > Passed)

**validations** (array)
- `name` - Validation record name (ENV-{name}-{timestamp} or TENANT-{timestamp})
- `runId` - GUID correlating all records in one orchestrator execution
- `scope` - Tenant or Environment
- `environmentId` - Power Platform environment GUID (null for tenant scope)
- `zone` - Governance zone at time of validation (Zone1, Zone2, Zone3, Unclassified)
- `severity` - Passed, Warning, GracePeriod, Failed, Error
- `validationType` - UnifiedAuditLog, MailboxAudit, PurviewRetention, EnvironmentAudit, EnvironmentRetention, Orchestrator
- `rawValue` - Actual configuration values retrieved during validation
- `reason` - Human-readable explanation of validation result
- `timestamp` - When validation ran (UTC)

## Recommended Export Schedule

- **Monthly exports** for ongoing compliance (default -FromDate covers 30 days)
- **Quarterly exports** for regulatory examinations
- **On-demand exports** for specific investigation periods using -FromDate/-ToDate
- **Retention policy** - Retain exports per organizational retention policy (reference Control 1.7 WORM guidance for broker-dealers)

## Troubleshooting

| Issue | Cause | Resolution |
|-------|-------|-----------|
| Authentication failure | Missing MSAL.PS module | Run `Install-Module MSAL.PS` |
| Empty export (0 records) | No validation history in date range | Check -FromDate/-ToDate parameters, verify validation runs completed |
| Hash mismatch | File modified after export | File integrity compromised, re-export from Dataverse |
| JSON truncation | Nested object depth exceeded | Evidence export uses -Depth 10 (should not occur) |
| Service principal auth fails | Missing certificate or permissions | Verify certificate installed, check Dataverse API permissions in app registration |
| "Scope Environment requires EnvironmentId" | Missing -EnvironmentId parameter | Add -EnvironmentId parameter when using -Scope Environment |

## Related Documentation

- [Flow Setup Guide](FLOW_SETUP.md) - Configure Power Automate flows for automated validation
- [Control 1.7](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) - Audit log configuration framework control
