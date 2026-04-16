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
| msdyn_botsessionid | Uniqueidentifier | Primary key | Used as operation_Id for deduplication |
| msdyn_botid | Lookup (bot) | Reference to the agent | Foreign key to bot table |
| msdyn_sessionoutcome | OptionSet | Session result | See outcome values below |
| msdyn_csatscore | Integer | Customer satisfaction score | 1-5 scale; null if survey not enabled |
| msdyn_sessioncreatedon | DateTime | Session start timestamp | UTC |
| msdyn_sessionclosedon | DateTime | Session end timestamp | UTC; used as event timestamp |
| msdyn_conversationid | String | Conversation identifier | Links to conversationtranscript |
| msdyn_channelid | String | Channel identifier | Teams, Web, etc. |
| msdyn_sessionoutcomereason | String | Reason for session outcome | e.g., escalation reason, resolution detail |
| msdyn_isengaged | Boolean | Whether the user engaged with the agent | Filters out non-interactive sessions |
| msdyn_topicname | String | Topic name associated with the session | Primary topic that handled the session |
| modifiedon | DateTime | Last modified timestamp | Used for watermark-based sync |
| createdon | DateTime | Record creation timestamp | |

**Session Outcome Values (msdyn_sessionoutcome):**

| Value | Label | Description |
|-------|-------|-------------|
| 1 | Resolved | Session completed successfully -- user's intent was addressed |
| 2 | Escalated | Session transferred to a human agent |
| 3 | Abandoned | User left the session without resolution |
| 4 | Unengaged | Session started but no meaningful interaction occurred |

> **Note:** Outcome values may vary by Copilot Studio version. Verify against your environment's option set metadata using `GET /api/data/v9.2/EntityDefinitions(LogicalName='msdyn_botsession')/Attributes(LogicalName='msdyn_sessionoutcome')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?$select=LogicalName&$expand=OptionSet`.

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
| componenttype | OptionSet | Component type identifier | |
| componenttypename | String | Component type name | Key field for classification |
| botid | Lookup (bot) | Parent agent reference | Join key to bot table |
| schemaname | String | Component schema name | |
| createdon | DateTime | Component creation timestamp | |

**Agent Type Classification Logic:**

| componenttypename Value | Classification | Description |
|-------------------------|---------------|-------------|
| 17 (External Trigger) | Autonomous | Agent triggered by events, not user conversations |
| Other values | Conversational | Standard conversational agent |

> **Classification query:** `GET /api/data/v9.2/botcomponents?$filter=_botid_value eq '{botId}'&$select=componenttypename`

---

## Tier 2 Tables (Planned)

> **Note:** Tier 2 table queries are planned for a future release and are not yet implemented in the sync pipeline. The table schemas below document the intended data sources.

> **Retention warning:** conversationtranscript records are subject to a default 30-day bulk delete job. See [prerequisites.md](../prerequisites.md) for extension instructions.

### msdyn_botcomponentsession

Per-topic session data. Each record represents the execution of a specific topic (dialog) within a session.

| Column (Logical Name) | Type | Description | Notes |
|------------------------|------|-------------|-------|
| msdyn_botcomponentsessionid | Uniqueidentifier | Primary key | |
| msdyn_botsessionid | Lookup (msdyn_botsession) | Parent session | Join key to session table |
| msdyn_botcomponentid | Lookup (botcomponent) | Topic/dialog executed | |
| msdyn_topicname | String | Topic display name | |
| msdyn_sessionoutcome | OptionSet | Topic-level outcome | Same option set as session outcome |
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
| conversationid | String | Conversation identifier | Links to msdyn_botsession.msdyn_conversationid |
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

> **Schema creation:** Run `python scripts/create_csa_dataverse_schema.py` to create this table. Use `--output-docs` flag to generate schema documentation. See [docs/dataverse-schema.md](../docs/dataverse-schema.md) for the auto-generated reference.

---

## OData Query Patterns

### Tier 1 Incremental Sync

```
GET /api/data/v9.2/msdyn_botsessions
  ?$filter=msdyn_sessioncreatedon ge {watermark}
  &$select=msdyn_botsessionid,msdyn_sessionoutcome,msdyn_csatscore,
           msdyn_sessioncreatedon,msdyn_sessionclosedon,_msdyn_botid_value,
           msdyn_conversationid,msdyn_channelid,modifiedon
  &$orderby=msdyn_sessioncreatedon asc
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
  ?$filter=_botid_value eq '{botId}'
  &$select=botcomponentid,componenttypename
```

### Tier 2 Topic Sessions *(Planned)*

```
GET /api/data/v9.2/msdyn_botcomponentsessions
  ?$filter=createdon gt {watermark}
  &$select=msdyn_botcomponentsessionid,_msdyn_botsessionid_value,
           msdyn_topicname,msdyn_sessionoutcome,
           msdyn_sessioncreatedon,msdyn_sessionclosedon
  &$orderby=createdon asc
  &$top=5000
```

---

*Dataverse Data Sources version: 1.1.0*
*Last updated: February 2026*
