# FINRA Supervision Workflow

> **Status:** Preview (v1.0.1)

Automated **retrospective** supervision workflow for AI agent outputs to support FINRA Rule 3110 compliance in financial services organizations. This solution provides post-delivery review queue, SLA tracking, escalation, and immutable audit logging fed by Microsoft Purview Communication Compliance.

> **Scope of this solution:** This is the **retrospective supervision** arm of Control 2.12. It does **not** replace pre-delivery Human-in-the-Loop (HITL) review, which Control 2.12 requires for Zone 3 / customer-facing (retail communication) agents. For pre-delivery HITL on Zone 3 agents, deploy [hitl-workflow-governance](../hitl-workflow-governance/) alongside this solution.

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

> ⚠️ **API Risk:** The `compliance.microsoft.com/api/SupervisoryReview/alerts` endpoint
> is undocumented and not officially supported by Microsoft. It may change or be removed
> without notice. As a fallback, consider using `Connect-IPPSSession` with
> `Get-SupervisoryReviewPolicyV2` cmdlets for programmatic access.

## What This Solution Does

- **Routes** flagged AI agent outputs to designated supervisory principals
- **Tracks** review status with configurable SLAs and escalation
- **Helps enforce** supervision coverage by zone and agent tier
- **Documents** supervisory reviews for regulatory evidence
- **Reports** supervision metrics via Power BI dashboard

**This is a supervision workflow solution** - it helps organizations implement FINRA 3110 requirements for AI agent oversight by automating the routing and tracking of items requiring supervisory review.

## Known Limitations

| Capability | Status | Alternative |
|------------|--------|-------------|
| Retrieve Communication Compliance alerts | **API** | Purview Communication Compliance API with Compliance Admin permissions |
| Create Dataverse tables | **Automated** | `deploy.py` |
| Create security roles | **Manual** | See `docs/security-roles.md`; `deploy.py` prints privilege matrix |
| Configure Communication Compliance | **Manual** | Purview compliance portal |
| Deploy Power BI dashboard | **Manual** | Import .pbix template |
| Configure escalation rules | **Manual** | Model-driven app settings |
| Solution packaging | **Not implemented** | Components deployed via Web API; no managed/unmanaged solution package (solution.xml, customizations.xml) for ALM pipelines. Cannot be promoted through dev→test→prod using Power Platform Pipelines or Azure DevOps ALM tooling. |

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
| `fsi_sourcetype` | Choice | Communication Compliance, Audit Log, Manual Entry |
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
| `fsi_actor` | Lookup (User) | Person taking action |
| `fsi_timestamp` | DateTime | Action timestamp |
| `fsi_details` | Multiline Text | Action details/notes |

### SupervisionConfig Table

Configuration for supervision rules by zone/tier.

| Column | Type | Purpose |
|--------|------|---------|
| `fsi_name` | Text | Zone-tier combination name (primary column) |
| `fsi_zone` | Choice | Zone 1/2/3 |
| `fsi_tier` | Choice | Tier 1/2/3 |
| `fsi_slahours` | Number | Hours before SLA breach |
| `fsi_escalationhours` | Number | Hours before auto-escalation |
| `fsi_reviewpercent` | Number | Percentage requiring review (Zone 1: 5%, Zone 3: 100%) |
| `fsi_defaultprincipal` | Lookup (User) | Default supervisory principal |
| `fsi_escalationto` | Lookup (User) | Escalation recipient |
| `fsi_active` | Yes/No | Configuration active flag |

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

### Step 1.5: Create Columns and Option Sets Manually

Using `docs/dataverse-schema.md` as the spec, create every column on the three tables (`fsi_supervisionqueue`, `fsi_supervisionlog`, `fsi_supervisionconfig`) in the Power Apps maker portal. **For Choice columns, set the option-set values explicitly to the integers documented in the schema (1, 2, 3 …) rather than accepting the auto-generated 100000000+ defaults.** All scripts and DAX measures in this solution assume the small-integer values from the schema doc.

### Step 2: Configure Communication Compliance

1. Open Microsoft Purview compliance portal
2. Navigate to Communication Compliance > Policies
3. Create policy targeting Copilot Studio agent interactions
4. Configure conditions for flagging (regulatory terms, sensitive data)
5. Note the policy ID for flow configuration

See [docs/communication-compliance-setup.md](./docs/communication-compliance-setup.md) for detailed steps.

### Step 3: Create Security Roles

Create four security roles manually or via solution import (the deployment script outputs the required privilege matrix but does not provision roles automatically):

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
4. **Review Complete Flow** - Logs review completion, handles escalation routing

### Step 5: Deploy Power BI Dashboard (Optional)

1. Open Power BI Desktop
2. Build the dashboard manually using the instructions in [docs/power-bi-setup.md](./docs/power-bi-setup.md) Step 2, Option B

> **Note:** The `templates/SupervisionDashboard.pbit` template is not yet included in this release. Use the manual connection steps in the Power BI setup guide.

### Step 6: Configure Supervision Rules

1. Open model-driven app (Supervision Manager)
2. Navigate to Configuration > Supervision Rules
3. Set SLA hours by zone/tier
4. Assign default supervisory principals
5. Configure escalation paths

### Step 7: Test End-to-End

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
        Approved   Rejected/Escalated
            |           |
            v           v
        Closed    Escalation Flow
            |           |
            v           v
    SupervisionLog  Notify Senior Principal
```

## Supervision Rules by Zone

| Zone | Tier | Review Coverage | SLA | Escalation |
|------|------|----------------|-----|------------|
| Zone 1 (Personal) | Tier 1 | 25% sampling | 24 hours | 48 hours |
| Zone 1 (Personal) | Tier 2 | 10% sampling | 48 hours | 72 hours |
| Zone 1 (Personal) | Tier 3 | 5% sampling | 48 hours | 72 hours |
| Zone 2 (Team) | Tier 1 | 50% sampling | 8 hours | 24 hours |
| Zone 2 (Team) | Tier 2 | 25% sampling | 24 hours | 48 hours |
| Zone 2 (Team) | Tier 3 | 10% sampling | 48 hours | 72 hours |
| Zone 3 (Enterprise) | Tier 1 | 100% review | 4 hours | 8 hours |
| Zone 3 (Enterprise) | Tier 2 | 100% review | 8 hours | 24 hours |
| Zone 3 (Enterprise) | Tier 3 | 100% review | 24 hours | 48 hours |

> See [docs/dataverse-schema.md](./docs/dataverse-schema.md) for the full zone×tier configuration matrix.

> **Sampling layers:** The review percentages above apply at the flow level (SupervisionConfig `fsi_reviewpercent`). Communication Compliance policies apply independent, upstream sampling (e.g., Zone 1 at 5%, Zone 2 at 25%, Zone 3 at 100% — see [docs/communication-compliance-setup.md](./docs/communication-compliance-setup.md)). These two sampling layers are independent and multiplicative. For example, Zone 1 / Tier 1 has an effective review rate of approximately 1.25% (5% CC sampling × 25% flow-level review). Adjust rates in both layers to achieve your target supervision coverage.

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
- `SupervisionConfig-{period}.json` - Effective supervision rules at export time
- `manifest-{period}.json` - SHA-256 hashes for integrity (e.g., `manifest-Week04-2026.json`)
- `manifest-{period}.sha256` - Manifest checksum for tamper-evident packaging

### FINRA 3120 Testing Evidence

Quarterly testing reports per FINRA Rule 3120:


> **Planned — not yet implemented.** A `generate_3120_report.py` script for automated quarterly report generation is planned for a future release. In the interim, use the weekly supervision evidence exports to compile quarterly testing evidence manually.

## FSI Regulatory Alignment

| Regulation | Requirement | How This Helps |
|------------|-------------|----------------|
| **FINRA 3110** | Supervision of associated persons | Automated routing to principals, audit trail |
| **FINRA 3120** | Testing supervisory controls | Quarterly evidence export, SLA metrics |
| **FINRA 24-09** *(Regulatory Notice — guidance)* | Gen AI communication supervision | AI agent output review workflow |
| **SEC 17a-3** | Recordkeeping | Immutable SupervisionLog |
| **SEC 17a-4(b)(4)** | Record preservation — communications | **3-year retention** for communications under SEC 17a-4(b)(4) (first 2 years readily accessible). Export to WORM/compliant archival storage via `scripts/export_supervision_evidence.py` |
| **FINRA Rule 4511(b)** | Record retention — supervisory designations | **6-year retention** for FINRA-required records when no other period is specified by SEA Rule 17a-4 (e.g., supervisory system designations, written supervisory procedures). Firm policy may extend retention beyond regulatory minimums |

## Platform Update Notes

### DSR Transcript Endpoints (April 2026)

Microsoft has added new [Power Platform REST API](https://learn.microsoft.com/en-us/rest/api/power-platform/) endpoints for Data Subject Request (DSR) compliance, including transcript export and deletion for Copilot Studio conversations.

**Impact on this solution:** FINRA Rule 4511 requires member firms to retain books and records for specified periods. The new DSR transcript endpoints introduce a potential conflict between privacy-driven deletion requests and regulatory retention obligations. Organizations should:

- Ensure DSR deletion workflows check for active supervision holds before deleting Copilot Studio transcripts
- Document retention-override policies that defer transcript deletion until the FINRA 4511 / SEC 17a-4 retention period expires
- Consider adding a DSR hold check step to the supervision queue workflow to prevent premature evidence destruction

### Voice Agent Supervision (April 2026)

Copilot Studio now supports [real-time voice agents](https://learn.microsoft.com/en-us/microsoft-copilot-studio/voice-configuration) with telephony integration. Voice-enabled agents generate speech transcripts that may require supervisory review under FINRA 3110, similar to text-based agent outputs.

> **Note:** Voice transcript ingestion is not yet automated in this solution's supervision queue. Organizations deploying voice-enabled agents should evaluate manual supervision coverage until automated voice transcript routing is implemented.

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

- [Control 2.12: Supervision and Oversight (FINRA Rule 3110)](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.12-supervision-and-oversight-finra-rule-3110.md)
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
