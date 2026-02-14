# UASD Solution - Customer Delivery Checklist

## Files to Include in Customer Package

### 1. Documentation
- [ ] **SOLUTION-DOCUMENTATION.md** — Main technical documentation (Executive Summary + Technical Details)

### 2. Solution Components (JSON Files)

All files located in the `src/` directory:

- [ ] **uasd-detector-scan-agents.json** — Daily scan flow for agent sharing violations
- [ ] **uasd-remediation-apply-sharing-policy.json** — Automated remediation flow
- [ ] **uasd-exception-approval-workflow.json** — Exception approval workflow with dual approvals
- [ ] **uasd-exception-manager-app.json** — Canvas app for exception submission and tracking
- [ ] **adaptive-card-uasd-alert.json** — Teams alert card template

### 3. Packaging Instructions

**Option A: Create ZIP Archive**
```bash
# From the unrestricted-agent-sharing-detector directory:
zip -r UASD-Solution-v1.0.0.zip \
  SOLUTION-DOCUMENTATION.md \
  src/uasd-detector-scan-agents.json \
  src/uasd-remediation-apply-sharing-policy.json \
  src/uasd-exception-approval-workflow.json \
  src/uasd-exception-manager-app.json \
  src/adaptive-card-uasd-alert.json
```

**Option B: Create Structured Folder**
```
UASD-Solution-v1.0.0/
├── SOLUTION-DOCUMENTATION.md
└── solution-components/
    ├── uasd-detector-scan-agents.json
    ├── uasd-remediation-apply-sharing-policy.json
    ├── uasd-exception-approval-workflow.json
    ├── uasd-exception-manager-app.json
    └── adaptive-card-uasd-alert.json
```

### 4. Email Template

**Subject:** Unrestricted Agent Sharing Detector (UASD) - Solution Delivery v1.0.0

**Body:**

```
Hi [Customer Name],

Please find attached the Unrestricted Agent Sharing Detector (UASD) solution package, version 1.0.0.

This solution provides continuous automated monitoring and remediation of Copilot Studio agent
sharing configurations across your Power Platform environments.

Package Contents:
- SOLUTION-DOCUMENTATION.md — Complete technical documentation with:
  • Executive Summary (problem statement, solution overview, business value)
  • Technical Details (architecture, components, data model)
  • Configuration and Prerequisites
  • Deployment validation steps
  • Operational guidance and troubleshooting
  • Violation type reference guide

- 5 Solution Component Files (JSON):
  • Detector scan flow (daily automated scans)
  • Remediation flow (automated policy enforcement)
  • Exception approval workflow (time-bound exception management)
  • Exception Manager app (self-service exception submission)
  • Teams alert card template (severity-based notifications)

Key Capabilities:
✓ Detects 5 violation types: Org-wide sharing, public links, unapproved groups,
  excessive individual shares, cross-tenant access
✓ Automated remediation with break-glass exclusions
✓ Time-bound exception workflow with dual approvals
✓ Real-time Teams alerting with severity classification
✓ Complete audit trail in Dataverse

Next Steps:
1. Review the SOLUTION-DOCUMENTATION.md file (Section 2: Technical Details)
2. Validate prerequisites against your environment
3. Schedule deployment planning session (recommended: 1-2 hours)
4. We can assist with initial configuration and validation testing

Please let me know if you have any questions or need clarification on any aspect
of the solution.

Best regards,
[Your Name]
```

### 5. Pre-Delivery Validation

Before sending to customer, verify:

- [ ] All 5 JSON files are included and not corrupted
- [ ] SOLUTION-DOCUMENTATION.md renders correctly in Markdown viewer
- [ ] File sizes are reasonable (JSON files should be < 500KB each)
- [ ] No sensitive data in JSON files (tenant IDs, email addresses should be placeholders)
- [ ] Version numbers are consistent (v1.0.0) across all files

### 6. Files NOT to Include

Do NOT include these repository management files:
- ❌ README.md (internal reference only)
- ❌ CHANGELOG.md (version history for our tracking)
- ❌ .git/ folder (version control)
- ❌ Any test scripts or lab automation scripts

### 7. Customer Requirements Reminder

Remind customer they will need:

**Licensing:**
- Microsoft 365 E5 or E5 Compliance
- Power Automate Premium
- Power Apps per-user or per-app

**Permissions:**
- Power Platform Admin (or Global Admin)
- Dataverse System Administrator
- Application Developer (if using service principal)

**Environment:**
- Power Platform environment with Dataverse enabled
- Microsoft Teams for alerting
- Entra ID P2 (included in M365 E5)

### 8. Follow-Up Support

Offer these follow-up services:
- Deployment assistance (4-6 hours recommended)
- Configuration validation session
- Exception approval workflow training
- Quarterly review of violation patterns and policy tuning

---

**Package Version:** v1.0.0
**Release Date:** February 2026
**Solution:** Unrestricted Agent Sharing Detector (UASD)
