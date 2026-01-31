# Environment Lifecycle Management

Automated Power Platform environment provisioning with zone-based governance classification.

> **Important:** This solution combines **Python automation scripts** with **manual portal configuration** for Copilot Studio agents. Environment Groups and Copilot Studio topics must be created manually via the admin portal. See [Known Limitations](#known-limitations) for details.

## Prerequisites

### 1. Licensing

| License | Purpose |
|---------|---------|
| Power Apps Premium | Dataverse tables, model-driven app |
| Copilot Studio | Intake agent (may be included in M365 E3/E5) |
| Power Automate Premium | HTTP actions with Entra ID connector |
| Azure Subscription | Key Vault for credential storage |

### 2. Roles Required

| Role | Purpose |
|------|---------|
| Power Platform Admin | Service Principal setup, environment creation |
| Entra ID Application Administrator | App registration |
| System Administrator | Dataverse table creation, security roles |
| Key Vault Secrets Officer | Credential storage |

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
3. Store Service Principal client secret as `ELM-ServicePrincipal-Secret`

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
    --interactive \
    --dry-run

# Full deployment
python scripts/deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
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

- **Classifies** environment requests into governance zones (Zone 1/2/3) based on data sensitivity
- **Automates** approval workflows with segregation of duties enforcement
- **Provisions** environments via Service Principal with zone-specific configurations
- **Binds** security groups and applies baseline settings (audit retention, session timeout)
- **Maintains** immutable provisioning audit trail for regulatory evidence
- **Exports** quarterly evidence with SHA-256 integrity hashing

**This is an environment governance solution** - it helps organizations automate environment provisioning while maintaining regulatory compliance for FINRA 4511, SEC 17a-3/4, and SOX 404.

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

Create three flows per [docs/flow-configuration.md](./docs/flow-configuration.md):

1. **Main Provisioning Flow** - Triggered on approval
2. **Security Group Binding Flow** - Post-creation binding
3. **Baseline Configuration Flow** - Child flow for settings

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
- `EnvironmentRequest-Q1-2026.json` - All requests with approvals
- `ProvisioningLog-Q1-2026.json` - Complete audit trail
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
| **FINRA 4511** | Books and records retention | 7-year Zone 3 audit retention, immutable logs |
| **SEC 17a-3/4** | Record preservation | Quarterly exports with integrity hashing |
| **SOX 404** | IT general controls | Segregation of duties, approval workflows |
| **OCC 2011-12** | Model risk management | Zone classification, approval documentation |
| **GLBA 501(b)** | Safeguards rule | Security group binding, access controls |

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

## Related Controls

This solution supports:

- [Control 2.1: Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.1-managed-environments.md)
- [Control 2.2: Environment Groups and Tier Classification](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.2-environment-groups-and-tier-classification.md)
- [Control 2.3: Change Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.3-change-management-and-release-planning.md)
- [Control 2.8: Access Control and Segregation of Duties](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.8-access-control-and-segregation-of-duties.md)
- [Control 1.7: Comprehensive Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md)

## Playbook Reference

Full implementation guidance available in FSI-AgentGov:

- [Environment Lifecycle Management Playbook](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/environment-lifecycle-management/index.md)

## Version

1.1.1 - January 2026

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## License

MIT - See LICENSE in repository root
