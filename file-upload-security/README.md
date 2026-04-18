# File Upload Security Configurator

Automated validation of Copilot Studio agent file upload settings against governance zone policies. Supports Control 1.14 (Data Minimization and Agent Scope Control) by detecting agents with file uploads enabled in zones where uploads should be restricted or disabled.

> **Status:** Completed

## Solution Overview

| Attribute | Value |
|-----------|-------|
| **Control** | 1.14 — Data Minimization and Agent Scope Control |
| **Solution Type** | Tier 2 — Automated Validation with Drift Detection |
| **Version** | 1.0.2 |
| **Zone Model** | Zone 1: Allowed · Zone 2: Restricted · Zone 3: Disabled |
| **Regulatory** | FINRA Regulatory Notice 25-07, FINRA Rule 4511, SEC Rule 17a-3, GLBA 501(b), Interagency Guidelines Establishing Information Security Standards (12 CFR 30 App. B) |

## Why File Upload Governance Matters

Copilot Studio agents can accept file uploads (images, PDFs, text files) during conversations. When file uploads are enabled, agents can ingest data beyond their declared operational scope — creating data minimization risks that FSI organizations must manage:

- **Zone 3 (Enterprise Managed)** agents handle sensitive data; unrestricted file uploads expand attack surface
- **Zone 2 (Team Collaboration)** agents require governance approval before accepting user-uploaded content
- **Content moderation cross-check** — agents accepting file uploads should have elevated content moderation levels

## Quick Start

### Prerequisites

- PowerShell 7.4+
- Microsoft.PowerApps.Administration.PowerShell module
- Copilot Studio environment access
- See [PREREQUISITES.md](docs/PREREQUISITES.md)
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
| Zone 1 (Personal) | Allowed | Not required | Low | Warning if no moderation |
| Zone 2 (Team) | Restricted | Required | High | High if enabled without approval/moderation |
| Zone 3 (Enterprise) | Disabled | Required | Highest | Critical if enabled |

## Documentation

- [PREREQUISITES.md](docs/PREREQUISITES.md) — Required modules and permissions
- [SCHEMA.md](docs/SCHEMA.md) — Dataverse table definitions
- [EVIDENCE_EXPORT.md](docs/EVIDENCE_EXPORT.md) — Evidence export and integrity verification
- [FLOW_SETUP.md](docs/FLOW_SETUP.md) — Power Automate flow deployment
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — Common issues and resolution

## Configuration Placeholders

Configuration values for the Power Automate flow (tenant domain, Dataverse URL, compliance email, Teams IDs, certificate thumbprint, etc.) must be set during manual flow creation. See [FLOW_SETUP.md](docs/FLOW_SETUP.md#2-configure-variables) for the complete list with descriptions.

> **Note:** For full environment portability across dev/test/prod, consider storing these values as Dataverse environment variables (see [SCHEMA.md](docs/SCHEMA.md) Environment Variables section). This allows per-environment configuration without modifying the flow definition.

## Platform Update Notes

### Microsoft Purview Sensitivity Labels (2026 Wave 1)

Microsoft is introducing [sensitivity label visibility in Copilot Studio](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/power-platform-governance-administration/view-sensitivity-labels-copilot-studio) (GA June 2026). This feature enables Purview autolabeling at the Dataverse column level, with labels surfaced when selecting knowledge sources and in agent response citations.

**Relationship to this solution:** Purview sensitivity labels classify data and make classification visible to makers and users. File Upload Security validates **whether file uploads are enabled or disabled** per governance zone. As sensitivity labels become available in Copilot Studio, organizations can use label metadata to inform zone policy decisions — for example, automatically escalating the violation severity when an upload-enabled agent accesses columns labeled "Highly Confidential." The two capabilities are complementary.

## Related Controls

- **1.14** — Data Minimization and Agent Scope Control (primary)
- **1.8** — Content Moderation Configuration (cross-check)
- **1.4** — Connector and DLP Policies (data boundary)

## License

MIT — See repository root LICENSE file.
