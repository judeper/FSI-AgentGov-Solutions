# Troubleshooting Guide

Common issues and resolutions for the Agent Access Governance Monitor.

## Deployment Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Tables not created | `deploy.py` did not complete | Re-run `python scripts/deploy.py` (full deployment is the default); check Dataverse System Administrator role |
| Environment variables missing | Selective deployment skipped variables | Run `python scripts/deploy.py --vars-only` to deploy variables only |
| Connection reference errors | Connector not available in environment | Verify Power Automate Premium license; check connector availability in target environment |
| `deploy.py` authentication failure | Expired or invalid token | Re-authenticate with `az login`; verify tenant and environment URL |
| Schema version mismatch | Partial upgrade from earlier version | Re-run `python scripts/deploy.py` (full deployment is the default) to reconcile schema |

## Authentication Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| MSAL.PS module not found | Module not installed | Run `Install-Module MSAL.PS -Scope CurrentUser -Force` |
| Interactive auth popup not appearing | Browser block or policy restriction | Try a different browser; check Conditional Access policies |
| Certificate auth fails with 401 | Certificate not uploaded or expired | Verify certificate in Microsoft Entra ID app registration; check expiration date |
| Insufficient privileges | Missing Dataverse role | Assign Dataverse User role (minimum) or System Administrator for schema deployment |
| Token expired during long export | Access token TTL exceeded | Re-run the export; token lifetime is typically 60 minutes |

## Validation Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| No environments returned | PowerApps Admin module not connected | Run `Add-PowerAppsAccount` before validation; verify Power Platform Admin role |
| Zone classification errors | Baseline record missing or zone not set | Verify `fsi_accessbaselines` has an active record for the environment, or check naming convention fallback matches environment names |
| False positive violations | Zone assignment incorrect | Check zone classification in `fsi_accessbaselines` Dataverse table; re-capture baseline with correct zone via `Invoke-AccessBaselineCapture.ps1` |
| Grace period not applied | `fsi_AAM_GracePeriodHours` set to 0 | Set environment variable to desired hours (default: 48) in Dataverse |
| Sandbox environments included | `fsi_AAM_IncludeSandbox` is true | Set to false in Dataverse environment variables, or use `-ExcludeSandbox` flag |

## Drift Detection Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Baseline not found | No baseline captured yet | Run `Invoke-AccessBaselineCapture.ps1` to create initial baselines |
| "No previous validation" warning | First run in environment | Expected on first run; baseline is established after first successful validation |
| Validation history not persisting | Missing Dataverse write permission | Verify Create permission on `fsi_accessvalidationhistory` entity |
| Drift detected but setting is correct | Stale baseline record | Re-capture baseline with `Invoke-AccessBaselineCapture.ps1` to update |

## Evidence Export Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Empty export (0 records) | No validation data in date range | Adjust `-FromDate` and `-ToDate`; confirm validations have run |
| Truncated JSON objects | PowerShell version < 7.0 | Upgrade to PowerShell 7.0+; script uses `-Depth 10` for serialization |
| Hash mismatch on verification | File modified after export | Re-export evidence; avoid opening JSON in editors that modify whitespace |
| Output directory permission denied | Restricted file system path | Use a writable directory; run as administrator if needed |
| Large export file (>100 MB) | Extended date range with many violations | Narrow `-FromDate`/`-ToDate` range, or filter by `-Zone` |

## Power Automate Flow Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Flow not triggering | Disabled or suspended flow | Check flow status in Power Automate portal; re-enable if suspended |
| Adaptive card not sent | Teams connection ref expired | Re-authorize `fsi_cr_teams_accessmonitor` connection reference in Power Automate |
| Dataverse write failure (403) | Managed identity lacks Create permission | Assign Security role with Organization-level Create on `fsi_accessvalidationhistory` |
| Azure Automation job timeout | Runbook exceeds default timeout | Increase job timeout in Automation Account; check for environment query delays |
| Email alerts not received | Office 365 connection expired or DL invalid | Re-authorize `fsi_cr_office365_accessmonitor`; verify distribution list address |
| Connection auth expired | Connections need periodic re-authorization | Re-authorize all connection references; consider service principal connections |

## Related Documentation

- [PREREQUISITES.md](PREREQUISITES.md) — Module and permission requirements
- [SCHEMA.md](SCHEMA.md) — Dataverse table definitions and environment variables
- [EVIDENCE_EXPORT.md](EVIDENCE_EXPORT.md) — Evidence export operations guide
- [FLOW_SETUP.md](FLOW_SETUP.md) — Power Automate flow deployment and configuration
