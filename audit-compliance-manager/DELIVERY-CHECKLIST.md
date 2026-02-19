# ACM Solution - Customer Delivery Checklist

## Files to Include in Customer Package

### 1. Documentation
- [ ] **SOLUTION-DOCUMENTATION.md** — Main technical documentation (Executive Summary + Technical Details)

### 2. Solution Components (Source Files)

All files located in the `scripts/`, `templates/`, and `docs/` directories:

**PowerShell Components:**
- [ ] **AuditComplianceHelpers.psm1** — Shared helper module (MI auth, retry, Dataverse, email)
- [ ] **AuditComplianceHelpers.psd1** — Module manifest
- [ ] **Check-AuditLoggingCompliance.ps1** — Detection runbook (ALCA)
- [ ] **Enable-AuditLogging.ps1** — Remediation runbook (ALCA)
- [ ] **Invoke-TenantAuditValidation.ps1** — Tenant-level validation orchestrator (ACV)
- [ ] **Invoke-EnvironmentAuditValidation.ps1** — Environment-level validation orchestrator (ACV)
- [ ] **Invoke-EnvironmentDiscovery.ps1** — Environment discovery script (ACV)
- [ ] **Start-TenantValidationRunbook.ps1** — Tenant validation runbook entry point (ACV)
- [ ] **Start-EnvironmentValidationRunbook.ps1** — Environment validation runbook entry point (ACV)
- [ ] **Export-AuditValidationEvidence.ps1** — Evidence export with SHA-256 hashing (ACV)
- [ ] **Test-UnifiedAuditLog.ps1** — Unified audit log validation (ACV)
- [ ] **Test-MailboxAudit.ps1** — Mailbox audit validation (ACV)
- [ ] **Test-PurviewRetention.ps1** — Purview retention validation (ACV)
- [ ] **Test-EnvironmentAudit.ps1** — Environment audit validation (ACV)
- [ ] **Test-EnvironmentRetention.ps1** — Environment retention validation (ACV)
- [ ] **Test-EvidenceIntegrity.ps1** — Evidence hash verification (ACV)
- [ ] **scripts/private/Compare-ValidationBaseline.ps1** — Drift detection (ACV)
- [ ] **scripts/private/Connect-AuditServices.ps1** — Service connection helper (ACV)
- [ ] **scripts/private/Connect-PowerPlatform.ps1** — Power Platform connection helper (ACV)
- [ ] **scripts/private/Get-ValidationResults.ps1** — Validation results query (ACV)
- [ ] **scripts/private/New-CanaryEvent.ps1** — Canary event creation (ACV)
- [ ] **scripts/private/Write-ValidationResult.ps1** — Validation result writer (ACV)
- [ ] **AuditComplianceHelpers.Tests.ps1** — Pester unit tests (optional, for validation)

**Python Components:**
- [ ] **create_audit_compliance_schema.py** — ALCA Dataverse schema creation script
- [ ] **create_dataverse_schema.py** — ACV Dataverse schema creation script
- [ ] **create_connection_references.py** — Connection reference setup script
- [ ] **create_environment_variables.py** — Environment variable setup script
- [ ] **deploy.py** — Deployment orchestrator
- [ ] **alca_client.py** — ALCA Dataverse Web API client library
- [ ] **acv_client.py** — ACV Dataverse Web API client library
- [ ] **requirements.txt** — Python dependencies

**Power Automate:**
- [ ] **audit-remediation-approval-flow.json** — Approval workflow template (ALCA)
- [ ] **tenant-validation-flow.json** — Tenant-level audit validation flow (ACV)
- [ ] **environment-validation-flow.json** — Environment-level audit validation flow (ACV)
- [ ] **adaptive-card-tenant-alert.json** — Tenant alert adaptive card template (ACV)
- [ ] **adaptive-card-environment-alert.json** — Environment alert adaptive card template (ACV)

**Supporting Documentation:**
- [ ] **docs/deployment-guide.md** — Azure Automation deployment guide
- [ ] **docs/scheduling-guide.md** — Runbook scheduling configuration
- [ ] **docs/testing-scenarios.md** — Test scenarios and troubleshooting
- [ ] **docs/evidence-export-guide.md** — Evidence export and integrity verification guide
- [ ] **docs/FLOW_SETUP.md** — Power Automate flow setup guide
- [ ] **docs/acv-CHANGELOG.md** — ACV subsystem changelog
- [ ] **docs/alca-CHANGELOG.md** — ALCA subsystem changelog

### 3. Packaging Instructions

**Option A: Create ZIP Archive**
```bash
# From the audit-compliance-manager directory:
zip -r ACM-Solution-v1.0.0.zip \
  SOLUTION-DOCUMENTATION.md \
  scripts/AuditComplianceHelpers.psm1 \
  scripts/AuditComplianceHelpers.psd1 \
  scripts/AuditComplianceHelpers.Tests.ps1 \
  scripts/Check-AuditLoggingCompliance.ps1 \
  scripts/Enable-AuditLogging.ps1 \
  scripts/Invoke-TenantAuditValidation.ps1 \
  scripts/Invoke-EnvironmentAuditValidation.ps1 \
  scripts/Invoke-EnvironmentDiscovery.ps1 \
  scripts/Start-TenantValidationRunbook.ps1 \
  scripts/Start-EnvironmentValidationRunbook.ps1 \
  scripts/Export-AuditValidationEvidence.ps1 \
  scripts/Test-UnifiedAuditLog.ps1 \
  scripts/Test-MailboxAudit.ps1 \
  scripts/Test-PurviewRetention.ps1 \
  scripts/Test-EnvironmentAudit.ps1 \
  scripts/Test-EnvironmentRetention.ps1 \
  scripts/Test-EvidenceIntegrity.ps1 \
  scripts/private/Compare-ValidationBaseline.ps1 \
  scripts/private/Connect-AuditServices.ps1 \
  scripts/private/Connect-PowerPlatform.ps1 \
  scripts/private/Get-ValidationResults.ps1 \
  scripts/private/New-CanaryEvent.ps1 \
  scripts/private/Write-ValidationResult.ps1 \
  scripts/create_audit_compliance_schema.py \
  scripts/create_dataverse_schema.py \
  scripts/create_connection_references.py \
  scripts/create_environment_variables.py \
  scripts/deploy.py \
  scripts/alca_client.py \
  scripts/acv_client.py \
  scripts/requirements.txt \
  templates/audit-remediation-approval-flow.json \
  templates/tenant-validation-flow.json \
  templates/environment-validation-flow.json \
  templates/adaptive-card-tenant-alert.json \
  templates/adaptive-card-environment-alert.json \
  docs/deployment-guide.md \
  docs/scheduling-guide.md \
  docs/testing-scenarios.md \
  docs/evidence-export-guide.md \
  docs/FLOW_SETUP.md \
  docs/acv-CHANGELOG.md \
  docs/alca-CHANGELOG.md
```

**Option B: Create Structured Folder**
```
ACM-Solution-v1.0.0/
├── SOLUTION-DOCUMENTATION.md
├── PowerShell-Components/
│   ├── AuditComplianceHelpers.psm1
│   ├── AuditComplianceHelpers.psd1
│   ├── Check-AuditLoggingCompliance.ps1
│   └── Enable-AuditLogging.ps1
├── Python-Components/
│   ├── create_audit_compliance_schema.py
│   ├── alca_client.py
│   └── requirements.txt
├── Power-Automate/
│   ├── audit-remediation-approval-flow.json
│   ├── tenant-validation-flow.json
│   └── environment-validation-flow.json
└── Deployment-Guides/
    ├── deployment-guide.md
    ├── scheduling-guide.md
    └── testing-scenarios.md
```

### 4. Email Template

**Subject:** Audit Compliance Manager (ACM) - Solution Delivery v1.0.0

**Body:**

```
Hi [Customer Name],

Please find attached the Audit Compliance Manager (ACM) solution package, version 1.0.0.

This solution provides enterprise-grade automated detection and remediation of audit logging
gaps across Microsoft 365 and Power Platform environments with Azure Automation and Managed
Identity authentication.

Package Contents:
- SOLUTION-DOCUMENTATION.md — Complete technical documentation with:
  • Executive Summary (problem statement, solution overview, business value)
  • Technical Details (architecture, components, data model)
  • Configuration and Prerequisites (Azure Automation setup, MI permissions)
  • Deployment validation steps
  • Operational guidance and troubleshooting
  • Regulatory alignment (FINRA 4511, SEC 17a-3/4, SOX 404, GLBA 501(b))

- 8 Solution Component Files:
  • 2 PowerShell runbooks (detection + remediation)
  • 1 shared helper module with 6 reusable functions
  • 2 Python scripts (Dataverse schema creation + client library)
  • 1 Power Automate approval workflow template
  • Unit tests for quality assurance

- 3 Deployment Guides:
  • Azure Automation setup (phases 1-5, ~90 minutes total)
  • Runbook scheduling configuration
  • 15 test scenarios with troubleshooting

Key Capabilities:
✓ Automated detection of Purview unified audit and Dataverse audit status
✓ Intelligent remediation with org-level + entity-level Dataverse auditing
✓ Entity-level audit enablement for 6 Copilot Studio entities
✓ Approval-gated remediation via Power Automate
✓ Enterprise-grade Managed Identity authentication (no hardcoded credentials)
✓ WhatIf simulation mode for safe testing
✓ HTML email notifications with CSV compliance reports

Architecture:
• Azure Automation with System-Assigned Managed Identity
• PowerShell 7.2 runtime
• Dataverse compliance tracking table (upsert pattern)
• Exponential backoff retry logic for API resilience

Business Value:
• Eliminate manual audit configuration overhead (95%+ time savings)
• Ensure continuous audit coverage across all Power Platform environments
• Support regulatory examinations with automated compliance evidence
• Detect and remediate audit gaps within 24 hours (weekly scan) or faster (daily scan)

Regulatory Support:
• FINRA 4511 — Supervision
• SEC 17a-3/17a-4 — Recordkeeping
• SOX 404 — Internal Controls over Financial Reporting
• GLBA 501(b) — Safeguards Rule

Next Steps:
1. Review the SOLUTION-DOCUMENTATION.md file (Section 2: Technical Details)
2. Create Azure Automation Account with System-Assigned Managed Identity
3. Assign Managed Identity permissions:
   - Power Platform Administrator (Entra ID role)
   - Exchange Administrator (Entra ID role)
   - Mail.Send (Microsoft Graph API permission)
   - Dataverse Application User (per environment, System Administrator role)
4. Import PowerShell modules (Microsoft.PowerApps.Administration.PowerShell, ExchangeOnlineManagement)
5. Create Dataverse schema using Python script
6. Create and publish runbooks in Azure Automation
7. Schedule weekly detection runbook
8. Schedule deployment planning session (recommended: 2-3 hours for review + setup)

CRITICAL CONFIGURATION REQUIREMENTS:

1. **Managed Identity Permissions:**
   - The solution REQUIRES System-Assigned Managed Identity with specific permissions
   - Without proper permissions, all environments will show Error status
   - See deployment-guide.md for detailed permission assignment steps

2. **Dataverse Application User:**
   - MI must be configured as Application User in EVERY environment you want to scan/remediate
   - Security role: System Administrator (required for audit config modification)
   - Without this, remediation will fail with 401 Unauthorized errors

3. **Shared Mailbox (Optional):**
   - Required only for email notifications
   - MI needs Send-As permission on shared mailbox
   - See deployment-guide.md Phase 3 for setup

Please let me know if you have any questions or need clarification on any aspect
of the solution.

Best regards,
[Your Name]
```

### 5. Pre-Delivery Validation

Before sending to customer, verify:

- [ ] All 43 files are included (23 PowerShell, 8 Python, 5 JSON templates, 7 docs)
- [ ] SOLUTION-DOCUMENTATION.md renders correctly in Markdown viewer
- [ ] File sizes are reasonable (no files > 500KB except documentation)
- [ ] No sensitive data in files (tenant IDs, email addresses should be placeholders like `contoso.onmicrosoft.com`)
- [ ] Version numbers are consistent (v1.0.0) across all files
- [ ] Placeholder values documented clearly (see Configuration Placeholders section in README)

### 6. Files NOT to Include

Do NOT include these repository management files:
- ❌ README.md (internal reference only)
- ❌ CHANGELOG.md (version history for our tracking)
- ❌ .git/ folder (version control)

### 7. Customer Requirements Reminder

Remind customer they will need:

**Licensing:**
- Microsoft 365 E3 or E5 (for Purview unified audit log)
- Power Platform Admin permissions
- Power Apps Premium (for Dataverse)
- Azure subscription (for Azure Automation)

**Permissions:**
- Entra Global Admin (for role assignments during setup)
- Power Platform Admin (for environment enumeration and audit config)
- Exchange Administrator (for MI auth and Search-UnifiedAuditLog)
- Dataverse System Administrator (per-environment for audit config modification)

**Azure Resources:**
- Azure Automation Account ($0-50/month depending on runbook execution frequency)
- System-Assigned Managed Identity (no additional cost)

**Skills/Expertise:**
- PowerShell scripting (for runbook customization)
- Python 3.10+ (for Dataverse schema creation)
- Azure Automation experience (for runbook deployment and scheduling)
- Power Platform Admin Center familiarity

### 8. Follow-Up Support

Offer these follow-up services:
- Azure Automation deployment assistance (4-6 hours recommended)
- Managed Identity permission configuration workshop (2 hours)
- Runbook customization for organization-specific requirements
- Approval workflow integration with existing governance processes
- Quarterly review of compliance trends and remediation success rates

### 9. Important Customer Guidance

**Critical Configuration Steps:**

1. **Managed Identity Setup is CRITICAL:**
   - The solution uses System-Assigned MI for ALL authentication
   - NEVER uses interactive auth or hardcoded credentials (security best practice)
   - Without proper MI permissions, solution will not function
   - Detailed permission assignment steps in deployment-guide.md

2. **Dataverse Application User Configuration:**
   - MI must be added to EVERY environment as Application User
   - This is a per-environment configuration (cannot be tenant-wide)
   - Security role: System Administrator (required for audit config writes)
   - Missing app user = 401 Unauthorized errors during remediation

3. **Detection vs. Remediation:**
   - **Detection:** Safe, read-only operation, run weekly or daily
   - **Remediation:** Modifies audit configuration, use approval workflow or manual trigger
   - Always test remediation in WhatIf mode first
   - Tenant-wide Purview audit enablement affects ALL M365 services

4. **Entity-Level Audit:**
   - Solution enables audit on 6 Copilot Studio entities automatically
   - Entities: bot, botcomponent, connectionreference, environmentvariablevalue, workflow, systemuser
   - If customer uses other entities, they may need to add them to the script
   - Entity audit increases Dataverse storage usage (typically <1% increase)

5. **Email Notifications:**
   - Optional feature, requires shared mailbox + Mail.Send permission
   - HTML email with CSV attachment shows compliance summary
   - CSV includes per-environment details (environment ID, audit status, compliance status)
   - Can disable email and rely on Dataverse table queries instead

### 10. Deployment Validation Checklist for Customer

Provide this checklist to customer for post-deployment validation:

```
Azure Automation Setup:
□ Automation Account created with System-Assigned Managed Identity enabled
□ Managed Identity Object ID recorded for permission assignments

Managed Identity Permissions:
□ Power Platform Administrator role assigned (Entra ID)
□ Exchange Administrator role assigned (Entra ID)
□ Mail.Send permission assigned (Microsoft Graph API)
□ Admin consent granted for Graph API permissions

Dataverse Application User:
□ MI configured as Application User in governance environment (minimum)
□ MI configured as Application User in all target environments (recommended)
□ Security role: System Administrator assigned to MI app user

PowerShell Modules:
□ Microsoft.PowerApps.Administration.PowerShell (2.0+) imported
□ ExchangeOnlineManagement (3.0+) imported
□ AuditComplianceHelpers (1.0.0) custom module uploaded

Dataverse Schema:
□ Python script executed successfully
□ Table fsi_auditenvironmentcompliance created
□ Choice field fsi_alca_compliancestatus created (4 values)
□ Alternate key fsi_environmentid_key created

Runbooks:
□ ALCA-Check-AuditLoggingCompliance runbook created and published
□ ALCA-Enable-AuditLogging runbook created and published
□ Helper module referenced correctly in both runbooks

Test Execution:
□ Detection runbook test executed successfully (no errors)
□ Compliance records created in Dataverse table
□ Remediation runbook test executed in WhatIf mode
□ WhatIf output shows "[WHATIF] Would enable..." messages

Scheduling:
□ Weekly schedule created for detection runbook
□ Schedule parameters configured correctly (DataverseEnvironmentUrl, TenantDomain)
□ Email notification parameters configured (if using email feature)

Validation:
□ Manual environment scan completed, compliance records verified
□ Non-compliant environment identified
□ Remediation runbook executed on test environment (actual remediation)
□ Post-remediation validation shows Compliant status
□ Power Platform Admin Center manually verified audit enabled

Operational Readiness:
□ Governance team trained on reviewing compliance reports
□ Remediation workflow documented (manual or approval-gated)
□ Monthly review scheduled for compliance trends
□ Evidence export process documented for audit examinations
```

---

**Package Version:** v1.0.0
**Release Date:** February 2026
**Solution:** Audit Compliance Manager (ACM) — includes ACV and ALCA subsystems
