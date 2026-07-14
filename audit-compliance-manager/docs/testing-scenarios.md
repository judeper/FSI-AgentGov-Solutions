# Testing Scenarios — Audit Logging Compliance Automation (ALCA)

15 test scenarios for validating the ALCA solution, plus a troubleshooting guide for 10 common issues.

---

## Detection Scenarios

### Scenario 1: All Environments Compliant

**Setup:** All Power Platform environments have Purview unified audit enabled. All Dataverse environments have org-level audit enabled.

**Expected results:**
- All environments show `Compliant` status
- Summary: N/N compliant, 0 non-compliant, 0 errors
- Dataverse records all have `fsi_compliancestatus = 100000000` (Compliant)

**Verification:**
1. Run `Test-AuditLoggingCompliance.ps1` with required parameters
2. Verify console output shows all environments as Compliant
3. Check Dataverse table for matching records

### Scenario 2: Mixed Compliance (Compliant + Non-Compliant)

**Setup:** Tenant-level Microsoft Purview audit is enabled, but at least one Dataverse environment has org-level audit disabled. To test tenant-level Purview audit disabled, use a non-production tenant because that setting affects all environments.

**Expected results:**
- Mix of `Compliant` and `Non-Compliant` statuses
- Summary reflects accurate counts
- Non-compliant records have `fsi_compliancestatus = 100000001`

**Verification:**
1. Run detection runbook
2. Verify per-environment status matches actual configuration
3. Confirm Dataverse records have correct status values

### Scenario 3: Purview Unified Audit Disabled

**Setup:** Disable Microsoft Purview unified audit log ingestion in a non-production tenant via `Set-AdminAuditLogConfig`. This is a tenant-wide setting, not an environment-specific setting.

**Expected results:**
- Affected environment shows `Non-Compliant`
- `fsi_auditenabled = false` in Dataverse record
- Other environments in the same tenant also lose Microsoft 365 unified audit ingestion until the tenant setting is restored

**Verification:**
1. Disable audit: `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $false`
2. Run detection runbook
3. Verify environment shows Non-Compliant with `PurviewAuditEnabled = False`

### Scenario 4: Audit Event Validation

**Setup:** Environment with audit enabled but no recent audit events in last 7 days.

**Expected results:**
- Environment still shows `Compliant` if audit configuration is correct (event presence is informational, not a compliance gate)
- `LastAuditEvent` field shows "None in last 7 days"

**Verification:**
1. Run detection on an environment with audit enabled
2. Verify `LastAuditEvent` column in CSV output
3. Confirm compliance status based on configuration, not event presence

---

## Remediation Scenarios

### Scenario 5: WhatIf Mode

**Setup:** Non-compliant environments exist. Run with `-WhatIf` switch.

**Expected results:**
- Console shows `[WHATIF] Would enable...` for each action
- No actual changes made to any environment
- No Dataverse compliance records updated
- Summary shows all actions as simulated

**Verification:**
1. Run `Enable-AuditLogging.ps1 -WhatIf`
2. Verify `[WHATIF]` prefix on all action lines
3. Confirm environment audit settings unchanged after run
4. Verify Dataverse records unchanged

### Scenario 6: Dataverse Org-Level Audit Enablement

**Setup:** A Dataverse environment with `isauditenabled = false`.

**Expected results:**
- Runbook enables org-level audit via PATCH to `/api/data/v9.2/organizations`
- Entity-level audit enabled on 6 entities
- Validation confirms changes after 5-second wait
- Dataverse record updated to `Compliant`

**Verification:**
1. Confirm `isauditenabled = false` before remediation
2. Run remediation runbook (without WhatIf)
3. Verify `isauditenabled = true` via Dataverse Web API
4. Check entity audit settings for bot, botcomponent, connectionreference, environmentvariablevalue, workflow, systemuser

### Scenario 7: Tenant-Wide Purview Unified Audit Enablement

**Setup:** Purview unified audit disabled at tenant level. Run with `-EnableTenantUnifiedAudit`.

**Expected results:**
- Console shows tenant-wide change warning
- `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true` is called
- All environments benefit from tenant-level change

**Verification:**
1. Verify current state: `(Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled`
2. Run remediation with `-EnableTenantUnifiedAudit`
3. Verify post-state: `(Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled -eq $true`

### Scenario 8: Validation Failure After Remediation

**Setup:** Environment where audit enablement is applied but validation re-read still shows disabled (e.g., propagation delay exceeds 5 seconds).

**Expected results:**
- Remediation actions are attempted
- Validation re-read fails
- Status set to `Remediation Pending` (not Compliant)
- Environment flagged for follow-up in summary

**Verification:**
1. This scenario is typically transient — run detection again after 60 seconds
2. If persistent, check Dataverse for `fsi_compliancestatus = 100000002`

---

## Infrastructure Scenarios

### Scenario 9: Retry and Throttling (429)

**Setup:** High-volume tenant with many environments that may trigger API throttling.

**Expected results:**
- `Invoke-WithRetry` handles 429 responses with exponential backoff
- Verbose output shows retry attempts and delays
- Scanning completes successfully (may take longer)

**Verification:**
1. Run detection with `-Verbose` to see retry logs
2. Verify all environments are processed despite throttling
3. Check that no environments are skipped

### Scenario 10: Multi-Recipient Email Notification

**Setup:** Configure `-NotificationToAddresses` with multiple comma-separated recipients.

**Expected results:**
- HTML email sent to all recipients
- CSV attachment included
- Email subject includes compliance counts
- `saveToSentItems = false` (shared mailbox)

**Verification:**
1. Run detection with `-SendEmail -NotificationToAddresses "user1@example.com,user2@example.com"`
2. Verify all recipients received the email
3. Verify CSV attachment is present and contains all environment data

### Scenario 11: Dataverse Upsert — Create New Record

**Setup:** First-time scan of an environment not yet in the compliance table.

**Expected results:**
- `Write-DataverseComplianceRecord` queries for existing record (GET returns empty)
- Creates new record via POST
- Record has correct environment ID, name, audit status, and compliance status

**Verification:**
1. Verify the environment has no existing record in the Audit Environment Compliance table (`fsi_auditenvironmentcompliance`; OData entity set `fsi_auditenvironmentcompliances`)
2. Run detection
3. Verify new record created with correct field values

### Scenario 12: Dataverse Upsert — Update Existing Record

**Setup:** Re-scan an environment that already has a compliance record.

**Expected results:**
- `Write-DataverseComplianceRecord` finds existing record (GET returns match)
- Updates record via PATCH (not POST)
- `fsi_lastchecked` timestamp updated
- Status reflects current compliance state

**Verification:**
1. Note the existing record's `fsi_lastchecked` value
2. Run detection
3. Verify `fsi_lastchecked` updated, record ID unchanged

---

## Error Handling Scenarios

### Scenario 13: Per-Environment Error (Continue Scanning)

**Setup:** An environment that causes an error (e.g., Dataverse API returns 403 for one environment).

**Expected results:**
- Error caught per-environment, does not stop scanning
- Error environment gets `ComplianceStatus = Error` with error message
- Remaining environments processed normally
- Summary includes error count

**Verification:**
1. Verify environment with restricted access exists
2. Run detection
3. Confirm error environment shows `Error` status with descriptive message
4. Confirm all other environments still processed

### Scenario 14: Fatal Authentication Failure

**Setup:** Revoke Managed Identity permissions (for example, remove the Power Platform Admin role).

**Expected results:**
- Authentication fails immediately at Step 1
- Runbook exits with error (does not proceed to scanning)
- Error message indicates authentication failure
- No Dataverse records written

**Verification:**
1. Temporarily remove MI role assignment
2. Run detection
3. Verify `[FATAL]` message in output
4. Restore MI role assignment after test

### Scenario 15: Scheduled Execution

**Setup:** Link the detection runbook to a schedule (see [Scheduling Guide](./scheduling-guide.md)).

**Expected results:**
- Runbook executes automatically at scheduled time
- Job status shows `Completed`
- Dataverse records updated
- Email sent (if configured)

**Verification:**
1. Configure schedule per scheduling guide
2. Wait for scheduled execution
3. Check **Automation Account** → **Jobs** for completed job
4. Verify Dataverse compliance records updated
5. Verify email received (if SendEmail configured)

---

## Troubleshooting Guide

### Issue 1: Power Platform Authentication Failure

**Symptoms:**
- `[FATAL] Power Platform authentication failed`
- Error: `Add-PowerAppsAccount : The token could not be acquired`

**Possible causes:**
- Managed Identity not assigned the **Power Platform Admin** role
- MI not enabled on the Automation Account
- Incorrect tenant domain

**Resolution:**
1. Verify MI is enabled: **Automation Account** → **Identity** → Status = On
2. Verify role: **Microsoft Entra ID** → **Roles and administrators** → **Power Platform Administrator** (Power Platform Admin display name) → Check MI is listed
3. Test token acquisition in Test Pane: `Get-ManagedIdentityToken -Resource "https://api.bap.microsoft.com/"`

### Issue 2: Exchange Online Authentication Failure

**Symptoms:**
- `[FATAL] Exchange Online authentication failed`
- Error: `Connect-ExchangeOnline : Failed to acquire token`

**Possible causes:**
- Managed Identity not assigned **Exchange Online Admin** role
- ExchangeOnlineManagement module not imported or wrong version
- Incorrect `-Organization` parameter

**Resolution:**
1. Verify role: **Entra ID** → **Roles and administrators** → **Exchange Online Admin** → Check MI is listed
2. Verify module: **Automation Account** → **Modules** → `ExchangeOnlineManagement` Status = Available on Runtime 7.4
3. Verify TenantDomain parameter matches `yourdomain.onmicrosoft.com` format

### Issue 3: Dataverse 401 Access Denied

**Symptoms:**
- Dataverse API calls fail with 401 Unauthorized
- Error in `Invoke-DataverseRequest`: `The user is not a member of the organization`

**Possible causes:**
- MI not added as Application User in the target Dataverse environment
- Application User does not have System Administrator role
- Token scoped to wrong Dataverse URL

**Resolution:**
1. Navigate to **Power Platform Admin Center** → target environment → **Settings** → **Application users**
2. Verify MI is listed as an Application User
3. Verify the assigned security role is **System Administrator**
4. Ensure `DataverseEnvironmentUrl` parameter matches the governance environment URL

### Issue 4: Email Not Sent

**Symptoms:**
- `[ERROR] Failed to send email`
- Error: `MailboxNotEnabledForRESTAPI` or `AccessDenied`

**Possible causes:**
- MI does not have **Mail.Send** Graph application permission
- Admin consent not granted for Mail.Send
- Shared mailbox does not have SendAs permission for MI
- Incorrect `NotificationFromAddress`

**Resolution:**
1. Verify Graph permission: Use `Get-MgServicePrincipalAppRoleAssignment` to check Mail.Send
2. Grant admin consent: **Enterprise Applications** → MI → **Permissions** → **Grant admin consent**
3. Verify SendAs: `Get-RecipientPermission -Identity "shared-mailbox@domain.com" | Where Trustee -match "MI-name"`
4. Ensure `NotificationFromAddress` matches the shared mailbox address exactly

### Issue 5: Dataverse Table Not Updated

**Symptoms:**
- Detection runs without errors but no records appear in the Audit Environment Compliance table (`fsi_auditenvironmentcompliance`; OData entity set `fsi_auditenvironmentcompliances`)
- Or records appear but fields are not updated

**Possible causes:**
- Table does not exist (schema not deployed)
- Alternate key not configured on `fsi_environmentid`
- Dataverse token scoped to wrong environment

**Resolution:**
1. Verify table exists: Navigate to **Dataverse** → **Tables** → Search for `Audit Environment Compliance`
2. Run the schema creation script: `python create_audit_compliance_schema.py`
3. Verify `DataverseEnvironmentUrl` points to the governance environment (not a target environment)

### Issue 6: 429 Throttling (Too Many Requests)

**Symptoms:**
- Verbose logs show multiple retry attempts
- Runbook takes significantly longer than expected
- Error: `429 Too Many Requests` in verbose output

**Possible causes:**
- Large number of environments (50+) causing API rate limits
- Concurrent automation scripts hitting same APIs
- Power Platform API throttling limits reached

**Resolution:**
1. This is handled automatically by `Invoke-WithRetry` with exponential backoff
2. If persistent, increase `MaxRetries` parameter in function calls
3. Consider staggering scheduled runs to avoid peak API usage times
4. For 100+ environments, consider batching (future enhancement)

### Issue 7: Validation Failure After Remediation

**Symptoms:**
- Remediation runs but validation step shows audit still disabled
- Status set to `Remediation Pending` instead of `Compliant`

**Possible causes:**
- Propagation delay exceeds the 5-second wait
- Cached API response returning stale data
- Insufficient permissions to modify entity definitions

**Resolution:**
1. Wait 60 seconds and re-run detection to check actual state
2. If still failing, increase the propagation wait (modify `Start-Sleep` in runbook)
3. Verify MI has System Administrator role in the target environment
4. Check entity-level audit settings manually via Dataverse Web API

### Issue 8: Search-UnifiedAuditLog Cmdlet Not Found

**Symptoms:**
- Error: `The term 'Search-UnifiedAuditLog' is not recognized`
- Or: `Search-UnifiedAuditLog requires Exchange Online connection`

**Possible causes:**
- ExchangeOnlineManagement module not imported
- Exchange Online not connected before searching
- Module version incompatible with PowerShell 7.4 (for example, ExchangeOnlineManagement 3.10+)

**Resolution:**
1. Verify module: **Automation Account** → **Modules** → `ExchangeOnlineManagement` Runtime 7.4 → Status: Available (recommended range: 3.0.0-3.9.2)
2. Ensure `Connect-ExchangeOnline` succeeds before `Search-UnifiedAuditLog`
3. Update module to latest version if Status shows issues

### Issue 9: CSV Export Path Failure

**Symptoms:**
- Error writing CSV to `$env:TEMP`
- `Export-Csv : Access to the path is denied`

**Possible causes:**
- `$env:TEMP` not defined in Azure Automation context
- Disk space issue in sandbox

**Resolution:**
1. Azure Automation runbooks typically have access to `$env:TEMP`; verify it is populated in the Test pane
2. If failing, configure a tenant-approved export directory and create it before `Export-Csv` rather than relying on a hardcoded local path
3. Verify the CSV is generated correctly in the Test Pane before scheduling

### Issue 10: WhatIf Not Working (Changes Still Applied)

**Symptoms:**
- Running with `-WhatIf` still makes actual changes
- Environments are modified despite WhatIf flag

**Possible causes:**
- Incorrect WhatIf parameter binding
- `SupportsShouldProcess` not properly configured in CmdletBinding

**Resolution:**
1. Verify the script is using `$PSCmdlet.ShouldProcess()` gates around all modification calls
2. Ensure `-WhatIf` is passed at the command line (not just referenced as a variable)
3. Test with: `.\Enable-AuditLogging.ps1 -DataverseEnvironmentUrl $url -TenantDomain $domain -WhatIf`
4. Verify `[WHATIF]` prefix appears in output for each would-be action

---

*Updated: April 2026 | Version: v1.0.4*
