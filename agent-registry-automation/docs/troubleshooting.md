# Troubleshooting Guide

Common issues and resolutions for the Agent Registry Automation solution.

---

## Discovery Issues (Flow 1)

### Environment enumeration returns 401 Unauthorized

**Symptoms:** Flow 1 fails when calling the BAP admin environments API with a 401 error.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Token expired | Re-authorize the `fsi_cr_http_agentregistry` connection reference used for the BAP call |
| Wrong resource URI | Verify the connection's resource URI is `https://service.powerapps.com/` (the BAP admin audience), not the Graph or Dataverse audience |
| Insufficient role | The identity must hold the **Power Platform Admin** role to use `scopes/admin/environments` |

**Verify connection reference:**

1. Navigate to **Power Apps** > **Solutions** > **Agent Registry Automation**
2. Select **Connection References** > `fsi_cr_http_agentregistry`
3. Verify the **Resource URI** for the BAP enumeration connection is `https://service.powerapps.com/`
4. Click **Edit** and re-select or re-create the connection

### `bot`-table query returns 401/403 Forbidden

**Symptoms:** Flow 1 receives a 401/403 error when listing rows from the `bot` table in specific environments.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| No Dataverse access | The identity needs a Dataverse security role with **read** on the `bot` table in that environment. Add an application user or assign a read role per environment. |
| Environment-level restriction | Some environments restrict cross-environment connections — verify tenant isolation / DLP settings |

### `bot`-table query returns 404 Not Found

**Symptoms:** Flow 1 receives a 404 when querying an environment's Dataverse `bot` table.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Environment has no Dataverse | Environments without a linked Dataverse instance have no `instanceUrl`; the flow should skip these gracefully |
| Wrong instance URL | Verify `properties.linkedEnvironmentMetadata.instanceUrl` from the environment list is used as the Dataverse base URL |
| Table not present | Confirm the environment provisions Copilot Studio (the `bot` table exists where Copilot Studio is enabled) |

### No Agents Discovered

**Symptoms:** Flow 1 completes without errors but discovers zero agents.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| No agents deployed | Expected behavior if no AI agents exist in scanned environments |
| Sandbox environments excluded | Set `fsi_ARA_IncludeSandboxEnvironments` to `true` if needed |
| Developer environments filtered | Developer SKU environments are excluded by your filter — this is intentional |
| `bot`-table read access missing | Confirm the identity can read the `bot` table in each environment |

---

## Alternate Key Issues

### Upsert Fails with 404 Error

**Symptoms:** The Dataverse upsert action in Flow 1 fails with "Entity with alternate key not found."

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Alternate key still **Pending** | Wait up to 30 minutes after schema deployment for the key to become **Active** |
| Key creation failed | Check key status in **Power Apps** > **Tables** > **Agent Inventory** > **Keys** |
| Column values contain special characters | Ensure `fsi_agentid` and `fsi_environmentid` are clean GUIDs without braces |

**Check alternate key status:**

1. Navigate to **Power Apps** > **Tables** > **Agent Inventory**
2. Select **Keys** from the left navigation
3. Verify `fsi_AgentEnvUniqueKey` (logical: `fsi_agentenvuniquekey`) shows status **Active**
4. If status is **Failed**, delete and recreate the key

> **Note:** If the alternate key repeatedly fails to activate, it may indicate duplicate data in the key columns. Query the table for duplicate `fsi_agentid` + `fsi_environmentid` combinations and resolve them before recreating the key.

### Alternate Key Status Shows "Pending" Indefinitely

**Symptoms:** The alternate key never transitions from **Pending** to **Active**.

**Resolution:**

1. Delete the alternate key
2. Query `fsi_agentinventories` for any records with null `fsi_agentid` or `fsi_environmentid`
3. Remove or fix records with null key columns
4. Recreate the alternate key using `scripts/create_dataverse_schema.py`

---

## Long-Term Retention (LTR) Issues

### LTR Not Available on Table

**Symptoms:** The Long-Term Retention option is not visible in table properties.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Environment is not Managed | Enable Managed Environment in Power Platform Admin Center |
| Table not eligible for LTR | Verify the table is a custom table (not a system table) |
| Feature not enabled in region | LTR availability varies by region — check Microsoft documentation |

### LTR Policy Not Retaining Records

**Symptoms:** Records older than the retention period are not being moved to long-term storage.

**Resolution:**

1. Verify LTR is enabled on the `fsi_agentcomplianceevent` table
2. Check the retention period configuration (recommended: 2,555 days for 7-year retention)
3. Verify the environment has sufficient Dataverse storage capacity
4. LTR processing runs on a schedule — allow 24–48 hours for initial processing

---

## DLP Connector Blocking

### Office 365 Users Connector Blocked

**Symptoms:** Flow 2 fails when attempting to look up the approver's time zone for SLA calculation.

**Resolution:**

1. This connector is optional — the flow falls back to `fsi_ARA_DefaultTimeZone`
2. If the fallback is not configured, set the environment variable:
   - Navigate to **Power Apps** > **Solutions** > **Agent Registry Automation** > **Environment Variables**
   - Set `fsi_ARA_DefaultTimeZone` to your organization's default (e.g., `Eastern Standard Time`)
3. The flow will use calendar days instead of business days for SLA calculations

### HTTP with Microsoft Entra ID Connector Blocked

**Symptoms:** Flows 1, 3, and 4 fail because the HTTP with Microsoft Entra ID connector is blocked by DLP policy.

**Resolution:**

This connector is **required** for the solution to function. Work with your DLP administrator to:

1. Classify `HTTP with Microsoft Entra ID` in the **Business** connector group
2. If organization-wide reclassification is not possible, create an environment-specific DLP policy that allows this connector in the governance environment

> **Note:** The HTTP with Microsoft Entra ID connector is used for BAP environment enumeration (Flow 1), Microsoft Entra Agent ID (Flow 3), and Graph API (Flow 4) calls. Without it, these flows cannot operate. Per-environment agent discovery (Flow 1) uses the Dataverse connector against each environment's `bot` table.

---

## Managed Identity Authentication Failures

### Deploy-AgentRegistry-Baseline.ps1 Fails with Auth Error

**Symptoms:** The baseline export script fails to authenticate using Managed Identity.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Not running in Azure context | Managed Identity auth only works in Azure VMs, Azure Functions, or Azure Automation |
| Managed Identity not assigned | Assign a system-assigned or user-assigned Managed Identity to the compute resource |
| Missing role assignments | Grant the Managed Identity appropriate Dataverse and Power Platform roles |
| Token audience mismatch | Verify the token is requested for the correct resource URI |

**Fallback to service principal auth:**

```powershell
.\scripts\Deploy-AgentRegistry-Baseline.ps1 `
    -DataverseUrl "https://your-org.crm.dynamics.com"
```

> **Note:** This script uses Managed Identity authentication exclusively. It must run in an Azure Automation context with a system-assigned Managed Identity.

---

## Rate Limiting (429 Errors)

### Discovery Rate Limiting

**Symptoms:** Flow 1 receives 429 (Too Many Requests) responses during environment scanning.

**Resolution:**

1. The flow should be configured with concurrency set to **1** (sequential) for the environment loop
2. If 429 errors persist, add a **Delay** action (e.g., 2 seconds) between per-environment `bot`-table queries
3. For large tenants with 50+ environments, consider splitting the scan across multiple flow runs

### Graph API Rate Limiting

**Symptoms:** Flow 4 receives 429 responses when checking user status.

**Resolution:**

1. Reduce concurrency on the agent loop from 5 to 1 or 2
2. Add a **Delay** action between Graph API calls
3. Consider batching Graph API requests using `$batch` endpoint (requires flow modification)

### Dataverse API Throttling

**Symptoms:** Any flow receives 429 responses on Dataverse operations.

**Resolution:**

1. Review Dataverse API limits for your environment tier
2. Reduce concurrency on loops that create or update Dataverse records
3. Implement retry logic with exponential backoff (Power Automate has built-in retry policies)
4. Monitor Dataverse API usage in Power Platform Admin Center

---

## Environment Variable Issues

### Environment Variable Not Found

**Symptoms:** Flow fails with "Environment variable not found" error.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Variable not deployed | Run `scripts/create_environment_variables.py` |
| Variable name mismatch | Verify the exact variable name in the flow matches the deployed variable |
| Solution not imported | Ensure the solution containing the variables is imported to the target environment |
| Current value not set | Navigate to the environment variable and set a **Current value** |

**Verify environment variables:**

1. Navigate to **Power Apps** > **Solutions** > **Agent Registry Automation**
2. Select **Environment Variables**
3. Verify all 10 variables exist and have current values set

### Environment Variable Has No Current Value

**Symptoms:** Flow reads an empty or null value from an environment variable.

**Resolution:**

1. Environment variables have a **Default value** and a **Current value**
2. The **Current value** overrides the default in the target environment
3. Set the current value for each variable in the target environment
4. For `fsi_ARA_IsEntraRegistrySyncEnabled`, the default is `false` — this is intentional

---

## Connection Reference Issues

### Connection Reference Not Bound

**Symptoms:** Flow fails with "Connection reference not bound" or "No connection found."

**Resolution:**

1. Navigate to **Power Apps** > **Solutions** > **Agent Registry Automation**
2. Select **Connection References**
3. For each unbound reference, click **Edit** and select or create a connection
4. Ensure the connection is authenticated with appropriate credentials

### Connection Reference Authentication Expired

**Symptoms:** Flow was working but suddenly fails with authentication errors.

**Resolution:**

1. Navigate to **Power Automate** > **Connections**
2. Find the connection linked to the failing connection reference
3. Click **Fix connection** or **Repair** to re-authenticate
4. Test the flow after re-authentication

---

## Teams Notification Issues

### Adaptive Cards Not Appearing

**Symptoms:** Flow completes without errors but no Teams notification is posted.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Wrong channel ID | Verify `fsi_ARA_TeamsChannelId` matches the target channel |
| Teams connection expired | Re-authorize the `fsi_cr_teams_agentregistry` connection |
| Bot blocked in channel | Ensure the Power Automate bot is not blocked in the Teams channel |
| Channel archived or deleted | Use an active channel |

### Approval Not Received in Teams

**Symptoms:** Registration request created but approver does not see the approval in Teams.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Approvals app not installed | Install the Power Automate Approvals app in Teams |
| Wrong approver email | Verify `fsi_ARA_GovernanceTeamEmail` is a valid individual or group mailbox |
| Shared mailbox limitations | Approvals to shared mailboxes require additional configuration |
| Connection expired | Re-authorize the Approvals connection in Power Automate |

---

## Diagnostic Queries

### Check Agent Inventory Status

```powershell
# Query all agents grouped by registration status
$token = Get-AccessToken -Scope "https://your-org.crm.dynamics.com/.default"
$headers = @{ "Authorization" = "Bearer $token"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }

$uri = "https://your-org.crm.dynamics.com/api/data/v9.2/fsi_agentinventories?" +
       "`$select=fsi_name,fsi_registrationstatus,fsi_zone,fsi_isorphaned,fsi_publishedstatus"
$response = Invoke-RestMethod -Uri $uri -Headers $headers
$response.value | Group-Object fsi_registrationstatus | Select-Object Name, Count
```

### Check Compliance Event Volume

```powershell
# Count compliance events by type in the last 7 days
$filter = "fsi_eventtimestamp ge " + (Get-Date).AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ")
$uri = "https://your-org.crm.dynamics.com/api/data/v9.2/fsi_agentcomplianceevents?" +
       "`$filter=$filter&`$select=fsi_eventtype"
$response = Invoke-RestMethod -Uri $uri -Headers $headers
$response.value | Group-Object fsi_eventtype | Select-Object Name, Count
```

### Check Pending Registration Requests

```powershell
# List all pending or escalated registration requests
# fsi_approvalstatus values: 100000000=Pending, 100000003=Escalated
$uri = "https://your-org.crm.dynamics.com/api/data/v9.2/fsi_registrationrequests?" +
       "`$filter=fsi_approvalstatus eq 100000000 or fsi_approvalstatus eq 100000003" +
       "&`$select=fsi_agentid,fsi_agentname,fsi_approvalstatus,fsi_sladeadline,fsi_escalationtarget"
$response = Invoke-RestMethod -Uri $uri -Headers $headers
$response.value | Format-Table fsi_agentname, fsi_approvalstatus, fsi_sladeadline, fsi_escalationtarget
```

---

*Agent Registry Automation v2.1.1 — FSI Agent Governance Framework*
