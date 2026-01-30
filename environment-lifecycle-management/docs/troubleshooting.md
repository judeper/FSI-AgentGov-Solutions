# Troubleshooting

Common issues, error recovery procedures, and rollback guidance.

## Error Categories

| Category | Severity | Example |
|----------|----------|---------|
| **Authentication** | High | SP credential expired |
| **Provisioning** | High | Environment creation failed |
| **Configuration** | Medium | Baseline settings not applied |
| **Integration** | Medium | Flow trigger not firing |
| **Validation** | Low | Invalid security group name |

---

## Authentication Errors

### 401 Unauthorized - Service Principal

**Symptoms:**
- Power Automate flow fails with 401
- Error: "The client credentials are invalid"

**Causes:**
1. Client secret expired
2. Secret not correctly stored in Key Vault
3. Wrong tenant/client ID

**Resolution:**

1. Check secret expiry in Entra ID:
   - App registrations > Your app > Certificates & secrets
   - Verify secret hasn't expired

2. Rotate if expired:
   ```bash
   python scripts/register_service_principal.py \
     --tenant-id <tenant> \
     --app-name ELM-Provisioning-ServicePrincipal \
     --key-vault-name <vault> \
     --rotate-secret \
     --verbose
   ```

3. Test connection:
   ```bash
   python scripts/elm_client.py --test-connection
   ```

### 403 Forbidden - Insufficient Permissions

**Symptoms:**
- Environment creation returns 403
- "The caller does not have the required permissions"

**Causes:**
1. SP not registered as Power Platform Management App
2. SP application user missing in Dataverse
3. ELM Admin role not assigned

**Resolution:**

1. Verify PPAC registration:
   - admin.powerplatform.microsoft.com > Settings > Service principal
   - Status should show "Enabled"

2. Re-register if needed:
   - Enter Application ID again
   - Click Create

3. Verify Dataverse application user:
   - Environment > Settings > Users
   - Filter to Application users
   - Confirm SP appears with ELM Admin role

---

## Provisioning Errors

### Environment Creation Timeout

**Symptoms:**
- Flow exceeds 60-minute timeout
- State stuck at "Provisioning"
- ProvisioningLog shows "ProvisioningStarted" but no "EnvironmentCreated"

**Causes:**
1. Power Platform capacity issues
2. Region-specific delays
3. Service disruption

**Resolution:**

1. Check environment status in PPAC:
   - admin.powerplatform.microsoft.com > Environments
   - Search for environment name
   - Check provisioning state

2. If environment exists but flow timed out:
   - Manually update EnvironmentRequest:
     - Set `fsi_environmentid` to environment GUID
     - Set `fsi_state` to Provisioning (6)
   - Re-trigger remaining steps manually or wait for next flow run

3. If environment doesn't exist:
   - Set `fsi_state` back to Approved (4)
   - Flow will re-trigger and retry

### Environment Creation Failed

**Symptoms:**
- Power Platform connector returns error
- ProvisioningLog shows "ProvisioningFailed"

**Common Error Messages:**

| Error | Cause | Resolution |
|-------|-------|------------|
| "EnvironmentQuotaExceeded" | Tenant environment limit | Request quota increase or delete unused environments |
| "InvalidRegion" | Region not available | Use different region or verify region spelling |
| "CapacityNotAvailable" | No capacity in region | Try different region or wait |
| "DuplicateName" | Environment name exists | Use unique name |

**Resolution:**

1. Review error in ProvisioningLog `fsi_errormessage`
2. Address root cause
3. Set `fsi_state` back to Approved (4) to retry

### Managed Environment Enable Failed

**Symptoms:**
- Environment created but not managed
- ProvisioningLog missing "ManagedEnabled" entry

**Causes:**
1. API version mismatch
2. Environment type doesn't support managed
3. Transient API error

**Resolution:**

1. Manually enable via PPAC:
   - Environment > Settings > Edit
   - Enable Managed Environment

2. Or via PowerShell:
   ```powershell
   Set-AdminPowerAppEnvironmentGovernanceConfiguration `
     -EnvironmentName <env-id> `
     -EnableGovernanceConfiguration $true
   ```

3. Log manual action in ProvisioningLog

### Environment Group Assignment Failed

**Symptoms:**
- Environment created but not in expected group
- Error: "Environment group not found"

**Causes:**
1. Group name mismatch (case-sensitive)
2. Group deleted
3. Transient API error

**Resolution:**

1. Verify group exists:
   - admin.powerplatform.microsoft.com > Environment groups
   - Confirm exact name matches flow variable

2. Manually add to group:
   - Select environment group
   - Add environment

3. Update flow variable if name changed

---

## Configuration Errors

### Baseline Configuration Not Applied

**Symptoms:**
- Environment created but auditing not enabled
- Session timeout not set

**Causes:**
1. Child flow failed
2. Organization ID lookup failed
3. Permission denied on settings

**Resolution:**

1. Check child flow run history
2. Manually apply settings via PowerShell:

   ```powershell
   # Connect to environment
   $conn = Connect-CrmOnline -ServerUrl "https://<env>.crm.dynamics.com"

   # Get organization ID
   $org = Get-CrmOrganizations | Select-Object -First 1

   # Update settings
   Set-CrmRecord -conn $conn -EntityLogicalName organization -Id $org.OrganizationId -Fields @{
     "isauditenabled" = $true
     "isuseraccessauditenabled" = $true
     "auditretentionperiodv2" = 365
     "sessiontimeoutenabled" = $true
     "sessiontimeoutinmins" = 480
   }
   ```

### Security Group Binding Failed

**Symptoms:**
- Zone 2/3 environment without security group
- Error: "Security group not found"

**Causes:**
1. Invalid security group ID
2. Group deleted after request
3. Graph API permission issue

**Resolution:**

1. Verify group exists:
   ```bash
   az ad group show --group "<group-id>"
   ```

2. If group exists, manually bind:
   - PPAC > Environment > Settings > Edit
   - Security group: Select correct group

3. If group doesn't exist, contact requester for valid group

---

## Integration Errors

### Flow Trigger Not Firing

**Symptoms:**
- Request approved but no provisioning starts
- Flow run history shows no recent runs

**Causes:**
1. Trigger filter condition not met
2. Flow disabled
3. Connection expired

**Resolution:**

1. Verify flow is enabled:
   - make.powerautomate.com > My flows
   - Check flow status

2. Check connections:
   - All connections should show green checkmark

3. Verify trigger condition:
   - Filter: `fsi_state eq 4`
   - Manually verify request has state = 4 (Approved)

4. Test trigger:
   - Update a test request to state = Approved
   - Check if flow runs

### Copilot Agent Not Responding

**Symptoms:**
- Agent doesn't respond to requests
- Error: "Something went wrong"

**Causes:**
1. Agent not published
2. Authentication issue
3. Power Automate action failed

**Resolution:**

1. Verify agent is published:
   - Copilot Studio > Agent > Publish status

2. Check authentication:
   - Settings > Security
   - Verify "Authenticate with Microsoft" is configured

3. Test topics individually:
   - Use Test panel in Copilot Studio
   - Check for errors in each node

---

## Validation Errors

### Invalid Environment Name

**Symptoms:**
- Agent rejects environment name
- Error: "Name must follow pattern"

**Resolution:**

Correct naming format: `DEPT-Purpose-TYPE`

| Valid | Invalid |
|-------|---------|
| FIN-Reporting-PROD | Finance-Reporting-Production |
| IT-DevTest-SANDBOX | it-devtest-sandbox |
| COMP-Risk-DEV | COMP_Risk_DEV |

### Security Group Not Found

**Symptoms:**
- Flow fails during group validation
- Error: "Group not found in Entra ID"

**Resolution:**

1. Verify exact group name with requester
2. Search in Entra ID:
   - entra.microsoft.com > Groups
   - Search by name or ID

3. If group is correct but lookup fails:
   - Check Graph API permissions
   - Verify `Group.Read.All` permission granted

---

## Rollback Procedures

### When to Rollback

| Scenario | Rollback? | Action |
|----------|-----------|--------|
| Environment created, config failed | No | Complete config manually |
| Environment created, wrong zone | Maybe | Reconfigure or delete if <1 hour |
| Environment created with wrong name | Yes | Delete and recreate |
| Provisioning stuck | Maybe | Check PPAC first |

### Manual Rollback Steps

1. **Log rollback initiation:**
   - Create ProvisioningLog entry with action = RollbackInitiated

2. **Delete environment (if appropriate):**
   ```powershell
   # Only if environment is <1 hour old and hasn't been used
   Remove-AdminPowerAppEnvironment -EnvironmentName "<env-id>" -Confirm
   ```

3. **Update request:**
   - Set `fsi_state` = Failed (8)
   - Clear `fsi_environmentid`
   - Clear `fsi_environmenturl`

4. **Log rollback completion:**
   - Create ProvisioningLog entry with action = RollbackCompleted

5. **Notify requester:**
   - Explain what happened
   - Provide next steps (resubmit or modified request)

### Rollback Decision Matrix

| Time Since Creation | Data Added | Rollback? |
|---------------------|------------|-----------|
| < 5 minutes | No | Yes - Auto |
| 5-60 minutes | No | Yes - Manual approval |
| > 60 minutes | No | Review case-by-case |
| Any | Yes | No - Manual remediation |

---

## Evidence Collection Errors

### Export Script Fails

**Symptoms:**
- `export_quarterly_evidence.py` returns error
- Empty or incomplete export files

**Causes:**
1. Authentication failure
2. Date range issues
3. Large dataset timeout

**Resolution:**

1. Test authentication:
   ```bash
   python scripts/elm_client.py --test-connection
   ```

2. Try smaller date range:
   ```bash
   python scripts/export_quarterly_evidence.py \
     --start-date 2026-01-01 \
     --end-date 2026-01-31
   ```

3. Check FetchXML query in script output (verbose mode)

### Immutability Check Fails

**Symptoms:**
- `validate_immutability.py` reports violations
- Unexpected audit entries found

**Investigation:**

1. Run detailed check:
   ```bash
   python scripts/validate_immutability.py \
     --environment-url https://<org>.crm.dynamics.com \
     --verbose
   ```

2. Review audit entries:
   - Who attempted modification?
   - When did it occur?
   - Was it blocked?

3. If modifications succeeded:
   - **CRITICAL**: Security incident
   - Review security role configuration
   - Check for System Administrator overrides
   - Document and report per security policy

---

## Getting Help

### Information to Gather

Before escalating, collect:

1. **Request details:**
   - Request number (REQ-XXXXX)
   - Requested environment name
   - Zone classification

2. **Error information:**
   - Exact error message
   - ProvisioningLog entries
   - Flow run ID (correlation ID)

3. **Environment:**
   - Governance environment URL
   - Target environment (if created)
   - Timestamp of failure

### Escalation Path

| Issue Type | Contact |
|------------|---------|
| Flow failures | Platform Operations |
| Permission issues | Identity team |
| API errors | Microsoft Support |
| Security incidents | Security Operations |

### Microsoft Support

For platform issues, open support case:

1. admin.powerplatform.microsoft.com > Help + support
2. Include:
   - Environment ID
   - Correlation ID from flow
   - Error message
   - Timestamp (UTC)

---

## Preventive Measures

### Monitoring

Set up alerts for:

- Flow failures (Power Automate)
- Environment creation failures (PPAC alerts)
- Credential expiry (90 days before)
- Immutability violations (weekly check)

### Regular Maintenance

| Task | Frequency | Script/Action |
|------|-----------|---------------|
| Credential rotation | 90 days | `register_service_principal.py --rotate` |
| Immutability check | Weekly | `validate_immutability.py` |
| Role privilege audit | Monthly | `verify_role_privileges.py` |
| Connection health check | Weekly | Manual in Power Automate |
| Quarterly evidence export | Quarterly | `export_quarterly_evidence.py` |
