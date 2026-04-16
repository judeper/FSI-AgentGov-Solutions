# Baseline Configuration

Guide to configuring agent scope baselines for the Scope Drift Monitor.

---

## Overview

A **scope baseline** defines what data sources and connectors an AI agent is allowed to access. The Scope Drift Monitor compares actual agent access against this baseline to detect drift.

```
Agent Access Event → Compare to Baseline → Match? → No Action
                                        → No Match? → Create Violation
```

---

## Creating Baselines

### Option 1: Auto-Generate from Audit History

Use the `New-AgentBaseline.ps1` script to analyze historical access and generate a baseline automatically.

```powershell
.\scripts\New-AgentBaseline.ps1 `
    -AgentId "12345678-1234-1234-1234-123456789012" `
    -Environment "https://contoso.crm.dynamics.com" `
    -EnvironmentId "87654321-4321-4321-4321-210987654321" `
    -OwnerId "user-guid" `
    -Days 7
```

**What it does:**

1. Queries Office 365 Management API for CopilotInteraction events
2. Filters events by agent ID
3. Extracts accessed connectors, sites, tables, and APIs
4. Creates an `fsi_agentscope` record with populated allowed lists
5. Sets status to **Active** immediately

**Best for:**

- Existing agents with established access patterns
- Quick baseline creation
- Agents in Zone 1 or Zone 2

### Option 2: Manual Configuration

Create baselines manually for precise control over allowed resources.

**Steps:**

1. Navigate to your Dataverse environment
2. Go to **Tables** > **Agent Scope** (fsi_agentscope)
3. Click **+ New record**
4. Fill in required fields (see [Scope Definition Fields](#scope-definition-fields))
5. Set **Status** to **Active** when ready

**Best for:**

- New agents before deployment
- Zone 3 enterprise agents requiring strict control
- Agents with known, limited scope

---

## Scope Definition Fields

### Required Fields

| Field | Description | Example |
|-------|-------------|---------|
| `fsi_name` | Display name | "Customer Service Agent" |
| `fsi_agentid` | Copilot Studio agent GUID | `12345678-1234-...` |
| `fsi_environmentid` | Power Platform environment ID | `87654321-4321-...` |
| `fsi_zone` | Governance zone (1-3) | 3 (Enterprise Managed) |
| `fsi_owner` | Agent owner (user lookup) | John Smith |
| `fsi_purpose` | Declared agent purpose | "Answer customer inquiries" |
| `fsi_status` | Baseline status | 10002 (Active) |

### Scope Arrays (JSON Format)

| Field | Description | Example |
|-------|-------------|---------|
| `fsi_allowedconnectors` | Allowed connector names | `["SharePoint", "Dataverse"]` |
| `fsi_allowedsites` | Allowed SharePoint site URLs | `["https://contoso.sharepoint.com/sites/KB"]` |
| `fsi_allowedtables` | Allowed Dataverse table names | `["contact", "case"]` |
| `fsi_allowedapis` | Allowed external API URLs | `["https://api.contoso.com/v1"]` |

### Optional Fields

| Field | Description | Example |
|-------|-------------|---------|
| `fsi_dataowner` | Data steward (user lookup) | Jane Doe |
| `fsi_lastvalidated` | Last validation timestamp | 2026-02-01T00:00:00Z |
| `fsi_nextreview` | Next scheduled review date | 2026-05-01 |

---

## Scope Status Values

| Value | Label | Meaning |
|-------|-------|---------|
| 10001 | **Draft** | Baseline being configured, not monitored |
| 10002 | **Active** | Baseline active, violations detected |
| 10003 | **Under Review** | Baseline under review (pauses monitoring) |
| 10004 | **Suspended** | Baseline suspended (not monitored) |
| 10005 | **Archived** | Baseline archived (no monitoring) |

**Monitoring behavior:**

- **Active:** Full monitoring, violations created
- **Draft/Under Review:** No violations created
- **Suspended:** Not monitored (fsi_status eq 10002 filter excludes suspended scopes)
- **Archived:** No monitoring

---

## Governance Zones

Baselines are classified by governance zone, affecting detection behavior.

| Zone | Label | Detection Frequency | Approval Rigor |
|------|-------|--------------------|-|
| 1 | Personal Productivity | Every 15 minutes | Security team (via `fsi_SDM_SecurityTeamEmail`) |
| 2 | Team Collaboration | Every 15 minutes | Security team (via `fsi_SDM_SecurityTeamEmail`) |
| 3 | Enterprise Managed | Every 15 minutes | Security team (via `fsi_SDM_SecurityTeamEmail`) |

> **Note:** Zone-differentiated approval rigor (self-service for Zone 1, team lead for Zone 2, dual Security + Data Owner for Zone 3) is planned but not yet implemented. All zones currently route expansion requests to the security team. The schema includes `fsi_dataownerapproval` and `fsi_dataownerapprovedby` fields for future use.

**Zone selection criteria:**

| Criteria | Zone 1 | Zone 2 | Zone 3 |
|----------|--------|--------|--------|
| User scope | Individual | Team/Department | Organization-wide |
| Data sensitivity | Low | Medium | High |
| Regulatory impact | None | Some | Critical |
| Approval required | Security team | Security team | Security team |

---

## Scope Array Format

All scope arrays must be valid JSON arrays of strings.

### Valid Examples

```json
// Single item
["SharePoint"]

// Multiple items
["SharePoint", "Dataverse", "Outlook"]

// Empty (monitor all access)
[]

// SharePoint sites
["https://contoso.sharepoint.com/sites/KB", "https://contoso.sharepoint.com/sites/HR"]

// Dataverse tables
["contact", "account", "case", "knowledgearticle"]

// External APIs
["https://api.contoso.com/v1", "https://data.contoso.com/graphql"]
```

### Invalid Examples

```json
// Not an array
"SharePoint"

// Null value
null

// Missing quotes
[SharePoint, Dataverse]

// Empty string (use [] instead)
""
```

---

## Empty Baselines

An empty baseline (all arrays set to `[]`) has special meaning:

| Behavior | Description |
|----------|-------------|
| **All access flagged** | Any data access creates a violation |
| **Use case** | New agents, pre-deployment validation |
| **Expected outcome** | High violation volume initially |

**To allow all access (no monitoring):**

Set baseline status to **Draft** or **Archived** instead of using empty arrays with Active status.

---

## Updating Baselines

### Manual Update

1. Open the agent scope record in Dataverse
2. Modify the allowed arrays
3. Save the record

**Note:** Changes take effect immediately for subsequent detection runs.

### Via Expansion Workflow

When a scope expansion request is approved:

1. SDM-ExpansionProcessor adds the resource to the appropriate array
2. No manual intervention required
3. Audit trail maintained in expansion request record

### Programmatic Update

```powershell
# Example: Add a SharePoint site to baseline
$scope = Get-DataverseRecord -EntityName "fsi_agentscope" -RecordId $scopeId
$currentSites = $scope.fsi_allowedsites | ConvertFrom-Json
$currentSites += "https://contoso.sharepoint.com/sites/NewSite"
$updatedSites = $currentSites | ConvertTo-Json -Compress

Update-DataverseRecord -EntityName "fsi_agentscope" -RecordId $scopeId -Data @{
    fsi_allowedsites = $updatedSites
    fsi_lastvalidated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}
```

---

## Best Practices

### Initial Setup

1. **Start with audit-generated baseline** - Captures actual access patterns
2. **Review before activating** - Remove unexpected or one-time access
3. **Set appropriate zone** - Affects detection frequency and approval rigor
4. **Document purpose clearly** - Helps reviewers understand expected access

### Ongoing Maintenance

1. **Review baselines quarterly** - Set `fsi_nextreview` dates
2. **Archive unused baselines** - Agents no longer in use
3. **Monitor violation trends** - High volume may indicate scope creep
4. **Use expansion workflow** - Maintains audit trail for changes

### Zone-Specific Guidance

**Zone 1 (Personal):**

- Broader allowed scope acceptable
- Security team approval for expansion (self-service planned for future)
- Focus on connector restrictions

**Zone 2 (Team):**

- Team-specific SharePoint sites
- Shared Dataverse tables
- Security team approval for expansion (team lead approval planned for future)

**Zone 3 (Enterprise):**

- Minimal required access only
- Security team approval required
- Regular compliance reviews

---

## Related Documentation

- [Flow Configuration](flow-configuration.md) - Detection and alert flows
- [Troubleshooting](troubleshooting.md) - Common issues and resolutions
- [Dataverse Schema](dataverse-schema.md) - Table definitions

---

*Scope Drift Monitor v1.1.2*
