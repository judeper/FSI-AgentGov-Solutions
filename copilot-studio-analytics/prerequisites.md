# Prerequisites

This document lists all requirements for deploying the Copilot Studio Analytics solution.

## AOF Deployment (Required)

CSA depends on infrastructure deployed by the [Agent Observability Foundation](../agent-observability-foundation/). Confirm AOF is deployed before proceeding.

| AOF Component | Required For | Verification |
|---------------|-------------|--------------|
| Application Insights | CopilotSessionOutcome event destination | `az monitor app-insights component show --app {name}` |
| Log Analytics workspace | KQL queries and workbook data source | `az monitor log-analytics workspace show --workspace-name {name}` |
| Copilot Studio integration | Native telemetry events (BotMessage*, GenerativeAnswers) | Query `customEvents` for recent BotMessageSend events |

## Dataverse Access Requirements

| Resource | Required Permission | Purpose |
|----------|-------------------|---------|
| Dataverse environment | Application user with read access | Session sync pipeline |
| msdyn_botsession | Read | Session outcome records |
| bot | Read | Agent metadata (name, schema name) |
| botcomponent | Read | Agent type classification |
| msdyn_botcomponentsession (Tier 2) | Read | Per-topic session data |
| conversationtranscript (Tier 2) | Read | Detailed behavior metrics |
| fsi_csawatermark | Read/Write | Sync tracking table (created by schema script) |

### App Registration Setup

1. Create an app registration in Entra ID (or reuse an existing one)
2. Add the Dataverse API permission: `https://org.api.crm.dynamics.com/.default`
3. Create a client secret or configure certificate authentication
4. Create an application user in Power Platform admin center:
   - Navigate to **Environments** > your environment > **Settings** > **Users + permissions** > **Application users**
   - Click **+ New app user** and select your app registration
   - Assign a security role with read access to the tables listed above

### Required Configuration Values

| Config Key | Source | Example |
|-----------|--------|---------|
| `dataverse_url` | Power Platform admin center > Environment URL | `https://org12345.api.crm.dynamics.com` |
| `tenant_id` | Entra ID > App registration > Overview | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `client_id` | Entra ID > App registration > Overview | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `client_secret` | Entra ID > App registration > Certificates & secrets | (stored securely, not in config file) |
| `appinsights_connection_string` | AOF Application Insights > Overview > Connection String | `InstrumentationKey=...;IngestionEndpoint=...` |

## Software Requirements

| Software | Version | Purpose |
|----------|---------|---------|
| Python | 3.9+ | Sync scripts and validation |
| pip | Latest | Package management |
| PowerShell | 7.0+ | Workbook deployment (optional) |
| Azure CLI | 2.50+ | Workbook deployment and validation (optional) |

### Python Packages

Install via `pip install -r scripts/requirements.txt`:

| Package | Version | Purpose |
|---------|---------|---------|
| msal | 1.24.0+ | Dataverse authentication (MSAL confidential client) |
| requests | 2.31.0+ | Dataverse Web API calls |
| applicationinsights | 0.11.10+ | Application Insights telemetry export |
| pyyaml | 6.0+ | Configuration file parsing |
| azure-identity | 1.14.0+ | Azure credential management |
| azure-monitor-query | 1.3.0+ | Log Analytics query for validation |
| azure-mgmt-applicationinsights | 4.0.0+ | App Insights management for validation |

## Transcript Retention Extension (Recommended)

> **This step is critical for Tier 2 data availability.**

Dataverse includes a default system job that bulk-deletes `conversationtranscript` records after 30 days. If not extended, Tier 2 queries (topic-level sessions, action execution, precise knowledge source counts) lose historical data after one month.

### Impact of Default Retention

| Tier | Affected | Impact if Not Extended |
|------|----------|----------------------|
| Tier 1 | No | msdyn_botsession records are not subject to bulk delete |
| Tier 2 | Yes | conversationtranscript records deleted after 30 days |

### Extension Steps

1. Navigate to **Power Platform admin center** > **Environments** > your environment
2. Click **Settings** > **Data management** > **Bulk deletion**
3. Locate the system job named **Delete conversationtranscript records older than 30 days** (or similar)
4. Select the job and click **Edit** (or create a new recurring job):
   - Change the condition from `createdon older than 30 days` to your desired retention period
   - Recommended: **90 days** for standard analytics, **365 days** for full historical analysis
5. Save the modified job

### Alternative: Disable Bulk Delete

If your organization requires indefinite transcript retention:

1. Locate the bulk delete system job as above
2. **Suspend** the job rather than deleting it (allows re-enablement if needed)
3. Monitor Dataverse storage consumption -- transcripts can grow significantly

> **Storage Note:** Extending transcript retention increases Dataverse storage consumption. Monitor storage via Power Platform admin center > **Resources** > **Capacity** and plan for additional database capacity if needed.

## Copilot Studio Agent Configuration

Each agent must be connected to the same Application Insights instance used by AOF.

### Per-Agent Setup

1. Open **Copilot Studio** > select your agent
2. Navigate to **Settings** > **Diagnostics**
3. Enable **Application Insights**
4. Enter the Application Insights **connection string** (same string used by AOF)
5. Optionally enable **CSAT survey** (Settings > Customer satisfaction) for CSAT data in analytics

### CSAT Survey Enablement

CSAT data in CSA analytics requires the survey to be enabled per agent:

| Setting | Location | Impact |
|---------|----------|--------|
| Customer satisfaction survey | Copilot Studio > Agent > Settings > Customer satisfaction | Enables msdyn_csatscore in session records |
| Survey timing | Same location | Configure when survey appears (end of session recommended) |

> **Note:** CSAT scores appear as null in CopilotSessionOutcome events for agents without the survey enabled. Queries handle null CSAT gracefully.

## Minimum Data Requirements

For meaningful analytics, confirm at least:

- [ ] **One Copilot Studio agent** connected to Application Insights with production sessions
- [ ] **7+ days of session data** in msdyn_botsession for trend analysis
- [ ] **GenerativeAnswers events** visible in App Insights customEvents (for Tier 1 knowledge source proxy)

### Validation Commands

```bash
# Verify AOF Application Insights has data
python scripts/validate_telemetry.py --check-aof

# Verify Dataverse connectivity
python scripts/validate_telemetry.py --check-dataverse

# Full pre-deployment validation
python scripts/validate_telemetry.py --pre-deploy
```

## Pre-Deployment Checklist

- [ ] **AOF deployed** -- Application Insights and Log Analytics workspace operational
- [ ] **App registration created** -- With Dataverse API permissions and application user
- [ ] **Configuration values collected** -- Dataverse URL, tenant ID, client ID, App Insights connection string
- [ ] **Client secret stored securely** -- Environment variable or key vault reference
- [ ] **Python environment ready** -- Python 3.9+ with dependencies installed
- [ ] **Transcript retention reviewed** -- Default 30-day bulk delete extended if Tier 2 analytics needed
- [ ] **CSAT survey enabled** -- On agents where customer satisfaction tracking is desired
- [ ] **Test agent available** -- At least one agent with production sessions for validation

---

*Prerequisites version: 1.0.0*
*Last updated: February 2026*
