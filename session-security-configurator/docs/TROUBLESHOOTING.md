# Session Security Configurator Troubleshooting

This guide covers common issues encountered during SSC deployment and operation, with resolution steps.

## Deployment Issues

### Authentication Context Deployment

| Error | Cause | Resolution |
|-------|-------|------------|
| "Context already exists" | Authentication context c1-c5 already defined | Use `-Force` to overwrite, or manually update in Entra portal |
| "Insufficient permissions" | Missing Security Administrator role | Assign Security Administrator or Entra Global Admin |
| Graph API timeout | Large tenant with many CA policies | Retry with `-Verbose`; consider off-hours deployment |
| "Invalid context ID format" | Context ID doesn't match c1-c5 pattern | Verify context IDs in Deploy-AuthContexts.ps1 |

### Conditional Access Policy Deployment

| Error | Cause | Resolution |
|-------|-------|------------|
| "Bake period not met" | Policy created less than 72 hours ago | Wait for report-only period to complete |
| "Conflicting policy detected" | Overlapping CA policy targeting same users | Review conflict audit output; merge or disable conflicting policy |
| "Authentication strength not found" | Named auth strength policy doesn't exist | Create authentication strength policy before deploying CA policy |
| "Target users/groups invalid" | Group GUID not found | Verify group exists and is accessible |
| "Session controls conflict" | Multiple policies with different session settings | Review all policies targeting same scope |

### Dataverse Schema Deployment

| Error | Cause | Resolution |
|-------|-------|------------|
| "Table already exists" | Schema previously deployed | Re-run deployment with `--force` flag |
| "Insufficient privileges" | Missing System Customizer role | Assign System Administrator or System Customizer role |
| Connection refused | Firewall blocking Dataverse API | Verify network access to *.crm.dynamics.com |
| "Option set not found" | Dependent option set missing | Deploy option sets before tables |
| "Publisher prefix mismatch" | Using different publisher | Verify publisher configuration in deploy.py |

## Validation Issues

### Test-SessionCompliance Failures

| Validation Type | Common Failure | Resolution |
|-----------------|----------------|------------|
| SessionControls | Sign-in frequency not enforced | Verify CA policy is in Enforce mode (not report-only) |
| SessionControls | Persistent browser enabled | Disable persistent browser sessions in CA policy |
| AuthStrength | Wrong authentication strength applied | Check auth strength assignment in target CA policy |
| AuthStrength | Auth strength policy not found | Create named authentication strength policy |
| PIMSettings | Activation window exceeds zone limit | Configure PIM role settings to match zone requirements |
| PIMSettings | Approval not required for Zone 3 | Enable approval requirement in PIM role settings |
| BreakGlass | Break-glass accounts not excluded | Add break-glass accounts to CA policy exclusion group |
| ConflictAudit | Multiple conflicting policies detected | Use pre-deployment conflict audit to identify overlaps |

### Break-Glass Validation Errors

Break-glass failures are **CRITICAL** and cause overall validation to fail.

| Scenario | Cause | Resolution |
|----------|-------|------------|
| "Break-glass not excluded" | Accounts not in exclusion group | Add break-glass accounts to CA policy exclusion group |
| "Group membership check failed" | Graph API error querying group | Verify exclusion group exists and is accessible |
| "Multiple break-glass accounts missing" | Partial exclusion configuration | Add ALL designated break-glass accounts to exclusion |
| "Break-glass group not found" | Group deleted or renamed | Recreate exclusion group with correct membership |

### PIM Settings Validation

| Issue | Cause | Resolution |
|-------|-------|------------|
| Activation window too long | PIM role allows extended activation | Reduce maximum activation duration in PIM settings |
| Justification not required | PIM role doesn't require justification | Enable "Require justification on activation" |
| Approval not configured | Zone 3 requires approval for activation | Configure approval workflow in PIM role settings |
| MFA not required on activation | PIM allows activation without MFA | Enable "Require MFA on activation" |

## Flow Issues

### Daily Validation Flow

| Issue | Cause | Resolution |
|-------|-------|------------|
| Flow not triggering | Recurrence misconfigured | Verify daily schedule in Power Automate |
| Teams alert not sent | Connection reference not bound | Bind Teams connection reference to valid connection |
| Dataverse write fails | ValidationHistory security role issue | Check Flow service account has Create privilege on table |
| Timeout on validation | Large number of CA policies | Increase flow timeout; consider zone-by-zone execution |
| Azure Automation job fails | Runbook not imported or missing modules | Verify runbook deployed with required modules |
| Connection authorization expired | OAuth token expired | Re-authorize connection references in Power Automate |

### Adaptive Card Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Card not displaying | Teams channel permissions | Verify Flow has permission to post to channel |
| Card actions not working | Incoming webhook restrictions | Use Flow Bot connection instead of webhook |
| Card truncated | Too many validation results | Limit results in card; link to full report |

## Evidence Export Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| No records returned | No validations in date range | Expand date range; verify validation flow has run |
| JSON truncated | ConvertTo-Json depth exceeded | Script uses `-Depth 10`; check for circular references |
| Hash verification fails | File modified after export | Re-export evidence; never edit exported evidence files |
| Access token expired | Long-running export | Re-authenticate before export |
| Output directory not created | Permission issue | Verify write permission to output path |
| Empty validations array | Query filter too restrictive | Relax Zone or date range filters |

## Error Code Reference

| Error Code | Message | Resolution |
|------------|---------|------------|
| SSC-001 | Authentication context conflict | Review context IDs; use `-Force` to overwrite existing |
| SSC-002 | Policy bake period violation | Wait 72 hours before enabling policy enforcement |
| SSC-003 | Break-glass exclusion missing | Add all break-glass accounts to exclusion group immediately |
| SSC-004 | PIM configuration mismatch | Update PIM role settings to match zone requirements |
| SSC-005 | Conflict audit warning | Review overlapping CA policies and consolidate |
| SSC-006 | Dataverse connection failed | Verify URL, authentication, and network access |
| SSC-007 | Evidence export failed | Check date range, table access, and authentication |

## Diagnostic Commands

### Check Module Versions

```powershell
Get-Module Microsoft.Graph* -ListAvailable | Select-Object Name, Version
Get-Module MSAL.PS -ListAvailable | Select-Object Name, Version
```

### Verify Graph Permissions

```powershell
Connect-MgGraph -Scopes "Policy.Read.All", "Directory.Read.All"
Get-MgContext | Select-Object Scopes
```

### Test Dataverse Connection

```python
python scripts/ssc_client.py --test-connection \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id your-tenant-id \
    --interactive
```

### Validate CA Policy Configuration

```powershell
.\scripts\Test-SessionCompliance.ps1 -Zone Zone3 -ConfigPath ".\tenant-config.json" -Verbose
```

## Common Misconfigurations

### Zone Threshold Mismatch

Symptom: Validation passes but doesn't match expected zone requirements.

Cause: Environment variables have incorrect default values.

Resolution: Verify environment variable values in Dataverse:
- `fsi_SSC_Zone1SignInFrequencyMinutes` = 480
- `fsi_SSC_Zone2SignInFrequencyMinutes` = 240
- `fsi_SSC_Zone3SignInFrequencyMinutes` = 60

### CA Policy Targeting Wrong Users

Symptom: Validation shows controls not applied.

Cause: CA policy user/group assignment doesn't include AI agent admin roles.

Resolution: Review CA policy "Users and groups" assignment in Entra portal.

## Getting Support

1. **Check logs:** Review PowerShell output with `-Verbose` flag
2. **Verify prerequisites:** Re-run prerequisite checks from [PREREQUISITES.md](PREREQUISITES.md)
3. **Review documentation:** Check [FLOW_SETUP.md](FLOW_SETUP.md) for flow-specific issues
4. **Search existing issues:** [FSI-AgentGov-Solutions Issues](https://github.com/judeper/FSI-AgentGov-Solutions/issues)
5. **Open new issue:** Include error code, environment details, and steps to reproduce
