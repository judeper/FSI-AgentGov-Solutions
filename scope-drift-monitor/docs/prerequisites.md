# Prerequisites

Requirements for deploying the Scope Drift Monitor.

---

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate detection flows |
| **Dataverse capacity** | Scope and violation storage |
| **Microsoft 365 E5** or **E5 Compliance** | Unified Audit Log access |
| **Defender for Cloud Apps** | CloudAppEvents for shadow access detection |

---

## Permissions

### Microsoft Entra ID Roles

| Role | Required For |
|------|--------------|
| **Purview Compliance Admin** | Audit log queries |
| **Security Reader** | Defender CloudAppEvents |

### Power Platform Roles

| Role | Required For |
|------|--------------|
| **System Administrator** | Dataverse table creation |

### Microsoft Graph API Permissions

| Permission | Type | Purpose |
|------------|------|---------|
| `AuditLog.Read.All` | Application | Unified Audit Log access |
| `Directory.Read.All` | Application | User and app details |

---

## Service Principal Setup

1. Register application in Entra ID
2. Grant required API permissions
3. Create client secret
4. Store credentials securely

---

## Validation Checklist

- [ ] E5 or E5 Compliance license available
- [ ] Power Platform Premium for flow creator
- [ ] Dataverse environment ready
- [ ] Service principal configured
- [ ] Admin consent granted
- [ ] Audit logging enabled in tenant

---

*Scope Drift Monitor v1.0.0*
