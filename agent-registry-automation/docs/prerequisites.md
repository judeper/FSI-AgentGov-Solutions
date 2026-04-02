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

### Entra Agent Registry API (Optional — Flow 3)

If enabling Flow 3 (Entra Sync), additional permissions may be required:

| Permission | Type | API | Purpose |
|------------|------|-----|---------|
| `AgentRegistration.ReadWrite.All` | Application | Microsoft Graph (beta) | Register agents in Entra Agent Registry |

> **Note:** The Entra Agent Registry API is subject to change. Confirm required permissions and API availability before enabling Flow 3.

---

## Service Principal Setup

### Step 1: Register Application

1. Navigate to **Entra ID** > **App registrations** > **New registration**
2. Name: `Agent Registry Automation`
3. Supported account type: **Single tenant**
4. Click **Register**

### Step 2: Grant API Permissions

1. Navigate to **API permissions** > **Add a permission**
2. Add each permission listed in the API Permissions section above
3. Click **Grant admin consent** (requires Entra Global Admin)

### Step 3: Create Client Secret

1. Navigate to **Certificates & secrets** > **New client secret**
2. Description: `Agent Registry Automation — Production`
3. Expiration: Choose based on your organization's rotation policy
4. **Copy the secret value** — it is only shown once

> **Security:** For production deployments, use certificate-based authentication or Managed Identity instead of client secrets. If using client secrets, store them in Azure Key Vault and reference them via environment variable **Secret** type with Key Vault backing.

### Step 4: Record Application Details

Save these values for environment variable configuration:

| Value | Where to Find |
|-------|---------------|
| **Application (client) ID** | App registration > Overview |
| **Directory (tenant) ID** | App registration > Overview |
| **Client secret** | Certificates & secrets (copy at creation time) |

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
| `graph.microsoft.com` | HTTPS (443) | User status checks and Entra Agent Registry |
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
- [ ] Client secret created and stored securely
- [ ] DLP policies allow required connectors
- [ ] Microsoft Teams channel configured for notifications
- [ ] Microsoft Entra ID P1/P2 available (for full orphan detection)
- [ ] Network connectivity to required endpoints verified

---

*Agent Registry Automation v1.0.0 — FSI Agent Governance Framework*
