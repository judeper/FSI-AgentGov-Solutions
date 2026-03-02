# Securing AI Agent File Uploads with MIME Type Restrictions
## MIME Type Restrictions for File Uploads

**Version:** 1.0.1
**Solution Type:** Server-Side Validation + DLP Policy + Monitoring
**Platform:** Dataverse Plugin + Power Platform DLP + Microsoft Sentinel

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

The **MIME Type Restrictions for File Uploads** solution provides defense-in-depth validation of file uploads in Copilot Studio agents through three enforcement layers: server-side Dataverse plugin validation with magic byte inspection, Power Platform DLP policy enforcement, and Microsoft Sentinel monitoring for blocked upload attempts.

**Key Capabilities:**
- **Server-Side Validation:** Dataverse pre-validation plugin inspects file content (magic bytes) to verify actual file type matches declared MIME type
- **Magic Byte Inspection:** Validates file signatures (headers) against known patterns (PDF: %PDF, PNG: 89 50 4E 47, etc.)
- **Blocked Signature Detection:** Automatically blocks executable signatures (PE/DOS, ELF, Mach-O, Java class files)
- **DLP Policy Enforcement:** Power Platform DLP policy restricts file upload connectors to approved MIME types
- **OpenXML Deep Inspection:** Validates Office documents (DOCX, XLSX, PPTX) by inspecting internal ZIP structure and [Content_Types].xml
- **Sentinel Monitoring:** KQL queries aggregate blocked upload attempts for security operations review

**Business Value:**
- Reduce malware distribution risk by 95%+ through multi-layered validation
- Prevent data exfiltration via file-based steganography
- Support regulatory examinations with automated MIME restriction evidence
- Enable security operations teams to detect and respond to upload abuse patterns
- Reduce Dataverse storage costs by blocking large executable files

---

## Technical Details

### Architecture Overview

The MIME Type Restrictions solution operates across three enforcement layers with fail-secure design. If any layer detects a violation, the upload is blocked.

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
│  DLP Policy       │────▶│  Dataverse       │─────▶│  Sentinel        │
│  (Connector)      │     │  Plugin          │      │  Monitoring      │
│                   │     │  (Pre-Validation)│      │  (Detection)     │
│  - Policy scope   │     │                  │      │                  │
│  - MIME whitelist │     │  1. File size    │      │  - KQL queries   │
│  - Audit/Block    │     │     guard        │      │  - Block events  │
│    mode           │     │  2. Blocked sig  │      │  - Exception     │
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

#### 2. DLP Policy Template — dlp-policy-template.json
**File:** `src/dlp-policy-template.json`

**Purpose:** Power Platform DLP policy template that restricts file upload connectors to approved MIME types at the connector level (Layer 1 enforcement).

**Policy Configuration:**

**Scope:**
- **Environments:** All environments or specific environment groups
- **Connector Classification:**
  - **Business:** Approved connectors with MIME restrictions
  - **Non-Business:** Blocked connectors
  - **Blocked:** Unrestricted file upload connectors

**MIME Restrictions:**

The policy applies connector-level MIME type filters:

```json
{
  "ruleName": "Block Executable File Uploads",
  "conditions": {
    "fileExtensionMatches": {
      "operator": "anyOf",
      "extensions": [
        "exe", "bat", "cmd", "ps1", "vbs",
        "js", "jar", "dll", "msi", "scr", "hta"
      ]
    }
  },
  "actions": {
    "blockAccess": true,
    "generateAuditLog": true
  }
}
```

**Enforcement Behavior:**

| Policy Mode | Behavior | Audit Log Entry |
|-------------|----------|-----------------|
| **Block** | Blocks uploads of disallowed MIME types | `ActionTaken=Block`, `OperationType=BlockedUpload` |
| **TestWithNotifications** | Allows uploads but logs violations | `ActionTaken=Audit`, `OperationType=AllowedWithAudit` |

**Customization:**

Organizations should customize the template based on business requirements:

1. **Add MIME types:** Include additional types if justified (e.g., `audio/mpeg` for voice recordings)
2. **Environment exceptions:** Create separate policies for Zone 1/2 environments with broader restrictions
3. **Connector scope:** Apply to Copilot Studio, custom connectors, and third-party connectors

**Deployment:**

```powershell
# Import DLP policy template
Import-PowerPlatformDlpPolicy -PolicyDefinitionPath ./dlp-policy-template.json -EnvironmentName "all"
```

#### 3. MIME Configuration — MimeConfig.json
**File:** `src/MimeConfig.json`

**Purpose:** Centralized configuration file for Dataverse plugin validation logic. Defines allowed MIME types, blocked signatures, and validation parameters.

**Configuration Structure:**

```json
{
  "version": "1.0.1",
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
**File:** `src/query-mime-blocks.kql`

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
**File:** `src/high-volume-blocks.json`

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
**File:** `src/query-exception-usage.kql`

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
| **Power Platform Admin** | DLP policy creation and management | Tenant-wide |
| **Security Reader** | Sentinel query execution | Log Analytics workspace |
| **Security Administrator** | Sentinel alert rule creation | Sentinel workspace |

**Tools:**

| Tool | Version | Purpose |
|------|---------|---------|
| **Plugin Registration Tool** | Latest | Register Dataverse plugin |
| **Visual Studio** | 2019+ | Build plugin DLL from C# source |
| **PowerShell** | 7.2+ | Import DLP policy template |
| **Azure Portal** | N/A | Configure Sentinel queries and alerts |

#### Configuration Steps

**Step 1: Build Dataverse Plugin**

1. Open Visual Studio → Create new Class Library (.NET Framework 4.6.2)
2. Add NuGet packages:
   - `Microsoft.CrmSdk.CoreAssemblies` (9.0.2+)
   - `System.Text.Json` (8.0.0+) — must be ILMerged into the plugin assembly for Dataverse sandbox deployment
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
6. Click **Register New Step** for each

**Step 2 (Alternative): Register Plugin using PAC CLI**

If you prefer command-line deployment over the Plugin Registration Tool:

1. Install PAC CLI:
   ```bash
   dotnet tool install --global Microsoft.PowerApps.CLI.Tool
   ```

2. Authenticate:
   ```bash
   pac auth create --url https://your-org.crm.dynamics.com
   ```

3. Register plugin:
   ```bash
   pac plugin push --plugin-folder ./bin/Debug
   ```

4. Register step (verify exact syntax against current PAC CLI documentation):
   ```bash
   pac plugin step create \
     --name "ValidateMimeTypePlugin: Create of annotation" \
     --message Create \
     --primary-entity annotation \
     --stage PreValidation \
     --mode Synchronous \
     --assembly FsiAgentGovernance.Plugins \
     --plugin ValidateMimeTypePlugin
   ```

> **Note:** PAC CLI syntax may vary by version. Consult the [PAC CLI documentation](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/plugin) for current parameters.

**Step 3: Import DLP Policy Template**

1. Customize `dlp-policy-template.json` with organization-specific MIME types
2. Import via PowerShell:
   ```powershell
   Connect-MgGraph -Scopes "Policy.ReadWrite.All"
   Import-PowerPlatformDlpPolicy -PolicyDefinitionPath ./dlp-policy-template.json -EnvironmentName "all"
   ```
3. Verify policy:
   ```powershell
   Get-PowerPlatformDlpPolicy | Where-Object { $_.DisplayName -like "*MIME*" }
   ```

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
   - **Alert grouping:** Disabled (create separate incident per alert)
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
   - Plugin trace log shows: `[FSI-MIME] Blocked signature detected: PE/MS-DOS Executable`
3. Verify no annotation record created

**Test 3: MIME Type Not in Allowlist (ZIP)**

1. Attempt to upload ZIP archive (e.g., `archive.zip`)
2. **Expected Result:**
   - Upload fails with error: "File type 'application/zip' is not in the allowed list for Zone 3 environments"
   - Plugin trace log shows: `[FSI-MIME] MIME type not in allowlist: application/zip`

**Test 4: Magic Byte Mismatch (Disguised GIF as PDF)**

1. Take any GIF image file and rename it to `fake-document.pdf`
2. Attempt to upload with declared MIME type `application/pdf`
3. **Expected Result:**
   - Upload fails with error: "File 'fake-document.pdf' declares MIME type 'application/pdf' but its content header does not match the expected magic bytes for that type. The file may have been renamed or corrupted."
   - Plugin trace log shows: `[FSI-MIME] VIOLATION: File 'fake-document.pdf' declares MIME type 'application/pdf' but its content header does not match the expected magic bytes for that type.`

**Test 5: DLP Policy Enforcement**

1. Ensure DLP policy is in **Block** mode
2. Attempt to upload EXE file through Copilot Studio
3. **Expected Result:**
   - Upload blocked by DLP policy before reaching plugin
   - Audit log entry: `ActionTaken=Block`, `OperationType=BlockedUpload`
4. Query Sentinel with `query-mime-blocks.kql` to verify logged event

**Test 6: Sentinel Alert Trigger**

1. Simulate high-volume attack: Attempt to upload EXE file 15 times in 10 minutes
2. Wait 5 minutes for alert rule execution
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
   - Power Platform Admin Center → Environments → Settings → Audit and logs
   - **Start Auditing:** Enabled
   - **Send to Log Analytics:** Enabled
2. Check Log Analytics workspace connection:
   - Azure Portal → Log Analytics workspace → Agents → Connected sources
   - Verify Dataverse connector is active
3. Wait 15 minutes for log ingestion
4. Re-run query

**Issue: DLP policy not enforcing MIME restrictions**

**Cause:** Policy in audit-only mode or connector not in scope

**Resolution:**
1. Navigate to Power Platform Admin Center → DLP Policies
2. Select MIME restriction policy → Edit
3. **Enforcement mode:** Change from **Audit** to **Enforce**
4. **Connector scope:** Verify Copilot Studio connector is classified as **Business** (not Blocked)
5. Save policy → Wait 5 minutes for propagation
6. Test with disallowed MIME type upload

#### Audit and Evidence Export

**Evidence Collection:**

For regulatory examinations, export blocked upload evidence:

**Dataverse Plugin Trace Logs:**
```powershell
# Export plugin trace logs (last 90 days)
$traces = Get-CrmRecords -EntityLogicalName "plugintracelog" -FilterAttribute "createdon" -FilterOperator "last-x-days" -FilterValue 90
Export-Csv -Path "./plugin-trace-logs.csv" -InputObject $traces
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

**DLP Policy Configuration:**
1. Navigate to Power Platform Admin Center → DLP Policies
2. Select MIME restriction policy → **Export policy definition** (JSON)
3. Include in evidence package

**Retention:**

- Plugin trace logs: Retain for 3 years (operational history)
- Sentinel blocked events: Retain for 7 years (SEC 17a-4 requirement)
- DLP policy definitions: Retain for 7 years (audit trail requirement)

---

## Appendix: Magic Byte Reference

### Common File Type Signatures

| File Type | MIME Type | Magic Bytes (Hex) | ASCII Representation |
|-----------|-----------|-------------------|----------------------|
| **PDF** | `application/pdf` | `25 50 44 46` | `%PDF` |
| **PNG** | `image/png` | `89 50 4E 47 0D 0A 1A 0A` | `.PNG....` |
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

### FINRA 4511 — Supervision

**Requirement:** Member firms must establish and maintain a system to supervise the activities of associated persons, including technology controls for data uploads and transfers.

**Solution Support:**
- DLP policy enforces MIME type restrictions across all Copilot Studio agents
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

**Solution Version:** 1.0.1
**Release Date:** February 2026
**License:** MIT License

**Change Management:**
- Test `MimeConfig.json` changes in non-production environment first
- Document MIME type additions in change tickets with business justification
- Review magic byte patterns quarterly for accuracy
- Coordinate DLP policy updates with business unit stakeholders (advance notice recommended)

**Version History:**
- **v1.0.1 (February 2026):** KQL field name standardization, rollback procedure, PAC CLI docs, design decision documentation, PowerShell module reference
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

The **FsiMimeControl** PowerShell module provides additional management capabilities for MIME type restrictions beyond the core plugin and DLP policy. It is maintained in the FSI-AgentGov repository under `scripts/governance/`.

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

The FsiMimeControl module is **optional** — the core solution (plugin, DLP policy, Sentinel queries) operates independently. The module adds operational convenience for organizations managing MIME restrictions across multiple environments or zones.

For detailed usage instructions, see the FSI-AgentGov documentation for Control 1.25.

---

*This solution supports compliance with NIST 800-53 SI-3, FINRA 4511, and SEC 17a-4. Consult with your compliance and legal teams for applicability to your organization's regulatory requirements.*
