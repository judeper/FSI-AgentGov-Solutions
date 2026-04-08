# Troubleshooting Guide

## Common Issues

### API Schema Validation Failed

**Symptom:** Flow run fails at a Dataverse create/update action with a schema validation error.

**Cause:** Column logical names in the flow action do not match the deployed Dataverse schema. This can happen if entity set names or column names were customized during deployment.

**Resolution:**
1. Open the solution's `create_ctsg_dataverse_schema.py` and confirm the `SchemaName` for each column
2. Lowercase the `SchemaName` to get the correct logical name (e.g., `fsi_ExternalTenantId` → `fsi_externaltenantid`)
3. Update the flow action to use the correct logical names
4. Refer to the DELIVERY-CHECKLIST.md for confirmed field names if available

### Flow Terminates with Feature Flag Check

**Symptom:** Flow run completes immediately without processing, showing "Feature flag disabled" in run history.

**Cause:** The `IsCrossTenantGovernanceEnabled` environment variable is set to `"false"`. This is intentional during initial deployment to allow schema and permission validation before activating governance flows.

**Resolution:**
1. Verify all prerequisites are met (see [Prerequisites](prerequisites.md))
2. Confirm Managed Identity permissions are propagated
3. Set `IsCrossTenantGovernanceEnabled` to `"true"` in the Power Platform environment variables
4. Trigger a test run of each flow to validate end-to-end processing

### Guest User Domain Resolution Failed (Unresolved)

**Symptom:** Finding record shows "Unknown" for the external tenant domain. Flow logs show all three resolution methods attempted.

**Cause:** The three-method fallback chain (EXT# UPN parsing → mail field → creationType) yielded no domain for the guest user. This can occur with service accounts or programmatically-created guest users that lack standard mail attributes.

**Resolution:**
1. Open the guest user record in Entra ID and check for a valid `mail` or `otherMails` attribute
2. If the user has no email attributes, manually identify the source tenant from the `createdBy` audit log
3. Update the finding record with the correct external tenant information
4. Consider adding the tenant to the approved registry if the relationship is legitimate

### Permission Denied on Graph API Calls

**Symptom:** Flow HTTP action returns `403 Forbidden` when calling Microsoft Graph.

**Cause:** Managed Identity permissions have not been granted or have not yet propagated. App role assignments can take up to 30 minutes to become effective.

**Resolution:**
1. Verify the Managed Identity Object ID matches the service principal in Entra ID
2. Confirm all required app roles are assigned (see [Prerequisites — Managed Identity Setup](prerequisites.md#managed-identity-setup))
3. Wait 30 minutes after assignment before retesting
4. If permissions were recently changed, restart the Azure Automation runbook or flow to pick up new tokens
5. Check the Entra ID audit log for any denied consent operations

### Duplicate Findings Not Created

**Symptom:** A known cross-tenant violation is not generating a new finding record.

**Cause:** Deduplication is working correctly. The detection flows check for existing open findings with the same agent ID, external tenant ID, and finding type combination before creating new records.

**Resolution:**
1. Search `fsi_externalsharefindings` for existing records matching the agent and tenant combination
2. If an open finding already exists, it should be remediated or closed before a new detection creates a fresh record
3. If the existing finding was remediated but the violation recurred, verify the previous finding status was set to "Resolved" — only resolved or closed findings allow new detections for the same combination

### Tenant Isolation Disabled Cannot Be Auto-Remediated

**Symptom:** Flow 5 (Auto-Remediation) logs show "Tenant isolation remediation deferred — manual action required."

**Cause:** Flow 5 correctly defers this action. Enabling tenant isolation is a tenant-wide setting that can disrupt legitimate cross-tenant integrations. Automated enablement could cause service outages.

**Resolution:**
1. Review the finding in the Power Apps portal (Screen 2)
2. Assess impact by reviewing the approved tenant registry for any active cross-tenant integrations
3. Enable tenant isolation manually in the Power Platform admin center under **Tenant settings** > **Tenant isolation**
4. After enabling, run Flow 1 (Tenant Isolation Audit) to confirm the new state is recorded

### Expired Onboarding Request

**Symptom:** An external tenant onboarding request shows status "Expired" and cannot be edited.

**Cause:** The 10 business day approval timeout elapsed without a governance team decision. Expired records are locked to maintain audit trail integrity.

**Resolution:**
1. The original requestor must submit a new onboarding request via the Power Apps portal (Screen 1 > "New Request")
2. Reference the expired request ID in the new submission for continuity
3. The governance team should review and act on new requests within the 10 business day window
4. Consider configuring reminder notifications in Flow 4 to alert approvers before timeout

### OptionSet Value Mismatch

**Symptom:** Flow actions fail with "Invalid option set value" errors, or records display incorrect labels.

**Cause:** The integer values used in flow expressions do not match the option set definitions in the deployed Dataverse schema.

**Resolution:**
1. Open the solution's `create_ctsg_dataverse_schema.py` and locate the option set definitions
2. Confirm the integer values for each option (e.g., Approval Status: Pending = 0, Approved = 1, Expired = 2)
3. Update flow expressions to use the correct integer values
4. If the solution was imported over an existing schema, check for option set value conflicts

### Entity Set Name Not Found

**Symptom:** Dataverse API calls return `404 Not Found` when referencing an entity set.

**Cause:** Entity set names in Dataverse are pluralized versions of the logical entity name, and custom publishers may add prefixes that alter the expected name.

**Resolution:**
1. Query the Dataverse metadata endpoint to find the correct entity set name:
   ```
   GET [OrgUrl]/api/data/v9.2/EntityDefinitions?$filter=LogicalName eq 'fsi_approvedexternaltenant'&$select=EntitySetName
   ```
2. Update flow actions and API calls to use the returned `EntitySetName`
3. Document the confirmed entity set names for the deployment environment

## Flow-Specific Issues

### Flow 1: Tenant Isolation Audit

- **Issue:** Flow returns empty results for tenant isolation status
  - **Check:** Verify `MI-CrossTenantReadOnly` has `PowerPlatform.Admin.Read.All` permission
  - **Check:** Confirm the Power Platform API endpoint URL is correct for your region

- **Issue:** Historical comparison fails on first run
  - **Expected:** The first run creates a baseline record. Comparison logic activates from the second run onward.

### Flow 3: Entra CTA Policy Audit

- **Issue:** Partner policies return empty array
  - **Check:** Verify `MI-CrossTenantReadOnly` has `Policy.Read.All` permission
  - **Check:** Confirm at least one cross-tenant access partner policy exists in Entra ID

- **Issue:** Tenant display name shows as GUID
  - **Check:** Verify `CrossTenantInformation.ReadBasic.All` permission is assigned
  - **Note:** Some tenant IDs may not resolve if the remote tenant has restricted directory visibility

### Flow 2: External Agent Share Detection

- **Issue:** No agent shares detected despite known external sharing
  - **Check:** Verify the Power Platform API returns share data for the target environment
  - **Check:** Confirm agent shares include role assignment details with user principal names

- **Issue:** Guest user classification misidentifies internal users
  - **Check:** Review the domain comparison logic — users with UPN domains matching the home tenant should be excluded
  - **Check:** Verify `Organization.Read.All` permission is assigned for home tenant domain resolution

### Flow 4: External Tenant Onboarding

- **Issue:** Approval email not sent
  - **Check:** Verify the governance team distribution list or shared mailbox is configured
  - **Check:** Confirm the Power Automate connection for Office 365 Outlook is authorized

- **Issue:** CTA partner policy creation fails
  - **Check:** Verify `MI-CrossTenantReadWrite` has `Policy.ReadWrite.CrossTenantAccess` permission
  - **Check:** Confirm no existing partner policy exists for the same tenant ID (duplicates are rejected by Graph API)

### Flow 5: Auto-Remediation

- **Issue:** Remediation action completes but finding status not updated
  - **Check:** Verify the flow has write access to `fsi_externalsharefindings` table
  - **Check:** Review the Dataverse update action for correct record ID binding

- **Issue:** Agent share removal fails with permission error
  - **Check:** Verify `MI-CrossTenantReadWrite` has `PowerPlatform.Admin.ReadWrite.All` permission
  - **Check:** Confirm the target agent share has not already been removed by another process

### Flow 6: Compliance Event Logging

- **Issue:** Events not appearing in `fsi_crosstenantcomplianceevents`
  - **Check:** Verify Flow 6 is activated and running
  - **Check:** Confirm the Dataverse connection in Flow 6 is authorized and pointing to the correct environment

- **Issue:** Event timestamps show incorrect timezone
  - **Check:** Power Automate uses UTC by default — verify timezone conversion in flow expressions if local time display is required

## Contact

For issues not covered here, contact the FSI Agent Governance team.
