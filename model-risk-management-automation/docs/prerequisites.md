# Prerequisites

Complete all prerequisites before deploying the Model Risk Management Automation solution. This checklist helps meet the configuration requirements for Dataverse, Power Automate, SharePoint, and API integrations.

## Licensing Requirements

| Requirement | Purpose |
|-------------|---------|
| Power Platform Premium | Power Automate flows with Dataverse, HTTP, Approvals, SharePoint, Word Online connectors |
| Dataverse capacity | 6 custom tables for MRM data storage |
| Managed Environment | Required for Dataverse Long-Term Retention (LTR) |
| Microsoft 365 E3+ | Teams notifications, Graph API, SharePoint |
| Power BI Pro or Premium Per User | MRM Compliance Dashboard (optional but recommended) |

> **Note:** Power Platform Premium licensing is required for each user who triggers or interacts with approval flows. Service account licensing may differ — consult your Microsoft licensing representative.

## Required Roles

| Role | Required For |
|------|--------------|
| Power Platform Admin | Environment enumeration, Dataverse `bot` table access, and Managed Environment configuration |
| System Administrator (Dataverse) | Dataverse table creation, solution import, and alternate key configuration |
| Microsoft Entra Global Administrator or Application Administrator | Managed identity creation and API permission grants |
| SharePoint Admin | MRM Governance site creation and permission configuration |

> **Important:** These roles are required during initial deployment. Day-to-day operation requires only the service account / Managed Identity permissions listed below.

## API Permissions (Managed Identity and Delegated Admin)

Grant the following application permissions to the managed identity used by production Power Automate flows where the target API supports application permissions:

| Permission | Type | Scope | Purpose |
|-----------|------|-------|---------|
| `User.Read.All` | Application | Microsoft Graph | Resolve owner and validator UPNs to user profiles (department, display name) |
| `Sites.ReadWrite.All` | Application | Microsoft Graph / SharePoint | Agent Card document creation, update, and folder management |
| `PowerPlatform.Admin.Read.All` | Application | Power Platform API | Read agent metadata and environment configurations |

Optional Agent 365 registry enrichment depends on which Microsoft Graph preview path your tenant uses:

| Permission | Type | Scope | Purpose |
|-----------|------|-------|---------|
| `CopilotPackages.Read.All` | Delegated | Microsoft Graph beta Agent 365 package APIs | Inventory/export agents from `/beta/copilot/admin/catalog/packages`; current Microsoft Learn lists delegated permissions only and requires AI Admin or Global Admin role |
| `AgentInstance.Read.All` | Application or Delegated | Microsoft Graph beta `/agentRegistry/agentInstances` | Identity-only cross-reference during Agent Registry convergence; feature-flag with `IsAgent365LifecycleEnabled` and plan migration to Agent 365 APIs |

### Granting Permissions

1. Navigate to **Microsoft Entra ID** → **Enterprise Applications** → locate the managed identity
2. Select **API Permissions** → **Add a permission**
3. Add the application permissions listed above
4. Select **Grant admin consent** (requires Microsoft Entra Global Administrator or Application Administrator)
5. For `CopilotPackages.Read.All`, use a delegated administrator connection or offline export until Microsoft supports application permissions for the Agent 365 package APIs.

> **Note:** Agent 365 / Agent ID registry permissions are only required when `IsAgent365LifecycleEnabled` is set to `"true"`. If Agent 365 registry APIs are unavailable in your tenant or cloud, keep the flag disabled and rely on `agent-registry-automation` as the source of registered agents.

## Solution Dependencies

| Dependency | Required | Notes |
|-----------|----------|-------|
| agent-registry-automation | **Yes (mandatory)** | Must be deployed first. Flow 1 reads from `fsi_agentinventory` to sync registered agents into the MRM inventory. |
| agent-365-lifecycle-governance | No (optional) | If deployed, enables Agent 365 / Microsoft Entra Agent ID cross-reference via `IsAgent365LifecycleEnabled`. Set the flag to `"true"` only after confirming the selected preview API path, roles, and permissions in your tenant. |

### Verifying agent-registry-automation

Before proceeding, confirm:

1. The `fsi_agentinventory` table exists in your Dataverse environment
2. The agent-registry-automation sync flow has run at least once
3. Agent records exist with `fsi_registrationstatus = "Registered"`

## Environment Requirements

| Requirement | Details |
|-------------|---------|
| Managed Environment | Target environment must be configured as a Managed Environment |
| Dataverse Long-Term Retention | Must be available (configured post-deployment for `fsi_mrmcomplianceevent`) |
| Power Automate cloud flows | Must be enabled in the target environment |
| Microsoft Teams | Must be available for approval and notification flows |
| Approvals provisioning | Power Automate Approvals must be provisioned in the environment |

### Verifying Managed Environment

1. Navigate to **Power Platform Admin Center** → **Environments**
2. Select the target environment → **Edit**
3. Confirm **Managed Environment** is toggled on
4. If not enabled, enable it before proceeding (requires Power Platform Admin)

## Feature Flags

Feature flags are implemented as Dataverse environment variables. Both default to `"false"` to prevent premature execution.

| Flag | Default | Purpose | When to Enable |
|------|---------|---------|----------------|
| `IsMRMAutomationEnabled` | `"false"` | Master switch for all MRM flows | Set to `"true"` only after all tables, connection references, environment variables, and SharePoint are configured |
| `IsAgent365LifecycleEnabled` | `"false"` | Gates optional Agent 365 / Microsoft Entra Agent ID registry calls in Flow 1 | Set to `"true"` only after confirming the selected registry API, role, and permission model for your tenant |

> **Important:** Setting `IsMRMAutomationEnabled` to `"true"` before completing all configuration steps may result in flow failures. Follow the deployment guide sequentially and use the DELIVERY-CHECKLIST.md to track completion.

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `graph.microsoft.com` | HTTPS (443) | Graph API calls for user resolution and Agent Registry |
| `{org}.crm.dynamics.com` | HTTPS (443) | Dataverse Web API (model inventory and `bot` table agent metadata) |
| `{tenant}.sharepoint.com` | HTTPS (443) | Agent Card document operations |

> **Note:** If your environment uses a firewall or proxy, verify that these endpoints are accessible from the Power Automate service. Refer to [Microsoft Power Automate IP addresses](https://learn.microsoft.com/en-us/power-automate/ip-address-configuration) for the current IP ranges.

## Pre-Deployment Checklist

- [ ] Power Platform Premium licensing confirmed for all flow users
- [ ] Managed Environment enabled on target environment
- [ ] Dataverse capacity sufficient for 6 custom tables
- [ ] `agent-registry-automation` deployed and `fsi_agentinventory` populated
- [ ] Managed Identity created with all API permissions granted
- [ ] SharePoint MRM Governance site created (see [SharePoint Setup](sharepoint-setup.md))
- [ ] Microsoft Teams available and Approvals provisioned
- [ ] Power BI Pro or Premium Per User available (if deploying dashboard)
- [ ] Network connectivity to all required endpoints verified
- [ ] Both feature flags confirmed at `"false"` (default)
