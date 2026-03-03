# Session Security Configurator Dataverse Schema

## Overview

The Session Security Configurator uses three Dataverse tables to store session security baselines, validation history, and drift violations. This schema supports automated validation, immutable audit logging, and compliance reporting.

## Tables

### fsi_SessionBaseline

Stores zone-specific session security baseline configurations.

**Ownership:** User-owned  
**Purpose:** Configuration storage for expected session controls per governance zone

| Column | Type | Description |
|--------|------|-------------|
| fsi_sessionbaselineid | GUID | Primary key |
| fsi_name | String (200) | Baseline display name |
| fsi_zone | Option Set | Zone classification (fsi_acv_zone) |
| fsi_signinfrequencyminutes | Integer | Expected sign-in frequency in minutes |
| fsi_authstrength | String (200) | Expected authentication strength policy name |
| fsi_requirecompliantdevice | Boolean | Whether compliant device is required |
| fsi_pimmaxactivationhours | Integer | PIM maximum activation duration in hours |
| fsi_pimrequireapproval | Boolean | Whether PIM activation requires approval |
| fsi_pimrequireauthcontext | Boolean | Whether PIM activation requires auth context |
| fsi_isactive | Boolean | Whether this baseline is the current active configuration |
| fsi_capturedon | DateTime | Timestamp when baseline was captured |
| fsi_rawjson | Memo | Full JSON snapshot of CA session settings at capture time |
| createdby | Lookup (User) | User who created the record |
| createdon | DateTime | Record creation timestamp |
| modifiedby | Lookup (User) | User who last modified the record |
| modifiedon | DateTime | Last modification timestamp |

### fsi_ValidationHistory

Immutable audit log of all validation runs.

**Ownership:** Organization-owned  
**Purpose:** Regulatory audit trail — Write/Delete privileges removed post-deployment

| Column | Type | Description |
|--------|------|-------------|
| fsi_validationhistoryid | GUID | Primary key |
| fsi_name | String (200) | Validation display name |
| fsi_runid | String (36) | Unique identifier for the validation run |
| fsi_zone | Option Set | Zone validated (fsi_acv_zone) |
| fsi_severity | Option Set | Result severity (fsi_acv_severity) |
| fsi_validationtype | Option Set | Validation dimension (fsi_ssc_validationtype) |
| fsi_rawvalue | Memo (100000) | Actual config values checked (full JSON) |
| fsi_reason | String (4000) | Detailed result explanation |
| fsi_remediationhint | String (2000) | Suggested fix for alerting |
| fsi_timestamp | DateTime | Validation execution timestamp |
| fsi_checkcount | Integer | Number of individual checks |
| fsi_baselineid | String (200) | Reference to baseline used for comparison |
| createdby | Lookup (User) | System account that created the record |
| createdon | DateTime | Record creation timestamp |

### fsi_DriftViolation

Threshold violations requiring operator attention.

**Ownership:** User-owned  
**Purpose:** Alert management with acknowledgment and remediation workflow

| Column | Type | Description |
|--------|------|-------------|
| fsi_driftviolationid | GUID | Primary key |
| fsi_name | String (200) | Violation display name |
| fsi_zone | Option Set | Affected zone (fsi_acv_zone) |
| fsi_severity | Option Set | Violation severity (fsi_acv_severity) |
| fsi_drifttype | String (200) | Type of drift detected |
| fsi_expectedvalue | String (2000) | Baseline expected value |
| fsi_actualvalue | String (2000) | Actual observed value |
| fsi_policyid | String (200) | CA policy ID that drifted |
| fsi_policyname | String (500) | CA policy display name |
| fsi_detectedon | DateTime | When drift was detected |
| fsi_acknowledged | Boolean | Whether operator has reviewed |
| fsi_acknowledgedby | String (200) | UPN of operator who acknowledged |
| fsi_acknowledgedon | DateTime | When operator acknowledged the violation |
| fsi_notes | Memo (2000) | Operator notes on violation |
| createdby | Lookup (User) | User who created the record |
| createdon | DateTime | Record creation timestamp |

## Option Sets

### fsi_acv_zone (Shared with ACV)

Global option set for governance zone classification.

| Value | Label | Description |
|-------|-------|-------------|
| 100000000 | Unclassified | Zone not yet assigned |
| 100000001 | Zone 1 | Personal Productivity |
| 100000002 | Zone 2 | Team Collaboration |
| 100000003 | Zone 3 | Enterprise Managed |

### fsi_acv_severity (Shared with ACV)

Global option set for validation result severity.

| Value | Label | Description |
|-------|-------|-------------|
| 1 | Passed | Validation passed all checks |
| 2 | Warning | Minor issue detected, within tolerance |
| 3 | GracePeriod | Configuration in grace period |
| 4 | Failed | Validation failed threshold check |
| 5 | Error | Validation encountered an error |

### fsi_ssc_validationtype (SSC-specific)

Local option set for session security validation dimensions.

| Value | Label | Description |
|-------|-------|-------------|
| 1 | SessionControls | Sign-in frequency, persistent browser settings |
| 2 | AuthStrength | Authentication strength policy validation |
| 3 | PIMSettings | PIM activation window and approval settings |
| 4 | BreakGlass | Break-glass account exclusion verification |
| 5 | ConflictAudit | CA policy conflict detection |
| 6 | Orchestrator | Overall validation run coordination |

## Environment Variables

Configurable thresholds stored as Dataverse environment variables.

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| fsi_SSC_Zone1SignInFrequencyMinutes | Decimal | 480 | Zone 1 session limit (8 hours) |
| fsi_SSC_Zone2SignInFrequencyMinutes | Decimal | 240 | Zone 2 session limit (4 hours) |
| fsi_SSC_Zone3SignInFrequencyMinutes | Decimal | 60 | Zone 3 session limit (1 hour) |
| fsi_SSC_Zone1AuthStrength | String | standard | Zone 1 authentication strength |
| fsi_SSC_Zone2AuthStrength | String | Passwordless MFA | Zone 2 authentication strength |
| fsi_SSC_Zone3AuthStrength | String | Phishing-resistant MFA | Zone 3 authentication strength |

## Deployment

Deploy the schema using the provided deployment script:

```bash
# Navigate to scripts directory
cd scripts

# Deploy tables only
python deploy.py --environment-url https://org.crm.dynamics.com --tables-only

# Deploy environment variables only
python deploy.py --environment-url https://org.crm.dynamics.com --vars-only

# Full deployment (tables, option sets, environment variables)
python deploy.py --environment-url https://org.crm.dynamics.com
```

## Security Configuration

### ValidationHistory Immutability

After deployment, configure the security role for `fsi_ValidationHistory` to remove Write and Delete privileges for all roles except System Administrator. This configuration supports regulatory requirements for immutable audit trails.

**Steps:**

1. Navigate to Power Platform Admin Center > Environments > [Your Environment] > Settings
2. Open Security Roles
3. For each role except System Administrator:
   - Locate `fsi_ValidationHistory` entity
   - Remove Write and Delete privileges
   - Retain Read privilege for audit access

### Recommended Security Roles

| Role | SessionBaseline | ValidationHistory | DriftViolation |
|------|-----------------|-------------------|----------------|
| System Administrator | Full | Full | Full |
| SSC Operator | Read, Write | Read | Read, Write |
| Compliance Auditor | Read | Read | Read |
| Flow Service Account | Read | Create | Create, Write |

## Relationships

- **SessionBaseline** → Referenced by validation scripts for baseline comparison
- **ValidationHistory** → Written by validation flow, read by evidence export
- **DriftViolation** → Created when validation detects threshold breach

## Related Documentation

- [Prerequisites](PREREQUISITES.md) — Licensing and role requirements
- [Evidence Export Guide](EVIDENCE-EXPORT-GUIDE.md) — Exporting validation history
- [Flow Setup](FLOW_SETUP.md) — Automated daily validation
