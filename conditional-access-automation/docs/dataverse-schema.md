# Dataverse Schema Reference

> Auto-generated from `create_caa_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Ownership | Description | Primary Name Attribute |
|---|---|---|---|---|
| fsi_CAPolicyBaseline | fsi_capolicybaseline | UserOwned | Point-in-time snapshots of Conditional Access policy configurations for drift detection | fsi_policy_display_name |
| fsi_CAPolicyValidationHistory | fsi_capolicyvalidationhistory | OrganizationOwned | Immutable audit trail of compliance scan results — organization-owned to prevent individual record deletion | fsi_run_id |
| fsi_CAPolicyViolation | fsi_capolicyviolation | UserOwned | Individual policy-level violation records with resolution tracking and severity-based escalation | fsi_policy_display_name |

## Columns

### fsi_CAPolicyBaseline (`fsi_capolicybaseline`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Policy_Display_Name | fsi_policy_display_name | String | Yes | Primary name — CA policy display name |  |
| fsi_Policy_Id | fsi_policy_id | String | Yes | Entra ID object ID of the CA policy |  |
| fsi_Policy_State | fsi_policy_state | String | Yes | Policy state at capture time (enabled, disabled, enabledForReportingButNotEnforced) |  |
| fsi_Zone | fsi_zone | Picklist | Yes | Governance zone classification | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_Conditions_Json | fsi_conditions_json | Memo | Yes | Full conditions block (users, applications, locations, platforms, risk levels) |  |
| fsi_Grant_Controls_Json | fsi_grant_controls_json | Memo | Yes | Grant control requirements (MFA, compliant device, etc.) |  |
| fsi_Session_Controls_Json | fsi_session_controls_json | Memo | No | Session control settings (sign-in frequency, persistent browser, etc.) |  |
| fsi_Break_Glass_Exclusions | fsi_break_glass_exclusions | Memo | No | Emergency access account exclusions |  |
| fsi_Baseline_Hash | fsi_baseline_hash | String | Yes | SHA-256 hash of the serialized policy for fast drift comparison |  |
| fsi_Is_Active | fsi_is_active | Boolean | Yes | Whether this baseline is the current active snapshot | `1` = Yes, `0` = No |
| fsi_Captured_At | fsi_captured_at | DateTime | Yes | UTC timestamp when the baseline was captured |  |
| fsi_Captured_By | fsi_captured_by | String | Yes | Identity that captured the baseline (UPN or service principal) |  |
| fsi_Tenant_Id | fsi_tenant_id | String | Yes | Entra ID tenant GUID |  |

### fsi_CAPolicyValidationHistory (`fsi_capolicyvalidationhistory`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Run_Id | fsi_run_id | String | Yes | Primary name — unique identifier for each validation run |  |
| fsi_Validation_Time | fsi_validation_time | DateTime | Yes | UTC timestamp when the scan executed |  |
| fsi_Total_Policies | fsi_total_policies | Integer | Yes | Number of CA policies evaluated |  |
| fsi_Passed_Count | fsi_passed_count | Integer | Yes | Policies that met all requirements |  |
| fsi_Warning_Count | fsi_warning_count | Integer | Yes | Policies with non-critical findings |  |
| fsi_Failed_Count | fsi_failed_count | Integer | Yes | Policies that failed validation checks |  |
| fsi_Drift_Count | fsi_drift_count | Integer | Yes | Policies that drifted from baseline |  |
| fsi_Overall_Severity | fsi_overall_severity | Picklist | Yes | Worst severity across all evaluated policies | **fsi_acv_severity**: `100000000` = Passed, `100000001` = Warning, `100000002` = GracePeriod, `100000003` = Failed, `100000004` = Error |
| fsi_Results_Json | fsi_results_json | Memo | Yes | Full scan results array with per-policy detail |  |
| fsi_Validated_By | fsi_validated_by | String | Yes | Identity that executed the scan |  |
| fsi_Tenant_Id | fsi_tenant_id | String | Yes | Entra ID tenant GUID |  |

### fsi_CAPolicyViolation (`fsi_capolicyviolation`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Policy_Display_Name | fsi_policy_display_name | String | Yes | Primary name — CA policy that triggered the violation |  |
| fsi_Run_Id | fsi_run_id | String | Yes | Validation run that detected the violation |  |
| fsi_Policy_Id | fsi_policy_id | String | Yes | Entra ID object ID of the violating policy |  |
| fsi_Violation_Type | fsi_violation_type | String | Yes | Category (e.g., state_drift, condition_change, grant_mismatch, policy_removed) |  |
| fsi_Zone | fsi_zone | Picklist | Yes | Governance zone of the affected policy | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_Severity | fsi_severity | Picklist | Yes | Severity level of the violation | **fsi_acv_severity**: `100000000` = Passed, `100000001` = Warning, `100000002` = GracePeriod, `100000003` = Failed, `100000004` = Error |
| fsi_Expected_Value | fsi_expected_value | Memo | No | Baseline value that was expected |  |
| fsi_Actual_Value | fsi_actual_value | Memo | No | Current value that differs from baseline |  |
| fsi_Description | fsi_description | Memo | No | Human-readable explanation of the violation |  |
| fsi_Is_Resolved | fsi_is_resolved | Boolean | Yes | Whether the violation has been addressed | `1` = Yes, `0` = No |
| fsi_Resolved_At | fsi_resolved_at | DateTime | No | UTC timestamp when the violation was resolved |  |
| fsi_Resolved_By | fsi_resolved_by | String | No | Identity that resolved the violation |  |
| fsi_Detected_At | fsi_detected_at | DateTime | Yes | UTC timestamp when the violation was detected |  |
| fsi_Tenant_Id | fsi_tenant_id | String | Yes | Entra ID tenant GUID |  |

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
