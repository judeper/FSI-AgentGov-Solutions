# Prerequisites

Complete prerequisites for deploying the Compliance Dashboard solution.

---

## Licensing Requirements

### Required Licenses

| License | Quantity | Purpose |
|---------|----------|---------|
| **Power BI Pro** | Per dashboard viewer | View and interact with dashboard |
| **Power BI Premium** | 1 capacity (alternative) | Unlimited viewers, larger datasets |
| **Power Platform Premium** | Per flow creator | Power Automate data collection flows |
| **Dataverse capacity** | 1 GB minimum | Compliance data storage |
| **Microsoft 365 E5** or **E5 Compliance** | 1 minimum | Purview Compliance Manager portal export and evidence review |

### Optional Licenses

| License | Purpose |
|---------|---------|
| **Power BI Premium Per User** | Individual premium features without capacity |
| **Dataverse for Teams** | Limited storage if using Teams-based environments |

---

## Permission Requirements

### Service Admin Roles

| Role | Required For | Minimum Scope |
|------|--------------|---------------|
| **Purview Compliance Admin** | Compliance Manager assessment export and evidence review in the Purview portal | Tenant |
| **Power Platform Admin** | Environment and DLP data access | Tenant |
| **Global Reader** | Read-only access to configuration | Tenant |
| **Exchange Online Admin** | Required for the Exchange data collector script (`Get-ExchangeComplianceData.ps1`) when running interactively | Tenant |

### Power Platform Roles

| Role | Required For | Scope |
|------|--------------|-------|
| **System Administrator** | Dataverse table creation | Environment |
| **Environment Maker** | Flow creation | Environment |
| **Application User** | Service principal access to Dataverse Web API (must be created in Power Platform admin center for the app registration below) | Environment |

### Power BI Roles

| Role | Required For |
|------|--------------|
| **Workspace Admin** | Dashboard deployment |
| **Capacity Admin** | Premium capacity assignment (if applicable) |

---

## Service Principal Setup

The data collection flows and scripts use managed identity or workload identity federation first. Use service principal client secrets only for legacy local development, and prefer certificate-based app authentication for Exchange Online Security & Compliance PowerShell automation.

### Required Permissions

```json
{
  "servicePrincipalPermissions": {
    "microsoftGraph": [
      "Reports.Read.All",
      "Directory.Read.All",
      "AuditLog.Read.All",
      "User.Read.All",
      "Group.Read.All",
      "MailboxSettings.Read",
      "Mail.Read",
      "SecurityAlert.Read.All"
    ],
    "powerPlatform": [
      "Environment.Read.All",
      "DLP.Read.All"
    ],
    "dynamics365": [
      "user_impersonation"
    ]
  }
}
```

> **Note:** `User.Read.All`, `MailboxSettings.Read`, `Mail.Read`, `Group.Read.All`, and `SecurityAlert.Read.All` are required by `Get-ExchangeComplianceData.ps1` for license, mailbox-purpose, inactive-mailbox, distribution group, and audit-event signal collection. Grant admin consent after adding.

### Registration Steps

1. Navigate to **Microsoft Entra ID** > **App registrations**
2. Click **New registration**
3. Name: `FSI-AgentGov-ComplianceDashboard`
4. Supported account types: **Single tenant**
5. Click **Register**

### API Permission Configuration

1. Go to **API permissions** > **Add a permission**
2. Add Microsoft Graph permissions:
   - `Reports.Read.All` (Application) — Microsoft 365 usage reports, including Copilot usage reports where available
   - `Directory.Read.All` (Application)
   - `AuditLog.Read.All` (Application)
   - `User.Read.All` (Application) — license + UPN enumeration
   - `Group.Read.All` (Application) — distribution group counts
   - `MailboxSettings.Read` (Application) — `mailboxSettings/userPurpose`
   - `Mail.Read` (Application) — inactive mailbox classification
   - `SecurityAlert.Read.All` (Application) — Exchange-related security signals
3. Click **Grant admin consent**

### Dataverse Application User

After registering the app, grant it Dataverse access:

1. Navigate to **Power Platform admin center** > target environment > **Settings** > **Users + permissions** > **Application users**
2. Click **+ New app user** and select the app registration above
3. Assign the **System Customizer** role (for table reads/writes performed by the dashboard flows) and **Basic User** for OData access

### Authentication credentials

Use the strongest available credential for the runtime:

1. **Managed identity** for Azure-hosted jobs (system-assigned by default; set `AZURE_CLIENT_ID` for user-assigned managed identity).
2. **Workload identity federation** for GitHub Actions or other CI jobs.
3. **Certificate-based app authentication** for Exchange Online Security & Compliance PowerShell (`Connect-IPPSSession -AppId ... -CertificateThumbprint ... -Organization ...`).
4. **Interactive/device-code sign-in** for one-off administrator workstation runs.
5. **Client secret** only as a legacy dev-only fallback. If used, store it in Azure Key Vault, rotate it frequently, and remove it from production automation.

---

## Environment Requirements

### Dataverse Environment

| Requirement | Specification |
|-------------|---------------|
| **Type** | Production or Sandbox |
| **Region** | Same as Power BI tenant |
| **Security Group** | Configured for dashboard users |
| **Capacity** | Minimum 1 GB available |

### Power BI Workspace

| Requirement | Specification |
|-------------|---------------|
| **Type** | Pro or Premium workspace |
| **License Mode** | Pro (per-user) or Premium (capacity) |
| **Region** | Same as Dataverse environment |

---

## Network Requirements

### Firewall Allowlist

Ensure the following endpoints are accessible:

| Endpoint | Purpose |
|----------|---------|
| `*.compliance.microsoft.com` | Purview Compliance Manager |
| `*.api.powerplatform.com` | Power Platform Admin API |
| `*.crm.dynamics.com` | Dataverse |
| `*.powerbi.com` | Power BI Service |
| `graph.microsoft.com` | Microsoft Graph API |

### Conditional Access

If Conditional Access policies restrict API access:

1. Create exclusion for the service principal
2. Or configure compliant device requirement for automation accounts

---

## Dependency Solutions

### Required

| Solution | Minimum Version | Purpose |
|----------|-----------------|---------|
| Environment Lifecycle Management | v1.1.3 | Zone classification data |

### Optional

| Solution | Version | Purpose |
|----------|---------|---------|
| FINRA Supervision Workflow | v1.1.0 | Supervision queue metrics |
| Deny Event Correlation Report | v2.0.1 | DLP violation data |

---

## Validation Checklist

Before proceeding with deployment, verify:

- [ ] Power BI Pro/Premium licenses assigned to dashboard users
- [ ] Power Platform Premium license for flow creator
- [ ] Dataverse environment created with sufficient capacity
- [ ] Service principal registered with required permissions
- [ ] Admin consent granted for API permissions
- [ ] Managed identity, workload identity, or certificate credential configured; any client secret is documented as legacy dev-only and stored in Azure Key Vault
- [ ] Network endpoints accessible
- [ ] Environment Lifecycle Management solution deployed (if using zone data)

---

## Next Steps

Once prerequisites are met:

1. [Deploy Dataverse Schema](dataverse-schema.md)
2. [Configure Power Automate Flows](flow-configuration.md)
3. [Set Up Power BI Dashboard](power-bi-setup.md)

---

*Compliance Dashboard v1.0.4*
