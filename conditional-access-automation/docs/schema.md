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
| Policy Display Name | `fsi_policydisplayname` | String (256) | Yes | Primary name — CA policy display name |
| Policy ID | `fsi_policyid` | String (100) | Yes | Entra ID object ID of the CA policy |
| Policy State | `fsi_policystate` | String (50) | Yes | Policy state at capture time (enabled, disabled, enabledForReportingButNotEnforced) |
| Zone | `fsi_zone` | Picklist (`fsi_acv_zone`) | Yes | Governance zone classification |
| Conditions JSON | `fsi_conditionsjson` | Memo | Yes | Full conditions block (users, applications, locations, platforms, risk levels) |
| Grant Controls JSON | `fsi_grantcontrolsjson` | Memo | Yes | Grant control requirements (MFA, compliant device, etc.) |
| Session Controls JSON | `fsi_sessioncontrolsjson` | Memo | No | Session control settings (sign-in frequency, persistent browser, etc.) |
| Break Glass Exclusions | `fsi_breakglassexclusions` | Memo | No | Emergency access account exclusions |
| Baseline Hash | `fsi_baselinehash` | String (64) | Yes | SHA-256 hash of the serialized policy for fast drift comparison |
| Is Active | `fsi_isactive` | Boolean | Yes | Whether this baseline is the current active snapshot (default: No) |
| Captured At | `fsi_capturedat` | DateTime | Yes | UTC timestamp when the baseline was captured |
| Captured By | `fsi_capturedby` | String (256) | Yes | Identity that captured the baseline (UPN or service principal) |
| Tenant ID | `fsi_tenantid` | String (50) | Yes | Entra ID tenant GUID |

---

## Table: fsi_CAPolicyValidationHistory

Immutable audit trail of compliance scan results. Organization-owned to prevent individual record deletion — records are write-once and support regulatory evidence retention.

| Column | Schema Name | Type | Required | Description |
|--------|------------|------|----------|-------------|
| Run ID | `fsi_runid` | String (50) | Yes | Primary name — unique identifier for each validation run |
| Validation Time | `fsi_validationtime` | DateTime | Yes | UTC timestamp when the scan executed |
| Total Policies | `fsi_totalpolicies` | Integer | Yes | Number of CA policies evaluated |
| Passed Count | `fsi_passedcount` | Integer | Yes | Policies that met all requirements |
| Warning Count | `fsi_warningcount` | Integer | Yes | Policies with non-critical findings |
| Failed Count | `fsi_failedcount` | Integer | Yes | Policies that failed validation checks |
| Drift Count | `fsi_driftcount` | Integer | Yes | Policies that drifted from baseline |
| Overall Severity | `fsi_overallseverity` | Picklist (`fsi_acv_severity`) | Yes | Worst severity across all evaluated policies |
| Results JSON | `fsi_resultsjson` | Memo | Yes | Full scan results array with per-policy detail |
| Validated By | `fsi_validatedby` | String (256) | Yes | Identity that executed the scan |
| Tenant ID | `fsi_tenantid` | String (50) | Yes | Entra ID tenant GUID |

---

## Table: fsi_CAPolicyViolation

Individual policy-level violation records created when a CA policy fails validation or drifts from its baseline. Supports resolution tracking and severity-based escalation.

| Column | Schema Name | Type | Required | Description |
|--------|------------|------|----------|-------------|
| Policy Display Name | `fsi_policydisplayname` | String (256) | Yes | Primary name — CA policy that triggered the violation |
| Run ID | `fsi_runid` | String (50) | Yes | Validation run that detected the violation |
| Policy ID | `fsi_policyid` | String (100) | Yes | Entra ID object ID of the violating policy |
| Violation Type | `fsi_violationtype` | String (100) | Yes | Category (e.g., state_drift, condition_change, grant_mismatch, policy_removed) |
| Zone | `fsi_zone` | Picklist (`fsi_acv_zone`) | Yes | Governance zone of the affected policy |
| Severity | `fsi_severity` | Picklist (`fsi_acv_severity`) | Yes | Severity level of the violation |
| Expected Value | `fsi_expectedvalue` | Memo | No | Baseline value that was expected |
| Actual Value | `fsi_actualvalue` | Memo | No | Current value that differs from baseline |
| Description | `fsi_description` | Memo | No | Human-readable explanation of the violation |
| Is Resolved | `fsi_isresolved` | Boolean | Yes | Whether the violation has been addressed (default: No) |
| Resolved At | `fsi_resolvedat` | DateTime | No | UTC timestamp when the violation was resolved |
| Resolved By | `fsi_resolvedby` | String (256) | No | Identity that resolved the violation |
| Detected At | `fsi_detectedat` | DateTime | Yes | UTC timestamp when the violation was detected |
| Tenant ID | `fsi_tenantid` | String (50) | Yes | Entra ID tenant GUID |

---

## Shared Option Sets

Two global option sets are reused across all three tables:

### fsi_acv_zone — Governance Zone

| Value | Label | Description |
|-------|-------|-------------|
| 100000000 | Unclassified | Policy not yet assigned to a governance zone |
| 100000001 | Zone 1 | Personal Productivity — risk-based MFA, standard controls |
| 100000002 | Zone 2 | Team Collaboration — always-on MFA, enhanced controls |
| 100000003 | Zone 3 | Enterprise Managed — MFA + compliant device, strictest controls |

### fsi_acv_severity — Validation Severity

| Value | Label | Description |
|-------|-------|-------------|
| 100000000 | Passed | Policy meets all requirements |
| 100000001 | Warning | Non-critical finding — review recommended |
| 100000002 | GracePeriod | Policy recently deployed — within grace window (default 48 hours) |
| 100000003 | Failed | Policy does not meet zone requirements |
| 100000004 | Error | Scan could not evaluate the policy (connectivity, permissions, etc.) |

> Dataverse global option sets always use values ≥ 100,000,000. The integer
> values shown above are what `$select` / `$filter` queries return on the bare
> `fsi_overallseverity` and `fsi_zone` columns; the human label is on the
> `…@OData.Community.Display.V1.FormattedValue` annotation when the request
> sets `Prefer: odata.include-annotations="OData.Community.Display.V1.FormattedValue"`.

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
│  fsi_runid (PK)                         │
│  fsi_resultsjson → per-policy detail    │
│  fsi_overallseverity                    │
│                                          │
│  Ownership: OrganizationOwned (immutable)│
└────────────────┬─────────────────────────┘
                 │ fsi_runid
                 ▼
┌──────────────────────────────────────────┐
│        fsi_CAPolicyViolation             │
│                                          │
│  fsi_policydisplayname (PK)            │
│  fsi_runid → links to validation run    │
│  fsi_policyid → links to baseline       │
│  fsi_violationtype (drift category)     │
│  fsi_expectedvalue / fsi_actualvalue   │
│                                          │
│  Ownership: UserOwned                    │
└────────────────┬─────────────────────────┘
                 │ fsi_policyid
                 ▼
┌──────────────────────────────────────────┐
│        fsi_CAPolicyBaseline              │
│                                          │
│  fsi_policydisplayname (PK)            │
│  fsi_policyid (unique per active snap)  │
│  fsi_conditionsjson                     │
│  fsi_grantcontrolsjson                 │
│  fsi_baselinehash (SHA-256 for drift)   │
│  fsi_isactive                           │
│                                          │
│  Ownership: UserOwned                    │
└──────────────────────────────────────────┘
```

The `fsi_runid` column on `fsi_CAPolicyViolation` logically references the validation run that detected the violation. The `fsi_policyid` column references the Entra ID policy, which can be correlated with a `fsi_CAPolicyBaseline` record by matching on `fsi_policyid + fsi_isactive = true`.

---

## Deployment

Deploy the schema using the Dataverse Web API or Power Platform admin center via the deployment scripts (`create_caa_dataverse_schema.py`, `create_caa_environment_variables.py`, `create_caa_connection_references.py`).

Manual deployment steps:

1. Create the three tables (`fsi_CAPolicyBaseline`, `fsi_CAPolicyValidationHistory`, `fsi_CAPolicyViolation`) with the columns defined above
2. Create the two shared option sets (`fsi_acv_zone`, `fsi_acv_severity`)
3. Create the sixteen environment variables with `fsi_CAA_*` prefix
4. Create the three connection references with `fsi_cr_*` naming

---

*Schema Version: 1.2.2 | Publisher Prefix: fsi_ | Last Updated: April 2026*
