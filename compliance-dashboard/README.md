# Compliance Dashboard

> **Status:** Work In Progress

Aggregated compliance reporting dashboard for the FSI Agent Governance Framework, providing unified visibility across all 62 controls with zone-based filtering.

## Overview

The Compliance Dashboard aggregates compliance data from multiple Microsoft 365 and Power Platform sources to provide a unified view of your AI agent governance posture. It supports regulatory reporting requirements for SOX 404, FINRA 3120, and OCC 2011-12.

> **Beta Status:** This solution is currently in beta (v1.0.0-beta). The Power BI template (.pbit) requires manual creation based on the specifications in docs/power-bi-setup.md. Once the template is complete and tested, the solution will move to v1.0.0.

## Features

| Feature | Description |
|---------|-------------|
| **Executive Summary** | Overall compliance score with trend indicators |
| **Pillar Breakdown** | Compliance status by pillar (Security, Management, Reporting, SharePoint) |
| **Zone Filtering** | Filter by governance zone (Zone 1/2/3) |
| **Control Drill-Down** | Detailed status for each of 62 controls |
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
                              │ Power Automate Flows
                              │
┌─────────────┬───────────────┬───────────────┬───────────────────┐
│ Purview     │ Power Platform│ Environment   │ Supervision       │
│ Compliance  │ Admin Center  │ Lifecycle     │ Workflow          │
│ Manager     │               │ Management    │                   │
└─────────────┴───────────────┴───────────────┴───────────────────┘
```

## Data Sources

| Source | Data Collected | Refresh Frequency |
|--------|----------------|-------------------|
| **Purview Compliance Manager** | Compliance scores, assessment status | Daily |
| **Power Platform Admin Center** | Environment count, DLP policy status | Daily |
| **Environment Lifecycle Management** | Zone classification, governance status | Real-time |
| **FINRA Supervision Workflow** | Queue metrics, review completion rates | Hourly |
| **Purview Audit Log** | Compliance-relevant events | Daily |

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
| Compliance Administrator | Purview Compliance Manager API access |
| Power Platform Administrator | Environment and DLP data |
| Power BI Admin | Workspace creation and sharing |
| System Administrator (Dataverse) | Table creation and data access |

### Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| Environment Lifecycle Management | v1.1.0+ | Zone classification data |
| FINRA Supervision Workflow | v1.0.0+ | Supervision metrics (optional) |

## Quick Start

### 1. Deploy Dataverse Schema

```powershell
# Import the Dataverse solution
pac solution import --path ./templates/ComplianceDashboard_1_0_0.zip
```

Or manually create tables using the schema in [docs/dataverse-schema.md](docs/dataverse-schema.md).

### 2. Configure Power Automate Flows

Deploy the data collection flows:

1. **Compliance Score Collector** - Daily Purview Compliance Manager sync
2. **Environment Status Collector** - Daily Power Platform status sync
3. **Exception Aggregator** - Consolidates exceptions from all sources

See [docs/flow-configuration.md](docs/flow-configuration.md) for detailed setup.

### 3. Deploy Power BI Report

1. Download the Power BI template from `templates/ComplianceDashboard.pbit`
2. Open in Power BI Desktop
3. Configure Dataverse connection parameters
4. Publish to Power BI Service

See [docs/power-bi-setup.md](docs/power-bi-setup.md) for detailed instructions.

### 4. Load Sample Data (Optional)

For demonstration purposes, load the sample data:

```powershell
python scripts/load_sample_data.py --environment "https://your-org.crm.dynamics.com"
```

## Documentation

| Document | Description |
|----------|-------------|
| [Prerequisites](docs/prerequisites.md) | Detailed licensing and permission requirements |
| [Dataverse Schema](docs/dataverse-schema.md) | Table definitions and relationships |
| [Flow Configuration](docs/flow-configuration.md) | Power Automate flow setup |
| [Power BI Setup](docs/power-bi-setup.md) | Dashboard deployment and customization |
| [DAX Measures](docs/dax-measures.md) | Calculation logic for compliance metrics |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and solutions |

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
Overall Score = Σ(Control Score × Control Weight) / Σ(Control Weight)

Where:
- Control Score: 0 (Non-Compliant), 50 (Partial), 100 (Compliant)
- Control Weight: Based on zone and regulatory impact
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

### SOX 404 Support

- Control assessment documentation
- Evidence collection and linking
- Exception tracking with remediation timelines
- Quarterly attestation support

### FINRA 3120 Support

- Supervisory control testing results
- Annual review documentation
- Exception escalation tracking

### OCC 2011-12 Support

- Model risk assessment status
- Validation tracking
- Ongoing monitoring metrics

## Related Controls

| Control | Relationship |
|---------|--------------|
| [3.1 - Agent Inventory](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.1-agent-inventory-and-metadata-management.md) | Agent count metrics |
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Usage trend data |
| [3.4 - Incident Reporting](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.4-incident-reporting-and-root-cause-analysis.md) | Exception correlation |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0-beta | February 2026 | Initial beta release (Power BI template requires manual creation) |

## Support

For issues and feature requests, see the [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues) repository.

---

*FSI Agent Governance Framework - Compliance Dashboard v1.0.0*
