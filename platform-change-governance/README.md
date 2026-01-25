# Platform Change Governance Solution

Pre-built Power Platform solution for Microsoft Message Center change governance in regulated financial services environments.

## Prerequisites (Read First)

**These requirements will block your deployment if not addressed:**

### 1. DLP Policy - HTTP Connector

The Message Center Ingestion flow uses the **HTTP connector** to call Microsoft Graph API. In most FSI environments, DLP policies block HTTP by default.

**Before importing:**

1. Go to Power Platform Admin Center → Data policies
2. Locate the policy applied to your target environment
3. Add `graph.microsoft.com` to the HTTP connector's allowed endpoints
4. Or move HTTP connector to the "Business" group (if Graph is pre-approved)

Without this, the ingestion flow will fail silently or be blocked from creation.

### 2. Solution Checker (Managed Environments)

If your target environment is a **Managed Environment** with Solution Checker enforcement:

- **Block mode:** Import will fail if checker finds issues
- **Warn mode:** Import proceeds but logs warnings

This solution has been tested with Solution Checker. If import fails:

1. Check the import log for specific checker errors
2. Review [Solution Checker documentation](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/use-powerapps-checker)

### 3. Required Permissions

- **Power Platform:** Environment Maker or System Customizer role
- **Azure AD:** Application Administrator (to create app registration)
- **Graph API:** Grant `ServiceMessage.Read.All` to app registration

---

## What's Included

- **3 Tables:** MessageCenterPost, AssessmentLog, DecisionLog
- **4 Security Roles:** MC Admin, MC Owner, MC Compliance Reviewer, MC Auditor
- **1 Model-Driven App:** Message Center Governance
- **1 Business Process Flow:** 5-stage governance workflow
- **2 Environment Variables:** MCG_TenantId, MCG_PollingInterval

---

## Quick Start

1. **Verify prerequisites** above (DLP, Solution Checker, permissions)
2. **Download** `MessageCenterGovernance_1_0_0_0.zip` from this folder
3. **Import** at [make.powerapps.com](https://make.powerapps.com) → Solutions → Import
4. **Configure connections** when prompted during import
5. **Set environment variables:**
   - `MCG_TenantId`: Your Azure AD tenant ID
   - `MCG_PollingInterval`: Recommended `21600` (6 hours) - see note below
6. **Assign security roles** in Power Platform Admin Center

### Polling Interval Note

Microsoft Message Center has no webhook/push notification. The solution polls Graph API.

| Interval | Use Case |
|----------|----------|
| 21600 (6 hours) | **Recommended** - Balances freshness with API efficiency |
| 14400 (4 hours) | Higher urgency environments |
| 3600 (1 hour) | Not recommended - excessive API calls, no benefit |

---

## After Import

1. **Create Azure AD app registration** with `ServiceMessage.Read.All` permission
2. **Enable the Message Center Ingestion flow** in Power Automate
3. **Assign security roles** to users:
   - MC Admin: Full access, manages configuration
   - MC Owner: Creates assessments, decisions
   - MC Compliance Reviewer: Read + approval fields
   - MC Auditor: Read-only for audit purposes

---

## Documentation

For detailed setup, customization, and compliance guidance, see the FSI-AgentGov playbook:

[Platform Change Governance Playbook](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/platform-change-governance/index.md)

Key documents:

- [Architecture & Schema](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/platform-change-governance/architecture.md)
- [Step-by-Step Setup](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/platform-change-governance/implementation-path-a.md)
- [Hands-On Labs](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/platform-change-governance/labs.md)
- [Evidence & Audit](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/platform-change-governance/evidence-and-audit.md)

---

## Customization

This is an **unmanaged solution** - you can modify everything:

- **Add columns:** Edit tables in Power Apps to add your own fields
- **Change roles:** Clone and modify security roles to match your RBAC
- **Extend workflow:** Add stages to the Business Process Flow
- **Change prefix:** Unpack with PAC CLI, find/replace `mcg_`, repack

The `src/` folder contains the unpacked solution XML for:

- Version control diffs when you make changes
- Direct XML editing for advanced customization
- Rebuilding the .zip with `pac solution pack`

**Your customizations are yours.** We do not provide automatic updates - you own the solution after import.

---

## Compliance Notice

This solution provides a **framework** for governance. Regulatory compliance is the customer's responsibility.

- **FINRA 4511:** Solution supports record retention; customer must configure retention policies
- **SEC 17a-4:** Dataverse audit logs provide audit trail; customer must verify compliance with counsel
- **SOX 404:** Workflow documents approvals; customer must map to control framework

See [Evidence & Audit documentation](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/platform-change-governance/evidence-and-audit.md) for detailed regulatory mapping.

---

## Version

1.0.0 - January 2026

## License

MIT - See LICENSE in repository root
