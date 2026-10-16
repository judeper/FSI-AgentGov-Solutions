---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P3, P4]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# Credential Oversharing Detector

> **Version:** v2.1.2
> **Status:** Live
> **Validated against framework version:** v1.6.0
> **Upstream Microsoft dependency:** Preview — Copilot Studio credential-oversharing detection (Microsoft roadmap ID 566873) is listed as In development on the Microsoft AI at Work roadmap (preview target July 2026, general availability target September 2026; status checked 2026-10-16). Public availability is not confirmed; validate in a non-production tenant before regulated production use.
> **Last Verified:** 2026-10-16

>
> ⚠️ **Preview Feature Dependency:** This solution tracks the Microsoft "Enforce safe sharing by detecting credential oversharing" capability, published as **roadmap ID 566873** on the **AI at Work roadmap**. Microsoft lists a preview target of July 2026 and a general availability target of September 2026, with roadmap status *In development* (checked 2026-10-16; elapsed target dates do not confirm availability). Microsoft Learn states that release plans are no longer published starting September 2026 and directs new Power Platform capabilities to the roadmap. Verify current status on the [AI at Work roadmap](https://www.microsoft.com/en-us/microsoft-365/roadmap?searchterms=566873) before production deployment. The roadmap describes publish/share-time safe-sharing controls, **not a documented OAuth-scope telemetry API**. The existing [automatic security scan](https://learn.microsoft.com/en-us/microsoft-copilot-studio/security-scan) warns about maker-provided credentials; it does not establish the scanner's expected data contract.

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
- **Dry-run setup** — Python setup scripts support `--dry-run`; the scope-baseline and auth-method helpers support `-WhatIf`. The main scanner has no dry-run switch.
- **Multiple output formats** — Table, JSON, or PowerShell object
- **Workload identity CA review** — heuristic policy inventory for agent service principals (location or risk-based). Microsoft supports workload-identity CA for eligible single-tenant service principals, not managed identities or multitenant applications; manually verify effective coverage.
- **Auth method detection** — flags client-secret usage as legacy/risky and recommends managed identity or certificate migration
- **Name-level OAuth scope baseline** — compares actual scopes against approved baseline at the individual scope name level, detecting excess and sensitive scopes

## Architecture

Environment enumeration uses the Power Apps administration module; agent records and connection references are read from each environment's Dataverse Web API. The diagram is conceptual: the admin API is not a documented source of the nested credential/scope fields assumed by the extractor.

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

These are this solution's configurable policy defaults, not Microsoft product limits. The auto-remediation value is policy metadata; this release does not implement credential rotation or automatic credential changes.

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

Read the [prerequisites and host-compatibility caveat](docs/prerequisites.md) first. Set `COD_TENANT_ID` and `COD_ENVIRONMENT_URL` for Python setup, or supply `--tenant-id` and `--environment-url` explicitly. The scanner separately requires its documented tenant/application authentication parameters; it does not inherit the Python interactive session. Its client-secret path is a dev-only legacy path, not a production identity recommendation.

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
Open Power Apps maker portal → Solutions → Default Solution → Objects → Connection References. Bind each `fsi_cr_*_credentialoversharing` reference to an active connection.

### 5. Build Power Automate flows
Follow [Flow Configuration Guide](docs/flow-configuration.md) to manually build the 3 flows.

### 6. Run initial scan

Run the remaining commands from the solution root (`credential-oversharing-detector`), not its `scripts` subdirectory.

```powershell
.\scripts\governance\Invoke-CredentialScan.ps1 -DataverseUrl "https://org.crm.dynamics.com" -OutputFormat Table
```

Use the governance Dataverse URL containing COD and ELM tables. Without `-DataverseUrl`, this command does not persist scan evidence or resolve ELM zones. Validate connector telemetry against a known agent before interpreting a zero-finding result.

### 7. Test compliance
```powershell
.\scripts\governance\Test-CredentialCompliance.ps1 -DataverseUrl "https://org.crm.dynamics.com" -PersistResults -IncludeCompliant
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

- PowerShell 7.1+ for the repository scripts; Power Apps administration-module host compatibility must be validated separately (see full prerequisites)
- Python 3.9+ (for Dataverse setup)
- Power Platform Admin role
- Teams access for the notification connection and target channel; E3/E5 is not a specific connector prerequisite
- Power Automate premium-connector entitlement for Dataverse flows (for example, Power Automate Premium or allocated Process capacity)
- Microsoft Entra Workload ID Premium if creating or modifying service-principal Conditional Access policies

See [full prerequisites](docs/prerequisites.md) for detailed requirements.

## Known Limitations

1. **Unconfirmed safe-sharing availability** — Roadmap ID 566873 remains *In development* as of 2026-10-16 (preview target July 2026, general availability target September 2026). This is separate from the documented automatic security-scan warnings.
2. **Unverified connector telemetry contract** — The extractor reads `bot.configuration.connectorConfigurations`, `oauthScopes`, and credential metadata. Microsoft documents the `bot` table and its configuration column, but the sources reviewed do not document those nested fields or a safe-sharing API supplying them. Empty or missing fields are incomplete coverage, not evidence that credentials are safe. Validate with a known connector-bearing agent; see [verification record](docs/technical-verification-2026-10-16.md).
3. **Service principal resolution** — Cross-environment credential detection requires consistent service principal IDs across environments.
4. **Scan performance** — Large tenants (100+ environments) may require environment filters or batched scanning.
5. **CA inventory is not effective-policy evaluation** — The helper does not fully evaluate policy state, exclusions, service-principal filters, or the `ServicePrincipalsInMyTenant` selector. Check enabled policies and service-principal sign-in logs before treating a coverage result as effective protection. Managed identities are outside workload-identity CA scope.
6. **Independent helper execution** — The Graph-based CA/auth helpers and the name-level scope-baseline helper are separate from the main scheduled scan. Populate approved/actual baseline rows and run the helpers explicitly; the main scan does not automatically invoke them.

## Microsoft References

- [Enforce safe sharing by detecting credential oversharing — AI at Work roadmap ID 566873](https://www.microsoft.com/en-us/microsoft-365/roadmap?searchterms=566873)
- [AI at Work roadmap — Microsoft Copilot Studio](https://www.microsoft.com/en-us/microsoft-365/roadmap?filters=%5B%22Microsoft%20Copilot%20Studio%22%5D) (Microsoft's redirect target for the retired Copilot Studio release-plan pages: <https://aka.ms/MCStoM365Roadmap>)
- [Release plans for Dynamics 365 and Power Platform](https://learn.microsoft.com/en-us/dynamics365/release-plans/) (no longer published starting September 2026; existing plans remain available for historical reference)
- [Conditional Access for workload identities](https://learn.microsoft.com/en-us/entra/identity/conditional-access/workload-identity)
- [Automatic security scan in Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/security-scan)
- [Agent (bot) table reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/bot)
- [Power Platform for Admins V2 connector](https://learn.microsoft.com/en-us/connectors/powerplatformadminv2/)
- [Power Automate license types](https://learn.microsoft.com/en-us/power-platform/admin/power-automate-licensing/types)
- [Microsoft Teams connector](https://learn.microsoft.com/en-us/connectors/teams/)
- [Technical verification, sources, and downstream review (2026-10-16)](docs/technical-verification-2026-10-16.md)
- [Power Platform Preview Terms](https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v2.1.1 | May 2026 | AI Council review fixes: Dataverse-scoped token for v2.1.0 persistence (was using Graph audience), `fsi_description` column name corrections, GUID suffix on new violation IDs, `Get-MgApplicationFederatedIdentityCredential` parameter fix, `Unclassified` zone added to policy chain, severity label normalization, PS 5.1 compatibility cleanup. See CHANGELOG. |
| v2.1.0 | May 2026 | Added Workload Identity CA policy detection, certificate/MI auth detection, and name-level OAuth scope baseline comparison. |
| v2.0.1 | May 2026 | Microsoft Learn 2026-Q2 refresh: release-plan dates, module prerequisites, service-principal setup, Dataverse option-set corrections, and Teams connector wording. |
| v2.0.0 | April 2026 | BREAKING: AI Council review fixes — switch→bool params, JSON-only return, single scan-record write, V2 PP connector, multi-connector evaluation, regulatory citation accuracy. See CHANGELOG. |
| v1.0.1 | April 2026 | Full solution release: scanning scripts, Dataverse schema, zone policies, evidence export, documentation, and templates |
| v0.1.0-preview | March 2026 | Initial documentation-only placeholder |

## License

[MIT](../LICENSE)
