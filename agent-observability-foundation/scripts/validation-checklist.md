# Deployment Validation Checklist

**Version:** 1.0.0
**Last Updated:** February 2026

## Overview

This checklist provides pre-deployment prerequisites and post-deployment verification procedures for the Agent Observability Foundation solution. Use this guide to validate successful deployment of telemetry infrastructure, workbooks, and alert rules.

The checklist covers the complete deployment chain from Azure infrastructure (Phase 1) through workbook and alert deployments (Phase 5), helping support successful implementation of observability capabilities that aid in meeting FSI compliance requirements.

---

## Section 1: Pre-Deployment Prerequisites

### Azure Infrastructure (Phase 1)

Verify that Phase 1 telemetry infrastructure has been deployed:

- [ ] **Azure subscription active with Contributor role**
  Verify: `az account show --query "{Name:name, ID:id, State:state}"`

- [ ] **Resource group exists**
  Verify: `az group show --name {rg-name} --query "{Name:name, Location:location, State:properties.provisioningState}"`

- [ ] **Application Insights deployed**
  Verify: `az monitor app-insights component show --app {ai-name} --resource-group {rg-name} --query "{Name:name, State:provisioningState, InstrumentationKey:instrumentationKey}"`

- [ ] **Log Analytics workspace deployed**
  Verify: `az monitor log-analytics workspace show --workspace-name {law-name} --resource-group {rg-name} --query "{Name:name, RetentionDays:retentionInDays, State:provisioningState}"`

- [ ] **Storage account deployed (if using diagnostic export)**
  Verify: `az storage account show --name {sa-name} --resource-group {rg-name} --query "{Name:name, Kind:kind, State:provisioningState}"`

- [ ] **Application Insights receiving telemetry data**
  Verify: Run `python scripts/verify_telemetry.py` (should show telemetry data or pass gracefully for new deployments)

### Software Requirements

- [ ] **PowerShell 7.0+ installed**
  Verify: `pwsh --version` (should show `7.0.0` or higher)

- [ ] **Azure CLI 2.50+ installed**
  Verify: `az version --query "\"azure-cli\""` (should show `2.50.0` or higher)

- [ ] **Azure CLI authenticated**
  Verify: `az account show` (should show your account details without error)

- [ ] **Correct subscription selected**
  Verify: `az account show --query "{Name:name, ID:id}"` (confirm this is the intended subscription)
  Set if needed: `az account set --subscription {subscription-id}`

### ARM Template Files (Workbook Deployment)

Verify all workbook templates and parameter files are present:

- [ ] **Operational Health workbook template**
  Path: `agent-observability-foundation/workbooks/operational-health/workbook-template.json`

- [ ] **Operational Health parameters (dev)**
  Path: `agent-observability-foundation/workbooks/operational-health/workbook-parameters.dev.json`

- [ ] **Operational Health parameters (prod)**
  Path: `agent-observability-foundation/workbooks/operational-health/workbook-parameters.prod.json`

- [ ] **Error Diagnostics workbook template**
  Path: `agent-observability-foundation/workbooks/error-diagnostics/workbook-template.json`

- [ ] **Error Diagnostics parameters (dev)**
  Path: `agent-observability-foundation/workbooks/error-diagnostics/workbook-parameters.dev.json`

- [ ] **Error Diagnostics parameters (prod)**
  Path: `agent-observability-foundation/workbooks/error-diagnostics/workbook-parameters.prod.json`

- [ ] **Usage Overview workbook template**
  Path: `agent-observability-foundation/workbooks/usage-overview/workbook-template.json`

- [ ] **Usage Overview parameters (dev)**
  Path: `agent-observability-foundation/workbooks/usage-overview/workbook-parameters.dev.json`

- [ ] **Usage Overview parameters (prod)**
  Path: `agent-observability-foundation/workbooks/usage-overview/workbook-parameters.prod.json`

### ARM Template Files (Alert Deployment)

Verify all alert templates and parameter files are present:

- [ ] **Logic App template (Teams notification)**
  Path: `agent-observability-foundation/alerts/action-groups/logic-app-teams-notification.json`

- [ ] **Zone 1 action group template**
  Path: `agent-observability-foundation/alerts/action-groups/action-group-zone1.json`

- [ ] **Zone 2 action group template**
  Path: `agent-observability-foundation/alerts/action-groups/action-group-zone2.json`

- [ ] **Zone 3 action group template**
  Path: `agent-observability-foundation/alerts/action-groups/action-group-zone3.json`

- [ ] **ALRT-01 (high failure rate) template**
  Path: `agent-observability-foundation/alerts/ALRT-01-high-failure-rate.json`

- [ ] **ALRT-02 (latency regression) template**
  Path: `agent-observability-foundation/alerts/ALRT-02-latency-regression.json`

- [ ] **ALRT-03 (abnormal usage) template**
  Path: `agent-observability-foundation/alerts/ALRT-03-abnormal-usage.json`

- [ ] **Shared parameters (dev)**
  Path: `agent-observability-foundation/alerts/shared-parameters.dev.json`

- [ ] **Shared parameters (prod)**
  Path: `agent-observability-foundation/alerts/shared-parameters.prod.json`

### Configuration

- [ ] **Application Insights resource ID noted**
  Full resource ID format: `/subscriptions/{sub-id}/resourceGroups/{rg-name}/providers/Microsoft.Insights/components/{ai-name}`
  Obtain via: `az monitor app-insights component show --app {ai-name} --resource-group {rg-name} --query id -o tsv`

- [ ] **Environment selected (dev or prod)**
  Determine which parameter files to use based on target environment

- [ ] **Email addresses configured in shared parameter files**
  Edit `alerts/shared-parameters.{env}.json` with appropriate email addresses for alert notifications

- [ ] **Teams channel webhook URL available**
  (Will be captured from Logic App deployment output in Phase 1 of alert deployment)

---

## Section 2: Workbook Deployment Verification

### Deployment Execution

Run the workbook deployment script:

```powershell
# Preview deployment (dry run)
pwsh scripts/deploy-workbooks.ps1 `
  -ResourceGroup "{rg-name}" `
  -ApplicationInsightsId "/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{ai-name}" `
  -Environment dev `
  -DryRun

# Execute deployment
pwsh scripts/deploy-workbooks.ps1 `
  -ResourceGroup "{rg-name}" `
  -ApplicationInsightsId "/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{ai-name}" `
  -Environment dev
```

### Post-Deployment Verification

- [ ] **Script completed without errors**
  Verify no PowerShell errors or Azure CLI deployment failures in output

- [ ] **All 3 workbooks listed in script output summary**
  Script should show deployment status for Operational Health, Error Diagnostics, and Usage Overview

- [ ] **Workbooks visible via Azure CLI**
  Verify: `az monitor app-insights workbook list --resource-group {rg-name} --category workbook --output table`
  Expected: 3 workbooks with "Succeeded" provisioning state

- [ ] **Workbooks visible in Azure Portal**
  Navigate to: Azure Portal → Monitor → Workbooks → verify all 3 workbooks appear in list

- [ ] **Operational Health workbook opens**
  Click on "Operational Health" workbook → verify workbook loads without errors

- [ ] **Time range parameter functional**
  Change TimeRange parameter (24h, 7d) → verify workbook queries refresh

- [ ] **Zone parameter functional**
  Change Zone parameter → verify workbook filters data appropriately (or shows empty state if no zone metadata)

- [ ] **Error Diagnostics workbook opens**
  Click on "Error Diagnostics" workbook → verify workbook loads without errors

- [ ] **Usage Overview workbook opens**
  Click on "Usage Overview" workbook → verify workbook loads without errors

### Idempotency Test

- [ ] **Re-run deployment produces no errors**
  Execute deployment command again → verify script completes successfully

- [ ] **No duplicate workbooks created**
  Verify: `az monitor app-insights workbook list --resource-group {rg-name} --category workbook --output table`
  Expected: Still exactly 3 workbooks (not 6)

---

## Section 3: Alert Deployment Verification

### Phase 1 — Logic App Deployment

Deploy the Teams notification Logic App:

```powershell
# Preview deployment (dry run)
pwsh scripts/deploy-alerts.ps1 `
  -ResourceGroup "{rg-name}" `
  -ApplicationInsightsId "/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{ai-name}" `
  -Environment dev `
  -DryRun

# Execute deployment (with confirmation prompt)
pwsh scripts/deploy-alerts.ps1 `
  -ResourceGroup "{rg-name}" `
  -ApplicationInsightsId "/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{ai-name}" `
  -Environment dev
```

**Phase 1 Verification:**

- [ ] **Logic App deployed successfully**
  Verify: `az logic workflow show --name fsi-agent-alert-teams-{env} --resource-group {rg-name} --query "{Name:name, State:state}"`

- [ ] **Logic App callback URL captured**
  Verify script output displays callback URL (begins with `https://prod-XX.{region}.logic.azure.com:443/workflows/...`)

- [ ] **Callback URL format is correct**
  URL should include `triggers/manual/paths/invoke?` and end with SAS token

### Phase 2 — Action Groups Deployment

Script automatically deploys action groups after Logic App (dependency order enforced):

**Phase 2 Verification:**

- [ ] **All 3 action groups deployed**
  Verify: `az monitor action-group list --resource-group {rg-name} --output table`

- [ ] **Zone 1 action group present**
  Expected name: `action-group-zone1-{env}`

- [ ] **Zone 2 action group present**
  Expected name: `action-group-zone2-{env}`

- [ ] **Zone 3 action group present**
  Expected name: `action-group-zone3-{env}`

- [ ] **Action groups reference Logic App callback URL**
  Verify: `az monitor action-group show --name action-group-zone1-{env} --resource-group {rg-name} --query "logicAppReceivers[0].callbackUrl"`
  Should match callback URL from Phase 1

### Phase 3 — Alert Rules Deployment

Script automatically deploys alert rules after action groups (dependency order enforced):

**Phase 3 Verification:**

- [ ] **All alert rules deployed**
  Verify: `az monitor scheduled-query list --resource-group {rg-name} --output table`

- [ ] **ALRT-01 rules present (3 zones)**
  Expected names: `ALRT-01-high-failure-rate-zone1`, `ALRT-01-high-failure-rate-zone2`, `ALRT-01-high-failure-rate-zone3`

- [ ] **ALRT-02 rules present (3 zones)**
  Expected names: `ALRT-02-latency-regression-zone1`, `ALRT-02-latency-regression-zone2`, `ALRT-02-latency-regression-zone3`

- [ ] **ALRT-03 rules present (3 zones)**
  Expected names: `ALRT-03-abnormal-usage-zone1`, `ALRT-03-abnormal-usage-zone2`, `ALRT-03-abnormal-usage-zone3`

- [ ] **Alert rules reference action groups**
  Verify: `az monitor scheduled-query show --name ALRT-01-high-failure-rate-zone1 --resource-group {rg-name} --query "actions.actionGroups[0]"`
  Should show action group resource ID

- [ ] **Alert rules are enabled**
  Verify: `az monitor scheduled-query show --name ALRT-01-high-failure-rate-zone1 --resource-group {rg-name} --query "enabled"`
  Should return `true`

### End-to-End Validation

- [ ] **Logic App authorization completed (manual step)**
  Navigate to: Azure Portal → Logic App → Authorize Teams connector → Complete OAuth flow
  (Required before Teams notifications will work)

- [ ] **Trigger test alert (optional)**
  Navigate to: Azure Portal → Monitor → Alerts → Select alert rule → "New alert rule" → "Select a test query" → "Create test alert"
  Warning: This sends actual notifications to configured channels

- [ ] **Teams notification received (if test alert triggered)**
  Check configured Teams channel for alert notification with formatted schema

- [ ] **Email notification received (if test alert triggered)**
  Check configured email address for alert notification

### Idempotency Test

- [ ] **Re-run deployment produces no errors**
  Execute `deploy-alerts.ps1` again → verify script completes successfully with "already exists" messages

- [ ] **No duplicate alert rules created**
  Verify: `az monitor scheduled-query list --resource-group {rg-name} --output table`
  Expected: Still exactly 9 alert rules (3 alerts × 3 zones)

---

## Section 4: Post-Deployment Notes

### Dynamic Threshold Baseline Period

Alert rules use dynamic thresholds that require historical data to establish normal behavior patterns:

- **Minimum baseline:** 3 days (30+ data points for hourly aggregation)
- **Standard baseline:** 10-14 days (captures weekly operational patterns)
- **Full baseline:** 3 weeks (required for weekly cycles like weekday vs. weekend variance)

**What to expect:**
- Alert rules show "Learning" state during baseline period (visible in portal but do not fire)
- After 10-14 days, thresholds activate based on learned baseline
- New telemetry data continuously refines thresholds

**Recommendation:**
Allow 14 days of telemetry collection before relying on dynamic threshold alerts for production monitoring. For immediate alerting needs, consider temporary static threshold alert rules during baseline period.

### WORM Policy Configuration

SEC 17a-4(f) compliance requires immutable storage with Write Once Read Many (WORM) policy:

- **Not automated:** WORM policy configuration is intentionally excluded from deployment scripts to prevent accidental immutable lockdown
- **Manual setup required:** Follow steps in `docs/worm-configuration.md` for manual WORM policy application
- **When to configure:** After verifying storage account diagnostic export is working correctly (wait 7-14 days to ensure data export patterns are correct)

**Warning:**
WORM policy is irreversible. Once applied, data cannot be deleted or modified until retention period expires. Review carefully before applying.

### Cost Monitoring

The solution includes cost alerts at 50%, 75%, and 90% budget thresholds:

- Review Azure Cost Management dashboard weekly during first month
- Adjust sampling rates if costs exceed budget (see `docs/cost-tuning-guide.md`)
- Monitor Application Insights ingestion volume via portal metrics

**Typical costs for FSI environments:**
- Small deployment (<10 agents): $50-150/month
- Medium deployment (10-50 agents): $150-500/month
- Large deployment (50+ agents): $500-2000/month

### Runbook URLs

Alert rules include custom property runbook URLs pointing to FSI-AgentGov framework documentation:

- ALRT-01: https://judeper.github.io/FSI-AgentGov/playbooks/control-implementations/3.4/troubleshooting/
- ALRT-02: https://judeper.github.io/FSI-AgentGov/playbooks/control-implementations/2.9/troubleshooting/
- ALRT-03: https://judeper.github.io/FSI-AgentGov/playbooks/control-implementations/3.2/troubleshooting/

**Customization:**
To point runbook URLs to internal documentation sites, edit the `customProperties.RunbookUrl` value in alert rule ARM templates before deployment.

---

## Section 5: Troubleshooting Quick Reference

| Error | Cause | Resolution |
|-------|-------|------------|
| **"Error: Not authenticated"** | Azure CLI not logged in | Run `az login` and complete authentication |
| **"Resource group not found"** | Resource group doesn't exist or wrong subscription | Run Phase 1 provisioning (`python scripts/provision.py`) or create resource group manually; verify subscription with `az account show` |
| **"Application Insights not found"** | Phase 1 not completed or wrong resource name | Complete Phase 1 deployment first; verify Application Insights name and resource group are correct |
| **"Template validation failed"** | ARM template syntax error or invalid parameter | Run `az deployment group validate --resource-group {rg-name} --template-file {template-path} --parameters @{params-path}` for detailed error message |
| **"Duplicate workbook"** | Non-fixed GUID in parameter files | Verify parameter files use fixed workbookId GUIDs (not `newGuid()` expressions); check parameter files match template expectations |
| **"Action group not found" (during alert deployment)** | Phase 2 skipped or failed | Re-run `deploy-alerts.ps1` (script enforces phase order); check action group deployment output for errors |
| **"Cannot deploy Logic App"** | Logic App name already taken (global namespace) | Change `logicAppName` parameter to unique value; Logic App names must be unique within region |
| **"Callback URL not found"** | Logic App deployment output missing | Verify Logic App deployed successfully; manually retrieve callback URL via Azure Portal → Logic App → "When a HTTP request is received" trigger → Copy callback URL |
| **Workbook shows "No data available"** | Application Insights has no telemetry or wrong resource ID | Configure Copilot Studio agents to send telemetry to Application Insights; verify `applicationInsightsId` parameter matches deployed Application Insights resource |
| **Alert never fires despite visible anomalies** | Dynamic threshold in "Learning" state | Wait 10-14 days for baseline establishment; verify alert rule is enabled; check alert evaluation frequency and aggregation period |
| **Teams notification shows raw JSON** | Direct Teams webhook (not Logic App intermediary) | Verify action group uses `logicAppReceiver` (not `webhookReceiver`); ensure Logic App callback URL is correct in action group |
| **Email notifications not received** | Wrong email address or spam filter | Verify `emailReceivers` in action group ARM templates; check spam/junk folders; verify email domain allows Azure Monitor emails |
| **PowerShell script fails with "Command not found"** | Azure CLI not installed or not in PATH | Install Azure CLI 2.50+; verify with `az version`; restart PowerShell session after installation |
| **Script fails with "Parameter file not found"** | Wrong working directory or missing parameter files | Ensure you're running script from solution root directory; verify all parameter files exist; check file paths in error message |

### Additional Resources

For more detailed troubleshooting guidance, see:

- **Prerequisites:** [prerequisites.md](../prerequisites.md) — Detailed requirements checklist
- **Architecture:** [architecture.md](../architecture.md) — Data flow and component relationships
- **Workbooks:** [workbooks/README.md](../workbooks/README.md) — Workbook-specific troubleshooting
- **Alerts:** [alerts/README.md](../alerts/README.md) — Alert-specific troubleshooting
- **Cost Tuning:** [docs/cost-tuning-guide.md](../docs/cost-tuning-guide.md) — Sampling configuration
- **Alert Tuning:** [docs/alert-tuning-guide.md](../docs/alert-tuning-guide.md) — Dynamic threshold sensitivity

---

## Summary

This checklist helps support successful deployment by:

1. **Pre-deployment validation** — Ensures all prerequisites are met before starting
2. **Workbook verification** — Confirms all 3 workbooks deploy correctly and are functional
3. **Alert verification** — Confirms Logic App → Action Groups → Alert Rules dependency chain
4. **Post-deployment guidance** — Sets expectations for baseline periods and WORM policy timing
5. **Troubleshooting reference** — Provides quick resolutions for common deployment issues

**Next Steps After Successful Deployment:**

1. Configure Copilot Studio agents to send telemetry to Application Insights
2. Wait 10-14 days for dynamic threshold baseline establishment
3. Review workbooks daily during first week to verify data collection
4. Configure WORM policy after verifying diagnostic export (see `docs/worm-configuration.md`)
5. Customize runbook URLs if using internal documentation site
6. Set up RBAC assignments per role catalog (see [prerequisites.md](../prerequisites.md) Section: Role Assignment Reference)

---

*Validation Checklist Version: 1.0.0*
*Part of FSI Agent Observability Foundation*
*Last Updated: February 2026*
