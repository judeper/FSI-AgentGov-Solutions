# Prerequisites

Requirements for deploying the Agent Knowledge Source Scanner solution.

## PowerShell Requirements

| Requirement | Version | Purpose |
|-------------|---------|---------|
| PowerShell | 7.0+ | Core runtime (`#Requires -Version 7.0`) |
| PnP.PowerShell | 2.5.0+ | SharePoint Online item enumeration, permission reads, sensitivity label retrieval |

## Installation

```powershell
# Install PnP.PowerShell module
Install-Module -Name PnP.PowerShell -MinimumVersion 2.5.0 -Force -Scope CurrentUser
```

> **Note:** PnP.PowerShell 2.5.0+ requires PowerShell 7.0 or later. Windows PowerShell 5.1 is not supported.

## Permissions

### SharePoint Online

The executing user must have permission to read item-level details and role assignments in each target library.

| Role | Required For |
|------|--------------|
| **Site Collection Admin** or **Site Member** (with read access) | Enumerate items and read role assignments in knowledge source libraries |

The script uses `Connect-PnPOnline -Interactive` which triggers a delegated (user) authentication flow. The signed-in user must have at least read access to the target SharePoint site and library.

### Entra ID (Optional — Group Resolution)

When using the `-AgentUserGroupId` parameter to resolve agent user scope from a security group, the signed-in user needs permission to read group membership.

| Permission | Type | Required For |
|------------|------|--------------|
| **GroupMember.Read.All** or **Group.Read.All** | Delegated | Resolve security group members via `Get-PnPAzureADGroupMember` |
| **Entra ID Reader** role | Directory | Alternative: read group membership via directory role |

If group resolution fails, the script logs a warning and continues without agent user scope comparison.

### Sensitivity Labels (Optional)

For sensitivity label cross-referencing, Microsoft Information Protection labels must be published to the target SharePoint sites. The scanner reads the `_SensitivityLabel` field on items, falling back to `_ComplianceTag` if unavailable.

| Requirement | Purpose |
|-------------|---------|
| Microsoft 365 E5 or E5 Compliance (recommended) | Sensitivity labels on SharePoint items |
| MIP labels published to target sites | `_SensitivityLabel` field populated on library items |

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

This solution supports compliance with controls [4.3](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-4-sharepoint/4.3-sharepoint-oversharing-prevention-for-agents.md), [1.4](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.4-data-boundary-enforcement.md), and [1.5](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.5-dlp-policy-application.md). Organizations should verify that scanning coverage meets their specific regulatory obligations.
