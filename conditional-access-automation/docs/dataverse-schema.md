# Dataverse Schema Reference

> Auto-generated from `create_caa_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Ownership | Description | Primary Name Attribute |
|---|---|---|---|---|
| fsi_CAPolicyBaseline | fsi_capolicybaseline | UserOwned | Point-in-time snapshots of Conditional Access policy configurations for drift detection | fsi_policydisplayname |
| fsi_CAPolicyValidationHistory | fsi_capolicyvalidationhistory | OrganizationOwned | Immutable audit trail of compliance scan results — organization-owned to prevent individual record deletion | fsi_runid |
| fsi_CAPolicyViolation | fsi_capolicyviolation | UserOwned | Individual policy-level violation records with resolution tracking and severity-based escalation | fsi_policydisplayname |

## Columns

### fsi_CAPolicyBaseline (`fsi_capolicybaseline`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_PolicyDisplayName | fsi_policydisplayname | String | Yes | Primary name — CA policy display name |  |
| fsi_PolicyId | fsi_policyid | String | Yes | Entra ID object ID of the CA policy |  |
| fsi_PolicyState | fsi_policystate | String | Yes | Policy state at capture time (enabled, disabled, enabledForReportingButNotEnforced) |  |
| fsi_Zone | fsi_zone | Picklist | Yes | Governance zone classification | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_ConditionsJson | fsi_conditionsjson | Memo | Yes | Full conditions block (users, applications, locations, platforms, risk levels) |  |
| fsi_GrantControlsJson | fsi_grantcontrolsjson | Memo | Yes | Grant control requirements (MFA, compliant device, etc.) |  |
| fsi_SessionControlsJson | fsi_sessioncontrolsjson | Memo | No | Session control settings (sign-in frequency, persistent browser, etc.) |  |
| fsi_BreakGlassExclusions | fsi_breakglassexclusions | Memo | No | Emergency access account exclusions |  |
| fsi_BaselineHash | fsi_baselinehash | String | Yes | SHA-256 hash of the serialized policy for fast drift comparison |  |
| fsi_IsActive | fsi_isactive | Boolean | Yes | Whether this baseline is the current active snapshot | `1` = Yes, `0` = No |
| fsi_CapturedAt | fsi_capturedat | DateTime | Yes | UTC timestamp when the baseline was captured |  |
| fsi_CapturedBy | fsi_capturedby | String | Yes | Identity that captured the baseline (UPN or service principal) |  |
| fsi_TenantId | fsi_tenantid | String | Yes | Entra ID tenant GUID |  |

### fsi_CAPolicyValidationHistory (`fsi_capolicyvalidationhistory`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_RunId | fsi_runid | String | Yes | Primary name — unique identifier for each validation run |  |
| fsi_ValidationTime | fsi_validationtime | DateTime | Yes | UTC timestamp when the scan executed |  |
| fsi_TotalPolicies | fsi_totalpolicies | Integer | Yes | Number of CA policies evaluated |  |
| fsi_PassedCount | fsi_passedcount | Integer | Yes | Policies that met all requirements |  |
| fsi_WarningCount | fsi_warningcount | Integer | Yes | Policies with non-critical findings |  |
| fsi_FailedCount | fsi_failedcount | Integer | Yes | Policies that failed validation checks |  |
| fsi_DriftCount | fsi_driftcount | Integer | Yes | Policies that drifted from baseline |  |
| fsi_OverallSeverity | fsi_overallseverity | Picklist | Yes | Worst severity across all evaluated policies | **fsi_acv_severity**: `100000000` = Passed, `100000001` = Warning, `100000002` = GracePeriod, `100000003` = Failed, `100000004` = Error |
| fsi_ResultsJson | fsi_resultsjson | Memo | Yes | Full scan results array with per-policy detail |  |
| fsi_ValidatedBy | fsi_validatedby | String | Yes | Identity that executed the scan |  |
| fsi_TenantId | fsi_tenantid | String | Yes | Entra ID tenant GUID |  |

### fsi_CAPolicyViolation (`fsi_capolicyviolation`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_PolicyDisplayName | fsi_policydisplayname | String | Yes | Primary name — CA policy that triggered the violation |  |
| fsi_RunId | fsi_runid | String | Yes | Validation run that detected the violation |  |
| fsi_PolicyId | fsi_policyid | String | Yes | Entra ID object ID of the violating policy |  |
| fsi_ViolationType | fsi_violationtype | String | Yes | Category (e.g., state_drift, condition_change, grant_mismatch, policy_removed) |  |
| fsi_Zone | fsi_zone | Picklist | Yes | Governance zone of the affected policy | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_Severity | fsi_severity | Picklist | Yes | Severity level of the violation | **fsi_acv_severity**: `100000000` = Passed, `100000001` = Warning, `100000002` = GracePeriod, `100000003` = Failed, `100000004` = Error |
| fsi_ExpectedValue | fsi_expectedvalue | Memo | No | Baseline value that was expected |  |
| fsi_ActualValue | fsi_actualvalue | Memo | No | Current value that differs from baseline |  |
| fsi_Description | fsi_description | Memo | No | Human-readable explanation of the violation |  |
| fsi_IsResolved | fsi_isresolved | Boolean | Yes | Whether the violation has been addressed | `1` = Yes, `0` = No |
| fsi_ResolvedAt | fsi_resolvedat | DateTime | No | UTC timestamp when the violation was resolved |  |
| fsi_ResolvedBy | fsi_resolvedby | String | No | Identity that resolved the violation |  |
| fsi_DetectedAt | fsi_detectedat | DateTime | Yes | UTC timestamp when the violation was detected |  |
| fsi_TenantId | fsi_tenantid | String | Yes | Entra ID tenant GUID |  |

## Option Sets

### Shared Option Sets

#### fsi_acv_zone

Governance zone classification

| Value | Label |
|---|---|
| 100000000 | Unclassified |
| 100000001 | Zone 1 |
| 100000002 | Zone 2 |
| 100000003 | Zone 3 |

### CAA Option Sets

#### fsi_acv_severity

Severity level for CA policy validation results

| Value | Label |
|---|---|
| 100000000 | Passed |
| 100000001 | Warning |
| 100000002 | GracePeriod |
| 100000003 | Failed |
| 100000004 | Error |
