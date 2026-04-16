# ITE Solution — Delivery Checklist

> **Version:** v1.0.5 | **Solution:** Inactivity Timeout Enforcement (ITE)

## Pre-Deployment Verification

### 1. Documentation Review

- [ ] Review [flow-configuration.md](flow-configuration.md) — step-by-step flow build guide
- [ ] Review [dataverse-schema.md](dataverse-schema.md) — auto-generated schema reference
- [ ] Review the solution README for prerequisites and architecture

### 2. Dataverse Schema Deployment

- [ ] Run `scripts/create_ite_dataverse_schema.py` to create tables and option sets
- [ ] Verify three tables exist:
  - [ ] `fsi_environmentpolicies` — zone policy configuration
  - [ ] `fsi_inactivitytimeoutcompliances` — compliance scan results
  - [ ] `fsi_inactivitytimeouterrorlogs` — error audit trail
- [ ] Regenerate schema docs: `python scripts/create_ite_dataverse_schema.py --output-docs`

### 3. Environment Variables

- [ ] Run `scripts/create_ite_environment_variables.py` or set variables manually
- [ ] Verify `fsi_ITE_NotificationRecipients` is configured with valid email addresses

### 4. Connection References

- [ ] Run `scripts/create_ite_connection_references.py` or create manually
- [ ] Verify Dataverse connection reference is configured
- [ ] Verify Office 365 Outlook connection reference is configured

### 5. Cloud Flow Build

- [ ] Build the detection flow manually following [flow-configuration.md](flow-configuration.md)
- [ ] Configure the daily 06:00 UTC recurrence trigger
- [ ] Map connection references to active connections
- [ ] Activate the cloud flow

### 6. Data Setup

- [ ] Populate `fsi_environmentpolicies` table with zone-based timeout requirements
- [ ] Recommended zone policy:
  - Zone 1 (Personal): optional, ≤120 min if enabled
  - Zone 2 (Team): required, ≤120 min
  - Zone 3 (Enterprise): required, ≤60 min

### 7. Permissions

- [ ] Managed Service Identity configured with Power Platform Admin role
- [ ] MSI service principal added in Microsoft 365 Admin Center → Roles → Power Platform Admin → Members
- [ ] Dataverse System Administrator role assigned

### 8. PowerShell Governance Scripts

- [ ] `Invoke-TimeoutComplianceScan.ps1` tested with valid credentials
- [ ] `Test-TimeoutCompliance.ps1` produces expected summary output
- [ ] `Export-TimeoutComplianceEvidence.ps1` generates evidence JSON and SHA-256 hash
- [ ] `Test-EvidenceIntegrity.ps1` verifies exported evidence files

### 9. Post-Deployment Validation

- [ ] Manual flow test execution completed successfully
- [ ] Compliance records created in Dataverse
- [ ] Email notification sent (if issues detected)
- [ ] No API errors in error log table
- [ ] Remediation process documented for IT team

### 10. Ongoing Operations

- [ ] Monthly compliance review scheduled
- [ ] IT team aware of `Set-InactivityTimeout.ps1` script in FSI-AgentGov (`scripts/governance/`) for automated remediation
- [ ] Zone classification guidance documented for new environments

---

**Package Version:** v1.0.5
**Solution:** Inactivity Timeout Enforcement (ITE)
