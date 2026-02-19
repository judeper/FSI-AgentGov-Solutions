# Monitoring AI Agent Content Moderation Compliance
## Content Moderation Monitor

**Version:** 1.0.0
**Solution Type:** Automated Per-Agent Validation + Drift Detection
**Platform:** PowerShell + Power Automate + Dataverse

---

## Executive Summary

### Problem Statement

Copilot Studio agents with insufficient content moderation settings create significant risk exposure for financial services organizations. When agents deployed to customer-facing or team collaboration scenarios operate with "Low" or "Medium" moderation levels, they may generate inappropriate, offensive, or non-compliant content that violates regulatory requirements. Unlike environment-level controls, content moderation must be validated on a **per-agent basis** because individual agents within the same environment can have different moderation settings.

**Risk Exposure:**
- **Customer Harm:** Low-moderation customer-facing agents may generate offensive or harmful content
- **Compliance Violations:** Insufficient content controls violate supervisory requirements (FINRA 3110, SOX 404, GLBA 501(b))
- **Reputation Damage:** Inappropriate AI-generated responses damage brand trust and customer relationships
- **Regulatory Examinations:** Missing content moderation evidence creates audit findings
- **Inconsistent Governance:** Some agents properly configured while others remain unmoderated

### Solution Overview

The **Content Moderation Monitor** provides automated per-agent validation of content moderation levels across all Copilot Studio agents with zone-based compliance requirements. The solution validates each agent individually, detects configuration drift, generates severity-classified violations, and provides SHA-256 integrity-hashed evidence for regulatory examinations.

**Key Capabilities:**
- **Per-Agent Validation:** Validates each Copilot Studio agent's moderation level individually (not environment-level)
- **Zone-Based Requirements:** Different minimum moderation levels per governance zone (Zone 1: Medium min, Zone 2/3: High required)
- **Severity Classification:** Critical/High/Medium/Warning severity based on zone and actual moderation level
- **Drift Detection:** Daily baseline comparison detects when moderation levels are downgraded
- **Multiple Output Formats:** Table (human-readable), JSON (archival), Object (pipeline integration)
- **Teams Alerting:** Adaptive card alerts with per-agent severity and regulatory context
- **Evidence Export:** SHA-256 integrity-hashed JSON evidence for audit examinations

**Business Value:**
- Help ensure consistent content moderation across all AI agents (100% coverage)
- Detect and remediate High/Critical violations within 24 hours (daily scans)
- Support regulatory examinations with automated compliance evidence
- Prevent customer-facing agents from operating with insufficient content controls
- Enable zone-based risk management with tailored moderation requirements

---

## Technical Details

### Architecture Overview

The Content Moderation Monitor operates as PowerShell validation scripts with Power Automate orchestration and Dataverse persistence. The architecture follows a scan-validate-alert pattern with per-agent drift detection.

```
┌─────────────────────────────────────────────────────────────────────┐
│              Content Moderation Monitor Architecture                 │
│                 Per-Agent Validation + Drift Detection               │
└─────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────────┐     ┌──────────────────┐      ┌──────────────────┐
│  PowerShell       │     │  Power Automate  │      │  Dataverse       │
│  Validation       │────▶│  Orchestration   │─────▶│  Persistence     │
│  Scripts          │     │  (Daily Schedule)│      │  + Drift         │
│                   │     │                  │      │  Detection       │
│  1. Enumerate     │     │  1. Run          │      │                  │
│     environments  │     │     validation   │      │  Tables:         │
│  2. Query agents  │     │     script       │      │  - Validation    │
│     per env       │     │  2. Persist      │      │    History       │
│  3. Get moderation│     │     results      │      │  - Violations    │
│     level per     │     │  3. Detect drift │      │  - Baseline      │
│     agent         │     │  4. Send alerts  │      │                  │
│  4. Compare vs    │     │     (Critical/   │      │  Drift:          │
│     zone req      │     │     High)        │      │  - Compare       │
│  5. Classify      │     │                  │      │    current vs    │
│     severity      │     │                  │      │    baseline      │
│  6. Output        │     │                  │      │  - Detect        │
│     violations    │     │                  │      │    downgrades    │
└───────────────────┘     └──────────────────┘      └──────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────────┐     ┌──────────────────┐      ┌──────────────────┐
│  Teams Adaptive   │     │  Email Alert     │      │  Evidence Export │
│  Card             │     │  (Critical/High) │      │  (SHA-256)       │
│  (Critical only)  │     │                  │      │                  │
└───────────────────┘     └──────────────────┘      └──────────────────┘
```

### Zone Requirements

| Zone | Description | Minimum Moderation | Rationale |
|------|-------------|-------------------|-----------|
| **Zone 1** | Personal Productivity | Medium | Baseline content protection for individual use |
| **Zone 2** | Team Collaboration | High | Shared agents require stronger content controls |
| **Zone 3** | Enterprise Managed | High | Customer-facing agents require maximum protection |

### Violation Severity Matrix

| Zone | Actual Level | Severity | Regulatory Context |
|------|-------------|----------|-------------------|
| Zone 3 | Low | **Critical** | FINRA 3110 — Unmoderated customer-facing AI agent |
| Zone 3 | Medium | **High** | GLBA 501(b) — Insufficient content protection for enterprise agent |
| Zone 2 | Low | **High** | SOX 404 — Inadequate content controls for shared agent |
| Zone 2 | Medium | **Medium** | Best practice uplift recommended for team agents |
| Zone 1 | Low | **High** | Governance gap — Below minimum content moderation threshold |
| Unknown | Any non-compliant | **Warning** | Governance gap — Environment not assigned to zone |

### Solution Components

#### 1. Test-ContentModerationCompliance.ps1
**File:** `scripts/Test-ContentModerationCompliance.ps1`

**Purpose:** Primary validation script that orchestrates full content moderation compliance scans across all Copilot Studio agents.

**Process Flow:**

1. **Enumerate Power Platform Environments:**
   - Call `Get-AdminPowerAppEnvironment`
   - Apply filters: Exclude sandbox/trial/default (optional)
   - Apply grace period: Skip environments created within 48 hours (default)

2. **Per-Environment Agent Query:**
   - For each environment with Dataverse:
     - Authenticate to environment Dataverse
     - Query `bot` table for all agents
     - Filter: Published agents only (default) or include drafts with `-IncludeDrafts`

3. **Per-Agent Moderation Level Extraction:**
   - Parse agent JSON configuration (`bot.configuration` field)
   - Extract `contentModerationLevel` property
   - Normalize values: `"Low"`, `"Medium"`, `"High"`, or `"Unknown"`

4. **Zone Classification:**
   - If `-DataverseUrl` provided: Query environment lifecycle management table for zone
   - Else: Parse environment name for zone convention (`Zone1-`, `Zone2-`, `Zone3-`)
   - Fallback: `Unknown` zone

5. **Compliance Validation:**
   - Compare actual moderation level against zone minimum requirement
   - Determine violation severity using matrix (Critical/High/Medium/Warning)
   - Add regulatory context (FINRA 3110, SOX 404, GLBA 501(b))

6. **Output Results:**
   - **Table (default):** Color-coded severity with agent name, environment, zone, actual level, expected level, severity
   - **JSON:** Machine-readable format for evidence export pipeline
   - **Object:** Raw PSCustomObject array for PowerShell pipeline consumption

7. **Summary Statistics:**
   - Total agents scanned
   - Violations by severity (Critical/High/Medium/Warning)
   - Compliant agents count

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `WhatIf` | Switch | Dry-run mode (no Dataverse writes, no alerts) |
| `OutputFormat` | String | Table (default), Json, Object |
| `ExcludeSandbox` | Switch | Exclude sandbox environments |
| `ExcludeTrial` | Switch | Exclude trial environments |
| `ExcludeDefault` | Switch | Exclude default environment |
| `GracePeriodHours` | Int | Skip environments created within X hours (default: 48) |
| `IncludeDrafts` | Switch | Include unpublished agents (default: published only) |
| `IncludeCompliant` | Switch | Include compliant agents in output (default: violations only) |
| `DataverseUrl` | String | ELM Dataverse URL for zone lookup and result persistence |
| `PersistResults` | Switch | Write results to Dataverse (requires `-DataverseUrl`) |
| `BaselinePath` | String | Path to custom `moderation-baseline.json` file |

**Example Execution:**

```powershell
# Dry-run scan (safe, no writes)
Test-ContentModerationCompliance -WhatIf

# Production scan excluding sandbox/trial
Test-ContentModerationCompliance -ExcludeSandbox -ExcludeTrial

# Full scan with Dataverse persistence
Test-ContentModerationCompliance `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -PersistResults

# JSON output for evidence export
Test-ContentModerationCompliance -OutputFormat Json | Out-File violations.json
```

#### 2. Power Automate Flow — moderation-validation-flow.json
**File:** `src/moderation-validation-flow.json`

**Purpose:** Daily scheduled orchestration of content moderation validation with Dataverse persistence and conditional alerting.

**Trigger:**
- **Schedule:** Daily at 06:00 UTC
- **Type:** Recurrence trigger

**Workflow:**

1. **Run Validation Script:**
   - Execute `Test-ContentModerationCompliance.ps1` via Azure Automation webhook or inline PowerShell action
   - Parameters: `-DataverseUrl`, `-PersistResults`, `-ExcludeSandbox`, `-ExcludeTrial`

2. **Parse Validation Results:**
   - Extract summary statistics (total agents, violation counts by severity)
   - Extract individual violations (agent ID, environment, zone, severity, regulatory context)

3. **Persist to Dataverse:**
   - Write validation summary to `fsi_moderationvalidationhistory` table
   - Write individual violations to `fsi_moderationviolations` table
   - Correlate via `RunId` (GUID for each scan)

4. **Detect Drift:**
   - Query `fsi_moderationbaseline` for active baselines
   - Compare current moderation levels against baseline
   - Identify downgrades (High → Medium, High → Low, Medium → Low)
   - Add drift violations to alert payload

5. **Send Alerts (Conditional):**
   - **Critical violations:** Teams adaptive card + Email
   - **High violations:** Teams adaptive card + Email
   - **Medium/Warning violations:** Logged to Dataverse, no alert

**Adaptive Card Structure:**

```
┌─────────────────────────────────────────────────────────┐
│ [CRITICAL] Content Moderation Violations — 3 agents     │
│ Content Moderation Monitor · 2026-02-14 06:15:32 UTC   │
├─────────────────────────────────────────────────────────┤
│ Scan Summary                                             │
│ Status: Non-Compliant                                    │
│ Scanned: 2026-02-14 06:15:32 UTC                        │
│ Scan Run ID: abc-123-def                                │
│                                                          │
│ Total Agents: 147                                        │
│ Violations: 3                                            │
│ Environments: 12                                         │
├─────────────────────────────────────────────────────────┤
│ Violations (3)                                           │
│                                                          │
│ [CRITICAL] Customer Support Bot                         │
│ Environment: Finance Production (Zone 3)                │
│ Severity: Critical                                       │
│ Actual Level: Low | Required: High                      │
│ Regulatory: FINRA 3110 — Unmoderated customer-facing... │
│ Detected: 2026-02-14 06:15:45 UTC                       │
│                                                          │
│ [HIGH] HR Onboarding Agent                              │
│ Environment: HR Team (Zone 2)                           │
│ Severity: High                                           │
│ Actual Level: Low | Required: High                      │
│ Regulatory: SOX 404 — Inadequate content controls...    │
│ Detected: 2026-02-14 06:16:12 UTC                       │
└─────────────────────────────────────────────────────────┘
```

#### 3. Evidence Export — Export-ContentModerationEvidence.ps1
**File:** `scripts/Export-ContentModerationEvidence.ps1`

**Purpose:** SHA-256 integrity-hashed evidence export for regulatory examinations.

**Export Format:**

```json
{
  "evidenceType": "ContentModerationValidation",
  "exportTimestamp": "2026-02-14T15:30:00Z",
  "exportedBy": "admin@contoso.com",
  "dateRange": {
    "startDate": "2025-11-14T00:00:00Z",
    "endDate": "2026-02-14T23:59:59Z"
  },
  "filters": {
    "zones": ["Zone3"],
    "severities": ["Critical", "High"]
  },
  "validationHistory": [
    {
      "runId": "abc-123-def",
      "runTimestamp": "2026-02-14T06:15:32Z",
      "totalAgentsScanned": 147,
      "violationCount": 3,
      "criticalCount": 1,
      "highCount": 2
    }
  ],
  "violations": [
    {
      "agentId": "12345678-abcd-1234-abcd-123456789012",
      "agentName": "Customer Support Bot",
      "environmentId": "env-abc-123",
      "environmentName": "Finance Production",
      "zone": "Zone3",
      "actualLevel": "Low",
      "requiredLevel": "High",
      "severity": "Critical",
      "regulatory": "FINRA 3110 — Unmoderated customer-facing AI agent",
      "detectedAt": "2026-02-14T06:15:45Z"
    }
  ],
  "baseline": {
    "included": true,
    "baselineTimestamp": "2026-01-15T10:00:00Z",
    "baselineAgents": [
      {
        "agentId": "12345678-abcd-1234-abcd-123456789012",
        "agentName": "Customer Support Bot",
        "baselineLevel": "High"
      }
    ]
  },
  "metadata": {
    "framework": "FSI Agent Governance",
    "solution": "Content Moderation Monitor v1.0.0",
    "controlReference": "1.27"
  }
}
```

**Companion Hash File:**

```
evidence-cmm-Zone3-2026-02-14-153000.json.sha256:
abc123def456789012345678901234567890123456789012345678901234  cmm-evidence-Zone3-2026-02-14-153000.json
```

**Integrity Verification:**

```powershell
Test-EvidenceIntegrity -EvidenceFilePath ".\exports\evidence-cmm-Zone3-*.json"
# Output: PASSED — SHA-256 hash matches companion file
```

### Dataverse Schema

> For the complete schema reference including option sets, environment variables, connection references, and entity relationship diagram, see [docs/SCHEMA.md](docs/SCHEMA.md).

#### Table: fsi_moderationvalidationhistory

Purpose: Organization-owned immutable audit trail of validation scans with summary statistics.

| Column | Type | Description |
|--------|------|-------------|
| `fsi_moderationvalidationhistoryid` | GUID | Primary key |
| `fsi_name` | String(200) | Record name (`{Status}-{Timestamp}`) |
| `fsi_run_id` | String(36) | Correlation GUID for batch scan |
| `fsi_validation_time` | DateTime | Scan execution timestamp (UTC) |
| `fsi_total_agents` | Integer | Count of agents evaluated |
| `fsi_compliant_count` | Integer | Agents passing moderation checks |
| `fsi_violation_count` | Integer | Total violations detected |
| `fsi_overall_status` | String(50) | Passed, Failed, Warning, or Critical |
| `fsi_environments_scanned` | String(2000) | Comma-separated environment list |
| `fsi_summary_json` | Memo | Full JSON summary blob |

#### Table: fsi_moderationviolations

Purpose: Per-agent violation records with severity classification and regulatory context.

| Column | Type | Description |
|--------|------|-------------|
| `fsi_moderationviolationid` | GUID | Primary key |
| `fsi_name` | String(200) | Record name (`{AgentName}-{Zone}-{Date}`) |
| `fsi_environment_guid` | String(100) | Power Platform environment GUID |
| `fsi_environment_name` | String(500) | Environment display name |
| `fsi_agent_id` | String(100) | Copilot Studio agent GUID |
| `fsi_agent_name` | String(500) | Agent display name |
| `fsi_zone` | OptionSet (fsi_acv_zone) | Zone 1/2/3/Unclassified |
| `fsi_expected_level` | String(50) | Zone-required moderation level |
| `fsi_actual_level` | String(50) | Agent's current moderation level |
| `fsi_severity` | String(50) | Violation severity (Critical/High/Medium/Warning) |
| `fsi_regulatory_context` | String(2000) | Regulatory impact context (FINRA 3110, SOX 404, etc.) |
| `fsi_detected_at` | DateTime | Detection timestamp (UTC) |
| `fsi_run_id` | String(36) | Correlating scan GUID |

#### Table: fsi_moderationbaselines

Purpose: Per-agent moderation level snapshots for drift detection (one active baseline per agent).

| Column | Type | Description |
|--------|------|-------------|
| `fsi_moderationbaselineid` | GUID | Primary key |
| `fsi_name` | String(200) | Record name (`{AgentName}-{Zone}-{Timestamp}`) |
| `fsi_environment_guid` | String(100) | Power Platform environment GUID |
| `fsi_environment_name` | String(500) | Environment display name |
| `fsi_zone` | OptionSet (fsi_acv_zone) | Zone classification |
| `fsi_agent_id` | String(100) | Copilot Studio agent GUID |
| `fsi_agent_name` | String(500) | Agent display name at baseline capture |
| `fsi_moderation_level` | String(50) | Captured moderation level (Low/Medium/High) |
| `fsi_is_active` | Boolean | Active status (one active per agent) |
| `fsi_captured_at` | DateTime | Baseline capture timestamp (UTC) |
| `fsi_captured_by` | String(200) | User or service principal that captured baseline |
| `fsi_raw_json` | Memo | Full JSON snapshot of moderation settings |

### Configuration and Prerequisites

#### Prerequisites

**Microsoft 365 Licensing:**
- Power Platform Admin permissions
- Power Apps Premium (for Dataverse)
- Power Automate Premium (for cloud flow with Dataverse actions)

**PowerShell Modules:**
- `Microsoft.PowerApps.Administration.PowerShell` (2.0+)
- `Az.Accounts` (2.0+) — For Dataverse authentication
- `MSAL.PS` (4.37+) — For service principal authentication

**Permissions:**

| Role | Required For | Scope |
|------|--------------|-------|
| **Power Platform Admin** | Environment enumeration | Tenant-wide |
| **Dataverse Reader** | Agent query per environment | Per-environment |
| **Dataverse User** | Validation history writes (if `-PersistResults`) | Governance environment |

#### Configuration Steps

**Step 1: Install PowerShell Modules**

```powershell
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force
Install-Module -Name Az.Accounts -Force
Install-Module -Name MSAL.PS -Force
```

**Step 2: Connect to Power Platform**

```powershell
Add-PowerAppsAccount
```

**Step 3: Run Test Validation (Dry-Run)**

```powershell
cd /path/to/content-moderation-monitor/scripts
. ./Test-ContentModerationCompliance.ps1
Test-ContentModerationCompliance -WhatIf -ExcludeSandbox
```

**Step 4: Deploy Dataverse Schema (Optional)**

For Dataverse persistence and drift detection:

```bash
cd /path/to/content-moderation-monitor/scripts
python deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive
```

**Step 5: Import Power Automate Flow**

1. Navigate to Power Automate → My flows → Import
2. Upload `moderation-validation-flow.json`
3. Configure connection references:
   - Dataverse connection
   - Office 365 connection
   - Teams connection (if using Teams alerts)
4. Set environment variables:
   - `fsi_CMM_DataverseUrl`: Governance environment URL
   - `fsi_CMM_NotificationRecipients`: Compliance team emails
5. Activate flow

**Step 6: Capture Initial Baseline**

```powershell
cd /path/to/content-moderation-monitor/scripts
. ./Invoke-ModerationBaselineCapture.ps1
Invoke-ModerationBaselineCapture `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -Interactive
```

### Deployment Validation

**Test 1: Dry-Run Validation**

```powershell
Test-ContentModerationCompliance -WhatIf
# Expected: Table output with violations (if any), no Dataverse writes
```

**Test 2: JSON Output**

```powershell
Test-ContentModerationCompliance -OutputFormat Json | ConvertFrom-Json
# Expected: JSON array of violation objects
```

**Test 3: Dataverse Persistence**

```powershell
Test-ContentModerationCompliance `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -PersistResults
# Expected: Records created in fsi_moderationvalidationhistory and fsi_moderationviolations tables
```

**Test 4: Evidence Export**

```powershell
Export-ContentModerationEvidence `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputDirectory ".\exports" `
    -Interactive

Test-EvidenceIntegrity -EvidenceFilePath ".\exports\evidence-cmm-All-*.json"
# Expected: PASSED — SHA-256 hash matches
```

### Operational Guidance

#### Daily Operations

**Monitoring:**
- Review daily Power Automate flow execution results
- Investigate Critical and High violations within 4 business hours
- Track violation trends (increasing violations may indicate policy gaps)

**Violation Remediation:**

| Severity | Response Time | Action |
|----------|--------------|--------|
| **Critical** | Same day | Update agent moderation to High, validate in Copilot Studio |
| **High** | 2 business days | Review agent purpose, update moderation if shared/customer-facing |
| **Medium** | 1 week | Best practice uplift for team agents |
| **Warning** | 30 days | Assign environment to zone, re-validate |

**Monthly Tasks:**
- Review violation history trends
- Update zone classifications for new environments
- Export compliance evidence for audit folder
- Validate baseline accuracy (agents may be renamed or deleted)

#### Troubleshooting

**Issue: No violations detected but agents have Low moderation**

**Cause:** Zone classification returning "Unknown" (not enforcing minimum)

**Resolution:**
1. Verify environment naming convention includes zone prefix (`Zone1-`, `Zone2-`, `Zone3-`)
2. OR configure ELM Dataverse URL with `-DataverseUrl` parameter
3. OR manually assign zone in environment lifecycle management table

**Issue: Evidence export fails with "Access Denied"**

**Cause:** Missing MSAL.PS module or insufficient Dataverse permissions

**Resolution:**
1. Install MSAL.PS module: `Install-Module -Name MSAL.PS -Force`
2. Verify Dataverse User role assigned in governance environment
3. Re-run with `-Interactive` parameter for prompted authentication

---

## Appendix: Regulatory Alignment

### FINRA 3110 — Supervision

**Requirement:** Member firms must establish and maintain a system to supervise the activities of associated persons, including oversight of customer-facing technology.

**Solution Support:**
- Validates customer-facing agents (Zone 3) have High content moderation
- Critical severity violations for Zone 3 agents with Low moderation
- Immutable audit trail of validation history for examination evidence

### SOX 404 — Internal Controls over Financial Reporting

**Requirement:** Management must establish and maintain adequate internal controls, including IT controls for content validation.

**Solution Support:**
- Automated daily validation ensures content moderation controls remain effective
- Drift detection identifies when controls are weakened (High → Low)
- Evidence export provides audit trail of control effectiveness

### GLBA 501(b) — Safeguards Rule

**Requirement:** Financial institutions must implement administrative, technical, and physical safeguards to protect customer information.

**Solution Support:**
- Content moderation prevents inappropriate disclosures via AI agents
- Zone-based requirements align with data sensitivity (customer data = Zone 3 = High moderation)
- Monitoring ensures safeguards remain active

---

## Support and Maintenance

**Solution Version:** 1.0.0
**Release Date:** February 2026
**License:** MIT License

**Change Management:**
- Test baseline updates in non-production first
- Document zone classification changes in change tickets
- Review severity matrix quarterly (regulatory context may evolve)
- Coordinate moderation policy updates with business stakeholders

**Version History:**
- **v1.0.0 (February 2026):** Initial release with per-agent validation, drift detection, and evidence export

---

*This solution supports compliance with FINRA 3110, SOX 404, and GLBA 501(b). Consult with your compliance and legal teams for applicability to your organization's regulatory requirements.*
