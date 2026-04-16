# Dataverse Schema Reference

Complete schema reference for the Conditional Access Automation Dataverse solution. This schema supports compliance evidence persistence, policy drift detection, and audit-ready reporting for FINRA/SEC examination readiness.

## Tables Overview

The solution deploys three Dataverse tables under the `fsi_` publisher prefix:

| Table | Entity Set Name | Ownership | Purpose |
|-------|----------------|-----------|---------|
| `fsi_CAPolicyBaseline` | `fsi_capolicybaselines` | UserOwned | CA policy configuration snapshots for drift comparison |
| `fsi_CAPolicyValidationHistory` | `fsi_capolicyvalidationhistories` | OrganizationOwned | Immutable audit trail of compliance scan results |
| `fsi_CAPolicyViolation` | `fsi_capolicyviolations` | UserOwned | Individual policy-level violation records |

---

## Table: fsi_CAPolicyBaseline

Stores point-in-time snapshots of Conditional Access policy configurations. Used as the reference for drift detection — any change between a live policy and its baseline triggers a violation record.

| Column | Schema Name | Type | Required | Description |
|--------|------------|------|----------|-------------|
| Policy Display Name | `fsi_policy_display_name` | String (256) | Yes | Primary name — CA policy display name |
| Policy ID | `fsi_policy_id` | String (100) | Yes | Entra ID object ID of the CA policy |
| Policy State | `fsi_policy_state` | String (50) | Yes | Policy state at capture time (enabled, disabled, enabledForReportingButNotEnforced) |
| Zone | `fsi_zone` | Picklist (`fsi_acv_zone`) | Yes | Governance zone classification |
| Conditions JSON | `fsi_conditions_json` | Memo | Yes | Full conditions block (users, applications, locations, platforms, risk levels) |
| Grant Controls JSON | `fsi_grant_controls_json` | Memo | Yes | Grant control requirements (MFA, compliant device, etc.) |
| Session Controls JSON | `fsi_session_controls_json` | Memo | No | Session control settings (sign-in frequency, persistent browser, etc.) |
| Break Glass Exclusions | `fsi_break_glass_exclusions` | Memo | No | Emergency access account exclusions |
| Baseline Hash | `fsi_baseline_hash` | String (64) | Yes | SHA-256 hash of the serialized policy for fast drift comparison |
| Is Active | `fsi_is_active` | Boolean | Yes | Whether this baseline is the current active snapshot (default: No) |
| Captured At | `fsi_captured_at` | DateTime | Yes | UTC timestamp when the baseline was captured |
| Captured By | `fsi_captured_by` | String (256) | Yes | Identity that captured the baseline (UPN or service principal) |
| Tenant ID | `fsi_tenant_id` | String (50) | Yes | Entra ID tenant GUID |

---

## Table: fsi_CAPolicyValidationHistory

Immutable audit trail of compliance scan results. Organization-owned to prevent individual record deletion — records are write-once and support regulatory evidence retention.

| Column | Schema Name | Type | Required | Description |
|--------|------------|------|----------|-------------|
| Run ID | `fsi_run_id` | String (50) | Yes | Primary name — unique identifier for each validation run |
| Validation Time | `fsi_validation_time` | DateTime | Yes | UTC timestamp when the scan executed |
| Total Policies | `fsi_total_policies` | Integer | Yes | Number of CA policies evaluated |
| Passed Count | `fsi_passed_count` | Integer | Yes | Policies that met all requirements |
| Warning Count | `fsi_warning_count` | Integer | Yes | Policies with non-critical findings |
| Failed Count | `fsi_failed_count` | Integer | Yes | Policies that failed validation checks |
| Drift Count | `fsi_drift_count` | Integer | Yes | Policies that drifted from baseline |
| Overall Severity | `fsi_overall_severity` | Picklist (`fsi_acv_severity`) | Yes | Worst severity across all evaluated policies |
| Results JSON | `fsi_results_json` | Memo | Yes | Full scan results array with per-policy detail |
| Validated By | `fsi_validated_by` | String (256) | Yes | Identity that executed the scan |
| Tenant ID | `fsi_tenant_id` | String (50) | Yes | Entra ID tenant GUID |

---

## Table: fsi_CAPolicyViolation

Individual policy-level violation records created when a CA policy fails validation or drifts from its baseline. Supports resolution tracking and severity-based escalation.

| Column | Schema Name | Type | Required | Description |
|--------|------------|------|----------|-------------|
| Policy Display Name | `fsi_policy_display_name` | String (256) | Yes | Primary name — CA policy that triggered the violation |
| Run ID | `fsi_run_id` | String (50) | Yes | Validation run that detected the violation |
| Policy ID | `fsi_policy_id` | String (100) | Yes | Entra ID object ID of the violating policy |
| Violation Type | `fsi_violation_type` | String (100) | Yes | Category (e.g., state_drift, condition_change, grant_mismatch, policy_removed) |
| Zone | `fsi_zone` | Picklist (`fsi_acv_zone`) | Yes | Governance zone of the affected policy |
| Severity | `fsi_severity` | Picklist (`fsi_acv_severity`) | Yes | Severity level of the violation |
| Expected Value | `fsi_expected_value` | Memo | No | Baseline value that was expected |
| Actual Value | `fsi_actual_value` | Memo | No | Current value that differs from baseline |
| Description | `fsi_description` | Memo | No | Human-readable explanation of the violation |
| Is Resolved | `fsi_is_resolved` | Boolean | Yes | Whether the violation has been addressed (default: No) |
| Resolved At | `fsi_resolved_at` | DateTime | No | UTC timestamp when the violation was resolved |
| Resolved By | `fsi_resolved_by` | String (256) | No | Identity that resolved the violation |
| Detected At | `fsi_detected_at` | DateTime | Yes | UTC timestamp when the violation was detected |
| Tenant ID | `fsi_tenant_id` | String (50) | Yes | Entra ID tenant GUID |

---

## Shared Option Sets

Two global option sets are reused across all three tables:

### fsi_acv_zone — Governance Zone

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Unclassified | Policy not yet assigned to a governance zone |
| 1 | Zone 1 | Personal Productivity — risk-based MFA, standard controls |
| 2 | Zone 2 | Team Collaboration — always-on MFA, enhanced controls |
| 3 | Zone 3 | Enterprise Managed — MFA + compliant device, strictest controls |

### fsi_acv_severity — Validation Severity

| Value | Label | Description |
|-------|-------|-------------|
| 1 | Passed | Policy meets all requirements |
| 2 | Warning | Non-critical finding — review recommended |
| 3 | GracePeriod | Policy recently deployed — within grace window (default 48 hours) |
| 4 | Failed | Policy does not meet zone requirements |
| 5 | Error | Scan could not evaluate the policy (connectivity, permissions, etc.) |

---

## Environment Variables

Sixteen environment variables control runtime behavior. All use the `fsi_CAA_*` prefix.

| Schema Name | Display Name | Type | Default | Purpose |
|-------------|-------------|------|---------|---------|
| `fsi_CAA_GracePeriodHours` | CAA - Grace Period (Hours) | Decimal | `48` | Hours before newly deployed policies are included in validation |
| `fsi_CAA_ScanFrequencyHours` | CAA - Scan Frequency (Hours) | Decimal | `24` | Automated compliance scan interval for the daily flow |
| `fsi_CAA_BaselineMaxAgeDays` | CAA - Maximum Baseline Age (Days) | Decimal | `30` | Alert threshold for stale baselines requiring refresh |
| `fsi_CAA_DriftSeverityEscalation` | CAA - Drift Severity Escalation | String | `true` | Whether Zone 3 drift violations receive severity +1 |
| `fsi_CAA_IncludeReportOnlyPolicies` | CAA - Include Report-Only Policies | String | `true` | Whether report-only CA policies are included in validation scans |
| `fsi_CAA_TeamsGroupId` | CAA - Teams Alert Group ID | String | *(empty)* | Microsoft Teams group GUID for violation alert delivery |
| `fsi_CAA_TeamsChannelId` | CAA - Teams Alert Channel ID | String | *(empty)* | Microsoft Teams channel GUID for violation alert delivery |
| `fsi_CAA_ComplianceDistributionList` | CAA - Compliance Distribution List | String | *(empty)* | Email distribution list for compliance alert routing |
| `fsi_CAA_DocsBaseUrl` | CAA - Documentation Base URL | String | *(empty)* | Documentation site root URL for adaptive card links |
| `fsi_CAA_SubscriptionId` | CAA - Azure Subscription ID | String | *(empty)* | Azure subscription GUID containing the Automation Account |
| `fsi_CAA_ResourceGroup` | CAA - Resource Group | String | *(empty)* | Azure resource group containing the Automation Account |
| `fsi_CAA_AutomationAccount` | CAA - Automation Account | String | *(empty)* | Azure Automation account name for validation runbook execution |
| `fsi_CAA_EntraPortalUrl` | CAA - Entra Portal URL | String | `https://entra.microsoft.com` | Entra admin center base URL (override for sovereign clouds, e.g., `https://entra.microsoft.us` for GCC High) |
| `fsi_CAA_AzurePortalUrl` | CAA - Azure Portal URL | String | `https://portal.azure.com` | Azure portal base URL (override for sovereign clouds, e.g., `https://portal.azure.us` for GCC High) |
| `fsi_CAA_PowerPlatformAdminUrl` | CAA - Power Platform Admin URL | String | `https://admin.powerplatform.microsoft.com` | Power Platform admin center base URL (override for sovereign clouds) |
| `fsi_CAA_DataverseUrl` | CAA - Dataverse URL | String | *(empty)* | Dataverse environment URL (e.g., `https://org.crm.dynamics.com`) |

---

## Connection References

Three connection references enable Power Automate flows to interact with platform services. All use the `fsi_cr_*` naming convention.

| Logical Name | Display Name | Connector | Purpose |
|-------------|-------------|-----------|---------|
| `fsi_cr_dataverse_conditionalaccessautomation` | Dataverse - Conditional Access Automation | `shared_commondataserviceforapps` | Table CRUD for baselines, history, violations |
| `fsi_cr_office365_conditionalaccessautomation` | Office 365 - Conditional Access Automation | `shared_office365` | Email notification delivery |
| `fsi_cr_teams_conditionalaccessautomation` | Teams - Conditional Access Automation | `shared_teams` | Adaptive card alert delivery |

> **Note:** A Microsoft Graph connection reference (`fsi_cr_graph_conditionalaccessautomation`) is planned for future phases to enable direct CA policy reads from Power Automate flows. Current flows authenticate via HTTP actions with Managed Service Identity.

---

## Table Relationships

```
┌──────────────────────────────────────────┐
│     fsi_CAPolicyValidationHistory        │
│                                          │
│  fsi_run_id (PK)                         │
│  fsi_results_json → per-policy detail    │
│  fsi_overall_severity                    │
│                                          │
│  Ownership: OrganizationOwned (immutable)│
└────────────────┬─────────────────────────┘
                 │ fsi_run_id
                 ▼
┌──────────────────────────────────────────┐
│        fsi_CAPolicyViolation             │
│                                          │
│  fsi_policy_display_name (PK)            │
│  fsi_run_id → links to validation run    │
│  fsi_policy_id → links to baseline       │
│  fsi_violation_type (drift category)     │
│  fsi_expected_value / fsi_actual_value   │
│                                          │
│  Ownership: UserOwned                    │
└────────────────┬─────────────────────────┘
                 │ fsi_policy_id
                 ▼
┌──────────────────────────────────────────┐
│        fsi_CAPolicyBaseline              │
│                                          │
│  fsi_policy_display_name (PK)            │
│  fsi_policy_id (unique per active snap)  │
│  fsi_conditions_json                     │
│  fsi_grant_controls_json                 │
│  fsi_baseline_hash (SHA-256 for drift)   │
│  fsi_is_active                           │
│                                          │
│  Ownership: UserOwned                    │
└──────────────────────────────────────────┘
```

The `fsi_run_id` column on `fsi_CAPolicyViolation` logically references the validation run that detected the violation. The `fsi_policy_id` column references the Entra ID policy, which can be correlated with a `fsi_CAPolicyBaseline` record by matching on `fsi_policy_id + fsi_is_active = true`.

---

## Deployment

Deploy the schema using the Dataverse Web API or Power Platform admin center via the deployment scripts (`create_caa_dataverse_schema.py`, `create_caa_environment_variables.py`, `create_caa_connection_references.py`).

Manual deployment steps:

1. Create the three tables (`fsi_CAPolicyBaseline`, `fsi_CAPolicyValidationHistory`, `fsi_CAPolicyViolation`) with the columns defined above
2. Create the two shared option sets (`fsi_acv_zone`, `fsi_acv_severity`)
3. Create the sixteen environment variables with `fsi_CAA_*` prefix
4. Create the three connection references with `fsi_cr_*` naming

---

*Schema Version: 1.2.1 | Publisher Prefix: fsi_ | Last Updated: April 2026*
