# FINRA Supervision Workflow

> **Status:** Validated

Automated supervision workflow for AI agent outputs to support FINRA Rule 3110 compliance in financial services organizations.

> **Regulatory Context:** FINRA Rule 3110 requires member firms to establish and maintain a system to supervise the activities of each associated person that is reasonably designed to achieve compliance. This solution automates the routing and tracking of AI agent outputs requiring supervisory review.

## Prerequisites

### 1. Licensing

| License | Purpose |
|---------|---------|
| Power Apps Premium | Dataverse tables, model-driven app |
| Power Automate Premium | HTTP connector, approval workflows |
| Power BI Pro (optional) | Supervision dashboard |
| Microsoft 365 E5 Compliance | Communication Compliance integration |

### 2. Roles Required

| Role | Purpose |
|------|---------|
| Power Platform Admin | Dataverse table creation, security roles |
| Purview Compliance Admin | Communication Compliance policy access |
| System Administrator | Security role assignment |
| Power BI Admin (optional) | Dashboard deployment |

### 3. Dependencies

| Dependency | Purpose |
|------------|---------|
| Control 1.7 (Audit Logging) | Captures agent interactions for review |
| Control 1.10 (Communication Compliance) | Flags content requiring review |
| Microsoft Purview API | Retrieves flagged items |

## What This Solution Does

- **Routes** flagged AI agent outputs to designated supervisory principals
- **Tracks** review status with configurable SLAs and escalation
- **Enforces** supervision coverage by zone and agent tier
- **Documents** supervisory reviews for regulatory evidence
- **Reports** supervision metrics via Power BI dashboard

**This is a supervision workflow solution** - it helps organizations implement FINRA 3110 requirements for AI agent oversight by automating the routing and tracking of items requiring supervisory review.

## Known Limitations

| Capability | Status | Alternative |
|------------|--------|-------------|
| Retrieve Communication Compliance alerts | **API** | Graph API with Compliance Admin permissions |
| Create Dataverse tables | **Automated** | `deploy.py` |
| Create security roles | **Manual** | Solution import or Dataverse admin center |
| Configure Communication Compliance | **Manual** | Purview compliance portal |
| Deploy Power BI dashboard | **Manual** | Import .pbix template |
| Configure escalation rules | **Manual** | Model-driven app settings |

## Who Should Use This

| Audience | Use Case |
|----------|----------|
| Compliance Operations | Monitor and manage supervision queue |
| Supervisory Principals | Review flagged AI agent outputs |
| Chief Compliance Officer | Oversight of supervision coverage |
| Audit/Examination | Evidence of supervision controls |

## Data Model

### SupervisionQueue Table

Primary queue table for items requiring supervisory review.

| Column | Type | Purpose |
|--------|------|---------|
| `fsi_queuenumber` | Auto Number | SUP-00001 format |
| `fsi_sourcetype` | Choice | Communication Compliance, Audit Log, Manual |
| `fsi_sourceid` | Text | Source record identifier |
| `fsi_agentid` | Text | Agent ID that generated content |
| `fsi_agentname` | Text | Agent display name |
| `fsi_zone` | Choice | Zone 1/2/3 classification |
| `fsi_tier` | Choice | Tier 1/2/3 agent classification |
| `fsi_contentpreview` | Multiline Text | Truncated content preview (500 chars) |
| `fsi_flaggedreason` | Text | Why item was flagged |
| `fsi_state` | Choice | Pending, In Review, Approved, Escalated, Rejected |
| `fsi_assignedprincipal` | Lookup (User) | Assigned supervisory principal |
| `fsi_queueddate` | DateTime | When item entered queue |
| `fsi_sladue` | DateTime | SLA deadline |
| `fsi_reviewedby` | Lookup (User) | Principal who reviewed |
| `fsi_revieweddate` | DateTime | Review completion timestamp |
| `fsi_reviewoutcome` | Choice | Approved, Rejected, Escalated |
| `fsi_reviewnotes` | Multiline Text | Supervisor notes |

### SupervisionLog Table

Immutable audit trail for supervision actions.

| Column | Type | Purpose |
|--------|------|---------|
| `fsi_lognumber` | Auto Number | LOG-000001 format |
| `fsi_queueitem` | Lookup (SupervisionQueue) | Related queue item |
| `fsi_action` | Choice | Queued, Assigned, Claimed, Reviewed, Approved, Rejected, Escalated, Reassigned, Closed |
| `fsi_actor` | Text | UPN of person taking action |
| `fsi_timestamp` | DateTime | Action timestamp |
| `fsi_details` | Multiline Text | Action details/notes |

### SupervisionConfig Table

Configuration for supervision rules by zone/tier.

| Column | Type | Purpose |
|--------|------|---------|
| `fsi_name` | Text | Zone-Tier combination name (primary column) |
| `fsi_zone` | Choice | Zone 1/2/3 |
| `fsi_tier` | Choice | Tier 1/2/3 |
| `fsi_slahours` | Number | Hours before SLA breach |
| `fsi_escalationhours` | Number | Hours before auto-escalation |
| `fsi_reviewpercent` | Number | Percentage requiring review (Zone 1: 5%, Zone 3: 100%) |
| `fsi_defaultprincipal` | Lookup (User) | Default supervisory principal |
| `fsi_escalationto` | Lookup (User) | Escalation recipient |
| `fsi_active` | Yes/No | Configuration active toggle |

See [docs/dataverse-schema.md](./docs/dataverse-schema.md) for complete schema.

## Quick Start

### Step 1: Deploy Dataverse Schema

```bash
# Install dependencies
pip install -r scripts/requirements.txt

# Dry run first
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

### Step 2: Configure Communication Compliance

1. Open Microsoft Purview compliance portal
2. Navigate to Communication Compliance > Policies
3. Create policy targeting Copilot Studio agent interactions
4. Configure conditions for flagging (regulatory terms, sensitive data)
5. Note the policy ID for flow configuration

See [docs/communication-compliance-setup.md](./docs/communication-compliance-setup.md) for detailed steps.

### Step 3: Create Security Roles

The solution defines four security roles (manual creation or solution import required; see [docs/security-roles.md](./docs/security-roles.md)):

| Role | Access |
|------|--------|
| FSW Supervisor | Review assigned queue items, add notes |
| FSW Queue Manager | Assign items, manage queue, configure rules |
| FSW Admin | Full access, configuration management |
| FSW Auditor | Read-only organization-wide |

### Step 4: Create Power Automate Flows

Create four flows per [docs/flow-configuration.md](./docs/flow-configuration.md):

1. **Ingest Flagged Items** - Polls Communication Compliance, creates queue items
2. **Assignment Flow** - Routes items to supervisory principals based on zone/tier
3. **Escalation Flow** - Scheduled flow for SLA monitoring and escalation
4. **Review Complete** - Logs review completion, notifies stakeholders

### Step 5: Deploy Power BI Dashboard (Optional)

1. Open Power BI Desktop
2. Connect to Dataverse and select the supervision tables (see [docs/power-bi-setup.md](./docs/power-bi-setup.md) for manual connection steps)
3. Configure dashboard pages using the measures and visuals documented in the setup guide
4. Publish to Power BI Service

### Step 6: Configure Supervision Rules

1. Open model-driven app (Supervision Manager)
2. Navigate to Configuration > Supervision Rules
3. Set SLA hours by zone/tier
4. Assign default supervisory principals
5. Configure escalation paths

### Step 7: Configure Data Retention

Configure Dataverse data lifecycle policies to enforce the 7-year retention requirement (FINRA 4511 / SEC 17a-4):

1. Open the [Power Platform admin center](https://admin.powerplatform.microsoft.com)
2. Navigate to **Environments** > select your environment > **Settings** > **Data management** > **Bulk record deletion**
3. Ensure no automated deletion policies target the `fsi_supervisionqueue` or `fsi_supervisionlog` tables within the 7-year window
4. Configure long-term retention:
   - Navigate to **Settings** > **Data management** > **Long-term data retention**
   - Add the `fsi_supervisionqueue` and `fsi_supervisionlog` tables
   - Set retention period to **7 years** (minimum per FINRA 4511)
5. For environments using Dataverse for Teams or limited storage, consider archiving records older than 2 years to Azure Data Lake via Synapse Link while retaining them for the full 7-year period

> **Note:** Dataverse does not enforce retention periods automatically. Without explicit configuration, records may be deleted during storage management or environment cleanup, violating FINRA 4511 and SEC 17a-4 preservation requirements.

### Step 8: Test End-to-End

1. Trigger a Communication Compliance alert (test message with flagged terms)
2. Verify item appears in SupervisionQueue
3. Review as supervisory principal
4. Check SupervisionLog for audit trail

## Workflow

```
Communication Compliance Alert
        |
        v
Ingest Flow (Scheduled every 15 min)
        |
        v
SupervisionQueue Created (State: Pending)
        |
        v
Assignment Flow
    |       \
    v        v
Zone 1-2   Zone 3 (100% review)
(Sampling)      |
    |           v
    v      Assigned to Principal
Random Sample   |
    |           v
    +---------> SLA Clock Starts
                |
                v
        Supervisor Reviews
            |       \
            v        v
        Approved   Rejected
            |           |
            v           v
        Closed      Closed
            |           |
            v           v
    SupervisionLog  SupervisionLog

        (Separately, Escalation Flow runs hourly
         to escalate Pending/In Review items past SLA)
```

## Supervision Rules by Zone

| Zone | Review Coverage | SLA | Escalation |
|------|----------------|-----|------------|
| Zone 1 (Personal) | 5–25% sampling (varies by tier) | 24–48 hours | 48–72 hours |
| Zone 2 (Team) | 10–50% sampling (varies by tier) | 8–48 hours | 24–72 hours |
| Zone 3 (Enterprise) | 100% review | 4–24 hours | 8–48 hours |

> See [docs/dataverse-schema.md](./docs/dataverse-schema.md#default-configuration) for the full per-tier breakdown.

## Evidence Collection

### Weekly Supervision Report

```bash
python scripts/export_supervision_evidence.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive \
    --output-path ./exports \
    --start-date 2026-01-20 \
    --end-date 2026-01-26
```

Exports include:
- `SupervisionQueue-Week04-2026.json` - All queue items with outcomes
- `SupervisionLog-Week04-2026.json` - Complete audit trail
- `SLACompliance-Week04-2026.json` - SLA metrics
- `SupervisionConfig-Week04-2026.json` - Active configuration snapshot
- `manifest-Week04-2026.json` - SHA-256 hashes for integrity

### FINRA 3120 Testing Evidence

Quarterly testing reports per FINRA Rule 3120:

<!-- TODO: generate_3120_report.py is planned for a future release -->

> **Planned — not yet implemented.** A `generate_3120_report.py` script for automated quarterly report generation is planned for a future release. In the interim, use the weekly supervision evidence exports to compile quarterly testing evidence manually.

## FSI Regulatory Alignment

| Regulation | Requirement | How This Helps |
|------------|-------------|----------------|
| **FINRA 3110** | Supervision of associated persons | Automated routing to principals, audit trail |
| **FINRA 3120** | Testing supervisory controls | Quarterly evidence export, SLA metrics |
| **FINRA 24-09** | Gen AI communication supervision | AI agent output review workflow |
| **SEC 17a-3** | Recordkeeping | Immutable SupervisionLog |
| **SEC 17a-4** | Record preservation | 7-year retention via Dataverse (FINRA 4511) |

## Documentation

| Guide | Description |
|-------|-------------|
| [docs/prerequisites.md](./docs/prerequisites.md) | Licensing, roles, dependencies |
| [docs/dataverse-schema.md](./docs/dataverse-schema.md) | Complete table definitions |
| [docs/security-roles.md](./docs/security-roles.md) | Role privilege matrix |
| [docs/communication-compliance-setup.md](./docs/communication-compliance-setup.md) | Purview policy configuration |
| [docs/flow-configuration.md](./docs/flow-configuration.md) | Power Automate specifications |
| [docs/power-bi-setup.md](./docs/power-bi-setup.md) | Dashboard deployment |
| [docs/troubleshooting.md](./docs/troubleshooting.md) | Error recovery procedures |

## Related Controls

This solution supports:

- [Control 2.12: Supervision and Oversight](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.12-supervision-and-oversight.md)
- [Control 1.10: Communication Compliance](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.10-communication-compliance-monitoring.md)
- [Control 1.7: Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md)

## Playbook Reference

Implementation guidance in FSI-AgentGov:

- [Control 2.12 Portal Walkthrough](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/control-implementations/2.12/portal-walkthrough.md)
- [Control 2.12 Verification Testing](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/control-implementations/2.12/verification-testing.md)

## Version

1.0.0 - February 2026

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## License

MIT - See LICENSE in repository root
