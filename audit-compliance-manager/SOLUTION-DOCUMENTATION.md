# Automating Audit Logging Compliance for AI Agent Environments
## Audit Compliance Manager (ACM) — ALCA + ACV

**Version:** 1.0.2
**Solution Type:** Automated Detection and Remediation
**Platform:** Azure Automation + Power Platform with Dataverse

---

## Executive Summary

### Problem Statement

Audit logs are essential for tracking security-relevant events such as logins/logouts, configuration changes, and API token modifications in AI agent environments. However, many Power Platform environments are deployed without audit logging enabled, creating significant compliance gaps and security blind spots. Manual audit configuration across dozens or hundreds of environments is error-prone, time-consuming, and difficult to maintain.

**Risk Exposure:**
- **Compliance Violations:** Failure to maintain audit logs violates regulatory requirements (FINRA 4511, SEC 17a-3/17a-4, SOX 404)
- **Security Blind Spots:** Inability to detect unauthorized access, configuration tampering, or data exfiltration
- **Incident Response Gaps:** No forensic trail for security investigations or breach analysis
- **Regulatory Examination Failures:** Missing audit evidence during examinations results in findings and penalties
- **Scope Drift Undetected:** Changes to AI agent capabilities without governance oversight

### Solution Overview

The **Audit Logging Compliance Automation (ALCA)** solution provides enterprise-grade automated detection and remediation of audit logging gaps across Microsoft 365 and Power Platform environments. The solution leverages Azure Automation with Managed Identity authentication to scan all environments, identify non-compliant configurations, and automatically enable audit logging with approval workflows.

**Key Capabilities:**
- **Automated Detection:** Continuous scanning of Purview unified audit and Dataverse audit status across all environments
- **Intelligent Remediation:** Automated enablement of org-level and entity-level Dataverse auditing for non-compliant environments
- **Approval Workflows:** Governance-approved remediation via Power Automate with business justification
- **Entity-Level Audit:** Automatic enablement for 6 Copilot Studio entities (bot, botcomponent, workflow, etc.)
- **Compliance Tracking:** Upsert-based Dataverse table with current compliance status per environment
- **Email Notifications:** HTML notifications with CSV attachments showing compliance summary

**Business Value:**
- Reduce manual audit configuration overhead (95%+ time savings)
- Help maintain continuous audit coverage across all Power Platform environments
- Support regulatory examinations with automated compliance evidence
- Detect and remediate audit gaps within 24 hours (or faster with daily scheduling)
- Enable security incident response with comprehensive audit trails

---

## Technical Details

### Architecture Overview

ALCA operates as two Azure Automation runbooks (detection and remediation) with a shared PowerShell helper module. The architecture follows a scan-detect-remediate pattern with Managed Identity authentication and approval-gated remediation.

```
┌─────────────────────────────────────────────────────────────────────┐
│          Audit Logging Compliance Automation (ALCA)                  │
│    Azure Automation with System-Assigned Managed Identity            │
└─────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────────┐     ┌──────────────────┐      ┌──────────────────┐
│  Helper Module    │     │   Detection      │      │   Remediation    │
│  (Shared)         │────▶│   Runbook        │      │   Runbook        │
│                   │     │  (Weekly/Daily)  │      │  (On-Demand/     │
│ - MI Auth         │     │                  │      │   Approval)      │
│ - Retry Logic    │     │  1. Enumerate    │      │                  │
│ - Dataverse API  │     │     Environments │      │  1. Query Non-   │
│ - Email Send     │     │  2. Check Purview│      │     Compliant    │
└───────────────────┘     │     Unified Audit│      │     Environments │
                          │  3. Check        │      │  2. Enable       │
                          │     Dataverse    │      │     Purview      │
                          │     Audit        │      │     Unified      │
                          │  4. Validate     │      │     Audit        │
                          │     Recent Events│      │  3. Enable       │
                          │  5. Write to     │      │     Dataverse    │
                          │     Dataverse    │      │     Org Audit    │
                          │  6. Send Email   │      │  4. Enable       │
                          │     (if issues)  │      │     Entity Audit │
                          └────────┬─────────┘      │  5. Validate     │
                                   │                │  6. Update       │
                                   ▼                │     Dataverse    │
                    ┌──────────────────────────┐    └────────┬─────────┘
                    │  Dataverse Table         │             │
                    │  fsi_auditenvironment    │◀────────────┘
                    │  compliance              │
                    │                          │
                    │  - Environment ID (key)  │
                    │  - Compliance Status     │
                    │  - Audit Enabled         │
                    │  - Last Checked          │
                    │  - Remediation Date      │
                    └──────────┬───────────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
        ▼                      ▼                      ▼
┌───────────────┐    ┌─────────────────┐   ┌─────────────────┐
│  HTML Email   │    │  Power Automate │   │  Compliance     │
│  Notification │    │  Approval Flow  │   │  Reports        │
│  (CSV)        │    │  (Optional)     │   │  (Evidence)     │
└───────────────┘    └─────────────────┘   └─────────────────┘
```

### Solution Components

#### 1. Helper Module — AuditComplianceHelpers.psm1
**File:** `scripts/AuditComplianceHelpers.psm1`

**Purpose:** Shared PowerShell module providing reusable functions for authentication, retry logic, Dataverse operations, and email notifications.

**Functions:**

| Function Name | Purpose | Key Features |
|---------------|---------|--------------|
| `Invoke-WithRetry` | Retry wrapper with exponential backoff | Handles 429/503/504, jitter randomization, max 5 retries |
| `Get-ManagedIdentityToken` | Acquire MI token for any resource | Azure Automation MI endpoint, resource validation |
| `Get-DataverseToken` | Dataverse-specific token acquisition | URL normalization, automatic resource resolution |
| `Invoke-DataverseRequest` | Dataverse Web API wrapper | OData headers, retry logic, error handling |
| `Write-DataverseComplianceRecord` | Upsert compliance record | Upsert by environment ID, option set mapping |
| `Send-ComplianceNotification` | Send email via Graph sendMail | Shared mailbox support, CSV attachments, HTML body |

**Module Manifest:** `scripts/AuditComplianceHelpers.psd1`
- Version: 1.0.2
- PowerShell Version: 7.2+
- Exported Functions: 6 functions listed above

**Unit Tests:** `scripts/AuditComplianceHelpers.Tests.ps1`
- Pester 5 test suite with 15+ test scenarios
- Mock-based testing for MI authentication
- Retry logic validation with simulated failures

#### 2. Detection Runbook — Test-AuditLoggingCompliance.ps1
**File:** `scripts/Test-AuditLoggingCompliance.ps1`

**Purpose:** Azure Automation runbook that scans all Power Platform environments for audit logging compliance and writes results to Dataverse.

**Detection Logic:**

| Environment Type | Compliance Requirements | Validation |
|------------------|------------------------|------------|
| **Dataverse environments** | Microsoft Purview unified audit enabled AND Dataverse org-level audit enabled | Verifies tenant audit configuration and records recent audit event presence as informational evidence |
| **Non-Dataverse environments** | Purview unified audit enabled only | Validates unified audit log accessibility |

**Process Flow:**

1. **Authentication (Managed Identity):**
   - Acquire token for Power Platform API (`https://api.bap.microsoft.com/`)
   - Connect to Exchange Online via Managed Identity
   - Acquire Dataverse token for compliance table writes

2. **Environment Enumeration:**
   - Call `Get-AdminPowerAppEnvironment` to retrieve all environments
   - Extract environment ID, display name, Dataverse URL (if applicable)

3. **Per-Environment Compliance Check:**
   - **Check Purview Unified Audit:**
     - Query `Get-AdminAuditLogConfig` for tenant-level audit status
     - Validate `UnifiedAuditLogIngestionEnabled = true`
     - Optionally query recent audit events (last 7 days) as informational evidence; absence of recent events is not a compliance gate by itself
   - **Check Dataverse Audit (if Dataverse environment):**
     - Query `/api/data/v9.2/organizations?$select=isauditenabled`
     - Validate `isauditenabled = true`
   - **Determine Compliance Status:**
     - **Compliant (100000000):** All requirements met
     - **Non-Compliant (100000001):** Missing Purview OR Dataverse audit
     - **Error (100000003):** API errors or validation failures

4. **Write Compliance Records:**
   - Upsert to `fsi_auditenvironmentcompliance` table by environment ID
   - Include: environment name, audit enabled flags, compliance status, last checked timestamp, error message (if any)

5. **Generate Summary Report:**
   - Query all compliance records from current scan
   - Build HTML email with summary statistics
   - Export CSV attachment with per-environment details

6. **Send Email Notification (Optional):**
   - Send via Graph sendMail with shared mailbox
   - Include: compliance summary, non-compliant environments count, CSV attachment
   - Only sent if `-SendEmail` parameter is set

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `DataverseEnvironmentUrl` | String | Yes | Dataverse environment URL hosting compliance table (e.g., `https://org.crm.dynamics.com`) |
| `TenantDomain` | String | Yes | Tenant domain for Exchange Online (e.g., `contoso.onmicrosoft.com`) |
| `NotificationFromAddress` | String | No | Shared mailbox email for sending notifications |
| `NotificationToAddresses` | String | No | Comma-separated recipient emails |
| `SendEmail` | Switch | No | Enable email notification with CSV attachment |

**Example Execution:**
```powershell
.\Test-AuditLoggingCompliance.ps1 `
    -DataverseEnvironmentUrl "https://governance.crm.dynamics.com" `
    -TenantDomain "contoso.onmicrosoft.com" `
    -SendEmail `
    -NotificationFromAddress "governance@example.com" `
    -NotificationToAddresses "admin@example.com,compliance@example.com"
```

#### 3. Remediation Runbook — Enable-AuditLogging.ps1
**File:** `scripts/Enable-AuditLogging.ps1`

**Purpose:** Azure Automation runbook that enables audit logging on non-compliant environments with WhatIf simulation support.

**Remediation Actions:**

| Action | Scope | API Method | Result |
|--------|-------|------------|--------|
| **Enable Microsoft 365 Unified Audit Log** | Tenant-wide | `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true` | Turns on unified audit log ingestion where the tenant is not already enabled; verify in Exchange Online PowerShell |
| **Enable Dataverse Org Audit** | Per-environment | `PATCH /api/data/v9.2/organizations({orgId})` with `isauditenabled=true` | Enables organization-level Dataverse auditing |
| **Enable Entity-Level Audit** | Per-environment | `PUT /api/data/v9.2/EntityDefinitions({entityId})` with `IsAuditEnabled=true` | Enables audit on 6 Copilot Studio entities |

**Copilot Studio Entities (Entity-Level Audit):**

1. **bot** — Copilot Studio agent definitions
2. **botcomponent** — Agent components (topics, entities, variables)
3. **connectionreference** — Connection references used by agents
4. **environmentvariablevalue** — Environment variable values
5. **workflow** — Power Automate flows triggered by agents
6. **systemuser** — User records (for agent ownership tracking)

**Process Flow:**

1. **Authentication (Managed Identity):**
   - Same as detection runbook (Power Platform, Exchange Online, Dataverse)

2. **Target Environment Resolution:**
   - **If `EnvironmentId` parameter provided:** Remediate specific environment
   - **If `EnvironmentId` omitted:** Query `fsi_auditenvironmentcompliance` table for all records with `fsi_compliancestatus = 100000001` (Non-Compliant)

3. **Tenant-Level Remediation (Optional):**
   - **If `EnableTenantUnifiedAudit` switch is set:**
     - Run `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true`
     - **Note:** This is a tenant-wide change affecting all M365 services
     - **WhatIf:** Outputs `[WHATIF] Would enable tenant-wide Purview unified audit`

4. **Per-Environment Remediation:**
   - For each non-compliant environment:
     - **Enable Org-Level Audit:**
       - Query `/api/data/v9.2/organizations` to get organization ID
       - If `isauditenabled = false`:
         - `PATCH /api/data/v9.2/organizations({orgId})` with `isauditenabled=true`
         - Wait 5 seconds for propagation
       - **WhatIf:** Outputs `[WHATIF] Would enable org-level Dataverse auditing`
     - **Enable Entity-Level Audit:**
       - For each of the 6 Copilot Studio entities:
         - Query `/api/data/v9.2/EntityDefinitions(LogicalName='{entity}')?$select=MetadataId,IsAuditEnabled`
         - If `IsAuditEnabled.Value = false`:
           - `PUT /api/data/v9.2/EntityDefinitions({metadataId})` with `IsAuditEnabled={Value:true}`
         - **WhatIf:** Outputs `[WHATIF] Would enable entity-level audit on {entity}`

5. **Post-Remediation Validation:**
   - Re-query organization and entity audit status
   - Verify `isauditenabled = true` and all 6 entities have `IsAuditEnabled.Value = true`
   - Update `fsi_auditenvironmentcompliance` record:
     - `fsi_compliancestatus = 100000000` (Compliant) if validation succeeds
     - `fsi_compliancestatus = 100000003` (Error) if validation fails
     - `fsi_remediationdate = current timestamp`
     - `fsi_remediatedby = "Azure Automation MI"`

6. **Summary Report:**
   - Build console output with remediation results per environment
   - Include: environment name, org audit status, entity audit status, validation result

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `DataverseEnvironmentUrl` | String | Yes | Dataverse environment URL hosting compliance table |
| `TenantDomain` | String | Yes | Tenant domain for Exchange Online connection |
| `EnvironmentId` | String | No | Target specific environment by GUID. If omitted, remediates all non-compliant environments |
| `EnableTenantUnifiedAudit` | Switch | No | Enable tenant-wide Purview unified audit (default: `$true`) |
| `WhatIf` | Switch | No | Simulate remediation without making changes |

**Example Execution (WhatIf):**
```powershell
.\Enable-AuditLogging.ps1 `
    -DataverseEnvironmentUrl "https://governance.crm.dynamics.com" `
    -TenantDomain "contoso.onmicrosoft.com" `
    -WhatIf
```

**Example Execution (Specific Environment):**
```powershell
.\Enable-AuditLogging.ps1 `
    -DataverseEnvironmentUrl "https://governance.crm.dynamics.com" `
    -TenantDomain "contoso.onmicrosoft.com" `
    -EnvironmentId "12345678-abcd-1234-abcd-123456789012"
```

#### 4. Dataverse Schema Script — create_audit_compliance_schema.py
**File:** `scripts/create_audit_compliance_schema.py`

**Purpose:** Python script to create the Dataverse schema (table, columns, choice field, alternate key) for audit compliance tracking.

**Schema Components:**

**Table:** `fsi_auditenvironmentcompliance`
- **Display Name:** Audit Environment Compliance
- **Ownership:** Organization-owned
- **Auditing:** Enabled
- **Primary Column:** `fsi_environmentname` (environment display name)

**Columns:**

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_environmentid` | Single Line Text (100) | Power Platform environment GUID (upsert key) |
| `fsi_environmentname` | Single Line Text (200) | Environment display name (primary name column) |
| `fsi_auditenabled` | Yes/No | Purview unified audit enabled status |
| `fsi_dataverseauditenabled` | Yes/No | Dataverse org-level audit enabled status |
| `fsi_compliancestatus` | Choice | Compliance status (Compliant/Non-Compliant/Remediation Pending/Error) |
| `fsi_lastchecked` | DateTime (UTC) | Timestamp of last compliance check |
| `fsi_remediationdate` | DateTime (UTC) | Timestamp when remediation was applied |
| `fsi_remediatedby` | Single Line Text (100) | Identity that performed remediation (e.g., "Azure Automation MI") |
| `fsi_errormessage` | Multi-line Text (2000) | Error details if compliance check or remediation failed |
| `fsi_lasteventcaptured` | DateTime (UTC) | Timestamp of most recent audit event observed during optional audit search validation |

**Choice Field:** `fsi_alca_compliancestatus`

| Value | Label | Usage |
|-------|-------|-------|
| 100000000 | Compliant | Environment has both Purview and Dataverse audit enabled (if applicable) |
| 100000001 | Non-Compliant | Environment is missing Purview OR Dataverse audit |
| 100000002 | Remediation Pending | Remediation workflow initiated but not yet completed |
| 100000003 | Error | API errors or validation failures during compliance check |

**Alternate Key:** `fsi_environmentid_key`
- Column: `fsi_environmentid`
- Purpose: Enables upsert pattern (update if exists, insert if new) by environment GUID

**Execution:**
```bash
python create_audit_compliance_schema.py \
    --environment-url https://governance.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive
```

**Dry-Run Mode:**
```bash
python create_audit_compliance_schema.py \
    --environment-url https://governance.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive \
    --dry-run
```

#### 5. Power Automate Approval Flow — Audit Remediation Approval
**Build instructions:** See `docs/FLOW_SETUP.md`, section 2.4

**Purpose:** Power Automate cloud flow template for approval-gated remediation workflow.

**Trigger:** Dataverse webhook on `fsi_auditenvironmentcompliance` table
- **Filter:** `fsi_compliancestatus eq 100000001` (Non-Compliant status)
- **Message:** 1 (Create) and 2 (Update)
- **Scope:** Organization-level

**Workflow Logic:**

1. **Receive Non-Compliant Record:**
   - Extract environment ID, environment name, audit status flags

2. **Send Approval Request:**
   - **Approver:** Governance lead or compliance team
   - **Title:** `[AUDIT] Remediation Request — {EnvironmentName}`
   - **Details:**
     - Environment ID
     - Purview unified audit status
     - Dataverse audit status
     - Last checked timestamp
     - Request justification (auto-generated: "Audit logging is required for regulatory compliance")

3. **If Approved:**
   - Update `fsi_compliancestatus = 100000002` (Remediation Pending)
   - Trigger remediation runbook via Azure Automation webhook
   - Send Teams notification: "Remediation initiated for {EnvironmentName}"

4. **If Rejected:**
   - Log rejection reason in `fsi_errormessage` field
   - Send Teams notification: "Remediation rejected for {EnvironmentName} — {RejectionReason}"
   - Keep `fsi_compliancestatus = 100000001` (Non-Compliant)

5. **Post-Remediation:**
   - Wait for runbook completion (webhook callback)
   - Query updated compliance record
   - Send final status notification: "Remediation {Succeeded/Failed} for {EnvironmentName}"

**Configuration:**
- **Approver Email:** Set via environment variable `fsi_ALCA_ApproverEmail`
- **Teams Channel:** Set via environment variable `fsi_ALCA_TeamsChannelId`
- **Automation Webhook URL:** Set via environment variable `fsi_ALCA_RemediationWebhookUrl`

### Data Model

#### Dataverse Table: fsi_auditenvironmentcompliance

**Purpose:** Tracks current audit compliance status for each Power Platform environment. Updated via upsert pattern (by environment ID) on each compliance check.

**Table Properties:**
- **Schema Name:** `fsi_auditenvironmentcompliance`
- **Logical Name:** `fsi_auditenvironmentcompliance`
- **Ownership:** Organization-owned
- **Auditing:** Enabled
- **Primary Column:** `fsi_environmentname`

**Full Column Definitions:**

| Column | Schema Name | Type | Max Length | Required | Description |
|--------|-------------|------|------------|----------|-------------|
| Environment ID | `fsi_environmentid` | Text | 100 | Yes | Power Platform environment GUID (upsert key) |
| Environment Name | `fsi_environmentname` | Text | 200 | Yes | Environment display name (primary name) |
| Audit Enabled | `fsi_auditenabled` | Boolean | - | No | Purview unified audit enabled flag |
| Dataverse Audit Enabled | `fsi_dataverseauditenabled` | Boolean | - | No | Dataverse org-level audit enabled flag |
| Compliance Status | `fsi_compliancestatus` | Choice | - | Yes | Compliance status (see choice values below) |
| Last Checked | `fsi_lastchecked` | DateTime | - | No | Timestamp of last compliance check (UTC) |
| Remediation Date | `fsi_remediationdate` | DateTime | - | No | Timestamp when remediation was applied (UTC) |
| Remediated By | `fsi_remediatedby` | Text | 100 | No | Identity that performed remediation |
| Error Message | `fsi_errormessage` | Memo | 2000 | No | Error details if check/remediation failed |
| Last Event Captured | `fsi_lasteventcaptured` | DateTime | - | No | Timestamp of most recent audit event |

**Compliance Status Choice Values:**

| Value | Label | Meaning | Triggered By |
|-------|-------|---------|--------------|
| 100000000 | Compliant | Environment meets all audit requirements | Detection runbook validates all checks pass |
| 100000001 | Non-Compliant | Environment is missing required audit configuration | Detection runbook identifies missing Purview OR Dataverse audit |
| 100000002 | Remediation Pending | Remediation workflow initiated but not completed | Approval flow updates status before triggering remediation runbook |
| 100000003 | Error | API errors or validation failures | Detection or remediation runbook encounters exceptions |

**Alternate Key:** `fsi_environmentid_key`
- **Columns:** `fsi_environmentid`
- **Purpose:** Enables upsert operations by environment ID. When writing compliance records, if a record with the same environment ID exists, it is updated; otherwise, a new record is created.

**Example Data:**

```
┌──────────────────────────────────┬────────────────────────┬───────┬──────────────┬────────────────┬─────────────────────┐
│ fsi_environmentid                │ fsi_environmentname    │ fsi_  │ fsi_dataverse│ fsi_compliance │ fsi_lastchecked     │
│                                  │                        │ audit │ auditenabled │ status         │                     │
│                                  │                        │enabled│              │                │                     │
├──────────────────────────────────┼────────────────────────┼───────┼──────────────┼────────────────┼─────────────────────┤
│ 12345678-abcd-1234-abcd-123456…  │ Finance Production     │ true  │ true         │ 100000000      │ 2026-02-14 06:15:32 │
│                                  │                        │       │              │ (Compliant)    │                     │
├──────────────────────────────────┼────────────────────────┼───────┼──────────────┼────────────────┼─────────────────────┤
│ 87654321-bcde-2345-bcde-234567…  │ HR Team Sandbox        │ true  │ false        │ 100000001      │ 2026-02-14 06:16:10 │
│                                  │                        │       │              │ (Non-Compliant)│                     │
├──────────────────────────────────┼────────────────────────┼───────┼──────────────┼────────────────┼─────────────────────┤
│ aaaaaaaa-bbbb-cccc-dddd-eeeeee…  │ Legal Dev              │ false │ false        │ 100000001      │ 2026-02-14 06:16:45 │
│                                  │                        │       │              │ (Non-Compliant)│                     │
└──────────────────────────────────┴────────────────────────┴───────┴──────────────┴────────────────┴─────────────────────┘
```

### Configuration and Prerequisites

#### Prerequisites

**Microsoft 365 Licensing:**
- Microsoft 365 E3 or E5 (for Purview unified audit log)
- Power Platform Admin permissions
- Power Apps Premium (for Dataverse)
- Azure subscription (for Azure Automation)

**Permissions:**

| Role/Permission | Required For | Scope | Assignment Method |
|-----------------|--------------|-------|-------------------|
| **Power Platform Admin** (Entra display name: `Power Platform Administrator`) | Environment enumeration, audit config access | Microsoft Entra role | Microsoft Entra ID → Roles and administrators |
| **Exchange Online Admin** (Entra display name: `Exchange Administrator`) | Exchange Online managed identity auth, `Get-AdminAuditLogConfig`, `Search-UnifiedAuditLog` | Microsoft Entra role | Microsoft Entra ID → Roles and administrators |
| **Dataverse Application User** | Read/write compliance table, modify audit config | Per-environment | Power Platform Admin Center → Application users |
| **Mail.Send (Graph API)** | Send email notifications | Microsoft Graph | PowerShell: New-MgServicePrincipalAppRoleAssignment |

**Azure Resources:**

| Resource | Purpose | Configuration |
|----------|---------|---------------|
| **Azure Automation Account** | Host detection and remediation runbooks | System-Assigned Managed Identity enabled |
| **Shared Mailbox (optional)** | Send compliance notifications | Exchange Online shared mailbox with MI send-as permission |

**PowerShell Modules (Azure Automation):**

| Module | Version | Purpose |
|--------|---------|---------|
| `Microsoft.PowerApps.Administration.PowerShell` | 2.0+ | Power Platform environment management |
| `ExchangeOnlineManagement` | 3.7.0+ | Exchange Online MI auth, audit log search |
| `AuditComplianceHelpers` | 1.0.0 | ALCA shared helper module (custom) |

#### Configuration Steps

**Step 1: Create Azure Automation Account**

1. Navigate to **Azure Portal** → **Automation Accounts** → **+ Create**
2. Configure:
   - **Name:** `FSI-AgentGov-Automation`
   - **Resource Group:** Use governance resource group
   - **Region:** Same region as Power Platform tenant
   - **Identity:** System assigned = **On**
3. Click **Review + Create** → **Create**
4. Navigate to **Identity** → **System assigned** → Record **Object (principal) ID**

**Step 2: Assign Managed Identity Permissions**

**Entra ID Roles:**

1. Navigate to **Microsoft Entra ID** → **Roles and administrators**
2. Assign **Power Platform Admin** (search for Entra display name `Power Platform Administrator`):
   - Search for role → **+ Add assignments** → Select `FSI-AgentGov-Automation` MI → **Assign**
3. Assign **Exchange Online Admin** (search for Entra display name `Exchange Administrator`):
   - Search for role → **+ Add assignments** → Select `FSI-AgentGov-Automation` MI → **Assign**

**Microsoft Graph API Permission (Mail.Send):**

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.Read.All","AppRoleAssignment.ReadWrite.All"

# Get the Managed Identity service principal
$miObjectId = "<your-MI-object-id>"
$mi = Get-MgServicePrincipal -ServicePrincipalId $miObjectId

# Get Microsoft Graph service principal
$graph = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Find Mail.Send app role
$mailSendRole = $graph.AppRoles | Where-Object { $_.Value -eq "Mail.Send" }

# Assign the role
New-MgServicePrincipalAppRoleAssignment `
    -ServicePrincipalId $mi.Id `
    -PrincipalId $mi.Id `
    -ResourceId $graph.Id `
    -AppRoleId $mailSendRole.Id
```

**Dataverse Application User (Per Environment):**

For each Power Platform environment with Dataverse:

1. Navigate to **Power Platform Admin Center** → **Environments** → Select environment
2. **Settings** → **Users + permissions** → **Application users** → **+ New app user**
3. **Add an app:** Search for `FSI-AgentGov-Automation` by MI Application ID
4. **Business unit:** Select root business unit
5. **Security roles:** Assign **System Administrator**
6. Click **Create**

**Note:** Repeat for every Dataverse environment you want ALCA to scan and remediate.

**Step 3: Import PowerShell Modules**

1. Navigate to **Azure Automation Account** → **Modules** → **Browse gallery**
2. Search and import:
   - `Microsoft.PowerApps.Administration.PowerShell` (version 2.0+)
   - `ExchangeOnlineManagement` (version 3.7.0+)
3. Wait for import completion (Status: Available)

**Step 4: Upload Custom Helper Module**

1. Package `AuditComplianceHelpers.psm1` and `AuditComplianceHelpers.psd1` as ZIP
2. Navigate to **Azure Automation Account** → **Modules** → **+ Add a module**
3. **Upload:** Select ZIP file → **Runtime version:** 7.2 → **Import**

**Step 5: Create Detection Runbook**

1. Navigate to **Azure Automation Account** → **Runbooks** → **+ Create a runbook**
2. **Name:** `Test-AuditLoggingCompliance`
3. **Runbook type:** PowerShell
4. **Runtime version:** 7.2
5. Click **Create**
6. **Edit PowerShell Runbook:** Paste contents of `Test-AuditLoggingCompliance.ps1`
7. Click **Save** → **Publish**

**Step 6: Create Remediation Runbook**

1. Navigate to **Runbooks** → **+ Create a runbook**
2. **Name:** `Enable-AuditLogging`
3. **Runbook type:** PowerShell
4. **Runtime version:** 7.2
5. Click **Create**
6. **Edit PowerShell Runbook:** Paste contents of `Enable-AuditLogging.ps1`
7. Click **Save** → **Publish**

**Step 7: Create Dataverse Schema**

1. Install Python dependencies:
   ```bash
   pip install msal requests
   ```

2. Run schema creation script:
   ```bash
   python create_audit_compliance_schema.py \
       --environment-url https://governance.crm.dynamics.com \
       --tenant-id <your-tenant-id> \
       --interactive
   ```

3. Verify table creation in Power Apps maker portal:
   - Navigate to **Tables** → Search for `fsi_auditenvironmentcompliance`
   - Verify columns, choice field, and alternate key exist

**Step 8: Schedule Detection Runbook**

1. Navigate to **Test-AuditLoggingCompliance** runbook → **Schedules** → **+ Add a schedule**
2. **Create schedule:**
   - **Name:** `Weekly-Audit-Compliance-Scan`
   - **Starts:** Next Monday 06:00 UTC
   - **Recurrence:** Recur every **1 Week**
   - **Expires:** Never
3. **Configure parameters:**
   - `DataverseEnvironmentUrl`: `https://governance.crm.dynamics.com`
   - `TenantDomain`: `contoso.onmicrosoft.com`
   - `SendEmail`: `true`
   - `NotificationFromAddress`: `governance@example.com`
   - `NotificationToAddresses`: `admin@example.com,compliance@example.com`
4. Click **OK** → **Create**

**Step 9: Test Detection Runbook**

1. Navigate to **Test-AuditLoggingCompliance** runbook → **Start**
2. **Parameters:**
   - `DataverseEnvironmentUrl`: `https://governance.crm.dynamics.com`
   - `TenantDomain`: `contoso.onmicrosoft.com`
   - Leave email parameters empty for initial test
3. Click **OK**
4. Monitor **Jobs** → View output stream
5. Verify:
   - Authentication successful (Power Platform, Exchange Online, Dataverse)
   - Environments enumerated
   - Compliance records created in Dataverse table
   - No errors in output

**Step 10: Test Remediation Runbook (WhatIf)**

1. Navigate to **Enable-AuditLogging** runbook → **Start**
2. **Parameters:**
   - `DataverseEnvironmentUrl`: `https://governance.crm.dynamics.com`
   - `TenantDomain`: `contoso.onmicrosoft.com`
   - `WhatIf`: `true`
3. Click **OK**
4. Monitor output for `[WHATIF] Would enable...` messages
5. Verify no actual changes made

### Deployment Validation

**Test 1: Detection Runbook — Authentication**

```powershell
# In Azure Automation → Runbooks → Test-AuditLoggingCompliance → Test pane

# Expected output:
# [Step 1/6] Authenticating via Managed Identity...
#   [OK] Power Platform authentication successful
#   [OK] Exchange Online authentication successful
#   [OK] Dataverse authentication successful
```

**Test 2: Detection Runbook — Environment Scan**

```powershell
# Expected output:
# [Step 2/6] Enumerating Power Platform environments...
#   [OK] Found 42 environment(s)
#
# [Step 3/6] Scanning environments for audit compliance...
#   Environment 1/42: Finance Production
#     [OK] Purview unified audit: Enabled
#     [OK] Dataverse audit: Enabled
#     [OK] Recent audit events found (last 7 days)
#     Compliance: Compliant
```

**Test 3: Dataverse Table Validation**

1. Navigate to **Power Apps** → **Tables** → `fsi_auditenvironmentcompliance`
2. Verify records created for each environment
3. Check compliance status distribution:
   - Compliant (100000000): Environments with full audit coverage
   - Non-Compliant (100000001): Environments missing audit config
4. Verify `fsi_lastchecked` timestamp matches runbook execution time

**Test 4: Remediation Runbook — WhatIf Mode**

```powershell
# In Azure Automation → Enable-AuditLogging → Test pane
# Parameters: -WhatIf $true

# Expected output:
# [WHATIF] Would enable tenant-wide Purview unified audit
# Processing environment: HR Team Sandbox (87654321-bcde-2345...)
#   [WHATIF] Would enable org-level Dataverse auditing
#   [WHATIF] Would enable entity-level audit on bot
#   [WHATIF] Would enable entity-level audit on botcomponent
#   [WHATIF] Would enable entity-level audit on connectionreference
#   [WHATIF] Would enable entity-level audit on environmentvariablevalue
#   [WHATIF] Would enable entity-level audit on workflow
#   [WHATIF] Would enable entity-level audit on systemuser
```

**Test 5: Remediation Runbook — Actual Remediation**

1. Identify a non-compliant test environment from Dataverse table
2. Run remediation runbook WITHOUT `-WhatIf`:
   ```powershell
   .\Enable-AuditLogging.ps1 `
       -DataverseEnvironmentUrl "https://governance.crm.dynamics.com" `
       -TenantDomain "contoso.onmicrosoft.com" `
       -EnvironmentId "87654321-bcde-2345-bcde-234567890123"
   ```
3. Verify:
   - Console output shows successful org-level audit enablement
   - Console output shows entity-level audit enablement for 6 entities
   - Post-remediation validation shows `isauditenabled = true`
   - Dataverse record updated to `fsi_compliancestatus = 100000000` (Compliant)
4. Manually validate in Power Platform Admin Center:
   - **Settings** → **Audit and logs** → **Start Auditing** shows as **Enabled**

**Test 6: Email Notification**

1. Run detection runbook with `-SendEmail` parameter
2. Check recipient inbox for email:
   - **Subject:** `[AUDIT] Audit Logging Compliance Scan — {date}`
   - **Body:** HTML table with compliance summary
   - **Attachment:** CSV file with per-environment details
3. Verify CSV contains columns: Environment ID, Environment Name, Audit Enabled, Dataverse Audit Enabled, Compliance Status, Last Checked

### Operational Guidance

#### Daily Operations

**Monitoring:**
- Review weekly compliance scan email notifications
- Investigate Non-Compliant environments within 2 business days
- Track remediation success rate (target: 95%+ auto-remediation)
- Monitor Error status environments for API or permission issues

**Compliance Triage:**

| Compliance Status | Priority | Action | Timeline |
|-------------------|----------|--------|----------|
| **Non-Compliant** | High | Run remediation runbook (WhatIf first) | 2 business days |
| **Error** | Critical | Investigate error message, verify MI permissions | Same day |
| **Remediation Pending** | Medium | Check approval workflow status | 1 business day |
| **Compliant** | Low | No action required (periodic validation) | N/A |

**Remediation Workflow:**

1. **Review Non-Compliant Environments:**
   - Query Dataverse: `fsi_compliancestatus = 100000001`
   - Export to CSV for governance review
   - Identify business justification for audit enablement

2. **Approval (if using Power Automate flow):**
   - Approval request sent to governance lead automatically
   - Approver reviews environment purpose and data classification
   - Approve or reject with business justification

3. **Execute Remediation:**
   - **Manual:** Run `Enable-AuditLogging` runbook via Azure Portal
   - **Automated:** Approval flow triggers runbook via webhook

4. **Post-Remediation Validation:**
   - Wait 24 hours for next scheduled compliance scan
   - Verify environment status changed to **Compliant**
   - If still Non-Compliant → Check error message and re-remediate

**Weekly Tasks:**

- Review compliance scan email summary
- Track trend: % Compliant vs. Non-Compliant over time
- Investigate new environments (recently created, not yet scanned)
- Update approval workflow approvers if governance team changes

**Monthly Tasks:**

- Export compliance evidence for audit record:
  ```powershell
  # Query last 30 days of compliance records
  # Export to CSV for audit folder
  ```
- Review Error status environments and resolve persistent issues
- Validate MI permissions remain active (roles not accidentally removed)
- Test remediation runbook in sandbox environment

#### Troubleshooting

**Issue: Detection runbook fails with "Power Platform authentication failed"**

**Cause:** Managed Identity lacks Power Platform Admin role

**Resolution:**
1. Navigate to **Microsoft Entra ID** → **Roles and administrators** → **Power Platform Administrator** (Power Platform Admin display name)
2. Verify `FSI-AgentGov-Automation` MI is assigned
3. If missing, add assignment
4. Wait 15 minutes for role propagation
5. Re-run runbook

**Issue: "Search-UnifiedAuditLog failed: The term 'Search-UnifiedAuditLog' is not recognized"**

**Cause:** ExchangeOnlineManagement module not imported or MI lacks Exchange Online Admin role

**Resolution:**
1. Verify module imported in Azure Automation:
   - **Modules** → Search `ExchangeOnlineManagement` → Status: Available
2. Verify MI has Exchange Online Admin role:
   - **Microsoft Entra ID** → **Roles and administrators** → **Exchange Administrator** (Exchange Online Admin display name) → Verify assignment
3. Re-run runbook

**Issue: "Dataverse API call failed: Unauthorized (401)"**

**Cause:** Managed Identity not configured as Application User in target environment

**Resolution:**
1. Navigate to **Power Platform Admin Center** → **Environments** → Select environment
2. **Settings** → **Users + permissions** → **Application users**
3. Verify `FSI-AgentGov-Automation` exists
4. If missing, create new app user:
   - **Add an app:** Search by MI Application ID
   - **Security roles:** Assign **System Administrator**
5. Re-run runbook

**Issue: Remediation runbook completes but compliance status remains Non-Compliant**

**Cause:** Audit enablement propagation delay or validation logic error

**Resolution:**
1. Manually verify audit status in Power Platform Admin Center:
   - **Settings** → **Audit and logs** → Check **Start Auditing** status
2. If audit is actually enabled:
   - Wait 24 hours for next scheduled compliance scan
   - Dataverse record will update on next scan
3. If audit is still disabled:
   - Check runbook output for error messages
   - Verify MI has System Administrator role in environment
   - Re-run remediation runbook

**Issue: Email notifications not sent**

**Cause:** Missing Mail.Send permission or shared mailbox configuration

**Resolution:**
1. Verify Graph API permission:
   ```powershell
   Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $miObjectId | Where-Object { $_.AppRoleId -eq $mailSendRole.Id }
   ```
2. Verify shared mailbox exists and MI has send-as permission:
   - **Exchange Admin Center** → **Recipients** → **Mailboxes** → Search shared mailbox
   - **Manage mailbox delegation** → **Send as** → Verify MI listed
3. Re-run detection runbook with `-SendEmail`

**Issue: WhatIf mode shows "[WHATIF] Would enable..." but actual remediation fails**

**Cause:** WhatIf bypasses actual API calls, so permission errors not detected until real execution

**Resolution:**
1. Check remediation runbook output for specific API error
2. Common issues:
   - **403 Forbidden:** MI lacks System Administrator role
   - **404 Not Found:** Environment ID incorrect or environment deleted
   - **429 Throttled:** API rate limit exceeded (retry after 60 seconds)
3. Resolve permission issue and re-run

**Issue: Entity-level audit enablement fails for specific entity**

**Cause:** Entity does not exist in environment or entity name changed

**Resolution:**
1. Query entity existence:
   ```powershell
   GET /api/data/v9.2/EntityDefinitions(LogicalName='bot')
   ```
2. If entity not found (404):
   - Environment may not have Copilot Studio installed
   - Skip entity-level audit for this environment (not applicable)
3. If entity exists but update fails:
   - Check error message for permission issues
   - Verify MI has System Administrator role

#### Audit and Evidence Export

**Evidence Collection:**

For regulatory examinations, export compliance records from Dataverse:

```powershell
# Option 1: Dataverse Web API query
GET /api/data/v9.2/fsi_auditenvironmentcompliances  # OData entity set for logical table fsi_auditenvironmentcompliance
  ?$select=fsi_environmentid,fsi_environmentname,fsi_auditenabled,fsi_dataverseauditenabled,fsi_compliancestatus,fsi_lastchecked
  &$filter=fsi_lastchecked ge 2025-11-14T00:00:00Z
  &$orderby=fsi_lastchecked desc

# Option 2: Export via Power Apps
# Navigate to Tables → fsi_auditenvironmentcompliance → Export data → Excel
```

**Export Format:**

Evidence files should include:
- **Compliance records:** Last 90 days of compliance checks (CSV or Excel)
- **Remediation history:** Environments remediated with timestamps and identity
- **Runbook execution logs:** Azure Automation job history for detection and remediation
- **Email notifications:** Forward compliance scan emails to audit archive mailbox

**Retention:**

- **Communications-class compliance records:** Retain for **3 years** under SEC 17a-4(b)(4) (first 2 years readily accessible). For mailbox audit and message-related records.
- **Books-and-records-class compliance records:** Retain for **6 years** under SEC 17a-4(a) and FINRA Rule 4511(b) (e.g., environment registry, validation history, security role assignments).
- **SOX/PCAOB-related audit-supporting records:** Retain for **7 years** under PCAOB AS 1215 / SOX §802 where the records are relied upon as audit work papers.
- **GLBA Safeguards Rule** does not specify a retention period — firm policy applies.
- Remediation history: Retain for the longest applicable period above based on the underlying record class
- Runbook logs: Retain for 3 years (operational history, Azure Automation default)
- Email notifications: Retain for 3 years (compliance evidence)

---

## Appendix: Compliance Status Reference

### Compliant (Code: 100000000)

**Description:** Environment meets all audit logging requirements based on environment type.

**Criteria:**

| Environment Type | Requirements |
|------------------|--------------|
| **Dataverse environments** | Purview unified audit enabled AND Dataverse org-level audit enabled AND entity-level audit enabled for 6 Copilot Studio entities |
| **Non-Dataverse environments** | Purview unified audit enabled only |

**Validation:**
- `Get-AdminAuditLogConfig` returns `UnifiedAuditLogIngestionEnabled = $true`
- Optional audit search returns recent events when matching activity exists; event absence alone does not fail configuration validation
- (Dataverse only) `/api/data/v9.2/organizations` returns `isauditenabled = true`
- (Dataverse only) All 6 Copilot Studio entities have `IsAuditEnabled.Value = true`

**Example:**
```
Environment: Finance Production
Purview Unified Audit: Enabled
Dataverse Org Audit: Enabled
Entity Audit (bot, botcomponent, etc.): Enabled
Status: Compliant (100000000)
```

### Non-Compliant (Code: 100000001)

**Description:** Environment is missing required audit logging configuration.

**Criteria:**
- Purview unified audit disabled
- OR (for Dataverse environments) Dataverse org-level audit disabled
- OR (for Dataverse environments) Entity-level audit disabled for one or more Copilot Studio entities

**Remediation:**
- Run `Enable-AuditLogging.ps1` runbook to enable missing audit configuration
- Approve remediation via Power Automate flow (if configured)

**Example 1 (Purview Disabled):**
```
Environment: Legal Dev
Purview Unified Audit: Disabled
Dataverse Org Audit: N/A (no Dataverse)
Status: Non-Compliant (100000001)
Remediation: Enable tenant-wide Purview unified audit
```

**Example 2 (Dataverse Audit Disabled):**
```
Environment: HR Team Sandbox
Purview Unified Audit: Enabled
Dataverse Org Audit: Disabled
Status: Non-Compliant (100000001)
Remediation: Enable Dataverse org-level audit + entity-level audit
```

### Remediation Pending (Code: 100000002)

**Description:** Remediation workflow initiated but not yet completed.

**Criteria:**
- Approval flow updated status to Remediation Pending
- Remediation runbook triggered via webhook
- Awaiting runbook completion and post-remediation validation

**Next Steps:**
- Wait for remediation runbook to complete
- Monitor Azure Automation job history for status
- Post-remediation: Detection runbook will update status to Compliant or Error

**Example:**
```
Environment: Marketing Sandbox
Status: Remediation Pending (100000002)
Remediation Date: 2026-02-14 14:30:00 UTC
Remediated By: Azure Automation MI
Next Action: Await runbook completion and validation
```

### Error (Code: 100000003)

**Description:** API errors or validation failures during compliance check or remediation.

**Criteria:**
- Detection runbook encounters API errors (401 Unauthorized, 403 Forbidden, 500 Internal Server Error)
- Remediation runbook fails to enable audit configuration
- Post-remediation validation fails

**Error Types:**

| Error Message | Cause | Resolution |
|---------------|-------|------------|
| "Unauthorized (401)" | MI lacks permissions | Verify Power Platform Admin role, Dataverse app user, Exchange Admin role |
| "Forbidden (403)" | MI lacks System Administrator in environment | Add MI as app user with System Administrator role |
| "NotFound (404)" | Environment deleted or ID incorrect | Remove compliance record or correct environment ID |
| "Throttled (429)" | API rate limit exceeded | Retry after 60 seconds, reduce concurrent operations |
| "Search-UnifiedAuditLog failed" | Exchange Online MI auth failed or audit search unavailable | Verify Exchange Online Admin role assignment and ExchangeOnlineManagement module availability |

**Example:**
```
Environment: External Sandbox
Status: Error (100000003)
Error Message: Dataverse API call failed: Unauthorized (401). The Managed Identity does not have permission to access this environment.
Resolution: Add FSI-AgentGov-Automation as Application User with System Administrator role
```

---

## Appendix: Regulatory Alignment

The Audit Logging Compliance Automation solution supports compliance with the following regulatory requirements:

### FINRA 4511 — Books and Records

**Requirement:** Member firms must make and preserve books and records as required under FINRA rules and the Exchange Act, including electronic records of system configurations and audit trails.

**ALCA Support:**
- Continuous monitoring helps keep audit logging enabled across all environments
- Entity-level audit on Copilot Studio entities (bot, botcomponent, workflow) tracks agent changes
- Automated remediation helps prevent prolonged audit gaps
- Compliance records provide evidence of supervisory controls effectiveness

### SEC 17a-3 / 17a-4 — Recordkeeping

**Requirement:** Broker-dealers must make and preserve records related to business operations, including electronic communications, trading activities, and system changes. Records must be retained for prescribed periods (3-6 years).

**ALCA Support:**
- Purview unified audit log captures many supported audited M365 and Power Platform events (coverage varies by workload and license — see [Microsoft 365 audited activities documentation](https://learn.microsoft.com/purview/audit-log-activities)). `Search-UnifiedAuditLog` is a validation aid; it does not by itself prove exhaustive event capture
- Dataverse audit log captures entity changes, field modifications, and API calls
- Entity-level audit helps ensure Copilot Studio agent changes are recorded
- Compliance table provides immutable evidence of audit configuration history

### SOX 404 — Internal Controls over Financial Reporting

**Requirement:** Management must establish and maintain adequate internal controls to ensure reliability of financial reporting, including IT general controls (ITGCs) for change management and audit logging.

**ALCA Support:**
- Automated detection validates audit controls remain effective (preventive control)
- Remediation workflow helps correct non-compliant environments (detective and corrective control)
- Dataverse compliance table provides audit trail of control effectiveness
- Email notifications enable timely management review of control deficiencies

### GLBA 501(b) — Safeguards Rule

**Requirement:** Financial institutions must implement administrative, technical, and physical safeguards to protect customer information, including monitoring and logging of system access.

**ALCA Support:**
- Audit logging captures access to environments containing customer data
- Entity-level audit on systemuser entity tracks user access and permission changes
- Continuous monitoring helps keep audit controls active
- Remediation helps prevent audit gaps that could obscure unauthorized access

---

## Audit Configuration Validator (ACV) Subsystem

The ACM solution includes the **Audit Configuration Validator (ACV)** subsystem, which provides the Dataverse Web API integration layer and Power Automate validation flows.

### ACV Components

| Component | Description |
|-----------|-------------|
| `scripts/acv_client.py` | Dataverse Web API client with MSAL authentication (interactive browser or service principal), retry logic, and dry-run mode |
| `templates/adaptive-card-tenant-alert.json` | Adaptive Card v1.4 template for tenant-level drift alerts posted to Teams |
| `templates/adaptive-card-environment-alert.json` | Adaptive Card v1.4 template for environment-level drift alerts posted to Teams |
| `scripts/create_dataverse_schema.py` | Creates the **ACV** Dataverse tables (`fsi_auditvalidationhistory` and `fsi_environmentregistry`) |
| `scripts/create_audit_compliance_schema.py` | Creates the **ALCA** `fsi_auditenvironmentcompliance` Dataverse table and columns |
| `scripts/create_connection_references.py` | Creates connection references for Power Automate flows |
| `scripts/create_environment_variables.py` | Creates environment variables used by validation flows |

### ACV Authentication

ACV uses MSAL for Dataverse authentication, supporting interactive browser login for bootstrap and legacy dev-only service principal client-secret authentication. Production automation should use managed identity where supported or certificate-based app-only authentication for Exchange Online/Power Automate orchestration. The `ACVClient` class in `acv_client.py` handles token acquisition, caching, and refresh.

### Relationship to ALCA

ALCA provides the detection and remediation runbooks (Azure Automation). ACV provides the Dataverse schema, validation flows, and alerting infrastructure. Together they form the complete ACM solution: ACV detects drift via Power Automate flows and writes results to Dataverse; ALCA reads those results and remediates non-compliant environments via approval-gated runbooks.

---

## Support and Maintenance

**Solution Version:** 1.0.4
**Release Date:** April 2026
**License:** MIT License

**Change Management:**
- Test runbook changes in non-production Azure Automation account first
- Document Managed Identity permission changes in change tickets
- Review Copilot Studio entity list quarterly (new entities may require audit enablement)
- Coordinate tenant-wide audit enablement with M365 admin team (impacts all services)

**Version History:**
- **v1.0.0 (February 2026):** Initial merged release combining ACV and ALCA components
- **v1.0.1 (March 2026):** Issue-fix wave — see CHANGELOG
- **v1.0.2 (April 2026):** Token-cache and OData filter bug fixes
- **v1.0.3 (April 2026):** AI Council technical-accuracy pass (Opus 4.7 + Goldeneye + GPT-5.4)
- **v1.0.4 (Unreleased):** Microsoft Learn 2026-Q2 refresh for Purview Audit retention, managed-identity-first authentication, and Power Platform/Dataverse audit terminology

---

## Known Limitations

- **No Power Platform solution package:** This solution does not include `solution.xml` or `customizations.xml` and cannot be imported via the Power Platform Admin Center or `pac solution import`. Deployment uses Azure Automation runbooks and PowerShell scripts directly. For enterprise ALM scenarios requiring managed/unmanaged solution import, the scripts and Dataverse table definitions would need to be packaged into a standard Power Platform solution.

---

*This solution supports compliance with FINRA 4511, SEC 17a-3/17a-4, SOX 404, and GLBA 501(b). Consult with your compliance and legal teams for applicability to your organization's regulatory requirements.*
