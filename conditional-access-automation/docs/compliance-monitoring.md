# Compliance Monitoring

Monitor Conditional Access policy compliance, detect drift, and generate evidence for regulatory examination.

## Monitoring Overview

| Capability | Script | Frequency |
|------------|--------|-----------|
| Policy compliance check | `Test-PolicyCompliance.ps1` | Weekly |
| Configuration drift detection | `Watch-PolicyDrift.ps1` | Daily |
| Evidence export | `Export-CAAComplianceEvidence.ps1` | Quarterly |
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
    -TenantId   "<tenant-id>" `
    -OutputPath "./baselines/baseline.json"
```

> `-OutputPath` is a **file path**, not a directory. The script writes the
> baseline JSON to that path verbatim and creates the parent folder if needed.

### Drift Detection

```powershell
.\scripts\Watch-PolicyDrift.ps1 `
    -TenantId     "<tenant-id>" `
    -BaselinePath "./baselines/baseline.json"
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
  "type": "AdaptiveCard",
  "version": "1.4",
  "body": [
    {
      "type": "Container",
      "style": "attention",
      "items": [
        {
          "type": "TextBlock",
          "text": "[ALERT] CA Policy Drift Detected",
          "weight": "Bolder",
          "size": "Large",
          "wrap": true
        }
      ]
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "Policy", "value": "CA-FSI-CopilotStudio-Zone3-MFA-CompliantDevice" },
        { "title": "Change", "value": "Policy disabled" },
        { "title": "Changed By", "value": "admin@contoso.com" },
        { "title": "Time", "value": "2026-02-15 10:30:00 UTC" }
      ]
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "title": "View in Entra ID",
      "url": "https://entra.microsoft.com/..."
    }
  ]
}
```

### Scheduled Drift Detection

Create a scheduled task or Azure Automation runbook:

```powershell
# Azure Automation Runbook
param(
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$CertificateThumbprint,
    [Parameter(Mandatory)] [string]$BaselineFilePath,
    [Parameter(Mandatory)] [string]$TeamsWebhook
)

# App-only certificate auth — Connect-MgGraph -Identity is NOT supported by
# the Conditional Access Graph endpoints when the runbook needs delegated
# scope semantics. Use a registered app + cert.
. .\private\Connect-GraphSession.ps1
Connect-CAAGraphSession -TenantId $TenantId -ClientId $ClientId `
    -CertificateThumbprint $CertificateThumbprint

# Watch-PolicyDrift writes its findings to the OutputPath JSON file and
# returns drift records for the caller. -BaselinePath expects a FILE PATH,
# not a parsed JSON object.
$drift = .\Watch-PolicyDrift.ps1 -TenantId $TenantId `
    -BaselinePath $BaselineFilePath `
    -OutputPath   "./drift-report.json"

# Alert if drift detected
if ($drift -and $drift.Count -gt 0) {
    Send-TeamsAlert -Webhook $TeamsWebhook -Drift $drift
}
```

---

## Evidence Export

### Purpose

Generate compliance evidence for regulatory examinations (FINRA, SEC, OCC).
Helps support recordkeeping requirements; organizations should verify retention
and authenticity controls meet their specific regulatory obligations.

### Usage

```powershell
Connect-AzAccount -TenantId "<tenant-guid>"

.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId    "<tenant-guid>" `
    -OutputPath  "./evidence" `
    -FromDate    "2026-01-01" `
    -ToDate      "2026-03-31"
```

### Output Files

The export produces a single JSON document per run plus a SHA-256 companion:

| File | Content |
|------|---------|
| `CAA-Evidence-<UTC-timestamp>.json` | Validation history, active violations, active baselines, summary, zone breakdown — combined |
| `CAA-Evidence-<UTC-timestamp>.json.sha256` | sha256sum-compatible hash for integrity verification |

There is no per-table file split (no `CAPolicies*.json`, `SignInLogs*.json`,
`MFAUsage*.json`, or `manifest.json`). Sign-in and MFA usage data are sourced
from Microsoft Graph reporting endpoints separately and are out of scope for
the CAA evidence export.

### Evidence Content

#### Combined Evidence Document Layout

```json
{
  "exportInfo": {
    "timestamp": "2026-04-01T00:00:00Z",
    "exportedBy": "Export-CAAComplianceEvidence.ps1",
    "version": "1.2.2"
  },
  "tenantId": "<tenant-id>",
  "summary": {
    "passed": 120, "warning": 4, "failed": 1, "overallStatus": "Warning"
  },
  "zoneBreakdown": {
    "Zone1": { "passed": 40, "warning": 0, "failed": 0, "total": 40 },
    "Zone2": { "passed": 40, "warning": 2, "failed": 0, "total": 42 },
    "Zone3": { "passed": 40, "warning": 2, "failed": 1, "total": 43 }
  },
  "validations": [ /* fsi_capolicyvalidationhistories rows */ ],
  "violations":  [ /* fsi_capolicyviolations rows (active only) */ ],
  "baselines":   [ /* fsi_capolicybaselines rows (active only) */ ]
}
```

### Integrity Verification

```powershell
.\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidencePath "./evidence/CAA-Evidence-20260401T000000Z.json"

# or sha256sum on Linux / macOS:
# sha256sum -c CAA-Evidence-20260401T000000Z.json.sha256
```

---

### Evidence Content Reference

For the document layout produced by `Export-CAAComplianceEvidence.ps1`, see
the layout block above. Per-record schemas for `validations`, `violations`,
and `baselines` follow the Dataverse table definitions in
[`docs/dataverse-schema.md`](dataverse-schema.md):

- `validations` mirrors `fsi_capolicyvalidationhistories`
- `violations` mirrors `fsi_capolicyviolations` (filtered to `fsi_is_active eq true`)
- `baselines` mirrors `fsi_capolicybaselines` (filtered to `fsi_is_active eq true`)

Sign-in event data, MFA completion statistics, and Conditional Access audit
logs are sourced from Microsoft Graph reporting endpoints (e.g.,
`/auditLogs/signIns`, `/auditLogs/directoryAudits`) and are intentionally not
included in the CAA evidence package — pull those separately and archive them
alongside the CAA-Evidence file when required by your compliance program.

---

## Coverage Gap Analysis

### Identify Unprotected Applications

```powershell
.\scripts\Test-PolicyCompliance.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -OutputPath "./reports"
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

### Teams Alert Setup

Both Power Automate flows use the **Teams connector** (`PostCardToConversation` / `PostMessageToChannelV3`) with the `fsi_cr_teams_conditionalaccessautomation` connection reference — not incoming webhooks. To configure:

1. Set the `fsi_CAA_TeamsGroupId` environment variable to the target Teams group GUID
2. Set the `fsi_CAA_TeamsChannelId` environment variable to the target channel GUID
3. Ensure the Teams connection reference is authenticated in the Power Platform solution

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
