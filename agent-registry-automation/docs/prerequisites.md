# Prerequisites

Requirements for deploying the Agent Registry Automation solution.

---

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows with HTTP and Dataverse connectors |
| **Dataverse capacity** | Agent inventory, compliance events, and audit storage |
| **Managed Environment** | Required for Dataverse Long-Term Retention (LTR) |
| **Microsoft 365 E3+** | Microsoft Teams notifications, Graph API access |
| **Microsoft Entra ID P1/P2** | `signInActivity` property in Graph API for orphan detection (Flow 4) |

> **Note:** Microsoft Entra ID P1/P2 is required for the `signInActivity` property used by Flow 4 to detect inactive owners. Without this license, orphan detection is limited to account-enabled and account-existence checks. The flow handles this gracefully by skipping the inactivity check when `signInActivity` is not available.

---

## Tooling Versions

Install or update the supporting admin tooling on workstations used for validation:

```powershell
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -RequiredVersion 2.0.217 -Scope CurrentUser
Install-Module -Name Microsoft.PowerApps.PowerShell -RequiredVersion 1.0.45 -AllowClobber -Scope CurrentUser
Install-Module -Name Microsoft.Graph -RequiredVersion 2.36.1 -Scope CurrentUser
Install-Module -Name Az.Accounts -RequiredVersion 5.3.4 -Scope CurrentUser
pac --version
```

Install or update the Power Platform CLI using the current Microsoft Learn installation path for your workstation, then verify with `pac --version`.

Use `Get-AdminPowerApp`, `Get-AdminFlow`, and `pac copilot list --environment <environmentId-or-url>` as supplementary validation checks. The primary automated discovery path remains the Power Platform API because tenant-wide Copilot Studio agent inventory requires API-based environment enumeration.

---

## Permissions

### Microsoft Entra ID Roles

| Role | Required For |
|------|--------------|
| **Power Platform Admin** | Environment enumeration and Bots API access |
| **Entra Global Admin** or **Application Administrator** | Service principal registration and API permission grants |

### Power Platform Roles

| Role | Required For |
|------|--------------|
| **System Administrator** | Dataverse table creation and schema deployment |
| **Environment Maker** | Power Automate flow creation |

---

## API Permissions

### App Registration: Agent Registry Automation

Register a Microsoft Entra ID application with the following permissions:

| Permission | Type | API | Purpose |
|------------|------|-----|---------|
| `Environment.Read.All` | Application | Power Platform API | Enumerate environments for discovery |
| `Bot.Read.All` | Application | Power Platform API | Read bot registrations via Bots API |
| `User.Read.All` | Application | Microsoft Graph | Check owner account status for orphan detection |
| `Directory.Read.All` | Application | Microsoft Graph | Read user department and manager information |
| `AuditLog.Read.All` | Application | Microsoft Graph | Read sign-in activity for inactivity detection |

> **Note:** All permissions require **admin consent** from an Entra Global Admin.

### Microsoft Entra Agent ID API (Optional — Flow 3)

Flow 3 is feature-flagged because Microsoft Entra Agent ID for Copilot Studio is currently preview. Before enabling it, confirm the current Microsoft Graph beta endpoint and permission names in your tenant. Current Microsoft Learn Agent ID terminology uses agent identity blueprints, blueprint principals, agent identities, and agent users; avoid hard-coding legacy `AgentRegistration.*` permission names.

> **Note:** Do not enable Flow 3 in production until your Microsoft 365 tenant exposes the required Agent ID API permissions and the governance team validates licensing for Microsoft Agent 365 or Microsoft 365 E7.

---

## Identity and Authentication Setup

### Step 1: Choose the strongest available credential

Use this priority order for automation credentials:

1. **System-assigned managed identity** for Azure Automation, Azure Functions, or Azure-hosted runners.
2. **User-assigned managed identity** when multiple workloads share the same governance identity.
3. **Workload identity federation** for CI/CD runners such as GitHub Actions OIDC.
4. **Certificate-based app-only authentication** for admin workstations or hosted jobs that cannot use managed identity.
5. **Client secret** only as a legacy development fallback; do not use it as the production default.

### Step 2: Register Application (certificate or workload identity paths)

1. Navigate to **Microsoft Entra ID** > **App registrations** > **New registration**.
2. Name: `Agent Registry Automation`.
3. Supported account type: **Single tenant**.
4. Select **Register**.

### Step 3: Grant API Permissions

1. Navigate to **API permissions** > **Add a permission**.
2. Add each permission listed in the API Permissions section above.
3. Select **Grant admin consent** (requires Entra Global Admin).

### Step 4: Configure credentials

| Credential path | Configuration |
|-----------------|---------------|
| Managed identity | Assign the identity to the Azure host and grant Power Platform/Dataverse roles to that identity. No secret or certificate is required. |
| Workload identity federation | Add a federated credential to the app registration for the CI/CD issuer, subject, and audience. Set `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_FEDERATED_TOKEN_FILE` for deployment jobs. |
| Certificate auth | Upload the public certificate to **Certificates & secrets** > **Certificates** and provide the PEM private-key path plus thumbprint to the deployment scripts. |
| Legacy client secret | Development fallback only. Store in Azure Key Vault or a secure secret store and rotate per policy. |

### Step 5: Record Application Details

Save these values for environment variable configuration as applicable:

| Value | Where to Find |
|-------|---------------|
| **Application (client) ID** | App registration > Overview (certificate/workload identity paths) |
| **Directory (tenant) ID** | App registration > Overview |
| **Certificate thumbprint** | App registration > Certificates & secrets > Certificates |
| **Managed identity client ID** | Managed identity resource > Overview (user-assigned only) |

---

## Environment Requirements

### Managed Environment

The target environment **must** be a Managed Environment. This is required for:

- Dataverse Long-Term Retention (LTR) on the `fsi_agentcomplianceevent` table
- Enhanced governance controls
- Solution management capabilities

**To enable Managed Environment:**

1. Navigate to **Power Platform Admin Center** > **Environments**
2. Select the target environment > **Edit**
3. Enable **Managed Environment**
4. Save changes

> **Note:** Enabling Managed Environment may affect existing flows and apps. Review the [Microsoft documentation](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview) for implications before enabling.

### Dataverse Long-Term Retention

After deploying the Dataverse schema, enable LTR on the `fsi_agentcomplianceevent` table:

1. Navigate to **Power Apps** > **Tables** > **Agent Compliance Events**
2. Select **Properties** > **Advanced options**
3. Enable **Long-term retention**
4. Configure retention policy (recommended: 7 years for SEC 17a-3/4)

---

## DLP Policy Considerations

The following connectors are used by the solution's Power Automate flows. Verify that your organization's DLP policies allow these connectors in the target environment:

| Connector | Used By | Classification |
|-----------|---------|---------------|
| **Dataverse** | All flows | Must be in **Business** group |
| **HTTP with Microsoft Entra ID** | Flows 1, 3, 4 | Must be in **Business** group |
| **Microsoft Teams** | Flows 1, 2, 4 | Must be in **Business** group |
| **Approvals** | Flow 2 | Must be in **Business** group |
| **Office 365 Users** | Flow 2 (SLA calculation) | Must be in **Business** group |

> **Note:** The flow uses calendar days for SLA calculation by default. For business-day calculation, use the Office 365 Users connector to determine the approver's time zone and exclude weekends. If DLP policies block the Office 365 Users connector, the flow falls back to the `fsi_ARA_DefaultTimeZone` environment variable.

---

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `api.powerplatform.com` | HTTPS (443) | Bots API and environment enumeration |
| `graph.microsoft.com` | HTTPS (443) | User status checks and Microsoft Entra Agent ID |
| `login.microsoftonline.com` | HTTPS (443) | OAuth 2.0 authentication |
| `*.crm.dynamics.com` | HTTPS (443) | Dataverse API operations |

> **Note:** For GCC, GCC High, and DoD environments, substitute the appropriate sovereign cloud endpoints.

---

## Validation Checklist

- [ ] Power Platform Premium license available for flow creator
- [ ] Target environment is a Managed Environment
- [ ] Dataverse capacity is sufficient
- [ ] Microsoft Entra ID application registered with required permissions
- [ ] Admin consent granted for all API permissions
- [ ] Managed identity, workload identity federation, or certificate credential configured; client secret documented only if a legacy development fallback is approved
- [ ] DLP policies allow required connectors
- [ ] Microsoft Teams channel configured for notifications
- [ ] Microsoft Entra ID P1/P2 available (for full orphan detection)
- [ ] Network connectivity to required endpoints verified

---

*Agent Registry Automation v2.1.0 — FSI Agent Governance Framework*
