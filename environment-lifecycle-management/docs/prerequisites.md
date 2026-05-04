# Prerequisites

Complete requirements for deploying the Environment Lifecycle Management solution.

## Licensing Requirements

| License | Purpose | Minimum Tier |
|---------|---------|--------------|
| **Power Apps Premium** | Dataverse tables, model-driven app | Per User or Per App |
| **Copilot Studio** | Intake agent for environment requests | Separate license required (not included in M365 E3/E5) |
| **Power Automate Premium** | HTTP with Entra ID connector, child flows | Per User or Per Flow |
| **Azure Subscription** | Key Vault for credential/certificate storage | Pay-as-you-go |
| **Microsoft 365** | End-user licenses, Entra ID | E3 or E5 |

### License Notes

- **Power Apps Premium** is required for Dataverse custom tables (not included in standard M365)
- **Copilot Studio** messages are consumed per conversation; estimate 500-1000 messages/month for typical usage
- **Power Automate Premium** is required for the HTTP with Microsoft Entra ID (preauthorized) connector
- **Azure Key Vault** costs are minimal (~$0.03/10,000 operations)

## Role Requirements

### Deployment Roles

| Role | Entra ID / Power Platform | Purpose |
|------|---------------------------|---------|
| **Entra Global Admin** | Entra ID | Initial app registration (can delegate) |
| **Application Administrator** | Entra ID | Service Principal registration |
| **Power Platform Admin** | Power Platform | Environment creation, SP management app registration |
| **System Administrator** | Dataverse | Table creation, security roles |
| **Key Vault Secrets Officer** | Azure | Store and manage SP credentials |

### Operational Roles

| Role | Scope | Purpose |
|------|-------|---------|
| **ELM Requester** | User-level | Submit environment requests |
| **ELM Approver** | Business Unit | Approve environment requests |
| **ELM Admin** | Organization | Run automation, manage provisioning |
| **ELM Auditor** | Organization | Read-only access for compliance |

## Environment Requirements

### Governance Environment

The solution requires a dedicated Dataverse environment for governance data:

| Requirement | Specification |
|-------------|---------------|
| **Environment Type** | Production (recommended) or Sandbox |
| **Managed Environment** | Required |
| **Dataverse Database** | Required |
| **Region** | Same region as majority of target environments |
| **Security Group** | Restrict to governance team |

### Environment Groups (Pre-Create)

Create three environment groups before deployment:

| Group Name | Zone | Description |
|------------|------|-------------|
| `FSI-Zone1-PersonalProductivity` | Zone 1 | Personal productivity, standard DLP |
| `FSI-Zone2-TeamCollaboration` | Zone 2 | Team collaboration, restricted DLP |
| `FSI-Zone3-EnterpriseManagedEnvironment` | Zone 3 | Enterprise managed, highly restricted DLP |

> **Note:** Environment Groups are a premium governance capability. Groups can be created manually in the Power Platform admin center or through the current Power Platform API (`POST https://api.powerplatform.com/environmentmanagement/environmentGroups?api-version=2022-03-01-preview`). Only Managed Environments can be assigned to groups, each environment can belong to only one group, and published group rules lock the corresponding per-environment settings until the environment is removed from the group. Manual creation is recommended for initial setup to establish audit trail documentation.

## Azure Key Vault

### Key Vault Configuration

| Setting | Value |
|---------|-------|
| **SKU** | Standard |
| **Soft Delete** | Enabled (default) |
| **Purge Protection** | Recommended for production |
| **RBAC** | Azure role-based access control |

### Access Policies Required

| Principal | Secret Permissions |
|-----------|-------------------|
| Power Automate Managed Identity | Get |
| Deployment Administrator | Get, Set, Delete |
| Rotation Automation (optional) | Get, Set |

### Secrets to Store

| Secret Name | Content | Rotation |
|-------------|---------|----------|
| `ELM-ServicePrincipal-Secret` | Legacy dev-only SP client secret, if certificate/managed identity is unavailable | 90 days |
| `ELM-ServicePrincipal-Certificate` | Preferred certificate-backed app credential where supported | 1 year |

## Network Requirements

### Outbound Connectivity

The solution requires outbound access to:

| Endpoint | Purpose |
|----------|---------|
| `*.dynamics.com` | Dataverse Web API |
| `*.crm.dynamics.com` | Dataverse environment URLs |
| `login.microsoftonline.com` | Entra ID authentication |
| `graph.microsoft.com` | Microsoft Graph (user/group lookup) |
| `api.powerplatform.com` | Power Platform API, including Environment Groups (`environmentmanagement`) |
| `*.vault.azure.net` | Azure Key Vault |

### Firewall Considerations

If running scripts from on-premises or restricted networks:

1. Whitelist Microsoft 365 and Azure service tags
2. Allow HTTPS (443) outbound
3. Consider Azure Private Link for Key Vault if required by policy

## DLP Policy Considerations

### Connectors Required

The provisioning flows require these connectors to be allowed by the applicable tenant and environment data policies. Classify them consistently with your DLP strategy; if multiple policies apply, the most restrictive policy wins and environment-scoped policies cannot override tenant-wide policies. Some Microsoft connectors are non-blockable in classic DLP.

| Connector | Purpose |
|-----------|---------|
| **Dataverse** | Read/write EnvironmentRequest, ProvisioningLog |
| **Power Platform for Admins** | Create environments, enable managed |
| **HTTP with Microsoft Entra ID** | Power Platform API calls, Graph API |
| **Azure Key Vault** | Retrieve SP credentials |
| **Office 365 Outlook** | Send notifications (optional) |
| **Microsoft Teams** | Post notifications (optional) |

### DLP Policy Recommendations

| Policy Scope | Configuration |
|--------------|---------------|
| **Governance Environment** | Allow all governance connectors |
| **Zone 1 Environments** | Standard business connectors |
| **Zone 2 Environments** | Restricted to approved connectors |
| **Zone 3 Environments** | Whitelist-only approved connectors |

## Python Environment

### System Requirements

| Requirement | Specification |
|-------------|---------------|
| **Python Version** | 3.10 or higher |
| **pip** | Latest version |
| **Network** | Outbound HTTPS to Microsoft endpoints |

### Dependencies

Install via `pip install -r scripts/requirements.txt`:

```
msal>=1.30.0                    # Token caching improvements
requests>=2.32.0                # CVE-2024-35195 security fix
azure-identity>=1.18.0          # CAE support
azure-keyvault-secrets>=4.7.0
```

### Authentication

Scripts and flows should follow a managed-identity-first authentication pattern for production:

1. Prefer system-assigned or user-assigned managed identity for Azure-hosted automation, or workload identity federation for CI/CD.
2. Use certificate-backed app authentication where the connector or runtime supports it.
3. Use interactive authentication for one-off administrator workstations.
4. Use client secrets only as a legacy dev-only fallback; store them in Key Vault, never pass them on the command line, and rotate at least quarterly.

## Pre-Deployment Checklist

### Licensing

- [ ] Power Apps Premium licenses available
- [ ] Copilot Studio licenses available
- [ ] Power Automate Premium licenses available
- [ ] Azure subscription accessible

### Roles

- [ ] Application Administrator role assigned
- [ ] Power Platform Admin role assigned
- [ ] System Administrator role in governance environment
- [ ] Key Vault Secrets Officer role assigned

### Infrastructure

- [ ] Governance environment created and managed
- [ ] Azure Key Vault created
- [ ] Network connectivity verified
- [ ] DLP policies configured for governance environment

### Environment Groups

- [ ] FSI-Zone1-PersonalProductivity created
- [ ] FSI-Zone2-TeamCollaboration created
- [ ] FSI-Zone3-EnterpriseManagedEnvironment created
- [ ] DLP policies applied to each group

## Next Steps

After verifying prerequisites:

1. [Create Dataverse schema](./dataverse-schema.md)
2. [Configure security roles](./security-roles.md)
3. [Register Service Principal](./service-principal-setup.md)
