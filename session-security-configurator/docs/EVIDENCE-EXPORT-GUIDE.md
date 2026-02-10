# Evidence Export Guide

## Overview

`Export-SessionSecurityEvidence.ps1` exports session security validation history from Dataverse to JSON files with SHA-256 integrity hashing. These evidence packages support regulatory examination workflows for FINRA, SEC, and GLBA compliance.

Each export produces:

- **JSON evidence file** containing metadata, summary statistics, and complete validation results
- **SHA-256 hash file** for cryptographic integrity verification

## Prerequisites

- PowerShell 7.0 or later
- `MSAL.PS` module (for service principal authentication)
- Dataverse environment with SSC schema deployed
- Read access to `fsi_ValidationHistory` table

## Interactive Mode

Use interactive authentication for ad-hoc exports during audits.

### Export Last 30 Days (All Zones)

```powershell
.\scripts\Export-SessionSecurityEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId "your-tenant-id" `
    -OutputDirectory .\exports `
    -Interactive
```

### Export Specific Zone

```powershell
.\scripts\Export-SessionSecurityEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId "your-tenant-id" `
    -Zone 3 `
    -OutputDirectory .\exports `
    -Interactive
```

### Export Date Range

```powershell
.\scripts\Export-SessionSecurityEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId "your-tenant-id" `
    -FromDate "2026-01-01" `
    -ToDate "2026-01-31" `
    -OutputDirectory .\exports `
    -Interactive
```

### Export Specific Validation Run

```powershell
.\scripts\Export-SessionSecurityEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId "your-tenant-id" `
    -RunId "run-20260209-060000" `
    -OutputDirectory .\exports `
    -Interactive
```

## Service Principal Mode

Use service principal authentication for scheduled or automated exports.

```powershell
$clientSecret = ConvertTo-SecureString "your-client-secret" -AsPlainText -Force

.\scripts\Export-SessionSecurityEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId "your-tenant-id" `
    -ClientId "your-app-registration-id" `
    -ClientSecret $clientSecret `
    -OutputDirectory .\exports
```

## Parameters Reference

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| DataverseUrl | Yes | — | Dataverse organization URL (e.g., `https://org.crm.dynamics.com`) |
| TenantId | Yes | — | Azure AD tenant ID or domain |
| Zone | No | All | Filter by zone: `1`, `2`, `3`, or `All` |
| OutputDirectory | Yes | — | Destination folder for evidence files |
| FromDate | No | 30 days ago | Start of date range (inclusive) |
| ToDate | No | Current time | End of date range (inclusive) |
| RunId | No | — | Export specific validation run only |
| Interactive | No | False | Use browser-based interactive authentication |
| ClientId | No | — | Service principal application ID |
| ClientSecret | No | — | Service principal secret (SecureString) |

## Output Files

Each export produces two files with consistent naming:

```
session-security-evidence-{Zone}-{yyyyMMdd-HHmmss}.json
session-security-evidence-{Zone}-{yyyyMMdd-HHmmss}.json.sha256
```

**Example:**

```
session-security-evidence-Zone3-20260209-143022.json
session-security-evidence-Zone3-20260209-143022.json.sha256
```

## Evidence JSON Schema

```json
{
  "metadata": {
    "exportedAt": "2026-02-09T14:30:22Z",
    "scope": "SessionSecurity",
    "zone": "Zone 3",
    "fromDate": "2026-01-10T00:00:00Z",
    "toDate": "2026-02-09T23:59:59Z",
    "exportVersion": "1.0.0",
    "recordCount": 42,
    "organizationUrl": "https://org.crm.dynamics.com"
  },
  "summary": {
    "overallStatus": "Passed",
    "validationsRun": 42,
    "validationsPassed": 40,
    "validationsFailed": 2,
    "validationsWarning": 0
  },
  "validations": [
    {
      "name": "Zone 3 Session Controls",
      "runId": "run-20260209-060000",
      "zone": "Zone 3",
      "severity": "Passed",
      "validationType": "SessionControls",
      "signInFrequencyMinutes": 60,
      "authStrength": "Phishing-resistant MFA",
      "requireCompliantDevice": true,
      "reason": "Session controls match baseline configuration",
      "timestamp": "2026-02-09T06:00:00Z"
    }
  ]
}
```

### Metadata Fields

| Field | Description |
|-------|-------------|
| exportedAt | ISO 8601 timestamp of export generation |
| scope | Always "SessionSecurity" for SSC exports |
| zone | Zone filter applied (or "All") |
| fromDate | Start of validation date range |
| toDate | End of validation date range |
| exportVersion | Evidence schema version |
| recordCount | Number of validation records in export |
| organizationUrl | Dataverse organization URL |

### Summary Fields

| Field | Description |
|-------|-------------|
| overallStatus | Aggregate status (Error > Failed > GracePeriod > Warning > Passed) |
| validationsRun | Total validation records in export |
| validationsPassed | Count of Passed severity results |
| validationsFailed | Count of Failed severity results |
| validationsWarning | Count of Warning severity results |

## Verifying Evidence Integrity

Use `Test-EvidenceIntegrity.ps1` to verify SHA-256 hashes before submitting evidence to examiners.

### Verify Single File

```powershell
.\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidenceFilePath .\exports\session-security-evidence-Zone3-20260209-143022.json
```

### Batch Verification

```powershell
Get-ChildItem .\exports\*.json | ForEach-Object {
    $result = .\scripts\Test-EvidenceIntegrity.ps1 -EvidenceFilePath $_.FullName -Quiet
    [PSCustomObject]@{ 
        File = $_.Name
        Valid = $result 
    }
} | Format-Table
```

### Quiet Mode for Automation

```powershell
$isValid = .\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidenceFilePath .\exports\session-security-evidence-Zone3-20260209-143022.json `
    -Quiet

if (-not $isValid) {
    Write-Error "Evidence integrity check failed"
    exit 1
}
```

## Recommended Export Schedule

| Use Case | Schedule | Zone Filter | Retention |
|----------|----------|-------------|-----------|
| Weekly compliance check | Sunday 2:00 AM | All | 90 days |
| Monthly examination prep | 1st of month | All | 2 years |
| Zone 3 audit trail | Daily 7:00 AM | Zone 3 only | 730 days |
| On-demand examination | Ad-hoc | As requested | Permanent |

## Troubleshooting

| Error | Cause | Resolution |
|-------|-------|------------|
| 401 Unauthorized | Token expired or invalid | Re-authenticate with `-Interactive` |
| 404 Not Found | Table doesn't exist | Verify Dataverse schema deployed |
| No records returned | Date range has no data | Expand date range or verify validation flow ran |
| Hash mismatch | File modified after export | Re-export evidence; never modify exported files |
| Connection timeout | Network or Dataverse issue | Retry; check network access to *.crm.dynamics.com |

## Related Documentation

- [Prerequisites](PREREQUISITES.md) — Required modules and permissions
- [Dataverse Schema](DATAVERSE-SCHEMA.md) — ValidationHistory table structure
- [Troubleshooting](TROUBLESHOOTING.md) — Complete error reference
