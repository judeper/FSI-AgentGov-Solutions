---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P3, P4]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# Credential Oversharing Detector

> **Version:** v2.0.1 | **Controls:** 1.14, 1.4, 1.18 | **Status:** Public Preview
>
> ⚠️ **Preview Feature Dependency:** This solution tracks the Microsoft "Enforce safe sharing by detecting credential oversharing" capability, which the Microsoft release plan currently lists for public preview in July 2026 and general availability in September 2026. Verify current feature status at the [Microsoft release plan](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/microsoft-copilot-studio/enforce-safe-sharing-detecting-credential-oversharing) before production deployment.

## Overview

Configuration-time governance scanner that detects Copilot Studio agents with credentials broader than their approved operating scope. Identifies overprivileged connectors, excessive OAuth scopes, unauthorized service accounts, cross-environment credential sharing, and stale credentials — per governance zone policy.

See [CHANGELOG](./CHANGELOG.md) for version history.

**What this solution does:**
- Scans agent connector configurations against zone-based credential policies
- Detects 6 violation types with severity classification
- Persists scan history and violations to Dataverse for audit evidence
- Sends Teams alerts for findings requiring attention
- Supports exception workflows with approval routing and expiration
- Exports tamper-evident evidence packages (JSON + SHA-256)

**What this solution is NOT:**
- Not runtime access monitoring (see [Scope Drift Monitor](../scope-drift-monitor/))
- Not sharing recipient governance (see [Agent Sharing Access Restriction Detector](../agent-sharing-access-restriction-detector/))
- Not content moderation settings (see [Content Moderation Monitor](../content-moderation-monitor/))

## Features

- **Zone-based credential policies** — configurable thresholds per Zone 1/2/3
- **6 violation types** — OverprivilegedConnector, ExcessiveOAuthScope, UnauthorizedServiceAccount, CrossEnvironmentCredential, SharedCredentialMisuse, StaleCredentialAccess
- **Automated scanning** — scheduled via Power Automate with configurable frequency
- **Exception management** — approval workflows with automatic expiration
- **Evidence export** — SHA-256 hash-verified JSON for regulatory examinations
- **Dry-run mode** — preview changes before Dataverse writes
- **Multiple output formats** — Table, JSON, or PowerShell object
- **Workload identity CA detection** — identifies agent service principals without Conditional Access policies (location or risk-based)
- **Auth method detection** — flags client-secret usage as legacy/risky and recommends managed identity or certificate migration
- **Name-level OAuth scope baseline** — compares actual scopes against approved baseline at the individual scope name level, detecting excess and sensitive scopes

## Architecture

```
┌─────────────────────┐     ┌──────────────────────┐
│  Power Platform     │     │  Copilot Studio       │
│  Admin API          │────▶│  Agent Configs        │
└─────────┬───────────┘     └──────────┬────────────┘
          │                            │
          ▼                            ▼
┌─────────────────────────────────────────────────────┐
│              Credential Oversharing Detector          │
│                                                       │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │ Invoke-     │  │ Zone Policy  │  │ Exception   │ │
│  │ Credential  │──│ Engine       │──│ Manager     │ │
│  │ Scan        │  │              │  │             │ │
│  └─────────────┘  └──────────────┘  └─────────────┘ │
└───────────────────────────┬─────────────────────────┘
                            │
          ┌─────────────────┼─────────────────┐
          ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  Dataverse   │  │  Teams       │  │  Evidence    │
│  (Scan/      │  │  Alerts      │  │  Export      │
│   Violations)│  │              │  │  (JSON+SHA)  │
└──────────────┘  └──────────────┘  └──────────────┘
```

## Zone Requirements

| Setting | Zone 1 (Dev) | Zone 2 (Team) | Zone 3 (Prod) |
|---------|-------------|---------------|---------------|
| Max OAuth Scopes | 20 | 10 | 5 |
| Require Service Principal | No | No | Yes |
| Allow Cross-Environment | Yes | No | No |
| Allow Shared Credentials | Yes | No | No |
| Max Credential Age (days) | 180 | 90 | 30 |
| Credential Rotation Required | No | Yes | Yes |
| Auto-Remediate | No | No | Yes |

## Quick Start

### 1. Create Dataverse schema
```bash
cd credential-oversharing-detector/scripts
python create_cod_dataverse_schema.py --interactive --dry-run
python create_cod_dataverse_schema.py --interactive
```

### 2. Create environment variables
```bash
python create_cod_environment_variables.py --interactive
```

### 3. Create connection references
```bash
python create_cod_connection_references.py --interactive
```

### 4. Bind connection references
Open Power Apps maker portal → Solutions → Default Solution → Connection References. Bind each `fsi_cr_*_credentialoversharing` reference to an active connection.

### 5. Build Power Automate flows
Follow [Flow Configuration Guide](docs/flow-configuration.md) to manually build the 3 flows.

### 6. Run initial scan
```powershell
.\scripts\governance\Invoke-CredentialScan.ps1 -OutputFormat Table
```

### 7. Test compliance
```powershell
.\scripts\governance\Test-CredentialCompliance.ps1 -IncludeCompliant
```

## Solution Components

### Scripts
| Script | Purpose |
|--------|---------|
| `scripts/create_cod_dataverse_schema.py` | Create Dataverse tables and option sets |
| `scripts/create_cod_environment_variables.py` | Create environment variables |
| `scripts/create_cod_connection_references.py` | Create connection references |
| `scripts/governance/Invoke-CredentialScan.ps1` | Main credential scope scanner |
| `scripts/governance/Test-CredentialCompliance.ps1` | Zone compliance validator |
| `scripts/governance/Get-AgentConnectorScope.ps1` | Agent connector scope extractor |
| `scripts/governance/Get-ExpectedCredentialPolicy.ps1` | Zone policy lookup |
| `scripts/governance/Export-CredentialEvidence.ps1` | Evidence export with SHA-256 |
| `scripts/governance/Test-EvidenceIntegrity.ps1` | Evidence hash verification |
| `scripts/governance/Get-WorkloadIdentityCAPolicy.ps1` | Workload identity CA policy coverage analysis |
| `scripts/governance/Test-AgentAuthMethod.ps1` | Agent authentication method detection (MI/cert/secret) |
| `scripts/governance/Compare-OAuthScopeBaseline.ps1` | Name-level OAuth scope baseline comparison |

### Templates
| Template | Purpose |
|----------|---------|
| `templates/zone-credential-policy.json` | Zone-based credential policy baseline |
| `templates/adaptive-card-credential-alert.json` | Teams notification card |

### Documentation
| Document | Purpose |
|----------|---------|
| [Prerequisites](docs/prerequisites.md) | Licensing, permissions, setup |
| [Dataverse Schema](docs/dataverse-schema.md) | Table and column reference |
| [Flow Configuration](docs/flow-configuration.md) | Manual flow build guide |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and fixes |

## Related Controls

| Control | Relationship |
|---------|-------------|
| **1.14 — Data Minimization and Agent Scope Control** | Supports least-privilege review by detecting when agent connector OAuth scopes exceed declared zone limits |
| **1.4 — Advanced Connector Policies (ACP)** | Provides configuration-time visibility into connector credential scope alongside ACP rule enforcement |
| **1.18 — Application-Level Authorization and RBAC** | Adds credential-scope context to agent sharing reviews; sharing controls live in Agent Sharing Access Restriction Detector |

## Boundary with Existing Solutions

| Solution | Boundary |
|----------|----------|
| [Agent Sharing Access Restriction Detector](../agent-sharing-access-restriction-detector/) | Governs who an agent can be shared with. COD governs the credentials the agent carries. |
| [Scope Drift Monitor](../scope-drift-monitor/) | Monitors runtime data access. COD focuses on configuration-time credential review. |
| [Content Moderation Monitor](../content-moderation-monitor/) | Validates content moderation settings. COD validates connector credential scope. |

## Prerequisites

- PowerShell 7.1+
- Python 3.9+ (for Dataverse setup)
- Power Platform Admin role
- Microsoft 365 E3/E5 (for Teams alerts)

See [full prerequisites](docs/prerequisites.md) for detailed requirements.

## Known Limitations

1. **Preview feature dependency** — Credential oversharing signals from Copilot Studio depend on a Microsoft feature currently listed for public preview in July 2026 and general availability in September 2026. Release-plan timelines may change, and signal availability may vary by tenant.
2. **Connector scope visibility** — Not all connector types expose OAuth scope details through the admin API.
3. **Service principal resolution** — Cross-environment credential detection requires consistent service principal IDs across environments.
4. **Scan performance** — Large tenants (100+ environments) may require environment filters or batched scanning.

## Microsoft References

- [Enforce safe sharing by detecting credential oversharing](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/microsoft-copilot-studio/enforce-safe-sharing-detecting-credential-oversharing)
- [Copilot Studio 2026 Release Wave 1](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/microsoft-copilot-studio/planned-features)
- [Power Platform Preview Terms](https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v2.0.1 | May 2026 | Microsoft Learn 2026-Q2 refresh: release-plan dates, module prerequisites, service-principal setup, Dataverse option-set corrections, and Teams connector wording. |
| v2.0.0 | April 2026 | BREAKING: AI Council review fixes — switch→bool params, JSON-only return, single scan-record write, V2 PP connector, sovereign-cloud, multi-connector evaluation, regulatory citation accuracy. See CHANGELOG. |
| v1.0.1 | April 2026 | Full solution release: scanning scripts, Dataverse schema, zone policies, evidence export, documentation, and templates |
| v0.1.0-preview | March 2026 | Initial documentation-only placeholder |

## License

[MIT](../LICENSE)
