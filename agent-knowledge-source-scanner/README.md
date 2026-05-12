---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P2]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# Agent Knowledge Source Scanner

> **Status:** Completed | **Version:** v1.1.1

Item-level permission scanning for SharePoint libraries backing Copilot Studio agent knowledge sources.

See [CHANGELOG](./CHANGELOG.md) for version history.

## Overview

When a Copilot Studio agent uses SharePoint content as a knowledge source, it can cite **exact file content** after user permission checks — not just site-level summaries. If individual files or folders in the underlying SharePoint library are overshared (accessible to users outside the agent's intended audience), the agent becomes a direct data exposure path.

This solution scans item-level permissions within SharePoint libraries that back agent knowledge sources and produces a risk-scored report that identifies specific files and folders with overshared access. It complements site-level sharing analysis by examining the actual items an agent can surface.

### Current SharePoint Knowledge Source Coverage

| Knowledge source pattern | Scanner coverage | Notes |
|--------------------------|------------------|-------|
| SharePoint connector / full SharePoint integration | Scan libraries containing the referenced site, folder, or file content | Use exported or curated library lists for the agent's SharePoint scope |
| SharePoint files and folders added as unstructured data | Scan the containing library and selected folder subtree where known | Copilot Studio currently supports selecting SharePoint files and folders in this path; uploaded-file sources are separate |
| Uploaded files stored in Dataverse | Out of scope | These files don't use SharePoint item permissions after upload |
| OneDrive files and folders | Out of scope by default | Apply the same permission-review pattern separately if OneDrive sources are approved |

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
| **CRITICAL** | CRITICAL-tier sensitivity label (Highly Confidential, Restricted) AND accessible outside agent user group | Sensitive content directly surfaceable by agent to unauthorized users |
| **HIGH** | Anyone link, external/guest user access, OR HIGH-tier sensitivity label out-of-scope | External data exposure or near-critical sensitivity exposed beyond intended audience |
| **MEDIUM** | Organization-wide link with **write-equivalent** access (Edit / Contribute / Full Control) on a knowledge source item | Broad internal access with mutation rights exceeding need-to-know |
| **LOW** | Item accessible to a broader internal group than the agent's target audience, read-only org-wide link, or `FlexibleLink` (per-recipient grants we cannot enumerate) | Potential scope creep beyond intended agent users |

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
│ Library List │ │ PnP/CSOM     │ │ (sensitivity tiers, scope)   │
└──────────────┘ └──────────────┘ └──────────────────────────────┘
                       │
                       ▼
              ┌──────────────────┐
              │  CSV Risk Report │
              └──────────────────┘
```

### Microsoft Graph and SharePoint API Alignment

The current implementation uses PnP.PowerShell over SharePoint client APIs because it exposes SharePoint role assignments and list item fields in a compact PowerShell workflow. Current Microsoft Graph v1.0 APIs are still important for validation and future enhancement:

| API area | Current status | Scanner implication |
|----------|----------------|---------------------|
| `/drives/{drive-id}/items/{item-id}/permissions` | v1.0 lists effective sharing permissions on a file or folder | Future Graph mode can use `link.scope`, `roles`, and `grantedToIdentitiesV2` to expand specific-people links more precisely |
| `/sites/{site-id}/permissions` | v1.0 lists site permissions and requires high privilege (`Sites.FullControl.All`) | Useful for site-level app permission review, but not a replacement for item-level file/folder permission scans |
| SharePoint REST / CSOM | Still supported; Microsoft recommends Graph over CSOM/REST when Graph covers the scenario | PnP remains the implementation path for this release; large-scale scans should consider Graph batching or delta traversal in a future version |
| Graph JSON batching | Supports up to 20 requests per batch; individual requests can still be throttled | Future Graph mode should retry throttled subrequests using each response's `retry-after` value |

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
| **PowerShell** | 7.2+ (7.4+ for PnP 3.x) | Matches script `#Requires -Version 7.2` |
| **PnP.PowerShell** | 3.x recommended; 2.5.0+ legacy fallback | 3.x supports tenant-specific app registrations, managed identity, certificate auth, and transitive group expansion |

## Quick Start

### 1. Install Prerequisites

```powershell
# Recommended: PnP.PowerShell 3.x
Install-Module -Name PnP.PowerShell -MinimumVersion 3.0.0 -Force -Scope CurrentUser

# Legacy fallback: PnP.PowerShell 2.5.0+ for admin workstation scans
Install-Module -Name PnP.PowerShell -MinimumVersion 2.5.0 -Force -Scope CurrentUser
# See docs/prerequisites.md for managed identity, certificate, and interactive setup
```

### 2. Scan a Single Library

```powershell
# Recommended for Azure Automation / Azure Functions: managed identity
.\scripts\Get-KnowledgeSourceItemPermissions.ps1 `
    -SiteUrl "https://example.sharepoint.com/sites/AgentKB" `
    -LibraryName "Documents" `
    -AgentName "HR-Agent" `
    -AgentUserGroupId "00000000-0000-0000-0000-000000000001" `
    -AuthenticationMode ManagedIdentity

# Admin workstation fallback: interactive PnP.PowerShell 3.x app registration
.\scripts\Get-KnowledgeSourceItemPermissions.ps1 `
    -SiteUrl "https://example.sharepoint.com/sites/AgentKB" `
    -LibraryName "Documents" `
    -AgentName "HR-Agent" `
    -AgentUserGroupId "00000000-0000-0000-0000-000000000001" `
    -AuthenticationMode Interactive `
    -ClientId "your-client-id-here"
```

### 3. Scan Multiple Libraries from a List

```powershell
# Using a CSV file (SiteUrl, LibraryName, AgentName columns)
.\scripts\Get-KnowledgeSourceItemPermissions.ps1 `
    -LibraryList "./output/agent-knowledge-sources.csv" `
    -AgentUserGroupId "00000000-0000-0000-0000-000000000001" `
    -AuthenticationMode ManagedIdentity `
    -OutputPath "./output/item-risk-report.csv"
```

### 4. Dry-Run Mode

```powershell
.\scripts\Get-KnowledgeSourceItemPermissions.ps1 `
    -SiteUrl "https://example.sharepoint.com/sites/AgentKB" `
    -AgentUserGroupMembers @("user1@example.com", "user2@example.com") `
    -WhatIf
```

## Microsoft Graph Permissions

When using the Graph v1.0 scanner (`Invoke-GraphPermissionScan.ps1`), the following Microsoft Graph application or delegated permissions are required:

| Permission | Type | Purpose |
|-----------|------|---------|
| `Sites.Read.All` | Application or Delegated | Read SharePoint site and drive metadata |
| `Files.Read.All` | Application or Delegated | Read file content and item permissions |
| `Group.Read.All` | Application or Delegated | Resolve Entra ID group membership for permission grants |

For delegated flows, the signed-in user must also have access to the target SharePoint site. For application-only flows, admin consent is required.

## Graph v1.0 Permission Scan Mode

The `Invoke-GraphPermissionScan.ps1` script provides an alternative scan path using Microsoft Graph v1.0 APIs instead of PnP/CSOM:

- Uses `/drives/{driveId}/items/{itemId}/permissions` (v1.0, not beta)
- Resolves `grantedToIdentitiesV2` for specific-people links (addressing the `FlexibleLink` limitation in the PnP scanner)
- Implements JSON batching with a hard cap of 20 requests per batch ([Graph documented limit](https://learn.microsoft.com/graph/json-batching))
- Handles `Retry-After` headers on 429/503 responses; falls back to exponential backoff when the header is absent

```powershell
# Get an access token (requires Sites.Read.All, Files.Read.All, Group.Read.All)
$token = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token

# Scan permissions for specific drive items
.\scripts\Invoke-GraphPermissionScan.ps1 `
    -DriveId "b!xyzDriveId" `
    -ItemIds @("01ABCDEF", "02GHIJKL", "03MNOPQR") `
    -AccessToken $token
```

## Solution Components

```
agent-knowledge-source-scanner/
├── README.md                   # This file
├── CHANGELOG.md                # Version history
├── docs/                       # Additional documentation
├── scripts/
│   ├── Get-KnowledgeSourceItemPermissions.ps1   # Item-level permission scanner (PnP/CSOM)
│   └── Invoke-GraphPermissionScan.ps1           # Graph v1.0 batched permission scanner
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
| **Specific-people link detail** | PnP role assignments surface these as `FlexibleLink` without recipient details | Use the Graph v1.0 scanner (`Invoke-GraphPermissionScan.ps1`) which resolves `grantedToIdentitiesV2` for specific-people links, or review the SharePoint Manage Access panel |
| **PnP.PowerShell 3.x interactive auth requires a client ID** | The PnP multi-tenant app was removed in September 2024; interactive auth needs a tenant-specific Entra app registration or supported environment variable | Register an app with `Register-PnPEntraIDAppForInteractiveLogin` and pass `-ClientId` (see [Prerequisites](docs/prerequisites.md)) |
| **No agent definition auto-resolution** | Agent user scope must be provided manually; automated resolution from Copilot Studio agent definition is not yet implemented | Provide `-AgentUserGroupId` or `-AgentUserGroupMembers` parameter |
| **Sensitivity label field availability** | `_SensitivityLabel` field requires Microsoft Purview sensitivity labels to be published; falls back to `_ComplianceTag` | Verify sensitivity labels are enabled in your tenant; encrypted or password-protected files can have Copilot Studio indexing limitations depending on source type |
| **Large library performance** | Scanning libraries with 10,000+ items may take significant time | Adjust `maxItemsPerLibrary`, split scans by library/folder, and consider a future Graph batching or delta traversal path |

## License

[MIT](../LICENSE)

---

*FSI Agent Governance Framework — Agent Knowledge Source Scanner v1.1.1*
