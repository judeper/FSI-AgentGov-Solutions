# Prerequisites

Requirements for deploying the Action Confirmation Auditor. Core configuration
scanning and optional Purview activity correlation have different prerequisites.

---

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Automate premium connector entitlement** | ACA-Scanner and ACA-Exception-Approval use Dataverse and Azure Automation premium connectors. License through Power Automate Premium for the relevant owner, or a Power Automate Process license allocated to the flow, as applicable |
| **Dataverse capacity** | Scan run, audit result, and exception storage |
| **Copilot Studio entitlement for agent authors** | Authoring and operating the agents being inspected; this is separate from the scanner's Dataverse access |
| **Azure Automation** | Scheduled runbook execution for compliance scans |

Microsoft 365 E5 or an E5 Compliance add-on is not a blanket prerequisite for
reading `bot` and `botcomponent` configuration through Dataverse. Check Purview
feature entitlements separately if enabling the optional integration below.
Script-only scans do not execute the Power Automate flows.

Sources: [Power Automate licensing](https://learn.microsoft.com/power-platform/admin/power-automate-licensing/types),
[Dataverse S2S](https://learn.microsoft.com/power-apps/developer/data-platform/build-web-applications-server-server-s2s-authentication),
and [Copilot Studio licensing](https://learn.microsoft.com/microsoft-copilot-studio/requirements-licensing).

---

## Permissions

### Microsoft Entra ID Roles

| Role | Required For |
|------|--------------|
| **Power Platform Admin** | Tenant administration and management-application registration for unattended Power Platform enumeration |
| **Application Developer** or an authorized application administrator | App registration when tenant policy does not permit ordinary users to register applications |

### Power Platform Roles

| Role | Required For |
|------|--------------|
| **System Administrator** | Dataverse table creation and schema deployment |
| **System Customizer** | Environment variable and connection reference creation |

Entra administrative roles do not replace Dataverse security roles. Assign
Dataverse access explicitly in **each scanned environment** and in the central
evidence environment. For unattended access, create a Dataverse application user
for the service principal in each environment and assign an appropriate security
role. System Administrator is a broad setup role, not the minimum scan role.

### Dataverse Permissions

| Permission | Table | Purpose |
|------------|-------|---------|
| Read | `bot` | Enumerate Copilot Studio agents |
| Read | `botcomponent` | Inspect agent topic definitions and action nodes |
| Create/Read/Write | `fsi_actionauditresult` | Store violation records |
| Create/Read/Write | `fsi_actionconfirmationexception` | Manage exceptions |
| Create/Read/Write | `fsi_actionscanrun` | Store scan run history |

These rows describe operations across the deployment, scanner, and approval
workflow; assign privileges to the identity that performs each operation rather
than granting every identity every privilege. The scanner also reads environment
variable definitions/values and approved exceptions. Preserve the scan-run
write/delete restrictions described by the deployment script.

Sources: [Dataverse security roles](https://learn.microsoft.com/power-platform/admin/database-security)
and [application users](https://learn.microsoft.com/power-platform/admin/manage-application-users).

---

## Microsoft Entra ID App Registration

1. **Register Application**
   - In the Microsoft Entra admin center, navigate to **Entra ID > App registrations > New registration**
   - Name: `ACA-ActionConfirmationAuditor`
   - Supported account types: Single tenant
   - Redirect URI: Not required (daemon/service)

2. **Separate Power Platform and Dataverse Authorization**
   - For unattended Power Platform administration, register the service principal as a **Power Platform management application**. An authorized administrator performs this registration; granting Microsoft Graph `Application.Read.All` does not authorize environment enumeration.
   - For Dataverse server-to-server (S2S) access, create the per-environment application users and assign Dataverse security roles as described above. Delegated Dynamics CRM `user_impersonation` is for a signed-in user; it is not the authorization model for a certificate-authenticated daemon.
   - The core scanner does not call Microsoft Graph and does not require `Application.Read.All`. Configure and consent to Graph permissions only for an integration that actually uses Graph, such as the optional Purview helper below.

3. **Certificate Authentication**
   - Upload the public certificate to the app registration; make the matching private-key certificate available to the runbook identity
   - Record the certificate thumbprint for Azure Automation configuration
   - The shipped `Start-ActionConfirmationValidationRunbook.ps1` uses certificate authentication through `Az.Accounts`. Managed identity is preferred for Azure-hosted automation where supported; the separate MI sample is not a drop-in replacement for this runbook's flow output contract

4. **Record Values**
   - Application (client) ID > Pass as `-ClientId` runbook parameter
   - Directory (tenant) ID > Pass as `-TenantId` runbook parameter
   - Certificate thumbprint > Pass as `-CertificateThumbprint` runbook parameter

Sources: [register an application](https://learn.microsoft.com/entra/identity-platform/quickstart-register-app),
[management applications](https://learn.microsoft.com/power-platform/admin/powershell-create-service-principal),
and [single-tenant Dataverse S2S](https://learn.microsoft.com/power-apps/developer/data-platform/use-single-tenant-server-server-authentication).

---

## Azure Automation Setup

1. **Create or Use Existing Automation Account**
   - Resource group: Governance or shared services
   - Location: Select a supported Azure region; colocating with the Power Platform environment is a deployment choice, not an ACA API requirement

2. **Import Runbook**
   - Import `Start-ActionConfirmationValidationRunbook.ps1` as a Windows PowerShell 5.1 runbook. Microsoft Learn documents `Microsoft.PowerApps.Administration.PowerShell` as a .NET Framework module that is incompatible with PowerShell 6.0 and later.
   - Package the supporting ACA scripts, `private` module, and repository-root shared zone-classification script so their relative paths resolve on the worker. Importing the wrapper alone does not deploy these dependencies
   - Publish the runbook

3. **Configure Authentication**
   - Upload certificate to Azure Automation certificate store
   - Verify the worker can resolve the certificate and its private key by thumbprint for `Connect-AzAccount -ServicePrincipal`. Merely recording a thumbprint does not establish certificate availability
   - An Automation certificate asset is retrieved as an X509 certificate with `Get-AutomationCertificate`. This is distinct from the local personal certificate store (`Cert:\CurrentUser\My`) used by thumbprint sign-in; validate the asset-to-store setup for the selected worker
   - The runbook uses `-TenantId`, `-ClientId`, and `-CertificateThumbprint` parameters

4. **Install Required Modules**
   - `Microsoft.PowerApps.Administration.PowerShell` in Windows PowerShell 5.1
   - `Az.Accounts` **5.0.0 or later**, required by the certificate runbook for `Connect-AzAccount` and `Get-AzAccessToken`
   - `MSAL.PS` is not used by the current runbook or evidence exporter

5. **Validate Both Authentication Contexts Before Scheduling**
   - The scanner calls `Get-AdminPowerAppEnvironment`, which needs an authenticated Power Apps administration session in addition to the Az context used for Dataverse tokens
   - The certificate wrapper currently calls `Connect-AzAccount` but does **not** call `Add-PowerAppsAccount`. Establish and validate the Power Platform session in the worker bootstrap before invoking it; publishing the wrapper alone is not an end-to-end unattended setup
   - Verify access to known agents in every intended environment. A successful Azure sign-in or a zero-agent result is not proof of complete tenant coverage
   - `Start-ActionConfirmationRunbook-MI.ps1` is a separate sample with a different JSON envelope. Its Power Platform token handoff and flow adaptation still require tenant validation; do not substitute it into ACA-Scanner unchanged

Sources: [administration module runtime](https://learn.microsoft.com/power-platform/admin/powershell-installation),
[Automation runtime packages](https://learn.microsoft.com/azure/automation/runtime-environment-overview),
[certificate assets](https://learn.microsoft.com/azure/automation/shared-resources/certificates),
and [Azure PowerShell certificate authentication](https://learn.microsoft.com/powershell/azure/authenticate-noninteractive).

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
| `*.crm.dynamics.com` | HTTPS 443 | Dataverse Web API (regional variants such as `*.crm4.dynamics.com`) |
| `login.microsoftonline.com` | HTTPS 443 | Microsoft Entra ID authentication |
| `management.azure.com` | HTTPS 443 | Azure Automation API |
| `api.bap.microsoft.com` | HTTPS 443 | Power Platform Admin API |

This is not an exhaustive firewall allowlist. Review Microsoft's current Power
Platform URL/IP requirements for the tenant and connectors. The optional Purview
helper additionally calls `graph.microsoft.com` over HTTPS 443.

Sources: [Power Platform required services](https://learn.microsoft.com/power-apps/maker/canvas-apps/limits-and-config)
and [Automation networking](https://learn.microsoft.com/azure/automation/automation-network-configuration).

---

## Environment Lifecycle Management (ELM) Integration

ACA uses zone classification from the Environment Lifecycle Management (ELM) solution to determine confirmation requirements per environment. Zone classification is resolved using the shared module:

- **Shared module:** `scripts/shared/Get-ZoneClassification.ps1` (repository root)
- **Local wrapper:** `scripts/private/Get-ZoneClassification.ps1`

If ELM is not deployed and the environment name matches no zone naming convention, zone classification resolves to `Unknown`. Under canonical zone semantics the most-restrictive tier is **Zone 1 (Enterprise)**; classify environments explicitly (ELM or naming convention) so the correct confirmation policy is applied.

---

## Optional: Microsoft Purview DSPM Integration

`scripts/Get-PurviewAIHubEvidence.ps1` cross-references ACA confirmation results
with Microsoft Purview activity. The current **Data Security Posture Management
(DSPM)** experience replaces the earlier **DSPM for AI (classic)** and **Data
Security Posture Management (classic)** experiences. The file name retains the
historical AI Hub branding. The script is optional and has
additional dependencies beyond the core scan:

| Requirement | Purpose |
|-------------|---------|
| `Microsoft.Graph.Authentication` module | Connect to Microsoft Graph (`Connect-MgGraph`) |
| PowerShell 7 or later | Required by `Get-PurviewAIHubEvidence.ps1`; run separately from the Windows PowerShell 5.1 core scanner |
| Graph permission `AuditLogsQuery.Read.All` | Broad delegated/application permission accepted for creating audit queries and reading their records; this helper's example uses delegated access with admin consent. The API also supports service-scoped permissions |
| Dataverse access token (Power Automate Premium not required) | Query `fsi_actionauditresults`; supplied via `-DataverseAccessToken` (SecureString) or acquired automatically via `Az.Accounts` `Get-AzAccessToken` |
| Appropriate Purview audit/DSPM feature entitlements, audit access, and recorded activities | Required for the selected optional data sources; an E5 label alone does not establish that the desired activity exists |

The Microsoft Graph session token cannot be reused for Dataverse because the two
services require tokens scoped to different audiences. Example:

```powershell
Connect-MgGraph -Scopes 'AuditLogsQuery.Read.All'
Connect-AzAccount   # workstation example; Azure automation should use managed identity where supported
. ./scripts/Get-PurviewAIHubEvidence.ps1
Get-PurviewAIHubEvidence -DataverseUrl 'https://yourorg.crm.dynamics.com' -LookbackDays 7
```

**Collection boundary:** The helper's Graph query selects `aipDiscover` and
`aipSensitivityLabelAction`, not comprehensive Copilot interactions. Its optional
`Get-ActivityExplorerData` fallback is not the documented Microsoft
`Export-ActivityExplorerData` cmdlet and requires a separately supplied command.
Do not treat an empty result or a saved correlation file as proof that Copilot
activity was completely collected. Query completion, paging, and a supported
Copilot activity collection path require separate validation.

Sources: [current DSPM experience](https://learn.microsoft.com/purview/data-security-posture-management-learn-about),
[create audit query](https://learn.microsoft.com/graph/api/security-auditcoreroot-post-auditlogqueries?view=graph-rest-1.0),
[read audit records](https://learn.microsoft.com/graph/api/security-auditlogquery-list-records?view=graph-rest-1.0),
[Activity Explorer export](https://learn.microsoft.com/powershell/module/exchangepowershell/export-activityexplorerdata),
and [Purview licensing](https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description).

---

## Validation Checklist

- [ ] Premium connector licensing confirmed for the chosen flow owner or allocated Process license
- [ ] Agent authors have the appropriate Copilot Studio entitlement
- [ ] Dataverse environment ready with sufficient capacity
- [ ] Microsoft Entra ID app registration created (`ACA-ActionConfirmationAuditor`)
- [ ] Management application registered for unattended Power Platform enumeration; Power Apps administration session validated in the worker
- [ ] Dataverse application user and security role configured in every scanned environment and the central evidence environment
- [ ] Azure Automation account configured with runbook imported
- [ ] Service principal has Dataverse read access to `bot` and `botcomponent` tables
- [ ] Network connectivity to required endpoints verified
- [ ] Zone classification source configured (ELM or naming convention; unresolved resolves to `Unknown`)
- [ ] Az.Accounts 5.0.0+, Windows PowerShell 5.1, certificate/private key, and relative script dependencies verified on the actual worker
- [ ] Optional Purview licensing, audit permissions, PowerShell 7+ runtime, and collection completeness checked separately if used

---

See the [technical verification record](technical-verification-2026-10-16.md) for
Microsoft Learn sources, discrepancies, downstream review, and validation limits.

*Action Confirmation Auditor v1.2.3 — **Last Verified:** 2026-10-16*
