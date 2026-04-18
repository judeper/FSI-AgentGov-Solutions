# Deployment Guide — Audit Logging Compliance Automation (ALCA)

This guide covers end-to-end deployment of the ALCA solution in Azure Automation with System-Assigned Managed Identity.

## Overview

| Phase | What | Time Estimate |
|-------|------|---------------|
| 1 | Azure Automation Account setup | 15 min |
| 2 | Managed Identity permissions | 30 min |
| 3 | Shared mailbox setup | 15 min |
| 4 | Module import | 15 min |
| 5 | Runbook creation and publishing | 15 min |

**Total:** ~90 minutes for a complete deployment.

---

## Phase 1: Azure Automation Account Setup

### 1.1 Create the Automation Account

1. Navigate to **Azure Portal** → **Automation Accounts** → **+ Create**
2. Configure:
   - **Name:** `FSI-AgentGov-Automation`
   - **Resource group:** Use your governance resource group
   - **Region:** Same region as your Power Platform tenant (reduces latency)
   - **Identity:** System assigned = **On**
3. Click **Review + Create** → **Create**

### 1.2 Configure Runtime Environment

1. Navigate to your Automation Account → **Runtime Environments**
2. Verify the default **PowerShell 7.2** runtime is available
3. If not present, create a new runtime:
   - **Name:** `PowerShell-7.2`
   - **Language:** PowerShell
   - **Version:** 7.2
   - **Description:** ALCA runbook runtime

### 1.3 Enable System-Assigned Managed Identity

1. Navigate to **Automation Account** → **Identity** → **System assigned** tab
2. Set Status to **On** (if not already enabled during creation)
3. Click **Save**
4. Record the **Object (principal) ID** — you need this for permission assignments

> **Important:** The Managed Identity must be a System-Assigned MI. User-Assigned MIs are not supported by the ALCA helper module.

---

## Phase 2: Managed Identity Permissions

The Managed Identity requires permissions across four services.

### 2.1 Entra ID Role Assignments

Assign these Entra ID roles to the Managed Identity:

| Role | Purpose | How to Assign |
|------|---------|---------------|
| **Power Platform Administrator** | Environment enumeration, audit config access | Entra ID → Roles and administrators |
| **Exchange Administrator** | Exchange Online Managed Identity auth, Search-UnifiedAuditLog | Entra ID → Roles and administrators |

> **Least-Privilege Consideration:** The roles above are tenant-wide administrative roles,
> which is broader than needed for audit compliance scanning (read-only operations).
> For production deployments, consider these alternatives:
>
> - **Purview Compliance Admin** (Entra display name 'Compliance Administrator') instead of Exchange Online Admin — provides read access
>   to audit logs and compliance data without full Exchange administration rights.
> - **Power Platform Administrator** can be scoped using Entra ID Administrative Units
>   if your organization has segmented governance.
> - For environments that only need detection (not remediation), the Managed Identity
>   does not require System Administrator in target Dataverse environments —
>   **Compliance Reader** or a custom security role with read access to organization
>   settings is sufficient.
>
> Evaluate your organization's security requirements and apply the narrowest role
> assignments that satisfy the solution's operational needs.

**Steps:**

1. Navigate to **Microsoft Entra ID** → **Roles and administrators**
2. Search for **Power Platform Administrator**
3. Click **+ Add assignments** → **Select members**
4. Search for the Automation Account's system-assigned managed identity by its display name (the Automation Account name) or by its Object (principal) ID from the Azure portal
5. Click **Select** → **Next** → **Assign**
6. Repeat for **Exchange Administrator**

### 2.2 Microsoft Graph API Permission (Mail.Send)

Required for email notifications via shared mailbox.

1. Navigate to **Microsoft Entra ID** → **App registrations** → Search for the MI by Object ID
   - Note: System-Assigned MIs appear as Enterprise Applications, not App Registrations
2. Use PowerShell to assign the Graph permission:

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.Read.All","AppRoleAssignment.ReadWrite.All"

# Get the Managed Identity service principal
$miObjectId = "<your-MI-object-id>"
$mi = Get-MgServicePrincipal -ServicePrincipalId $miObjectId

# Get the Microsoft Graph service principal
$graph = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Find the Mail.Send app role
$mailSendRole = $graph.AppRoles | Where-Object { $_.Value -eq "Mail.Send" }

# Assign the role
New-MgServicePrincipalAppRoleAssignment `
    -ServicePrincipalId $mi.Id `
    -PrincipalId $mi.Id `
    -ResourceId $graph.Id `
    -AppRoleId $mailSendRole.Id
```

3. **Admin consent:** Navigate to **Enterprise Applications** → Find `FSI-AgentGov-Automation` → **Permissions** → **Grant admin consent**

### 2.3 Dataverse Application User

The Managed Identity needs access to each target Dataverse environment.

**For each Power Platform environment with Dataverse:**

1. Navigate to **Power Platform Admin Center** → **Environments** → Select environment → **Settings** → **Users + permissions** → **Application users**
2. Click **+ New app user**
3. **Add an app:** Search for `FSI-AgentGov-Automation` using the MI Application ID
4. **Business unit:** Select the root business unit
5. **Security roles:** Assign **System Administrator**
   - Required for: reading organization settings, modifying audit configuration, updating entity definitions
6. Click **Create**

> **Repeat** for every Dataverse environment you want ALCA to scan and remediate.

### 2.4 Permission Verification

Run this quick check to verify permissions:

```powershell
# In Azure Automation → Test Pane
# Test MI token acquisition for each resource

# Power Platform
$ppToken = Get-ManagedIdentityToken -Resource "https://api.bap.microsoft.com/"
Write-Output "Power Platform token: $($ppToken.Substring(0,20))..."

# Dataverse
$dvToken = Get-DataverseToken -DataverseEnvironmentUrl "https://your-org.crm.dynamics.com"
Write-Output "Dataverse token: $($dvToken.Substring(0,20))..."

# Graph
$graphToken = Get-ManagedIdentityToken -Resource "https://graph.microsoft.com"
Write-Output "Graph token: $($graphToken.Substring(0,20))..."
```

---

## Phase 3: Shared Mailbox Setup

Required only if you plan to use email notifications (`-SendEmail` parameter).

### 3.1 Create the Shared Mailbox

1. Navigate to **Exchange Admin Center** → **Recipients** → **Mailboxes** → **+ Add a shared mailbox**
2. Configure:
   - **Display name:** Power Platform Governance
   - **Email address:** `powerplatform-governance@yourdomain.com`
3. Click **Create**

### 3.2 Grant SendAs Permission

The Managed Identity needs SendAs permission on the shared mailbox:

```powershell
# Connect to Exchange Online
Connect-ExchangeOnline

# Grant SendAs to the Managed Identity
Add-RecipientPermission `
    -Identity "powerplatform-governance@yourdomain.com" `
    -Trustee "<MI-Object-ID>" `
    -AccessRights SendAs `
    -Confirm:$false
```

### 3.3 Verify Email Configuration

Test that the MI can send via the shared mailbox:

```powershell
# In Azure Automation → Test Pane
Send-ComplianceNotification `
    -FromAddress "powerplatform-governance@yourdomain.com" `
    -ToAddresses @("your-email@yourdomain.com") `
    -Subject "ALCA Test Email" `
    -HtmlBody "<p>If you received this, email is configured correctly.</p>"
```

---

## Phase 4: Module Import

### 4.1 Import AuditComplianceHelpers Module

1. Package the module as a ZIP:
   - Include `AuditComplianceHelpers.psm1` and `AuditComplianceHelpers.psd1`
   - ZIP file name: `AuditComplianceHelpers.zip`

2. Navigate to **Automation Account** → **Modules** → **+ Add a module**
3. Configure:
   - **Upload module file:** Select `AuditComplianceHelpers.zip`
   - **Runtime version:** 7.2
4. Click **Import**
5. Wait for status to show **Available**

### 4.2 Import Gallery Modules

Import these modules from the PowerShell Gallery:

| Module | Minimum Version | Purpose |
|--------|----------------|---------|
| `Microsoft.PowerApps.Administration.PowerShell` | 2.0.180 | Environment enumeration, admin config |
| `ExchangeOnlineManagement` | 3.0.0 | Exchange Online MI auth, audit log search |

**For each module:**

1. Navigate to **Automation Account** → **Modules** → **+ Add a module**
2. Select **Browse from gallery**
3. Search for the module name
4. Select the module → **Select**
5. **Runtime version:** 7.2
6. Click **Import**

### 4.3 Verify Module Status

1. Navigate to **Automation Account** → **Modules**
2. Filter by **Runtime version: 7.2**
3. Confirm all three modules show **Status: Available**:
   - ✅ `AuditComplianceHelpers` — Available
   - ✅ `Microsoft.PowerApps.Administration.PowerShell` — Available
   - ✅ `ExchangeOnlineManagement` — Available

> **Tip:** Module import can take 5–10 minutes. Refresh the page to check status.

---

## Phase 5: Runbook Creation

### 5.0 Pre-requisite: ALCA Dataverse Schema

Before creating runbooks, deploy the ALCA `fsi_auditenvironmentcompliance` table that the detection and remediation runbooks read/write. From a workstation that can reach the target Dataverse environment:

```bash
python scripts/create_audit_compliance_schema.py \
    --environment-url https://<your-org>.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --client-id <your-app-client-id> \
    --interactive
```

This creates the `fsi_auditenvironmentcompliance` table, columns, and the `fsi_compliancestatus` choice column (Compliant / Non-Compliant / Unknown / Error). The ACV tables (`fsi_auditvalidationhistory`, `fsi_environmentregistry`) are created separately by `scripts/deploy.py` (see [README Step 1](../README.md)).

### 5.0.1 Pre-requisite: Helper scripts uploaded with the runbook

The detection and remediation runbooks `dot-source` files in `scripts/private/` (`Connect-AuditServices.ps1`, `New-CanaryEvent.ps1`, `Connect-PowerPlatform.ps1`, `Compare-ValidationBaseline.ps1`, `Get-ValidationResults.ps1`, `Write-ValidationResult.ps1`). Azure Automation runbooks do not have a working directory that reaches your local filesystem. Two supported options:

1. **Convert the `private/` helpers into a single PowerShell module** (`AuditComplianceHelpersInternal.psm1`) and import it alongside `AuditComplianceHelpers` in step 4.1, then `Import-Module` it from the runbook instead of dot-sourcing.
2. **Inline the contents of the required helpers** at the top of each runbook (acceptable for short helpers; reduces maintainability).

If you skip this step, runbooks fail with `The term 'New-CanaryEvent' is not recognized as a name of a cmdlet, function, ...` or similar.

### 5.1 Create Detection Runbook

1. Navigate to **Automation Account** → **Runbooks** → **+ Create a runbook**
2. Configure:
   - **Name:** `Test-AuditLoggingCompliance`
   - **Runbook type:** PowerShell
   - **Runtime version:** 7.2
   - **Description:** Scans all Power Platform environments for Purview unified audit and Dataverse audit compliance
3. Click **Create**
4. In the editor, paste the contents of `scripts/Test-AuditLoggingCompliance.ps1`
5. Click **Save** → **Publish**

### 5.2 Create Remediation Runbook

1. Navigate to **Automation Account** → **Runbooks** → **+ Create a runbook**
2. Configure:
   - **Name:** `Enable-AuditLogging`
   - **Runbook type:** PowerShell
   - **Runtime version:** 7.2
   - **Description:** Enables org-level and entity-level Dataverse auditing on non-compliant environments
3. Click **Create**
4. In the editor, paste the contents of `scripts/Enable-AuditLogging.ps1`
5. Click **Save** → **Publish**

### 5.3 Verify Runbook Status

Both runbooks should show:
- **Status:** Published
- **Runtime version:** 7.2
- **Type:** PowerShell

---

## Post-Deployment Verification

After completing all 5 phases, run the detection runbook in Test mode:

1. Navigate to **Test-AuditLoggingCompliance** runbook → **Test pane**
2. Enter parameters:
   - **DataverseEnvironmentUrl:** `https://your-org.crm.dynamics.com`
   - **TenantDomain:** `yourdomain.onmicrosoft.com`
   - **SendEmail:** unchecked (first run without email)
3. Click **Start**
4. Verify:
   - ✅ Authentication succeeds for all three services
   - ✅ Environments are enumerated
   - ✅ Compliance records are written to Dataverse
   - ✅ CSV is exported to TEMP directory
   - ✅ Compliance summary shows correct counts

See [Testing Scenarios](./testing-scenarios.md) for comprehensive test procedures.

---

*Updated: April 2026 | Version: v1.0.2*
