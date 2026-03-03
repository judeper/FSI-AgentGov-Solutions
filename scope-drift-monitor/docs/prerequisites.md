# Prerequisites

Requirements for deploying the Scope Drift Monitor.

---

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate detection flows |
| **Dataverse capacity** | Scope and violation storage |
| **Microsoft 365 E5** or **E5 Compliance** | Unified Audit Log access |

---

## Permissions

### Microsoft Entra ID Roles

| Role | Required For |
|------|--------------|
| **Purview Compliance Admin** | Audit log queries |

### Power Platform Roles

| Role | Required For |
|------|--------------|
| **System Administrator** | Dataverse table creation |

### Office 365 Management API Permissions

| Permission | Type | Purpose |
|------------|------|---------|
| `ActivityFeed.Read` | Application | Office 365 Management API audit log access |
| `Directory.Read.All` | Application | User and app details |

> **Note:** The solution authenticates against `https://manage.office.com` (Office 365 Management API), not Microsoft Graph. Ensure the app registration has `ActivityFeed.Read` permission with admin consent.

---

## Service Principal Setup

1. Register application in Entra ID
2. Grant required API permissions
3. Create client secret
4. Store credentials securely

> **Security Note:** The `fsi_SDM_ClientSecret` environment variable uses the `Secret` type, but for production deployments it should be backed by an Azure Key Vault secret reference. Without Key Vault backing, the value is accessible to Dataverse System Administrators. See [Environment variable types](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/environmentvariables#environment-variable-types) for configuration guidance.

---

## Validation Checklist

- [ ] E5 or E5 Compliance license available
- [ ] Power Platform Premium for flow creator
- [ ] Dataverse environment ready
- [ ] Service principal configured
- [ ] Admin consent granted
- [ ] Audit logging enabled in tenant

---

*Scope Drift Monitor v1.1.0*
