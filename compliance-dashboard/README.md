# Compliance Dashboard

> **Status:** Completed

Aggregated compliance reporting dashboard for the FSI Agent Governance Framework, providing unified visibility across the control records loaded into Dataverse with zone-based filtering. The included sample dataset contains 62 controls; organizations should load the validated 78-control framework baseline before describing the dashboard as full-framework coverage.

## Overview

The Compliance Dashboard aggregates compliance data from Dataverse tables (populated by manual imports, the included score and exception flows, sample data, and the optional Exchange evidence collector) to provide a unified view of your AI agent governance posture. It helps support internal reporting used for **SOX Section 404** ICFR monitoring, **FINRA Rule 3120(a)(1)** supervisory control reporting, and **OCC Bulletin 2011-12 / FRB SR 11-7** model-risk governance where applicable. Organizations should verify scope, record categories, and supervisory procedures.

## Features

| Feature | Description |
|---------|-------------|
| **Executive Summary** | Overall compliance score with trend indicators |
| **Pillar Breakdown** | Compliance status by pillar (Security, Management, Reporting, SharePoint) |
| **Zone Filtering** | Filter by governance zone (Zone 1/2/3) |
| **Control Drill-Down** | Detailed status for each control loaded into Dataverse (sample dataset ships 62 controls; load the validated 78-control baseline to enable full-framework coverage) |
| **Trend Analysis** | Historical compliance tracking over time |
| **Exception Tracking** | Open exceptions with remediation status |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Power BI Dashboard                        │
├─────────────────────────────────────────────────────────────────┤
│  Executive   │  Pillar    │  Control   │  Exceptions  │  Trends │
│  Summary     │  Overview  │  Details   │  Tracker     │         │
└──────────────┴────────────┴────────────┴──────────────┴─────────┘
                              ▲
                              │ DirectQuery / Import
                              │
┌─────────────────────────────────────────────────────────────────┐
│                    Dataverse (Compliance Hub)                    │
├──────────────┬──────────────┬───────────────┬───────────────────┤
│ Control      │ Compliance   │ Compliance    │ Compliance        │
│ Assessment   │ Score        │ Exception     │ Evidence          │
└──────────────┴──────────────┴───────────────┴───────────────────┘
                              ▲
                              │ Power Automate Flows + Scripts
                              │
┌─────────────┬───────────────┬───────────────┬───────────────────┐
│ Purview     │ Power Platform│ Environment   │ Supervision       │
│ Compliance  │ Admin Center  │ Lifecycle     │ Workflow          │
│ Manager     │               │ Management    │                   │
├─────────────┴───────────────┴───────────────┴───────────────────┤
│ Exchange Online (Get-ExchangeComplianceData.ps1)                │
│ → Forwarding rules, DLP alerts, mailbox access, DL membership  │
└─────────────────────────────────────────────────────────────────┘
```

## Data Sources

| Source | Data Collected | Status | Refresh Frequency |
|--------|----------------|--------|-------------------|
| **Dataverse (Compliance Hub tables)** | Control master, assessments, scores, exceptions, evidence (populated by manual import or other solutions) | Implemented | On import |
| **Exchange Online (Get-ExchangeComplianceData.ps1)** | External forwarding rules, DLP alerts, mailbox access, DL membership | Implemented (script run on schedule; JSON output imported manually) | Scheduled (manual import) |
| **Purview Compliance Manager** | Compliance scores, assessment status | Planned (`CD-EvidenceCollector` flow not yet shipped) | — |
| **Power Platform Admin Center** | Environment count, DLP policy status | Planned | — |
| **Environment Lifecycle Management** | Zone classification, governance status | Optional dependency — populates Dataverse via the ELM solution | Real-time |
| **FINRA Supervision Workflow** | Queue metrics, review completion rates | Optional dependency — populates Dataverse via the FINRA solution | Hourly |
| **Purview Audit Log** | Compliance-relevant events | Planned | — |

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| Power BI Pro or Premium | Dashboard hosting and sharing |
| Dataverse capacity | Compliance data storage |
| Power Automate Premium | Data collection flows |
| Microsoft 365 E5 or E5 Compliance | Purview Compliance Manager access |

### Permissions

| Role | Required For |
|------|--------------|
| Purview Compliance Admin | Purview Compliance Manager API access |
| Power Platform Admin | Environment and DLP data |
| Power BI Admin | Workspace creation and sharing |
| System Administrator (Dataverse) | Table creation and data access |

### Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| Environment Lifecycle Management | v1.1.0+ | Zone classification data |
| FINRA Supervision Workflow | v1.0.0+ | Supervision metrics (optional) |
| Get-ExchangeComplianceData.ps1 | v1.0.3 | Exchange compliance signal collection (included) |

## Quick Start

Follow the comprehensive [Deployment Checklist](docs/deployment-checklist.md) for step-by-step deployment validation.

### 1. Deploy Dataverse Schema

Create the Dataverse tables manually following the schema definitions in [Dataverse Schema](docs/dataverse-schema.md). The solution does not ship a packaged `.zip` — tables, columns, and option sets are created through the Power Platform admin center or PAC CLI.

The schema includes:
- 5 Dataverse tables (control master, assessments, scores, exceptions, evidence)
- 2 Power Automate flows (score calculator, exception monitor)
- 3 security roles (Viewer, Assessor, Admin)

See [Dataverse Schema](docs/dataverse-schema.md) for table structure details.

### 2. Load Sample Data (Optional)

For demonstration and testing, load sample data:

```bash
# Set authentication environment variables
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"

# Load control master data into Dataverse
python scripts/load_sample_data.py --environment "https://your-org.crm.dynamics.com"

# Export all sample data (assessments, scores, exceptions) to JSON
python scripts/load_sample_data.py --export
```

> **⚠️ Security Note:** Avoid setting `AZURE_CLIENT_SECRET` directly in shell commands, as it may be recorded in shell history. For production deployments, use [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/), [`DefaultAzureCredential`](https://learn.microsoft.com/en-us/python/api/azure-identity/azure.identity.defaultazurecredential) from `azure-identity`, or managed identity instead.

> **Note:** The `--environment` mode currently uploads control master data only. Use `--export` to generate assessment, score, and exception JSON files, then import them via Power Apps or the Dataverse API.

> **Baseline Note:** Confirm the control master dataset reflects the validated 78-control framework baseline before importing it into Dataverse.

**Production Deployment:** Clear sample data before production use.

### 3. Build the Power BI Dashboard

The solution does not ship a pre-built `.pbit` template. Build it manually using Power BI Desktop following [Power BI Template Specification](docs/power-bi-template-spec.md):

1. Open Power BI Desktop and create a new report
2. Connect to your Dataverse environment using the Dataverse connector
3. Build pages, relationships, and measures per the template specification
4. Optionally save as a `.pbit` template for re-use within your organization
5. Publish to Power BI Service
6. Configure scheduled refresh (daily at 7:00 AM)

See [Power BI Setup](docs/power-bi-setup.md) for connector configuration and [Power BI Template Specification](docs/power-bi-template-spec.md) for complete page-by-page build instructions and the [DAX Measures](docs/dax-measures.md) reference for measure definitions.

### 4. Build and Activate Flows

Two Power Automate flows must be built manually following [Flow Configuration](docs/flow-configuration.md):

1. **CD-ScoreCalculator** (daily score calculation)
2. **CD-ExceptionMonitor** (hourly SLA monitoring)

After building each flow, turn it on and run a test execution to verify functionality.

> **Note:** A third flow, `CD-EvidenceCollector`, is documented as **planned** in [Flow Configuration](docs/flow-configuration.md) but is not yet implemented. Until it ships, evidence from the Exchange collector and other sources must be imported manually.

## Documentation

| Document | Description |
|----------|-------------|
| [Prerequisites](docs/prerequisites.md) | Detailed licensing and permission requirements |
| [Deployment Checklist](docs/deployment-checklist.md) | Step-by-step deployment validation checklist |
| [Dataverse Schema](docs/dataverse-schema.md) | Table definitions and relationships |
| [Flow Configuration](docs/flow-configuration.md) | Power Automate flow setup |
| [Power BI Setup](docs/power-bi-setup.md) | Dashboard deployment and customization |
| [Power BI Template Spec](docs/power-bi-template-spec.md) | Complete .pbit template creation instructions |
| [DAX Measures](docs/dax-measures.md) | Calculation logic for compliance metrics |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and solutions |

### Exchange Compliance Data Collection

The `Get-ExchangeComplianceData.ps1` script collects Exchange Online compliance signals via Microsoft Graph API. Run it as a scheduled task or on-demand to feed Exchange evidence into the dashboard.

```powershell
# Interactive mode
.\scripts\Get-ExchangeComplianceData.ps1 -Interactive

# Service principal mode
.\scripts\Get-ExchangeComplianceData.ps1 -TenantId "tenant.onmicrosoft.com" `
    -ClientId "00000000-0000-0000-0000-000000000001" `
    -CertificateThumbprint "ABC123DEF456"
```

**Data collected:**

| Signal | Risk Level | Description |
|--------|-----------|-------------|
| External forwarding rules | HIGH | Inbox rules forwarding to external addresses — data exfiltration vector |
| DLP policy alerts | MEDIUM-HIGH | DLP policy matches on Exchange workload |
| Inactive shared/unused mailboxes | MEDIUM | Mailboxes flagged as shared by `mailboxSettings.userPurpose` (or, when that filter is unavailable, disabled accounts that retain mailboxes); not an enumeration of mailbox permission grants |
| External distribution list members | MEDIUM | Mail-enabled groups with guest or external members |

**Configuration:** See `templates/exchange-config.sample.json` for scan scope, risk thresholds, and domain allow-list settings.

**Output:** JSON evidence file at `./output/exchange-compliance-report.json` — import into `fsi_complianceevidence` via Power Automate or Dataverse API for dashboard integration.

## Dashboard Pages

### 1. Executive Summary

- Overall compliance score (0-100)
- Trend indicator (improving/stable/declining)
- Critical exceptions count
- Zone distribution chart

### 2. Pillar Overview

- Pillar-by-pillar compliance scores
- Control count by status (Compliant/Partial/Non-Compliant)
- High-risk control indicators

### 3. Control Details

- Filterable control list
- Assessment status and last review date
- Evidence links
- Remediation actions

### 4. Exception Tracker

- Open exceptions by age
- Owner assignment
- SLA status
- Resolution trends

### 5. Trend Analysis

- 90-day compliance score trend
- Month-over-month comparison
- Seasonal patterns
- Forecasting (optional)

## Compliance Scoring

### Overall Score Calculation

```
Overall Score = Σ(Control Score × Control Weight × Zone Multiplier) / Σ(Control Weight × Zone Multiplier)

Where:
- Control Score: 0 (Non-Compliant), 50 (Partial), 100 (Compliant)
- Control Weight: Based on regulatory impact
- Zone Multiplier: See Zone Weighting table below
```

### Zone Weighting

| Zone | Weight Multiplier | Rationale |
|------|-------------------|-----------|
| Zone 1 | 1.0 | Personal productivity, lower risk |
| Zone 2 | 1.5 | Team collaboration, moderate risk |
| Zone 3 | 2.0 | Enterprise managed, highest risk |

### Control Status Definitions

| Status | Score | Definition |
|--------|-------|------------|
| **Compliant** | 100 | Control fully implemented and verified |
| **Partial** | 50 | Control partially implemented or pending verification |
| **Non-Compliant** | 0 | Control not implemented or failed verification |
| **Not Applicable** | N/A | Control excluded from scoring (with documented rationale) |

## Regulatory Alignment

### SOX Section 404 support

Supports evidence aggregation used in management's annual evaluation of internal control over financial reporting (ICFR). Firms should distinguish **application controls** from **IT general controls** and address **SOX Section 302** quarterly officer certifications separately.

- Control assessment documentation
- Evidence collection and linking
- Exception tracking with remediation timelines

### FINRA Rule 3120(a)(1) support

Supports aggregation of testing results and exception reporting used in a **reasonably designed** supervisory control system, in conjunction with written supervisory procedures under **FINRA Rule 3110(a)**. Subject to firm interpretation, sampling, and supervisory review procedures.

- Supervisory control testing results
- Annual review documentation
- Exception escalation tracking

### OCC Bulletin 2011-12 / FRB SR 11-7 support

Supports aggregation of validation and monitoring evidence **when the firm classifies the AI component as a model**. Organizations should document the model/non-model determination, validation scope, and governance responsibilities separately.

- Model risk assessment status
- Validation tracking
- Ongoing monitoring metrics

## Known Limitations

This section documents limitations and design decisions for the v1.0.x release.

| Limitation | Description | Workaround |
|------------|-------------|------------|
| **Manual .pbit creation** | Power BI template must be created manually using Power BI Desktop following [Power BI Template Specification](docs/power-bi-template-spec.md) | The specification provides step-by-step page-by-page build instructions |
| **Manual flow build** | Power Automate flows must be built manually following [Flow Configuration](docs/flow-configuration.md); no exported flow JSON ships in this solution per repository content policy | Use the manual build instructions; build once and optionally export to your own managed solution |
| **Sample dataset is 62 controls** | The shipped `sample-data/control-master.json` contains 62 controls (24 Pillar 1 + 21 Pillar 2 + 10 Pillar 3 + 7 Pillar 4); the validated framework baseline contains 78 | Extend `sample-data/control-master.json` and the `PillarDimension` `DATATABLE` in `docs/dax-measures.md` to your full control inventory |
| **Evidence collector flow not yet shipped** | The third flow `CD-EvidenceCollector` is documented as planned in `docs/flow-configuration.md` but not implemented | Import Exchange and other evidence JSON manually via Power Apps or the Dataverse Web API until the flow ships |
| **No automated validation** | Deployment validation uses manual checklist only, no automated testing scripts | Use [Deployment Checklist](docs/deployment-checklist.md) to verify each deployment step |
| **RLS not pre-configured** | Row-Level Security roles must be created by customer to match organizational structure | See [Power BI Setup](docs/power-bi-setup.md) for example RLS DAX patterns |
| **Sample data is demo only** | Sample data uses realistic distributions but should not be used in production environments | Manually delete records via Power Apps or Dataverse API before production use |
| **Pagination ceiling (100K records)** | All `ListRecords` actions in CD-ExceptionMonitor and CD-ScoreCalculator use `minimumItemCount: 100000`. Results are silently truncated beyond this limit with no runtime detection. | Enable Dataverse archival or add date-range filters to keep active record counts below 100,000 |
| **Exception count capped at 999** | The `fsi_exceptioncount` column has `MaxValue: 999`. The workflow caps the value with `min(..., 999)` to prevent Dataverse validation errors, but counts above 999 are underreported. | Increase the `MaxValue` on the column if your organization may exceed 999 open exceptions |
| **N+1 Dataverse update pattern** | `Update_Exception_Record` in CD-ExceptionMonitor issues individual `UpdateRecord` per exception inside a loop, which is inefficient at high volumes. | Migrate to Dataverse batch changeset (`$batch` endpoint) for large exception populations |

**Future Enhancements (planned for v1.1.0+):**
- Automated deployment validation script
- Pre-configured RLS templates for common org structures
- Quick Start deployment option with minimal configuration
- Upgrade migration toolkit for version transitions
- Managed solution variant for locked-down deployments

## Related Controls

| Control | Relationship |
|---------|--------------|
| [3.1 - Agent Inventory](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.1-agent-inventory-and-metadata-management.md) | Agent count metrics |
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Usage trend data |
| [3.3 - Compliance Reporting](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.3-compliance-reporting-and-attestation.md) | Aggregated compliance reporting |
| [3.4 - Incident Reporting](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.4-incident-reporting-and-root-cause-analysis.md) | Exception correlation |

## Rollback and Uninstall

If deployment issues are encountered, follow these steps to rollback:

### Quick Rollback

1. **Stop Power Automate flows:**
   - Navigate to Power Automate > Solutions > Compliance Dashboard
   - Turn off CD-ScoreCalculator and CD-ExceptionMonitor flows

2. **Delete Power BI report:**
   - In Power BI Service workspace, delete report and dataset
   - No data loss (data remains in Dataverse)

3. **Delete solution (optional):**
   - Navigate to Power Apps > Solutions
   - Delete "Compliance Dashboard" solution
   - Tables and data will be removed

### Complete Uninstall

For complete removal including all data:

1. Delete Power BI report and dataset
2. Turn off all flows in solution
3. Delete solution from Power Apps
4. (Optional) Manually delete Dataverse tables if solution deletion left remnants
5. (Optional) Manually delete sample data records via Power Apps or Dataverse API

See [Deployment Checklist - Rollback Procedure](docs/deployment-checklist.md#rollback-procedure) for detailed steps.

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.2 | April 2026 | Removed stale ZIP import references; updated Exchange script version |
| 1.0.1 | March 2026 | Removed exported Dataverse solution package per content policy |
| 1.0.0 | February 2026 | Production release with complete deployment artifacts |
| 1.0.0-beta | February 2026 | Initial beta release (Power BI template requires manual creation) |

See [CHANGELOG.md](CHANGELOG.md) for detailed release notes.

## Support

For issues and feature requests, see the [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues) repository.

---

*FSI Agent Governance Framework - Compliance Dashboard v1.0.3*
