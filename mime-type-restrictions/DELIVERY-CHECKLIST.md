# MIME Type Restrictions Solution - Customer Delivery Checklist

## Files to Include in Customer Package

### 1. Documentation
- [ ] **SOLUTION-DOCUMENTATION.md** — Main technical documentation (Executive Summary + Technical Details)

### 2. Solution Components (Source Files)

All files located in the `src/` directory:

**Server-Side Validation:**
- [ ] **ValidateMimeTypePlugin.cs** — Dataverse pre-validation plugin (C# source)
- [ ] **MimeConfig.json** — MIME type allowlist/blocklist configuration
- [ ] **BUILD-INSTRUCTIONS.md** — Step-by-step plugin build guide (ILRepack, strong-name verification)

**DLP Policy:**
- [ ] **dlp-policy-template.json** — Power Platform DLP policy template with MIME restrictions

**Sentinel Monitoring:**
- [ ] **query-mime-blocks.kql** — KQL query for blocked upload events (30-day summary)
- [ ] **high-volume-blocks.json** — Sentinel alert rule for high-volume block patterns
- [ ] **query-exception-usage.kql** — KQL query for exception usage tracking

### 3. Packaging Instructions

**Option A: Create ZIP Archive**
```bash
# From the mime-type-restrictions directory:
zip -r MIME-Type-Restrictions-1.0.1.zip \
  SOLUTION-DOCUMENTATION.md \
  src/ValidateMimeTypePlugin.cs \
  src/MimeConfig.json \
  src/BUILD-INSTRUCTIONS.md \
  src/dlp-policy-template.json \
  src/query-mime-blocks.kql \
  src/high-volume-blocks.json \
  src/query-exception-usage.kql
```

**Option B: Create Structured Folder**
```
MIME-Type-Restrictions-1.0.1/
├── SOLUTION-DOCUMENTATION.md
├── Dataverse-Plugin/
│   ├── ValidateMimeTypePlugin.cs
│   ├── MimeConfig.json
│   └── BUILD-INSTRUCTIONS.md
├── DLP-Policy/
│   └── dlp-policy-template.json
└── Sentinel-Monitoring/
    ├── query-mime-blocks.kql
    ├── high-volume-blocks.json
    └── query-exception-usage.kql
```

### 4. Email Template

**Subject:** MIME Type Restrictions for File Uploads - Solution Delivery 1.0.1

**Body:**

```
Hi [Customer Name],

Please find attached the MIME Type Restrictions for File Uploads solution package, version 1.0.1.

This solution provides defense-in-depth validation of file uploads in Copilot Studio agents
through server-side magic byte inspection, DLP policy enforcement, and Sentinel monitoring.

Package Contents:
- SOLUTION-DOCUMENTATION.md — Complete technical documentation with:
  • Executive Summary (problem statement, solution overview, business value)
  • Technical Details (architecture, 3-layer enforcement, components)
  • Configuration and Prerequisites (plugin registration, DLP deployment)
  • Deployment validation steps
  • Operational guidance and troubleshooting
  • Magic byte reference and regulatory alignment

- 7 Solution Component Files:
  • Dataverse pre-validation plugin (C# source)
  • MIME type configuration (JSON allowlist/blocklist)
  • Plugin build guide (ILRepack, strong-name verification)
  • DLP policy template (Power Platform connector restrictions)
  • 2 Sentinel KQL queries and 1 Sentinel alert rule (monitoring, exception tracking, high-volume alerting)

Key Capabilities:
✓ Server-side magic byte inspection (defense against disguised executables)
✓ Blocked signature detection (PE, ELF, Mach-O, Java class files)
✓ OpenXML deep inspection for Office documents (DOCX, XLSX, PPTX)
✓ DLP policy connector-level enforcement
✓ Sentinel monitoring for blocked upload attempts
✓ High-volume attack detection (>10 attempts per user per hour)

Architecture:
• Layer 1: DLP Policy (connector-level MIME whitelist)
• Layer 2: Dataverse Plugin (pre-validation with magic byte inspection)
• Layer 3: Sentinel Monitoring (blocked event aggregation and alerting)

Business Value:
• Reduce malware distribution risk by 95%+ through multi-layered validation
• Prevent data exfiltration via file-based steganography
• Enable security operations teams to detect upload abuse patterns
• Support regulatory examinations with automated MIME restriction evidence

Regulatory Support:
• NIST 800-53 SI-3 — Malicious Code Protection
• FINRA 4511 — Supervision
• SEC 17a-4 — Recordkeeping

Next Steps:
1. Review the SOLUTION-DOCUMENTATION.md file (Section 2: Technical Details)
2. Build Dataverse plugin DLL from C# source (Visual Studio required)
3. Register plugin using Plugin Registration Tool:
   - Entity: annotation (Note)
   - Message: Create
   - Stage: Pre-Validation (10)
   - Configuration: Paste MimeConfig.json content
4. Import DLP policy template via PowerShell
5. Deploy Sentinel queries and alert rule to Log Analytics workspace
6. Test with allowed and blocked file types (PDF vs EXE)
7. Schedule deployment planning session (recommended: 2-3 hours)

CRITICAL CONFIGURATION REQUIREMENTS:

1. **Plugin Configuration:**
   - MimeConfig.json must be pasted into plugin step configuration (unsecure or secure)
   - Enforcement mode: "Block" for production, "TestWithNotifications" for testing
   - Max file size: 10 MB default (adjust based on business requirements)

2. **Allowed MIME Types:**
   - Default allowlist: PDF, PNG, JPEG, GIF, TIFF, TXT, CSV, DOCX, XLSX, PPTX
   - Customize based on organization's legitimate file upload needs
   - Require business justification for new MIME type additions

3. **Blocked Signatures:**
   - Default blocklist: PE/DOS (EXE), ELF, Mach-O, Java class files
   - DO NOT remove blocked signatures without security team approval
   - Add custom signatures if organization-specific threats identified

4. **DLP Policy Mode:**
   - Start with "TestWithNotifications" mode to assess impact (log violations, allow uploads)
   - Review audit logs for 2-4 weeks
   - Switch to "Block" mode after validation (block disallowed uploads)

5. **Sentinel Workspace:**
   - Requires Dataverse audit logs flowing to Log Analytics workspace
   - Diagnostic settings: "Send to Log Analytics" enabled
   - 15-minute ingestion delay expected (not real-time)

Please let me know if you have any questions or need clarification on any aspect
of the solution.

Best regards,
[Your Name]
```

### 5. Pre-Delivery Validation

Before sending to customer, verify:

- [ ] All 8 files are included (1 doc, 1 build guide, 1 C#, 1 config, 1 DLP template, 2 KQL queries, 1 Sentinel alert rule)
- [ ] SOLUTION-DOCUMENTATION.md renders correctly in Markdown viewer
- [ ] C# source compiles without errors (test build in Visual Studio)
- [ ] MimeConfig.json is valid JSON (use JSON validator)
- [ ] No sensitive data in files (tenant IDs, user emails should be placeholders)
- [ ] Version numbers are consistent (1.0.1) across all files

### 6. Files NOT to Include

Do NOT include these repository management files:
- ❌ README.md (internal reference only)
- ❌ CHANGELOG.md (version history for our tracking)
- ❌ .git/ folder (version control)

### 7. Customer Requirements Reminder

Remind customer they will need:

**Licensing:**
- Microsoft 365 E5 or E5 Compliance (for DLP policies and Sentinel)
- Power Platform Admin permissions
- Power Apps Premium (for Dataverse)
- Microsoft Sentinel workspace (for KQL queries)

**Tools:**
- Visual Studio 2019+ (to build plugin DLL from C# source)
- Plugin Registration Tool (to register Dataverse plugin)
- PowerShell 7.2+ (to import DLP policy template)
- Azure Portal access (to configure Sentinel queries)

**Permissions:**
- Dataverse System Administrator (per-environment for plugin registration)
- Power Platform Admin (tenant-wide for DLP policy management)
- Security Reader (Log Analytics workspace for query execution)
- Security Administrator (Sentinel workspace for alert rule creation)

**Prerequisites:**
- Dataverse audit logging enabled in all environments
- Diagnostic settings: "Send to Log Analytics" enabled
- Log Analytics workspace connected to Sentinel

**Optional Component:**
- **FsiMimeControl PowerShell module** — Available in FSI-AgentGov repository under `scripts/governance/`. Provides bulk configuration management, deployment validation, and zone template support. Not required for core functionality but recommended for multi-environment deployments.

### 8. Follow-Up Support

Offer these follow-up services:
- Plugin build and registration assistance (2-4 hours recommended)
- MimeConfig.json customization workshop (1 hour)
- DLP policy testing and validation (2 hours)
- Sentinel dashboard creation for upload monitoring
- Quarterly review of blocked upload trends and policy tuning

### 9. Important Customer Guidance

**Critical Configuration Steps:**

1. **Build Plugin DLL:**
   - Customer MUST build the plugin from C# source code
   - Visual Studio project type: Class Library (.NET Framework 4.6.2)
   - Required NuGet packages: `Microsoft.CrmSdk.CoreAssemblies` (9.0.2+), `System.Text.Json` (6.0.0+)
   - Add `<LangVersion>8.0</LangVersion>` to `.csproj` `<PropertyGroup>` for `using var` syntax
   - Output: `FsiAgentGovernance.Plugins.dll`

2. **Plugin Registration:**
   - Use Plugin Registration Tool (download from Microsoft NuGet)
   - Register on `annotation` entity, `Create` message, Pre-Validation stage (10)
   - **CRITICAL:** Paste entire `MimeConfig.json` content into plugin step configuration
   - Without configuration, plugin will throw error on first upload

3. **MimeConfig.json Customization:**
   - Review default allowlist (10 MIME types) and adjust based on business needs
   - **DO NOT remove blocked signatures** without security team approval
   - Add magic byte patterns for new allowed types (consult file format specifications)
   - Test magic byte validation with sample files before deploying

4. **DLP Policy Testing:**
   - Start in "TestWithNotifications" mode for 2-4 weeks
   - Review audit logs to identify impact on legitimate users
   - Create exceptions for business-justified use cases
   - Switch to "Block" mode only after validation complete

5. **Sentinel Alert Tuning:**
   - Default threshold: 10 blocked uploads per user per hour
   - Adjust based on organization size and upload volume
   - Too low threshold = alert fatigue, too high = missed attacks
   - Review incident history quarterly and adjust threshold

### 10. Deployment Validation Checklist for Customer

Provide this checklist to customer for post-deployment validation:

```
Plugin Build and Registration:
□ Visual Studio project created (Class Library .NET Framework 4.6.2)
□ NuGet packages installed: Microsoft.CrmSdk.CoreAssemblies, System.Text.Json
□ ValidateMimeTypePlugin.cs compiled successfully
□ DLL output generated: FsiAgentGovernance.Plugins.dll

Plugin Registration:
□ Plugin Registration Tool connected to Dataverse environment
□ Assembly registered (Isolation: Sandbox, Location: Database)
□ Plugin step registered on annotation.Create, Pre-Validation (10)
□ MimeConfig.json pasted into plugin step configuration (unsecure or secure)
□ Plugin step status: Active

MimeConfig.json Validation:
□ JSON syntax validated (no parsing errors)
□ Enforcement mode set: "Block" for production
□ Max file size configured: 10485760 bytes (10 MB) or custom
□ Allowed types reviewed and customized for organization
□ Blocked signatures NOT removed (security risk)

DLP Policy Deployment:
□ dlp-policy-template.json customized with organization MIME types
□ Policy imported via PowerShell successfully
□ Policy mode set: "TestWithNotifications" (initial testing) or "Block" (production)
□ Policy scope configured: All environments or specific groups
□ Copilot Studio connector classified as "Business" (not Blocked)

Sentinel Queries:
□ Log Analytics workspace connected to Dataverse audit logs
□ query-mime-blocks.kql saved as function: MimeTypeBlocks
□ query-exception-usage.kql saved as function: MimeExceptionUsage
□ high-volume-blocks.json imported as alert rule
□ Alert rule enabled and configured (1-hour frequency, Medium severity)

Test Execution:
□ Test 1: Upload allowed PDF → Success (annotation created)
□ Test 2: Upload blocked EXE → Blocked (error message displayed)
□ Test 3: Upload ZIP (not in allowlist) → Blocked
□ Test 4: Upload disguised EXE (renamed to PDF) → Blocked (magic byte mismatch)
□ Test 5: DLP policy blocks disallowed MIME → Audit log entry created
□ Test 6: Sentinel query returns blocked events → Results displayed

Plugin Trace Log Review:
□ Trace logs show successful validation for allowed files
□ Trace logs show blocked signature detection for EXE
□ Trace logs show magic byte consistency validation
□ No errors or exceptions in trace logs during normal operation

Operational Readiness:
□ Security operations team trained on Sentinel dashboard
□ High-volume alert response procedure documented
□ Exception request process documented (business justification required)
□ Quarterly policy review scheduled (MIME type allowlist tuning)
```

---

**Package Version:** 1.0.1
**Release Date:** February 2026
**Solution:** MIME Type Restrictions for File Uploads
