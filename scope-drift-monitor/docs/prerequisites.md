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
| **Power Platform Admin** | Configure production environment auditing and enable SAS Logging in Purview |
| **System Administrator** | Dataverse table creation and application-user role assignment |

### Office 365 Management API Permissions

| Permission | Type | Purpose |
|------------|------|---------|
| `ActivityFeed.Read` | Application | Office 365 Management API audit log access |

> **Note:** The active collector authenticates against `https://manage.office.com` (Office 365 Management API), not Microsoft Graph. Microsoft Graph `/security/auditLog/queries` is v1.0 for Purview Audit Search, but this solution uses the Office 365 Management API until a future migration is validated. Grant `ActivityFeed.Read` admin consent to the managed identity or app registration used by the scripts.


### Power Platform activity logging in Purview

For each production environment monitored by Scope Drift Monitor:

1. Configure Dataverse auditing for the environment and required tables/columns.
2. Turn on **Enable SAS Logging in Purview** in Power Platform admin center > environment settings > Privacy and Security.
3. Allow `https://*.api.powerplatformusercontent.com` in network controls before enabling SAS Logging in Purview.
4. Assign Microsoft Purview **Audit Logs** or **View-Only Audit Logs** permissions to reviewers.

Power Platform admin activity collection is enabled by default, but user activity logs for production environments require the environment-level configuration above.

### Authentication model

Use managed identity for Azure-hosted production automation:

1. Enable a system-assigned managed identity on the Azure Automation account, Function, VM, or container host running the scripts.
2. For shared automation, configure a user-assigned managed identity and set `AZURE_MANAGED_IDENTITY_CLIENT_ID`.
3. Grant the identity Office 365 Management API `ActivityFeed.Read` application permission and the required Dataverse application-user security role.
4. Use `AZURE_CLIENT_SECRET` only for local development fallback; rotate and remove it before production deployment.

---

### Microsoft Graph Permissions (only for Test-AlertDelivery email path)

| Permission | Type | Purpose |
|------------|------|---------|
| `Mail.Send` | Delegated | Required by `Test-AlertDelivery.ps1` to send email alerts via `Send-MgUserMail`. Not used by the production drift scanner. |

> **Note:** `Test-AlertDelivery.ps1` performs an interactive `Connect-MgGraph -Scopes Mail.Send` if no Graph context is present. Pre-authenticate with the same scope when running unattended. The `From` mailbox owner must be the signed-in user (delegated) or, if you adapt the script to application permissions, the app must hold `Mail.Send` (Application) scoped via an exchange ApplicationAccessPolicy.

---

## Identity Setup

1. Configure a managed identity for production script hosts, or register an application for local development fallback.
2. Grant required API permissions and admin consent.
3. Create a Dataverse application user for the identity or app and assign the least-privilege role needed to read scope records and create violations.
4. If a client secret is used for development, store it securely and remove it from production runbooks.

> **Security Note:** `fsi_SDM_ClientSecret` and `AZURE_CLIENT_SECRET` are legacy dev-only fallback paths. If a temporary secret is unavoidable, back it with Azure Key Vault, restrict access, and remove it before production. Without Key Vault backing, secret environment-variable values are accessible to Dataverse System Administrators. See [Environment variable types](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/environmentvariables#environment-variable-types) for configuration guidance.

---

## Validation Checklist

- [ ] E5 or E5 Compliance license available
- [ ] Power Platform Premium for flow creator
- [ ] Dataverse environment ready
- [ ] Managed identity configured for production script host
- [ ] Admin consent granted
- [ ] Audit logging enabled in tenant
- [ ] Dataverse auditing and Enable SAS Logging in Purview configured for each monitored production environment

---

*Scope Drift Monitor v1.2.1*
