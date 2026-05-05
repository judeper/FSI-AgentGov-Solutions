# Dataverse Schema

Complete table and column definitions for the FINRA Supervision Workflow solution.

## Tables Overview

| Table | Purpose | Ownership | Records |
|-------|---------|-----------|---------|
| SupervisionQueue | Items requiring supervisory review | User-owned | Transactional |
| SupervisionLog | Append-only audit trail | Organization-owned | Append-only |
| SupervisionConfig | Zone/tier configuration | Organization-owned | Configuration |

---

## SupervisionQueue Table

**Schema Name:** `fsi_supervisionqueue`
**Display Name:** Supervision Queue
**Ownership:** User
**Primary Column:** `fsi_queuenumber`

### Columns

| Display Name | Schema Name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| Queue Number | `fsi_queuenumber` | Auto Number | Yes | SUP-{SEQNUM:5} format |
| Source Type | `fsi_sourcetype` | Choice | Yes | Communication Compliance, Audit Log, Manual Entry |
| Source ID | `fsi_sourceid` | Text (200) | No | Source record identifier |
| Agent ID | `fsi_agentid` | Text (100) | No | Copilot Studio agent ID |
| Agent Name | `fsi_agentname` | Text (200) | Yes | Agent display name |
| Zone | `fsi_zone` | Choice | Yes | Zone 1, Zone 2, Zone 3 |
| Tier | `fsi_tier` | Choice | Yes | Tier 1, Tier 2, Tier 3 |
| Content Preview | `fsi_contentpreview` | Multiline Text | No | First 500 characters |
| Flagged Reason | `fsi_flaggedreason` | Text (500) | Yes | Policy or rule that flagged item |
| State | `fsi_state` | Choice | Yes | Pending, In Review, Approved, Escalated, Rejected |
| Assigned Principal | `fsi_assignedprincipal` | Lookup (User) | No | Supervisory principal |
| Queued Date | `fsi_queueddate` | DateTime | Yes | When item entered queue |
| SLA Due | `fsi_sladue` | DateTime | Yes | SLA deadline |
| Reviewed By | `fsi_reviewedby` | Lookup (User) | No | Principal who reviewed |
| Reviewed Date | `fsi_revieweddate` | DateTime | No | Review completion timestamp |
| Review Outcome | `fsi_reviewoutcome` | Choice | No | Approved, Rejected, Escalated |
| Review Notes | `fsi_reviewnotes` | Multiline Text | No | Supervisor notes |

### Choice Values

**Source Type (`fsi_sourcetype`):**
| Value | Label |
|-------|-------|
| 1 | Communication Compliance |
| 2 | Audit Log |
| 3 | Manual Entry |

**Zone (`fsi_zone`):**
| Value | Label |
|-------|-------|
| 1 | Zone 1 - Personal Productivity |
| 2 | Zone 2 - Team Collaboration |
| 3 | Zone 3 - Enterprise Managed |

**Tier (`fsi_tier`):**
| Value | Label |
|-------|-------|
| 1 | Tier 1 - Critical |
| 2 | Tier 2 - Standard |
| 3 | Tier 3 - Low Risk |

**State (`fsi_state`):**
| Value | Label |
|-------|-------|
| 1 | Pending |
| 2 | In Review |
| 3 | Approved |
| 4 | Escalated |
| 5 | Rejected |

**Review Outcome (`fsi_reviewoutcome`):**
| Value | Label |
|-------|-------|
| 1 | Approved |
| 2 | Rejected |
| 3 | Escalated |

---

## SupervisionLog Table

**Schema Name:** `fsi_supervisionlog`
**Display Name:** Supervision Log
**Ownership:** Organization
**Primary Column:** `fsi_lognumber`

> **Important:** This table is append-only by security role design. Enable Dataverse auditing and export evidence to WORM or Microsoft Purview records-management storage when regulatory retention requires immutable preservation.

### Columns

| Display Name | Schema Name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| Log Number | `fsi_lognumber` | Auto Number | Yes | LOG-{SEQNUM:6} format |
| Queue Item | `fsi_queueitem` | Lookup (SupervisionQueue) | Yes | Related queue item |
| Action | `fsi_action` | Choice | Yes | Action taken |
| Actor | `fsi_actor` | Lookup (User) | Yes | Person taking action |
| Timestamp | `fsi_timestamp` | DateTime | Yes | Action timestamp |
| Details | `fsi_details` | Multiline Text | No | Additional details |

### Choice Values

**Action (`fsi_action`):**
| Value | Label |
|-------|-------|
| 1 | Queued |
| 2 | Assigned |
| 3 | Claimed |
| 4 | Reviewed |
| 5 | Approved |
| 6 | Rejected |
| 7 | Escalated |
| 8 | Reassigned |
| 9 | Closed |

---

## SupervisionConfig Table

**Schema Name:** `fsi_supervisionconfig`
**Display Name:** Supervision Config
**Ownership:** Organization
**Primary Column:** `fsi_name`

### Columns

| Display Name | Schema Name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| Name | `fsi_name` | Text (100) | Yes | Zone-Tier combination name |
| Zone | `fsi_zone` | Choice | Yes | Zone classification |
| Tier | `fsi_tier` | Choice | Yes | Tier classification |
| SLA Hours | `fsi_slahours` | Whole Number | Yes | Hours until SLA breach |
| Escalation Hours | `fsi_escalationhours` | Whole Number | Yes | Hours until auto-escalation |
| Review Percent | `fsi_reviewpercent` | Whole Number | Yes | Percentage requiring review |
| Default Principal | `fsi_defaultprincipal` | Lookup (User) | No | Default supervisor |
| Escalation To | `fsi_escalationto` | Lookup (User) | No | Escalation recipient |
| Active | `fsi_active` | Yes/No | Yes | Configuration active |

### Default Configuration

| Zone | Tier | SLA Hours | Escalation | Review % |
|------|------|-----------|------------|----------|
| Zone 1 | Tier 1 | 24 | 48 | 25% |
| Zone 1 | Tier 2 | 48 | 72 | 10% |
| Zone 1 | Tier 3 | 48 | 72 | 5% |
| Zone 2 | Tier 1 | 8 | 24 | 50% |
| Zone 2 | Tier 2 | 24 | 48 | 25% |
| Zone 2 | Tier 3 | 48 | 72 | 10% |
| Zone 3 | Tier 1 | 4 | 8 | 100% |
| Zone 3 | Tier 2 | 8 | 24 | 100% |
| Zone 3 | Tier 3 | 24 | 48 | 100% |

---

## Business Rules

### SupervisionQueue Rules

1. **Require Review Notes on Rejection**
   - Condition: Review Outcome = Rejected
   - Action: Review Notes is required

2. **Set SLA Due on Queue**
   - Condition: State = Pending (on create)
   - Action: Calculate SLA Due from config

3. **Lock Fields After Review**
   - Condition: State in (Approved, Rejected)
   - Action: Lock Content Preview, Flagged Reason

### SupervisionLog Rules

No business rules - append-only via automation.

---

## Views

### SupervisionQueue Views

| View | Filter | Columns |
|------|--------|---------|
| My Queue | Assigned Principal = Current User, State = Pending/In Review | Queue Number, Agent Name, Flagged Reason, SLA Due |
| Pending Review | State = Pending | Queue Number, Agent Name, Zone, Tier, Queued Date |
| Overdue Items | SLA Due < Now, State in (Pending, In Review) | Queue Number, Agent Name, Assigned Principal, SLA Due |
| Escalated Items | State = Escalated | Queue Number, Agent Name, Reviewed By, Escalation Reason |
| Completed This Week | Reviewed Date >= Week Start | Queue Number, Agent Name, Review Outcome, Reviewed By |
| All Items | None | All columns |

### SupervisionLog Views

| View | Filter | Columns |
|------|--------|---------|
| Today's Activity | Timestamp >= Today | Log Number, Queue Item, Action, Actor, Timestamp |
| Audit Trail | None | All columns, sorted by Timestamp desc |

---

## Deployment Script

The `deploy.py` script creates tables and seeds default configuration. Column creation within tables and security role provisioning require manual setup or solution import (see [security-roles.md](./security-roles.md)).

```bash
python scripts/deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <tenant-id> \
    --interactive
```

To create only specific components:

```bash
# Tables only
python scripts/deploy.py --environment-url ... --tenant-id <tenant-id> --interactive --tables-only

# Security roles only
python scripts/deploy.py --environment-url ... --tenant-id <tenant-id> --interactive --roles-only
```
