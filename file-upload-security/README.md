# File Upload Security Configurator

Automated validation of Copilot Studio agent file upload settings against governance zone policies. Supports Control 1.14 (Data Minimization and Agent Scope Control) by detecting agents with file uploads enabled in zones where uploads should be restricted or disabled.

> **Status:** Completed

## Solution Overview

| Attribute | Value |
|-----------|-------|
| **Control** | 1.14 — Data Minimization and Agent Scope Control |
| **Solution Type** | Tier 2 — Automated Validation with Drift Detection |
| **Version** | 1.0.0 |
| **Zone Model** | Zone 1: Allowed · Zone 2: Restricted · Zone 3: Disabled |
| **Regulatory** | FINRA 4511/25-07, SEC 17a-3, GLBA 501(b), OCC 2011-12 |

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

The following placeholder values in solution files must be replaced with your organization's values before deployment:

> **Note:** All deployment-specific values are currently stored as `InitializeVariable` actions in the flow JSON. For full environment portability across dev/test/prod, consider migrating these to Dataverse environment variables (see [SCHEMA.md](docs/SCHEMA.md) Environment Variables section). This would allow per-environment configuration without modifying the flow definition, but requires architectural changes to the flow JSON and supporting deployment scripts.

| Placeholder | Replace With | Files |
|------------|-------------|-------|
| `contoso.onmicrosoft.com` | Your tenant domain | `src/fileupload-validation-flow.json` |
| `compliance-alerts@contoso.com` | Your compliance team email | `src/fileupload-validation-flow.json` |
| `your-client-id-here` | Microsoft Entra ID application (client) ID | `src/fileupload-validation-flow.json` |
| `your-certificate-thumbprint-here` | Certificate thumbprint for service principal auth | `src/fileupload-validation-flow.json` |
| `your-subscription-id-here` | Azure subscription ID | `src/fileupload-validation-flow.json` |
| `your-teams-group-id-here` | Teams group (team) ID for alerts | `src/fileupload-validation-flow.json` |
| `your-teams-channel-id-here` | Teams channel ID for alerts | `src/fileupload-validation-flow.json` |
| `https://governance.crm.dynamics.com` | Your Dataverse org URL | `src/fileupload-validation-flow.json` |
| `rg-file-upload-security` | Azure resource group containing Automation Account | `src/fileupload-validation-flow.json` |
| `aa-file-upload-security` | Azure Automation Account name | `src/fileupload-validation-flow.json` |

## Related Controls

- **1.14** — Data Minimization and Agent Scope Control (primary)
- **1.8** — Content Moderation Configuration (cross-check)
- **1.4** — Connector and DLP Policies (data boundary)

## License

MIT — See repository root LICENSE file.
