# Troubleshooting

Common issues and resolutions for the Agent Knowledge Source Scanner.

## SharePoint Authentication

| Issue | Cause | Resolution |
|-------|-------|------------|
| `Connect-PnPOnline` fails with "Access denied" | Signed-in user lacks access to the target SharePoint site | Verify the user has at least Site Member or Site Visitor read access to the target site collection |
| Interactive login prompt does not appear | PnP.PowerShell version incompatibility or browser redirect issue | Update to PnP.PowerShell 2.5.0+ (`Update-Module PnP.PowerShell`); clear cached tokens with `Disconnect-PnPOnline` before retrying |
| "AADSTS50011: The redirect URI specified in the request does not match" | PnP.PowerShell app registration redirect mismatch | Register your own Entra ID app and use `-ClientId` with `Connect-PnPOnline`, or use `Register-PnPManagementShellAccess` to consent the PnP multi-tenant app |
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
| Scope comparison misses some users | Nested group membership is not fully resolved | `Get-PnPAzureADGroupMember` returns direct members only; flatten nested groups manually or provide the full UPN list via `-AgentUserGroupMembers` |

## Large Library Handling

| Issue | Cause | Resolution |
|-------|-------|------------|
| Scan takes excessively long (>30 min per library) | Library contains thousands of items with unique permissions | Reduce `maxItemsPerLibrary` in the config file or use `-MaxItemsPerLibrary 1000` to limit the scan scope for initial assessment |
| "The attempted operation is prohibited because it exceeds the list view threshold" | SharePoint list view threshold (5,000 items) may affect some queries | PnP.PowerShell uses paged queries (`-PageSize 500`) to avoid this; if the error persists, verify the library is not blocked by tenant-level throttling policies |
| Script appears to hang during item enumeration | Large batch of items being retrieved with `Get-PnPListItem` paging | The script processes items in pages of 500; check the console for progress log messages (every 100 items). Reduce `-MaxItemsPerLibrary` for faster iterations |
| Out-of-memory on very large scans | Thousands of results accumulated in memory before CSV export | Split the scan across multiple runs using separate `-LibraryList` CSV files with subsets of libraries |

## PnP.PowerShell Module Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| "The term 'Connect-PnPOnline' is not recognized" | PnP.PowerShell module not installed or not imported | Run `Install-Module PnP.PowerShell -MinimumVersion 2.5.0 -Force -Scope CurrentUser` |
| Module version conflict | Multiple PnP.PowerShell versions installed | Run `Get-Module PnP.PowerShell -ListAvailable` to check; remove older versions with `Uninstall-Module PnP.PowerShell -RequiredVersion <old>` |
| "Requires PowerShell 7.0" error | Script launched from Windows PowerShell 5.1 | Use `pwsh` (PowerShell 7+) instead of `powershell.exe`; install from [PowerShell GitHub releases](https://github.com/PowerShell/PowerShell/releases) |
| `Get-PnPAzureADGroupMember` not found | Older PnP.PowerShell version or PnP module rename | In PnP.PowerShell 2.x, the cmdlet name may vary; update to 2.5.0+ where the cmdlet is available |

## Configuration Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| "Failed to parse config file" warning | JSON syntax error in custom config file | Validate the JSON file with `Get-Content config.json \| ConvertFrom-Json`; common issues include trailing commas or unquoted strings |
| Sensitivity label tier mapping not working | Label names in config do not match published label names exactly | Label comparison is case-insensitive but must match the exact label name; check your tenant's published label names in the Microsoft Purview compliance portal |
| Unsupported file format error | `-LibraryList` points to a file that is not `.csv` or `.json` | Rename or convert the input file to CSV or JSON format as documented in the README |

## Output and Reporting

| Issue | Cause | Resolution |
|-------|-------|------------|
| CSV report is empty | No items with permission risks were found | This may be correct; run with `-IncludeCompliant` to include all scanned items regardless of risk |
| Output directory does not exist error | Parent directory for `-OutputPath` cannot be created | The script auto-creates the immediate parent directory; verify the full path is valid and the user has write access |
| CSV encoding issues | Special characters in item titles or user names | The script exports with `-Encoding UTF8`; open the CSV in a tool that supports UTF-8 (Excel may require import wizard for correct encoding) |
