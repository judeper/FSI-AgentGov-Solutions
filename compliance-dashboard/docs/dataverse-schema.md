# Dataverse Schema

Table definitions for the Compliance Dashboard data model.

---

## Schema Overview

```
┌─────────────────────┐     ┌─────────────────────┐
│  fsi_controlmaster  │────<│ fsi_controlassessment│
│  (62 sample / 78 baseline)      │     │  (assessments)       │
└─────────────────────┘     └─────────────────────┘
                                    │          │
                                    │          │
                                    ▼          ▼
                          ┌──────────────────┐ ┌─────────────────────┐
                          │fsi_compliance    │ │ fsi_complianceevidence│
                          │  exception       │ │  (evidence links)    │
                          │  (open exceptions)│ └─────────────────────┘
                          └──────────────────┘

┌─────────────────────┐
│ fsi_compliancescore │
│  (daily snapshots)  │
└─────────────────────┘
```

---

## Table: fsi_controlmaster

Master list of controls. The shipped sample dataset contains 62 controls; the validated FSI Agent Governance Framework baseline contains 78. Load whichever set matches your environment.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_controlmasterid` | Uniqueidentifier | Yes | Primary key |
| `fsi_controlid` | String (10) | Yes | Control identifier (e.g., "1.1", "2.12") |
| `fsi_name` | String (200) | Yes | Control name |
| `fsi_pillar` | Choice | Yes | Pillar (1-Security, 2-Management, 3-Reporting, 4-SharePoint) |
| `fsi_description` | Text | No | Control description |
| `fsi_zone1applicable` | Boolean | Yes | Applicable to Zone 1 |
| `fsi_zone2applicable` | Boolean | Yes | Applicable to Zone 2 |
| `fsi_zone3applicable` | Boolean | Yes | Applicable to Zone 3 |
| `fsi_regulatoryreference` | Text | No | Related regulations (FINRA, SEC, etc.) |
| `fsi_weight` | Decimal | Yes | Control weight for scoring (1.0-3.0) |
| `fsi_category` | Choice | No | Category (Native Feature, Custom Solution, Process Control) |
| `createdon` | DateTime | Auto | Record creation timestamp |
| `modifiedon` | DateTime | Auto | Record modification timestamp |

### Choice: fsi_pillar

| Value | Label |
|-------|-------|
| 1 | Security |
| 2 | Management |
| 3 | Reporting |
| 4 | SharePoint |

### Choice: fsi_category

| Value | Label |
|-------|-------|
| 1 | Native Microsoft Feature |
| 2 | Custom Solution Required |
| 3 | Process/Documentation Control |

### Sample Data

```json
{
  "fsi_controlid": "2.12",
  "fsi_name": "Supervision and Oversight (FINRA Rule 3110)",
  "fsi_pillar": 2,
  "fsi_description": "Establish supervisory procedures for AI agent outputs",
  "fsi_zone1applicable": false,
  "fsi_zone2applicable": true,
  "fsi_zone3applicable": true,
  "fsi_regulatoryreference": "FINRA Rule 3110, FINRA Rule 3120",
  "fsi_weight": 3.0,
  "fsi_category": 2
}
```

---

## Table: fsi_controlassessment

Assessment records for each control, capturing compliance status.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_controlassessmentid` | Uniqueidentifier | Yes | Primary key |
| `fsi_controlmasterid` | Lookup | Yes | Reference to control master |
| `fsi_assessmentdate` | DateTime | Yes | Date of assessment |
| `fsi_status` | Choice | Yes | Compliance status |
| `fsi_zone` | Choice | Yes | Zone being assessed |
| `fsi_score` | Integer | Yes | Numeric score (0, 50, 100) |
| `fsi_assessor` | Lookup (User) | Yes | Person who performed assessment |
| `fsi_notes` | Text | No | Assessment notes |
| `fsi_nextreviewdate` | DateTime | No | Scheduled next review |
| `fsi_evidencecount` | Integer | No | Number of linked evidence items |
| `createdon` | DateTime | Auto | Record creation timestamp |

### Choice: fsi_status

| Value | Label | Score |
|-------|-------|-------|
| 1 | Compliant | 100 |
| 2 | Partial | 50 |
| 3 | Non-Compliant | 0 |
| 4 | Not Applicable | N/A |

### Choice: fsi_zone

| Value | Label |
|-------|-------|
| 1 | Zone 1 - Personal Productivity |
| 2 | Zone 2 - Team Collaboration |
| 3 | Zone 3 - Enterprise Managed |

---

## Table: fsi_compliancescore

Daily compliance score snapshots for trend analysis.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_compliancescoreid` | Uniqueidentifier | Yes | Primary key |
| `fsi_scoredate` | Date | Yes | Score calculation date |
| `fsi_overallscore` | Decimal | Yes | Overall compliance score (0-100) |
| `fsi_pillar1score` | Decimal | No | Security pillar score |
| `fsi_pillar2score` | Decimal | No | Management pillar score |
| `fsi_pillar3score` | Decimal | No | Reporting pillar score |
| `fsi_pillar4score` | Decimal | No | SharePoint pillar score |
| `fsi_zone1score` | Decimal | No | Zone 1 score |
| `fsi_zone2score` | Decimal | No | Zone 2 score |
| `fsi_zone3score` | Decimal | No | Zone 3 score |
| `fsi_compliantcount` | Integer | Yes | Count of compliant controls |
| `fsi_partialcount` | Integer | Yes | Count of partial controls |
| `fsi_noncompliantcount` | Integer | Yes | Count of non-compliant controls |
| `fsi_exceptioncount` | Integer | Yes | Count of open exceptions |
| `createdon` | DateTime | Auto | Record creation timestamp |

### Index

Create an index on `fsi_scoredate` for efficient trend queries.

---

## Table: fsi_complianceexception

Open compliance exceptions requiring remediation.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_complianceexceptionid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Exception title |
| `fsi_controlassessmentid` | Lookup | Yes | Related assessment |
| `fsi_severity` | Choice | Yes | Exception severity |
| `fsi_exceptionstatus` | Choice | Yes | Exception status |
| `fsi_owner` | Lookup (User) | Yes | Assigned owner |
| `fsi_description` | Text | Yes | Exception description |
| `fsi_rootcause` | Text | No | Root cause analysis |
| `fsi_remediationplan` | Text | No | Remediation plan |
| `fsi_targetdate` | Date | Yes | Target remediation date |
| `fsi_actualclosedate` | Date | No | Actual close date |
| `fsi_daysopen` | Integer | Calculated | Days exception has been open |
| `fsi_slastatus` | Choice | Calculated | SLA status (On Track, At Risk, Breached) |
| `createdon` | DateTime | Auto | Record creation timestamp |
| `modifiedon` | DateTime | Auto | Record modification timestamp |

### Choice: fsi_severity

| Value | Label | SLA (Days) |
|-------|-------|------------|
| 1 | Critical | 7 |
| 2 | High | 14 |
| 3 | Medium | 30 |
| 4 | Low | 90 |

### Choice: fsi_exceptionstatus

| Value | Label |
|-------|-------|
| 1 | Open |
| 2 | In Progress |
| 3 | Pending Verification |
| 4 | Closed |
| 5 | Accepted Risk |

### Choice: fsi_slastatus

| Value | Label |
|-------|-------|
| 1 | On Track |
| 2 | At Risk |
| 3 | Breached |

### Business Rule: Calculate SLA Status

```
IF fsi_exceptionstatus IN (1, 2, 3) THEN
  IF fsi_daysopen > SLA[fsi_severity] THEN
    fsi_slastatus = 3 (Breached)
  ELSE IF fsi_daysopen > SLA[fsi_severity] * 0.8 THEN
    fsi_slastatus = 2 (At Risk)
  ELSE
    fsi_slastatus = 1 (On Track)
  END IF
END IF
```

---

## Table: fsi_complianceevidence

Evidence items linked to assessments for audit purposes.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_complianceevidenceid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Evidence title |
| `fsi_controlassessmentid` | Lookup | Yes | Related assessment |
| `fsi_evidencetype` | Choice | Yes | Type of evidence |
| `fsi_sourceurl` | URL | No | Link to evidence source |
| `fsi_evidencedescription` | Text | No | Evidence description |
| `fsi_collecteddate` | DateTime | Yes | Date evidence was collected |
| `fsi_collectedby` | Lookup (User) | Yes | Person who collected evidence |
| `fsi_hash` | String (64) | No | SHA-256 hash for integrity |
| `createdon` | DateTime | Auto | Record creation timestamp |

### Choice: fsi_evidencetype

| Value | Label |
|-------|-------|
| 1 | Screenshot |
| 2 | Configuration Export |
| 3 | Audit Log |
| 4 | Policy Document |
| 5 | Test Result |
| 6 | External Report |

---

## Relationships

| Parent Table | Child Table | Relationship |
|--------------|-------------|--------------|
| fsi_controlmaster | fsi_controlassessment | 1:N |
| fsi_controlassessment | fsi_complianceexception | 1:N |
| fsi_controlassessment | fsi_complianceevidence | 1:N |

---

## Exchange Online Evidence Integration

The `Get-ExchangeComplianceData.ps1` script produces a JSON evidence file that maps to the existing schema as follows:

### Mapping to fsi_complianceevidence

| Exchange Signal | fsi_evidencetype | Suggested Control Mapping |
|----------------|------------------|--------------------------|
| External forwarding rules | 2 (Configuration Export) | 3.3, 1.5 |
| DLP policy alerts | 3 (Audit Log) | 3.3, 1.8 |
| Inactive shared mailboxes | 2 (Configuration Export) | 3.1 |
| External DL membership | 2 (Configuration Export) | 3.3, 3.8 |

### Import Workflow

1. Run `Get-ExchangeComplianceData.ps1` to generate the JSON evidence file
2. Import evidence records into `fsi_complianceevidence` via:
   - Power Automate flow (recommended — use CD-EvidenceCollector when implemented)
   - Dataverse Web API (`POST /api/data/v9.2/fsi_complianceevidences`)
   - Power Apps manual import
3. Link each evidence record to the appropriate `fsi_controlassessment` via `fsi_controlassessmentid`
4. The `fsi_hash` column should be populated with the `contentHash` from the report metadata for integrity verification

---

## Security Roles

### CD Viewer

Read-only access for dashboard consumers.

| Table | Permissions |
|-------|-------------|
| fsi_controlmaster | Read |
| fsi_controlassessment | Read |
| fsi_compliancescore | Read |
| fsi_complianceexception | Read |
| fsi_complianceevidence | Read |

### CD Assessor

Assessment entry and exception management.

| Table | Permissions |
|-------|-------------|
| fsi_controlmaster | Read |
| fsi_controlassessment | Read, Create, Update |
| fsi_compliancescore | Read |
| fsi_complianceexception | Read, Create, Update |
| fsi_complianceevidence | Read, Create, Update |

### CD Admin

Full administrative access.

| Table | Permissions |
|-------|-------------|
| All tables | Read, Create, Update, Delete |

---

## Deployment

### Manual Creation

Use the Power Apps maker portal or PAC CLI to create tables manually following the schema above. The solution does not ship a packaged `.zip` file — see [templates/README.md](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/compliance-dashboard/templates/README.md) for guidance.

### Post-Deployment

1. Assign security roles to users
2. Load control master data from `sample-data/control-master.json`
3. Configure Power Automate flows

---

*Compliance Dashboard v1.0.3*
