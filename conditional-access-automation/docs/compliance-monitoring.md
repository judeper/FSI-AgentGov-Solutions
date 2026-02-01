# Compliance Monitoring

Monitor Conditional Access policy compliance, detect drift, and generate evidence for regulatory examination.

## Monitoring Overview

| Capability | Script | Frequency |
|------------|--------|-----------|
| Policy compliance check | `Test-PolicyCompliance.ps1` | Weekly |
| Configuration drift detection | `Watch-PolicyDrift.ps1` | Daily |
| Evidence export | `Export-PolicyEvidence.ps1` | Quarterly |
| Coverage gap analysis | `Test-PolicyCompliance.ps1` | On-demand |

---

## Policy Compliance Check

### Purpose

Verify that deployed CA policies match expected configuration and cover all required scenarios.

### Usage

```powershell
.\scripts\Test-PolicyCompliance.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -OutputPath "./reports" `
    [-IncludeReportOnly]
```

### Output Files

| File | Content |
|------|---------|
| `PolicyCoverage-YYYY-MM-DD.json` | Coverage analysis by zone and application |
| `PolicyGaps-YYYY-MM-DD.json` | Identified gaps and recommendations |
| `ComplianceReport-YYYY-MM-DD.html` | Human-readable summary report |

### Compliance Checks

The script verifies:

1. **Policy Existence** - Expected policies exist
2. **Policy State** - Policies are enabled (not report-only or disabled)
3. **Target Coverage** - All zones and applications covered
4. **Exclusion Integrity** - Break-glass accounts properly excluded
5. **Grant Controls** - MFA and device requirements correct
6. **Session Controls** - Timeout values match zone requirements

### Sample Output

```json
{
  "timestamp": "2026-02-15T10:30:00Z",
  "overallCompliance": "Compliant",
  "checksPerformed": 24,
  "checksPassed": 24,
  "checksFailed": 0,
  "coverage": {
    "zone1": { "status": "Covered", "policies": 2 },
    "zone2": { "status": "Covered", "policies": 3 },
    "zone3": { "status": "Covered", "policies": 4 }
  },
  "gaps": []
}
```

---

## Configuration Drift Detection

### Purpose

Detect unauthorized changes to CA policies that could weaken security posture.

### Baseline Export

First, export a known-good baseline:

```powershell
.\scripts\Export-PolicyBaseline.ps1 `
    -TenantId "<tenant-id>" `
    -OutputPath "./baseline"
```

### Drift Detection

```powershell
.\scripts\Watch-PolicyDrift.ps1 `
    -TenantId "<tenant-id>" `
    -BaselinePath "./baseline" `
    -AlertWebhook "<teams-webhook-url>" `
    [-SilentMode]
```

### Detected Changes

| Change Type | Severity | Alert |
|-------------|----------|-------|
| Policy disabled | Critical | Immediate |
| Policy deleted | Critical | Immediate |
| Exclusion added | High | Immediate |
| Grant control weakened | High | Immediate |
| Session timeout increased | Medium | Daily digest |
| Display name changed | Low | Weekly digest |

### Teams Alert Format

```json
{
  "@type": "MessageCard",
  "themeColor": "FF0000",
  "title": "CA Policy Drift Detected",
  "text": "Unauthorized change to Conditional Access policy",
  "sections": [{
    "facts": [
      { "name": "Policy", "value": "CA-FSI-CopilotStudio-Zone3-MFA-CompliantDevice" },
      { "name": "Change", "value": "Policy disabled" },
      { "name": "Changed By", "value": "admin@contoso.com" },
      { "name": "Time", "value": "2026-02-15 10:30:00 UTC" }
    ]
  }],
  "potentialAction": [{
    "@type": "OpenUri",
    "name": "View in Entra ID",
    "targets": [{ "os": "default", "uri": "https://entra.microsoft.com/..." }]
  }]
}
```

### Scheduled Drift Detection

Create a scheduled task or Azure Automation runbook:

```powershell
# Azure Automation Runbook
param(
    [string]$TenantId,
    [string]$KeyVaultName,
    [string]$BaselineBlobUrl,
    [string]$TeamsWebhook
)

# Authenticate using managed identity
Connect-MgGraph -Identity

# Download baseline from blob storage
$baseline = Invoke-WebRequest -Uri $BaselineBlobUrl | ConvertFrom-Json

# Check for drift
$drift = .\Watch-PolicyDrift.ps1 -TenantId $TenantId -Baseline $baseline

# Alert if drift detected
if ($drift.Count -gt 0) {
    Send-TeamsAlert -Webhook $TeamsWebhook -Drift $drift
}
```

---

## Evidence Export

### Purpose

Generate compliance evidence for regulatory examinations (FINRA, SEC, OCC).

### Usage

```powershell
.\scripts\Export-PolicyEvidence.ps1 `
    -TenantId "<tenant-id>" `
    -OutputPath "./evidence" `
    -StartDate "2026-01-01" `
    -EndDate "2026-03-31"
```

### Output Files

| File | Content |
|------|---------|
| `CAPolicies-Q1-2026.json` | Complete policy configurations |
| `PolicyAuditLog-Q1-2026.json` | Policy change audit trail |
| `SignInLogs-Q1-2026.json` | Sign-in events with CA evaluation |
| `MFAUsage-Q1-2026.json` | MFA completion statistics |
| `manifest.json` | SHA-256 hashes for integrity |

### Evidence Content

#### Policy Configuration Export

```json
{
  "exportDate": "2026-04-01T00:00:00Z",
  "tenantId": "<tenant-id>",
  "policies": [
    {
      "id": "<policy-id>",
      "displayName": "CA-FSI-CopilotStudio-Zone3-MFA-CompliantDevice",
      "state": "enabled",
      "createdDateTime": "2026-01-15T10:00:00Z",
      "modifiedDateTime": "2026-01-15T10:00:00Z",
      "conditions": { ... },
      "grantControls": { ... },
      "sessionControls": { ... }
    }
  ]
}
```

#### Audit Log Export

```json
{
  "exportDate": "2026-04-01T00:00:00Z",
  "events": [
    {
      "timestamp": "2026-02-01T14:30:00Z",
      "activity": "Update conditional access policy",
      "actor": "admin@contoso.com",
      "policyId": "<policy-id>",
      "policyName": "CA-FSI-CopilotStudio-Zone3-MFA-CompliantDevice",
      "changes": {
        "state": { "old": "enabledForReportingButNotEnforced", "new": "enabled" }
      }
    }
  ]
}
```

#### Sign-In Log Export

```json
{
  "exportDate": "2026-04-01T00:00:00Z",
  "summary": {
    "totalSignIns": 150000,
    "mfaRequired": 45000,
    "mfaCompleted": 44800,
    "blocked": 200,
    "byPolicy": {
      "CA-FSI-CopilotStudio-Zone3-MFA-CompliantDevice": {
        "applied": 12000,
        "granted": 11950,
        "blocked": 50
      }
    }
  },
  "signIns": [ ... ]  // Detailed records
}
```

### Integrity Verification

The manifest includes SHA-256 hashes:

```json
{
  "exportInfo": {
    "timestamp": "2026-04-01T00:00:00Z",
    "exportedBy": "Export-PolicyEvidence.ps1 v1.0.0"
  },
  "files": [
    {
      "filename": "CAPolicies-Q1-2026.json",
      "sha256": "abc123...",
      "recordCount": 8
    },
    {
      "filename": "PolicyAuditLog-Q1-2026.json",
      "sha256": "def456...",
      "recordCount": 24
    }
  ]
}
```

Verify integrity:

```powershell
$manifest = Get-Content "./evidence/manifest.json" | ConvertFrom-Json
foreach ($file in $manifest.files) {
    $hash = (Get-FileHash "./evidence/$($file.filename)" -Algorithm SHA256).Hash
    if ($hash -eq $file.sha256) {
        Write-Host "✓ $($file.filename): Verified" -ForegroundColor Green
    } else {
        Write-Host "✗ $($file.filename): FAILED" -ForegroundColor Red
    }
}
```

---

## Coverage Gap Analysis

### Identify Unprotected Applications

```powershell
.\scripts\Test-PolicyCompliance.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -OutputPath "./reports" `
    -AnalyzeGaps
```

### Gap Report

```json
{
  "gaps": [
    {
      "type": "ApplicationNotCovered",
      "application": "Custom AI Agent",
      "appId": "<app-id>",
      "recommendation": "Add to Zone 2 policy or create dedicated policy"
    },
    {
      "type": "ZoneNotCovered",
      "zone": "Zone 1",
      "application": "Agent Builder",
      "recommendation": "Create CA-AgentBuilder-Zone1 policy"
    },
    {
      "type": "WeakControl",
      "policy": "CA-FSI-M365Copilot-AllZones-RiskBasedMFA",
      "issue": "Risk-based MFA may not trigger for low-risk sign-ins",
      "recommendation": "Consider always requiring MFA for regulated users"
    }
  ]
}
```

---

## Regulatory Alignment

### NIST 800-53 Mapping

| Control | Requirement | Evidence |
|---------|-------------|----------|
| AC-2 | Account management | Policy configurations, exclusion lists |
| AC-7 | Unsuccessful logon attempts | Sign-in logs with failures |
| IA-2 | Identification and authentication | MFA enforcement records |
| IA-5 | Authenticator management | MFA registration status |

### SOX 404 Evidence

For IT General Controls (ITGC):

1. **Access Control** - CA policy configurations showing MFA requirements
2. **Change Management** - Audit logs showing policy changes with approvals
3. **Segregation of Duties** - Different admins for policy creation vs. approval

### FINRA Evidence

For supervision and access control:

1. **Policy documentation** - Full CA policy export
2. **Enforcement records** - Sign-in logs showing MFA completion
3. **Change history** - Audit trail of policy modifications

---

## Alerting Configuration

### Teams Webhook Setup

1. Create incoming webhook in Teams channel
2. Copy webhook URL
3. Add to drift detection configuration

### Alert Thresholds

| Metric | Threshold | Alert |
|--------|-----------|-------|
| Policy disabled | Any | Critical |
| Policy deleted | Any | Critical |
| Exclusion added | Any | High |
| MFA bypass rate | >5% | Medium |
| Blocked sign-ins | >10/hour | Medium |
| Compliance score | <95% | Medium |

### Sample Alert Configuration

```json
{
  "alerts": {
    "critical": {
      "webhook": "<teams-webhook-critical>",
      "events": ["PolicyDisabled", "PolicyDeleted", "BreakGlassUsed"]
    },
    "high": {
      "webhook": "<teams-webhook-high>",
      "events": ["ExclusionAdded", "GrantControlWeakened"]
    },
    "medium": {
      "webhook": "<teams-webhook-ops>",
      "events": ["SessionTimeoutChanged", "ComplianceScoreLow"]
    }
  }
}
```
