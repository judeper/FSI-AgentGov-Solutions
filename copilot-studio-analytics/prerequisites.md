# Prerequisites

This document lists all requirements for deploying the Copilot Studio Analytics solution.

## AOF Deployment (Required)

CSA depends on infrastructure deployed by the [Agent Observability Foundation](../agent-observability-foundation/). Confirm AOF is deployed before proceeding.

| AOF Component | Required For | Verification |
|---------------|-------------|--------------|
| Application Insights | CopilotSessionOutcome event destination | `az monitor app-insights component show --app {name}` |
| Log Analytics workspace | KQL queries and workbook data source | `az monitor log-analytics workspace show --workspace-name {name}` |
| Copilot Studio integration | Native telemetry events (BotMessage*, GenerativeAnswers) | Query `customEvents` or `AppEvents` for recent BotMessageSend events |

## Dataverse Access Requirements

| Resource | Required Permission | Purpose |
|----------|-------------------|---------|
| Dataverse environment | Application user with read access | Session sync pipeline |
| msdyn_botsession | Read | Session outcome records |
| bot | Read | Agent metadata (name, schema name) |
| botcomponent | Read | Agent type classification |
| msdyn_botcomponentsession (Tier 2 — planned) | Read | Per-topic session data *(not yet used by sync pipeline)* |
| conversationtranscript (Tier 2 — planned) | Read | Detailed behavior metrics *(not yet used by sync pipeline)* |
| fsi_csasyncwatermarks | Read/Write | Sync tracking table (created by schema script) |

### Authentication Setup

Use the strongest credential available for the runtime:

1. Prefer managed identity for Azure-hosted jobs, or workload identity federation for GitHub Actions and other CI runners.
2. For app-only Dataverse access, create or reuse an Entra ID app registration and add the Dataverse API permission: `https://org.api.crm.dynamics.com/.default`.
3. Configure certificate authentication for production app credentials when managed identity or workload identity is not available.
4. Use client secrets only as a legacy development fallback; do not store secrets in configuration files or source control.
5. Create an application user in Power Platform admin center:
   - Navigate to **Environments** > your environment > **Settings** > **Users + permissions** > **Application users**
   - Click **+ New app user** and select your app registration or managed identity enterprise application
   - Assign a security role with read access to the tables listed above

### Required Configuration Values

| Config Key | Source | Example |
|-----------|--------|---------|
| `dataverse.environment_url` | Power Platform admin center > Environment URL | `https://org12345.api.crm.dynamics.com` |
| `dataverse.auth_mode` | Runtime credential type | `managed-identity`, `workload-identity`, `certificate`, `interactive`, or legacy `client-secret` |
| `dataverse.tenant_id` | Entra ID > App registration > Overview | Required for workload identity, certificate, interactive, and legacy client-secret auth |
| `dataverse.client_id` | Entra ID > App registration > Overview | Required for workload identity, certificate, interactive, and legacy client-secret auth |
| `dataverse.managed_identity_client_id` | Managed identity resource | Optional; use only for user-assigned managed identity |
| `DATAVERSE_CLIENT_SECRET` env var | Entra ID > App registration > Certificates & secrets | Legacy development fallback only; store securely outside config files |
| `subscription_id` | Azure Portal > Subscriptions | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `resource_group` | Azure Portal > Resource Groups | `rg-agent-observability-dev` |
| `application_insights.name` | Azure Portal > Application Insights | `ai-copilot-analytics-dev` |

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
| msal | 1.24.0+ | Dataverse interactive and legacy confidential-client authentication |
| requests | 2.31.0+ | Dataverse Web API calls |
| applicationinsights | 0.11.10+ | Application Insights telemetry export |
| pyyaml | 6.0+ | Configuration file parsing |
| azure-identity | 1.14.0+ | Azure credential management |
| azure-monitor-query | 1.3.0+ | Log Analytics query for validation |
| azure-mgmt-applicationinsights | 4.0.0+ | App Insights management for validation |

## Transcript Retention Extension (Recommended for Future Tier 2 Support)

> **This step is relevant for Tier 2 data availability (planned for a future release).**
>
> Tier 2 sync capabilities (transcript-level analysis, per-action tracking) are not yet implemented
> in the current sync pipeline. However, extending transcript retention now helps ensure historical
> data is available when Tier 2 support is added.

Dataverse includes a default system job that bulk-deletes `conversationtranscript` records after 30 days. If not extended, future Tier 2 queries (topic-level sessions, action execution, precise knowledge source counts) would lose historical data after one month.

### Impact of Default Retention

| Tier | Affected | Impact if Not Extended |
|------|----------|----------------------|
| Tier 1 | No | msdyn_botsession records are not subject to bulk delete |
| Tier 2 *(planned)* | Yes (when implemented) | conversationtranscript records deleted after 30 days |

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
2. Navigate to **Settings** > **Advanced**
3. Within the **Application Insights** section, enter the **Connection string** (same string used by AOF)
4. Optionally enable **CSAT survey** (Settings > Customer satisfaction) for CSAT data in analytics

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
- [ ] **GenerativeAnswers events** visible in App Insights customEvents (planned Tier 2 knowledge-source signal; the current Tier 1 implementation uses a `msdyn_topicname` substring heuristic — see [docs/agent-assisted-hours-methodology.md](docs/agent-assisted-hours-methodology.md))

### Validation Commands

```bash
# Verify telemetry pipeline is operational (checks App Insights and event presence)
python scripts/validate_telemetry.py --config config/config.yml

# Extended lookback window for validation
python scripts/validate_telemetry.py --config config/config.yml --hours 48

# Verbose output for debugging
python scripts/validate_telemetry.py --config config/config.yml --verbose
```

## Pre-Deployment Checklist

- [ ] **AOF deployed** -- Application Insights and Log Analytics workspace operational
- [ ] **Runtime identity configured** -- Managed identity, workload identity, certificate, or legacy development secret has Dataverse application-user access
- [ ] **Configuration values collected** -- Dataverse URL, auth mode, identity IDs where required, and App Insights connection string
- [ ] **Legacy secret protected if used** -- Store development-only client secrets in an environment variable or key vault reference
- [ ] **Python environment ready** -- Python 3.9+ with dependencies installed
- [ ] **Transcript retention reviewed** -- Default 30-day bulk delete extended if Tier 2 analytics is planned
- [ ] **CSAT survey enabled** -- On agents where customer satisfaction tracking is desired
- [ ] **Test agent available** -- At least one agent with production sessions for validation

---

*Prerequisites version: 2.0.1*
*Last updated: 2026-Q2*
