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
| **Microsoft 365 E5** or **E5 Compliance** | 1 minimum | Purview Compliance Manager API access |

### Optional Licenses

| License | Purpose |
|---------|---------|
| **Power BI Premium Per User** | Individual premium features without capacity |
| **Dataverse for Teams** | Limited storage if using Teams-based environments |

---

## Permission Requirements

### Microsoft Entra ID Roles

| Role | Required For | Minimum Scope |
|------|--------------|---------------|
| **Compliance Administrator** | Purview Compliance Manager API | Tenant |
| **Power Platform Administrator** | Environment and DLP data access | Tenant |
| **Global Reader** | Read-only access to configuration | Tenant |

### Power Platform Roles

| Role | Required For | Scope |
|------|--------------|-------|
| **System Administrator** | Dataverse table creation | Environment |
| **Environment Maker** | Flow creation | Environment |

### Power BI Roles

| Role | Required For |
|------|--------------|
| **Workspace Admin** | Dashboard deployment |
| **Capacity Admin** | Premium capacity assignment (if applicable) |

---

## Service Principal Setup

The data collection flows use a service principal for API access.

### Required Permissions

```json
{
  "servicePrincipalPermissions": {
    "microsoftGraph": [
      "ComplianceManager.Read.All",
      "Directory.Read.All",
      "AuditLog.Read.All"
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

### Registration Steps

1. Navigate to **Microsoft Entra ID** > **App registrations**
2. Click **New registration**
3. Name: `FSI-AgentGov-ComplianceDashboard`
4. Supported account types: **Single tenant**
5. Click **Register**

### API Permission Configuration

1. Go to **API permissions** > **Add a permission**
2. Add Microsoft Graph permissions:
   - `ComplianceManager.Read.All` (Application)
   - `Directory.Read.All` (Application)
   - `AuditLog.Read.All` (Application)
3. Click **Grant admin consent**

### Client Secret

1. Go to **Certificates & secrets**
2. Click **New client secret**
3. Description: `ComplianceDashboard-Secret`
4. Expiration: 24 months (maximum)
5. Store securely in Azure Key Vault

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
| Environment Lifecycle Management | v1.1.0 | Zone classification data |

### Optional

| Solution | Version | Purpose |
|----------|---------|---------|
| FINRA Supervision Workflow | v1.0.0 | Supervision queue metrics |
| Deny Event Correlation Report | v1.1.0 | DLP violation data |

---

## Validation Checklist

Before proceeding with deployment, verify:

- [ ] Power BI Pro/Premium licenses assigned to dashboard users
- [ ] Power Platform Premium license for flow creator
- [ ] Dataverse environment created with sufficient capacity
- [ ] Service principal registered with required permissions
- [ ] Admin consent granted for API permissions
- [ ] Client secret stored in Azure Key Vault
- [ ] Network endpoints accessible
- [ ] Environment Lifecycle Management solution deployed (if using zone data)

---

## Next Steps

Once prerequisites are met:

1. [Deploy Dataverse Schema](dataverse-schema.md)
2. [Configure Power Automate Flows](flow-configuration.md)
3. [Set Up Power BI Dashboard](power-bi-setup.md)

---

*Compliance Dashboard v1.0.0*
