# Content Moderation Monitor Solution - Customer Delivery Checklist

## Files to Include in Customer Package

### 1. Documentation
- [ ] **SOLUTION-DOCUMENTATION.md** — Main technical documentation (Executive Summary + Technical Details)

### 2. Solution Components

**PowerShell Scripts** (from `scripts/` directory):
- [ ] **Test-ContentModerationCompliance.ps1** — Primary validation orchestrator
- [ ] **Get-AgentModerationSettings.ps1** — Agent moderation level query helper
- [ ] **Compare-ModerationCompliance.ps1** — Compliance comparison logic
- [ ] **Export-ContentModerationEvidence.ps1** — SHA-256 evidence export
- [ ] **Test-EvidenceIntegrity.ps1** — Evidence hash verification
- [ ] **Invoke-ModerationBaselineCapture.ps1** — Baseline capture utility
- [ ] **Start-ModerationValidationRunbook.ps1** — Azure Automation wrapper

**Private Helpers** (from `scripts/private/` directory):
- [ ] **CMMClient.psm1** — Dataverse client module
- [ ] **Get-ZoneClassification.ps1** — Zone lookup helper (delegates to shared module, see Dependencies below)
- [ ] **Get-ExpectedModerationLevel.ps1** — Moderation level reference
- [ ] **Connect-EnvironmentDataverse.ps1** — Per-env Dataverse auth
- [ ] **Test-ParameterValidation.ps1** — Parameter validators
- [ ] **Get-CMMValidationResults.ps1** — Evidence query helper

**Python Deployment Scripts** (from `scripts/` directory):
- [ ] **cmm_client.py** — Python Dataverse client library
- [ ] **create_dataverse_schema.py** — Dataverse table/column deployment
- [ ] **create_environment_variables.py** — Environment variable deployment
- [ ] **create_connection_references.py** — Connection reference deployment
- [ ] **deploy.py** — Orchestrates full Dataverse schema deployment
- [ ] **requirements.txt** — Python package dependencies

**Power Automate:**
- [ ] **src/moderation-validation-flow.json** — Daily scheduled validation flow

**Templates:**
- [ ] **moderation-baseline.json** — Zone requirements reference
- [ ] **adaptive-card-moderation-alert.json** — Teams alert template

**Supporting Documentation** (from `docs/` directory):
- [ ] **PREREQUISITES.md** — Module and permission requirements
- [ ] **SCHEMA.md** — Dataverse schema reference
- [ ] **EVIDENCE_EXPORT.md** — Evidence export guide
- [ ] **FLOW_SETUP.md** — Power Automate setup guide
- [ ] **TROUBLESHOOTING.md** — Troubleshooting guide

### 3. Packaging Instructions

> **External Dependency:** `scripts/private/Get-ZoneClassification.ps1` delegates to a shared
> module at `scripts/shared/Get-ZoneClassification.ps1` (outside this solution directory).
> Ensure the shared module is available on the deployment target or replace the delegate
> script with a self-contained implementation. See `PREREQUISITES.md` for details.

**Option A: Create ZIP Archive**
```bash
# From the content-moderation-monitor directory:
zip -r Content-Moderation-Monitor-v1.0.0.zip \
  SOLUTION-DOCUMENTATION.md \
  scripts/*.ps1 \
  scripts/private/*.ps1 \
  scripts/private/*.psm1 \
  scripts/*.py \
  scripts/requirements.txt \
  src/moderation-validation-flow.json \
  src/adaptive-card-moderation-alert.json \
  templates/moderation-baseline.json \
  docs/PREREQUISITES.md \
  docs/SCHEMA.md \
  docs/EVIDENCE_EXPORT.md \
  docs/FLOW_SETUP.md \
  docs/TROUBLESHOOTING.md
```

### 4. Email Template

**Subject:** Content Moderation Monitor - Solution Delivery v1.0.0

**Body:**

```
Hi [Customer Name],

Please find attached the Content Moderation Monitor solution package, version 1.0.0.

This solution provides automated per-agent validation of content moderation levels across
all Copilot Studio agents with zone-based compliance requirements, drift detection, and
SHA-256 integrity-hashed evidence export.

Package Contents:
- SOLUTION-DOCUMENTATION.md — Complete technical documentation
- 12 PowerShell Scripts (validation, evidence export, Dataverse integration)
- 5 Python Scripts (Dataverse schema/variable/connection deployment)
- 1 requirements.txt (Python dependencies)
- 1 Power Automate flow (daily scheduled orchestration)
- 2 Templates (zone requirements, Teams alert card)
- 5 Supporting Documentation Files

Key Capabilities:
✓ Per-agent validation (not environment-level, individual agent assessment)
✓ Zone-based requirements (Zone 1: Medium min, Zone 2/3: High required)
✓ Severity classification (Critical/High/Medium/Warning)
✓ Drift detection (daily baseline comparison)
✓ Teams adaptive card alerts with regulatory context
✓ SHA-256 integrity-hashed evidence for audit examinations

Zone Requirements:
• Zone 1 (Personal): Medium minimum
• Zone 2 (Team): High required
• Zone 3 (Enterprise): High required

Violation Severity Matrix:
• Zone 3 + Low moderation = CRITICAL (FINRA 3110 — Unmoderated customer-facing agent)
• Zone 3 + Medium moderation = HIGH (GLBA 501(b) — Insufficient content protection)
• Zone 2 + Low moderation = HIGH (SOX 404 — Inadequate content controls)

Business Value:
• Help ensure consistent content moderation across all AI agents (100% coverage)
• Detect and remediate Critical violations within 24 hours (daily scans)
• Support regulatory examinations with automated compliance evidence
• Enable zone-based risk management with tailored moderation requirements

Regulatory Support:
• FINRA 3110 — Supervision
• SOX 404 — Internal Controls over Financial Reporting
• GLBA 501(b) — Safeguards Rule

Next Steps:
1. Review SOLUTION-DOCUMENTATION.md (Section 2: Technical Details)
2. Install PowerShell modules:
   - Microsoft.PowerApps.Administration.PowerShell (2.0+)
   - Az.Accounts (2.0+)
   - MSAL.PS (4.37+)
3. Run test validation: Test-ContentModerationCompliance -WhatIf
4. Deploy Dataverse schema (optional, for persistence and drift detection)
5. Import Power Automate flow for daily orchestration
6. Capture initial baseline for drift detection
7. Schedule deployment planning session (recommended: 2-3 hours)

CRITICAL CONFIGURATION REQUIREMENTS:

1. **Zone Classification:**
   - Environments MUST be assigned to zones (Zone 1/2/3)
   - Without zone assignment, all violations show as "Warning" severity
   - Use environment naming convention (Zone1-, Zone2-, Zone3-) OR configure ELM Dataverse

2. **Per-Agent Validation:**
   - This solution validates EACH AGENT individually (not environment-level)
   - Single environment may contain both compliant and non-compliant agents
   - Remediation targets specific agents (update moderation level in Copilot Studio)

3. **Severity Matrix:**
   - Critical = Zone 3 customer-facing agent with Low moderation → IMMEDIATE ACTION REQUIRED
   - High = Zone 2/3 agent with Low moderation OR Zone 3 with Medium → Fix within 2 days
   - Medium = Zone 2 agent with Medium moderation → Best practice uplift
   - Warning = Unclassified environment → Assign zone within 30 days

4. **Drift Detection:**
   - Requires initial baseline capture (Invoke-ModerationBaselineCapture.ps1)
   - Detects downgrades: High → Medium, High → Low, Medium → Low
   - Baseline updated when moderation level increases (not decreases)

5. **Evidence Export:**
   - SHA-256 integrity hash ensures tamper detection
   - Companion .sha256 file contains hash for verification
   - Use Test-EvidenceIntegrity.ps1 to validate before submitting to auditors

Please let me know if you have any questions or need clarification.

Best regards,
[Your Name]
```

### 5. Pre-Delivery Validation

- [ ] All 26+ files included (scripts, Python scripts, templates, docs)
- [ ] SOLUTION-DOCUMENTATION.md renders correctly
- [ ] PowerShell scripts have no syntax errors (use PSScriptAnalyzer)
- [ ] moderation-baseline.json is valid JSON
- [ ] No sensitive data in files (tenant IDs, emails = placeholders)
- [ ] Version numbers consistent (v1.0.0)

### 6. Files NOT to Include

- ❌ README.md (internal reference)
- ❌ CHANGELOG.md (version history)
- ❌ .git/ folder

### 7. Customer Requirements

**Licensing:**
- Power Platform Admin permissions
- Power Apps Premium (Dataverse)
- Power Automate Premium (cloud flow)

**PowerShell Modules:**
- Microsoft.PowerApps.Administration.PowerShell (2.0+)
- Az.Accounts (2.0+)
- MSAL.PS (4.37+)

**Python (for Dataverse schema deployment):**
- Python 3.9+
- Dependencies listed in `scripts/requirements.txt`

**Permissions:**
- Power Platform Admin (tenant-wide environment enumeration)
- Dataverse Reader (per-environment agent query)
- Dataverse User (governance environment, if using persistence)

### 8. Follow-Up Support

- PowerShell script execution assistance
- Zone classification workshop
- Baseline capture and drift detection training
- Monthly violation trend review
- Evidence export for regulatory examinations

### 9. Deployment Validation Checklist

```
PowerShell Modules:
□ Microsoft.PowerApps.Administration.PowerShell installed
□ Az.Accounts installed
□ MSAL.PS installed

Authentication:
□ Add-PowerAppsAccount executed successfully
□ Power Platform environments enumerated

Test Execution:
□ Dry-run validation executed: Test-ContentModerationCompliance -WhatIf
□ Violations detected and displayed in table format
□ JSON output tested: Test-ContentModerationCompliance -OutputFormat Json

Dataverse (Optional):
□ Python 3.9+ installed with requirements.txt dependencies
□ Dataverse schema deployed: python scripts/deploy.py (3 tables created)
□ Environment variables deployed: python scripts/create_environment_variables.py
□ Connection references deployed: python scripts/create_connection_references.py
□ Validation history persisted: Test-ContentModerationCompliance -PersistResults
□ Records visible in fsi_moderationvalidationhistory table

Baseline Capture (Optional):
□ Initial baseline captured: Invoke-ModerationBaselineCapture.ps1
□ Baseline records created in fsi_moderationbaseline table
□ Active baseline flag verified

Power Automate Flow (Optional):
□ moderation-validation-flow.json imported
□ Connection references configured
□ Environment variables set
□ Flow activated (daily 06:00 UTC schedule)
□ Test execution successful

Evidence Export:
□ Evidence exported: Export-ContentModerationEvidence.ps1
□ SHA-256 hash file generated
□ Integrity verified: Test-EvidenceIntegrity.ps1 → PASSED
```

---

**Package Version:** v1.0.0
**Release Date:** February 2026
**Solution:** Content Moderation Monitor
