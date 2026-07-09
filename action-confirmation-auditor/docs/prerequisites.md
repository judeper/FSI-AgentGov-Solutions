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

## Microsoft Entra ID App Registration

1. **Register Application**
   - Navigate to Entra ID > App registrations > New registration
   - Name: `ACA-ActionConfirmationAuditor`
   - Supported account types: Single tenant
   - Redirect URI: Not required (daemon/service)

2. **API Permissions**
   - Microsoft Graph: `Application.Read.All` (Application)
   - Dynamics CRM: `user_impersonation` (Delegated) or configure S2S
   - Admin consent: Required

3. **Certificate Authentication**
   - Create or upload a certificate for the app registration
   - Record the certificate thumbprint for Azure Automation configuration
   - Certificate-based auth is required for the validation runbook

4. **Record Values**
   - Application (client) ID > Pass as `-ClientId` runbook parameter
   - Directory (tenant) ID > Pass as `-TenantId` runbook parameter
   - Certificate thumbprint > Pass as `-CertificateThumbprint` runbook parameter

---

## Azure Automation Setup

1. **Create or Use Existing Automation Account**
   - Resource group: Governance or shared services
   - Location: Same region as Power Platform environment

2. **Import Runbook**
   - Import `Start-ActionConfirmationValidationRunbook.ps1` as a Windows PowerShell 5.1 runbook. Microsoft Learn documents `Microsoft.PowerApps.Administration.PowerShell` as a .NET Framework module that is incompatible with PowerShell 6.0 and later.
   - Publish the runbook

3. **Configure Authentication**
   - Upload certificate to Azure Automation certificate store
   - The runbook uses certificate-based auth via `-ClientId` and `-CertificateThumbprint` parameters

4. **Install Required Modules**
   - `Microsoft.PowerApps.Administration.PowerShell` in Windows PowerShell 5.1
   - `MSAL.PS` for certificate-based token acquisition
   - `Az.Accounts` only if using interactive workstation authentication helpers

---

## Dataverse Schema

The ACA solution uses 3 Dataverse tables:

| Table | Logical Name | Purpose |
|-------|-------------|---------|
| Action Audit Result | `fsi_actionauditresult` | Individual violation records per action |
| Action Confirmation Exception | `fsi_actionconfirmationexception` | Approved exception records |
| Action Scan Run | `fsi_actionscanrun` | Scan execution history and summary |

Deploy using:

```bash
python scripts/create_dataverse_schema.py \
  --environment-url https://yourorg.crm.dynamics.com \
  --tenant-id <tenant-id> \
  --interactive
```

See [dataverse-schema.md](dataverse-schema.md) for the auto-generated column reference.

---

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `*.crm.dynamics.com` | HTTPS 443 | Dataverse Web API |
| `login.microsoftonline.com` | HTTPS 443 | Microsoft Entra ID authentication |
| `management.azure.com` | HTTPS 443 | Azure Automation API |
| `api.bap.microsoft.com` | HTTPS 443 | Power Platform Admin API |

---

## Environment Lifecycle Management (ELM) Integration

ACA uses zone classification from the Environment Lifecycle Management (ELM) solution to determine confirmation requirements per environment. Zone classification is resolved using the shared module:

- **Shared module:** `scripts/shared/Get-ZoneClassification.ps1` (repository root)
- **Local wrapper:** `scripts/private/Get-ZoneClassification.ps1`

If ELM is not deployed and the environment name matches no zone naming convention, zone classification resolves to `Unknown`. Under canonical zone semantics the most-restrictive tier is **Zone 1 (Enterprise)**; classify environments explicitly (ELM or naming convention) so the correct confirmation policy is applied.

---

## Optional: Purview AI Hub / DSPM Integration

`scripts/Get-PurviewAIHubEvidence.ps1` cross-references ACA confirmation results
with Microsoft Purview AI Hub (DSPM for AI) activity. It is optional and has
additional dependencies beyond the core scan:

| Requirement | Purpose |
|-------------|---------|
| `Microsoft.Graph.Authentication` module | Connect to Microsoft Graph (`Connect-MgGraph`) |
| Graph scope `AuditLogsQuery.Read.All` | Required by the Graph audit log query API (`security/auditLog/queries`) |
| Dataverse access token (Power Platform Premium not required) | Query `fsi_actionauditresults`; supplied via `-DataverseAccessToken` (SecureString) or acquired automatically via `Az.Accounts` `Get-AzAccessToken` |
| DSPM for AI enabled and Copilot audit logging active | So AI Hub activities exist to correlate |

The Microsoft Graph session token cannot be reused for Dataverse because the two
services require tokens scoped to different audiences. Example:

```powershell
Connect-MgGraph -Scopes 'AuditLogsQuery.Read.All'
Connect-AzAccount   # or rely on managed identity in Azure Automation
. ./scripts/Get-PurviewAIHubEvidence.ps1
Get-PurviewAIHubEvidence -DataverseUrl 'https://yourorg.crm.dynamics.com' -LookbackDays 7
```

---

## Validation Checklist

- [ ] E5 or E5 Compliance license available
- [ ] Power Platform Premium for flow creator
- [ ] Dataverse environment ready with sufficient capacity
- [ ] Microsoft Entra ID app registration created (`ACA-ActionConfirmationAuditor`)
- [ ] Admin consent granted for API permissions
- [ ] Azure Automation account configured with runbook imported
- [ ] Service principal has Dataverse read access to `bot` and `botcomponent` tables
- [ ] Network connectivity to required endpoints verified
- [ ] Zone classification source configured (ELM or naming convention; unresolved resolves to `Unknown`)

---

*Action Confirmation Auditor v1.2.1 — Last Verified: 2026-05-25*
