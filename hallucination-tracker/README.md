# Hallucination Feedback Tracker

> **Status:** Work In Progress
>
> **Known Gaps:**
> - Power Platform solution artifacts (solution.xml, customizations.xml, workflow definitions, canvas app files, Dataverse table definitions) are not yet included — create tables manually using the [Dataverse Schema](#dataverse-schema) section
> - Solution package and Power BI template files are planned for a future release
>
> **FSI Governance Gaps:**
> The following controls are required for FSI compliance but are not yet implemented:
> - **DLP Enforcement:** No Data Loss Prevention policies are applied to the Dataverse tables or Power Automate flows. Feedback data containing PII or regulated content may flow to unintended connectors. A DLP policy scoping the environment to approved connectors (Dataverse, Office 365, Power BI) must be configured before production use.
> - **Audit Logging:** Dataverse standard auditing is not enabled on the feedback tables. Read/write/delete operations are not tracked. Enable Dataverse auditing on all `fsi_` tables and configure log retention per your organization's record-keeping requirements.
> - **Sharing Restrictions:** No role-based access controls or sharing rules are defined for feedback data. By default, any user with Dataverse access can read all hallucination reports. Security roles restricting access to authorized compliance and supervisory personnel must be created before deployment.

Feedback aggregation pipeline for tracking and analyzing hallucination patterns in AI agent outputs.

## Overview

The Hallucination Feedback Tracker collects user feedback, supervisor rejections, and automated checks to identify and analyze patterns in AI agent hallucinations, enabling targeted improvements and risk mitigation.

## Features

| Feature | Description |
|---------|-------------|
| **Multi-Source Collection** | Feedback from users, supervisors, and automated checks |
| **Auto-Categorization** | Classify hallucination types automatically (Planned) |
| **Pattern Detection** | Identify recurring error patterns |
| **Trend Analysis** | Track hallucination rates over time (Planned) |
| **Agent Comparison** | Compare accuracy across agents |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                  Hallucination Tracker                           │
├─────────────────────────────────────────────────────────────────┤
│  Collector  │  Categorizer (Planned)  │  Analyzer  │  Dashboard  │
└─────────────┴───────────────┴────────────┴──────────────────────┘
                              ▲
                              │ Analysis
                              │
┌─────────────────────────────────────────────────────────────────┐
│                    Dataverse (Feedback Store)                    │
├────────────────┬────────────────┬────────────────┬──────────────┤
│ Hallucination  │ Feedback       │ Pattern        │ Agent        │
│ Report         │ Source         │ Analysis       │ Score        │
└────────────────┴────────────────┴────────────────┴──────────────┘
                              ▲
                              │ Feedback Sources
                              │
┌─────────────┬───────────────┬───────────────┬───────────────────┐
│ User        │ Supervisor    │ Automated     │ Customer          │
│ Thumbs-Down │ Rejections    │ Checks        │ Complaints        │
│             │               │               │ (Planned)         │
└─────────────┴───────────────┴───────────────┴───────────────────┘
```

## Feedback Sources

### 1. User Feedback

Direct user reactions captured via Copilot Studio feedback mechanism.

| Signal | Weight | Description |
|--------|--------|-------------|
| Thumbs down | High | User explicitly marks response as wrong |
| Regenerate request | Medium | User asks for different answer |
| Abandonment | Low | User leaves without completing task |

### 2. Supervisor Rejections

Feedback from FINRA Supervision Workflow.

| Signal | Weight | Description |
|--------|--------|-------------|
| Factual rejection | Critical | Supervisor marks content as factually incorrect |
| Citation missing | High | Required citation not provided |
| Needs revision | Medium | Content requires modification |

### 3. Automated Checks

Programmatic verification where possible.

| Check | Capability | Limitation |
|-------|------------|------------|
| Citation verification | Verify cited sources exist | Cannot verify accuracy of content |
| Date validation | Check dates are plausible | Limited to format checking |
| Number sanity | Flag outlier numeric values | Context-dependent |

## Hallucination Categories

| Category | Description | Example |
|----------|-------------|---------|
| **Factual Error** | Incorrect statement of fact | "The S&P 500 was founded in 1892" |
| **Fabricated Data** | Made-up statistics or figures | "Our fund returned 45% last year" (false) |
| **Citation Missing** | Claim without required source | Unsubstantiated performance claim |
| **Outdated Info** | Stale information presented as current | Old regulatory guidance |
| **Confidence Overstatement** | Uncertain info stated as fact | "This will definitely..." |

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows |
| **Dataverse capacity** | Feedback storage |
| **Power BI Pro** | Dashboard visualization |

### Permissions

| Role | Required For |
|------|--------------|
| **System Administrator** | Dataverse table access |
| **Power BI Creator** | Dashboard development |

### Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| FINRA Supervision Workflow | v1.0.0+ | Supervisor feedback source |

## Dataverse Schema

The following tables must be created manually in your Dataverse environment. All tables use the `fsi_` publisher prefix.

### Hallucination Report (`fsi_hallucinationreport`)

| Column Logical Name | Display Name | Data Type | Description |
|---------------------|--------------|-----------|-------------|
| `fsi_hallucinationreportid` | Hallucination Report | Unique Identifier (PK) | Auto-generated primary key |
| `fsi_category` | Category | Choice (Option Set) | Hallucination type — see values below |
| `fsi_severity` | Severity | Choice (Option Set) | Issue severity — see values below |
| `fsi_agentid` | Agent ID | Single Line of Text | Identifier of the AI agent that produced the hallucination |
| `createdon` | Created On | Date and Time | System-managed record creation timestamp |

**`fsi_category` option set values:**

| Value | Label |
|-------|-------|
| 100000000 | Factual Error |
| 100000001 | Fabricated Data |
| 100000002 | Citation Missing |
| 100000003 | Outdated Info |
| 100000004 | Confidence Overstatement |

**`fsi_severity` option set values:**

| Value | Label | Weight |
|-------|-------|--------|
| 100000000 | Low | 1 |
| 100000001 | Medium | 2 |
| 100000002 | High | 3 |
| 100000003 | Critical | 4 |

### Feedback Source (`fsi_feedbacksource`)

Stores metadata about where feedback originated (user thumbs-down, supervisor rejection, automated check).

### Pattern Analysis (`fsi_patternanalysis`)

Stores the output of pattern detection runs for historical tracking.

### Agent Score (`fsi_agentscore`)

Stores calculated accuracy scores per agent over time.

> **Note:** Feedback Source, Pattern Analysis, and Agent Score tables are used by planned Power Automate flows and Power BI dashboards not yet included in this release. Only the Hallucination Report table is required for the `analyze_patterns.py` script.

## Quick Start

### 1. Deploy Dataverse Schema

> **Note:** Solution package (`HallucinationTracker_1_0_0.zip`) is not yet available. Create the Dataverse tables manually using the schema defined in the [Dataverse Schema](#dataverse-schema) section above.

### 2. Configure Feedback Sources

Configure your Dataverse environment to receive feedback from users, supervisors, and automated checks as described in the Feedback Sources section above.

### 3. Run Pattern Analysis

```python
python scripts/analyze_patterns.py --environment "https://your-org.crm.dynamics.com"
```

### 4. Deploy Dashboard

> **Note:** Power BI dashboard template (`HallucinationDashboard.pbit`) is not yet available. Dashboard must be built manually using OData connection to your Dataverse environment.

## Deployment

> **Note:** The solution package, cloud flows, and Power BI template are not yet available. The steps below describe the intended deployment process for a future release.

1. Import the solution ZIP into your Power Platform environment
2. Configure connection references (see prerequisites)
3. Configure feedback sources (see Feedback Sources section above)
4. Activate cloud flows
5. Deploy the Power BI dashboard

## Documentation

> **Note:** Detailed documentation is planned for a future release. See the sections below for current guidance on prerequisites, schema, and configuration.

## Metrics

### Key Performance Indicators

| Metric | Target | Description |
|--------|--------|-------------|
| **Hallucination Rate** | < 2% | Flagged responses / total responses |
| **Critical Rate** | < 0.1% | Critical hallucinations / total |
| **Resolution Time** | < 24 hours | Time to address reported issue |
| **Repeat Rate** | < 10% | Same error recurring after fix |

### Agent Scorecard

| Score | Rating | Action |
|-------|--------|--------|
| 95-100 | Excellent | Continue monitoring |
| 85-94 | Good | Review flagged items |
| 70-84 | Needs Improvement | Targeted retraining |
| < 70 | Critical | Immediate intervention |

## Pattern Detection

### Pattern Analysis

Pattern analysis uses frequency counting with fixed thresholds to identify recurring hallucination categories. The analyzer groups feedback by category and by agent, flagging any category with 3+ occurrences or any agent with 5+ reports as a pattern requiring investigation.

> **Note:** Advanced pattern detection (clustering, semantic similarity) is planned for a future release.

### Root Cause Analysis

| Pattern | Likely Cause | Remediation |
|---------|--------------|-------------|
| Topic clustering | Knowledge gap | Add training data |
| Time-based spike | Model update | Review recent changes |
| Agent-specific | Configuration issue | Audit agent setup |
| Source-linked | Bad RAG source | Validate source integrity |

## Integration

### FINRA Supervision Workflow

Supervisor rejections automatically feed into hallucination tracking:

```
Supervisor Rejects → Categorize → Pattern Analysis → Remediation
```

### Compliance Dashboard

Hallucination metrics contribute to Control 3.10 status in Compliance Dashboard.

## Regulatory Alignment

### FINRA 2210 - Communications

> Communications must be fair, balanced, and not misleading.

**Coverage:** Tracks factual accuracy of agent communications.

### SEC Marketing Rule

> Substantiation required for material claims.

**Coverage:** Monitors citation compliance.

### CFPB Chatbot Guidance

> Chatbots must provide accurate information.

**Coverage:** Systematic accuracy tracking.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.9 - Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Quality metrics |
| [2.12 - Supervision](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.12-supervision-and-oversight-finra-rule-3110.md) | Supervisor feedback |
| [3.10 - Hallucination Feedback Loop](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.10-hallucination-feedback-loop.md) | Primary control for hallucination tracking |
| [3.4 - Incident Reporting](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.4-incident-reporting-and-root-cause-analysis.md) | Escalation |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | February 2026 | Initial release |

## Support

For issues, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - Hallucination Feedback Tracker v1.0.0*
