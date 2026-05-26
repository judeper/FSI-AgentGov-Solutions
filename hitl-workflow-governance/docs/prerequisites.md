# Prerequisites

Requirements for deploying the HITL Workflow Governance solution.

> **Preview Notice:** The Human in the Loop connector actions — **Request for Information** (RFI) and **Run a Multistage Approval** — are currently in public preview. RFI entered public preview in July 2025. The connector reference labels both actions as "(preview)." Preview features may change before general availability. This solution provides governance tooling, but administrators should monitor the [Copilot Studio release notes](https://learn.microsoft.com/en-us/microsoft-copilot-studio/whats-new) and connector reference for changes that may affect behavior.

---

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Automate license appropriate for Dataverse/Azure Automation connectors** | Cloud flows and automation jobs |
| **Dataverse capacity** | Checkpoint result, scan run, and exception storage |
| **Microsoft 365 E5** or **E5 Compliance** | Tenant-wide agent and bot component visibility |
| **Azure Automation** *(optional)* | Scheduled runbook execution for compliance scans |
| **Copilot Studio Copilot Credits** *(conditional)* | Required by Microsoft Learn when AI approval stages are used in multistage approvals |

The Human in the Loop connector and Approvals connector are documented as Standard connectors. Verify licensing with your Microsoft agreement because Dataverse, Azure Automation, and tenant connector policies may still require premium licensing.

---

## Permissions

### Microsoft Entra ID Roles

| Role | Required For |
|------|--------------|
| **Power Platform Admin** | Cross-environment agent and bot component enumeration |
| **Entra Global Admin** or **Application Administrator** | App registration, certificate configuration, and admin consent when service principals are used |

### Power Platform Roles

| Role | Required For |
|------|--------------|
| **System Administrator** | Dataverse table creation and schema deployment |
| **System Customizer** | Environment variable and connection reference creation |

### Dataverse Permissions

| Permission | Table | Purpose |
|------------|-------|---------|
| Read | `bot` | Enumerate Copilot Studio agents |
| Read | `botcomponent` | Inspect agent topic definitions and HITL action nodes |
| Create/Read/Write | `fsi_HitlCheckpointResult` | Store checkpoint validation records |
| Create/Read/Write | `fsi_HitlCheckpointException` | Manage approved exceptions |
| Create/Read/Write | `fsi_HitlScanRun` | Store scan run history |

---

## Authentication Standard

Use the strongest secretless authentication option available in your runtime:

1. **System-assigned managed identity** for Azure-hosted setup jobs or Automation workers where supported.
2. **User-assigned managed identity** when the same identity must be shared across resources.
3. **Workload identity federation** for CI/CD runners such as GitHub Actions OIDC.
4. **Certificate-based service principal** for Azure Automation runbooks that cannot use managed identity for every required connector.
5. **Interactive/device-code auth** for one-off administrator workstation setup.
6. **Client secret** only as a development fallback. `# legacy: dev-only — replace with managed identity in production`

The Python deployment client uses `DefaultAzureCredential` when `--client-secret` is omitted. Set `AZURE_CLIENT_ID` or pass `--client-id` for user-assigned managed identity scenarios. Use `--interactive` for local administrator setup when secretless Azure credentials are not available.

---

## PowerShell Modules

| Module | Minimum Version | Purpose |
|--------|----------------|---------|
| `Microsoft.PowerApps.Administration.PowerShell` | 2.0+ | Power Platform environment and agent enumeration |
| `Az.Accounts` | 5.0+ | Managed identity, certificate, and interactive Azure token acquisition |
| `MSAL.PS` | 4.37+ | Certificate-based token acquisition in `Start-HitlValidationRunbook.ps1` |

> ⚠️ **MSAL.PS deprecation notice:** The [`MSAL.PS`](https://github.com/AzureAD/MSAL.PS) repository was archived in September 2023 and receives no further updates. The rest of this solution migrated to `Az.Accounts` in v1.1.2 (m-6); `Start-HitlValidationRunbook.ps1` retains the dependency for certificate-based Azure Automation token acquisition. For new runbook deployments, consider using `Az.Accounts` `Connect-AzAccount -CertificateThumbprint` instead.

Install with:
```powershell
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force
Install-Module -Name Az.Accounts -Scope CurrentUser -Force
Install-Module -Name MSAL.PS -Scope CurrentUser -Force
```

---

## Python Requirements

| Requirement | Purpose |
|-------------|---------|
| **Python 3.9+** | Dataverse schema deployment and setup scripts |
| `azure-identity` | Secretless `DefaultAzureCredential` authentication |
| `msal` | Interactive and legacy client-secret authentication fallback |
| `requests` | Dataverse Web API calls |

Install with:
```bash
pip install -r scripts/requirements.txt
```

---

## Microsoft Entra ID App Registration

Create an app registration when certificate-based Automation or legacy service-principal setup is required.

1. **Register Application**
   - Navigate to Microsoft Entra ID > App registrations > New registration
   - Name: `HITL-WorkflowGovernance`
   - Supported account types: Single tenant
   - Redirect URI: Not required for certificate or managed identity paths

2. **API Permissions**
   - Dynamics CRM: `user_impersonation` or Dataverse application user configuration
   - Power Platform API: permissions required for environment enumeration
   - Microsoft Graph: `Application.Read.All` only if your local extension needs Graph-backed agent metadata
   - Admin consent: required where application permissions are used

3. **Credential**
   - Preferred: certificate credential stored in Azure Automation certificate assets or approved certificate store
   - Alternative: workload identity federation for CI/CD
   - Development fallback: client secret with short expiration. `# legacy: dev-only — replace with managed identity in production`

4. **Record Values**
   - Application (client) ID
   - Directory (tenant) ID
   - Certificate thumbprint or managed identity client ID
   - Dataverse environment URL

---

## Dataverse Environment

- Target Dataverse environment URL (for example, `https://yourorg.crm.dynamics.com`)
- Sufficient storage capacity for checkpoint result and scan run records
- Deploy schema using secretless auth where available:

```bash
python scripts/create_hwg_dataverse_schema.py \
  --environment-url https://yourorg.crm.dynamics.com \
  --tenant-id <tenant-id>
```

For local setup, use interactive auth:

```bash
python scripts/create_hwg_dataverse_schema.py \
  --environment-url https://yourorg.crm.dynamics.com \
  --tenant-id <tenant-id> \
  --interactive
```

Client-secret deployment remains available only for development fallback:

```bash
python scripts/create_hwg_dataverse_schema.py \
  --environment-url https://yourorg.crm.dynamics.com \
  --client-id <app-id> \
  --client-secret <secret> \
  --tenant-id <tenant-id>
```

See [dataverse-schema.md](dataverse-schema.md) for the auto-generated column reference.

---

## Azure Automation Setup (Optional)

For scheduled unattended scans:

1. **Create or Use Existing Automation Account**
   - Resource group: governance or shared services
   - Location: same region as the Power Platform environment where possible
   - Enable managed identity if your connector/runtime model supports it

2. **Import Runbook**
   - Import `Start-HitlValidationRunbook.ps1` as a PowerShell 7.2 runbook (this is the orchestrator entrypoint)
   - Import the companion scripts and `private/` helper folder that the runbook dot-sources
   - Publish the runbook

3. **Configure Authentication**
   - Preferred: certificate-based app registration or managed identity with required Dataverse and Power Platform permissions
   - Avoid long-lived client secrets for production automation

4. **Install Required Modules**
   - `Az.Accounts`
   - `MSAL.PS`
   - `Microsoft.PowerApps.Administration.PowerShell`

---

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `*.crm.dynamics.com` | HTTPS 443 | Dataverse Web API |
| `login.microsoftonline.com` | HTTPS 443 | Microsoft Entra ID authentication |
| `api.powerplatform.com` | HTTPS 443 | Power Platform Admin API |
| `management.azure.com` | HTTPS 443 | Azure Automation API (if using runbooks) |
| `outlook.office.com` / Microsoft 365 mail endpoints | HTTPS 443 | RFI Outlook delivery and approval notifications |

---

## Environment Lifecycle Management (ELM) Integration

HITL Workflow Governance uses zone classification from the Environment Lifecycle Management (ELM) solution to determine checkpoint requirements per environment. Zone classification is resolved using the shared module:

- **Shared module:** `scripts/shared/Get-ZoneClassification.ps1` (repository root)
- **Local wrapper:** `scripts/governance/Get-ZoneClassification.ps1`

If ELM is not deployed, zone classification defaults to Zone 3 (most restrictive) for all environments.

---

## Human in the Loop Connector — Preview Considerations

The `shared_advancedapprovals` connector (Human in the Loop) provides two actions used by Copilot Studio agents:

| Action | Operation ID | Status | Key considerations |
|--------|--------------|--------|--------------------|
| **Request for Information** | `RequestForInformation` | Public preview | Requires `title`, Outlook `message`, and `assignedTo`; uses only the first response; does not support external-tenant assignees; supports Text, Yes/No, Email, Number, and Date input types |
| **Run a Multistage Approval** | `StartAndWaitForAnApprovalProcess` | Preview | Available only in agent flows; no attachments; no ALM/sharing/import support; same approver cannot be assigned to different stages; AI stages require Copilot Studio Copilot Credits |

Administrators should avoid spaces in RFI input names because Microsoft Learn notes that spaces can cause output values to be wrapped in double braces. Re-validate scan logic if Microsoft changes connector schemas before general availability.

---

## Validation Checklist

- [ ] E5 or E5 Compliance license available
- [ ] Power Automate and Dataverse licensing verified for the target tenant
- [ ] Dataverse environment ready with sufficient capacity
- [ ] Managed identity, workload identity federation, certificate credential, or interactive admin setup path selected
- [ ] App registration created only where required for certificate-based or legacy service-principal auth
- [ ] Admin consent granted for required API permissions
- [ ] PowerShell modules installed (`Microsoft.PowerApps.Administration.PowerShell`, `Az.Accounts`, `MSAL.PS`)
- [ ] Python 3.9+ with packages from `scripts/requirements.txt`
- [ ] Scanning identity has Dataverse read access to `bot` and `botcomponent` tables
- [ ] Network connectivity to required endpoints verified
- [ ] Zone classification source configured (ELM or default Zone 3)
- [ ] Azure Automation account configured (optional — for scheduled scans)
- [ ] HITL connector preview status acknowledged and monitoring plan in place

---

*HITL Workflow Governance v1.1.2*
