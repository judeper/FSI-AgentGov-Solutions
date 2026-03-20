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
| Power Platform Admin | Environment enumeration, Bots API access, and Managed Environment configuration |
| System Administrator (Dataverse) | Dataverse table creation, solution import, and alternate key configuration |
| Entra Global Admin or Application Administrator | Managed Identity creation and API permission grants |
| SharePoint Admin | MRM Governance site creation and permission configuration |

> **Important:** These roles are required during initial deployment. Day-to-day operation requires only the service account / Managed Identity permissions listed below.

## API Permissions (Managed Identity)

Grant the following application permissions to the Managed Identity used by the Power Automate flows:

| Permission | Type | Scope | Purpose |
|-----------|------|-------|---------|
| `AgentRegistry.Read.All` | Application | Microsoft Graph | Read agent identities for cross-reference with Entra Agent Registry |
| `User.Read.All` | Application | Microsoft Graph | Resolve owner and validator UPNs to user profiles (department, display name) |
| `Sites.ReadWrite.All` | Application | Microsoft Graph / SharePoint | Agent Card document creation, update, and folder management |
| `PowerPlatform.Admin.Read.All` | Application | Power Platform API | Read agent metadata and environment configurations |

### Granting Permissions

1. Navigate to **Entra ID** → **Enterprise Applications** → locate the Managed Identity
2. Select **API Permissions** → **Add a permission**
3. Add each permission listed above
4. Select **Grant admin consent** (requires Entra Global Admin or Application Administrator)

> **Note:** `AgentRegistry.Read.All` is only required when `IsAgent365LifecycleEnabled` is set to `"true"`. If Agent 365 / Frontier is not enabled in your tenant, this permission can be deferred.

## Solution Dependencies

| Dependency | Required | Notes |
|-----------|----------|-------|
| agent-registry-automation | **Yes (mandatory)** | Must be deployed first. Flow 1 reads from `fsi_agentinventory` to sync registered agents into the MRM inventory. |
| agent-365-lifecycle-governance | No (optional) | If deployed, enables Entra Agent Registry cross-reference via `IsAgent365LifecycleEnabled` flag. Set flag to `"true"` only after confirming Agent 365 / Frontier is available. |

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
| `IsAgent365LifecycleEnabled` | `"false"` | Gates Entra Agent Registry API calls in Flow 1 | Set to `"true"` only when Agent 365 / Frontier is enabled in your tenant and `AgentRegistry.Read.All` permission is granted |

> **Important:** Setting `IsMRMAutomationEnabled` to `"true"` before completing all configuration steps may result in flow failures. Follow the deployment guide sequentially and use the DELIVERY-CHECKLIST.md to track completion.

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `graph.microsoft.com` | HTTPS (443) | Graph API calls for user resolution and Agent Registry |
| `api.powerplatform.com` | HTTPS (443) | Power Platform API for agent metadata |
| `{tenant}.sharepoint.com` | HTTPS (443) | Agent Card document operations |
| `{org}.crm.dynamics.com` | HTTPS (443) | Dataverse Web API |

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
