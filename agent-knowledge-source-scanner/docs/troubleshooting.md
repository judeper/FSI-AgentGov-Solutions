# Troubleshooting

Common issues and resolutions for the Agent Knowledge Source Scanner.

## SharePoint Authentication

| Issue | Cause | Resolution |
|-------|-------|------------|
| `Connect-PnPOnline` fails with "Access denied" | Caller or app identity lacks access to the target SharePoint site | For interactive scans, verify the user has at least Site Member or Site Visitor read access. For managed identity or certificate scans, verify the app identity has access to the target site |
| Interactive login prompt does not appear | PnP.PowerShell version incompatibility or browser redirect issue | Update to PnP.PowerShell 2.5.0+ (`Update-Module PnP.PowerShell`); clear cached tokens with `Disconnect-PnPOnline` before retrying |
| "AADSTS50011: The redirect URI specified in the request does not match" | PnP.PowerShell app registration redirect mismatch | For PnP.PowerShell 3.x interactive auth, register a tenant-specific app with `Register-PnPEntraIDAppForInteractiveLogin` and pass `-ClientId`. For PnP 2.x, use `Register-PnPManagementShellAccess` to consent the legacy PnP multi-tenant app |
| Managed identity fails with token or audience errors | Runtime doesn't expose a managed identity or the identity lacks SharePoint/Graph permissions | Verify the job runs in Azure Automation, Azure Functions, Azure Cloud Shell, or another managed identity-capable host. Grant site access and group-read permissions before scanning |
| Certificate auth fails before item enumeration | Missing `-Tenant`, missing `-ClientId`, or certificate not available to the runner | Provide exactly one certificate selector (`-CertificateThumbprint`, `-CertificatePath`, or `-CertificateBase64Encoded`) and verify the app registration trusts that certificate |
| Authentication works but scan fails on specific sites | Multi-geo or cross-tenant site access | Each `Connect-PnPOnline` call targets one site; verify the user has access to every site listed in `-SiteUrl` or `-LibraryList` |

## Permission Enumeration

| Issue | Cause | Resolution |
|-------|-------|------------|
| "Failed to read permissions for '...'" warnings in output | Item-level permission reads require at least read access; item may be locked or restricted | Check the specific item path in the warning; verify the scanning user has access to that item |
| `PermissionType` shows "ScanError" in CSV output | An exception occurred reading role assignments for that item | Review the `AffectedUsers` column for the error message; common causes include throttled requests or permission inheritance issues |
| All items show `RiskScore = NONE` | No items have unique role assignments (all inherit from library) | This is expected when library permissions are uniform; use `-IncludeCompliant` to include inherited-permission items in the report |
| External/guest users not detected | Guest user login name format varies by tenant configuration | The scanner detects `#ext#` patterns and federated claim patterns; verify guest users exist on the target items by checking SharePoint's "Manage Access" panel |

## Agent User Scope Resolution

| Issue | Cause | Resolution |
|-------|-------|------------|
| "Failed to resolve group '...'" warning | The `-AgentUserGroupId` GUID does not exist or the user lacks group read permissions | Verify the group object ID in Entra ID; the scanning user needs `GroupMember.Read.All` or the Entra ID Reader role |
| "No agent user scope defined" warning | Neither `-AgentUserGroupId` nor `-AgentUserGroupMembers` was provided | Scope comparison is optional; provide one of these parameters to enable out-of-scope detection and CRITICAL/LOW risk scoring |
| Scope comparison misses some users | PnP.PowerShell 2.x fallback returns direct group members only, or a nested group lacks readable membership | Use PnP.PowerShell 3.x so the scanner can call `Get-PnPEntraIDGroupMember -Transitive`, or provide the full UPN list via `-AgentUserGroupMembers` |

## Large Library Handling

| Issue | Cause | Resolution |
|-------|-------|------------|
| Scan takes excessively long (>30 min per library) | Library contains thousands of items with unique permissions | Reduce `maxItemsPerLibrary`, split runs by library or folder, and schedule recurring scans outside business hours |
| "The attempted operation is prohibited because it exceeds the list view threshold" | SharePoint list view threshold (5,000 items) may affect some queries | PnP.PowerShell uses paged queries (`-PageSize 500`) to avoid this; if the error persists, verify the library is not blocked by tenant-level throttling policies |
| Script appears to hang during item enumeration | Large batch of items being retrieved with `Get-PnPListItem` paging or SharePoint throttling | The script processes items in pages of 500; check progress log messages every 100 items. If throttled, honor SharePoint `Retry-After` guidance by reducing concurrency and rerunning later |
| Out-of-memory on very large scans | Thousands of results accumulated in memory before CSV export | Split the scan across multiple runs using separate `-LibraryList` CSV files with subsets of libraries. Consider a future Microsoft Graph batching or delta traversal path for large recurring scans |

## PnP.PowerShell Module Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| "The term 'Connect-PnPOnline' is not recognized" | PnP.PowerShell module not installed or not imported | Run `Install-Module PnP.PowerShell -MinimumVersion 2.5.0 -Force -Scope CurrentUser` |
| Module version conflict | Multiple PnP.PowerShell versions installed | Run `Get-Module PnP.PowerShell -ListAvailable` to check; remove older versions with `Uninstall-Module PnP.PowerShell -RequiredVersion <old>` |
| `#Requires -Version 7.2` error | Script launched from Windows PowerShell 5.1 or an older PowerShell 7 runtime | Use `pwsh` 7.2+ (7.4+ for PnP.PowerShell 3.x) instead of `powershell.exe`; install from [PowerShell GitHub releases](https://github.com/PowerShell/PowerShell/releases) |
| `Get-PnPAzureADGroupMember` not found | PnP.PowerShell 3.x renamed this cmdlet to `Get-PnPEntraIDGroupMember` | Update to PnP.PowerShell 3.x and use `-AuthenticationMode Interactive -ClientId`, managed identity, or certificate auth. The scanner uses the current cmdlet first and falls back to the legacy cmdlet only when needed |

## Configuration Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| "Failed to parse config file" warning | JSON syntax error in custom config file | Validate the JSON file with `Get-Content config.json \| ConvertFrom-Json`; common issues include trailing commas or unquoted strings |
| Sensitivity label tier mapping not working | Label names in config do not match published label names exactly, or SharePoint stores label GUIDs in `_SensitivityLabel` | Label comparison is case-insensitive but must match the stored value. Check your tenant's published label names in the Microsoft Purview portal and add GUID values to the config if needed |
| Unsupported file format error | `-LibraryList` points to a file that is not `.csv` or `.json` | Rename or convert the input file to CSV or JSON format as documented in the README |

## Output and Reporting

| Issue | Cause | Resolution |
|-------|-------|------------|
| CSV report is empty | No items with permission risks were found | This may be correct; run with `-IncludeCompliant` to include all scanned items regardless of risk |
| Output directory does not exist error | Parent directory for `-OutputPath` cannot be created | The script auto-creates the immediate parent directory; verify the full path is valid and the user has write access |
| CSV encoding issues | Special characters in item titles or user names | The script exports with `-Encoding UTF8`; open the CSV in a tool that supports UTF-8 (Excel may require import wizard for correct encoding) |
