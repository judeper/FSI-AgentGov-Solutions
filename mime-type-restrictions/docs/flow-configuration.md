# Securing AI Agent File Uploads with MIME Type Restrictions
## MIME Type Restrictions for File Uploads

**Version:** 1.2.1
**Solution Type:** Server-Side Validation + Data Policy Reference + Monitoring
**Platform:** Dataverse Plugin + Power Platform data policies + Microsoft Sentinel

---

## Executive Summary

### Problem Statement

Copilot Studio agents often include file upload capabilities to enable users to share documents, images, and data files. However, unrestricted file uploads create significant security risks, including malware distribution, data exfiltration via steganography, and execution of malicious code disguised as legitimate file types. Without proper MIME type validation, attackers can bypass client-side checks by manipulating file extensions or MIME headers.

**Risk Exposure:**
- **Malware Distribution:** Executable files (EXE, DLL, JAR) uploaded and distributed through AI agents
- **Data Exfiltration:** Sensitive data hidden in image files via steganography
- **Code Execution:** Malicious scripts (PowerShell, VBS, BAT) uploaded and executed on user workstations
- **Compliance Violations:** Failure to restrict file types violates security control requirements (NIST 800-53 SI-3, FINRA 4511)
- **Storage Abuse:** Unrestricted file types lead to excessive Dataverse storage consumption

### Solution Overview

The **MIME Type Restrictions for File Uploads** solution provides defense-in-depth validation of file uploads in Copilot Studio agents through server-side Dataverse plugin validation with magic byte inspection, Power Platform data policy guardrails for upload-capable connectors, and Microsoft Sentinel monitoring for blocked upload attempts.

**Key Capabilities:**
- **Server-Side Validation:** Dataverse pre-validation plugin inspects file content (magic bytes) to verify actual file type matches declared MIME type
- **Magic Byte Inspection:** Validates file signatures (headers) against known patterns (PDF: %PDF, PNG: 89 50 4E 47, etc.)
- **Blocked Signature Detection:** Automatically blocks executable signatures (PE/DOS, ELF, Mach-O, Java class files)
- **Power Platform Data Policy Guardrails:** Power Platform data policies classify or block upload-capable connectors; MIME and extension checks are performed by the Dataverse plugin
- **OpenXML Deep Inspection:** Validates Office documents (DOCX, XLSX, PPTX) by inspecting internal ZIP structure and [Content_Types].xml
- **Sentinel Monitoring:** KQL queries aggregate blocked upload attempts for security operations review

**Business Value:**
- Significantly reduces malware distribution risk through multi-layered validation
- Helps reduce data exfiltration risk from file-based steganography
- Supports regulatory examinations with MIME restriction evidence
- Enables security operations teams to detect and respond to upload abuse patterns
- Reduce Dataverse storage costs by blocking large executable files

---

## Technical Details

### Architecture Overview

The MIME Type Restrictions solution operates across two preventive layers plus a monitoring layer. The Dataverse plugin fails secure for MIME and magic-byte violations, Power Platform data policies constrain upload-capable connectors, and Sentinel surfaces evidence and alerts.

```
┌─────────────────────────────────────────────────────────────────────┐
│              MIME Type Restrictions Architecture                     │
│                    Defense-in-Depth Validation                       │
└─────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────────┐     ┌──────────────────┐      ┌──────────────────┐
│  Layer 1:         │     │  Layer 2:        │      │  Layer 3:        │
│  Data Policy      │────▶│  Dataverse       │─────▶│  Sentinel        │
│  (Connectors)     │     │  Plugin          │      │  Monitoring      │
│                   │     │  (Pre-Validation)│      │  (Detection)     │
│  - Policy scope   │     │                  │      │                  │
│  - Data groups    │     │  1. File size    │      │  - KQL queries   │
│  - Audit/Block    │     │     guard        │      │  - Block events  │
│    propagation    │     │  2. Blocked sig  │      │  - Exception     │
│                   │     │     scan         │      │    tracking      │
│  If PASS ──────┐  │     │  3. Allowlist    │      │  - High-volume   │
│                │  │     │     check        │      │    alerts        │
│  If BLOCK ─────┼──┼─────┼──────────────────┼─────▶│  Log blocked     │
│                │  │     │  4. Magic byte   │      │  event (DLP)     │
│                │  │     │     consistency  │      │                  │
│                │  │     │  5. OpenXML deep │      │                  │
│                │  │     │     inspection   │      │                  │
│                │  │     │                  │      │                  │
│                │  │     │  If PASS ──────┐ │      │                  │
│                │  │     │                │ │      │                  │
│                │  │     │  If BLOCK ─────┼─┼─────▶│  Log blocked     │
│                │  │     │                │ │      │  event           │
│                │  │     │                │ │      │                  │
│                ▼  │     │                ▼ │      │                  │
│           ┌───────────────────────────┐   │      │                  │
│           │  Dataverse Annotation     │   │      │                  │
│           │  (Note) Entity            │   │      │                  │
│           │  - documentbody (Base64)  │   │      │                  │
│           │  - mimetype               │   │      │                  │
│           │  - filename               │   │      │                  │
│           │  - filesize               │   │      │                  │
│           └───────────────────────────┘   │      │                  │
└───────────────────┘     └──────────────────┘      └──────────────────┘
                                    │
                                    ▼
                          ┌─────────────────┐
                          │  MimeConfig.json│
                          │  (Configuration)│
                          │                 │
                          │  - Allowlist    │
                          │  - Blocklist    │
                          │  - Magic bytes  │
                          │  - Max file size│
                          └─────────────────┘
```

### Solution Components

#### 1. Dataverse Plugin — ValidateMimeTypePlugin.cs
**File:** `src/ValidateMimeTypePlugin.cs`

**Purpose:** Server-side pre-validation plugin that inspects file uploads (annotations) for magic-byte signature compliance and blocks disallowed or malicious file types.

**Registration:**
- **Entity:** `annotation` (Note)
- **Message:** `Create` and `Update` (filtering attributes: `documentbody`, `mimetype`)
- **Stage:** Pre-Validation (stage 10)
- **Mode:** Synchronous
- **Deployment:** Sandbox

**Validation Process:**

1. **File Size Guard:**
   - Checks file size against `maxFileSizeBytes` configuration (default: 10 MB)
   - Blocks files exceeding limit
   - Example: 50 MB EXE file → Blocked

2. **Blocked Signature Scan:**
   - Compares first 16 bytes against known executable headers
   - Blocked signatures:
     - **PE/MS-DOS:** `4D 5A` (Windows EXE/DLL)
     - **ELF:** `7F 45 4C 46` (Linux binaries)
     - **Mach-O 32/64-bit:** `FE ED FA CE`, `FE ED FA CF` (macOS binaries)
     - **Mach-O 32/64-bit (reversed):** `CE FA ED FE`, `CF FA ED FE` (macOS binaries, reversed byte order)
     - **Java Class:** `CA FE BA BE` (compiled Java)
   - If match found → Blocked immediately

3. **Allowlist Check:**
   - Verifies declared MIME type exists in `allowedTypes` configuration
   - Example allowed types:
     - `application/pdf`
     - `image/png`, `image/jpeg`, `image/gif`
     - `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` (XLSX)
     - `text/plain`, `text/csv`
   - If MIME not in allowlist → Blocked

4. **Magic Byte Consistency:**
   - For types with known signatures, verifies file header matches expected pattern
   - Examples:
     - PDF: Must start with `25 50 44 46` (`%PDF`)
     - PNG: Must start with `89 50 4E 47` (PNG signature)
     - JPEG: Must start with `FF D8 FF` (JPEG SOI marker)
   - If mismatch detected (e.g., declared PDF but header is EXE) → Blocked

5. **OpenXML Deep Inspection:**
   - For Office documents (DOCX, XLSX, PPTX):
     - Verifies PK ZIP header (`50 4B 03 04`)
     - Extracts and validates `[Content_Types].xml` from ZIP structure
     - Confirms document contains Office-specific content types
   - Prevents malicious ZIP files disguised as Office documents
   - If validation fails → Blocked

**Enforcement Modes:**

| Mode | Behavior | Use Case |
|------|----------|----------|
| **Block** | Throws `InvalidPluginExecutionException` on violation | Production enforcement (default) |
| **TestWithNotifications** | Logs violation to trace, allows upload | Testing and impact assessment |
| **Disabled** | Skips all validation; plugin returns immediately after context checks | Emergency bypass without unregistering plugin |

**Configuration Loading:**

Plugin reads `MimeConfig.json` from plugin step configuration:
- **Secure Configuration (preferred):** Encrypted storage for production
- **Unsecure Configuration (fallback):** Visible in plugin registration tool

**Error Handling:**

| Error Scenario | Plugin Behavior | User Experience |
|----------------|-----------------|-----------------|
| Invalid Base64 | Block with error message | Upload fails with "Invalid file content" |
| File size exceeded | Block with size limit message | Upload fails with "File too large (limit: 10 MB)" |
| Blocked signature | Block with signature name | Upload fails with "File type not permitted (PE Executable detected)" |
| MIME not in allowlist | Block with MIME type | Upload fails with "File type 'application/x-msdownload' not allowed" |
| Magic byte mismatch | Block with inconsistency details | Upload fails with "File content does not match declared type" |
| OpenXML validation failure | Block with ZIP structure error | Upload fails with "Invalid Office document structure" |

**Trace Logging:**

Plugin writes detailed trace logs for troubleshooting:
```
[FSI-MIME] Plugin invoked. CorrelationId=12345678-abcd-1234-abcd-123456789012
[FSI-MIME] Validating file 'document.pdf', declared MIME='application/pdf'
[FSI-MIME] File size OK: 245,680 bytes
[FSI-MIME] No blocked signatures detected
[FSI-MIME] MIME type 'application/pdf' is in allowlist
[FSI-MIME] Magic bytes match for 'application/pdf'.
[FSI-MIME] Validation PASSED for 'document.pdf'
```

#### Copilot Studio File Upload Scope — 2026-Q2

Current Microsoft Learn guidance distinguishes **agent user file input** from **uploaded knowledge-source files**:

- **User file input** can analyze CSV, PDF, TXT, JPG, PNG, WebP, or nonanimated GIF files. Current limits include images up to 15 MB (4 MB for DirectLine-based channels), PDFs under 40 pages, and TXT/CSV files under 180 KB. Users can't upload files when the agent is published to the SharePoint channel, and files in customer-managed-key environments can be accepted but aren't processed by the agent.
- **Uploaded files as knowledge sources** support document formats such as Word, Excel, PowerPoint, PDF, text, HTML, CSV, XML, OpenDocument, EPUB, RTF, Apple iWork, JSON, YAML, and LaTeX. Standalone image, video, executable, and audio files aren't supported as uploaded knowledge documents; files over 512 MB and encrypted or password-protected files aren't supported.
- The default `mime-config.json` remains intentionally narrower for Enterprise Managed environments. Add WebP, legacy Office, or other supported platform formats only after documenting business need, magic-byte behavior, downstream scanning, and zone-specific risk acceptance.

#### 2. Power Platform Data Policy Reference — dlp-policy-template.json
**File:** `templates/dlp-policy-template.json`

**Purpose:** Conceptual reference for the connector and environment guardrails that should accompany server-side MIME validation. The JSON is **not** a deployable Power Platform DLP export and can't be imported with DLP cmdlets.

**Current Power Platform behavior:**

- Data policies classify connectors into **Business**, **Non-business**, and **Blocked** data groups and can apply to a single environment, an environment group, or the tenant.
- Data policy enforcement applies to Copilot Studio agents for all tenants; legacy agent exemptions aren't supported.
- Copilot Studio data policies govern authoring abilities, channels, knowledge sources, individual connectors, skills, and Application Insights connections. Makers and users can see real-time errors for violations.
- Power Platform DLP doesn't parse file contents, magic bytes, or MIME headers. MIME and extension enforcement for uploaded Dataverse annotations is performed by `ValidateMimeTypePlugin`.
- Policy changes cascade through environments and resources. Microsoft Learn notes most changes apply within about an hour, but full enforcement can take up to 24 hours in large tenants.

**Connector classification checklist:**

1. Identify upload-capable connectors in scope for the target zone, such as HTTP, HTTP with Microsoft Entra ID, custom connectors, FTP, Azure Blob Storage, SharePoint, OneDrive, and other binary payload paths.
2. Keep required Copilot Studio connectors and approved internal data sources in compatible data groups.
3. Move risky or unapproved upload-capable connectors to **Blocked** or **Non-business**, based on the zone's data movement rules.
4. Document why each connector remains allowed and how server-side MIME validation, malware scanning, and monitoring cover residual risk.

**PowerShell support:**

```powershell
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
Import-Module Microsoft.PowerApps.Administration.PowerShell
Add-PowerAppsAccount

Get-AdminDlpPolicy | Format-Table DisplayName, PolicyName
$config = Get-PowerAppDlpPolicyConnectorConfigurations -TenantId $TenantId -PolicyName $PolicyName
# Review $config, then update with a tested DlpPolicyConnectorConfigurationsDefinition object.
Set-PowerAppDlpPolicyConnectorConfigurations -TenantId $TenantId -PolicyName $PolicyName -UpdatedConnectorConfigurations $UpdatedConnectorConfigurations
```

For Microsoft Graph-based automation, prefer managed identities where available:

```powershell
Connect-MgGraph -Identity
# User-assigned managed identity:
Connect-MgGraph -Identity -ClientId "<USER_ASSIGNED_MANAGED_IDENTITY_CLIENT_ID>"
```

Client-secret authentication is a legacy development fallback only and should be replaced with managed identity, workload identity federation, or certificate-based app-only authentication for production automation.

#### 3. MIME Configuration — MimeConfig.json
**File:** `templates/mime-config.json`

**Purpose:** Centralized configuration file for Dataverse plugin validation logic. Defines allowed MIME types, blocked signatures, and validation parameters.

**Configuration Structure:**

```json
{
  "version": "1.2.1",
  "enforcementMode": "Block",
  "maxFileSizeBytes": 10485760,
  "zone": 3,
  "allowedTypes": [ ... ],
  "blockedSignatures": [ ... ]
}
```

**Allowed Types (Examples):**

| MIME Type | Extensions | Magic Bytes | Description |
|-----------|------------|-------------|-------------|
| `application/pdf` | `.pdf` | `25 50 44 46` | Portable Document Format |
| `image/png` | `.png` | `89 50 4E 47` | Portable Network Graphics |
| `image/jpeg` | `.jpg`, `.jpeg` | `FF D8 FF` | JPEG image |
| `image/gif` | `.gif` | `47 49 46 38` | Graphics Interchange Format |
| `text/plain` | `.txt` | `null` | Plain text (validated by absence of binary content) |
| `text/csv` | `.csv` | `null` | Comma-separated values |
| `application/vnd...sheet` | `.xlsx` | `50 4B 03 04` | Excel spreadsheet (OpenXML ZIP) |
| `application/vnd...document` | `.docx` | `50 4B 03 04` | Word document (OpenXML ZIP) |
| `application/vnd...presentation` | `.pptx` | `50 4B 03 04` | PowerPoint presentation (OpenXML ZIP) |

**Blocked Signatures:**

| Signature Name | Magic Bytes | Platform | Risk |
|----------------|-------------|----------|------|
| PE/MS-DOS Executable | `4D 5A` | Windows | Code execution (EXE, DLL, SYS) |
| ELF Executable | `7F 45 4C 46` | Linux | Code execution (binaries) |
| Mach-O 32-bit | `FE ED FA CE` | macOS | Code execution (binaries) |
| Mach-O 64-bit | `FE ED FA CF` | macOS | Code execution (binaries) |
| Mach-O 32-bit (reversed) | `CE FA ED FE` | macOS | Code execution (reversed byte order) |
| Mach-O 64-bit (reversed) | `CF FA ED FE` | macOS | Code execution (reversed byte order) |
| Java Class File | `CA FE BA BE` | JVM | Code execution (compiled Java) |

**Configuration Updates:**

To add new allowed MIME types:

1. Edit `MimeConfig.json`:
   ```json
   {
     "mimeType": "audio/mpeg",
     "extensions": [".mp3"],
     "magicBytes": "49 44 33",
     "description": "MP3 audio file"
   }
   ```

2. Re-register Dataverse plugin with updated configuration
3. Test with sample upload to verify magic byte validation

#### 4. Sentinel Query — query-mime-blocks.kql
**File:** `scripts/query-mime-blocks.kql`

**Purpose:** KQL query for Microsoft Sentinel to aggregate blocked file upload attempts over the past 30 days, grouped by file extension, user, and environment.

**Data Source:**

- **Custom Log:** `PowerPlatformDlpActivity_CL`
- **Standard Log:** `PowerPlatformAdminActivity` (if using Microsoft 365 connector)

**Query Logic:**

```kql
PowerPlatformDlpActivity_CL
| where TimeGenerated > ago(30d)
| where OperationType_s in ("Blocked", "Denied", "BlockedUpload")
    or ActionTaken_s == "Block"
| extend FileExtension = tolower(extract(@"\.([a-zA-Z0-9]+)$", 1, FileName_s))
| where isnotempty(FileExtension)
| summarize
    BlockCount    = count(),
    FirstBlocked  = min(TimeGenerated),
    LastBlocked   = max(TimeGenerated)
    by FileExtension, UserPrincipalName = UserPrincipalName_s, EnvironmentName = EnvironmentName_s
| sort by BlockCount desc
| project FileExtension, UserPrincipalName, EnvironmentName, BlockCount, FirstBlocked, LastBlocked
```

**Output Example:**

| FileExtension | UserPrincipalName | EnvironmentName | BlockCount | FirstBlocked | LastBlocked |
|---------------|-------------------|-----------------|------------|--------------|-------------|
| exe | user1@contoso.com | Finance-Prod | 15 | 2026-01-15 | 2026-02-14 |
| zip | user2@contoso.com | HR-Sandbox | 8 | 2026-01-20 | 2026-02-10 |
| dll | user3@contoso.com | Legal-Dev | 5 | 2026-02-01 | 2026-02-12 |

**Variants:**

**Daily Trend (Time-Series Chart):**
```kql
| summarize BlockCount = count() by FileExtension, bin(TimeGenerated, 1d)
| sort by TimeGenerated asc
| render timechart
```

**Top 10 Most-Blocked Extensions:**
```kql
| summarize BlockCount = count() by FileExtension
| top 10 by BlockCount
```

#### 5. Sentinel Alert — high-volume-blocks.json
**File:** `templates/high-volume-blocks.json`

**Purpose:** Sentinel alert rule that triggers when a user attempts to upload blocked file types more than 10 times in 1 hour, indicating potential attack or policy violation.

**Alert Logic:**

```kql
PowerPlatformDlpActivity_CL
| where OperationType_s in ("Blocked", "Denied", "BlockedUpload") or ActionTaken_s == "Block"
| where TimeGenerated > ago(1h)
| summarize BlockCount = count() by UserPrincipalName = UserPrincipalName_s, EnvironmentName = EnvironmentName_s
| where BlockCount > 10
| project UserPrincipalName, EnvironmentName, BlockCount
```

**Alert Configuration:**

- **Frequency:** Every 1 hour
- **Threshold:** 10 blocked uploads per user per hour
- **Severity:** Medium
- **MITRE ATT&CK:** T1566 (Phishing), T1204 (User Execution)
- **Response:** Create incident, notify security operations team

**Incident Actions:**

1. Review user's blocked upload history
2. Identify file extensions attempted (EXE, DLL, etc.)
3. Contact user to determine intent (legitimate need vs. malicious)
4. If malicious: Disable user account, investigate compromise
5. If legitimate: Create exception request with business justification

#### 6. Sentinel Query — query-exception-usage.kql
**File:** `scripts/query-exception-usage.kql`

**Purpose:** KQL query to track exception usage patterns for governance review and policy tuning.

**Query Logic:**

```kql
PowerPlatformDlpActivity_CL
| where TimeGenerated > ago(90d)
| where MimeType_s in (ExceptionMimeTypes)
| where OperationType_s in ("Upload", "Allowed", "AllowedUpload")
    or ActionTaken_s == "Allow"
| summarize
    UploadCount   = count(),
    DistinctUsers = dcount(UserPrincipalName_s),
    FirstUpload   = min(TimeGenerated),
    LastUpload    = max(TimeGenerated)
    by MimeType = MimeType_s, EnvironmentName = EnvironmentName_s
| sort by UploadCount desc
```

**Use Cases:**

- **Quarterly Review:** Identify exceptions used frequently (candidates for allowlist addition)
- **Policy Tuning:** Determine if MIME restrictions are too strict (high exception usage)
- **Compliance Validation:** Verify exceptions are used appropriately (not abused)

### Configuration and Prerequisites

#### Prerequisites

**Microsoft 365 Licensing:**
- Microsoft 365 E5 or E5 Compliance (for DLP policies and Sentinel)
- Power Platform Admin permissions
- Power Apps Premium (for Dataverse)

**Permissions:**

| Role/Permission | Required For | Scope |
|-----------------|--------------|-------|
| **Dataverse System Administrator** | Plugin registration | Per-environment |
| **Power Platform Admin** | Data policy creation and management | Tenant-wide |
| **Security Reader** | Sentinel query execution | Log Analytics workspace |
| **Security Administrator** | Sentinel alert rule creation | Sentinel workspace |

**Tools:**

| Tool | Version | Purpose |
|------|---------|---------|
| **Plugin Registration Tool** | Latest | Register Dataverse plugin |
| **Visual Studio** | 2019+ | Build plugin DLL from C# source |
| **PowerShell** | 7.2+ | Review or update data policy connector classifications |
| **Azure portal** | N/A | Configure Sentinel queries and alerts |

#### Configuration Steps

**Step 1: Build Dataverse Plugin**

1. Open Visual Studio → Create new Class Library (.NET Framework 4.6.2)
2. Add NuGet packages:
   - `Microsoft.CrmSdk.CoreAssemblies` (9.0.2+)
   - `System.Text.Json` (8.0.5 or later in the 8.x line) — must be ILRepack-merged into the plugin assembly for Dataverse sandbox deployment
3. Add project reference to `System.IO.Compression` assembly (required for OpenXML deep inspection)
4. Copy `ValidateMimeTypePlugin.cs` to project
5. Build solution → Output: `FsiAgentGovernance.Plugins.dll`

**Step 2: Register Dataverse Plugin**

1. Download Plugin Registration Tool from [Microsoft](https://www.nuget.org/packages/Microsoft.CrmSdk.XrmTooling.PluginRegistrationTool/)
2. Connect to Dataverse environment
3. **Register New Assembly:**
   - Click **Register** → **Register New Assembly**
   - Select `FsiAgentGovernance.Plugins.dll`
   - Isolation Mode: **Sandbox**
   - Location: **Database**
4. **Register New Step (Create):**
   - **Message:** `Create`
   - **Primary Entity:** `annotation`
   - **Event Pipeline Stage:** Pre-Validation (10)
   - **Execution Mode:** Synchronous
   - **Configuration:**
     - **Unsecure Configuration:** Paste full contents of `MimeConfig.json`
     - **Secure Configuration:** (Optional) Same as unsecure for encrypted storage
   - **Filtering Attributes:** `documentbody, mimetype, filename`
5. **Register New Step (Update):**
   - **Message:** `Update`
   - **Primary Entity:** `annotation`
   - **Event Pipeline Stage:** Pre-Validation (10)
   - **Execution Mode:** Synchronous
   - **Configuration:** Same as Create step
   - **Filtering Attributes:** `documentbody, mimetype`
6. **Register a Pre-Image on the Update step** (REQUIRED — without this,
   updates that don't include the `mimetype` and `filename` columns will
   be fail-secure-blocked by the plugin):
   - Right-click the new Update step → **Register New Image**
   - **Image Type:** Pre Image
   - **Name:** `PreImage` (case-sensitive — the plugin looks up
     `context.PreEntityImages["PreImage"]`)
   - **Entity Alias:** `PreImage`
   - **Parameters / Attributes:** `mimetype, filename`
7. Click **Register New Step** for each (and the Pre Image for the Update step)

**Step 2 (Alternative): Register Plugin using PAC CLI**

`pac plugin` is intended for low-code plugin scaffolding via
`pac plugin init`; it does not currently expose commands to register a
compiled .NET Framework Dataverse plugin assembly or its steps.
**Use the Plugin Registration Tool (PRT)** described in Step 2 above
for this solution. There is no supported PAC CLI alternative for
registering plugin steps and pre-images on the `annotation` table at
this time.

If you want a CLI-driven workflow for CI/CD, package the plugin and
its registration into a Dataverse solution (`.zip`) once via PRT,
then promote it across environments using `pac solution import`.

**Step 3: Translate DLP Reference Template into Connector Classifications**

The file at `templates/dlp-policy-template.json` is a **conceptual
reference** describing the intended MIME / extension restrictions —
**it cannot be imported directly**. Power Platform DLP operates on
*connectors*, not on file extensions or MIME types. Use the reference
as a checklist when configuring connector classifications:

1. Review the extension and MIME-type lists in
   `templates/dlp-policy-template.json` and identify which **connectors**
   in your tenant could be used to upload content of those types
   (e.g., HTTP, custom connectors, FTP, file-system connectors).
2. In the Power Platform admin center → **Policies** → **Data policies**,
   create or edit the data policy targeting your Zone 2 / Zone 3
   environments.
3. Move risky connectors into the **Blocked** or **Non-business**
   group as required by your zone policy.
4. (Optional) Use PowerShell to review or update connector
   configurations once the policy exists:
   ```powershell
   Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
   Import-Module Microsoft.PowerApps.Administration.PowerShell
   Add-PowerAppsAccount
   Get-AdminDlpPolicy | Format-Table DisplayName, PolicyName
   $config = Get-PowerAppDlpPolicyConnectorConfigurations -TenantId $TenantId -PolicyName $PolicyName
   # Update with a tested DlpPolicyConnectorConfigurationsDefinition object.
   Set-PowerAppDlpPolicyConnectorConfigurations -TenantId $TenantId -PolicyName $PolicyName -UpdatedConnectorConfigurations $UpdatedConnectorConfigurations
   ```

The actual server-side MIME enforcement is performed by the
ValidateMimeType plugin registered in Step 2; this data policy layer is
defence-in-depth for the upload connectors themselves.

**Step 4: Deploy Sentinel Queries**

1. Navigate to **Microsoft Sentinel** → **Logs**
2. Paste `query-mime-blocks.kql` → Click **Save as function**
3. **Function Name:** `MimeTypeBlocks`
4. **Category:** Power Platform Governance
5. Repeat for `query-exception-usage.kql` (function name: `MimeExceptionUsage`)

**Step 5: Create Sentinel Alert Rule**

1. Navigate to **Microsoft Sentinel** → **Analytics** → **+ Create** → **Scheduled query rule**
2. **Name:** High-Volume MIME Type Block Attempts
3. **Tactics:** Initial Access (T1566), Execution (T1204)
4. **Severity:** Medium
5. **Rule query:** Paste the KQL query from the `query` property inside `high-volume-blocks.json` (not the entire ARM template)
6. **Query scheduling:**
   - **Run query every:** 1 hour
   - **Lookup data from the last:** 1 hour
7. **Alert threshold:** Generate alert when query results > 0
8. **Event grouping:** Group all events into a single alert
9. **Incident settings:**
   - **Create incidents:** Enabled
   - **Alert grouping:** Enabled (group by Account entity, 5-hour lookback)
10. Click **Create**

### Deployment Validation

**Test 1: Allowed MIME Type (PDF)**

1. Create test Copilot Studio agent with file upload action
2. Upload legitimate PDF file (e.g., `test-document.pdf`)
3. **Expected Result:**
   - Upload succeeds
   - Plugin trace log shows: `[FSI-MIME] Validation PASSED for 'test-document.pdf'`
4. Verify annotation record created in Dataverse

**Test 2: Blocked Signature (EXE)**

1. Attempt to upload Windows executable (e.g., `notepad.exe`)
2. **Expected Result:**
   - Upload fails with error: "File 'notepad.exe' matches blocked signature 'PE/MS-DOS Executable'"
   - Plugin trace log shows: `[FSI-MIME] VIOLATION: File 'notepad.exe' matches blocked signature 'PE/MS-DOS Executable'. This file type is not permitted in Zone 3 environments. Contact your administrator if you believe this is in error. (CorrelationId=<guid>)`
3. Verify no annotation record created

**Test 3: MIME Type Not in Allowlist (ZIP)**

1. Attempt to upload ZIP archive (e.g., `archive.zip`)
2. **Expected Result:**
   - Upload fails with error: "File type 'application/zip' is not in the allowed list for Zone 3 environments"
   - Plugin trace log shows: `[FSI-MIME] VIOLATION: MIME type 'application/zip' for file 'archive.zip' is not in the Zone 3 allowed list. Review the allowed types configuration or contact your administrator. (CorrelationId=<guid>)`

**Test 4: Magic Byte Mismatch (Disguised GIF as PDF)**

1. Take any GIF image file and rename it to `fake-document.pdf`
2. Attempt to upload with declared MIME type `application/pdf`
3. **Expected Result:**
   - Upload fails with error: "File 'fake-document.pdf' declares MIME type 'application/pdf' but its content header does not match the expected magic bytes for that type. The file may have been renamed or corrupted."
   - Plugin trace log shows: `[FSI-MIME] VIOLATION: File 'fake-document.pdf' declares MIME type 'application/pdf' but its content header does not match the expected magic bytes for that type.`

**Test 5: Power Platform Data Policy Connector Guardrail**

1. In a non-production environment, classify a risky upload-capable connector as **Blocked** or place it in an incompatible data group.
2. Attempt to save or run an agent action or flow that uses that connector with Copilot Studio.
3. **Expected Result:**
   - Maker or runtime experience shows a data policy violation for the connector.
   - MIME and magic-byte enforcement remains the responsibility of the Dataverse plugin when files reach `annotation` records.
4. Query Sentinel with `query-mime-blocks.kql` to verify plugin or data policy telemetry is flowing for blocked upload events where available.

**Test 6: Sentinel Alert Trigger**

1. Simulate high-volume attack: Attempt to upload EXE file 15 times in 10 minutes
2. Wait up to 1 hour for alert rule execution (query frequency is PT1H)
3. **Expected Result:**
   - Sentinel incident created: "High-Volume MIME Type Block Attempts"
   - Incident details show user, block count, file extension
4. Review incident and close with "True Positive - Attack"

### Operational Guidance

#### Daily Operations

**Monitoring:**
- Review Sentinel dashboard for blocked upload trends
- Investigate high-volume block alerts (>10 attempts per user per hour)
- Track exception usage patterns monthly

**Incident Response:**

| Alert Type | Priority | Action | Timeline |
|------------|----------|--------|----------|
| **High-volume blocks (same user)** | High | Investigate user intent, check for compromise | Same day |
| **Blocked executable uploads** | Medium | Review user context, contact for justification | 2 business days |
| **Exception abuse** | Low | Quarterly review, validate business need | 30 days |

**Policy Tuning:**

Based on Sentinel query results, adjust MIME type allowlist:

1. **Frequent Legitimate Blocks:**
   - Query: `MimeExceptionUsage | where ExceptionCount > 50`
   - Action: Add MIME type to `MimeConfig.json` allowlist if justified
   - Example: Organization frequently uploads MP3 audio files for training → Add `audio/mpeg`

2. **Zero Blocks for Allowed Type:**
   - Query: Review allowlist against actual usage (Dataverse annotations)
   - Action: Remove unused MIME types from allowlist (reduce attack surface)

3. **New File Type Requests:**
   - Require business justification document
   - Validate magic byte signature exists
   - Add to `MimeConfig.json` with magic byte pattern
   - Re-register plugin with updated configuration

#### Rollback Procedure

If the MIME Type Restrictions plugin causes issues in production, use one of the following options to disable enforcement:

**Option 1: Disable Plugin Step (Recommended)**

1. Open Plugin Registration Tool
2. Connect to your Dataverse environment
3. Navigate to `FsiAgentGovernance.Plugins` assembly
4. Find the step `ValidateMimeTypePlugin: Create of annotation`
5. Right-click → **Disable**
6. The plugin stops processing but remains registered for quick re-enablement

> This is the recommended approach — it allows immediate re-enablement after troubleshooting without re-registration.

**Option 2: Switch to TestWithNotifications Mode**

1. Edit `MimeConfig.json`
2. Change `"enforcementMode": "Block"` to `"enforcementMode": "TestWithNotifications"`
3. Update the plugin step configuration in Plugin Registration Tool:
   - Right-click step → **Update**
   - Paste updated `MimeConfig.json` into unsecure configuration
4. Upload violations will be logged to plugin trace but not blocked

**Option 3: Unregister Plugin (Emergency Only)**

1. Open Plugin Registration Tool
2. Select the `FsiAgentGovernance.Plugins` assembly
3. Click **Unregister** → Confirm deletion
4. The plugin and all steps are permanently removed

> **Warning:** Unregistering requires full re-registration to restore. Use only when Options 1-2 are insufficient.

#### Troubleshooting

**Issue: Plugin not triggering on file uploads**

**Cause:** Plugin step not registered or inactive

**Resolution:**
1. Open Plugin Registration Tool → Connect to environment
2. Navigate to registered assemblies → Verify `FsiAgentGovernance.Plugins` exists
3. Expand assembly → Verify `ValidateMimeTypePlugin: Create of annotation` step exists
4. Check step status: Should show as **Active**
5. If inactive, right-click → **Activate**

**Issue: Allowed MIME type is blocked**

**Cause:** MIME type missing from `MimeConfig.json` allowlist

**Resolution:**
1. Review plugin trace logs for blocked MIME type
2. Edit `MimeConfig.json` → Add missing MIME type to `allowedTypes` array
3. Re-register plugin step with updated configuration:
   - Plugin Registration Tool → Expand assembly → Right-click step → **Update**
   - Paste updated `MimeConfig.json` to unsecure configuration
4. Test with sample upload

**Issue: Magic byte validation fails for valid file**

**Cause:** File has non-standard header or configuration has incorrect magic byte pattern

**Resolution:**
1. Extract first 16 bytes of file:
   ```powershell
   $bytes = [System.IO.File]::ReadAllBytes("C:\path\to\file.pdf")
   $header = $bytes[0..15] | ForEach-Object { $_.ToString("X2") }
   Write-Output ($header -join " ")
   ```
2. Compare with configured magic byte pattern in `MimeConfig.json`
3. If pattern mismatch:
   - Verify file is legitimate (not corrupted or malicious)
   - Update `MimeConfig.json` with correct pattern (or add alternate pattern)
   - Example TIFF: Supports little-endian (`49 49 2A 00`) and big-endian (`4D 4D 00 2A`)

**Issue: Sentinel queries return no results**

**Cause:** Dataverse audit logs not flowing to Sentinel workspace

**Resolution:**
1. Verify Dataverse diagnostic settings:
   - Power Platform admin center → Environments → Settings → Audit and logs
   - **Start Auditing:** Enabled
   - **Send to Log Analytics:** Enabled
2. Check Log Analytics workspace connection:
   - Azure portal → Log Analytics workspace → Agents → Connected sources
   - Verify Dataverse connector is active
3. Wait 15 minutes for log ingestion
4. Re-run query

**Issue: Data policy doesn't limit risky upload connectors**

**Cause:** Connector remains in an allowed data group, the policy targets the wrong environment, or policy propagation hasn't completed.

**Resolution:**
1. Navigate to Power Platform admin center → **Policies** → **Data policies**.
2. Select the data policy that targets the affected environment or environment group.
3. Review the relevant Copilot Studio, HTTP, custom connector, SharePoint, OneDrive, Azure Blob Storage, and other upload-capable connectors.
4. Move risky or unapproved connectors to **Blocked** or **Non-business** as required by the zone policy.
5. Save the policy and allow propagation. Most changes apply within about an hour, but large tenants can take up to 24 hours.
6. Test connector policy behavior separately from MIME validation. The Dataverse plugin remains the control that blocks disallowed MIME types and magic-byte mismatches.

#### Audit and Evidence Export

**Evidence Collection:**

For regulatory examinations, export blocked upload evidence:

**Dataverse Plugin Trace Logs:**
```powershell
# Export plugin trace logs (last 90 days)
$traces = Get-CrmRecords -EntityLogicalName "plugintracelog" -FilterAttribute "createdon" -FilterOperator "last-x-days" -FilterValue 90
$traces.CrmRecords | Export-Csv -Path "./plugin-trace-logs.csv" -NoTypeInformation
```

**Sentinel Blocked Upload Events:**
```kql
PowerPlatformDlpActivity_CL
| where TimeGenerated > ago(90d)
| where OperationType_s in ("Blocked", "Denied", "BlockedUpload")
| project TimeGenerated, UserPrincipalName_s, FileName_s, MimeType_s, EnvironmentName_s
| sort by TimeGenerated desc
```

Export to CSV via Sentinel portal → **Export** → **CSV**

**Data Policy Configuration:**
1. Navigate to Power Platform admin center → Policies → Data policies
2. Export or document the policy connector classifications and scope
3. Include in evidence package

**Retention:**

- Plugin trace logs: Retain for 3 years (operational history)
- Sentinel blocked events: Retain for 7 years (SEC 17a-4 requirement)
- Data policy definitions: Retain for 7 years (audit trail requirement)

---

## Appendix: Magic Byte Reference

### Common File Type Signatures

| File Type | MIME Type | Magic Bytes (Hex) | ASCII Representation |
|-----------|-----------|-------------------|----------------------|
| **PDF** | `application/pdf` | `25 50 44 46` | `%PDF` |
| **PNG** | `image/png` | `89 50 4E 47` | `.PNG` (4-byte prefix; full signature is `89 50 4E 47 0D 0A 1A 0A` but the 4-byte prefix is sufficient for unique identification) |
| **JPEG** | `image/jpeg` | `FF D8 FF` | `ÿØÿ` |
| **GIF (87a)** | `image/gif` | `47 49 46 38 37 61` | `GIF87a` |
| **GIF (89a)** | `image/gif` | `47 49 46 38 39 61` | `GIF89a` |
| **TIFF (LE)** | `image/tiff` | `49 49 2A 00` | `II*.` |
| **TIFF (BE)** | `image/tiff` | `4D 4D 00 2A` | `MM.*` |
| **ZIP** | `application/zip` | `50 4B 03 04` | `PK..` |
| **Office (DOCX/XLSX/PPTX)** | `application/vnd...` | `50 4B 03 04` | `PK..` (ZIP-based) |
| **RAR** | `application/x-rar-compressed` | `52 61 72 21` | `Rar!` |
| **7-Zip** | `application/x-7z-compressed` | `37 7A BC AF 27 1C` | `7z¼¯'.` |

### Blocked Executable Signatures

| Signature Name | Magic Bytes (Hex) | Platform | File Types |
|----------------|-------------------|----------|------------|
| **PE/MS-DOS** | `4D 5A` | Windows | EXE, DLL, SYS, COM, SCR |
| **ELF** | `7F 45 4C 46` | Linux/Unix | Binary executables |
| **Mach-O 32-bit** | `FE ED FA CE` | macOS | Binary executables |
| **Mach-O 64-bit** | `FE ED FA CF` | macOS | Binary executables |
| **Mach-O 32-bit (rev)** | `CE FA ED FE` | macOS | Reversed byte order |
| **Mach-O 64-bit (rev)** | `CF FA ED FE` | macOS | Reversed byte order |
| **Java Class** | `CA FE BA BE` | JVM | Compiled Java (.class) |
| **Windows Script** | `4D 5A` (if compiled) | Windows | VBS, JS (if WSF/WSH) |

**Note:** Text-based scripts (PS1, BAT, VBS, JS) have no magic bytes but can be detected by MIME type filtering (`application/x-powershell`, `application/x-bat`).

---

## Appendix: Regulatory Alignment

The MIME Type Restrictions solution supports compliance with the following regulatory requirements:

### NIST 800-53 SI-3 — Malicious Code Protection

**Requirement:** Information systems must employ malicious code protection mechanisms at information system entry and exit points to detect and eradicate malicious code.

**Solution Support:**
- Server-side plugin validates file uploads at system entry point (Dataverse annotation creation)
- Blocked signature scan detects known executable file types (PE, ELF, Mach-O, Java)
- Magic byte inspection prevents disguised malicious files (EXE renamed to PDF)

### FINRA 3110 — Supervision

**Requirement:** Member firms must establish and maintain a system to supervise the activities of associated persons, including technology controls for data uploads and transfers.

**Solution Support:**
- Data policies constrain upload-capable connectors across Copilot Studio environments
- Sentinel monitoring detects high-volume upload attempts (potential policy violation or attack)
- Audit trail provides evidence of supervisory controls effectiveness

### SEC 17a-4 — Recordkeeping

**Requirement:** Broker-dealers must make and preserve records related to business operations, including electronic communications and data transfers.

**Solution Support:**
- Dataverse plugin trace logs capture all file upload validation events
- Sentinel logs provide immutable record of blocked upload attempts
- DLP audit logs capture policy enforcement actions (Block, Audit, Exception)

---

## Support and Maintenance

**Solution Version:** 1.2.1
**Release Date:** April 2026
**License:** MIT License

**Change Management:**
- Test `MimeConfig.json` changes in non-production environment first
- Document MIME type additions in change tickets with business justification
- Review magic byte patterns quarterly for accuracy
- Coordinate data policy updates with business unit stakeholders (advance notice recommended)

**Version History:**
- **v1.2.1 (Unreleased):** Microsoft Learn 2026-Q2 refresh for Copilot Studio file input, Power Platform data policies, PowerShell cmdlets, and manifest control coverage
- **v1.0.2 (April 2026):** KQL field name standardization, rollback procedure, PAC CLI docs, design decision documentation, PowerShell module reference
- **v1.0.0 (February 2026):** Initial release with Dataverse plugin, DLP template, and Sentinel queries

---

## Design Decisions

### Intentionally Excluded File Types

The following file types are intentionally excluded from the default allowlist. Organizations may add them with appropriate risk acceptance.

**Legacy Office Formats (.doc, .xls, .ppt)**

Legacy Office files use the OLE Compound File Binary Format, which can contain embedded macros and ActiveX controls. These formats present a higher risk of malicious code execution compared to modern OpenXML formats (DOCX, XLSX, PPTX), which separate content from code. If your organization requires legacy format support, add entries with the shared magic bytes `D0 CF 11 E0 A1 B1 1A E1` and ensure macro scanning is enabled upstream.

**SVG Files (.svg)**

SVG (Scalable Vector Graphics) files are XML-based and can contain embedded JavaScript, making them a vector for cross-site scripting (XSS) attacks when rendered in web contexts. If your organization requires SVG support, implement SVG sanitization (stripping `<script>` tags and event handlers) before rendering in any web-facing application.

### Rate Limiting Architecture

Rate limiting is intentionally handled at the Sentinel monitoring layer (Layer 3) rather than in the Dataverse plugin (Layer 2). The high-volume-blocks alert rule detects patterns of >10 blocked attempts per user per hour and creates a Sentinel incident. This design avoids plugin complexity and leverages Sentinel's incident management, correlation, and response capabilities.

---

## PowerShell Module (Optional Component)

The **FsiMimeControl** PowerShell module provides additional management capabilities for MIME type restrictions beyond the core plugin and data policy reference. It is maintained in the FSI-AgentGov repository under `scripts/governance/`.

### Functionality

- Bulk MIME type configuration management across environments
- Plugin deployment validation and health checks
- Configuration comparison between zone templates (Zone 1, 2, 3)
- Exception register management and reporting

### Installation

1. Download `FsiMimeControl.psm1` from the FSI-AgentGov repository: `scripts/governance/FsiMimeControl.psm1`
2. Import the module:
   ```powershell
   Import-Module .\FsiMimeControl.psm1
   ```

### Zone Templates

Pre-configured MIME type templates for each governance zone are available at:
- `scripts/governance/mime-templates/zone1.json` — Personal Productivity (broadest allowlist)
- `scripts/governance/mime-templates/zone2.json` — Team Collaboration (moderate restrictions)
- `scripts/governance/mime-templates/zone3.json` — Enterprise Managed (strictest allowlist)

### Relationship to This Solution

The FsiMimeControl module is **optional** — the core solution (plugin, data policy reference, Sentinel queries) operates independently. The module adds operational convenience for organizations managing MIME restrictions across multiple environments or zones.

For detailed usage instructions, see the FSI-AgentGov documentation for Control 1.25.

---

*This solution supports compliance with NIST 800-53 SI-3, FINRA 4511, and SEC 17a-4. Consult with your compliance and legal teams for applicability to your organization's regulatory requirements.*
