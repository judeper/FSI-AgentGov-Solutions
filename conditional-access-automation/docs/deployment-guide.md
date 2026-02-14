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

Run the prerequisites verification script:

```powershell
.\scripts\Test-Prerequisites.ps1 -TenantId "<tenant-id>"
```

Expected output:
```
Checking prerequisites...
✓ PowerShell 7.4 detected
✓ Microsoft.Graph module installed (v2.15.0)
✓ Az.KeyVault module installed (v5.2.0)
✓ Entra ID P2 license active
✓ Conditional Access Administrator role assigned
✓ Break-glass accounts found (2)
✓ All prerequisites met
```

If any checks fail, resolve before proceeding.

---

## Step 2: Service Principal Setup

### 2.1 Create App Registration

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
$clientId = (Get-AzKeyVaultSecret -VaultName "<vault-name>" -Name "CAA-SP-ClientId").SecretValueText
$clientSecret = (Get-AzKeyVaultSecret -VaultName "<vault-name>" -Name "CAA-SP-ClientSecret").SecretValueText

$secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($clientId, $secureSecret)

Connect-MgGraph -TenantId "<tenant-id>" -ClientSecretCredential $credential

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
    "m365Copilot": "fb8d773d-7ef8-4ec0-a117-179f88add510"
  },
  "policyPrefix": "CA-FSI"
}
```

### 3.3 Validate Configuration

```powershell
.\scripts\Test-Configuration.ps1 -ConfigPath "./config/tenant-config.json"
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

Total policies: 8
State: Report-only (enabledForReportingButNotEnforced)
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

### 5.4 Validate Coverage

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
# Export baseline
.\scripts\Export-PolicyBaseline.ps1 `
    -TenantId "<tenant-id>" `
    -OutputPath "./baseline"

# Schedule drift detection (run daily)
.\scripts\Watch-PolicyDrift.ps1 `
    -TenantId "<tenant-id>" `
    -BaselinePath "./baseline" `
    -AlertWebhook "<teams-webhook-url>"
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
.\scripts\Export-PolicyEvidence.ps1 `
    -TenantId "<tenant-id>" `
    -OutputPath "./evidence" `
    -StartDate "2026-01-01" `
    -EndDate "2026-03-31"
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
