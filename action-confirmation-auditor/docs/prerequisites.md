# Prerequisites

Requirements for deploying the Action Confirmation Auditor.

---

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows (ACA-Scanner, ACA-Exception-Approval) |
| **Dataverse capacity** | Scan run, audit result, and exception storage |
| **Microsoft 365 E5** or **E5 Compliance** | Tenant-wide agent and action visibility |
| **Azure Automation** | Scheduled runbook execution for compliance scans |

---

## Permissions

### Microsoft Entra ID Roles

| Role | Required For |
|------|--------------|
| **Power Platform Admin** | Cross-environment agent and action enumeration |
| **Application Administrator** (or equivalent) | App registration for service principal |

### Power Platform Roles

| Role | Required For |
|------|--------------|
| **System Administrator** | Dataverse table creation and schema deployment |
| **System Customizer** | Environment variable and connection reference creation |

### Dataverse Permissions

| Permission | Table | Purpose |
|------------|-------|---------|
| Read | `bot` | Enumerate Copilot Studio agents |
| Read | `botcomponent` | Inspect agent topic definitions and action nodes |
| Create/Read/Write | `fsi_ActionAuditResult` | Store violation records |
| Create/Read/Write | `fsi_ActionConfirmationException` | Manage exceptions |
| Create/Read/Write | `fsi_ActionScanRun` | Store scan run history |

---

## Azure AD App Registration

1. **Register Application**
   - Navigate to Entra ID > App registrations > New registration
   - Name: `ACA-ActionConfirmationAuditor`
   - Supported account types: Single tenant
   - Redirect URI: Not required (daemon/service)

2. **API Permissions**
   - Microsoft Graph: `Application.Read.All` (Application)
   - Dynamics CRM: `user_impersonation` (Delegated) or configure S2S
   - Admin consent: Required

3. **Client Secret**
   - Create client secret with appropriate expiration
   - Store securely in Azure Key Vault or Azure Automation credentials

4. **Record Values**
   - Application (client) ID > `fsi_ACA_ClientId`
   - Directory (tenant) ID > `fsi_ACA_TenantId`
   - Client secret > Store in Azure Automation credential asset

---

## Azure Automation Setup

1. **Create or Use Existing Automation Account**
   - Resource group: Governance or shared services
   - Location: Same region as Power Platform environment

2. **Import Runbook**
   - Import `Start-ActionConfirmationValidationRunbook.ps1` as PowerShell 7.2 runbook
   - Publish the runbook

3. **Configure Credentials**
   - Create credential asset with app registration client ID and secret
   - Or configure System-Assigned Managed Identity with required permissions

4. **Install Required Modules**
   - `Az.Accounts` (for authentication)
   - `MSAL.PS` (if using client credential flow)

---

## Dataverse Schema

The ACA solution uses 3 Dataverse tables:

| Table | Logical Name | Purpose |
|-------|-------------|---------|
| Action Audit Result | `fsi_ActionAuditResult` | Individual violation records per action |
| Action Confirmation Exception | `fsi_ActionConfirmationException` | Approved exception records |
| Action Scan Run | `fsi_ActionScanRun` | Scan execution history and summary |

Deploy using:

```bash
python scripts/create_dataverse_schema.py \
  --dataverse-url https://yourorg.crm.dynamics.com \
  --client-id <app-id> \
  --client-secret <secret> \
  --tenant-id <tenant-id>
```

See [dataverse-schema.md](dataverse-schema.md) for the auto-generated column reference.

---

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `*.crm.dynamics.com` | HTTPS 443 | Dataverse Web API |
| `login.microsoftonline.com` | HTTPS 443 | Azure AD authentication |
| `management.azure.com` | HTTPS 443 | Azure Automation API |
| `api.powerplatform.com` | HTTPS 443 | Power Platform Admin API |

---

## Environment Lifecycle Management (ELM) Integration

ACA uses zone classification from the Environment Lifecycle Management (ELM) solution to determine confirmation requirements per environment. Zone classification is resolved using the shared module:

- **Shared module:** `scripts/shared/Get-ZoneClassification.ps1` (repository root)
- **Local wrapper:** `scripts/governance/Get-ZoneClassification.ps1`

If ELM is not deployed, zone classification defaults to Zone 3 (most restrictive) for all environments.

---

## Validation Checklist

- [ ] E5 or E5 Compliance license available
- [ ] Power Platform Premium for flow creator
- [ ] Dataverse environment ready with sufficient capacity
- [ ] Azure AD app registration created (`ACA-ActionConfirmationAuditor`)
- [ ] Admin consent granted for API permissions
- [ ] Azure Automation account configured with runbook imported
- [ ] Service principal has Dataverse read access to `bot` and `botcomponent` tables
- [ ] Network connectivity to required endpoints verified
- [ ] Zone classification source configured (ELM or default Zone 3)

---

*Action Confirmation Auditor v1.0.0*
