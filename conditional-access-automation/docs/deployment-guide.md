# Deployment Guide

Step-by-step instructions for deploying Conditional Access policies for AI workloads.

## Deployment Overview

```
1. Prerequisites Check
        ↓
2. Service Principal Setup
        ↓
3. Template Customization
        ↓
4. Deploy (Report-Only)
        ↓
5. Test and Validate
        ↓
6. Enable Policies
        ↓
7. Monitor and Maintain
```

---

## Step 1: Prerequisites Check

Run the prerequisites verification:

```powershell
# Verify PowerShell version
$PSVersionTable.PSVersion

# Verify required modules
Get-Module -ListAvailable Microsoft.Graph*, Az.KeyVault, Az.Accounts |
    Select-Object Name, Version | Format-Table

# Verify roles (connect to Graph first; broader scopes are needed below to
# enumerate groups, users, and service principals during deployment validation).
Connect-MgGraph -Scopes "RoleManagement.Read.Directory","Group.Read.All","User.Read.All","Application.Read.All"
```

---

## Step 2: Automation identity setup

Managed identity is the preferred unattended authentication pattern for Azure Automation. Use `Register-ServicePrincipal.ps1` only when you need a certificate-backed app registration fallback; client secrets are legacy dev-only.

### 2.1 Create App Registration (certificate fallback)

```powershell
.\scripts\Register-ServicePrincipal.ps1 `
    -TenantId "<tenant-id>" `
    -AppName "CAA-Automation-SP" `
    -KeyVaultName "<vault-name>" `
    -DryRun
```

Review the dry run output, then execute:

```powershell
.\scripts\Register-ServicePrincipal.ps1 `
    -TenantId "<tenant-id>" `
    -AppName "CAA-Automation-SP" `
    -KeyVaultName "<vault-name>"
```

### 2.2 Grant Admin Consent

The script outputs a URL for admin consent:

```
Admin consent URL: https://login.microsoftonline.com/<tenant-id>/adminconsent?client_id=<app-id>
```

1. Open the URL in a browser
2. Sign in as Entra Global Admin
3. Review permissions and grant consent

### 2.3 Verify Service Principal

```powershell
# Connect using the service principal
$clientId = Get-AzKeyVaultSecret -VaultName "<vault-name>" -Name "CAA-SP-ClientId" -AsPlainText
$thumbprint = Get-AzKeyVaultSecret -VaultName "<vault-name>" -Name "CAA-SP-CertThumbprint" -AsPlainText

Connect-MgGraph -TenantId "<tenant-id>" -ClientId $clientId -CertificateThumbprint $thumbprint

# legacy: dev-only — replace with managed identity in production
# $clientSecret = Get-AzKeyVaultSecret -VaultName "<vault-name>" -Name "CAA-SP-ClientSecret" -AsPlainText
# $secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
# $credential = New-Object System.Management.Automation.PSCredential($clientId, $secureSecret)
# Connect-MgGraph -TenantId "<tenant-id>" -ClientSecretCredential $credential

# Verify access
Get-MgIdentityConditionalAccessPolicy | Select-Object DisplayName, State | Format-Table
```

---

## Step 3: Template Customization

### 3.1 Gather Required IDs

```powershell
# Get zone security groups
$zone1Group = Get-MgGroup -Filter "displayName eq 'FSI-Zone1-Users'" | Select-Object -ExpandProperty Id
$zone2Group = Get-MgGroup -Filter "displayName eq 'FSI-Zone2-Users'" | Select-Object -ExpandProperty Id
$zone3Group = Get-MgGroup -Filter "displayName eq 'FSI-Zone3-Users'" | Select-Object -ExpandProperty Id

# Get break-glass accounts
$breakGlass1 = Get-MgUser -Filter "userPrincipalName eq 'breakglass1@contoso.onmicrosoft.com'" | Select-Object -ExpandProperty Id
$breakGlass2 = Get-MgUser -Filter "userPrincipalName eq 'breakglass2@contoso.onmicrosoft.com'" | Select-Object -ExpandProperty Id

# Get AI application IDs
$copilotStudio = Get-MgServicePrincipal -Filter "displayName eq 'Copilot Studio'" | Select-Object -ExpandProperty AppId
$agentBuilder = Get-MgServicePrincipal -Filter "displayName eq 'Agent Builder'" | Select-Object -ExpandProperty AppId

# Output for template configuration
@{
    Zone1GroupId = $zone1Group
    Zone2GroupId = $zone2Group
    Zone3GroupId = $zone3Group
    BreakGlass1Id = $breakGlass1
    BreakGlass2Id = $breakGlass2
    CopilotStudioAppId = $copilotStudio
    AgentBuilderAppId = $agentBuilder
} | ConvertTo-Json
```

### 3.2 Create Configuration File

Create `config/tenant-config.json`:

```json
{
  "tenantId": "<your-tenant-id>",
  "groups": {
    "zone1Users": "<zone-1-group-id>",
    "zone2Users": "<zone-2-group-id>",
    "zone3Users": "<zone-3-group-id>"
  },
  "breakGlassAccounts": [
    "<break-glass-1-id>",
    "<break-glass-2-id>"
  ],
  "applications": {
    "copilotStudio": "<copilot-studio-app-id>",
    "agentBuilder": "<agent-builder-app-id>",
    "m365Copilot": "fb8d773d-7ef8-4ec0-a117-179f88add510",
    "microsoftFlowService": "7df0a125-d3be-4c96-aa54-591f83ff541c"
  },
  "policyPrefix": "CA-FSI"
}
```

### 3.3 Validate Configuration

Verify the configuration file is valid JSON and contains all required fields:

```powershell
$config = Get-Content "./config/tenant-config.json" -Raw | ConvertFrom-Json
$config | Select-Object tenantId, policyPrefix
$config.breakGlassAccounts  # Should list 2 accounts
```

---

## Step 4: Deploy (Report-Only)

### 4.1 Dry Run

Preview what will be created:

```powershell
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -TemplateSet "All" `
    -DryRun
```

Expected output:
```
Dry run mode - no changes will be made

Policies to be created:
  1. CA-FSI-CopilotStudio-Zone1-RiskBasedMFA
  2. CA-FSI-CopilotStudio-Zone2-MFARequired
  3. CA-FSI-CopilotStudio-Zone3-MFA-CompliantDevice
  4. CA-FSI-AgentBuilder-Zone2-MFARequired
  5. CA-FSI-AgentBuilder-Zone3-MFA-CompliantDevice
  6. CA-FSI-M365Copilot-AllZones-RiskBasedMFA
  7. CA-FSI-BlockLegacyAuth-AllAI
  8. CA-FSI-RequireCompliantDevice-Zone3

  9. CA-FSI-AgentBuilder-Zone1-RiskBasedMFA
 10. (optional add-on) CA-RiskBased-Zone3-Block — requires Entra ID P2 to evaluate
     signInRiskLevels / userRiskLevels at the Zone-3 risk-block grant control

Total bundled policies: 9 baseline + 1 optional Entra ID P2 add-on
State: Report-only (enabledForReportingButNotEnforced) — switch to enabled
       per zone after report-only review.
```

### 4.2 Deploy

```powershell
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -TemplateSet "All" `
    -EnablePolicies $false
```

### 4.3 Verify Deployment

```powershell
# List deployed policies
Get-MgIdentityConditionalAccessPolicy |
    Where-Object { $_.DisplayName -like "CA-FSI-*" } |
    Select-Object DisplayName, State, CreatedDateTime |
    Format-Table

# Check specific policy
$policy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq 'CA-FSI-CopilotStudio-Zone3-MFA-CompliantDevice'"
$policy | Select-Object DisplayName, State, Conditions, GrantControls | Format-List
```

---

## Step 5: Test and Validate

### 5.1 Wait for Data Collection

Allow 24-48 hours for report-only data collection.

### 5.2 Review Conditional Access Insights

1. Navigate to Entra ID > Conditional Access > Insights and reporting
2. Select time range (last 7 days)
3. Filter by policy names (`CA-FSI-*`)
4. Review:
   - Success vs. failure counts
   - Users impacted
   - Applications covered

### 5.3 What-If Testing

> ⚠️ **Preview API.** The `/beta/identity/conditionalAccess/evaluate` endpoint
> is part of the Microsoft Graph beta surface and is subject to change without
> notice. Do not depend on its response shape in production runbooks; treat
> it as an interactive validation aid only. Track changes in the
> [Microsoft Graph beta changelog](https://learn.microsoft.com/graph/changelog).

```powershell
# Test Zone 3 user accessing Copilot Studio
$testParams = @{
    ConditionalAccessWhatIfSubject = @{
        User = @{ UserId = "<zone-3-user-id>" }
    }
    ConditionalAccessWhatIfConditions = @{
        Application = @{ IncludeApplications = @("<copilot-studio-app-id>") }
        ClientAppType = "browser"
    }
}

Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/beta/identity/conditionalAccess/evaluate" `
    -Body ($testParams | ConvertTo-Json -Depth 10)
```

### 5.4 Authentication strengths and CAE validation

If your tenant adopts phishing-resistant authentication strength for Zone 3, validate the policy references `grantControls.authenticationStrength` and does not also include `builtInControls: ["mfa"]`. Confirm FIDO2/passkey, Windows Hello for Business, or certificate-based authentication registration before enabling the policy. CAE is on by default; treat strict location enforcement as preview and validate named locations before use.

### 5.5 Validate Coverage

```powershell
.\scripts\Test-PolicyCompliance.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -OutputPath "./reports"
```

Review the generated reports for:
- ✓ All target applications covered
- ✓ All zones have appropriate policies
- ✓ Break-glass accounts excluded
- ✓ No overlapping or conflicting policies

---

## Step 6: Enable Policies

### 6.1 Staged Enablement

Enable policies zone by zone:

```powershell
# Enable Zone 1 policies first
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -TemplateSet "Zone1" `
    -EnablePolicies $true

# Wait 24 hours, monitor, then Zone 2
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -TemplateSet "Zone2" `
    -EnablePolicies $true

# Finally Zone 3
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -TemplateSet "Zone3" `
    -EnablePolicies $true
```

### 6.2 Enable All (Alternative)

If testing is complete and confident:

```powershell
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -TemplateSet "All" `
    -EnablePolicies $true
```

### 6.3 Verify Enabled State

```powershell
Get-MgIdentityConditionalAccessPolicy |
    Where-Object { $_.DisplayName -like "CA-FSI-*" } |
    Select-Object DisplayName, State |
    Format-Table
```

All policies should show `State: enabled`.

---

## Step 7: Monitor and Maintain

### 7.1 Set Up Drift Detection

```powershell
# Export baseline (OutputPath is a FILE path, not a directory)
Connect-AzAccount -TenantId "<tenant-id>"
.\scripts\Export-PolicyBaseline.ps1 `
    -TenantId   "<tenant-id>" `
    -OutputPath "./baselines/baseline.json"

# Schedule drift detection (run daily)
.\scripts\Watch-PolicyDrift.ps1 `
    -TenantId "<tenant-id>" `
    -BaselinePath "./baselines/baseline.json"
```

### 7.2 Regular Compliance Checks

Schedule weekly compliance reports:

```powershell
.\scripts\Test-PolicyCompliance.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config/tenant-config.json" `
    -OutputPath "./reports/weekly"
```

### 7.3 Evidence Export (Quarterly)

```powershell
# Authenticate to Azure first so the script can request a Dataverse token.
Connect-AzAccount -TenantId "<tenant-guid>"

.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId    "<tenant-guid>" `
    -OutputPath  "./evidence" `
    -FromDate    "2026-01-01" -ToDate "2026-03-31"
```

---

## Rollback Procedure

If issues occur after enabling policies:

### Disable All Policies

```powershell
Get-MgIdentityConditionalAccessPolicy |
    Where-Object { $_.DisplayName -like "CA-FSI-*" } |
    ForEach-Object {
        Update-MgIdentityConditionalAccessPolicy `
            -ConditionalAccessPolicyId $_.Id `
            -State "disabled"
        Write-Host "Disabled: $($_.DisplayName)"
    }
```

### Revert to Report-Only

```powershell
Get-MgIdentityConditionalAccessPolicy |
    Where-Object { $_.DisplayName -like "CA-FSI-*" } |
    ForEach-Object {
        Update-MgIdentityConditionalAccessPolicy `
            -ConditionalAccessPolicyId $_.Id `
            -State "enabledForReportingButNotEnforced"
        Write-Host "Reverted to report-only: $($_.DisplayName)"
    }
```

### Delete Policies (Full Rollback)

```powershell
Get-MgIdentityConditionalAccessPolicy |
    Where-Object { $_.DisplayName -like "CA-FSI-*" } |
    ForEach-Object {
        Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $_.Id
        Write-Host "Deleted: $($_.DisplayName)"
    }
```

---

## Deployment Checklist

### Pre-Deployment
- [ ] Prerequisites verified
- [ ] Service principal created
- [ ] Admin consent granted
- [ ] Configuration file created
- [ ] IDs validated

### Deployment
- [ ] Dry run completed
- [ ] Policies deployed (report-only)
- [ ] Deployment verified

### Testing
- [ ] 24-48 hours data collection
- [ ] Insights reviewed
- [ ] What-If testing completed
- [ ] Coverage validated

### Enablement
- [ ] Zone 1 enabled and monitored
- [ ] Zone 2 enabled and monitored
- [ ] Zone 3 enabled and monitored
- [ ] All states verified

### Post-Deployment
- [ ] Baseline exported
- [ ] Drift detection scheduled
- [ ] Weekly compliance scheduled
- [ ] Quarterly evidence scheduled
