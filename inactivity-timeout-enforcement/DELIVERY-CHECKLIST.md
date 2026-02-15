# ITE Solution - Customer Delivery Checklist

## Files to Include in Customer Package

### 1. Documentation
- [ ] **SOLUTION-DOCUMENTATION.md** — Main technical documentation (Executive Summary + Technical Details)

### 2. Solution Components (JSON Files)

File located in the `src/` directory:

- [ ] **detect-inactivity-timeout-noncompliance.json** — Daily compliance detection flow for inactivity timeout settings

### 3. Packaging Instructions

**Option A: Create ZIP Archive**
```bash
# From the inactivity-timeout-enforcement directory:
zip -r ITE-Solution-v1.0.0.zip \
  SOLUTION-DOCUMENTATION.md \
  src/detect-inactivity-timeout-noncompliance.json
```

**Option B: Create Structured Folder**
```
ITE-Solution-v1.0.0/
├── SOLUTION-DOCUMENTATION.md
└── solution-components/
    └── detect-inactivity-timeout-noncompliance.json
```

### 4. Email Template

**Subject:** Inactivity Timeout Enforcement (ITE) - Solution Delivery v1.0.0

**Body:**

```
Hi [Customer Name],

Please find attached the Inactivity Timeout Enforcement (ITE) solution package, version 1.0.0.

This solution provides continuous automated monitoring of Power Platform environment inactivity
timeout configurations with zone-based policy enforcement.

Package Contents:
- SOLUTION-DOCUMENTATION.md — Complete technical documentation with:
  • Executive Summary (problem statement, solution overview, business value)
  • Technical Details (architecture, compliance logic, data model)
  • Configuration and Prerequisites
  • Deployment validation steps
  • Operational guidance and troubleshooting
  • Compliance status reference and regulatory alignment

- 1 Solution Component File (JSON):
  • Daily compliance detection flow (zone-based timeout policy enforcement)

Key Capabilities:
✓ Daily automated scans across all Power Platform environments
✓ Zone-based policy enforcement (Personal: optional ≤120min, Team: ≤120min, Enterprise: ≤60min)
✓ Three-state compliance classification (Compliant, Non-Compliant, Unknown)
✓ Guarded email alerting (notifications sent only when issues detected)
✓ Immutable compliance audit trail in Dataverse
✓ ISO 8601 duration parsing for timeout values

Business Value:
• Reduce session-based security incidents through proactive timeout detection
• Ensure no environment exceeds 120-minute inactivity timeout (regulatory requirement)
• Support regulatory examinations with complete compliance history
• Enable zone-based risk management with tailored timeout policies

Regulatory Support:
• GLBA 501(b) — Safeguards Rule
• SOX 302 — Internal Controls over Financial Reporting
• FINRA 4511 — Supervision
• NIST 800-53 AC-11 (Session Lock) and AC-12 (Session Termination)

Next Steps:
1. Review the SOLUTION-DOCUMENTATION.md file (Section 2: Technical Details)
2. Create Dataverse tables:
   - fsi_environmentpolicies (policy registry)
   - fsi_inactivitytimeoutcompliances (compliance records)
   - fsi_inactivitytimeouterrorlogs (error logs)
3. Populate environment policies with zone-based timeout requirements
4. Configure Managed Service Identity for BAP Admin API access
5. Schedule deployment planning session (recommended: 1-2 hours)
6. We can assist with policy configuration and validation testing

Please let me know if you have any questions or need clarification on any aspect
of the solution.

Best regards,
[Your Name]
```

### 5. Pre-Delivery Validation

Before sending to customer, verify:

- [ ] JSON file is included and not corrupted
- [ ] SOLUTION-DOCUMENTATION.md renders correctly in Markdown viewer
- [ ] File size is reasonable (JSON file should be < 100KB)
- [ ] No sensitive data in JSON file (tenant IDs, email addresses should be placeholders)
- [ ] Version numbers are consistent (v1.0.0) across all files

### 6. Files NOT to Include

Do NOT include these repository management files:
- ❌ README.md (internal reference only)
- ❌ CHANGELOG.md (version history for our tracking)
- ❌ .git/ folder (version control)

### 7. Customer Requirements Reminder

Remind customer they will need:

**Licensing:**
- Power Automate Premium (for cloud flow with HTTP actions and Dataverse)
- Power Platform Admin permissions (for BAP Admin API access)
- Exchange Online mailbox (for email notifications)

**Permissions:**
- Power Platform Admin (or Global Admin)
- Dataverse System Administrator
- Managed Service Identity with Power Platform Administrator role

**Environment:**
- Power Platform environment with Dataverse enabled
- Managed Service Identity configured for BAP Admin API access

**Data Setup:**
- Environment policy registry (`fsi_environmentpolicies` table) populated with zone-based timeout requirements
- Recommended zone policy: Zone 1 (Personal) = optional (≤120min), Zone 2 (Team) = ≤120min, Zone 3 (Enterprise) = ≤60min

### 8. Follow-Up Support

Offer these follow-up services:
- Deployment assistance (2-4 hours recommended)
- Policy configuration workshop (1 hour)
- Zone classification guidance for existing environments
- Quarterly compliance trend review
- Remediation workflow training for IT teams

### 9. Important Customer Guidance

**Critical Configuration Steps:**

1. **Environment Policy Population:**
   - The solution requires `fsi_environmentpolicies` table to be populated BEFORE first run
   - Missing policies result in **Unknown** compliance status
   - Provide customer with environment enumeration script to expedite policy creation

2. **Managed Service Identity Setup:**
   - MSI must have **Power Platform Administrator** role
   - BAP Admin API access is critical for privacy settings retrieval
   - Without proper MSI permissions, all environments will show **Unknown** status with Unauthorized errors

3. **Timeout Policy Recommendation:**
   - **Zone 1 (Personal):** Optional; ≤120 minutes if enabled — Individual development environments
   - **Zone 2 (Team):** ≤120 minutes (required) — Team collaboration environments
   - **Zone 3 (Enterprise):** ≤60 minutes (required) — Production environments processing sensitive financial data
   - **CRITICAL:** Zone 3 environments must have the shortest timeouts per NIST 800-53 AC-11 and FINRA 4511 requirements

4. **Guarded Notification:**
   - Email alerts are only sent when Non-Compliant or Unknown environments are detected
   - If all environments are Compliant, no email is sent (expected behavior)
   - Customer should expect initial email if environment policies are not yet configured

### 10. Deployment Validation Checklist for Customer

Provide this checklist to customer for post-deployment validation:

```
□ Dataverse tables created successfully:
  □ fsi_environmentpolicies
  □ fsi_inactivitytimeoutcompliances
  □ fsi_inactivitytimeouterrorlogs

□ Environment policies populated for all production environments

□ Managed Service Identity configured with Power Platform Administrator role

□ Flow imported successfully and connection references configured

□ Environment variables set:
  □ fsi_ITE_NotificationRecipients
  □ fsi_ITE_ConcurrencyLimit
  □ fsi_ITE_ScanFrequencyHours

□ Flow activated with daily 06:00 UTC schedule

□ Test execution completed successfully:
  □ Compliance records created in Dataverse
  □ Email notification sent (if issues detected)
  □ No API errors in error log table

□ Remediation process documented for IT team

□ Monthly compliance review scheduled
```

---

**Package Version:** v1.0.0
**Release Date:** February 2026
**Solution:** Inactivity Timeout Enforcement (ITE)
