# Prerequisites

Complete requirements for deploying the FINRA Supervision Workflow solution.

## Licensing Requirements

### Required Licenses

| License | Purpose | Users |
|---------|---------|-------|
| Power Apps Premium | Dataverse tables, model-driven app | Queue Managers, Admins |
| Power Automate Premium | HTTP connector, scheduled flows | Service account |
| Microsoft 365 E5 Compliance | Communication Compliance | Compliance Admins |

### Optional Licenses

| License | Purpose | Users |
|---------|---------|-------|
| Power BI Pro | Supervision dashboard | Queue Managers, CCO |
| Power BI Premium | Embedded dashboards | Organization-wide |

### License Verification

```powershell
# Check user licenses
Get-MgUserLicenseDetail -UserId user@domain.com |
    Select-Object SkuPartNumber
```

Expected output should include:
- `POWERAPPS_VIRAL` or `POWERAPPS_PER_USER`
- `FLOW_P2` or `POWERAUTOMATE_ATTENDEDUSER`
- `SPE_E5` or `M365_E5_COMPLIANCE`

---

## Role Requirements

### Deployment Roles

| Role | Platform | Purpose |
|------|----------|---------|
| Power Platform Admin | PPAC | Environment and DLP management |
| System Administrator | Dataverse | Table and security role creation |
| Purview Compliance Admin | Purview | Communication Compliance access |
| Application Administrator | Entra ID | App registration for service principal |

### Operational Roles

| Role | Platform | Purpose |
|------|----------|---------|
| FSW Supervisor | Dataverse | Review queue items |
| FSW Queue Manager | Dataverse | Manage queue and assignments |
| FSW Admin | Dataverse | Full administration |
| FSW Auditor | Dataverse | Read-only audit access |

### Role Verification

```powershell
# Check Entra ID role assignments
Get-MgDirectoryRoleMember -DirectoryRoleId <role-id> |
    Select-Object DisplayName, UserPrincipalName

# Check Dataverse security roles
# Use Power Platform Admin Center > Environments > [Env] > Settings > Users + permissions
```

---

## Environment Requirements

### Dataverse Environment

| Requirement | Specification |
|-------------|---------------|
| Environment type | Production or Sandbox |
| Dataverse database | Required (provisioned) |
| Region | Must match compliance requirements |
| Managed Environment | Recommended for Zone 3 |

### Capacity Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| Dataverse storage | 1 GB | 5 GB |
| File storage | 500 MB | 2 GB |
| Log storage | 1 GB | 5 GB |

### Environment Creation

If creating a new environment:

1. Open Power Platform admin center
2. Environments > + New
3. Configure:
   - Name: `FSI-Supervision-Prod`
   - Type: Production
   - Region: United States
   - Create database: Yes
   - Enable Dynamics 365 apps: No

---

## API and Connector Requirements

### Microsoft Graph API

| Permission | Type | Purpose |
|------------|------|---------|
| `User.Read.All` | Application | Look up supervisor users |

### Microsoft Purview

| Permission | Type | Purpose |
|------------|------|---------|
| Compliance Administrator | Role | Read Communication Compliance alerts (see [communication-compliance-setup.md](./communication-compliance-setup.md)) |

### Power Platform API

| Permission | Type | Purpose |
|------------|------|---------|
| Environment access | Delegated | Create Dataverse records |

### Connectors Required

| Connector | License | Purpose |
|-----------|---------|---------|
| Dataverse | Premium | Queue and log tables |
| HTTP with Azure AD | Premium | Graph API calls |
| Office 365 Outlook | Standard | Email notifications |
| Microsoft Teams | Standard | Teams notifications |
| Azure Key Vault | Premium | Credential storage |

---

## Azure Requirements

### Azure Key Vault

Required for secure credential storage:

| Secret | Purpose |
|--------|---------|
| `FSW-ServicePrincipal-ClientId` | App registration client ID |
| `FSW-ServicePrincipal-ClientSecret` | App registration secret |
| `FSW-LastRunTime` | Polling state storage |

### Key Vault Configuration

1. Create or identify existing Key Vault
2. Configure access:
   - Power Automate managed identity: Get, List secrets
   - Deployment account: Set, Get, List secrets
3. Enable soft delete and purge protection

```bash
# Create Key Vault (if needed)
az keyvault create \
    --name fsw-credentials-kv \
    --resource-group rg-fsi-governance \
    --location eastus \
    --enable-soft-delete true \
    --enable-purge-protection true
```

---

## Network Requirements

### Outbound Connectivity

| Endpoint | Port | Purpose |
|----------|------|---------|
| `graph.microsoft.com` | 443 | Microsoft Graph API |
| `compliance.microsoft.com` | 443 | Purview Communication Compliance API |
| `*.crm.dynamics.com` | 443 | Dataverse API |
| `*.azure-api.net` | 443 | Power Platform connectors |
| `login.microsoftonline.com` | 443 | Entra ID authentication |

### Firewall Rules

If using Azure Firewall or third-party firewall, allow:

```
*.dynamics.com:443
*.crm.dynamics.com:443
graph.microsoft.com:443
compliance.microsoft.com:443
login.microsoftonline.com:443
*.azure-api.net:443
```

---

## Dependency Services

### Communication Compliance

This solution requires active Communication Compliance policies:

1. Navigate to Microsoft Purview compliance portal
2. Communication Compliance > Policies
3. Ensure policy exists targeting AI agent communications
4. Note the policy ID for flow configuration

See [communication-compliance-setup.md](./communication-compliance-setup.md) for detailed setup.

### Audit Logging

Ensure audit logging is enabled:

1. Microsoft Purview > Audit
2. Verify "Start recording user and admin activity" is enabled
3. Check CopilotInteraction events are being captured

### Control Dependencies

| Control | Requirement | Verification |
|---------|-------------|--------------|
| 1.7 (Audit Logging) | Enabled, capturing agent events | Check Purview Audit |
| 1.10 (Communication Compliance) | Policy targeting agents | Check Purview CC |
| 2.12 (Supervision) | WSP documents AI supervision | Review WSP |

---

## Pre-Deployment Checklist

### Licensing
- [ ] Power Apps Premium licenses assigned
- [ ] Power Automate Premium licenses assigned
- [ ] Microsoft 365 E5 Compliance active
- [ ] Power BI Pro (if using dashboard)

### Roles
- [ ] Power Platform Admin access confirmed
- [ ] System Administrator in target environment
- [ ] Purview Compliance Admin access
- [ ] Entra ID Application Administrator

### Environment
- [ ] Target Dataverse environment identified
- [ ] Adequate storage capacity
- [ ] Managed Environment enabled (Zone 3)

### Azure
- [ ] Key Vault created/identified
- [ ] Access policies configured
- [ ] Service principal created

### Network
- [ ] Outbound connectivity verified
- [ ] Firewall rules configured

### Dependencies
- [ ] Communication Compliance policy active
- [ ] Audit logging enabled
- [ ] Supervisor principals identified

---

## Estimated Deployment Time

| Phase | Duration | Activities |
|-------|----------|------------|
| Prerequisites | 2-4 hours | Licensing, roles, Key Vault |
| Schema deployment | 30 minutes | Run deploy.py |
| Flow creation | 2-4 hours | Create and configure 4 flows |
| Configuration | 1-2 hours | Supervision rules, assignments |
| Testing | 2-4 hours | End-to-end validation |
| **Total** | **8-14 hours** | Across 1-2 days |
