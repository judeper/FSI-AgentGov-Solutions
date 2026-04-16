# Agent Knowledge Source Scanner

> **Status:** Completed | **Version:** v1.0.3

Item-level permission scanning for SharePoint libraries connected to Copilot Studio agents as knowledge sources.

See [CHANGELOG](./CHANGELOG.md) for version history.

## Overview

When a Copilot Studio agent uses a SharePoint document library as a knowledge source, it retrieves and returns **exact document content** to users — not site-level summaries. If individual files within that library are overshared (accessible to users outside the agent's intended audience), the agent becomes a direct data exposure path.

This solution scans item-level permissions within agent-connected SharePoint libraries and produces a risk-scored report that identifies specific files and folders with overshared access. It complements site-level sharing analysis by examining the actual items an agent can surface.

### Why Item-Level Scanning Matters for Agent Knowledge Sources

| Scenario | Site-Level Scanner | Item-Level Scanner |
|----------|-------------------|--------------------|
| Library shared with "Everyone except external" | ✅ Detected | ✅ Detected |
| Individual file shared via Anyone link | ❌ Missed | ✅ Detected |
| Sensitivity-labeled file with broad internal access | ❌ Missed | ✅ Detected |
| File shared with external guest user | ❌ Missed (if site allows guests) | ✅ Detected |
| Folder with unique permissions broader than library | ❌ Missed | ✅ Detected |

## Features

| Feature | Description |
|---------|-------------|
| **Item-Level Enumeration** | Scans individual files and folders within agent knowledge source libraries |
| **Risk Scoring** | Agent-context-aware scoring (CRITICAL, HIGH, MEDIUM, LOW) stricter than general SharePoint |
| **Sensitivity Labels** | Cross-references sensitivity labels to identify high-risk oversharing combinations |
| **Agent Scope Comparison** | Compares item access against the agent's intended user group |
| **Multi-Library Input** | Accepts CSV or JSON listing of knowledge source libraries from prior scans |
| **Dry-Run Mode** | `-WhatIf` support for safe pre-scan validation |

## Risk Scoring

Risk scoring is stricter than general SharePoint oversharing analysis because agent knowledge sources create a direct content retrieval path.

| Risk Level | Criteria | Rationale |
|------------|----------|-----------|
| **CRITICAL** | High-sensitivity label (Highly Confidential, Restricted) AND accessible outside agent user group | Sensitive content directly surfaceable by agent to unauthorized users |
| **HIGH** | Anyone link OR external/guest user access on any knowledge source item | External data exposure through agent responses |
| **MEDIUM** | Organization-wide link with Edit access on a knowledge source item | Broad internal access exceeding need-to-know |
| **LOW** | Item accessible to a broader internal group than the agent's target audience | Potential scope creep beyond intended agent users |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│              Agent Knowledge Source Scanner                       │
├─────────────┬──────────────────┬────────────────┬───────────────┤
│ Library     │ Item Permission  │ Risk Scoring   │ Report        │
│ Resolver    │ Enumerator       │ Engine         │ Generator     │
└──────┬──────┴────────┬─────────┴────────┬───────┴───────────────┘
       │               │                  │
       ▼               ▼                  ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────────────────────┐
│ CSV/JSON     │ │ SharePoint   │ │ Configuration                │
│ Library List │ │ PnP API      │ │ (sensitivity tiers, scope)   │
└──────────────┘ └──────────────┘ └──────────────────────────────┘
                       │
                       ▼
              ┌──────────────────┐
              │  CSV Risk Report │
              └──────────────────┘
```

### Scan Sequence

```
1. Load configuration (item-scope-config.json)
2. Resolve scan targets from parameters or library list file
3. Resolve agent user scope (security group or UPN list)
4. For each library:
   a. Connect to SharePoint site via PnP PowerShell
   b. Enumerate items (up to maxItemsPerLibrary)
   c. For items with unique role assignments:
      - Read role assignments (permissions)
      - Classify permission type (AnonymousLink, ExternalUser, etc.)
      - Compare against agent user scope
      - Cross-reference sensitivity label
      - Calculate risk score
   d. Disconnect
5. Export CSV report
6. Display scan summary
```

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **SharePoint Online** | Access to agent knowledge source libraries |
| **Microsoft 365 E5** (recommended) | Sensitivity label support |

### Permissions

| Role | Required For |
|------|--------------|
| **SharePoint Site Collection Admin** or **Site Member** | Read item permissions in knowledge source libraries |
| **Entra ID Reader** | Resolve security group membership (when using -AgentUserGroupId) |

### Runtime Requirements

| Requirement | Minimum Version | Notes |
|-------------|----------------|-------|
| **PowerShell** | 7.0 (7.4+ for PnP 3.x) | |
| **PnP.PowerShell** | 2.5.0 | 3.x supported with `-ClientId` |

## Quick Start

### 1. Install Prerequisites

```powershell
# PnP.PowerShell 2.x (uses built-in multi-tenant app)
Install-Module -Name PnP.PowerShell -MinimumVersion 2.5.0 -Force -Scope CurrentUser

# OR PnP.PowerShell 3.x (requires tenant-specific app registration)
Install-Module -Name PnP.PowerShell -MinimumVersion 3.0.0 -Force -Scope CurrentUser
# See docs/prerequisites.md for Register-PnPEntraIDApp setup
```

### 2. Scan a Single Library

```powershell
# PnP.PowerShell 2.x (no -ClientId needed)
.\scripts\Get-KnowledgeSourceItemPermissions.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/AgentKB" `
    -LibraryName "Documents" `
    -AgentName "HR-Agent" `
    -AgentUserGroupId "00000000-0000-0000-0000-000000000001"

# PnP.PowerShell 3.x (requires -ClientId)
.\scripts\Get-KnowledgeSourceItemPermissions.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/AgentKB" `
    -LibraryName "Documents" `
    -AgentName "HR-Agent" `
    -AgentUserGroupId "00000000-0000-0000-0000-000000000001" `
    -ClientId "your-client-id-here"
```

### 3. Scan Multiple Libraries from a List

```powershell
# Using a CSV file (SiteUrl, LibraryName, AgentName columns)
.\scripts\Get-KnowledgeSourceItemPermissions.ps1 `
    -LibraryList "./output/agent-knowledge-sources.csv" `
    -AgentUserGroupId "00000000-0000-0000-0000-000000000001" `
    -OutputPath "./output/item-risk-report.csv"
```

### 4. Dry-Run Mode

```powershell
.\scripts\Get-KnowledgeSourceItemPermissions.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/AgentKB" `
    -AgentUserGroupMembers @("user1@contoso.com", "user2@contoso.com") `
    -WhatIf
```

## Solution Components

```
agent-knowledge-source-scanner/
├── README.md                   # This file
├── CHANGELOG.md                # Version history
├── docs/                       # Additional documentation
├── scripts/
│   └── Get-KnowledgeSourceItemPermissions.ps1   # Item-level permission scanner
└── templates/
    └── item-scope-config.sample.json            # Configuration template
```

## Configuration

The `item-scope-config.sample.json` file controls scan behavior:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `scanScope` | string | `agent-knowledge-sources-only` | Scan scope identifier |
| `sensitivityLabelRiskTiers` | object | See below | Maps sensitivity label names to risk tiers |
| `agentUserScopeResolution` | string | `from-parameter` | How agent user scope is determined |
| `maxItemsPerLibrary` | integer | `10000` | Maximum items to scan per library |
| `outputPath` | string | `./output/item-permissions-report.csv` | Default output file path |

### Sensitivity Label Risk Tiers (Defaults)

| Tier | Labels |
|------|--------|
| CRITICAL | Highly Confidential, Restricted |
| HIGH | Confidential, Internal Confidential |
| MEDIUM | Internal |
| LOW | Public, General |

Customize these tiers in the config file to match your organization's sensitivity label taxonomy.

## Output Format

The CSV report includes these columns:

| Column | Description |
|--------|-------------|
| `AgentName` | Name of the agent using this knowledge source |
| `KnowledgeSourceSite` | SharePoint site URL |
| `LibraryName` | Document library name |
| `ItemPath` | Server-relative path to the file or folder |
| `ItemTitle` | Item title or filename |
| `SensitivityLabel` | Applied sensitivity label (or "None") |
| `BroadPermission` | SharePoint permission level (Read, Edit, Full Control) |
| `PermissionType` | Classification (AnonymousLink, ExternalUser, OrganizationLink, DirectPermission, etc.) |
| `AffectedUsers` | Users or groups with access |
| `RiskScore` | CRITICAL, HIGH, MEDIUM, or LOW |

## Documentation

| Document | Description |
|----------|-------------|
| [Prerequisites](docs/prerequisites.md) | PowerShell modules, permissions, network endpoints, and configuration |
| [Troubleshooting](docs/troubleshooting.md) | Common issues with authentication, permissions, large libraries, and PnP.PowerShell |

## Related Controls

| Control | Description | Relationship |
|---------|-------------|--------------|
| [4.3 - SharePoint Oversharing Prevention](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-4-sharepoint/4.3-sharepoint-oversharing-prevention-for-agents.md) | Prevent agents from accessing overshared content | Primary |
| [1.4 - Data Boundary Enforcement](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.4-data-boundary-enforcement.md) | Enforce data boundaries for agent access | Related |
| [1.5 - DLP Policy Application](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.5-dlp-policy-application.md) | Apply DLP policies to agent data access | Related |

## Regulatory Context

| Regulation | Relevance |
|------------|-----------|
| **GLBA 501(b)** | Information security safeguards for customer data accessed through agent knowledge sources |
| **FINRA 4511** | Record-keeping requirements for access control assessments and evidence of permission reviews |
| **SEC 17a-3/4** | Retention of scan evidence demonstrating periodic access validation |

This solution supports compliance with these regulations by providing auditable evidence that agent knowledge source permissions have been reviewed for oversharing. Organizations should store scan output CSV files on immutable media (e.g., Azure Blob Storage with WORM policy) to meet SEC 17a-4(f) non-rewritable storage requirements.

## Known Limitations

| Limitation | Description | Workaround |
|------------|-------------|------------|
| **PnP interactive auth only** | v1.0.x uses `-Interactive` authentication; service principal auth for unattended scanning is planned | Run interactively or use PnP PowerShell's certificate-based auth manually |
| **PnP.PowerShell 3.x requires `-ClientId`** | The PnP multi-tenant app was removed in September 2024; PnP 3.x requires a tenant-specific Entra app registration | Register an app with `Register-PnPEntraIDApp` and pass `-ClientId` (see [Prerequisites](docs/prerequisites.md)) |
| **No agent definition auto-resolution** | Agent user scope must be provided manually; automated resolution from Copilot Studio agent definition is not yet implemented | Provide `-AgentUserGroupId` or `-AgentUserGroupMembers` parameter |
| **Sensitivity label field availability** | `_SensitivityLabel` field requires Microsoft Information Protection labels to be published; falls back to `_ComplianceTag` | Verify sensitivity labels are enabled in your tenant |
| **Large library performance** | Scanning libraries with 10,000+ items may take significant time | Adjust `maxItemsPerLibrary` in config or use `-MaxItemsPerLibrary` parameter |

## License

[MIT](../LICENSE)

---

*FSI Agent Governance Framework — Agent Knowledge Source Scanner v1.0.3*
