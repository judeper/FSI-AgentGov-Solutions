# Architecture

This document describes the data flow and component architecture of the Copilot Studio Analytics solution.

## Data Flow Overview

CSA combines two telemetry streams into a unified analytics layer. Native Copilot Studio events (managed by AOF) provide operational signals, while Dataverse session records (synced by CSA) provide business outcome data. Both streams land in the same Application Insights workspace, enabling cross-correlation via KQL queries and Azure Monitor Workbooks.

```mermaid
graph LR
    subgraph "Copilot Studio"
        A1[Agent Conversations]
        A2[Autonomous Agent Runs]
    end

    subgraph "Native Telemetry (AOF-managed)"
        B1[BotMessageSend<br/>BotMessageReceived]
        B2[GenerativeAnswers<br/>CopilotInteraction]
    end

    subgraph "Dataverse"
        D1[msdyn_botsession]
        D2[bot]
        D3[botcomponent]
        D4[msdyn_botcomponentsession<br/>Tier 2 — Planned]
        D5[conversationtranscript<br/>Tier 2 — Planned]
    end

    subgraph "CSA Sync Pipeline"
        S1[sync_dataverse_sessions.py]
        S2[fsi_CSASyncWatermark<br/>Tracking Table]
    end

    subgraph "Azure Monitor"
        AI[Application Insights<br/>customEvents]
        LA[Log Analytics<br/>Workspace]
    end

    subgraph "Analytics Layer"
        Q[KQL Query Library<br/>15 queries]
        W[Azure Monitor Workbooks<br/>4 workbooks, 14 tabs]
    end

    A1 -->|Native events| B1
    A1 -->|Native events| B2
    A2 -->|Native events| B1
    A2 -->|Native events| B2
    B1 -->|Automatic| AI
    B2 -->|Automatic| AI

    A1 -->|Session records| D1
    A2 -->|Session records| D1

    D1 --> S1
    D2 --> S1
    D3 --> S1
    S2 <-->|Watermark tracking| S1
    S1 -->|CopilotSessionOutcome<br/>custom events| AI

    AI -->|Workspace binding| LA
    LA --> Q
    LA --> W

    style A1 fill:#0078d4,color:#fff
    style A2 fill:#0078d4,color:#fff
    style B1 fill:#50e6ff,color:#000
    style B2 fill:#50e6ff,color:#000
    style D1 fill:#742774,color:#fff
    style D2 fill:#742774,color:#fff
    style D3 fill:#742774,color:#fff
    style D4 fill:#742774,color:#fff
    style D5 fill:#742774,color:#fff
    style S1 fill:#ffb900,color:#000
    style S2 fill:#ffb900,color:#000
    style AI fill:#50e6ff,color:#000
    style LA fill:#50e6ff,color:#000
    style Q fill:#107c10,color:#fff
    style W fill:#107c10,color:#fff
```

## Tiered Data Strategy

CSA uses a two-tier approach to balance data availability, API complexity, and cost.

### Tier 1 -- Core Session Data

**Source tables:** msdyn_botsession, bot, botcomponent
**Sync method:** Dataverse Web API with OData queries
**Refresh frequency:** Configurable (daily to 4-6 hours)

Tier 1 provides session-level outcome data sufficient for most analytics:

| Data Point | Source | Notes |
|-----------|--------|-------|
| Session outcome | msdyn_botsession.msdyn_sessionoutcome | Resolved, Escalated, Abandoned, Unengaged |
| CSAT score | msdyn_botsession.msdyn_csatscore | 1-5 scale when survey enabled |
| Session duration | msdyn_botsession timestamps | Start and end time |
| Agent ID | msdyn_botsession.msdyn_botid | Joined with bot table for name |
| Agent type | botcomponent.componenttypename | 17 = External Trigger (autonomous) |
| Knowledge source proxy | GenerativeAnswers events (App Insights) | Result = "Success" indicates KS citation |

### Tier 2 -- Detailed Behavior Data (Planned)

> **Note:** Tier 2 capabilities described below are planned for a future release and are not yet implemented in the sync pipeline. The current `--tier 2` flag in `sync_dataverse_sessions.py` only changes the `syncTier` label on emitted events — it does not perform transcript parsing or emit additional fields. Current implementation provides Tier 1 data only.

**Source tables:** msdyn_botcomponentsession, conversationtranscript
**Sync method:** Additional Dataverse queries with content JSON parsing *(planned)*
**Refresh frequency:** Daily batch (higher API cost) *(planned)*

When implemented, Tier 2 will provide granular topic and action data for deeper analysis:

| Data Point | Source | Notes |
|-----------|--------|-------|
| Topic-level sessions | msdyn_botcomponentsession | Per-topic outcome within a session *(planned)* |
| Action execution | conversationtranscript content JSON | Requires JSON path parsing *(planned)* |
| Knowledge source count | conversationtranscript content JSON | Precise count vs Tier 1 proxy *(planned)* |
| Conversation turns | conversationtranscript | Message-level detail *(planned)* |

> **Important:** When implemented, Tier 2 data will depend on conversationtranscript records, which are subject to a default 30-day bulk delete job in Dataverse. See [prerequisites.md](prerequisites.md) for retention extension instructions.

## Watermark Sync Mechanism

The sync pipeline uses a Dataverse tracking table (`fsi_csawatermark`) to implement incremental synchronization.

### Sync Flow

1. **Read watermark:** Query fsi_csasyncwatermarks for the last successful sync timestamp per environment
2. **Check concurrency lock:** Verify no other sync is InProgress (advisory lock with stale timeout)
3. **Fetch new records:** Query msdyn_botsession where `msdyn_sessioncreatedon >= watermark - lookback_buffer` with `$orderby=msdyn_sessioncreatedon asc`
4. **Enrich records:** Join with bot (agent name) and botcomponent (agent type classification)
5. **Emit events:** Send CopilotSessionOutcome custom events to Application Insights via Track API
6. **Update watermark:** Write new watermark timestamp (last session's end time) after successful batch commit

### Failure Handling

- **Partial batch failure:** Watermark advances to the last session's timestamp; status recorded as WARNING with error details
- **Full batch failure:** Watermark status set to FAILED; next run retries the same window
- **Concurrent sync protection:** Advisory lock via InProgress watermark status prevents parallel runs (stale locks auto-expire after 30 minutes)
- **Lookback buffer:** Configurable overlap window (default 2 hours) re-fetches recent sessions to catch late-arriving records

### CopilotSessionOutcome Event Schema

Each synced session produces a custom event with these properties:

| Property | Type | Description |
|----------|------|-------------|
| name | string | `CopilotSessionOutcome` (fixed) |
| customDimensions.recipientId | string | Agent ID (matches AOF `recipientId` format) |
| customDimensions.sessionId | string | Unique session ID from `msdyn_sessionid` |
| customDimensions.sessionOutcome | string | Conversational: Resolved, Escalated, Abandoned; Autonomous: Success, Failure |
| customDimensions.sessionOutcomeReason | string | Sub-type from `msdyn_outcomereason` |
| customDimensions.isEngaged | boolean | Engaged session flag from `msdyn_isengaged` |
| customDimensions.csatScore | number | 1-5 for conversational, empty for autonomous |
| customDimensions.sessionDurationSeconds | number | Duration from startedon/endedon |
| customDimensions.hasKnowledgeSource | boolean | Knowledge source proxy (Tier 1: GenerativeAnswers) |
| customDimensions.topicName | string | Primary topic from `msdyn_topicname` |
| customDimensions.agentMode | string | `Conversational` or `Autonomous` |
| customDimensions.channelId | string | Channel identifier |
| customDimensions.Zone | string | Governance zone from environment metadata |
| customDimensions.syncSource | string | `DataverseSync` (distinguishes from native events) |
| customDimensions.syncTier | string | `Tier1` or `Tier2` |
| timestamp | datetime | Session end time (msdyn_sessionclosedon), falling back to start time if not yet closed |

## Agent Type Classification

CSA classifies agents as either **conversational** or **autonomous** based on Dataverse metadata.

### Classification Logic

1. Query `botcomponent` table for records associated with the agent's bot ID
2. Check `componenttypename` values:
   - If any component has `componenttypename = 17` (External Trigger), the agent is classified as **autonomous**
   - Otherwise, the agent is classified as **conversational**
3. Classification is determined per sync run based on current botcomponent metadata

### Why Classification Matters

Conversational and autonomous agents have fundamentally different interaction models, requiring separate AAH calculations:

- **Conversational agents** interact with users via chat, handling questions and providing answers
- **Autonomous agents** execute tasks independently, triggered by events rather than user messages

See [docs/agent-assisted-hours-methodology.md](docs/agent-assisted-hours-methodology.md) for the separate calculation formulas.

## AOF Integration Points

| Integration Point | Direction | Description |
|-------------------|-----------|-------------|
| Application Insights workspace | CSA writes to AOF infrastructure | CopilotSessionOutcome events land in the same App Insights |
| Log Analytics workspace | CSA reads from AOF infrastructure | KQL queries correlate session outcomes with native events |
| GenerativeAnswers events | CSA reads AOF data | Used as Tier 1 proxy for knowledge source citations |
| BotMessageSend events | CSA reads AOF data | Used for session volume cross-validation |

---

*Architecture version: 1.1.0*
*Last updated: April 2026*
