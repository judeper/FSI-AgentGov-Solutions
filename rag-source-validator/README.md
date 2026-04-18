# RAG Source Validator

> **Status:** Completed (v1.1.1)

Integrity validation for Retrieval-Augmented Generation (RAG) knowledge sources with change detection and audit capabilities.

## Overview

The RAG Source Validator helps verify AI agents use trusted, verified knowledge sources by continuously validating content integrity, detecting unauthorized modifications, and tracking changes over time.

## Features

| Feature | Description |
|---------|-------------|
| **Hash Validation** | SHA-256 content hash verification (binary-safe) |
| **Change Detection** | Content modification detection via hash comparison |
| **Source Registry** | Centralized inventory of all knowledge sources |
| **Freshness Monitoring** | Detect stale or outdated content (detection only; alert delivery not yet implemented) |
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

| Type | Content | Hash Method | Status |
|------|---------|-------------|--------|
| **SharePoint Document Library** | Documents | File content hash | ✅ Implemented |
| **SharePoint List** | Lists | Row checksum | 🔲 Planned |
| **SharePoint Page** | Pages | Page content hash | 🔲 Planned |
| **Dataverse** | Tables, rows | Row checksum | 🔲 Planned |
| **Azure Blob** | Files, containers | Blob content hash | 🔲 Planned |
| **Web API** | JSON responses | Response body hash | 🔲 Planned |
| **Database** | Queries, tables | Query result hash | 🔲 Planned |

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

### 1. Deploy Dataverse Schema (Manual)

The Dataverse schema must currently be created manually. The deployable solution package (`solution.xml`, managed/unmanaged `.zip`) is not yet available, so the solution cannot be imported via the Power Platform admin center or `pac` CLI at this time.

> **Note:** The Dataverse schema is documented in [docs/dataverse-schema.md](docs/dataverse-schema.md). Create the tables and columns manually or via `pac` CLI using the schema reference until the packaged solution is published.

### 2. Register Knowledge Sources

Register sources directly in the `fsi_knowledgesource` Dataverse table via the model-driven app or Dataverse API.

### 3. Run Validation

```powershell
.\scripts\Invoke-SourceValidation.ps1 -Environment "https://your-org.crm.dynamics.com"
```

For sovereign cloud environments (GCC High, DoD, China), specify the corresponding Graph and auth endpoints:

```powershell
# GCC High
.\scripts\Invoke-SourceValidation.ps1 -Environment "https://your-org.crm.microsoftdynamics.us" `
    -GraphBaseUrl "https://graph.microsoft.us" -AuthBaseUrl "https://login.microsoftonline.us"

# DoD
.\scripts\Invoke-SourceValidation.ps1 -Environment "https://your-org.crm.appsplatform.us" `
    -GraphBaseUrl "https://dod-graph.microsoft.us" -AuthBaseUrl "https://login.microsoftonline.us"

# 21Vianet China
.\scripts\Invoke-SourceValidation.ps1 -Environment "https://your-org.crm.dynamics.cn" `
    -GraphBaseUrl "https://microsoftgraph.chinacloudapi.cn" -AuthBaseUrl "https://login.chinacloudapi.cn"
```

> **Cross-validation:** The script validates that `GraphBaseUrl`, `AuthBaseUrl`, and `Environment` all target the same sovereign cloud. Mismatched combinations (e.g., commercial Graph URL with a GCC-High environment) will produce a clear error at startup.

The script automatically captures baselines on first run for sources without an existing hash.

## Deployment

1. Create the Dataverse schema manually in your Power Platform environment (see [Quick Start](#1-deploy-dataverse-schema-manual) for current status)
2. Set environment variables `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_CLIENT_SECRET` for service principal access (certificate-based authentication and managed identities are recommended for production but not yet supported by the script)
3. Register knowledge sources via the model-driven app or Dataverse API
4. Run `Invoke-SourceValidation.ps1` to capture baselines and validate
5. Configure scheduled execution via Task Scheduler, cron, or Azure Automation to run `Invoke-SourceValidation.ps1` on a recurring basis

## Documentation

| Document | Description |
|----------|-------------|
| [Dataverse Schema](docs/dataverse-schema.md) | Table definitions and choice values |

## Validation Types

### Content Hash Validation

Computes SHA-256 hash of source content and compares to stored baseline. Binary content (PDF, DOCX, XLSX) is hashed directly from the raw byte stream; text content is hashed as UTF-8.

> **Re-baseline required after upgrade from v1.0.0:** Versions prior to v1.0.1 coerced binary file content to a string before hashing, producing non-standard SHA-256 values. After upgrading, all sources with binary content will report hash mismatches on the first validation run. Run a full validation pass and approve the resulting changes to re-establish baselines.

```
Source Content → SHA-256 Hash → Compare to Baseline → Pass/Fail
```

### Schema Validation

> **Not yet implemented.** Result code 3 ("Failed - Schema Drift") is defined in the Dataverse schema but no code path currently produces it. This section describes planned functionality.

For structured data sources, validates schema hasn't changed.

| Check | Description |
|-------|-------------|
| Column count | Number of columns matches |
| Column names | Column names unchanged |
| Data types | Column types consistent |
| Constraints | Keys and relationships intact |

### Freshness Validation

Validates that content is current and not stale by comparing `fsi_lastmodified` against the per-source `fsi_freshnessthreshold` (in days).

> **Note:** The validation script reads `fsi_lastmodified` but does not update it. This field must be maintained externally (e.g., via Power Automate flows, SharePoint webhooks, or manual updates in the model-driven app).

| Condition | Status |
|-----------|--------|
| Within threshold | Fresh |
| Exceeds threshold | Stale (result = 4) |

### Link Validation

> **Not yet implemented.** No result code for link validation exists in the Dataverse schema and no code path currently performs it. This section describes planned functionality.

For documents with references, validates all links are accessible.

## Alert Configuration

> **Not yet implemented.** The validation script detects alert-enabled sources but alert delivery (email, Teams, Power Automate, webhooks) is not yet functional. This section describes planned functionality.

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

### SEC Rule 17a-4

> Records must be preserved in a non-rewriteable, non-erasable format.

**Coverage:** Hash validation helps verify records haven't been altered.

> **Limitation:** Validation results are currently stored in standard mutable Dataverse records, which do not satisfy WORM (Write Once Read Many) requirements. Production deployments requiring full SEC Rule 17a-4 compliance should integrate an immutable audit trail (e.g., Azure Immutable Blob Storage, or a third-party WORM-compliant archive) to store validation results alongside Dataverse records.

### FINRA Rule 4511(a)

> Books and records must be accurate and complete.

**Coverage:** Change detection identifies unauthorized modifications.

### SOX Section 404

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
| 1.1.1 | April 2026 | Binary content hashing fix; freshness timezone fix; source status updates; non-zero exit code on validation failures |
| 1.1.0 | March 2026 | Governance scripts (Export-ValidationEvidence, Get-SourceValidationSummary, Test-EvidenceIntegrity); sovereign cloud support |
| 1.0.1 | March 2026 | Binary-safe SHA-256 hashing for non-text content |
| 1.0.0 | February 2026 | Initial release |

## Troubleshooting

### Known Limitations

| Limitation | Details |
|------------|---------|
| **SharePoint direct URLs** | The script acquires a Graph API-scoped token only. Sources registered with direct SharePoint REST API URLs (`https://contoso.sharepoint.com/_api/...`) will fail authentication. Use Graph API URLs (`https://graph.microsoft.com/v1.0/sites/...`) instead. |
| **Binary hash re-baseline** | Upgrading from v1.0.0 changes how binary content is hashed. See [Content Hash Validation](#content-hash-validation) for re-baseline instructions. |
| **Trust-on-first-use baseline** | On first run (or when no baseline hash exists), the script captures the current content hash as the trusted baseline. If a source is already compromised at that point, the tampered content becomes the trusted reference. Operators should verify source integrity out-of-band before or shortly after the initial baseline capture, especially in SEC Rule 17a-4 and FINRA Rule 4511(a) contexts. |
| **No automated tests** | `Invoke-SourceValidation.ps1` does not have automated test coverage. For compliance-critical deployments (SEC Rule 17a-4, FINRA Rule 4511(a), SOX Section 404), consider adding unit tests for hash computation, SSRF URI validation, sovereign cloud cross-validation, freshness threshold arithmetic, result-to-status mapping, and status-transition logic before production use. |

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Authentication failure | Expired token or insufficient SharePoint/Dataverse permissions | Re-authenticate; verify SharePoint Reader and Dataverse Reader roles |
| Hash mismatch on first run | No baseline captured for the source | Run `Invoke-SourceValidation.ps1` — baselines are captured automatically on first run |
| Source not found | Incorrect URI or source moved/renamed | Verify source URI; re-register via the model-driven app or Dataverse API |
| Stale content alerts | Source not updated within freshness threshold | Review source update schedule; adjust threshold if appropriate |
| Source excluded from validation | Source status changed to Validation Failed (3) or Stale (4) by a prior run | Reset source status to Active (1) in the model-driven app or via Dataverse API. See [Source Status Lifecycle](#source-status-lifecycle) below. |

### Source Status Lifecycle

When validation detects a failure (hash mismatch, source unavailable, unexpected error) or staleness, the script updates the source's `fsi_status` to **Validation Failed** (3) or **Stale** (4). On subsequent runs, the OData query filters to `fsi_status eq 1` (Active only), so **non-Active sources are silently excluded from all future validation runs** until an operator manually resets their status to Active (1).

This design prevents repeated alerts for known-broken sources but has compliance implications:

| Concern | Detail |
|---------|--------|
| **Transient failures** | A temporary SharePoint outage permanently removes the source from automated validation with no automatic retry. |
| **SEC Rule 17a-4 / FINRA Rule 4511(a)** | Sources that drop out of monitoring create compliance gaps if not promptly re-activated. |
| **`-SourceId` targeting** | If a specific source is targeted with `-SourceId` but has non-Active status, the script exits with code 2 and a warning instead of silently reporting success. |

**Recommended mitigations:**

1. **Monitor exit codes** — exit code 2 indicates no sources were validated (distinct from exit code 1 for validation failures)
2. **Scheduled status audit** — periodically query Dataverse for sources with `fsi_status ne 1` and alert on sources that have been non-Active for more than a defined period
3. **Review validation logs** — the script logs `WARNING` entries when zero sources are found, including guidance on status resets

> **Note:** Automatic retry or re-validation of non-Active sources is not currently implemented. This requires policy decisions (retry count, backoff strategy, whether to include non-Active sources in a secondary pass) and is planned for a future release.

### Logs

Review script output for `FAILED` and `WARNING` entries displayed in the console during validation.

For persistent logging (recommended for scheduled execution via Task Scheduler, cron, or Azure Automation), use the `-LogFile` parameter:

```powershell
.\scripts\Invoke-SourceValidation.ps1 -Environment "https://your-org.crm.dynamics.com" -LogFile "validation.log"
```

Log entries are written in `YYYY-MM-DDTHH:mm:ss.fffZ [LEVEL] Message` format (UTC timestamps, UTF-8 encoded).

## Support

For issues, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - RAG Source Validator v1.1.1*
