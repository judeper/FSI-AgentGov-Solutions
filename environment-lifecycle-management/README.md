---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P2, P4]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: enable
---
# Environment Lifecycle Management

> **Version:** v1.2.2
> **Status:** Live
> **Validated against framework version:** v1.6.0

Automated Power Platform environment provisioning with zone-based governance classification.

> **Important:** This solution combines **Python automation scripts** with **manual portal configuration** for Copilot Studio agents. Environment Groups and Copilot Studio topics must be created manually via the admin portal. See [Known Limitations](#known-limitations) for details.

## Prerequisites

### 1. Licensing

| License | Purpose |
|---------|---------|
| Power Apps Premium | Dataverse tables, model-driven app |
| Copilot Studio | Intake agent (separate license required) |
| Power Automate Premium | HTTP actions with Entra ID connector |
| Azure Subscription | Key Vault for credential storage |

### 2. Roles Required

| Role | Purpose |
|------|---------|
| Power Platform Admin | Service Principal setup, environment creation |
| Entra ID Application Administrator | App registration |
| System Administrator | Dataverse table creation, security roles |
| Key Vault Secrets Officer | Credential storage |

!!! warning "Service Principal Permissions"
    This solution uses a Service Principal for automated environment provisioning. Service Principals are application identities that bypass security group-based access controls. Ensure:

    - Service Principal has System Administrator security role assigned via `pac admin create-service-principal`
    - Service Principal sign-ins are restricted via Named Locations to trusted networks
    - Service Principal authentication is monitored via Entra ID Sign-in Logs
    - Service Principal credentials use managed identity or certificate-based authentication where supported; any client secret is a legacy development fallback stored in Azure Key Vault and rotated at least quarterly
    - Service Principal does NOT have Entra Global Admin or Power Platform Administrator directory roles (use least-privilege API permissions instead)

    See [docs/service-principal-setup.md](./docs/service-principal-setup.md) for security configuration guidance.

### 3. Environment Groups

Create three environment groups in Power Platform admin center before deployment:

| Group Name | Zone | DLP Policy |
|------------|------|------------|
| FSI-Zone1-PersonalProductivity | Zone 1 | Standard |
| FSI-Zone2-TeamCollaboration | Zone 2 | Restricted |
| FSI-Zone3-EnterpriseManagedEnvironment | Zone 3 | Highly Restricted |

### 4. Azure Key Vault

Required for Service Principal credential storage:

1. Create or identify existing Key Vault
2. Grant Power Automate identity "Get" secret permission
3. Prefer a managed identity or certificate-backed credential where the connector supports it; if a legacy client secret is required for lab/dev, store it as `ELM-ServicePrincipal-Secret` and rotate it at least quarterly

See [docs/service-principal-setup.md](./docs/service-principal-setup.md) for complete setup.

## Automated Deployment (Lab/Dev)

For quick setup in lab or development environments, use the automated deployment script:

```bash
# Install dependencies
pip install -r scripts/requirements.txt

# Dry run first to preview changes
python scripts/deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --client-id <your-client-id> \
    --interactive \
    --dry-run

# Full deployment
python scripts/deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --client-id <your-client-id> \
    --interactive
```

The deployment script creates:
- Option sets (State, Zone, Region, etc.)
- EnvironmentRequest table (22 columns, user-owned)
- ProvisioningLog table (11 columns, org-owned, immutable)
- Security roles (Requester, Approver, Admin, Auditor)
- Business rules (conditional required fields)
- Model-driven app views
- Field security profiles

**After automated deployment, you still need to manually:**
1. Register Service Principal in PPAC
2. Create Environment Groups
3. Build Copilot Studio agent
4. Create Power Automate flows

For production environments, use the [manual setup process](#quick-start) for full audit trail.

## What This Solution Does

- **Classifies** environment requests into governance zones (Zone1, Zone2, Zone3) based on data sensitivity
- **Automates** approval workflows with segregation of duties enforcement
- **Provisions** environments via Service Principal with zone-specific configurations
- **Binds** security groups and applies baseline settings (audit retention, session timeout)
- **Maintains** immutable provisioning audit trail for regulatory evidence
- **Exports** quarterly evidence with SHA-256 integrity hashing

**This is an environment governance solution** - it helps organizations automate environment provisioning while supporting compliance with FINRA Rule 4511(a), SEC Rules 17a-3 / 17a-4(f), and SOX 404 requirements.

## Known Limitations

| Capability | Status | Script/Alternative |
|------------|--------|-------------------|
| Create Dataverse tables | **Automated** | `deploy.py` or `create_dataverse_schema.py` |
| Create security roles | **Automated** | `deploy.py` or `create_security_roles.py` |
| Create business rules | **Automated** | `deploy.py` or `create_business_rules.py` |
| Create views | **Automated** | `deploy.py` or `create_views.py` |
| Create field security | **Automated** | `deploy.py` or `create_field_security.py` |
| Create Environment Groups | **Manual** | Create via admin.powerplatform.com |
| Create Copilot Studio agent | **Manual** | Build via make.powerapps.com (Copilot Studio) |
| Create Power Automate flows | **Manual** | Create manually or import solution |
| Register SP in PPAC | **Manual** | Portal step after `register_service_principal.py` |
| Register Service Principal | **Automated** | `register_service_principal.py` |
| Export quarterly evidence | **Automated** | `export_quarterly_evidence.py` |
| Verify role privileges | **Automated** | `verify_role_privileges.py` |
| Validate immutability | **Automated** | `validate_immutability.py` |
| Async environment polling | **Flow handles** | Do-Until loop with 30s delay |
| Dataverse solution container | **Not implemented** | Components are created directly in the environment without a managed solution wrapper. This prevents managed solution transport between dev/test/prod and breaks ALM dependency tracking. Acceptable for lab/dev; wrap in a Dataverse solution for production deployments. |
| GUID validation for security group | **Partial** | `fsi_securitygroupid` is a plain text column (max 100 chars). The Copilot agent validates GUID format at intake (Question 10b), but no server-side validation exists in business rules or flows. An invalid GUID will cause a runtime Graph API error. For production, add a Regex Match business rule or flow-level validation before the Graph API call. |

See [docs/troubleshooting.md](./docs/troubleshooting.md) for workarounds and error recovery.

## Who Should Use This

| Audience | Use Case |
|----------|----------|
| Platform Operations | Automate environment provisioning, maintain compliance |
| AI Governance Committee | Enforce zone-based governance classification |
| Environment Approvers | Review and approve environment requests |
| Compliance Teams | Export evidence for regulatory examinations |
| Auditors | Verify provisioning controls and immutability |

## Data Model

### EnvironmentRequest Table

Primary request table with 22 columns including zone classification, approval workflow, and provisioning status.

| Key Column | Type | Purpose |
|------------|------|---------|
| `fsi_requestnumber` | Auto Number | REQ-00001 format |
| `fsi_environmentname` | Text | DEPT-Purpose-TYPE naming |
| `fsi_zone` | Choice | Zone 1/2/3 classification |
| `fsi_state` | Choice | Workflow state (Draft → Completed) |
| `fsi_environmentid` | Text | Power Platform environment ID |

### ProvisioningLog Table

Immutable audit trail with 11 columns. Organization-owned with no Update/Delete privileges.

| Key Column | Type | Purpose |
|------------|------|---------|
| `fsi_sequence` | Number | Action sequence (1, 2, 3...) |
| `fsi_action` | Choice | 16 action types |
| `fsi_actor` | Text | UPN or Service Principal ID |
| `fsi_timestamp` | DateTime | Action timestamp |
| `fsi_success` | Boolean | Success/failure flag |

See [docs/dataverse-schema.md](./docs/dataverse-schema.md) for complete schema.

## Quick Start

### Step 1: Create Dataverse Tables

1. Open Power Apps maker portal (make.powerapps.com)
2. Create `EnvironmentRequest` table per [docs/dataverse-schema.md](./docs/dataverse-schema.md)
3. Create `ProvisioningLog` table (organization-owned)
4. Configure business rules for conditional required fields

### Step 2: Create Security Roles

Create four security roles per [docs/security-roles.md](./docs/security-roles.md):

| Role | Access |
|------|--------|
| ELM Requester | Create/read own requests |
| ELM Approver | Read/approve business unit requests |
| ELM Admin | Full access (via automation) |
| ELM Auditor | Read-only organization-wide |

### Step 3: Register Service Principal

```bash
# Install dependencies
pip install -r scripts/requirements.txt

# Register Service Principal (dry run first)
python scripts/register_service_principal.py \
  --tenant-id <tenant-id> \
  --app-name ELM-Provisioning-ServicePrincipal \
  --key-vault-name <vault-name> \
  --dry-run

# Execute registration
python scripts/register_service_principal.py \
  --tenant-id <tenant-id> \
  --app-name ELM-Provisioning-ServicePrincipal \
  --key-vault-name <vault-name>
```

### Step 4: Create Environment Groups (Manual)

1. Open Power Platform admin center
2. Navigate to Environment groups
3. Create three groups: Zone1, Zone2, Zone3
4. Configure DLP policies for each group

### Step 5: Create Copilot Studio Agent (Manual)

1. Open Copilot Studio (make.powerapps.com > Copilot Studio)
2. Create new agent: "Environment Request Agent"
3. Configure topics per [docs/copilot-agent-setup.md](./docs/copilot-agent-setup.md)
4. Enable authentication (Authenticate with Microsoft)

### Step 6: Create Power Automate Flows (Manual)

Create four flows per [docs/flow-configuration.md](./docs/flow-configuration.md):

1. **Main Provisioning Flow** - Triggered on approval
2. **Security Group Binding Flow** - Post-creation binding
3. **Baseline Configuration Flow** - Child flow for settings
4. **Approval Routing Flow** - Manager and compliance approvals

### Step 7: Validate Setup

```bash
# Verify role privileges
python scripts/verify_role_privileges.py \
  --environment-url https://<org>.crm.dynamics.com

# Validate ProvisioningLog immutability
python scripts/validate_immutability.py \
  --environment-url https://<org>.crm.dynamics.com
```

### Step 8: Test End-to-End

1. Submit test request via Copilot agent
2. Approve request
3. Verify environment created with correct zone settings
4. Check ProvisioningLog for complete audit trail

## Workflow

```
Copilot Intake Agent
        |
        v
EnvironmentRequest Created (Draft → Submitted)
        |
        v
Zone Classification (Auto-detect triggers)
        |
        v
Approval Routing (Zone 2/3 require manager + compliance)
        |
        v
Approval Decision
    |       \
    v        v
Approved   Rejected → END
    |
    v
Main Provisioning Flow
    |
    +→ Create Environment (async polling)
    +→ Enable Managed Environment
    +→ Assign to Environment Group
    +→ Security Group Binding (Zone 2/3)
    +→ Baseline Configuration (child flow)
    |
    v
ProvisioningLog (immutable audit trail)
    |
    v
Notify Requester → END
```

## Permissions

| Role | Script Access | Portal Access |
|------|---------------|---------------|
| Platform Ops Team | All scripts | Full Dataverse + PPAC |
| AI Governance Committee | Evidence export | Approve Zone 3 requests |
| Environment Approvers | None | Approve requests in model-driven app |
| Compliance/Audit | Evidence export | Read-only ProvisioningLog |

## Platform Update Notes

### Relationship to Native Agentic Center of Enablement (2026 Wave 1)

Microsoft's [Agentic Center of Enablement](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/power-platform-governance-administration/automate-governance-agentic-center-enablement) (Agentic CoE) introduces AI-powered agents to the Power Platform admin center for automated governance — daily tenant snapshots, continuous issue scanning, and remediation planning.

**Relationship to this solution:** The Agentic CoE monitors tenant-level governance health. ELM governs the **environment request and provisioning lifecycle** — intake, zone classification, approval routing, automated provisioning via Service Principal, security group binding, and baseline hardening. These are complementary, not overlapping:

- ELM applies zone-based governance **at provisioning time** (before environments exist)
- The Agentic CoE monitors **existing environments** for governance drift
- ELM maintains immutable provisioning audit trails for FINRA 4511 / SEC 17a-4
- ELM integrates with Copilot Studio intake agents for self-service provisioning with guardrails

FSI organizations should use the Agentic CoE for ongoing environment health monitoring and ELM for governed provisioning and regulatory evidence.

### Unified Environment Types (April 2026)

Microsoft has introduced [unified environment types](https://learn.microsoft.com/en-us/power-platform/admin/unified-experience/unified-environment-types-and-templates) for Power Platform, consolidating environment management under three standardized types:

| Unified Type | Abbreviation | Replaces | Scope |
|-------------|-------------|----------|-------|
| Unified Production Environment | **UPE** | Production | Live workloads, up to 80 AOS instances |
| Unified Sandbox Environment | **USE** | Sandbox | Testing, UAT, training, up to 80 AOS instances |
| Unified Developer Environment | **UDE** | Developer | Single-developer, X++ development, 1 AOS instance |

**Impact on this solution:** The ELM Dataverse schema (`create_dataverse_schema.py`) currently uses the environment type choice values: Production, Sandbox, Developer. As organizations adopt unified environment types:

- The `fsi_environmenttype` choice on the `EnvironmentRequest` table may need to be expanded to include UPE, USE, and UDE values
- Zone classification logic should map UPE → Zone 2/3 (production), USE → Zone 1/2 (sandbox), UDE → Zone 1 (developer)
- Environment Group assignment rules may need updating as Microsoft aligns environment groups with unified types

> **Note:** The unified environment types are currently most relevant for Dynamics 365 Finance & Operations workloads. Copilot Studio and standard Power Platform environments continue to use the existing Production/Sandbox/Developer model. Monitor Microsoft documentation for broader adoption timelines before modifying the schema.

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Environment creation timeout | Async provisioning delayed | Check PPAC for status, retry after 15 min |
| Security group not found | Invalid group ID | Verify group exists in Entra ID |
| Service Principal auth fails | Credential expired | Rotate secret, update Key Vault |
| Environment Group not found | Group name mismatch | Verify exact group name in PPAC |
| Immutability check fails | Role has Update privilege | Remove Write/Delete from ELM Admin role |

See [docs/troubleshooting.md](./docs/troubleshooting.md) for complete error recovery procedures.

## Evidence Collection

### Quarterly Export

```bash
python scripts/export_quarterly_evidence.py \
  --environment-url https://<org>.crm.dynamics.com \
  --output-path ./exports \
  --start-date 2026-01-01 \
  --end-date 2026-03-31
```

Exports include:
- `EnvironmentRequest-2026-Q1.json` - All requests with approvals
- `ProvisioningLog-2026-Q1.json` - Complete audit trail
- `manifest.json` - SHA-256 hashes for integrity verification

### Integrity Verification

```bash
python scripts/validate_immutability.py \
  --environment-url https://<org>.crm.dynamics.com
```

Checks:
- No Update/Delete audit entries on ProvisioningLog
- Security roles have correct privilege assignments
- All log entries have required fields populated

## FSI Regulatory Alignment

| Regulation | Requirement | How This Helps |
|------------|-------------|----------------|
| **FINRA Rule 4511(a)** | General requirements for books and records | Maintains structured environment-request and provisioning audit data; **does not** by itself satisfy the WORM media or 6-year retention obligations of related rules — pair with WORM-compatible storage (Azure Storage Immutable Blobs in time-based retention/legal-hold mode, Purview Records Management, or equivalent). |
| **SEC Rules 17a-3(a)(17) and 17a-4(f)** | Records of advisory accounts; record preservation on non-rewriteable, non-erasable media | Quarterly evidence exports include SHA-256 hashes and a chained `previousManifestHash` for tamper-evidence; **does not** itself constitute WORM-compliant storage. The exported files must be written to an SEC 17a-4(f)-validated WORM target. |
| **SOX 404** | IT general controls | Segregation of duties via field-security profiles, mandatory approver routing, and immutable provisioning logs. |
| **GLBA 501(b) Safeguards Rule** | Customer information protection | Security-group binding and zone-based DLP application; full safeguards program is broader than this solution. |
| **FFIEC IT Examination Handbook (Information Security)** | Change and access controls for IT systems | Provides a documented request → approval → provisioning → evidence pipeline; the regulator expects this to be one part of a wider SDLC and access-management program. |

## Documentation

| Guide | Description |
|-------|-------------|
| [docs/prerequisites.md](./docs/prerequisites.md) | Licensing, roles, environment requirements |
| [docs/dataverse-schema.md](./docs/dataverse-schema.md) | Complete table and column definitions |
| [docs/security-roles.md](./docs/security-roles.md) | Role privilege matrix, field-level security |
| [docs/service-principal-setup.md](./docs/service-principal-setup.md) | SP registration, Key Vault integration |
| [docs/flow-configuration.md](./docs/flow-configuration.md) | Power Automate flow specifications |
| [docs/copilot-agent-setup.md](./docs/copilot-agent-setup.md) | Copilot Studio topic configuration |
| [docs/troubleshooting.md](./docs/troubleshooting.md) | Error recovery, rollback procedures |
| [SETUP_CHECKLIST.md](./SETUP_CHECKLIST.md) | Phase-based deployment checklist |

## Cross-Solution Contract

ELM is the source-of-truth for environment zone classification across the
FSI-AgentGov solutions. Other solutions (e.g., conditional-access-automation,
agent-sharing-access-restriction-detector) read the zone via the shared
PowerShell helper at `scripts/shared/Get-ZoneClassification.ps1`, which
queries Dataverse using the contract below.

| Element | Value |
|---------|-------|
| Entity set | `fsi_environmentrequests` |
| Filter column | `fsi_environmentid` (Power Platform environment GUID written back by the provisioning flow) |
| Returned column | `fsi_zone` |
| Option values | `100000001` = Zone1, `100000002` = Zone2, `100000003` = Zone3 |
| Returned labels | `Zone1`, `Zone2`, `Zone3` (no spaces) |

Changing any of these is a **breaking change** for downstream solutions.
Bump the ELM major version and update the consuming solutions when this
contract changes.

<!-- BEGIN:IMPLEMENTED_CONTROLS -->
<!-- Generated by scripts/build-manifest.py from manifest.yaml.controls — do not edit by hand. -->

## Implemented Controls

Canonical control coverage for this solution is declared in `manifest.yaml.controls` and exported in `solutions.json` as `solutions.<solution-id>.controls`. Downstream consumers should sync from that machine-readable list rather than parsing hand-maintained README prose.

| Control | Description |
|---------|-------------|
| [2.1](https://judeper.github.io/FSI-AgentGov-Solutions/reference/control-mapping/#control-2-1) | Managed Environments |
| [2.2](https://judeper.github.io/FSI-AgentGov-Solutions/reference/control-mapping/#control-2-2) | Environment Groups and Tier Classification |
| [2.8](https://judeper.github.io/FSI-AgentGov-Solutions/reference/control-mapping/#control-2-8) | Access Control and Segregation of Duties |
| [1.7](https://judeper.github.io/FSI-AgentGov-Solutions/reference/control-mapping/#control-1-7) | Comprehensive Audit Logging and Compliance |

<!-- END:IMPLEMENTED_CONTROLS -->

> Control 2.3 (Change Management and Release Planning) was previously
> claimed but has been removed from this list — ELM provisions
> environments themselves; release planning across those environments is
> covered by the **pipeline-governance-cleanup** solution.

## Playbook Reference

Full implementation guidance available in FSI-AgentGov:

- [Environment Lifecycle Management Playbook](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/environment-lifecycle-management/index.md)

## Version

1.2.2 - Council review remediation (deploy.py ImportError fix; option-set example correction; audit FetchXML clarification)
1.2.1 - Microsoft Learn 2026-Q2 refresh (see CHANGELOG)

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## License

MIT - See LICENSE in repository root
