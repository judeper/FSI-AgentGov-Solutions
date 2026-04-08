# Prerequisites

Requirements for deploying the HITL Workflow Governance solution.

> **Preview Notice:** The Human in the Loop connector actions — **Request for Information** (RFI) and **Run a Multistage Approval** — are currently in public preview. RFI entered public preview in July 2025. The connector reference labels both actions as "(preview)." Preview features may change before general availability. This solution provides full governance tooling but administrators should monitor the [Copilot Studio release notes](https://learn.microsoft.com/en-us/microsoft-copilot-studio/release-notes) for changes that may affect behavior.

---

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows (HITL-Scanner, HITL-Violation-Alert, HITL-Exception-Approval) |
| **Dataverse capacity** | Checkpoint result, scan run, and exception storage |
| **Microsoft 365 E5** or **E5 Compliance** | Tenant-wide agent and bot component visibility |
| **Azure Automation** *(optional)* | Scheduled runbook execution for compliance scans |

---

## Permissions

### Microsoft Entra ID Roles

| Role | Required For |
|------|--------------|
| **Power Platform Admin** | Cross-environment agent and bot component enumeration |
| **Entra Global Admin** or **Application Administrator** | App registration for service principal |

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

## PowerShell Modules

| Module | Minimum Version | Purpose |
|--------|----------------|---------|
| `Microsoft.PowerApps.Administration.PowerShell` | 2.0+ | Power Platform environment and agent enumeration |
| `MSAL.PS` | 4.37+ | Microsoft Entra ID token acquisition |

Install with:
```powershell
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force
Install-Module -Name MSAL.PS -Scope CurrentUser -Force
```

---

## Python Requirements

| Requirement | Purpose |
|-------------|---------|
| **Python 3.9+** | Dataverse schema deployment and evidence export scripts |
| `msal` | Microsoft Entra ID authentication |
| `requests` | Dataverse Web API calls |

Install with:
```bash
pip install msal requests
```

---

## Microsoft Entra ID App Registration

1. **Register Application**
   - Navigate to Entra ID > App registrations > New registration
   - Name: `HITL-WorkflowGovernance`
   - Supported account types: Single tenant
   - Redirect URI: Not required (daemon/service)

2. **API Permissions**
   - Dynamics CRM: `user_impersonation` (Delegated) or configure S2S
   - Power Platform API: As required for environment enumeration
   - Microsoft Graph: `Application.Read.All` (Application) — for agent metadata
   - Admin consent: Required

3. **Client Secret**
   - Create client secret with appropriate expiration
   - Store securely in Azure Key Vault or Azure Automation credentials

4. **Record Values**
   - Application (client) ID → `fsi_HWG_ClientId`
   - Directory (tenant) ID → `fsi_HWG_TenantId`
   - Client secret → Store in Azure Automation credential asset or Key Vault

---

## Dataverse Environment

- Target Dataverse environment URL (e.g., `https://yourorg.crm.dynamics.com`)
- Sufficient storage capacity for checkpoint result and scan run records
- Deploy schema using:

```bash
python scripts/create_hwg_dataverse_schema.py \
  --dataverse-url https://yourorg.crm.dynamics.com \
  --client-id <app-id> \
  --client-secret <secret> \
  --tenant-id <tenant-id>
```

See [dataverse-schema.md](dataverse-schema.md) for the auto-generated column reference.

---

## Azure Automation Setup (Optional)

For scheduled unattended scans:

1. **Create or Use Existing Automation Account**
   - Resource group: Governance or shared services
   - Location: Same region as Power Platform environment

2. **Import Runbook**
   - Import `Test-HitlWorkflowCompliance.ps1` as PowerShell 7.2 runbook
   - Publish the runbook

3. **Configure Credentials**
   - Create credential asset with app registration client ID and secret
   - Or configure System-Assigned Managed Identity with required permissions

4. **Install Required Modules**
   - `Az.Accounts` (for authentication)
   - `MSAL.PS` (if using client credential flow)
   - `Microsoft.PowerApps.Administration.PowerShell`

---

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `*.crm.dynamics.com` | HTTPS 443 | Dataverse Web API |
| `login.microsoftonline.com` | HTTPS 443 | Microsoft Entra ID authentication |
| `api.powerplatform.com` | HTTPS 443 | Power Platform Admin API |
| `management.azure.com` | HTTPS 443 | Azure Automation API (if using runbooks) |

---

## Environment Lifecycle Management (ELM) Integration

HITL Workflow Governance uses zone classification from the Environment Lifecycle Management (ELM) solution to determine checkpoint requirements per environment. Zone classification is resolved using the shared module:

- **Shared module:** `scripts/shared/Get-ZoneClassification.ps1` (repository root)
- **Local wrapper:** `scripts/governance/Get-ZoneClassification.ps1`

If ELM is not deployed, zone classification defaults to Zone 3 (most restrictive) for all environments.

---

## Human in the Loop Connector — Preview Considerations

The `advancedapprovals` connector (Human in the Loop) provides two actions used by Copilot Studio agents:

| Action | Status | Description |
|--------|--------|-------------|
| **Request for Information** (RFI) | Public preview (Jul 2025) | Pauses agent flow to request human input |
| **Run a Multistage Approval** | Preview | Routes agent decisions through multi-step approval chains |

**Preview limitations to consider:**
- Action schemas may change before GA
- Connector API versioning may shift
- Bot component inspection patterns may evolve
- Monitor Microsoft Learn documentation for breaking changes

This solution provides governance tooling for these preview actions. Administrators should plan to re-validate scan logic if Microsoft publishes breaking changes to the connector schema.

---

## Validation Checklist

- [ ] E5 or E5 Compliance license available
- [ ] Power Platform Premium license for flow creator
- [ ] Dataverse environment ready with sufficient capacity
- [ ] Microsoft Entra ID app registration created (`HITL-WorkflowGovernance`)
- [ ] Admin consent granted for API permissions
- [ ] PowerShell modules installed (`Microsoft.PowerApps.Administration.PowerShell`, `MSAL.PS`)
- [ ] Python 3.9+ with `msal` and `requests` packages installed
- [ ] Service principal has Dataverse read access to `bot` and `botcomponent` tables
- [ ] Network connectivity to required endpoints verified
- [ ] Zone classification source configured (ELM or default Zone 3)
- [ ] Azure Automation account configured (optional — for scheduled scans)
- [ ] HITL connector preview status acknowledged and monitoring plan in place

---

*HITL Workflow Governance v1.0.0*
