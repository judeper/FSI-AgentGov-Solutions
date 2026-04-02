# Prerequisites

Complete requirements for deploying the Agent 365 Lifecycle Governance solution.

## Licensing Requirements

| License | Requirement | Purpose |
|---------|------------|---------|
| **Microsoft Agent 365** | Required | Agent identity lifecycle management, sponsor assignment |
| **Entra ID Governance P2** | Required | Access reviews, lifecycle workflows |
| **Power Automate Premium** | Required | HTTP connector, Power Platform Admin connector |
| **Power Apps Premium** | Required (Admin Portal) | Canvas app for governance team |
| **Power BI Pro** | Required (Dashboard) | Lifecycle compliance reporting |

### License Notes

- **Microsoft Agent 365** is a standalone license ($15/user/month) or included in M365 E7
- **Entra ID Governance P2** is required for access review API creation and lifecycle workflows
- **Power Automate Premium** is required for the HTTP with Microsoft Entra ID (preauthorized) connector
- **Power BI Pro** is required only if deploying the optional compliance dashboard

## Entra ID Configuration

### Required Security Groups

Create these before deploying flows:

| Group Name | Purpose |
|-----------|---------|
| `FSI-AllAgentIdentities` | All agent identities — scope for Lifecycle Workflows 1 and 2 |
| `FSI-Zone3-Agents` | Zone 3 agents only — scope for Conditional Access policy |

### API Permissions (System-Assigned Managed Identity)

| Permission | Type | Scope | Purpose |
|-----------|------|-------|---------|
| `AgentRegistry.ReadWrite.All` | Application | Graph | Read/update agent identities and sponsors |
| `IdentityGovernance.ReadWrite.All` | Application | Graph | Create access reviews, trigger lifecycle workflows |
| `AuditLog.Read.All` | Application | Graph | Read agent sign-in logs for inactivity detection |
| `Application.ReadWrite.All` | Application | Graph | Disable and delete agent service principals |
| `User.Read.All` | Application | Graph | Validate sponsor accounts, resolve UPNs |
| `GroupMember.ReadWrite.All` | Application | Graph | Manage agent group membership |
| `PowerPlatform.Admin.ReadWrite.All` | Application | Power Platform | Read agent activity timestamps |

> **Note:** `AuditLog.Read.All` may be restricted in some FSI tenants. The solution handles this gracefully — inactivity detection falls back to PPAC timestamps when sign-in log access is unavailable.

### Entra Lifecycle Workflows

Two workflows must be created manually in the Entra Admin Center. See [Flow Configuration](./flow-configuration.md) for step-by-step configuration.

**Workflow 1: Agent-Sponsor-Mover-Notification**

- Template: Mover
- Scope: FSI-AllAgentIdentities group
- Trigger: Sponsor attribute change
- Store workflow ID in `SponsorMoverWorkflowId` environment variable

**Workflow 2: Agent-Sponsor-Leaver-Deactivation**

- Template: Leaver
- Scope: FSI-AllAgentIdentities group
- Trigger: Sponsor account disabled/deleted
- Store workflow ID in `SponsorLeaverWorkflowId` environment variable

### Conditional Access Policy (Zone 3 Only)

Create `FSI-Zone3-Agent-Conditional-Access` in Entra Admin Center:

- Assignments: FSI-Zone3-Agents group
- Grant: Compliant managed devices
- Session: Sign-in frequency 1 hour, continuous access evaluation enabled
- Note: Agent identities are exempt from MFA by default

## Dataverse Environment

| Requirement | Specification |
|-------------|---------------|
| **Environment Type** | Production (recommended) or Sandbox |
| **Managed Environment** | Required |
| **Dataverse Database** | Required |
| **System Administrator** | Required for schema deployment |
| **Long-Term Retention** | Required for 7-year SEC 17a-3/4 compliance |

> **Note:** Dataverse Long-Term Retention (LTR) is configured post-deployment via the Power Platform Admin Center. LTR is only available in Managed Environments.

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

- [ ] Microsoft Agent 365 licensing active in target tenant
- [ ] Entra ID Governance P2 licensing available
- [ ] Power Automate Premium licenses available
- [ ] Power Apps Premium licenses available (if deploying admin portal)
- [ ] Power BI Pro licenses available (if deploying dashboard)

### Entra ID

- [ ] `FSI-AllAgentIdentities` security group created
- [ ] `FSI-Zone3-Agents` security group created
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
