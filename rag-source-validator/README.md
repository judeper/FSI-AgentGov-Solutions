# RAG Source Validator

> **Status:** Work In Progress

Integrity validation for Retrieval-Augmented Generation (RAG) knowledge sources with change detection and audit capabilities.

## Overview

The RAG Source Validator ensures AI agents use trusted, verified knowledge sources by continuously validating content integrity, detecting unauthorized modifications, and tracking changes over time.

## Features

| Feature | Description |
|---------|-------------|
| **Hash Validation** | SHA-256 content hash verification |
| **Change Detection** | Hash-based modification detection with `fsi_sourcechange` recording *(scheduled monitoring coming soon)* |
| **Source Registry** | Centralized inventory of all knowledge sources |
| **Freshness Monitoring** | *Coming Soon* — Alert on stale or outdated content |
| **Audit Trail** | Validation results and source change records in Dataverse |

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
├────────────────────┬─────────────────────┬──────────────────────┤
│ Knowledge          │ Validation          │ Source               │
│ Source             │ Result              │ Change               │
└────────────────────┴─────────────────────┴──────────────────────┘
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

> **Coming Soon** — The solution template (`templates/RAGSourceValidator_1_0_0.zip`) is not yet available.

### 2. Register Knowledge Sources

> **Coming Soon** — `Register-KnowledgeSource.ps1` is not yet available. Register sources directly in Dataverse.

### 3. Capture Initial Baseline

> **Coming Soon** — `New-SourceBaseline.ps1` is not yet available. Run `Invoke-SourceValidation.ps1` to capture baselines automatically on first run.

### 4. Run Validation

```powershell
.\scripts\Invoke-SourceValidation.ps1 -Environment "https://your-org.crm.dynamics.com"
```

## Deployment

1. Import the solution ZIP into your Power Platform environment
2. Configure connection references (see prerequisites)
3. Register knowledge sources *(coming soon: `Register-KnowledgeSource.ps1`)*
4. Capture initial baseline *(coming soon: `New-SourceBaseline.ps1`)*
5. Activate cloud flows for scheduled validation

## Documentation

| Document | Description |
|----------|-------------|
| Prerequisites *(coming soon)* | Licensing and permission requirements |
| [Dataverse Schema](docs/dataverse-schema.md) | Table definitions |
| Source Registration *(coming soon)* | Adding knowledge sources |
| Validation Process *(coming soon)* | How validation works |
| Troubleshooting *(coming soon)* | Common issues |

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

Ensures content is current and not stale.

| Age | Status |
|-----|--------|
| < 7 days | Fresh |
| 7-30 days | Warning |
| > 30 days | Stale |

### Link Validation

For documents with references, validates all links are accessible.

## Alert Configuration

> **Coming Soon** — Alert functionality is not yet implemented. The tables and channels described below represent planned capabilities.

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

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | February 2026 | Initial release |

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Authentication failure | Expired token or insufficient SharePoint/Dataverse permissions | Re-authenticate; verify SharePoint Reader and Dataverse Reader roles |
| Hash mismatch on first run | No baseline captured for the source | Run `New-SourceBaseline.ps1` to establish initial hashes |
| Source not found | Incorrect URI or source moved/renamed | Verify source URI; re-register with `Register-KnowledgeSource.ps1` |
| Stale content alerts | Source not updated within freshness threshold | Review source update schedule; adjust threshold if appropriate |

### Logs

Review script output for `[ERROR]` entries. Enable verbose output with `-Verbose` flag.

## Support

For issues, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - RAG Source Validator v1.0.0*
