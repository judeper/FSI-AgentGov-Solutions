# Dataverse Data Sources

Reference documentation for the Dataverse tables used by Copilot Studio Analytics.

## Overview

CSA reads from five Dataverse tables across two tiers. Tier 1 tables provide session-level outcome data and are queried on every sync. Tier 2 tables are planned for a future release and will provide detailed behavior data when implemented.

| Table | Tier | Purpose | Sync Frequency |
|-------|------|---------|----------------|
| msdyn_botsession | 1 | Session outcome records | Every sync cycle |
| bot | 1 | Agent metadata | Every sync cycle (cached) |
| botcomponent | 1 | Agent type classification | Daily (cached) |
| msdyn_botcomponentsession | 2 *(planned)* | Per-topic session data | Daily batch *(planned)* |
| conversationtranscript | 2 *(planned)* | Detailed conversation content | Daily batch *(planned)* |

---

## Tier 1 Tables

### msdyn_botsession

The primary data source for session outcome analytics. Each record represents one user session with a Copilot Studio agent.

| Column (Logical Name) | Type | Description | Notes |
|------------------------|------|-------------|-------|
| msdyn_botsessionid | Uniqueidentifier | Primary key | Used as session ID for deduplication |
| msdyn_botid | Lookup (bot) | Reference to the agent | Foreign key to bot table (`_msdyn_botid_value`) |
| msdyn_outcome | OptionSet | Session result | Global choice `msdyn_sessionoutcome`; see outcome values below |
| msdyn_outcomereason | OptionSet | Reason for session outcome | Global choice `msdyn_sessionoutcomereason`; see reason values below |
| msdyn_csatscore | Integer | Customer satisfaction score | 1-5 scale; null if survey not enabled |
| msdyn_startedon | DateTime | Session start timestamp | UTC; used for the lookback filter and `$orderby` |
| msdyn_endedon | DateTime | Session end timestamp | UTC; used as event timestamp (falls back to start) |
| msdyn_isengaged | Boolean | Whether the user engaged with the agent | Filters out non-interactive sessions |
| msdyn_topicname | String | Topic name associated with the session | Primary topic that handled the session |
| msdyn_convtranscriptid | Lookup | Conversation transcript reference | Reserved for Tier 2 transcript parsing |
| modifiedon | DateTime | Last modified timestamp | |
| createdon | DateTime | Record creation timestamp | |

> **No channel column:** `msdyn_botsession` does not expose a channel identifier in its
> documented schema, so channel-derived `usageType` (Internal/External) is not available
> in Tier 1. The sync emits `usageType = "Unknown"`; channel classification is planned for
> Tier 2 (conversation-transcript parsing). Source of truth for this table's columns is the
> [official `msdyn_botsession` entity reference](https://learn.microsoft.com/en-us/dynamics365/developer/reference/entities/msdyn_botsession).

**Session Outcome Values (`msdyn_outcome`, global choice `msdyn_sessionoutcome`):**

The following integer optionset values are documented in the official `msdyn_botsession`
entity reference and are what the sync code (`scripts/sync_dataverse_sessions.py`
`SESSION_OUTCOMES`) reads:

| Value | Label (Microsoft) | Mapped label | Description |
|-------|-------------------|--------------|-------------|
| 419550000 | none | Unengaged | No outcome recorded -- typically an unengaged session |
| 419550001 | resolved | Resolved | Session completed successfully -- user's intent was addressed |
| 419550002 | escalated | Escalated | Session transferred to a human agent |
| 419550003 | abandoned | Abandoned | User left the session without resolution |

**Session Outcome Reason Values (`msdyn_outcomereason`, global choice `msdyn_sessionoutcomereason`):**

| Value | Label (Microsoft) |
|-------|-------------------|
| 419560000 | noError |
| 419560001 | userError |
| 419560002 | systemError |
| 419560003 | userExit |
| 419560004 | agentTransferWithoutError |
| 419560005 | agentTransferRequestedByUser |
| 419560006 | resolved |
| 419560007 | agentTransferConfiguredByAuthor |
| 419560008 | agentTransferFromQuestionMaxAttempts |

> **Note:** Optionset values are Microsoft-managed and may change across Copilot Studio releases. Verify against your environment's option set metadata using `GET /api/data/v9.2/EntityDefinitions(LogicalName='msdyn_botsession')/Attributes(LogicalName='msdyn_outcome')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?$expand=OptionSet`.

### bot

Agent metadata table. Provides display names and identifiers for agents referenced in session records.

| Column (Logical Name) | Type | Description | Notes |
|------------------------|------|-------------|-------|
| botid | Uniqueidentifier | Primary key | Referenced by msdyn_botsession.msdyn_botid |
| name | String | Agent display name | User-facing name in Copilot Studio |
| schemaname | String | Agent schema name | Internal identifier |
| botcomponentid | Lookup | Primary component reference | |
| statecode | OptionSet | Record state | 0 = Active |
| statuscode | OptionSet | Status reason | |
| createdon | DateTime | Agent creation timestamp | |

### botcomponent

Component metadata table. Used for agent type classification -- specifically to identify autonomous agents.

| Column (Logical Name) | Type | Description | Notes |
|------------------------|------|-------------|-------|
| botcomponentid | Uniqueidentifier | Primary key | |
| name | String | Component display name | |
| componenttype | OptionSet (integer) | Component type identifier | **Key field for classification.** Filter on this integer value, e.g. `componenttype eq 17`. |
| componenttypename | String | Human-readable component-type label | Informational only — do **not** filter on this. |
| parentbotid | Lookup (bot) | Parent agent reference (`_parentbotid_value` in the Web API) | Join key to bot table. There is no `botid` column on botcomponent. |
| schemaname | String | Component schema name | |
| createdon | DateTime | Component creation timestamp | |

**Agent Type Classification Logic:**

| componenttype Value | Classification | Description |
|---------------------|---------------|-------------|
| 17 (External Trigger) | Autonomous | Agent triggered by events, not user conversations |
| Other values | Conversational | Standard conversational agent |

> **Classification query:** `GET /api/data/v9.2/botcomponents?$filter=_parentbotid_value eq '{botId}' and componenttype eq 17&$select=_parentbotid_value,componenttype`

---

## Tier 2 Tables (Planned)

> **Note:** Tier 2 table queries are planned for a future release and are not yet implemented in the sync pipeline. The table schemas below document the intended data sources.

> **Retention warning:** conversationtranscript records are subject to a default 30-day bulk delete job. See [prerequisites.md](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/copilot-studio-analytics/prerequisites.md) for extension instructions.

### msdyn_botcomponentsession

Per-topic session data. Each record represents the execution of a specific topic (dialog) within a session.

| Column (Logical Name) | Type | Description | Notes |
|------------------------|------|-------------|-------|
| msdyn_botcomponentsessionid | Uniqueidentifier | Primary key | |
| msdyn_botsessionid | Lookup (msdyn_botsession) | Parent session | Join key to session table |
| msdyn_botcomponentid | Lookup (botcomponent) | Topic/dialog executed | |
| msdyn_topicname | String | Topic display name | |
| msdyn_outcome | OptionSet | Topic-level outcome | Global choice `msdyn_sessionoutcome` (verify per environment) |
| msdyn_startedon | DateTime | Topic start timestamp | |
| msdyn_endedon | DateTime | Topic end timestamp | |
| createdon | DateTime | Record creation timestamp | |

**Use cases:**
- Topic performance analysis (which topics resolve vs escalate)
- Topic-level duration and engagement metrics
- Multi-topic session flow analysis

### conversationtranscript

Full conversation content in JSON format. Contains message-level detail including action execution and knowledge source references.

| Column (Logical Name) | Type | Description | Notes |
|------------------------|------|-------------|-------|
| conversationtranscriptid | Uniqueidentifier | Primary key | |
| name | String | Transcript display name | |
| conversationid | String | Conversation identifier | Correlate via `msdyn_botsession.msdyn_convtranscriptid` lookup |
| content | Memo (large text) | JSON conversation content | Requires JSON parsing -- see schema below |
| schematype | String | Content schema identifier | Indicates JSON structure version |
| createdon | DateTime | Transcript creation timestamp | Subject to 30-day bulk delete |
| bot_conversationtranscriptid | Lookup (bot) | Agent reference | |

**Content JSON Structure (simplified):**

```json
{
  "activities": [
    {
      "type": "message",
      "from": { "role": "user" },
      "text": "...",
      "timestamp": "2026-02-20T10:30:00Z"
    },
    {
      "type": "message",
      "from": { "role": "bot" },
      "text": "...",
      "timestamp": "2026-02-20T10:30:05Z",
      "entities": [
        {
          "type": "https://schema.org/Citation",
          "name": "Knowledge source name",
          "url": "..."
        }
      ]
    },
    {
      "type": "invoke",
      "name": "ActionName",
      "value": { "...action parameters..." },
      "timestamp": "2026-02-20T10:30:10Z"
    }
  ]
}
```

**Tier 2 data extracted from content JSON *(planned — not yet implemented)*:**

| Data Point | JSON Path | Description |
|-----------|-----------|-------------|
| Knowledge source citations | `activities[].entities[type=Citation]` | Precise count of KS references per session |
| Action executions | `activities[type=invoke]` | Count and names of actions executed |
| Conversation turns | `activities[type=message]` | User and bot message count |
| Time between turns | `activities[].timestamp` differences | Response latency at message level |

---

## Watermark Tracking Table

### fsi_CSASyncWatermark

Custom Dataverse table created by `create_csa_dataverse_schema.py`. Tracks sync progress per environment.

| Column (Logical Name) | Type | Description | Notes |
|------------------------|------|-------------|-------|
| fsi_csasyncwatermarkid | Uniqueidentifier | Primary key | Auto-generated |
| fsi_environmenturl | String (500) | Dataverse environment URL | Unique per environment |
| fsi_lastsynctimestamp | DateTime | Last successful sync timestamp | Used as watermark for incremental queries |
| fsi_recordssynced | Integer | Records synced in last run | For monitoring sync health |
| fsi_syncstatus | OptionSet | Last sync result | Success, Failed, InProgress, Warning |
| fsi_synctier | OptionSet | Data tier synced | Tier1, Tier2 |
| fsi_errormessage | Multiline | Error details on failure | Null on success |

> **Schema creation:** Run `python scripts/create_csa_dataverse_schema.py` to create this table. Use `--output-docs` flag to generate schema documentation. See [dataverse-schema.md](./dataverse-schema.md) for the auto-generated reference.

---

## OData Query Patterns

### Tier 1 Incremental Sync

```
GET /api/data/v9.2/msdyn_botsessions
  ?$filter=msdyn_startedon ge {watermark}
  &$select=msdyn_botsessionid,msdyn_outcome,msdyn_outcomereason,msdyn_csatscore,
           msdyn_startedon,msdyn_endedon,_msdyn_botid_value,
           msdyn_isengaged,msdyn_topicname
  &$orderby=msdyn_startedon asc
  &$top=5000
```

### Agent Metadata (Cached)

```
GET /api/data/v9.2/bots
  ?$filter=statecode eq 0
  &$select=botid,name,schemaname
```

### Agent Type Classification (Cached)

```
GET /api/data/v9.2/botcomponents
  ?$filter=_parentbotid_value eq '{botId}' and componenttype eq 17
  &$select=botcomponentid,componenttype,_parentbotid_value
```

### Tier 2 Topic Sessions *(Planned)*

```
GET /api/data/v9.2/msdyn_botcomponentsessions
  ?$filter=createdon gt {watermark}
  &$select=msdyn_botcomponentsessionid,_msdyn_botsessionid_value,
           msdyn_topicname,msdyn_outcome,
           msdyn_startedon,msdyn_endedon
  &$orderby=createdon asc
  &$top=5000
```

---

*Dataverse Data Sources version: 2.0.1*
*Last updated: 2026-Q2*
