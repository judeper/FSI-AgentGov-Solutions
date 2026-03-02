# Dataverse Schema

Table definitions for the RAG Source Validator.

---

## Table: fsi_knowledgesource

Registry of all RAG knowledge sources.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_knowledgesourceid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Source display name |
| `fsi_sourcetype` | Choice | Yes | Type of source |
| `fsi_sourceuri` | String (500) | Yes | Source location URI |
| `fsi_agentid` | String (36) | No | Associated agent |
| `fsi_owner` | Lookup (User) | Yes | Source owner |
| `fsi_description` | Text | No | Source description |
| `fsi_currenthash` | String (64) | No | Current SHA-256 hash |
| `fsi_baselinehash` | String (64) | No | Baseline hash for comparison |
| `fsi_status` | Choice | Yes | Source status |
| `fsi_lastvalidated` | DateTime | No | Last validation timestamp |
| `fsi_validationfrequency` | Choice | Yes | How often to validate |
| `fsi_alertonchange` | Boolean | Yes | Send alert on changes |
| `fsi_freshnessthreshold` | Integer | No | Days before stale warning |
| `fsi_lastmodified` | DateTime | No | Last known modification |
| `createdon` | DateTime | Auto | Record creation |
| `modifiedon` | DateTime | Auto | Record modification |

### Choice: fsi_sourcetype

| Value | Label |
|-------|-------|
| 1 | SharePoint Document Library |
| 2 | SharePoint List |
| 3 | SharePoint Page |
| 4 | Dataverse Table |
| 5 | Azure Blob Container |
| 6 | Azure Blob File |
| 7 | External API |
| 8 | Database Query |

### Choice: fsi_status

| Value | Label |
|-------|-------|
| 1 | Active |
| 2 | Pending Validation |
| 3 | Validation Failed |
| 4 | Stale |
| 5 | Archived |

### Choice: fsi_validationfrequency

| Value | Label |
|-------|-------|
| 1 | Real-time (webhook) |
| 2 | Hourly |
| 3 | Daily |
| 4 | Weekly |
| 5 | Monthly |

---

## Table: fsi_validationresult

History of validation executions.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_validationresultid` | Uniqueidentifier | Yes | Primary key |
| `fsi_knowledgesourceid` | Lookup | Yes | Source validated |
| `fsi_validationtime` | DateTime | Yes | Validation timestamp |
| `fsi_result` | Choice | Yes | Validation result |
| `fsi_previoushash` | String (64) | No | Hash before validation |
| `fsi_currenthash` | String (64) | No | Hash after validation |
| `fsi_hashchanged` | Boolean | Yes | Whether hash changed |
| `fsi_changedetails` | Text | No | Details of changes |
| `fsi_validationtype` | Choice | Yes | Type of validation |
| `fsi_duration` | Integer | No | Validation duration (ms) |
| `fsi_errordetails` | Text | No | Error if failed |
| `createdon` | DateTime | Auto | Record creation |

### Choice: fsi_result

| Value | Label |
|-------|-------|
| 1 | Passed |
| 2 | Failed - Hash Mismatch |
| 3 | Failed - Schema Drift |
| 4 | Failed - Stale Content |
| 5 | Failed - Source Unavailable |
| 6 | Warning - Minor Changes |
| 7 | Skipped - Not Implemented |
| 8 | Skipped - Unsupported Type |

### Choice: fsi_validationtype

| Value | Label |
|-------|-------|
| 1 | Scheduled |
| 2 | On-Demand |
| 3 | Webhook Triggered |
| 4 | Baseline Capture |

---

## Table: fsi_sourcechange

Tracked changes to knowledge sources.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_sourcechangeid` | Uniqueidentifier | Yes | Primary key |
| `fsi_knowledgesourceid` | Lookup | Yes | Affected source |
| `fsi_changetype` | Choice | Yes | Type of change |
| `fsi_detectedon` | DateTime | Yes | Detection timestamp |
| `fsi_previousvalue` | Text | No | Before change |
| `fsi_newvalue` | Text | No | After change |
| `fsi_changedby` | String (200) | No | User who made change |
| `fsi_reviewed` | Boolean | Yes | Change reviewed |
| `fsi_reviewedby` | Lookup (User) | No | Reviewer |
| `fsi_reviewedon` | DateTime | No | Review timestamp |
| `fsi_approved` | Boolean | No | Change approved |
| `createdon` | DateTime | Auto | Record creation |

### Choice: fsi_changetype

| Value | Label |
|-------|-------|
| 1 | Content Modified |
| 2 | Schema Changed |
| 3 | Source Moved |
| 4 | Source Deleted |
| 5 | Permissions Changed |
| 6 | New Content Added |

---

## Security Roles

### RSV Viewer

| Table | Permissions |
|-------|-------------|
| fsi_knowledgesource | Read |
| fsi_validationresult | Read |
| fsi_sourcechange | Read |

### RSV Validator

| Table | Permissions |
|-------|-------------|
| fsi_knowledgesource | Read, Update |
| fsi_validationresult | Read, Create |
| fsi_sourcechange | Read, Create, Update |

### RSV Admin

| Table | Permissions |
|-------|-------------|
| All tables | Full |

---

*RAG Source Validator v1.0.0*
