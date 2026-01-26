# Platform Change Governance Solution

Pre-built Power Platform solution for Microsoft Message Center change governance in regulated financial services environments.

## Prerequisites (Read First)

**These requirements will block your deployment if not addressed:**

### 0. Python 3.10+ Required

The deployment script requires **Python 3.10 or later** due to use of:
- Type hints with `|` union syntax (e.g., `str | None`)
- Match statements and other modern Python features

```bash
python --version  # Must be 3.10+
```

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

- **Power Platform:** System Administrator role (required for security role creation)
- **Azure AD:** Application Administrator (to create app registration)
- **Graph API:** Grant `ServiceMessage.Read.All` (Application permission) + admin consent

### 4. Two Separate App Registrations Required

This solution requires **two separate Azure AD app registrations**:

| App Registration | Purpose | Permissions |
|------------------|---------|-------------|
| **Dataverse Deployment App** | Used by `deploy_mcg.py` to create solution components | Dataverse `user_impersonation` or Application User |
| **Message Center Ingestion App** | Used by Power Automate to read Message Center | Graph API `ServiceMessage.Read.All` |

**Why two apps?** Separation of concerns and least privilege:
- Deployment app needs Dataverse admin access (temporary, during setup)
- Ingestion app only needs read-only Graph API access (ongoing, automated)

### 5. Security Warning: Client Secrets

⚠️ **Never pass secrets via command line in production systems**

The deployment script supports three methods for providing the client secret:

1. **Environment variable (recommended):** `export MCG_CLIENT_SECRET="..."`
2. **Interactive prompt:** Script will ask if not provided
3. **Command line argument:** `--client-secret "..."` (appears in shell history - avoid in production)

Command line arguments are visible in:
- Shell history files (`~/.bash_history`, `~/.zsh_history`)
- Process listings (`ps aux`)
- System audit logs

---

## What's Included

The deployment script (`scripts/deploy_mcg.py`) creates the **complete solution** via Dataverse Web API:

| Component | Details |
|-----------|---------|
| **3 Tables** | MessageCenterPost, AssessmentLog, DecisionLog with AI-friendly descriptions |
| **26 Columns** | All with descriptions for AI agent reasoning (includes choice value semantics) |
| **4 Security Roles** | MC Admin, MC Owner, MC Compliance Reviewer, MC Auditor (auto-associated with app) |
| **4 Views** | All Open Posts, New Posts - Awaiting Triage, High Severity, My Assigned |
| **1 Main Form** | 5 tabs: Overview, Content, Assessment, Decision, Audit Trail |
| **1 Model-Driven App** | Message Center Governance with security role associations |
| **1 Business Process Flow** | 5-stage workflow placeholder (requires portal configuration) |
| **2 Environment Variables** | MCG_TenantId, MCG_PollingInterval (default: 6 hours) |

**AI-Readiness:** All tables and columns include rich descriptions that help AI agents (Copilot, custom agents) understand field purposes, choice value meanings, and correlation guidance.

---

## Quick Start

### Option A: Automated Deployment (Recommended)

```bash
# Install dependencies
pip install requests msal

# Set client secret via environment variable (recommended)
export MCG_CLIENT_SECRET="your-secret-value"

# Run deployment script
python scripts/deploy_mcg.py \
    --environment-url "https://org12345.crm.dynamics.com" \
    --tenant-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
    --client-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

The script creates all components and is **idempotent** (safe to run multiple times).

The script outputs a verification report showing all created components and any issues detected.

### Option B: Manual Import

1. **Verify prerequisites** above (DLP, Solution Checker, permissions)
2. **Download** `MessageCenterGovernance_1_0_0_0.zip` from this folder
3. **Import** at [make.powerapps.com](https://make.powerapps.com) → Solutions → Import
4. **Configure connections** when prompted during import
5. **Set environment variables (in Power Platform):**
   - `mcg_TenantId`: Your Azure AD tenant ID
   - `mcg_PollingInterval`: Recommended `21600` (6 hours) - see note below
6. **Assign security roles** in Power Platform Admin Center

### Polling Interval Note

Microsoft Message Center has no webhook/push notification. The solution polls Graph API.

| Interval | Use Case |
|----------|----------|
| 21600 (6 hours) | **Recommended** - Balances freshness with API efficiency |
| 14400 (4 hours) | Higher urgency environments |
| 3600 (1 hour) | Not recommended - excessive API calls, no benefit |

---

## After Deployment

### 1. Azure AD App Registration for Message Center Ingestion

**Important:** This is a SEPARATE app registration from the one used for deployment. See "Two Separate App Registrations Required" in Prerequisites.

1. Go to Azure Portal > Azure Active Directory > App Registrations
2. Create new registration (single tenant)
   - Name suggestion: "MCG Message Center Ingestion"
3. Under "Certificates & secrets", create a client secret (save securely)
4. Under "API permissions":
   - Add permission > Microsoft Graph > **Application permissions** (NOT Delegated)
   - Select `ServiceMessage.Read.All`
   - Click **"Grant admin consent"** (requires Global Administrator)
5. Note the Application (client) ID and client secret for use in Power Automate

### 2. Power Automate Flow for Message Center Ingestion

Create a scheduled flow with these components:

- **Trigger:** Recurrence (6 hours recommended, configurable via MCG_PollingInterval)
- **HTTP Action:**
  - Method: GET
  - URI: `https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages`
  - Authentication: Active Directory OAuth
    - Tenant: Your Azure AD Tenant ID
    - Audience: `https://graph.microsoft.com`
    - Client ID: From app registration
    - Credential Type: Secret
    - Secret: From app registration
- **Parse JSON:** Use Message Center schema
- **For Each:** Create/Update Dataverse record using `mcg_MessageCenterId` as alternate key

### 3. Business Process Flow Configuration

The script creates a placeholder BPF. To make it functional:

1. Go to make.powerapps.com > Solutions > MessageCenterGovernance
2. Configure the BPF or delete and recreate via UI:
   - Name: MCG Governance Process
   - Entity: Message Center Post
   - Stages: New, Triage, Assess, Decide, Closed
3. Add relevant fields to each stage
4. Save and **Activate** the BPF

### 4. Assign Security Roles

Security roles are automatically associated with the app. Assign to users:

- **MC Admin:** Full access, manages configuration
- **MC Owner:** Creates assessments, decisions
- **MC Compliance Reviewer:** Read + approval fields
- **MC Auditor:** Read-only for audit purposes

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

1.3.0 - January 2026

## License

MIT - See LICENSE in repository root
