# Governance Mapping

This document maps Agent Observability Foundation artifacts to FSI-AgentGov framework controls with tiered evidence indicators and regulatory citations.

## Overview

The governance mapping uses an **artifact-first approach**: each observability component is documented with the framework controls it supports. Evidence contributions are classified using a three-tier model to clarify the strength of each artifact's role in satisfying compliance requirements.

### Evidence Tier Definitions

| Tier | Indicator | Meaning |
|------|-----------|---------|
| **Primary evidence** | The artifact directly satisfies the control's evidence requirement |
| **Supporting evidence** | The artifact provides supplementary evidence alongside other controls |
| **Partial coverage** | The artifact provides some evidence but additional artifacts are needed (often from future phases) |

> **Regulatory Language Note:** This document uses hedging language ("helps support", "aids in meeting") per FSI-AgentGov CONTRIBUTING.md guidelines. No control or artifact should be described as independently satisfying a compliance obligation. Implementation, validation, and ongoing maintenance are required for compliance.

---

## Phase 1 Artifacts

### Application Insights Workspace

**Description:** Workspace-based Application Insights component with 730-day retention capturing Copilot Studio CopilotInteraction customEvents.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [1.7 - Comprehensive Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) | Complete audit trail of agent interactions | SEC 17a-4(b)(4) - 3-year communications retention (first 2 years easily accessible), FINRA 4511 - Books and records |
| [3.2 - Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Session metrics, message volumes, interaction patterns | Operational visibility requirement |

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.9 - Agent Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Latency telemetry, response time tracking | SR 11-7 - Model performance monitoring |

**Partial coverage for:**

| Control | Gap | Resolution |
|---------|-----|------------|
| [2.6 - Model Risk Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.6-model-risk-management-sr-26-2.md) | Telemetry available; KQL queries needed for governance evidence extraction | Delivered in v1.1.0: KQL Query Library (see queries/) |

---

### Log Analytics Workspace (730-Day Retention)

**Description:** PerGB2018 SKU workspace with 730-day interactive retention providing real-time KQL query capability.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [1.7 - Comprehensive Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) | 2-year interactive query access | SEC 17a-4(b)(4) - "easily accessible place" for first 2 years |
| [3.2 - Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Real-time KQL query capability | Operational analytics requirement |

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|

**Partial coverage for:**

| Control | Gap | Resolution |
|---------|-----|------------|
| [3.1 - Operational Dashboards](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.1-agent-inventory-and-metadata-management.md) | Workspace foundation established; visualization needed | Delivered in v1.1.0: Azure Monitor Workbooks (see workbooks/) |

---

### StorageV2 Storage Export

**Description:** StorageV2 storage account (hierarchical namespace disabled) receiving Diagnostic Settings exports with WORM policy capability for immutable archival.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [1.7 - Comprehensive Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) | Immutable storage for audit records | SEC 17a-4(f) - WORM storage requirement (Cohasset validated) |

**Supporting evidence for:**

| Regulation | Requirement | How This Artifact Supports |
|------------|-------------|---------------------------|
| SOX 302/404 | Internal controls evidence preservation | Long-term retention with immutability option |

**Partial coverage for:**

| Regulation | Gap | Resolution |
|------------|-----|------------|
| FINRA 4511 | 6-year retention achievable with WORM | Manual WORM policy configuration per [worm-configuration.md](docs/worm-configuration.md) |

---

### RBAC Separation

**Description:** Role assignments establishing distinct access paths for operational monitoring (Monitoring Reader) and compliance audit (Storage Blob Data Reader).

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [1.4 - Advanced Connector Policies](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.4-advanced-connector-policies-acp.md) | Role-based access to telemetry | Access control requirement |
| [2.8 - Access Control and Segregation of Duties](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.8-access-control-and-segregation-of-duties.md) | Distinct roles for operational and compliance functions | SOX 302/404 - Segregation of duties |

---

### PII Sanitization Guidance

**Description:** Decision framework and field-level recommendations for handling PII in Copilot Studio customDimensions telemetry.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| (informational adjacency — AOF documents PII-handling guidance for telemetry; primary GLBA 501(b) controls are delivered by Microsoft Purview / DLP) | PII telemetry-handling guidance | GLBA 501(b) (adjacent) |

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|

**Partial coverage for:**

| Control | Gap | Resolution |
|---------|-----|------------|
| [1.7 - Comprehensive Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) | Sanitized logs meet retention requirements | Implementation of guidance in Copilot Studio settings |

---

### Sampling and Cost Management

**Description:** Configuration guidance for ingestion sampling rates and Azure Monitor cost alert thresholds.

**Supporting evidence for:**

| Control | Requirement | Impact |
|---------|-------------|--------|
| [2.9 - Agent Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Sampling affects metric accuracy | Trade-off documentation |
| [3.2 - Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Sampling affects event counts | Analytics accuracy consideration |

---

## Delivered Phases

### Phase 2: KQL Query Library (Delivered in v1.1.0)

**Artifacts:** 14 production KQL queries across 5 categories (compliance, performance, usage-analytics, error-categorization, sr11-7-model-risk)

**Provides evidence for:**

| Control | Evidence Type |
|---------|---------------|
| [1.7 - Comprehensive Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) | Structured audit trail extraction queries |
| [3.2 - Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Session analytics and trend analysis |
| [2.9 - Agent Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | P50/P95/P99 latency distribution queries |
| [2.6 - Model Risk Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.6-model-risk-management-sr-26-2.md) | Decision audit trail and model output analysis |

---

### Phase 3: Workbooks and Alerts (Delivered in v1.1.0)

**Artifacts:** 3 Azure Monitor Workbooks (Operational Health, Error Diagnostics, Usage Overview), 3 Alert Rules (ALRT-01 through ALRT-03), 3 Zone-specific Action Groups

**Provides evidence for:**

| Control | Evidence Type |
|---------|---------------|
| [3.1 - Agent Inventory and Metadata Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.1-agent-inventory-and-metadata-management.md) | Visual inventory dashboard |
| [2.9 - Agent Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Proactive alerting on performance degradation |

---

### Phase 4: Power BI and Viva Insights (Coming)

**Artifacts:** PBI-01 (Executive Dashboard), PBI-02 (Compliance Report), VIVA-01 (Adoption Metrics), VIVA-02 (Productivity Correlation)

**Will provide evidence for:**

| Control | Evidence Type |
|---------|---------------|
| [3.1 - Agent Inventory and Metadata Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.1-agent-inventory-and-metadata-management.md) | Executive-level inventory visualization |
| [3.2 - Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Cross-agent usage comparison and business correlation |

---

## Regulatory Cross-Reference

| Regulation | Requirement | Phase 1 Coverage | Future Phase |
|------------|-------------|------------------|--------------|
| **SEC 17a-4** | 730-day retention + immutable storage (f) | App Insights + Log Analytics + Azure Blob Storage (StorageV2, HNS disabled) with WORM capability | Phase 5: Validation testing |
| **FINRA 4511** | 6-year record retention | Azure Blob Storage (StorageV2, HNS disabled) with WORM policy | Phase 2: Audit trail KQL queries |
| **FINRA 3110** | Supervisory procedures | Telemetry foundation | Phase 2: Decision audit KQL queries |
| **SOX 302/404** | Internal controls evidence | RBAC separation + immutable storage | Phase 2: Control evidence collection |
| **SR 11-7** | Model risk management and ongoing monitoring | Performance telemetry foundation | Phase 2: Risk monitoring KQL queries |
| **GLBA 501(b)** | Customer data protection | PII sanitization guidance | N/A (complete) |
| **FINRA Annual Oversight Report (2026)** | Agentic AI risk monitoring and governance | Telemetry foundation + zone-based alerting | Phase 2: Agentic AI-specific risk dashboards |

---

## Control Coverage Summary

> **Scope:** Per the catalog, this solution maps formally to controls **1.7, 2.8, 2.9, 3.2** only. Other controls below are listed as *informational adjacencies* (telemetry that may be useful when implementing those controls); they are not delivered by AOF and should not be cited as primary evidence for those controls.

| Control ID | Control Name | Phase 1 Artifacts | Evidence Tier |
|------------|--------------|-------------------|---------------|
| 1.7 | Comprehensive Audit Logging | App Insights, Log Analytics, Azure Blob Storage (StorageV2) | Primary (in scope) |
| 2.8 | Access Control and Segregation of Duties | RBAC Separation | Primary (in scope) |
| 2.9 | Agent Performance Monitoring | App Insights, Sampling Configuration | Primary (in scope) |
| 3.2 | Usage Analytics and Activity Monitoring | App Insights, Log Analytics | Primary (in scope) |
| 1.3 | SharePoint Content Governance | PII Sanitization Guidance | Adjacent (not delivered here) |
| 1.4 | Advanced Connector Policies | RBAC Separation | Adjacent (not delivered here) |
| 2.6 | Model Risk Management | App Insights (telemetry available) | Adjacent (not delivered here) |
| 3.1 | Operational Dashboards | Log Analytics (foundation) | Adjacent (workbook design only) |

> **Control 1.6 (DSPM for AI) is NOT mapped to this solution.** DSPM coverage is delivered by Microsoft Purview, not by AOF telemetry. Earlier drafts that listed 1.6 here were inaccurate.

---

*Governance Mapping version: 1.2.0*
*Last updated: April 2026*
