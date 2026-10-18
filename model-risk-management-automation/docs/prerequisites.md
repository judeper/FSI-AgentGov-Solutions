# Prerequisites

Complete all prerequisites before deploying the Model Risk Management Automation solution. This checklist helps meet the configuration requirements for Dataverse, Power Automate, SharePoint, and API integrations.

## Licensing Requirements

| Requirement | Purpose |
|-------------|---------|
| Power Automate Premium or Process licensing | Premium-connector cloud flows (Dataverse, HTTP, Word Online (Business)); Approvals and SharePoint are standard connectors |
| Power Apps entitlement for Dataverse apps | Appropriate Power Apps licensing for each user of the Canvas portal or model-driven workbench |
| Dataverse capacity | 6 custom tables for MRM data storage |
| Managed Environment | Required for Dataverse Long-Term Retention (LTR) |
| Teams and SharePoint Online service entitlements | Confirm assigned plans include each service; Teams may be bundled in a qualifying Microsoft 365 plan or licensed separately |
| Power BI Pro or Premium Per User | MRM Compliance Dashboard (optional but recommended) |

> **Licensing context:** Automated/scheduled premium flows use the owner's license context; instant premium flows use the invoking user's context unless covered by a Process license or applicable app-context rights. Responding to an approval alone does not require Premium. Power Automate licensing does not replace Power Apps rights for these Dataverse apps. Microsoft Graph authorization is API-specific, not a blanket "E3+" entitlement. See [Power Automate licensing](https://learn.microsoft.com/power-platform/admin/power-automate-licensing/faqs), [Power Apps licensing](https://learn.microsoft.com/power-platform/admin/powerapps-flow-licensing-faq), [Teams plans](https://learn.microsoft.com/office365/servicedescriptions/teams-service-description), and [Graph user-read permissions](https://learn.microsoft.com/graph/api/user-get?view=graph-rest-1.0).

## Required Roles

| Role | Required For |
|------|--------------|
| Power Platform Admin | Environment administration and Managed Environment configuration; Dataverse `bot` data access additionally requires a Dataverse security role |
| System Administrator (Dataverse) | Dataverse table creation, solution import, and alternate key configuration |
| Entra Global Admin or Privileged Role Administrator | Tenant-wide consent / app-role assignment for Microsoft Graph application permissions; enabling a managed identity on an Azure resource separately requires Azure resource permissions |
| SharePoint Admin | MRM Governance site creation and permission configuration |

> **Important:** These roles are required during initial deployment. Day-to-day operation requires only the service account / Managed Identity permissions listed below.

Entra service-admin assignment does not automatically grant Dataverse System Administrator in environments. [Self-elevate when required](https://learn.microsoft.com/power-platform/admin/use-service-admin-role-manage-tenant), or assign an appropriately scoped Dataverse role to the operator/application user.

## API Permissions (Managed Identity and Delegated Admin)

Grant the following application permissions to the managed identity used by production Power Automate flows where the target API supports application permissions:

| Permission | Type | Scope | Purpose |
|-----------|------|-------|---------|
| `User.Read.All` | Application | Microsoft Graph | Resolve owner and validator UPNs to user profiles (department, display name) |
| `Sites.ReadWrite.All` | Application | Microsoft Graph / SharePoint | Agent Card document creation, update, and folder management |
| `EnvironmentManagement.Settings.Read` | Application | Power Platform API | Read environment management settings via the Power Platform programmability API |

> **Power Platform API scopes are namespaced.** There is no `PowerPlatform.Admin.Read.All`
> permission; the [Power Platform API permission reference](https://learn.microsoft.com/power-platform/admin/programmability-permission-reference#defined-permissions)
> defines namespaced scopes such as `EnvironmentManagement.Settings.Read` and
> `ResourceQuery.Resources.Read`. **Agent (bot) metadata** lives in Dataverse — read it
> through the [Dataverse Web API](https://learn.microsoft.com/power-apps/developer/data-platform/webapi/overview)
> using an application user granted a security role (for example, a read-only custom role),
> not a Power Platform API scope.

Optional Agent 365 registry enrichment depends on which Microsoft Graph preview path your tenant uses:

| Permission | Type | Scope | Purpose |
|-----------|------|-------|---------|
| `CopilotPackages.Read.All` | Application or Delegated | Microsoft Graph Agent 365 package APIs | Inventory/export from `/v1.0/copilot/admin/catalog/packages`; beta is also documented. Requires a Microsoft Agent 365 license; delegated administrators require AI Admin or Global Admin |
| `AgentInstance.Read.All` | Application or Delegated | Microsoft Graph beta `/agentRegistry/agentInstances` | Identity-only cross-reference during Agent Registry convergence; feature-flag with `IsAgent365LifecycleEnabled` and plan migration to Agent 365 APIs |

### Granting Permissions

1. For managed identities, follow Microsoft's [grant API permissions to managed identities](https://learn.microsoft.com/powershell/entra-powershell/grant-api-permissions-managed-identity) procedure. Assign Graph app roles directly to the managed identity's service principal; do not look for **Add a permission** under Enterprise applications.
2. Identify the managed identity by its service-principal object ID, resolve the Microsoft Graph resource service principal and the required app roles, then grant only the reviewed application permissions. Graph grants require Privileged Role Administrator (or Entra Global Admin), not Application Administrator.
3. Read back the service principal's app-role assignments and verify the resource and role IDs match the requested permissions.
4. For an app registration instead, configure **App registrations** → **API permissions** and use the documented [tenant-wide admin consent](https://learn.microsoft.com/entra/identity/enterprise-apps/grant-admin-consent) process.
5. For optional package inventory, validate the [List packages](https://learn.microsoft.com/microsoft-365-copilot/extensibility/api/admin-settings/package/copilotpackages-list) license and permission requirements. Application access is now documented; delegated access remains an option. Granting a managed identity Graph permissions does not authenticate the SharePoint or Word connector connections: configure each connection according to its supported authentication.

> **Note:** Agent 365 / Agent ID registry permissions are only required when `IsAgent365LifecycleEnabled` is set to `"true"`. If Agent 365 registry APIs are unavailable in your tenant or cloud, keep the flag disabled and rely on `agent-registry-automation` as the source of registered agents.

## Solution Dependencies

| Dependency | Required | Notes |
|-----------|----------|-------|
| agent-registry-automation | **Yes (mandatory)** | Must be deployed first. Flow 1 reads from `fsi_agentinventory` to sync registered agents into the MRM inventory. |
| agent-365-lifecycle-governance | No (optional) | If deployed, enables Agent 365 / Microsoft Entra Agent ID cross-reference via `IsAgent365LifecycleEnabled`. Set the flag to `"true"` only after confirming the selected API version, license, roles, and permissions in your tenant. |

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
4. If not enabled, enable it before proceeding (requires Power Platform Administrator)

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

- [ ] Power Automate owner/invoker or Process licensing confirmed for the selected flow design; approval responders are not automatically Premium users
- [ ] Power Apps entitlements confirmed for Dataverse app users; Teams and SharePoint Online service plans verified
- [ ] Managed Environment enabled on target environment
- [ ] Dataverse capacity sufficient for 6 custom tables
- [ ] `agent-registry-automation` deployed and `fsi_agentinventory` populated
- [ ] Managed Identity created with all API permissions granted
- [ ] SharePoint MRM Governance site created (see [SharePoint Setup](sharepoint-setup.md))
- [ ] Microsoft Teams available and Approvals provisioned
- [ ] Power BI Pro or Premium Per User available (if deploying dashboard)
- [ ] Network connectivity to all required endpoints verified
- [ ] Both feature flags confirmed at `"false"` (default)

Current technical verification and downstream review: [2026-10-16 record](verification-2026-10-16.md).
