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
   - Use hybrid Azure AD joined as alternative
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

# Or use client credentials for automation
$secureSecret = ConvertTo-SecureString "<secret>" -AsPlainText -Force
$credential = New-Object PSCredential("<client-id>", $secureSecret)
Connect-MgGraph -TenantId "<tenant-id>" -ClientSecretCredential $credential
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
    -TenantId "<tenant-id>" `
    -OutputPath "./baseline" `
    -Force
```

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
   - Use Azure AD emergency access procedures

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

```powershell
.\scripts\Restore-PolicyBaseline.ps1 `
    -TenantId "<tenant-id>" `
    -BaselinePath "./baseline" `
    -Confirm
```

---

## Getting Help

If issues persist:

1. Collect diagnostic information:
```powershell
.\scripts\Export-Diagnostics.ps1 -OutputPath "./diagnostics"
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
