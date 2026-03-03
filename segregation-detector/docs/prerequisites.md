# Prerequisites

Complete requirements for deploying the Segregation of Duties Detector.

---

## Licensing Requirements

### Required

| License | Quantity | Purpose |
|---------|----------|---------|
| **Power Platform Premium** | Per flow creator | PowerShell detection scripts; Power Automate flows (planned) |
| **Dataverse capacity** | 500 MB minimum | Violation and rule storage |
| **Microsoft Entra ID P1** | Included with M365 E3+ | Role assignment queries |

### Recommended

| License | Purpose |
|---------|---------|
| **Microsoft Entra ID P2** | Privileged Identity Management integration |
| **Power BI Pro** | Advanced reporting dashboards |

---

## Permission Requirements

### Microsoft Entra ID Roles

| Role | Required For |
|------|--------------|
| **Global Reader** | Query directory role assignments |
| **Directory Readers** | Alternative for limited read access |

### Power Platform Roles

| Role | Required For |
|------|--------------|
| **Power Platform Administrator** | Query environment role assignments |
| **System Administrator** | Dataverse table creation and queries |

### Microsoft Graph API Permissions

| Permission | Type | Purpose |
|------------|------|---------|
| `RoleManagement.Read.Directory` | Application | Read Entra ID role assignments |
| `User.Read.All` | Application | Read user details |
| `Directory.Read.All` | Application | Read directory information |

---

## Service Principal Setup

### 1. Register Application

1. Navigate to **Microsoft Entra ID** > **App registrations**
2. Click **New registration**
3. Configure:
   - Name: `FSI-AgentGov-SoDDetector`
   - Supported account types: **Single tenant**
4. Click **Register**
5. Note the **Application (client) ID** and **Directory (tenant) ID**

### 2. Configure API Permissions

1. Go to **API permissions**
2. Click **Add a permission** > **Microsoft Graph**
3. Select **Application permissions**
4. Add:
   - `RoleManagement.Read.Directory`
   - `User.Read.All`
   - `Directory.Read.All`
5. Click **Grant admin consent**

### 3. Create Client Secret

1. Go to **Certificates & secrets**
2. Click **New client secret**
3. Configure:
   - Description: `SoDDetector-Secret`
   - Expiration: 24 months
4. Copy and store the secret value securely

### 4. Store in Azure Key Vault

```powershell
# Create secret in Key Vault
az keyvault secret set --vault-name "your-vault" --name "SoD-ClientSecret" --value "<secret-value>"
```

---

## Environment Requirements

### Dataverse Environment

| Requirement | Specification |
|-------------|---------------|
| **Type** | Production or Sandbox |
| **Capacity** | 500 MB minimum available |
| **Security Groups** | Configured for SoD roles |

### Power Platform Environment

| Requirement | Purpose |
|-------------|---------|
| **Managed Environment** | Enhanced governance features |
| **DLP Policies** | Allow required connectors |

---

## Network Requirements

### Firewall Allowlist

| Endpoint | Purpose |
|----------|---------|
| `graph.microsoft.com` | Microsoft Graph API (commercial) |
| `graph.microsoft.us` | Microsoft Graph API (GCC High) |
| `microsoftgraph.chinacloudapi.cn` | Microsoft Graph API (China / 21Vianet) |
| `*.crm.dynamics.com` | Dataverse |
| `*.api.powerplatform.com` | Power Platform API |
| `api.bap.microsoft.com` | Power Platform BAP API (commercial) |
| `api.bap.appsplatform.us` | Power Platform BAP API (US sovereign / GCC High) |
| `api.bap.partner.microsoftonline.cn` | Power Platform BAP API (China sovereign / 21Vianet) |
| `login.microsoftonline.com` | Authentication |

---

## Dependencies

### Required

| Solution | Version | Purpose |
|----------|---------|---------|
| None | - | Standalone deployment possible |

### Optional Integrations

| Solution | Version | Benefit |
|----------|---------|---------|
| Environment Lifecycle Management | v1.1.0+ | Environment context for violations |
| FINRA Supervision Workflow | v1.0.0+ | Supervision role validation |
| Conditional Access Automation | v1.0.0+ | Access policy enforcement |

---

## Validation Checklist

Before deployment, verify:

- [ ] Power Platform Premium license available
- [ ] Dataverse environment with sufficient capacity
- [ ] Service principal registered with required permissions
- [ ] Admin consent granted for Graph API permissions
- [ ] Client secret stored securely
- [ ] Network endpoints accessible
- [ ] User accounts have appropriate Dataverse security roles

---

## Next Steps

1. [Deploy Dataverse Schema](dataverse-schema.md)
2. [Configure Conflict Rules](conflict-rules.md)

---

*Segregation of Duties Detector v1.0.0*
