# Prerequisites

## Software Requirements

| Component | Version | Purpose |
|-----------|---------|---------|
| PowerShell | 7.1+ | Core scanning and governance scripts |
| Microsoft.PowerApps.Administration.PowerShell | 2.0.217+ | Power Platform environment and agent queries (`Add-PowerAppsAccount`, `Get-AdminPowerAppEnvironment`) |
| Python | 3.9+ | Dataverse schema setup and evidence export |
| Az.Accounts | 2.17.0+ (5.3.4 validated) | Dataverse token acquisition for compliance persistence and evidence export |
| Microsoft.Graph (helper-specific) | 2.36.1+ | Required for the separate CA/auth helpers; not used by the core connector scan |

**Host compatibility caveat:** These script/module versions are repository requirements, not a Microsoft support matrix. Microsoft's [PowerShell support article](https://learn.microsoft.com/en-us/power-platform/admin/powerapps-powershell#prerequisites-for-powershell) requires Windows PowerShell 5.x for the Power Apps modules and explicitly warns of incompatibility with PowerShell 6+. COD scripts require PowerShell 7 and use PowerShell 7-only operations. Do not assume a supported end-to-end host combination, or simply run these scripts in 5.1. Validate the exact module/host combination in an isolated lab; a supported-host migration requires implementation work beyond this documentation re-check.

## Licensing

- **Dataverse environment and appropriate use rights/capacity** — required for COD tables. Dataverse application users can be unlicensed; their access is controlled by assigned security roles, not an assumed "Power Platform per-user/per-app" SKU. See [application users](https://learn.microsoft.com/en-us/power-platform/admin/manage-application-users).
- **Teams access** — the notification connection needs access to the target team/channel. The [Teams connector](https://learn.microsoft.com/en-us/connectors/teams/) is Standard; it does not specify E3/E5 as the required SKU. Allow the Workflows app for adaptive-card posting actions.
- **Power Automate premium-connector use rights** — the Dataverse flows need an entitlement such as **Power Automate Premium** for the owner or **Process** capacity allocated to a solution-aware flow. Scheduling alone does not require Premium. Confirm the applicable licensing model with the [current license types](https://learn.microsoft.com/en-us/power-platform/admin/power-automate-licensing/types).
- **Microsoft Entra Workload ID Premium** — required to create or modify Conditional Access policies scoped to service principals. These policies do not cover managed identities or multitenant apps. See [workload-identity Conditional Access](https://learn.microsoft.com/en-us/entra/identity/conditional-access/workload-identity).

## Required Permissions

### Power Platform Administration

- **Power Platform Admin** or **Dynamics 365 Service Admin** role — required for cross-environment agent scanning
- **Environment-level System Administrator** — required for Dataverse table operations (schema creation, record read/write)

### Microsoft Entra ID

The core `Invoke-CredentialScan.ps1` / `Get-AgentConnectorScope.ps1` path does not call Microsoft Graph. The existing, separately executed `Get-WorkloadIdentityCAPolicy.ps1` and `Test-AgentAuthMethod.ps1` helpers do. Establish a Graph session separately; neither helper authenticates it for you.

| Permission | Type | Purpose (when running the Graph helpers) |
|-----------|------|---------|
| `Application.Read.All` | Delegated or Application | Read service principals, applications, and federated identity credentials |
| `Policy.Read.All` | Delegated or Application | Read Conditional Access policies for the CA helper |

`ServicePrincipal.Read.All` is not the permission listed by Microsoft for service-principal enumeration. For delegated CA reads, the signed-in user also needs a supported role such as Security Reader. Sources: [service principals](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list), [CA policies](https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-policies), [federated credentials](https://learn.microsoft.com/en-us/graph/api/application-list-federatedidentitycredentials).

### Service Principal Setup

1. Register an application in Microsoft Entra ID (requires Entra Global Admin or Application Administrator).
2. Register the application with Microsoft Power Platform using `New-PowerAppManagementApp -ApplicationId <appId>` from an administrator context. Microsoft Learn notes that a service principal cannot register itself and that Power Platform treats the registered app similarly to a Power Platform administrator for supported admin operations.
3. Grant Graph permissions only if running the separate Graph helpers (`Application.Read.All`, plus `Policy.Read.All` for CA inventory). The core scanner's Power Platform admin cmdlets do not require Graph scopes.
4. Prefer managed identity or workload federation where supported, then certificates. The current main scanner and connector extractor accept client secrets only: treat those paths as dev-only legacy, not a production-ready managed-identity implementation. Key Vault storage does not change this limitation. See [Microsoft credential guidance](https://learn.microsoft.com/en-us/entra/identity-platform/security-best-practices-for-app-registration#credentials-including-certificates-and-secrets).
5. Create an application user in each target Dataverse environment with the System Administrator role for Dataverse table operations.

### Network Endpoints

The following endpoints must be accessible from the execution environment:

| Endpoint | Purpose |
|----------|---------|
| `api.powerplatform.com` | Power Platform admin API |
| `api.bap.microsoft.com` | Business Application Platform API |
| `*.crm.dynamics.com` | Dataverse Web API |
| `graph.microsoft.com` | Microsoft Graph (optional, for Entra queries) |

## Environment Lifecycle Management Integration

If using the Environment Lifecycle Management (ELM) solution, zone classification is read from the `fsi_environments` Dataverse table automatically. Otherwise, environments resolve to `Unknown` zone and policy is applied per the `Unknown` entry in `templates/zone-credential-policy.json`. (Naming-convention fallback heuristics are not implemented in this version — use ELM or pre-populate `fsi_environments` for accurate zone resolution.)

## Important Notes

- The Microsoft "Enforce safe sharing by detecting credential oversharing" feature is listed on the [AI at Work roadmap](https://www.microsoft.com/en-us/microsoft-365/roadmap?searchterms=566873) as In development (ID 566873; preview target July 2026, general availability target September 2026; checked 2026-10-16). Public availability is not confirmed. This roadmap does not document an OAuth-scope extraction API; validate the extractor's expected configuration fields independently.
- Preview features may have different security, compliance, and data residency commitments. Review Microsoft Power Platform preview terms.
- This solution supports compliance with FINRA Rule 4511(a) record-keeping and OCC 2011-12 operational risk requirements but does not provide regulatory compliance on its own. Organizations should verify configuration helps meet their specific obligations.
