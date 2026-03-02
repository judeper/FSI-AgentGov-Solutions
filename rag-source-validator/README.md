# RAG Source Validator

> **Status:** Work In Progress

Integrity validation for Retrieval-Augmented Generation (RAG) knowledge sources with change detection and audit capabilities.

## Overview

The RAG Source Validator ensures AI agents use trusted, verified knowledge sources by continuously validating content integrity, detecting unauthorized modifications, and tracking changes over time.

## Features

| Feature | Description |
|---------|-------------|
| **Hash Validation** | SHA-256 content hash verification |
| **Change Detection** | Real-time and scheduled modification tracking |
| **Source Registry** | Centralized inventory of all knowledge sources |
| **Freshness Monitoring** | Alert on stale or outdated content |
| **Audit Trail** | Complete history of source changes |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    RAG Source Validator                          │
├─────────────────────────────────────────────────────────────────┤
│  Source Mgr  │  Hash Engine  │  Change Detector │  Audit Log   │
└──────────────┴───────────────┴──────────────────┴──────────────┘
                              ▲
                              │ Validation
                              │
┌─────────────────────────────────────────────────────────────────┐
│                    Dataverse (Source Registry)                   │
├────────────────────┬────────────────────┬───────────────────────┤
│ Knowledge          │ Validation         │ Source                │
│ Source             │ Result             │ Change                │
└────────────────────┴────────────────────┴───────────────────────┘
                              ▲
                              │ Source Types
                              │
┌─────────────┬───────────────┬───────────────┬───────────────────┐
│ SharePoint  │ Dataverse     │ Azure Blob    │ External          │
│ Documents   │ Tables        │ Storage       │ APIs              │
└─────────────┴───────────────┴───────────────┴───────────────────┘
```

## Supported Source Types

| Type | Content | Hash Method |
|------|---------|-------------|
| **SharePoint** | Documents, lists, pages | File content hash |
| **Dataverse** | Tables, rows | Row checksum |
| **Azure Blob** | Files, containers | Blob content hash |
| **Web API** | JSON responses | Response body hash |
| **Database** | Queries, tables | Query result hash |

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Validation flows |
| **Dataverse capacity** | Source registry |
| **SharePoint Online** | SharePoint source access |
| **Azure Storage** | Blob source access (optional) |

### Permissions

| Role | Required For |
|------|--------------|
| **SharePoint Reader** | Document content access |
| **Dataverse Reader** | Table data access |
| **Storage Blob Reader** | Azure Blob access |

## Quick Start

### 1. Deploy Dataverse Schema

Import the Dataverse solution into your Power Platform environment using the Power Platform admin center or `pac` CLI.

> **Note:** The deployable solution package (solution.xml, managed/unmanaged .zip) is not yet available. The Dataverse schema is documented in [docs/dataverse-schema.md](docs/dataverse-schema.md) and must be created manually or via `pac` CLI until the packaged solution is published.

### 2. Register Knowledge Sources

Register sources directly in the `fsi_knowledgesource` Dataverse table via the model-driven app or Dataverse API.

### 3. Run Validation

```powershell
.\scripts\Invoke-SourceValidation.ps1 -Environment "https://your-org.crm.dynamics.com"
```

The script automatically captures baselines on first run for sources without an existing hash.

## Deployment

1. Import the Dataverse solution into your Power Platform environment (see [Quick Start](#1-deploy-dataverse-schema) for current status)
2. Set environment variables `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_CLIENT_SECRET` (or configure certificate-based authentication) for service principal access
3. Register knowledge sources via the model-driven app or Dataverse API
4. Run `Invoke-SourceValidation.ps1` to capture baselines and validate
5. Configure scheduled execution via Task Scheduler, cron, or Azure Automation to run `Invoke-SourceValidation.ps1` on a recurring basis

## Documentation

| Document | Description |
|----------|-------------|
| [Dataverse Schema](docs/dataverse-schema.md) | Table definitions and choice values |

## Validation Types

### Content Hash Validation

Computes SHA-256 hash of source content and compares to stored baseline.

```
Source Content → SHA-256 Hash → Compare to Baseline → Pass/Fail
```

### Schema Validation

For structured data sources, validates schema hasn't changed.

| Check | Description |
|-------|-------------|
| Column count | Number of columns matches |
| Column names | Column names unchanged |
| Data types | Column types consistent |
| Constraints | Keys and relationships intact |

### Freshness Validation

Ensures content is current and not stale by comparing `fsi_lastmodified` against the per-source `fsi_freshnessthreshold` (in days).

| Condition | Status |
|-----------|--------|
| Within threshold | Fresh |
| Exceeds threshold | Stale (result = 4) |

### Link Validation

For documents with references, validates all links are accessible.

## Alert Configuration

### Alert Types

| Type | Trigger | Severity |
|------|---------|----------|
| **Hash Mismatch** | Content changed | High |
| **Schema Drift** | Structure changed | High |
| **Stale Content** | No updates > threshold | Medium |
| **Broken Link** | Referenced content unavailable | Medium |
| **New Source** | Unregistered source accessed | Low |

### Alert Channels

- Email notifications
- Teams adaptive cards
- Power Automate triggers
- Webhook integrations

## Regulatory Alignment

### SEC 17a-4

> Records must be preserved in a non-rewriteable, non-erasable format.

**Coverage:** Hash validation ensures records haven't been altered.

> **Limitation:** Validation results are currently stored in standard mutable Dataverse records, which do not satisfy WORM (Write Once Read Many) requirements. Production deployments requiring full SEC 17a-4 compliance should integrate an immutable audit trail (e.g., Azure Immutable Blob Storage, or a third-party WORM-compliant archive) to store validation results alongside Dataverse records.

### FINRA 4511

> Books and records must be accurate and complete.

**Coverage:** Change detection identifies unauthorized modifications.

### SOX 404

> Internal controls over data integrity.

**Coverage:** Continuous validation provides assurance of data integrity.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.7 - Comprehensive Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) | Audit trail integration |
| [2.13 - Documentation](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.13-documentation-and-record-keeping.md) | Record integrity |
| [2.16 - RAG Source Integrity Validation](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.16-rag-source-integrity-validation.md) | Primary control for source validation |
| [4.3 - Site and Document Retention](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-4-sharepoint/4.3-site-and-document-retention-management.md) | Source access control |

> **Note:** The current implementation logs validation results to Dataverse and stdout. It does not yet integrate DLP enforcement, sharing restrictions, or centralized audit logging beyond the validation result records. These governance controls are planned for a future release.

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | February 2026 | Initial release |

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Authentication failure | Expired token or insufficient SharePoint/Dataverse permissions | Re-authenticate; verify SharePoint Reader and Dataverse Reader roles |
| Hash mismatch on first run | No baseline captured for the source | Run `Invoke-SourceValidation.ps1` — baselines are captured automatically on first run |
| Source not found | Incorrect URI or source moved/renamed | Verify source URI; re-register via the model-driven app or Dataverse API |
| Stale content alerts | Source not updated within freshness threshold | Review source update schedule; adjust threshold if appropriate |

### Logs

Review script output for `[ERROR]` entries. Enable verbose output with `-Verbose` flag.

## Support

For issues, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - RAG Source Validator v1.0.0*
