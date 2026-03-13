# Hallucination Feedback Tracker

> **Status:** Work In Progress — This solution currently contains documentation, a Dataverse schema specification, and a Python analysis script. Deployable Power Platform solution artifacts (solution.xml, customizations.xml, cloud flows, Dataverse entity definitions) are planned for a future release.

Feedback aggregation pipeline for tracking and analyzing hallucination patterns in AI agent outputs.

## Overview

The Hallucination Feedback Tracker collects user feedback, supervisor rejections, and automated checks to identify and analyze patterns in AI agent hallucinations, enabling targeted improvements and risk mitigation.

## Features

| Feature | Description | Status |
|---------|-------------|--------|
| **Multi-Source Collection** | Feedback from users, supervisors, and automated checks | Planned |
| **Pattern Detection** | Identify recurring error patterns | Implemented |
| **Agent Comparison** | Compare accuracy across agents | Implemented |
| **Auto-Categorization** | Classify hallucination types automatically | Planned |
| **Trend Analysis** | Track hallucination rates over time | Planned |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                  Hallucination Tracker                           │
├─────────────────────────────────────────────────────────────────┤
│  Collector  │  Categorizer  │  Analyzer  │  Dashboard            │
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

### 4. Customer Complaints

Feedback derived from customer complaints routed through support channels.

| Signal | Weight | Description |
|--------|--------|-------------|
| Accuracy complaint | Critical | Customer reports factually incorrect information |
| Misleading response | High | Customer flags response as misleading |
| General dissatisfaction | Medium | Complaint citing poor answer quality |

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
| **Basic User** (or custom read-only role) | Dataverse table read access (the analysis script performs read-only queries) |
| **Power BI Creator** | Dashboard development |
| **Environment Maker** | Solution import |

### Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| FINRA Supervision Workflow | v1.0.0+ | Supervisor feedback source |

## Quick Start

### 1. Deploy Dataverse Schema

> **Note:** The solution ZIP and Power BI template are not yet available. See [Dataverse Schema](docs/dataverse-schema.md) for the table specification to create manually.

<!-- Future: pac solution import --path ./templates/HallucinationTracker_1_0_0.zip -->

### 2. Configure Feedback Sources

See [docs/source-configuration.md](docs/source-configuration.md).

### 3. Run Pattern Analysis

```python
python scripts/analyze_patterns.py --environment "https://your-org.crm.dynamics.com"
```

### 4. Deploy Dashboard

> **Note:** The Power BI template (`templates/HallucinationDashboard.pbit`) is planned for a future release.

## Deployment

> **Note:** Deployable solution artifacts are not yet available. The steps below describe the planned deployment workflow.

1. Import the solution ZIP into your Power Platform environment
2. Configure connection references (see prerequisites)
3. Configure feedback sources (see [docs/source-configuration.md](docs/source-configuration.md))
4. Activate cloud flows
5. Deploy the Power BI dashboard

## Documentation

| Document | Description |
|----------|-------------|
| [Prerequisites](docs/prerequisites.md) | Requirements |
| [Dataverse Schema](docs/dataverse-schema.md) | Table definitions |
| [Source Configuration](docs/source-configuration.md) | Connecting feedback sources |
| [Pattern Analysis](docs/pattern-analysis.md) | Detection algorithms |
| [Troubleshooting](docs/troubleshooting.md) | Common issues |

## Metrics

### Key Performance Indicators

| Metric | Target | Description |
|--------|--------|-------------|
| **Hallucination Rate** | < 2% | Flagged responses / total responses (current implementation uses rate-based weighted penalty scoring — see [Pattern Analysis](docs/pattern-analysis.md)) |
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

Pattern analysis uses frequency counting with frequency thresholds to identify recurring hallucination categories. The analyzer groups feedback by category and by agent, flagging any category with 3+ occurrences or any agent with 5+ reports as a pattern requiring investigation.

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

## Current Limitations

| Area | Status | Notes |
|------|--------|-------|
| **Solution Artifacts** | Not yet implemented | No solution.xml, customizations.xml, or cloud flow definitions |
| **DLP Enforcement** | Not yet implemented | No data loss prevention policies for feedback data |
| **Sharing Restrictions** | Not yet implemented | No security role definitions or row-level security |
| **Audit Logging** | Not yet implemented | No Dataverse auditing configuration |
| **Power BI Dashboard** | Not yet implemented | Template planned for future release |

> These controls are required for production use in regulated environments. The regulatory alignment
> claims below describe the *intended* coverage once the solution is fully implemented.

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
| 0.1.0-preview | February 2026 | Initial release |

## Support

For issues, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - Hallucination Feedback Tracker v0.1.0-preview*
