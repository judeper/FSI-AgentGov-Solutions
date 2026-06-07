# Prerequisites

Complete requirements for deploying the Segregation of Duties Detector.

---

## Licensing Requirements

### Required

| License | Quantity | Purpose |
|---------|----------|---------|
| **Power Platform admin access** | Per operator or workload identity | Environment and role enumeration for detection scripts |
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
| `RoleAssignmentSchedule.Read.Directory` | Application | Read active Entra role assignment schedule instances, including active PIM assignments |
| `RoleManagement.Read.Directory` | Application | Read Entra role definitions and higher-privilege role management data |
| `User.Read.All` | Application | Read expanded user details when Graph returns principals |
| `Directory.Read.All` | Application | Read directory information and expanded principals |
| `RoleEligibilitySchedule.Read.Directory` | Application | Optional: read PIM-eligible assignments for an extended eligibility scan |

---

## Authentication setup (managed-identity-first)

Use the strongest authentication mode available in the runtime. The scripts accept `-AuthMode ManagedIdentity`, `-AuthMode WorkloadIdentity`, or `-AuthMode ClientSecret`.

### Option A — Managed identity (recommended for Azure-hosted runs)

1. Enable a system-assigned or user-assigned managed identity on the Azure Automation account, Function, VM, or hosted runner.
2. Grant the identity the Microsoft Graph application permissions listed above and admin consent.
3. Register the identity for Power Platform administration when it calls the BAP admin API:

```powershell
Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
Add-PowerAppsAccount
New-PowerAppManagementApp -ApplicationId <managed-identity-client-id>
```

4. Run the scanner. For a system-assigned identity, omit `-ManagedIdentityClientId`; for a user-assigned identity, pass its client ID or set `MANAGED_IDENTITY_CLIENT_ID`.

```powershell
.\scripts\Invoke-SoDScan.ps1 -Environment "https://your-org.crm.dynamics.com" -AuthMode ManagedIdentity
```

### Option B — Workload identity federation (recommended for CI)

1. Configure a federated identity credential on the app registration or user-assigned managed identity used by the pipeline.
2. Set `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_FEDERATED_TOKEN_FILE` in the runner environment.
3. Register the app or identity for Power Platform administration with `New-PowerAppManagementApp -ApplicationId <client-id>`.
4. Run the scanner with `-AuthMode WorkloadIdentity`.

```powershell
.\scripts\Invoke-SoDScan.ps1 -Environment "https://your-org.crm.dynamics.com" -AuthMode WorkloadIdentity
```

### Option C — Client secret (legacy dev-only fallback)

Client secrets are not recommended for production. Use this only for local development when managed identity and workload identity federation are unavailable. Mark any local automation using this mode as legacy and rotate the secret according to organizational policy.

```powershell
# legacy: dev-only — replace with managed identity in production
$env:AZURE_TENANT_ID = "<tenant-id>"
$env:AZURE_CLIENT_ID = "<app-client-id>"
$env:FSI_CLIENT_SECRET = "<client-secret>"
.\scripts\Invoke-SoDScan.ps1 -Environment "https://your-org.crm.dynamics.com" -AuthMode ClientSecret
```

Reference: [Use service principal accounts to connect to Power Platform](https://learn.microsoft.com/en-us/power-platform/admin/powershell-create-service-principal).

### Power Platform BAP token audience

The scanner queries Power Platform environment role assignments through the BAP admin REST API
(`api.bap.microsoft.com`). The OAuth **resource (audience)** for these
calls is the first-party **Power Apps Service** resource `https://service.powerapps.com/`
(Application ID `475226c6-020e-4fb2-8a90-7a972cbfc1d4`) — the request host is *not* the audience.
`Invoke-SoDScan.ps1` derives this automatically. If
token acquisition fails with `AADSTS500011`, override the audience with `-BapResource` or the
`FSI_BAP_RESOURCE` environment variable. Reference:
[Power Platform programmability authentication](https://learn.microsoft.com/en-us/power-platform/admin/programmability-authentication).

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
| `graph.microsoft.com` | Microsoft Graph API |
| `*.crm.dynamics.com` | Dataverse |
| `*.api.powerplatform.com` | Power Platform API |
| `api.bap.microsoft.com` | Power Platform BAP API |
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

- [ ] Power Platform admin access available for the operator or workload identity
- [ ] Dataverse environment with sufficient capacity
- [ ] Managed identity or federated workload identity registered with required permissions
- [ ] Admin consent granted for Graph API permissions
- [ ] ClientSecret mode avoided in production; any legacy dev secret is stored and rotated according to organizational policy
- [ ] Network endpoints accessible
- [ ] User accounts have appropriate Dataverse security roles

---

## Next Steps

1. [Deploy Dataverse Schema](dataverse-schema.md)
2. [Configure Conflict Rules](conflict-rules.md)

---

*Segregation of Duties Detector v1.2.1*
