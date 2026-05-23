# Dataverse Schema Reference

> Auto-generated from `scripts/create_sd_dataverse_schema.py`. Do not edit manually.

This reference lists the Dataverse SchemaName and logical name for each table and column. The PowerShell scripts use the logical names shown here in OData requests.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_ConflictRule | fsi_conflictrule | Defines incompatible role combinations for SoD detection | fsi_name |
| fsi_SodViolation | fsi_sodviolation | Detected segregation of duties violation | fsi_name |
| fsi_SodException | fsi_sodexception | Approved exception for a justified role conflict | fsi_name |
| fsi_SodAuditLog | fsi_sodauditlog | Audit trail for SoD-related activity | fsi_name |

## Columns

### fsi_ConflictRule (`fsi_conflictrule`)

| SchemaName | Logical Name | Type | Required | Description | Values / Target |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Rule name |  |
| fsi_Category | fsi_category | Choice | Yes | Conflict category | `100000000` = Maker/Checker, `100000001` = Segregation, `100000002` = Privileged Access |
| fsi_RoleA | fsi_rolea | String | Yes | First role in conflict |  |
| fsi_RoleAContext | fsi_roleacontext | Choice | Yes | Context for Role A | `100000000` = Entra ID Directory Role, `100000001` = Entra ID App Role, `100000002` = Power Platform Environment Role, `100000003` = Dataverse Security Role, `100000004` = Custom Application Role |
| fsi_RoleB | fsi_roleb | String | Yes | Second role in conflict |  |
| fsi_RoleBContext | fsi_rolebcontext | Choice | Yes | Context for Role B | `100000000` = Entra ID Directory Role, `100000001` = Entra ID App Role, `100000002` = Power Platform Environment Role, `100000003` = Dataverse Security Role, `100000004` = Custom Application Role |
| fsi_Severity | fsi_severity | Choice | Yes | Violation severity | `100000000` = Critical, `100000001` = High, `100000002` = Medium, `100000003` = Low |
| fsi_Description | fsi_description | Memo | No | Rule description |  |
| fsi_Enabled | fsi_enabled | Boolean | Yes | Rule is active | `1` = Yes, `0` = No |
| fsi_AllowException | fsi_allowexception | Boolean | Yes | Exceptions are permitted | `1` = Yes, `0` = No |

### fsi_SodViolation (`fsi_sodviolation`)

| SchemaName | Logical Name | Type | Required | Description | Values / Target |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Violation title |  |
| fsi_ConflictRuleId | fsi_conflictruleid | Lookup | Yes | Violated rule | Targets: `fsi_conflictrule` |
| fsi_UserId | fsi_userid | String | Yes | User principal name |  |
| fsi_UserObjectId | fsi_userobjectid | String | Yes | Microsoft Entra object ID |  |
| fsi_UserDisplayName | fsi_userdisplayname | String | Yes | User display name |  |
| fsi_RoleAAssignment | fsi_roleaassignment | String | Yes | Role A assignment details |  |
| fsi_RoleBAssignment | fsi_rolebassignment | String | Yes | Role B assignment details |  |
| fsi_Environment | fsi_environment | String | No | Power Platform environment ID when applicable |  |
| fsi_Status | fsi_status | Choice | Yes | Violation status | `100000000` = Open, `100000001` = Under Review, `100000002` = Exception Requested, `100000003` = Exception Approved, `100000004` = Resolved - Role Removed, `100000005` = Resolved - User Removed, `100000006` = Closed - False Positive |
| fsi_DetectedOn | fsi_detectedon | DateTime | Yes | Detection timestamp |  |
| fsi_ResolvedOn | fsi_resolvedon | DateTime | No | Resolution timestamp |  |
| fsi_ResolutionType | fsi_resolutiontype | Choice | No | How the violation was resolved | `100000000` = Role A Removed, `100000001` = Role B Removed, `100000002` = Both Roles Removed, `100000003` = User Deactivated, `100000004` = Exception Granted, `100000005` = False Positive, `100000006` = Rule Disabled |
| fsi_ExceptionId | fsi_exceptionid | Lookup | No | Approved exception when applicable | Targets: `fsi_sodexception` |

### fsi_SodException (`fsi_sodexception`)

| SchemaName | Logical Name | Type | Required | Description | Values / Target |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Exception title |  |
| fsi_SodViolationId | fsi_sodviolationid | Lookup | Yes | Related violation | Targets: `fsi_sodviolation` |
| fsi_UserId | fsi_userid | String | Yes | User principal name |  |
| fsi_ExceptionType | fsi_exceptiontype | Choice | Yes | Exception type | `100000000` = Emergency, `100000001` = Temporary, `100000002` = Permanent |
| fsi_Justification | fsi_justification | Memo | Yes | Business justification |  |
| fsi_CompensatingControls | fsi_compensatingcontrols | Memo | Yes | Mitigating controls |  |
| fsi_MonitoringPlan | fsi_monitoringplan | Memo | No | Ongoing monitoring description |  |
| fsi_RequestedBy | fsi_requestedby | Lookup | Yes | Exception requestor | Targets: `systemuser` |
| fsi_RequestedOn | fsi_requestedon | DateTime | Yes | Request timestamp |  |
| fsi_ApprovedBy | fsi_approvedby | Lookup | No | Final approver | Targets: `systemuser` |
| fsi_ApprovedOn | fsi_approvedon | DateTime | No | Approval timestamp |  |
| fsi_Status | fsi_status | Choice | Yes | Exception status | `100000000` = Requested, `100000001` = Manager Approved, `100000002` = Compliance Review, `100000003` = Approved, `100000004` = Denied, `100000005` = Expired, `100000006` = Revoked |
| fsi_EffectiveDate | fsi_effectivedate | DateTime | No | Exception start date |  |
| fsi_ExpirationDate | fsi_expirationdate | DateTime | No | Exception end date |  |
| fsi_NextReviewDate | fsi_nextreviewdate | DateTime | No | Next review due date |  |
| fsi_RiskAcceptance | fsi_riskacceptance | Boolean | No | Risk formally accepted | `1` = Yes, `0` = No |

### fsi_SodAuditLog (`fsi_sodauditlog`)

| SchemaName | Logical Name | Type | Required | Description | Values / Target |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Log entry title |  |
| fsi_EventType | fsi_eventtype | Choice | Yes | Type of event | `100000000` = Violation Detected, `100000001` = Violation Resolved, `100000002` = Exception Requested, `100000003` = Exception Approved, `100000004` = Exception Denied, `100000005` = Exception Expired, `100000006` = Rule Created, `100000007` = Rule Modified, `100000008` = Rule Disabled, `100000009` = Scan Completed, `100000010` = Alert Sent |
| fsi_EntityType | fsi_entitytype | String | Yes | Related entity type |  |
| fsi_EntityId | fsi_entityid | String | Yes | Related entity ID |  |
| fsi_UserId | fsi_userid | String | Yes | User involved |  |
| fsi_PerformedBy | fsi_performedby | String | Yes | Action performer |  |
| fsi_EventDetails | fsi_eventdetails | Memo | No | Detailed event description |  |
| fsi_PreviousValue | fsi_previousvalue | Memo | No | Value before change |  |
| fsi_NewValue | fsi_newvalue | Memo | No | Value after change |  |
| fsi_IpAddress | fsi_ipaddress | String | No | Source IP address |  |

## Option Sets

### fsi_SD_category

Segregation of Duties conflict category

| Value | Label |
|---|---|
| 100000000 | Maker/Checker |
| 100000001 | Segregation |
| 100000002 | Privileged Access |

### fsi_SD_rolecontext

Source system where a role assignment is evaluated

| Value | Label |
|---|---|
| 100000000 | Entra ID Directory Role |
| 100000001 | Entra ID App Role |
| 100000002 | Power Platform Environment Role |
| 100000003 | Dataverse Security Role |
| 100000004 | Custom Application Role |

### fsi_SD_severity

Severity assigned to a detected SoD violation

| Value | Label |
|---|---|
| 100000000 | Critical |
| 100000001 | High |
| 100000002 | Medium |
| 100000003 | Low |

### fsi_SD_violationstatus

Lifecycle status for a SoD violation

| Value | Label |
|---|---|
| 100000000 | Open |
| 100000001 | Under Review |
| 100000002 | Exception Requested |
| 100000003 | Exception Approved |
| 100000004 | Resolved - Role Removed |
| 100000005 | Resolved - User Removed |
| 100000006 | Closed - False Positive |

### fsi_SD_resolutiontype

How a SoD violation was remediated or closed

| Value | Label |
|---|---|
| 100000000 | Role A Removed |
| 100000001 | Role B Removed |
| 100000002 | Both Roles Removed |
| 100000003 | User Deactivated |
| 100000004 | Exception Granted |
| 100000005 | False Positive |
| 100000006 | Rule Disabled |

### fsi_SD_exceptiontype

Approved exception duration category

| Value | Label |
|---|---|
| 100000000 | Emergency |
| 100000001 | Temporary |
| 100000002 | Permanent |

### fsi_SD_exceptionstatus

Approval status for a SoD exception

| Value | Label |
|---|---|
| 100000000 | Requested |
| 100000001 | Manager Approved |
| 100000002 | Compliance Review |
| 100000003 | Approved |
| 100000004 | Denied |
| 100000005 | Expired |
| 100000006 | Revoked |

### fsi_SD_auditeventtype

Type of SoD audit event

| Value | Label |
|---|---|
| 100000000 | Violation Detected |
| 100000001 | Violation Resolved |
| 100000002 | Exception Requested |
| 100000003 | Exception Approved |
| 100000004 | Exception Denied |
| 100000005 | Exception Expired |
| 100000006 | Rule Created |
| 100000007 | Rule Modified |
| 100000008 | Rule Disabled |
| 100000009 | Scan Completed |
| 100000010 | Alert Sent |

## OData entity sets used by scripts

| Table | Entity set | Used by |
|---|---|---|
| fsi_conflictrule | `fsi_conflictrules` | `Import-ConflictRules.ps1`, `Invoke-SoDScan.ps1` |
| fsi_sodviolation | `fsi_sodviolations` | `Invoke-SoDScan.ps1` |
| systemuser | `systemusers` | Dataverse security role collection expansion |
| role | `roles` via `systemuserroles_association` | Dataverse security role collection expansion |

## Deployment note

Create these Dataverse tables and choices with the exact SchemaNames and numeric choice values above. If you create choice columns manually in Power Apps, verify the generated numeric values before running `Import-ConflictRules.ps1`; mismatched values can cause imports and OData filters to evaluate incorrectly.

---

*Segregation of Duties Detector v1.2.1*
