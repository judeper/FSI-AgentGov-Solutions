# Security Roles

Role definitions and privilege matrix for the FINRA Supervision Workflow solution.

## Role Overview

| Role | Purpose | Typical Users |
|------|---------|---------------|
| FSW Supervisor | Review assigned queue items | Supervisory Principals, Team Leads |
| FSW Queue Manager | Manage queue, assign items, configure rules | Compliance Operations |
| FSW Admin | Full access, automation service account | Platform Admins |
| FSW Auditor | Read-only access for audit/examination | Internal Audit, Examiners |

---

## FSW Supervisor

Supervisory principals who review flagged AI agent outputs.

### SupervisionQueue Privileges

| Privilege | Access Level |
|-----------|--------------|
| Create | None |
| Read | User (own assigned items) |
| Write | User (own assigned items) |
| Delete | None |
| Append | User |
| Append To | User |

### SupervisionLog Privileges

| Privilege | Access Level |
|-----------|--------------|
| Create | Organization (via automation) |
| Read | User (related to assigned items) |
| Write | None |
| Delete | None |

### SupervisionConfig Privileges

| Privilege | Access Level |
|-----------|--------------|
| Read | Organization |
| All others | None |

---

## FSW Queue Manager

Compliance operations staff who manage the supervision queue.

### SupervisionQueue Privileges

| Privilege | Access Level |
|-----------|--------------|
| Create | Organization |
| Read | Organization |
| Write | Organization |
| Delete | None |
| Append | Organization |
| Append To | Organization |
| Assign | Organization |

### SupervisionLog Privileges

| Privilege | Access Level |
|-----------|--------------|
| Create | Organization |
| Read | Organization |
| Write | None |
| Delete | None |

### SupervisionConfig Privileges

| Privilege | Access Level |
|-----------|--------------|
| Create | Organization |
| Read | Organization |
| Write | Organization |
| Delete | None |

---

## FSW Admin

Full access for platform administrators and automation accounts.

### SupervisionQueue Privileges

| Privilege | Access Level |
|-----------|--------------|
| Create | Organization |
| Read | Organization |
| Write | Organization |
| Delete | Organization |
| Append | Organization |
| Append To | Organization |
| Assign | Organization |

### SupervisionLog Privileges

| Privilege | Access Level |
|-----------|--------------|
| Create | Organization |
| Read | Organization |
| Write | None |
| Delete | None |

> **Important:** Even Admin role should NOT have Write or Delete on SupervisionLog to maintain audit integrity.

### SupervisionConfig Privileges

| Privilege | Access Level |
|-----------|--------------|
| All | Organization |

---

## FSW Auditor

Read-only access for internal audit and regulatory examiners.

### All Tables

| Privilege | Access Level |
|-----------|--------------|
| Read | Organization |
| All others | None |

---

## Miscellaneous Privileges

All roles require these base privileges:

| Privilege | Purpose |
|-----------|---------|
| prvReadUser | Look up users for assignment |
| prvReadOrganization | Access organization settings |
| prvReadAsyncOperation | View background job status |

---

## Assignment Guidelines

### Supervisory Principals

1. Assign **FSW Supervisor** role
2. Ensure proper delegation of authority documentation
3. Configure as potential assignee in SupervisionConfig

### Compliance Operations

1. Assign **FSW Queue Manager** role
2. May also have FSW Supervisor if they review items

### Service Accounts

1. Assign **FSW Admin** role to Power Automate connection identity
2. Document service account in system inventory

### Auditors

1. Assign **FSW Auditor** role
2. Time-limited access during examination periods recommended

---

## Field-Level Security

### SupervisionQueue Field Security

| Field | FSW Supervisor | FSW Queue Manager | FSW Admin | FSW Auditor |
|-------|---------------|-------------------|-----------|-------------|
| Content Preview | Read | Read/Write | Read/Write | Read |
| Review Notes | Read/Write | Read/Write | Read/Write | Read |
| Source ID | Read | Read/Write | Read/Write | Read |

### SupervisionLog Field Security

No field-level security - entire table is read-only except Create.

---

## Verification Script

Verify role privileges match expected configuration:

```bash
python scripts/verify_role_privileges.py \
    --environment-url https://org.crm.dynamics.com \
    --role-name "FSW Admin"
```

Expected output:
```
Verifying role: FSW Admin
✓ SupervisionQueue: Create=Organization, Read=Organization, Write=Organization
✓ SupervisionLog: Create=Organization, Read=Organization, Write=None, Delete=None
✓ SupervisionConfig: Full Organization access
Role verification: PASSED
```

---

## Segregation of Duties

| Function | Required Role | Cannot Also Have |
|----------|---------------|------------------|
| Review items | FSW Supervisor | - |
| Assign items | FSW Queue Manager | FSW Supervisor (for same items) |
| Configure rules | FSW Queue Manager | - |
| Delete queue items | FSW Admin | FSW Supervisor (recommended) |

For Zone 3 / Tier 1 agents, implement dual-supervisor review by requiring two FSW Supervisors to approve.
