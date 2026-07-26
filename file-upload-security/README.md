---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P3]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# File Upload Security Configurator

> **Version:** v1.1.2
> **Status:** Live
> **Validated against framework version:** v1.6.0
> **Last Verified:** 2026-07-26

Automated validation of Copilot Studio agent file upload settings against governance zone policies. Supports Control 1.14 (Data Minimization and Agent Scope Control) by detecting agents with file uploads enabled in zones where uploads should be restricted or disabled.

## Solution Overview

| Attribute | Value |
|-----------|-------|
| **Control** | 1.14 — Data Minimization and Agent Scope Control |
| **Solution Type** | Tier 2 — Automated Validation with Drift Detection |
| **Version** | 1.1.2 |
| **Zone Model** | Zone 1: Allowed · Zone 2: Restricted · Zone 3: Disabled |
| **Regulatory** | FINRA Regulatory Notice 25-07, FINRA Rule 4511, SEC Rule 17a-3, GLBA 501(b), Interagency Guidelines Establishing Information Security Standards (12 CFR 30 App. B) |

## Why File Upload Governance Matters

Copilot Studio agents can accept file uploads (images, PDFs, text files) during conversations. When file uploads are enabled, agents can ingest data beyond their declared operational scope — creating data minimization risks that FSI organizations must manage:

- **Zone 1 (Enterprise Managed)** agents handle sensitive data; unrestricted file uploads expand attack surface
- **Zone 2 (Team Collaboration)** agents require governance approval before accepting user-uploaded content
- **Content moderation cross-check** — agents accepting file uploads should have elevated content moderation levels

## Quick Start

### Prerequisites

- PowerShell 7.4+
- Microsoft.PowerApps.Administration.PowerShell module
- Copilot Studio environment access
- See [PREREQUISITES.md](docs/prerequisites.md)
- See [CHANGELOG](./CHANGELOG.md) for version history.

### Validate File Upload Compliance

```powershell
# Import the module and helpers
Import-Module ./scripts/private/FUSClient.psm1

# Run full compliance validation
./scripts/Test-FileUploadCompliance.ps1 -OutputFormat Table

# Dry run (no Dataverse queries)
./scripts/Test-FileUploadCompliance.ps1 -DryRun

# Target specific environments
./scripts/Test-FileUploadCompliance.ps1 -IncludeEnvironments "prod-env-1","prod-env-2" -OutputFormat JSON

# Include compliant agents in output
./scripts/Test-FileUploadCompliance.ps1 -IncludeCompliant -OutputFormat CSV
```

### Capture Baseline

```powershell
./scripts/Invoke-FileUploadBaselineCapture.ps1 -EnvironmentFilter "*"
```

### Export Evidence

```powershell
./scripts/Export-FileUploadEvidence.ps1 -OutputPath ./evidence
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                Orchestrator Layer                     │
│  Test-FileUploadCompliance.ps1                       │
│  (dry-run, multi-format output, summary stats)       │
├──────────────┬──────────────┬────────────────────────┤
│  Enumeration │  Comparison  │  Cross-Check           │
│  Get-Agent   │  Compare-    │  Content moderation    │
│  FileUpload  │  FileUpload  │  level validation      │
│  Settings    │  Compliance  │  for upload-enabled    │
├──────────────┴──────────────┴────────────────────────┤
│                 FUSClient Module                      │
│  Dataverse queries · Baselines · Validations         │
├──────────────────────────────────────────────────────┤
│               Private Helpers                         │
│  Connect-EnvironmentDataverse · Get-Zone · Validate  │
└──────────────────────────────────────────────────────┘
```

## Key Scripts

| Script | Purpose |
|--------|---------|
| `Test-FileUploadCompliance.ps1` | End-to-end orchestrator with dry-run and multi-format output |
| `Get-AgentFileUploadSettings.ps1` | Enumerate agents and retrieve file upload enabled status |
| `Compare-FileUploadCompliance.ps1` | Evaluate settings against zone baselines with severity |
| `Export-FileUploadEvidence.ps1` | SHA-256 integrity-hashed evidence export |
| `Invoke-FileUploadBaselineCapture.ps1` | Capture current settings as compliance baseline |
| `Start-FileUploadValidationRunbook.ps1` | Azure Automation wrapper for unattended execution |
| `deploy.py` | Dataverse infrastructure deployment orchestrator |
| `fus_client.py` | Python Dataverse REST API client |
| `create_dataverse_schema.py` | Create Dataverse tables and columns |
| `create_environment_variables.py` | Create Dataverse environment variables |
| `create_connection_references.py` | Create Dataverse connection references |

## Zone Policy Model

| Zone | File Upload | Approval | Min Moderation | Violation Severity |
|------|------------|----------|----------------|-------------------|
| Zone 1 (Enterprise) | Disabled | Required | Highest | Critical if enabled |
| Zone 2 (Team) | Restricted | Required | High | High if enabled without approval/moderation |
| Zone 3 (Personal) | Allowed | Not required | Low | Warning if no moderation |

## Documentation

- [PREREQUISITES.md](docs/prerequisites.md) — Required modules and permissions
- [SCHEMA.md](docs/schema.md) — Dataverse table definitions
- [EVIDENCE_EXPORT.md](docs/evidence-export.md) — Evidence export and integrity verification
- [FLOW_SETUP.md](docs/flow-setup.md) — Power Automate flow deployment
- [Downstream Validation](docs/downstream-validation.md) — Post-upload attachment validation examples
- [TROUBLESHOOTING.md](docs/troubleshooting.md) — Common issues and resolution

## Configuration Placeholders

Configuration values for the Power Automate flow (tenant domain, Dataverse URL, compliance email, Teams IDs, certificate thumbprint, etc.) must be set during manual flow creation. See [FLOW_SETUP.md](docs/flow-setup.md#2-configure-variables) for the complete list with descriptions.

> **Note:** For full environment portability across dev/test/prod, consider storing these values as Dataverse environment variables (see [SCHEMA.md](docs/schema.md) Environment Variables section). This allows per-environment configuration without modifying the flow definition.

## Platform Update Notes

### Copilot Studio file input limits (Microsoft Learn 2026-Q3)

Copilot Studio user file uploads are turned on in the agent **Settings** > **Generative AI** > **File processing capabilities** > **File uploads** area, where makers can also select the content moderation strictness level. Per [Allow file input from users](https://learn.microsoft.com/microsoft-copilot-studio/image-input-analysis) (Microsoft Learn), the supported user-upload types are DOCX, CSV, PDF, TXT, JPG, PNG, WebP, and nonanimated GIF; XLSX and PPTX are available only in experimental mode (requires Microsoft support engagement). The documented size restrictions are an individual file size limit of 15 MB and a text character limit of 30,000 characters per file (and across files in a multi-file upload) when no code interpreter is used; with the [code interpreter](https://learn.microsoft.com/microsoft-copilot-studio/knowledge-code-interpreter-structured-data) there is no character limit. Microsoft Learn scopes that character limit to text the agent extracts from Office documents (Word, PowerPoint, Excel); PDFs are processed as the file itself rather than as extracted text, so the character limit doesn't apply to them. SharePoint-channel agents don't support user file uploads, and agents in customer-managed-key (CMK) environments can accept files as input but don't process them. Files carrying encryption — including sensitivity labels or password protection — aren't supported as user uploads; the agent reports that the file can't be read. (File uploads used as agent **knowledge sources** are a separate feature with its own, larger 512 MB per-file limit and a broader supported-type list; see [Use uploaded files with generative answers nodes](https://learn.microsoft.com/microsoft-copilot-studio/nlu-documents).)

### Dataverse extension and MIME controls

Power Platform also provides environment-level file controls through Dataverse organization settings. `Organization.BlockedAttachments` controls blocked file extensions, while `Organization.BlockedMimeTypes` and `Organization.AllowedMimeTypes` control MIME type restrictions. If `allowedmimetypes` is configured, it takes precedence and `blockedmimetypes` is ignored. These settings are server-side controls for Dataverse file, image, attachment, and note storage; this solution complements them by validating whether each Copilot Studio agent has file uploads enabled for its governance zone.

### Microsoft Graph attachment and file API scope

If downstream agent flows or connector tools route uploaded files to Microsoft 365 services, prefer Microsoft Graph v1.0 APIs unless a beta-only capability is explicitly required. The v1.0 driveItem content API supports single-call uploads up to 250 MB. Outlook message and event attachments use a single POST below 3 MB and upload sessions for files from 3 MB to 150 MB.

### Defender for Cloud Apps and Purview DLP scope

Microsoft Defender for Cloud Apps file policies provide API-based continuous controls for files stored in connected cloud apps, including metadata and MIME-type filters. These policies are complementary detective controls and don't replace per-agent file-upload gating. **Retirement notice:** Microsoft Learn now documents that Defender for Cloud Apps [file policies retire on January 6, 2027](https://learn.microsoft.com/defender-cloud-apps/data-protection-policies), and directs organizations to [migrate file-based data protection to Microsoft Purview DLP or auto-labeling policies](https://learn.microsoft.com/defender-cloud-apps/migrate-file-policies-to-purview). Organizations that depend on file policies as a detective control should plan that migration. Microsoft Purview DLP for Microsoft 365 Copilot and Copilot Chat can restrict sensitive prompt text and labeled stored files or emails from Copilot processing, but Microsoft Learn notes that DLP can't scan the contents of files uploaded directly into prompts — only the text typed into the prompt itself is evaluated.

### Microsoft Purview Sensitivity Labels (2026 Wave 1)

Microsoft has announced [sensitivity label visibility in Copilot Studio](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/power-platform-governance-administration/view-sensitivity-labels-copilot-studio) in the Power Platform 2026 release wave 1 plan, with public preview dated November 30, 2025 and general availability targeted for June 2026. As of this verification (2026-07-26) that release plan entry still carries Microsoft's standard "has not been released" disclaimer and no GA confirmation appears in the Copilot Studio product documentation, so treat the June 2026 date as a projected target rather than delivered functionality. This feature enables Purview autolabeling at the Dataverse column level, with labels surfaced when selecting knowledge sources and in agent response citations.

**Relationship to this solution:** Purview sensitivity labels classify data and make classification visible to makers and users. File Upload Security validates **whether file uploads are enabled or disabled** per governance zone. As sensitivity labels become available in Copilot Studio, organizations can use label metadata to inform zone policy decisions — for example, automatically escalating the violation severity when an upload-enabled agent accesses columns labeled "Highly Confidential." The two capabilities are complementary.

## Related Controls

- **1.14** — Data Minimization and Agent Scope Control (primary)
- **1.8** — Content Moderation Configuration (cross-check)
- **1.4** — Connector and DLP Policies (data boundary)

## License

MIT — See repository root LICENSE file.
