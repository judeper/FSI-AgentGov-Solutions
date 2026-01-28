# Pipeline Governance Compliance Audit Checklist

Use this checklist to document governance evidence for auditors reviewing pipeline consolidation activities.

---

## Pre-Enforcement Evidence

Evidence collected before executing force-link operations.

| Item | Evidence Location | Verified |
|------|------------------|----------|
| Environment inventory completed | `reports/environment-inventory.csv` | [ ] |
| Designated pipelines host documented | README.md or governance wiki | [ ] |
| Non-compliant environments identified | Filtered inventory CSV | [ ] |
| Owner notifications sent | Email delivery logs | [ ] |
| Notification date recorded | Tracking table/spreadsheet | [ ] |
| Notification period elapsed (30-60 days) | Calendar records | [ ] |
| Exemption requests processed | ServiceNow/ticket system | [ ] |
| Exemptions documented with business justification | Approval records | [ ] |

---

## Enforcement Evidence

Evidence collected during force-link execution.

| Item | Evidence Location | Verified |
|------|------------------|----------|
| Force-link executed | Admin portal screenshots | [ ] |
| Force-link date recorded | Tracking table/spreadsheet | [ ] |
| Performing admin documented | Tracking table/spreadsheet | [ ] |
| Post-migration verification completed | Test deployment logs | [ ] |
| Maker communication sent | Email records | [ ] |
| Old pipelines marked as orphaned | Tracking documentation | [ ] |

---

## Post-Enforcement Evidence

Evidence collected after migration is complete.

| Item | Evidence Location | Verified |
|------|------------------|----------|
| All target environments linked to central host | Environments list in host | [ ] |
| Test deployments successful | Deployment history | [ ] |
| Maker access granted to central host | Security role assignments | [ ] |
| Monitoring configured for new violations | Power Automate flow | [ ] |
| Documentation updated | Solution README | [ ] |

---

## Regulatory Mapping

How this solution supports regulatory compliance.

| Regulation | Requirement | Evidence |
|------------|------------|----------|
| **OCC 2011-12** | Change management controls | Notification timeline, approval records, documented procedures |
| **FFIEC IT Handbook** | Configuration management | Centralized host documentation, inventory records |
| **SOX 404** | IT general controls | Force-link execution records, segregation of duties |
| **FINRA 4511** | Books and records | Complete inventory, change logs, communication records |

---

## Retention Requirements

| Record Type | Recommended Retention | Notes |
|-------------|----------------------|-------|
| Environment inventory CSV | 7 years | Baseline for audit comparison |
| Owner notification emails | 7 years | Proof of communication |
| Force-link screenshots | 7 years | Evidence of enforcement action |
| Exemption approvals | 7 years | Business justification records |
| Test deployment logs | 3 years | Verification evidence |
| Tracking spreadsheet | 7 years | Complete audit trail |

> **Note:** Verify retention periods against your organization's records retention policy. Financial services organizations may require longer retention for certain record types.

---

## Evidence Collection Tips

### Screenshots

When capturing force-link operations:

1. Include browser URL showing environment context
2. Capture before and after states
3. Include timestamp (system clock visible or noted)
4. Save with descriptive filename: `forcelink-{envname}-{date}.png`

### Email Logs

For notification records:

1. Export from mail server or use delivery reports
2. Include recipient, timestamp, and delivery status
3. Retain original email content (not just subject)

### CSV Exports

For inventory records:

1. Include export date in filename
2. Do not modify original exports
3. Keep separate files for each milestone (initial, post-notification, post-enforcement)

---

## Audit Interview Preparation

Common auditor questions and where to find answers:

| Question | Evidence Source |
|----------|-----------------|
| How were non-compliant environments identified? | Inventory script, `-ProbePipelines` output |
| Were owners notified before enforcement? | Email delivery logs, notification dates |
| What was the notification period? | Tracking spreadsheet dates |
| How were exemptions handled? | Ticket system, approval records |
| Who performed the force-link operations? | Tracking spreadsheet, admin name column |
| How was success verified? | Test deployment logs |
| Is ongoing monitoring in place? | Power Automate flow configuration |

---

## Checklist Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Platform Operations Lead | | | |
| Compliance Officer | | | |
| IT Audit | | | |

---

## See Also

- [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) - Force-link procedures
- [README.md](./README.md) - Solution overview
- [LIMITATIONS.md](./LIMITATIONS.md) - Technical constraints
