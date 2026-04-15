# Troubleshooting Guide

Common issues and resolutions for the Content Moderation Governance Monitor solution.

---

## Deployment Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Tables not created | Insufficient Dataverse permissions | Verify executing identity has System Administrator or System Customizer role |
| Environment variables missing | `deploy.py --vars-only` not run or failed | Re-run `python scripts/deploy.py --vars-only`; check for existing variables with same schema name |
| Connection reference errors | Connector not available in environment | Verify Office 365 Outlook, Teams, and Dataverse connectors are available in the target environment |
| `deploy.py` fails with 403 | MSAL token lacks Dataverse scope | Verify app registration has `user_impersonation` scope for Dataverse; re-authenticate |
| Duplicate option set error | `fsi_acv_zone` or `fsi_acv_severity` already exists from ACV/SSC deployment | Expected — `create_dataverse_schema.py` checks for existing option sets before creation |

---

## Authentication Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Certificate auth 401 | Certificate not associated with app registration | Upload certificate to the app registration in Entra ID; verify thumbprint matches |
| MSAL token error | `MSAL.PS` module not installed | Run `Install-Module MSAL.PS -Scope CurrentUser` |
| Dataverse 401 Unauthorized | Token expired or wrong audience | Re-authenticate; verify token audience matches Dataverse URL |
| Dataverse 403 Forbidden | Missing security role in target environment | Add executing identity as application user with read access to CMM tables |
| `ConvertFrom-SecureString` error: "A parameter cannot be found that matches parameter name 'AsPlainText'" | Running on Windows PowerShell 5.1 — the `-AsPlainText` parameter requires PowerShell 7.0+ | Install PowerShell 7.1+ as documented in [PREREQUISITES.md](PREREQUISITES.md). Run scripts with `pwsh` (not `powershell`) |
| Interactive auth popup blocked | PowerShell session does not support interactive UI | Use `-CertificateThumbprint` and `-ClientId` for non-interactive auth |

---

## Validation Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| No agents found | Environment has no Copilot Studio bots, or bots are all drafts | Verify bots exist; use `-IncludeDrafts` to scan unpublished agents |
| Unknown moderation level | Bot `configuration` JSON does not contain content moderation settings | Agent may not have generative AI enabled; Unknown agents receive Warning severity |
| **All** agents show Unknown level | The `bot.configuration` JSON key for content moderation may have changed (Microsoft undocumented internal schema) | Verify at least one agent returns a known level (Low/Medium/High). If none do, contact Microsoft support or check Copilot Studio release notes for schema changes. The script emits a warning when this occurs. |
| Zone lookup failure | ELM `fsi_environmentlifecycles` table not deployed or empty | Verify ELM deployment; falls back to naming convention matching (`-Z1-`, `-Z2-`, `-Z3-` in environment name) |
| Bot metadata query error | Environment Dataverse not provisioned | Skip environments without Dataverse; these cannot host Copilot Studio bots |
| Sandbox environments included | `fsi_CMM_IncludeSandbox` set to true | Set environment variable to `false` or use `-ExcludeSandbox` parameter |
| Moderation level shows "strict" | Older Copilot Studio version uses non-standard labels | `Get-BotModerationLevel` normalizes "strict" → "High", "standard" → "Medium", and "moderate" → "Medium" |

---

## Drift Detection Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| No baseline found for agent | `Invoke-ModerationBaselineCapture.ps1` not yet run | Capture initial baselines: `.\scripts\Invoke-ModerationBaselineCapture.ps1 -DataverseUrl ...` |
| Drift always detected | Baseline agent ID does not match current bot GUID | Re-capture baselines; bot GUIDs may change after republish |
| Baseline deactivation failure | Dataverse update permission missing | Verify executing identity has write access to `fsi_moderationbaselines` table |
| Runbook timeout on large tenant | Many environments with many agents per environment | Increase Azure Automation job timeout; consider filtering by zone (`-Zone 3`) |
| Stale baseline warning | Baseline older than `fsi_CMM_BaselineMaxAgeDays` | Re-capture baselines to refresh timestamps |

---

## Evidence Export Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Empty evidence file | No validation scans in date range | Check `FromDate`/`ToDate` parameters; verify scans have been executed |
| Hash mismatch after file copy | File encoding changed during transfer | Re-export from source system; ensure UTF-8 encoding preserved during copy |
| ConvertTo-Json truncation | Nested objects beyond serialization depth | Script uses `-Depth 10`; if still truncated, inspect source data structure |
| Zone filter returns no results | No violations for specified zone | Verify zone classification is correct; try `-Zone All` first |
| Pagination timeout | Very large validation history (10000+ records) | Narrow date range with `-FromDate` and `-ToDate` parameters |
| Missing baselines section | `-IncludeBaselines` not specified | Re-run with `-IncludeBaselines` switch |

---

## Power Automate Flow Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Flow not triggering | Recurrence trigger misconfigured or flow disabled | Verify flow is turned on; check recurrence interval (default: 24 hours) |
| Adaptive card not posting | Teams connection reference not configured | Open flow → edit → update `fsi_cr_teams_moderationmonitor` connection reference |
| Connection reference not configured | First-run setup not completed | Edit flow, select each connection reference action, and bind to active connections |
| JSON parsing error in flow | Runbook output format changed | Verify `Start-ModerationValidationRunbook.ps1` output matches expected JSON schema |
| Flow timeout | Runbook execution exceeds flow timeout | Increase flow timeout or reduce scan scope (filter by zone) |
| Email notification not sent | Office 365 connection reference not bound | Configure `fsi_cr_office365_moderationmonitor` with a mailbox that can send |

---

## Deployment Placeholders

The Power Automate flow template contains placeholder URLs that must be replaced before import. If adaptive card buttons (e.g., "Run Manual Check" or "View Documentation") are non-functional after deployment, see [FLOW_SETUP.md](FLOW_SETUP.md) for required placeholder replacements including `${ManualCheckUrl}` and the `your-org.github.io` documentation URL.

## Related Documentation

- [PREREQUISITES.md](PREREQUISITES.md) — Module and permission requirements
- [SCHEMA.md](SCHEMA.md) — Dataverse schema reference
- [EVIDENCE_EXPORT.md](EVIDENCE_EXPORT.md) — Evidence export guide
- [FLOW_SETUP.md](FLOW_SETUP.md) — Power Automate flow deployment and placeholder configuration

---

*Content Moderation Governance Monitor — Troubleshooting Guide v1.0.3*
