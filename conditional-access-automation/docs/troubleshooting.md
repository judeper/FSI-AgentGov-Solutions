# Troubleshooting

Common issues and resolution procedures for the Conditional Access Automation solution.

## Deployment Issues

### Insufficient Permissions Error

**Symptom:**
```
Error: Insufficient privileges to complete the operation.
Status: 403 Forbidden
```

**Cause:** Service principal lacks required Graph API permissions.

**Resolution:**
1. Verify permissions granted:
```powershell
Get-MgServicePrincipal -Filter "appId eq '<app-id>'" |
    Select-Object -ExpandProperty AppRoles
```

2. Add missing permissions:
```powershell
# Required permissions
$permissions = @(
    "Policy.Read.All",
    "Policy.ReadWrite.ConditionalAccess",
    "Application.Read.All",
    "Directory.Read.All"
)

# Add via Azure portal or Graph API
```

3. Grant admin consent:
```
https://login.microsoftonline.com/<tenant-id>/adminconsent?client_id=<app-id>
```

---

### Policy Already Exists Error

**Symptom:**
```
Error: A policy with this display name already exists.
```

**Cause:** Attempting to create a policy with a duplicate name.

**Resolution:**
1. Check existing policies:
```powershell
Get-MgIdentityConditionalAccessPolicy |
    Where-Object { $_.DisplayName -like "CA-FSI-*" } |
    Select-Object DisplayName, Id
```

2. Options:
   - Use `-Force` parameter to overwrite existing
   - Delete existing policy first
   - Use different policy prefix in config

---

### Key Vault Access Denied

**Symptom:**
```
Error: Access denied to Key Vault '<vault-name>'.
```

**Cause:** Current identity lacks Key Vault access.

**Resolution:**
```powershell
# Grant access to current user
az keyvault set-policy `
    --name "<vault-name>" `
    --upn "admin@contoso.com" `
    --secret-permissions get list set

# Or grant to service principal
az keyvault set-policy `
    --name "<vault-name>" `
    --object-id "<sp-object-id>" `
    --secret-permissions get list
```

---

## Policy Issues

### Users Not Being Prompted for MFA

**Symptom:** Users can access AI applications without MFA prompt.

**Cause:** Multiple possible causes.

**Resolution Checklist:**

1. **Policy State:**
```powershell
$policy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq 'CA-FSI-CopilotStudio-Zone3-MFA-CompliantDevice'"
$policy.State  # Should be "enabled", not "enabledForReportingButNotEnforced"
```

2. **User Assignment:**
- Verify user is in the target group
- Verify user is not in an exclusion group
```powershell
$user = Get-MgUser -Filter "userPrincipalName eq 'user@contoso.com'"
Get-MgUserMemberOf -UserId $user.Id | Where-Object { $_.Id -eq "<zone-3-group-id>" }
```

3. **Application Assignment:**
- Verify the application ID is correct
- Check if using correct enterprise app vs app registration

4. **What-If Testing:**
```powershell
# Use Entra ID portal: Conditional Access > What If
# Or Graph API evaluation endpoint
```

---

### Authentication strength policy not counted as MFA

**Symptom:** A phishing-resistant or passwordless authentication-strength policy is reported as missing MFA.

**Cause:** Older validation logic only inspected `grantControls.builtInControls` and ignored `grantControls.authenticationStrength`.

**Resolution:** Use v2.0.1 or later. The validation and drift scripts now treat MFA-satisfying authentication strengths as valid MFA requirements and compare authentication-strength drift.

---

### MFA Prompt Loops

**Symptom:** User repeatedly prompted for MFA, never able to complete sign-in.

**Cause:** Conflicting policies or session control issues.

**Resolution:**

1. **Check for conflicting policies:**
```powershell
# Find all policies applying to the user/app combination
Get-MgIdentityConditionalAccessPolicy | Where-Object {
    $_.Conditions.Applications.IncludeApplications -contains "<app-id>" -or
    $_.Conditions.Applications.IncludeApplications -contains "All"
} | Select-Object DisplayName, State, GrantControls
```

2. **Check session controls:**
- Ensure sign-in frequency isn't too short (minimum 1 hour)
- Check persistent browser settings

3. **Temporary workaround:**
- Add user to exclusion temporarily
- Investigate with sign-in logs
- Remove from exclusion after fix

---

### Embedded Power Automate connections break after CA changes

**Symptom:** Embedded flows in SharePoint, Teams, Excel, or model-driven apps show token or MFA errors after a CA policy change.

**Cause:** Host apps and Microsoft Flow Service can have inconsistent Conditional Access requirements when policies target individual applications.

**Resolution:** Target **Office 365** or **All cloud apps** where appropriate, or explicitly align requirements for host apps and Microsoft Flow Service (`7df0a125-d3be-4c96-aa54-591f83ff541c`). Ask affected users to sign out and sign back in after policy repair.

---

### Unexpected Blocks

**Symptom:** Legitimate users being blocked from access.

**Cause:** Overly restrictive conditions or missing exclusions.

**Resolution:**

1. **Check sign-in logs:**
```powershell
Get-MgAuditLogSignIn -Filter "userPrincipalName eq 'user@contoso.com' and status/errorCode ne 0" -Top 10 |
    Select-Object CreatedDateTime, AppDisplayName, Status, ConditionalAccessStatus
```

2. **Review applied policies:**
```powershell
$signIn = Get-MgAuditLogSignIn -Filter "userPrincipalName eq 'user@contoso.com'" -Top 1
$signIn.AppliedConditionalAccessPolicies | Format-Table DisplayName, Result, EnforcedGrantControls
```

3. **Common causes:**
   - User on unmanaged device (compliant device required)
   - Legacy authentication client
   - High-risk sign-in detected
   - Location-based restrictions

---

### Device Compliance Requirements Failing

**Symptom:** Users with managed devices still blocked for device compliance.

**Cause:** Device not properly registered or compliance policy not met.

**Resolution:**

1. **Check device status:**
```powershell
$user = Get-MgUser -Filter "userPrincipalName eq 'user@contoso.com'"
Get-MgUserRegisteredDevice -UserId $user.Id |
    Select-Object DisplayName, DeviceId, IsCompliant, TrustType
```

2. **Verify device compliance:**
   - Check Intune compliance policies
   - Verify device sync status
   - Check compliance policy assignments

3. **Temporary workaround:**
   - Use Microsoft Entra hybrid joined as alternative
   - Check if device just needs to sync

---

## Script Issues

### Module Not Found

**Symptom:**
```
Error: The term 'Get-MgIdentityConditionalAccessPolicy' is not recognized
```

**Cause:** Microsoft Graph module not installed or not imported.

**Resolution:**
```powershell
# Install module
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Import specific submodule
Import-Module Microsoft.Graph.Identity.SignIns

# Verify
Get-Command Get-MgIdentityConditionalAccessPolicy
```

---

### Authentication Token Expired

**Symptom:**
```
Error: Token has expired. Please re-authenticate.
```

**Cause:** Cached token expired during long-running operation.

**Resolution:**
```powershell
# Disconnect and reconnect
Disconnect-MgGraph
Connect-MgGraph -TenantId "<tenant-id>" -Scopes "Policy.ReadWrite.ConditionalAccess"

# Preferred for Azure Automation: managed identity
Connect-MgGraph -Identity

# Certificate fallback when managed identity is unavailable
Connect-MgGraph -TenantId "<tenant-id>" -ClientId "<client-id>" `
    -CertificateThumbprint "<thumbprint>"

# legacy: dev-only — replace with managed identity in production
# $secureSecret = ConvertTo-SecureString "<secret>" -AsPlainText -Force
# $credential = New-Object PSCredential("<client-id>", $secureSecret)
# Connect-MgGraph -TenantId "<tenant-id>" -ClientSecretCredential $credential
```

---

### Rate Limiting

**Symptom:**
```
Error: Request was throttled. Too many requests.
Status: 429
```

**Cause:** Exceeded Graph API rate limits.

**Resolution:**
1. Add delays between operations:
```powershell
foreach ($policy in $policies) {
    # Process policy
    Start-Sleep -Milliseconds 500
}
```

2. Implement retry logic:
```powershell
$retryCount = 0
$maxRetries = 3
do {
    try {
        $result = Invoke-MgGraphRequest -Uri $uri -Method GET
        break
    } catch {
        if ($_.Exception.Response.StatusCode -eq 429) {
            $retryAfter = $_.Exception.Response.Headers["Retry-After"]
            Start-Sleep -Seconds ([int]$retryAfter + 1)
            $retryCount++
        } else { throw }
    }
} while ($retryCount -lt $maxRetries)
```

---

## Compliance Issues

### Drift Detection False Positives

**Symptom:** Drift alerts for changes that are expected.

**Cause:** Baseline needs updating after legitimate changes.

**Resolution:**
1. Verify the change is legitimate
2. Update the baseline:
```powershell
.\scripts\Export-PolicyBaseline.ps1 `
    -TenantId   "<tenant-id>" `
    -OutputPath "./baselines/baseline.json"
```

> `Export-PolicyBaseline.ps1 -OutputPath` is a **file path**, not a directory,
> and the script does NOT expose a `-Force` switch. The file is overwritten
> in place each run, so re-running is the supported way to refresh a baseline.

3. Add expected changes to ignore list:
```json
{
  "ignoreChanges": [
    { "policyName": "CA-FSI-*", "property": "modifiedDateTime" }
  ]
}
```

---

### Evidence Export Missing Data

**Symptom:** Export doesn't include all expected records.

**Cause:** Audit log retention or filter issues.

**Resolution:**

1. **Check audit log retention:**
- Entra ID P1: 30 days
- Entra ID P2: 30 days (extendable to 2 years with log analytics)

2. **Verify date filters:**
```powershell
# Ensure dates are in correct format
$startDate = [datetime]::Parse("2026-01-01").ToUniversalTime().ToString("o")
$endDate = [datetime]::Parse("2026-03-31").ToUniversalTime().ToString("o")
```

3. **Export to Log Analytics for long-term retention:**
- Configure diagnostic settings in Entra ID
- Export to Log Analytics workspace
- Query from workspace for older data

---

## Recovery Procedures

### Emergency: All Users Blocked

If a policy misconfiguration blocks all users:

1. **Use break-glass account:**
```powershell
# Sign in as break-glass account
Connect-MgGraph -TenantId "<tenant-id>"

# Disable problematic policy immediately
Update-MgIdentityConditionalAccessPolicy `
    -ConditionalAccessPolicyId "<policy-id>" `
    -State "disabled"
```

2. **If break-glass account also blocked:**
   - Contact Microsoft Support
   - Use Microsoft Entra ID emergency access procedures

### Rollback All Policies

```powershell
# Disable all FSI policies
Get-MgIdentityConditionalAccessPolicy |
    Where-Object { $_.DisplayName -like "CA-FSI-*" } |
    ForEach-Object {
        Update-MgIdentityConditionalAccessPolicy `
            -ConditionalAccessPolicyId $_.Id `
            -State "disabled"
        Write-Host "Disabled: $($_.DisplayName)"
    }
```

### Restore from Baseline

Restore CA policies from a previously exported baseline by re-deploying:

```powershell
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -TemplateSet "All" `
    -EnablePolicies $true
```

---

## Getting Help

If issues persist:

1. Collect diagnostic information:
```powershell
# Gather CA policy state
Get-MgIdentityConditionalAccessPolicy |
    Where-Object { $_.DisplayName -like "CA-*" } |
    Select-Object DisplayName, State, Id |
    ConvertTo-Json -Depth 5 | Out-File "./diagnostics/ca-policies.json"

# Check Graph API connectivity
Get-MgContext | Select-Object Account, TenantId, Scopes
```

2. Check Microsoft service health:
   - https://status.office365.com
   - Entra ID service status

3. Review documentation:
   - [Microsoft CA documentation](https://learn.microsoft.com/en-us/entra/identity/conditional-access/)
   - [FSI-AgentGov Control 1.11 playbooks](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/control-implementations/1.11/troubleshooting.md)

4. Open GitHub issue with:
   - Error messages
   - Script output
   - Policy configurations (sanitized)

---

## Evidence Export Issues

### Hash Mismatch After Export

**Symptom:**
```
HASH MISMATCH — Expected: A1B2C3... Actual: D4E5F6...
Test-EvidenceIntegrity returns Valid = $false
```

**Cause:** The evidence JSON file was modified after export (manual edits, encoding changes, or file transfer corruption).

**Resolution:**
1. Do not modify evidence files after export — they are tamper-evident by design
2. Re-export from the Dataverse source using the same date range:
```powershell
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence" `
    -FromDate "2026-01-01" -ToDate "2026-01-31"
```
3. Verify the new export:
```powershell
.\scripts\Test-EvidenceIntegrity.ps1 -EvidencePath "./evidence/CAA-Evidence-*.json"
```

---

### Empty Validations Array

**Symptom:** Evidence JSON contains `"validations": []` with `"recordCount": 0`.

**Cause:** No validation runs occurred within the specified date range.

**Resolution:**
1. Check the `-FromDate` and `-ToDate` parameters — they may be too narrow
2. Verify the daily compliance flow is running:
```powershell
# Check recent flow runs in Power Automate admin center
# Or query Dataverse directly for recent validation records
Get-CAAValidationResults -DataverseUrl $url -AccessToken $token `
    -Table 'fsi_capolicyvalidationhistories' `
    -FromDate (Get-Date).AddDays(-7)
```
3. Trigger a manual validation run to populate data:
```powershell
.\scripts\Test-PolicyCompliance.ps1 -TenantId "<tenant-id>" -OutputPath "./reports"
```

---

### Truncated JSON Output

**Symptom:** Evidence JSON file is incomplete or fails to parse (`ConvertFrom-Json` throws an error).

**Cause:** The `ConvertTo-Json` depth was insufficient for nested policy data. The export script uses `-Depth 10` by default, but manual JSON manipulation or piping through other tools may truncate the output.

**Resolution:**
1. Re-run the export script without modifications — it includes `-Depth 10` automatically
2. If processing evidence manually, always specify depth:
```powershell
$evidence | ConvertTo-Json -Depth 10 | Out-File -FilePath $path -Encoding utf8
```
3. Validate the JSON structure:
```powershell
$json = Get-Content "./evidence/CAA-Evidence-*.json" -Raw | ConvertFrom-Json
$json.metadata  # Should contain exportedAt, scope, etc.
```

---

### Dataverse Authentication Failure

**Symptom:**
```
Error: Failed to acquire Dataverse access token.
Status: 401 Unauthorized
```

**Cause:** Certificate expired, app registration permissions removed, or managed identity not configured.

**Resolution:**
1. Verify the app registration certificate is valid:
```powershell
Get-AzADAppCredential -ApplicationId "<app-id>" |
    Select-Object DisplayName, EndDateTime, Type
```
2. Check Graph API permissions are still granted:
```powershell
Get-MgServicePrincipal -Filter "appId eq '<app-id>'" |
    Get-MgServicePrincipalAppRoleAssignment |
    Select-Object ResourceDisplayName, AppRoleId
```
3. Verify Dataverse environment is accessible:
```powershell
Invoke-RestMethod -Uri "https://org.crm.dynamics.com/api/data/v9.2/WhoAmI" `
    -Headers @{ Authorization = "Bearer $token" }
```
4. If using Azure Automation managed identity, verify it has Dataverse security role assigned

---

### Large Export File

**Symptom:** Evidence JSON file is very large (>100 MB) and slow to process.

**Cause:** Wide date range capturing months of daily validation data.

**Resolution:**
1. Filter by specific run ID to export a single scan:
```powershell
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence" `
    -RunId "specific-run-id"
```
2. Narrow the date range:
```powershell
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence" `
    -FromDate (Get-Date).AddDays(-7) -ToDate (Get-Date)
```
3. Consider weekly exports instead of the 30-day default for environments with many policies
4. Exclude baselines if only validation results are needed:
```powershell
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence" `
    -IncludeBaselines:$false
```
