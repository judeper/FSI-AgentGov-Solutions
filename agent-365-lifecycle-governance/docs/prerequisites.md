# Prerequisites

Complete requirements for deploying the Agent 365 Lifecycle Governance solution.

## Licensing Requirements

| License | Requirement | Purpose |
|---------|------------|---------|
| **Microsoft Agent 365** | Required | Agent registry visibility, owner assignment, and Agent ID capabilities |
| **Microsoft Entra ID Governance or Microsoft Entra Suite** | Required | Access reviews and sponsor-user lifecycle workflows |
| **Power Automate Premium** | Required | HTTP connector, Power Platform Admin connector |
| **Power Apps Premium** | Required (Admin Portal) | Canvas app for governance team |
| **Power BI Pro** | Required (Dashboard) | Lifecycle compliance reporting |

### License Notes

- **Microsoft Agent 365** is licensed on a per-user basis; verify current pricing and included SKU eligibility in the Microsoft Agent 365 licensing FAQ. Microsoft Entra Agent ID features are available with Microsoft Agent 365 or Microsoft 365 E7, with additional Entra licensing depending on feature.
- **Microsoft Entra ID Governance or Microsoft Entra Suite** is required for access review API creation and lifecycle workflows; Microsoft Entra ID P2, Microsoft 365 E5, or Microsoft Entra Suite may be required for specific Agent ID governance features.
- **Power Automate Premium** is required for the HTTP with Microsoft Entra ID (preauthorized) connector
- **Power BI Pro** is required only if deploying the optional compliance dashboard

## Entra ID Configuration

### Required Security Groups

Create these before deploying flows:

| Group Name | Purpose |
|-----------|---------|
| `FSI-AgentSponsors` | Sponsor users — scope for Lifecycle Workflows 1 and 2 |
| `FSI-AllAgentIdentities` | All agent identities — inventory and group-based reporting, not lifecycle workflow scope |
| `FSI-Zone3-Agents` | Zone 3 agent identities — inventory/reporting; Conditional Access for workload identities must directly assign service principals |

### API Permissions (Automation Identity)

| Permission | Type | Scope | Purpose |
|-----------|------|-------|---------|
| `AgentInstance.ReadWrite.All` | Application | Graph beta | Read/update Agent 365 agent instances and `ownerIds` through `/agentRegistry/agentInstances` |
| `AccessReview.ReadWrite.All` | Application | Graph | Required for `POST /identityGovernance/accessReviews/definitions` (access review CRUD) |
| `LifecycleWorkflows.ReadWrite.All` | Application | Graph | Required for activating Entra ID Governance lifecycle workflows (`POST /identityGovernance/lifecycleWorkflows/workflows/{id}/activate`) — `LifecycleWorkflows-Workflow.Activate` is also acceptable for activate-only scenarios |
| `AuditLog.Read.All` | Application | Graph | Read agent sign-in logs for inactivity detection |
| `Application.ReadWrite.All` | Application | Graph | Disable and delete agent service principals |
| `User.Read.All` | Application | Graph | Validate sponsor accounts, resolve UPNs |
| `GroupMember.ReadWrite.All` | Application | Graph | Manage agent group membership |
| `PowerPlatform.Admin.ReadWrite.All` | Application | Power Platform | Read agent activity timestamps |

> **Note:** `AuditLog.Read.All` may be restricted in some FSI tenants. The solution handles this gracefully — inactivity detection falls back to PPAC timestamps when sign-in log access is unavailable.

> **Note:** All application permissions require admin consent and must be granted to the automation identity (managed identity, workload identity, or certificate-backed app registration). The previously documented `IdentityGovernance.ReadWrite.All` is a broader legacy scope; the more specific `AccessReview.ReadWrite.All` + `LifecycleWorkflows.ReadWrite.All` pair is preferred per Microsoft Graph guidance. The older `AgentRegistry.ReadWrite.All` permission is not documented for the current `agentInstances` API surface; use `AgentInstance.ReadWrite.All` for this solution's Graph beta calls.

### Entra Lifecycle Workflows

> **Important — applicability:** Entra ID Governance lifecycle workflows operate against **user** principals (joiner/mover/leaver), not service principals or agent identities. The workflows below are intended to fire on **sponsor user** lifecycle events (a sponsor moving departments or leaving the company), not on the agent identity itself. Flow 5 then reads the sponsor change and updates the agent's lifecycle record. Do not attempt to scope a lifecycle workflow directly to an agent service principal.

Two workflows must be created manually in the Microsoft Entra admin center. See [Flow Configuration](./flow-configuration.md) for step-by-step configuration.

**Workflow 1: Agent-Sponsor-Mover-Notification**

- Template: Mover
- Scope: Sponsor users (for example, the `FSI-AgentSponsors` security group)
- Trigger: Sponsor user attribute change (department/manager move)
- Store workflow ID in `fsi_ALG_SponsorMoverWorkflowId` environment variable

**Workflow 2: Agent-Sponsor-Leaver-Deactivation**

- Template: Leaver
- Scope: Sponsor users (for example, the `FSI-AgentSponsors` security group)
- Trigger: Sponsor user account disabled/deleted
- Store workflow ID in `fsi_ALG_SponsorLeaverWorkflowId` environment variable

### Conditional Access Policy (Zone 3 Only) — Workload Identity policy

> **Important:** Agent identities are **service principals / workload identities**, not user accounts. Standard user-targeted Conditional Access policies do **not** apply to service principals, and group assignment is **not enforced** for workload identities (see [Microsoft docs — Conditional Access for workload identities](https://learn.microsoft.com/en-us/entra/identity/conditional-access/workload-identity)). Use a **Conditional Access policy for workload identities** and assign the policy directly to the `FSI-Zone3-Agents` service principals.

Create `FSI-Zone3-Agent-Conditional-Access` in Entra Admin Center as a **workload identity** Conditional Access policy:

- License: requires the **Workload Identities Premium** add-on license.
- Assignments: select **Workload identities** and pick the Zone 3 service principals directly (group assignment is not enforced for service principals — pick them individually or maintain the list as part of onboarding).
- Conditions: scope by location and (optionally) service-principal risk.
- Grant: **Block access** is the available grant control for service-principal Conditional Access policies. Device-compliance, multifactor authentication, and sign-in-frequency controls are user-session controls and **do not apply** to service-principal sign-ins.

## Dataverse Environment

| Requirement | Specification |
|-------------|---------------|
| **Environment Type** | Production (recommended) or Sandbox |
| **Managed Environment** | Required |
| **Dataverse Database** | Required |
| **System Administrator** | Required for schema deployment |
| **Long-Term Retention** | Recommended; configure per the firm's record schedule (FINRA 4511 / SEC 17a-4 retention varies by record category — typically 3 years for communications, 6 years for books and records). |

> **Note:** Dataverse Long-Term Retention (LTR) is configured post-deployment via the Power Platform Admin Center. LTR is only available in Managed Environments. LTR alone is not equivalent to a SEC 17a-4-compliant electronic recordkeeping system; firms should validate format/storage requirements with legal/compliance and use a compliant archive where required.

## Network Requirements

### Outbound Connectivity

The solution requires outbound access to:

| Endpoint | Purpose |
|----------|---------|
| `graph.microsoft.com` | Microsoft Graph API (agent identities, sponsors, access reviews) |
| `*.dynamics.com` | Dataverse Web API |
| `api.bap.microsoft.com` | Power Platform Admin API (agent activity timestamps) |
| `login.microsoftonline.com` | Entra ID authentication |

### Firewall Considerations

If running scripts from on-premises or restricted networks:

1. Whitelist Microsoft 365 and Azure service tags
2. Allow HTTPS (443) outbound
3. Verify Graph beta endpoints are not blocked by network inspection policies

## Cross-Solution Dependencies

| Dependency | Solution | Purpose |
|-----------|----------|---------|
| `fsi_environment_policy` table | agent-registry-automation | Zone detection for new agents |

If the `agent-registry-automation` solution is not deployed, zone detection defaults to Zone 2 for all agents.

## DLP Policy Considerations

### Connectors Required

The lifecycle governance flows require these connectors in the Business/Non-Blockable group:

| Connector | Purpose |
|-----------|---------|
| **Dataverse** | Read/write lifecycle records, compliance events |
| **HTTP with Microsoft Entra ID** | Graph API, PPAC API calls |
| **Approvals** | Deactivation approval workflow |
| **Microsoft Teams** | Sponsor notifications, adaptive cards |
| **Office 365 Outlook** | Email notifications (optional) |

## Pre-Deployment Checklist

### Licensing

- [ ] Microsoft Agent 365 licensing active in target tenant; current pricing/SKU eligibility verified
- [ ] Microsoft Entra ID Governance or Microsoft Entra Suite licensing available
- [ ] Power Automate Premium licenses available
- [ ] Power Apps Premium licenses available (if deploying admin portal)
- [ ] Power BI Pro licenses available (if deploying dashboard)

### Entra ID

- [ ] `FSI-AgentSponsors` security group created and populated with sponsor users
- [ ] `FSI-AllAgentIdentities` security group created
- [ ] `FSI-Zone3-Agents` security group created for inventory/reporting
- [ ] Zone 3 service principals assigned directly to workload identity Conditional Access policy
- [ ] All 7 API permissions granted and admin-consented
- [ ] Lifecycle Workflow 1 created — workflow ID recorded
- [ ] Lifecycle Workflow 2 created — workflow ID recorded
- [ ] Conditional Access policy created (Zone 3)

### Infrastructure

- [ ] Governance environment created and managed
- [ ] Dataverse database provisioned
- [ ] Network connectivity verified to all required endpoints
- [ ] DLP policies configured for governance environment

## Next Steps

After verifying prerequisites:

1. [Deploy Dataverse schema](./dataverse-schema.md)
2. [Configure flows](./flow-configuration.md)
3. [Build admin portal](./canvas-app-guide.md) (optional)
4. [Build compliance dashboard](./power-bi-dashboard.md) (optional)
