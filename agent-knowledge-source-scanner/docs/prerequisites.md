# Prerequisites

Requirements for deploying the Agent Knowledge Source Scanner solution.

## PowerShell Requirements

| Requirement | Version | Purpose |
|-------------|---------|---------|
| PowerShell | 7.2+ (7.4+ for PnP 3.x) | Core runtime (`#Requires -Version 7.2`) |
| PnP.PowerShell | 3.x recommended; 2.5.0+ legacy fallback | SharePoint Online item enumeration, permission reads, sensitivity label retrieval, and Entra group expansion |

## Installation

### PnP.PowerShell 3.x (recommended)

```powershell
Install-Module -Name PnP.PowerShell -MinimumVersion 3.0.0 -Force -Scope CurrentUser
```

### PnP.PowerShell 2.x (legacy fallback)

```powershell
Install-Module -Name PnP.PowerShell -MinimumVersion 2.5.0 -Force -Scope CurrentUser
```

> **Note:** PnP.PowerShell 2.5.0+ requires PowerShell 7.2 or later. Windows PowerShell 5.1 and PowerShell 7.0/7.1 are not supported. Use PnP.PowerShell 3.x for managed identity, current cmdlet names, and transitive Entra group expansion.

## Authentication Modes

Use the strongest authentication mode available for the runtime:

| Priority | Mode | Script parameters | Recommended host |
|----------|------|-------------------|------------------|
| 1 | System-assigned managed identity | `-AuthenticationMode ManagedIdentity` | Azure Automation, Azure Functions, Azure-hosted runners |
| 2 | User-assigned managed identity | `-AuthenticationMode ManagedIdentity -ManagedIdentityClientId <client-id>` | Shared Azure automation hosts |
| 3 | Certificate app-only | `-AuthenticationMode Certificate -ClientId <id> -Tenant <tenant> -CertificateThumbprint <thumbprint>` | Legacy unattended jobs that can't use managed identity |
| 4 | Interactive | `-AuthenticationMode Interactive -ClientId <id>` | Admin workstation validation |

Client secrets are intentionally not exposed by this script. If a development-only client secret path is ever added, mark it as legacy and do not document it as a production pattern.

### PnP.PowerShell 3.x

PnP.PowerShell 3.x introduces breaking changes that affect authentication:

| Change | Detail |
|--------|--------|
| **PowerShell 7.4+** required | Minimum runtime raised from 7.0 to 7.4 |
| **.NET 8.0** required | Runtime dependency upgraded from .NET 6.0 |
| **Multi-tenant app removed** | The PnP multi-tenant app registration (`31359c7f-bd7e-475c-86db-fdb8c937548e`) was removed in September 2024 |
| **Interactive client ID required** | Interactive `Connect-PnPOnline` requires a tenant-specific Entra app registration or supported client ID environment variable |
| **Cmdlet renames** | `Get-PnPAzureADGroupMember` renamed to `Get-PnPEntraIDGroupMember` (this script handles both automatically) |

```powershell
# Install PnP.PowerShell 3.x
Install-Module -Name PnP.PowerShell -MinimumVersion 3.0.0 -Force -Scope CurrentUser
```

#### Register a Tenant-Specific Entra App

PnP.PowerShell 3.x requires a tenant-specific Entra app registration. Use the built-in registration command:

```powershell
# Register an interactive PnP app in your tenant (requires admin consent)
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "PnP.PowerShell - AgentGov Scanner" `
    -Tenant "example.onmicrosoft.com" `
    -SharePointDelegatePermissions "AllSites.Read" `
    -GraphDelegatePermissions "Group.Read.All"
```

Record the **Client ID** from the output. Pass it to the scanner with `-AuthenticationMode Interactive -ClientId`:

```powershell
.\scripts\Get-KnowledgeSourceItemPermissions.ps1 `
    -SiteUrl "https://example.sharepoint.com/sites/AgentKB" `
    -LibraryName "Documents" `
    -AgentName "HR-Agent" `
    -AgentUserGroupId "00000000-0000-0000-0000-000000000001" `
    -AuthenticationMode Interactive `
    -ClientId "your-client-id-here"
```

> **Note:** The script detects PnP.PowerShell 3.x at runtime and produces a clear error if interactive authentication lacks `-ClientId` or a supported client ID environment variable (`ENTRAID_CLIENT_ID` or `ENTRAID_APP_ID`).

### Managed Identity

Managed identity is the recommended unattended pattern for Azure-hosted runs. Grant the managed identity access to the target SharePoint sites (for example, a Sites.Selected grant administered by SharePoint admins) and Microsoft Graph group-read permissions if `-AgentUserGroupId` is used.

```powershell
.\scripts\Get-KnowledgeSourceItemPermissions.ps1 `
    -SiteUrl "https://example.sharepoint.com/sites/AgentKB" `
    -LibraryName "Documents" `
    -AgentName "HR-Agent" `
    -AgentUserGroupId "00000000-0000-0000-0000-000000000001" `
    -AuthenticationMode ManagedIdentity
```

For a user-assigned managed identity, add one selector such as `-ManagedIdentityClientId <client-id>`.

### Certificate App-Only

Use certificate app-only authentication only when managed identity isn't available. The app registration needs SharePoint application permissions or site-specific grants for target sites, plus Microsoft Graph group-read permissions when resolving agent user groups.

```powershell
.\scripts\Get-KnowledgeSourceItemPermissions.ps1 `
    -SiteUrl "https://example.sharepoint.com/sites/AgentKB" `
    -LibraryName "Documents" `
    -AgentName "HR-Agent" `
    -AuthenticationMode Certificate `
    -ClientId "your-client-id-here" `
    -Tenant "example.onmicrosoft.com" `
    -CertificateThumbprint "0123456789ABCDEF0123456789ABCDEF01234567"
```

## Permissions

### SharePoint Online

The executing user must have permission to read item-level details and role assignments in each target library.

| Role | Required For |
|------|--------------|
| **Site Collection Admin** or **Site Member** (with read access) | Enumerate items and read role assignments in knowledge source libraries |

For delegated interactive scans, the signed-in user must have at least read access to the target SharePoint site and library. For managed identity or certificate app-only scans, the app identity must have SharePoint access to every target site and library.

### Entra ID (Optional — Group Resolution)

When using the `-AgentUserGroupId` parameter to resolve agent user scope from a security group, the signed-in user needs permission to read group membership.

| Permission | Type | Required For |
|------------|------|--------------|
| **GroupMember.Read.All** or **Group.Read.All** | Delegated or application, matching the authentication mode | Resolve security group members via `Get-PnPEntraIDGroupMember -Transitive` (PnP 3.x) or `Get-PnPAzureADGroupMember` direct-member fallback (PnP 2.x) |
| **Entra ID Reader** role | Directory | Alternative: read group membership via directory role |

If group resolution fails, the script logs a warning and continues without agent user scope comparison. For nested groups, use PnP.PowerShell 3.x so the scanner can request transitive membership.

### Sensitivity Labels (Optional)

For sensitivity label cross-referencing, Microsoft Purview sensitivity labels must be published to the target SharePoint sites. The scanner reads the `_SensitivityLabel` field on items, falling back to `_ComplianceTag` if unavailable. Copilot Studio can display sensitivity labels for supported knowledge sources, but encrypted or password-protected files may have indexing limitations depending on how the source was added.

| Requirement | Purpose |
|-------------|---------|
| Microsoft 365 E5 or E5 Compliance (recommended) | Sensitivity labels on SharePoint items |
| Microsoft Purview labels published to target sites | `_SensitivityLabel` field populated on library items |

Without sensitivity labels, risk scoring still functions but the CRITICAL tier (high-sensitivity + out-of-scope) cannot be evaluated.

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `*.sharepoint.com` | HTTPS | SharePoint Online site and item access via PnP PowerShell |
| `login.microsoftonline.com` | HTTPS | OAuth token acquisition (interactive authentication) |
| `graph.microsoft.com` | HTTPS | Entra ID group membership resolution (when using `-AgentUserGroupId`) |

## Configuration File

The scanner loads default settings from `templates/item-scope-config.sample.json`. Copy and customize for your environment:

```powershell
Copy-Item .\templates\item-scope-config.sample.json .\templates\item-scope-config.json
```

Key configuration options:

| Setting | Default | Description |
|---------|---------|-------------|
| `maxItemsPerLibrary` | `10000` | Maximum items scanned per library (override with `-MaxItemsPerLibrary`) |
| `sensitivityLabelRiskTiers` | See config file | Maps sensitivity label names to risk tiers (CRITICAL, HIGH, MEDIUM, LOW) |
| `outputPath` | `./output/item-permissions-report.csv` | Default report output location |

## Related Controls

This solution supports compliance with controls [4.8](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-4-sharepoint/4.8-item-level-permission-scanning-agent-knowledge-sources.md), [1.4](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.4-advanced-connector-policies-acp.md), and [1.5](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.5-data-loss-prevention-dlp-and-sensitivity-labels.md). Organizations should verify that scanning coverage meets their specific regulatory obligations.
