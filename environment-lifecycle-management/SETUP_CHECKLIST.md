# Setup Checklist

Phase-based deployment checklist for the Environment Lifecycle Management solution.

> **Legend:**
> - ✓ = Automated (script available)
> - **[MANUAL]** = Requires admin portal interaction
> - ⚠ = Requires manual verification after automation

---

## Prerequisites

### Licensing

- [ ] Power Apps Premium or Per App license available
- [ ] Copilot Studio license (or included in M365 E3/E5)
- [ ] Power Automate Premium license (for HTTP with Entra ID connector)
- [ ] Azure subscription with Key Vault access

### Roles

- [ ] Power Platform Admin role assigned
- [ ] Entra ID Application Administrator role assigned
- [ ] System Administrator role in target Dataverse environment
- [ ] Key Vault Secrets Officer role assigned

### Environment

- [ ] Identify governance environment for Dataverse tables
- [ ] Verify environment is a Managed Environment
- [ ] Confirm DLP policies allow required connectors

---

## Phase 1: Data Layer

### Option A: Automated Deployment (✓ Recommended for Lab/Dev)

```bash
# Install dependencies
pip install -r scripts/requirements.txt

# Dry run first
python scripts/deploy.py \
  --environment-url https://<org>.crm.dynamics.com \
  --tenant-id <tenant-id> \
  --interactive \
  --dry-run

# Full deployment
python scripts/deploy.py \
  --environment-url https://<org>.crm.dynamics.com \
  --tenant-id <tenant-id> \
  --interactive
```

- [ ] Run deploy.py with `--dry-run` to validate
- [ ] Review output for expected configuration
- [ ] Execute without `--dry-run` to create resources
- [ ] Skip to "Verify Immutability" section below

### Option B: Manual Deployment **[MANUAL]** (Production)

#### Create Dataverse Tables

- [ ] Open Power Apps maker portal (make.powerapps.com)
- [ ] Select governance environment
- [ ] Create `EnvironmentRequest` table:
  - [ ] Set ownership to User (enables row-level security)
  - [ ] Enable auditing (all fields, all operations)
  - [ ] Configure auto-number primary column: `REQ-{SEQNUM:5}`
  - [ ] Add all 22 columns per [docs/dataverse-schema.md](./docs/dataverse-schema.md)
- [ ] Create `ProvisioningLog` table:
  - [ ] Set ownership to Organization (enforces immutability)
  - [ ] Enable auditing
  - [ ] Configure relationship to EnvironmentRequest (Restrict Delete)
  - [ ] Add all 11 columns per [docs/dataverse-schema.md](./docs/dataverse-schema.md)
- [ ] Create business rules:
  - [ ] Zone Rationale Required (when Zone = 2 or 3)
  - [ ] Security Group Required (when Zone = 2 or 3)
  - [ ] Approval Comments Required (when State = Rejected)

#### Create Security Roles

- [ ] Open Power Platform admin center
- [ ] Navigate to environment > Security roles
- [ ] Create `ELM Requester` role:
  - [ ] EnvironmentRequest: Create (User), Read (User), Write (User)
  - [ ] ProvisioningLog: Read (User)
- [ ] Create `ELM Approver` role:
  - [ ] EnvironmentRequest: Read (BU), Write (BU) - approval fields only
  - [ ] ProvisioningLog: Read (BU)
  - [ ] Configure field-level security for approval fields
- [ ] Create `ELM Admin` role:
  - [ ] EnvironmentRequest: Create (Org), Read (Org), Write (Org), Append (Org), AppendTo (Org)
  - [ ] ProvisioningLog: Create (Org), Read (Org) **ONLY** - NO Write, NO Delete
- [ ] Create `ELM Auditor` role:
  - [ ] EnvironmentRequest: Read (Org)
  - [ ] ProvisioningLog: Read (Org)

### Verify Immutability (⚠ Verify After)

After creating roles, run verification:

```bash
python scripts/verify_role_privileges.py \
  --environment-url https://<org>.crm.dynamics.com
```

Expected output: No Update or Delete privileges on ProvisioningLog for any role.

---

## Phase 2: Service Principal

### Register Application (✓ Automated)

```bash
# Install dependencies
pip install -r scripts/requirements.txt

# Dry run first
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

- [ ] Run script with `--dry-run` to validate
- [ ] Review output for expected configuration
- [ ] Execute without `--dry-run` to create resources
- [ ] Save Application (client) ID for later configuration
- [ ] Verify secret stored in Key Vault

### Register as Power Platform Management App **[MANUAL]**

- [ ] Open Power Platform admin center
- [ ] Navigate to Settings > Admin settings > Power Platform settings
- [ ] Select Service principal > New service principal
- [ ] Enter Application (client) ID from registration step
- [ ] Click Create
- [ ] Verify status shows "Enabled"

See [docs/service-principal-setup.md](./docs/service-principal-setup.md) for details.

---

## Phase 3: Environment Groups

### Create Environment Groups **[MANUAL]**

- [ ] Open Power Platform admin center (admin.powerplatform.com)
- [ ] Navigate to Environment groups
- [ ] Create `FSI-Zone1-PersonalProductivity`:
  - [ ] Description: "Zone 1 - Personal productivity, minimal governance"
  - [ ] Apply standard DLP policy
- [ ] Create `FSI-Zone2-TeamCollaboration`:
  - [ ] Description: "Zone 2 - Team collaboration, restricted connectors"
  - [ ] Apply restricted DLP policy
- [ ] Create `FSI-Zone3-EnterpriseManagedEnvironment`:
  - [ ] Description: "Zone 3 - Enterprise managed, highly restricted"
  - [ ] Apply highly restricted DLP policy

### Configure DLP Policies **[MANUAL]**

For each environment group:

- [ ] Zone 1: Block known-risky connectors only
- [ ] Zone 2: Business-only connectors, block social/consumer
- [ ] Zone 3: Approved connectors whitelist only

---

## Phase 4: Copilot Studio Agent

### Create Agent **[MANUAL]**

- [ ] Open Copilot Studio (make.powerapps.com > Copilot Studio)
- [ ] Create new agent: "Environment Request Agent"
- [ ] Configure authentication:
  - [ ] Settings > Security
  - [ ] Authentication: Authenticate with Microsoft
  - [ ] Require users to sign in: Yes

### Create Topics **[MANUAL]**

Create topics per [docs/copilot-agent-setup.md](./docs/copilot-agent-setup.md):

- [ ] **Request Environment** topic:
  - [ ] Add 11 slot collection questions
  - [ ] Configure zone classification Power Fx expression
  - [ ] Add naming convention validation
  - [ ] Configure JSON output for Power Automate
- [ ] **Check Request Status** topic:
  - [ ] Trigger: "status of my request", "REQ-xxxxx"
  - [ ] Query EnvironmentRequest by request number
- [ ] **Cancel Request** topic:
  - [ ] Trigger: "cancel request", "withdraw"
  - [ ] Update request state to Cancelled (if Draft/Submitted)
- [ ] **Help** topic:
  - [ ] Trigger: "help", "what can you do"
  - [ ] Display available commands and guidance

### Customize System Topics **[MANUAL]**

- [ ] Greeting: Add environment request option
- [ ] Fallback: Route to Request Environment or Help
- [ ] End of Conversation: Provide request tracking link

### Test Agent **[MANUAL]**

- [ ] Test Request Environment flow end-to-end
- [ ] Verify zone classification triggers correctly
- [ ] Confirm JSON output matches expected schema
- [ ] Test error handling for invalid inputs

---

## Phase 5: Power Automate Flows

### Create Service Principal Connection **[MANUAL]**

- [ ] Open Power Automate (make.powerautomate.com)
- [ ] Go to Connections > New connection
- [ ] Select Power Platform for Admins V2
- [ ] Choose Service Principal authentication
- [ ] Enter Tenant ID, Client ID
- [ ] Configure Key Vault reference for Client Secret

### Create Main Provisioning Flow **[MANUAL]**

Per [docs/flow-configuration.md](./docs/flow-configuration.md):

- [ ] Create flow with Dataverse trigger:
  - [ ] Table: EnvironmentRequest
  - [ ] Filter: `er_state eq 'Approved'`
- [ ] Add Key Vault action to retrieve SP secret
- [ ] Add Create Environment action (Power Platform for Admins V2)
- [ ] Add Do-Until loop for async polling:
  - [ ] Condition: provisioningState = Succeeded OR Failed
  - [ ] Limit: 120 iterations, 60 minute timeout
  - [ ] Delay: 30 seconds between checks
- [ ] Add Enable Managed Environment (HTTP with Entra ID)
- [ ] Add Assign to Environment Group (HTTP with Entra ID)
- [ ] Add ProvisioningLog entries for each step
- [ ] Configure error handling scopes
- [ ] Add notification to requester on completion

### Create Security Group Binding Flow **[MANUAL]**

- [ ] Create flow with Dataverse trigger:
  - [ ] Table: EnvironmentRequest
  - [ ] Filter: `er_state eq 'Provisioning' and er_securitygroupid ne null`
- [ ] Add Graph API call to validate security group
- [ ] Add Force Sync User action for Service Principal
- [ ] Add Security Group binding via Power Platform connector
- [ ] Add ProvisioningLog entries
- [ ] Configure error handling

### Create Baseline Configuration Flow (Child) **[MANUAL]**

- [ ] Create instant flow with input parameters:
  - [ ] environmentId, environmentUrl, zone, requestId
- [ ] Add Enable Auditing action (HTTP with Entra ID)
- [ ] Add Set Session Timeout action
- [ ] Add Configure Sharing Limits action
- [ ] Add ProvisioningLog entries
- [ ] Return success/failure status

### Configure Flow Connections **[MANUAL]**

- [ ] Link all flows to Service Principal connection
- [ ] Verify Key Vault connection works
- [ ] Test Dataverse connection
- [ ] Verify HTTP with Entra ID (preauthorized) connector

---

## Phase 6: Validation

### End-to-End Test **[MANUAL]**

- [ ] Submit test request via Copilot agent
- [ ] Verify request created in EnvironmentRequest table
- [ ] Approve request
- [ ] Monitor provisioning flow execution
- [ ] Verify environment created with correct settings:
  - [ ] Managed Environment enabled
  - [ ] Correct Environment Group assigned
  - [ ] Security group bound (Zone 2/3)
  - [ ] Audit settings applied
  - [ ] Session timeout configured
- [ ] Verify ProvisioningLog contains all entries
- [ ] Verify requester notification received

### Immutability Validation (✓ Automated)

```bash
python scripts/validate_immutability.py \
  --environment-url https://<org>.crm.dynamics.com
```

- [ ] No Update audit entries on ProvisioningLog
- [ ] No Delete audit entries on ProvisioningLog
- [ ] All required fields populated on log entries

### Security Role Audit (✓ Automated)

```bash
python scripts/verify_role_privileges.py \
  --environment-url https://<org>.crm.dynamics.com
```

- [ ] ELM Admin has no Write privilege on ProvisioningLog
- [ ] ELM Admin has no Delete privilege on ProvisioningLog
- [ ] Segregation of duties enforced

---

## Phase 7: Operational Readiness

### Documentation

- [ ] Document Environment Group names and IDs
- [ ] Document Service Principal app ID
- [ ] Document Key Vault name and secret name
- [ ] Update runbook with environment-specific values
- [ ] Create user guide for requesters

### Monitoring Setup **[MANUAL]**

- [ ] Configure alerts for failed provisioning flows
- [ ] Set up Teams notifications for Zone 3 requests
- [ ] Create dashboard for pending approvals
- [ ] Configure weekly integrity check schedule

### Evidence Collection (✓ Automated)

Test quarterly export:

```bash
python scripts/export_quarterly_evidence.py \
  --environment-url https://<org>.crm.dynamics.com \
  --output-path ./test-export \
  --start-date 2026-01-01 \
  --end-date 2026-01-31
```

- [ ] Verify export files created
- [ ] Verify SHA-256 hashes in manifest
- [ ] Test archive to SharePoint/WORM storage

### Credential Rotation Schedule

- [ ] Document rotation schedule (90 days for secrets)
- [ ] Set calendar reminders for rotation
- [ ] Test rotation procedure in non-production

---

## Quick Links

| Resource | URL |
|----------|-----|
| Power Platform Admin Center | https://admin.powerplatform.microsoft.com |
| Power Apps Maker Portal | https://make.powerapps.com |
| Power Automate | https://make.powerautomate.com |
| Copilot Studio | https://copilotstudio.microsoft.com |
| Azure Portal (Key Vault) | https://portal.azure.com |
| Entra Admin Center | https://entra.microsoft.com |

---

## Automation Summary

| Task | Status | Method |
|------|--------|--------|
| Create Dataverse tables | ✓ Automated | `deploy.py` or `create_dataverse_schema.py` |
| Create security roles | ✓ Automated | `deploy.py` or `create_security_roles.py` |
| Create business rules | ✓ Automated | `deploy.py` or `create_business_rules.py` |
| Create views | ✓ Automated | `deploy.py` or `create_views.py` |
| Create field security | ✓ Automated | `deploy.py` or `create_field_security.py` |
| Register Service Principal | ✓ Automated | `register_service_principal.py` |
| Register as PPAC Management App | **MANUAL** | Power Platform admin center |
| Create Environment Groups | **MANUAL** | Power Platform admin center |
| Create Copilot agent | **MANUAL** | Copilot Studio |
| Create Power Automate flows | **MANUAL** | Power Automate (or solution import) |
| Verify role privileges | ✓ Automated | `verify_role_privileges.py` |
| Validate immutability | ✓ Automated | `validate_immutability.py` |
| Export quarterly evidence | ✓ Automated | `export_quarterly_evidence.py` |

---

## Timeline Template

### Lab/Dev Environment (Automated)

| Day | Activity | Type |
|-----|----------|------|
| Day 1 | Run deploy.py for schema, roles, rules, views | ✓ Automated |
| Day 1 | Register Service Principal | ✓ + **MANUAL** |
| Day 1 | Create Environment Groups | **MANUAL** |
| Day 2 | Build Copilot Studio agent | **MANUAL** |
| Day 2-3 | Create Power Automate flows | **MANUAL** |
| Day 3 | End-to-end testing, validation scripts | ✓ + **MANUAL** |

### Production Environment (Manual)

| Week | Activity | Type |
|------|----------|------|
| Week 1 | Create Dataverse tables, security roles | **MANUAL** |
| Week 1 | Register Service Principal | ✓ + **MANUAL** |
| Week 2 | Create Environment Groups, DLP policies | **MANUAL** |
| Week 2 | Build Copilot Studio agent | **MANUAL** |
| Week 3 | Create Power Automate flows | **MANUAL** |
| Week 3 | End-to-end testing | **MANUAL** |
| Week 4 | Validation scripts, documentation | ✓ + **MANUAL** |
| Week 4 | Go-live, monitoring setup | **MANUAL** |
