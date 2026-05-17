---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P2, P4, P5]
applicable_drivers:
  - ai_governance
  - business_strategy
  - technology_data
coe_function: optimize
---
# Hallucination Feedback Tracker

> **Version:** v1.2.0
> **Status:** Live
> **Validated against framework version:** v1.6.0

Feedback aggregation pipeline for tracking and analyzing hallucination patterns in AI agent outputs.

## Overview

The Hallucination Feedback Tracker collects user reactions, feedback comments, supervisor rejections, Microsoft 365 Copilot Product Feedback exports, customer complaints, and automated evaluation results to identify patterns in AI agent hallucinations. The solution normalizes those signals into Dataverse, then reports clusters by category, agent, topic, channel, and time window.

## Features

| Feature | Description | Status |
|---------|-------------|--------|
| **Multi-Source Collection** | Feedback from users, supervisors, Microsoft 365 Copilot exports, automated checks, and customer complaints | Documented |
| **Pattern Detection** | Identify recurring error patterns by category, agent, topic, channel, and day | Implemented |
| **Agent Comparison** | Compare risk profile across agents | Implemented |
| **Groundedness Signal** | Optional Azure AI Content Safety groundedness detection / Microsoft Foundry evaluation ingestion | Documented |
| **Trend Analysis** | Track hallucination report volume over time | Implemented (PowerShell weekly summary; Python daily distribution) |

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
│ Copilot     │ Microsoft 365 │ Supervisor    │ Automated /       │
│ Studio      │ Copilot       │ Rejections    │ Customer Sources  │
└─────────────┴───────────────┴───────────────┴───────────────────┘
```

## Feedback Sources

### 1. Copilot Studio custom-agent reactions

Copilot Studio custom agents can collect thumbs-up/thumbs-down reactions and comments for supported channels. Current Microsoft Learn guidance documents reactions as an Analytics feature that is on by default and configurable under **Settings > User feedback**. Feedback is visible in Analytics and stored with conversation transcript data in Dataverse; downloaded session CSV files include `SessionID`, `TopicName`, `TopicId`, `ChannelId`, `CSAT`, and `Comments` fields.

| Signal | Weight | Description |
|--------|--------|-------------|
| Thumbs down + factual comment | High | User explicitly marks a response as wrong and explains the concern |
| Low CSAT with comment | Medium | Session-level dissatisfaction with usable comment context |
| Repeated topic comments | Medium | Multiple comments cluster around the same topic or knowledge source |

> **Channel caveat:** Agents published to the Microsoft 365 Copilot channel don't support Copilot Studio reactions. Use Microsoft 365 Product Feedback export for Microsoft 365 Copilot experiences.

### 2. Microsoft 365 Copilot Product Feedback

Microsoft 365 Copilot feedback is controlled by Microsoft 365 feedback policies. Administrators can view and export organizational feedback from **Microsoft 365 admin center > Health > Product Feedback**. Import exported rows into `fsi_hallucinationreports` with `fsi_source = 100000004`.

| Signal | Weight | Description |
|--------|--------|-------------|
| Copilot thumbs down | High | User flags a Microsoft 365 Copilot response as incorrect, incomplete, or not useful |
| Comment mentions unsupported claim | High | Feedback indicates missing citations or unsupported facts |
| Repeated app/workload feedback | Medium | Feedback clusters by Teams, Outlook, Word, or another app area |

Microsoft Graph Copilot interaction history can provide governed prompt/response context for licensed Microsoft 365 Copilot users, but it is not a feedback API and does not retrieve Copilot Studio agent interactions.

### 3. Supervisor Rejections

Feedback from FINRA Supervision Workflow.

| Signal | Weight | Description |
|--------|--------|-------------|
| Factual rejection | Critical | Supervisor marks content as factually incorrect |
| Citation missing | High | Required citation not provided |
| Outdated guidance | Medium | Content uses stale policy, product, or regulatory information |

### 4. Automated Checks

Programmatic verification where approved by governance and data-handling policy.

| Check | Capability | Limitation |
|-------|------------|------------|
| Azure AI Content Safety groundedness detection (preview) | Flags ungrounded generated content against supplied grounding sources | Preview API; validate region, API version, and data handling before production use |
| Microsoft Foundry evaluations | Offline/online evaluation for groundedness, relevance, safety, and quality | Requires curated datasets and evaluation governance |
| Citation verification | Verify cited sources exist | Does not by itself verify that the claim is correct |
| Date validation | Check dates are plausible/current | Limited to source data and rule quality |
| Number sanity | Flag outlier numeric values | Context-dependent |

### 5. Customer Complaints

Feedback derived from customer complaints routed through support channels.

| Signal | Weight | Description |
|--------|--------|-------------|
| Accuracy complaint | Critical | Customer reports factually incorrect information |
| Misleading response | High | Customer flags response as misleading or unsupported |
| General dissatisfaction | Medium | Complaint citing poor answer quality |

## Hallucination Categories

| Category | Dataverse value | Description | Example |
|----------|-----------------|-------------|---------|
| **Factual Error** | 100000000 | Incorrect statement of fact | "The S&P 500 was founded in 1892" |
| **Fabricated Data** | 100000001 | Made-up statistics or figures | "Our fund returned 45% last year" (false) |
| **Citation Missing** | 100000002 | Claim without required source | Unsubstantiated performance claim |
| **Outdated Info** | 100000003 | Stale information presented as current | Old regulatory guidance |
| **Confidence Overstatement** | 100000004 | Uncertain info stated as fact | "This will definitely..." |

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows or approved automation |
| **Dataverse capacity** | Feedback storage |
| **Power BI Pro** | Dashboard visualization |
| **Azure AI Content Safety** | Optional groundedness detection |
| **Microsoft Foundry project** | Optional evaluation and cluster analysis |

### Permissions

| Role | Required For |
|------|--------------|
| **Basic User** (or custom read-only role) | Dataverse table read access |
| **Bot Transcript Viewer** | Copilot Studio feedback comments/transcripts |
| **Power BI Creator** | Dashboard development |
| **Environment Maker** | Solution import |

### Authentication

Use managed identity first for Azure-hosted automation, workload identity federation for CI, and interactive/developer credentials for admin workstations. Client-secret authentication is a legacy development fallback only.

### Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| FINRA Supervision Workflow | v1.0.0+ | Supervisor feedback source |

## Quick Start

### 1. Deploy Dataverse Schema

```bash
# Generate schema documentation
python scripts/create_ht_dataverse_schema.py --output-docs

# Deploy schema (interactive admin workstation auth)
python scripts/create_ht_dataverse_schema.py \
    --tenant-id <tenant-id> \
    --environment-url https://your-org.crm.dynamics.com \
    --interactive

# Or dry run to preview
python scripts/create_ht_dataverse_schema.py \
    --tenant-id <tenant-id> \
    --environment-url https://your-org.crm.dynamics.com \
    --interactive --dry-run
```

See [Dataverse Schema](docs/dataverse-schema.md) for the full table specification.

### 2. Configure Feedback Sources

See [docs/source-configuration.md](docs/source-configuration.md).

### 3. Run Pattern Analysis

```powershell
# Preferred for Azure-hosted automation: managed identity or workload identity.
python scripts/analyze_patterns.py --environment "https://your-org.crm.dynamics.com"

# Legacy dev-only fallback — replace with managed identity in production.
$env:AZURE_TENANT_ID     = "<tenant-guid>"
$env:AZURE_CLIENT_ID     = "<app-registration-client-id>"
$env:AZURE_CLIENT_SECRET = "<client-secret>"
python scripts/analyze_patterns.py --environment "https://your-org.crm.dynamics.com"
```

Use `--dry-run` to validate the script with sample data without contacting Dataverse.

### 4. Deploy Dashboard

> **Note:** The Power BI template (`templates/HallucinationDashboard.pbit`) is planned for a future release. Use `Get-HallucinationSummary.ps1` for console-based reporting in the interim.

## Deployment

The Dataverse setup scripts (`create_ht_*.py`) support interactive admin-workstation authentication and non-interactive application-user authentication. Use managed identity or workload identity for production automation where available; `HT_CLIENT_SECRET` is a legacy development fallback.

1. Deploy Dataverse schema: `python scripts/create_ht_dataverse_schema.py --environment-url "https://your-org.crm.dynamics.com" --tenant-id "<tenant-id>" --interactive`
2. Create environment variables: `python scripts/create_ht_environment_variables.py --environment-url "https://your-org.crm.dynamics.com" --tenant-id "<tenant-id>" --interactive`
3. Create connection references: `python scripts/create_ht_connection_references.py --environment-url "https://your-org.crm.dynamics.com" --tenant-id "<tenant-id>" --interactive`
4. Configure feedback sources (see [docs/source-configuration.md](docs/source-configuration.md))
5. Build Power Automate flows or approved import scripts per source configuration documentation
6. Deploy the Power BI dashboard (template planned for future release)

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
| **Hallucination Rate** | < 2% | Flagged responses / total responses when total response volume is available |
| **Critical Rate** | < 0.1% | Critical hallucinations / total responses or total reports, depending on source denominator |
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

Pattern analysis uses frequency thresholds to identify recurring hallucination categories, agent-specific clusters, topic clusters, and daily spikes. The analyzer flags any category with 3+ occurrences, any agent with 5+ reports, any populated topic with 3+ reports, and any day with at least three reports and at least 2× the observed daily average.

> **Note:** Semantic similarity and Microsoft Foundry cluster analysis are recommended future enhancements after governance approval for prompt/response/comment data handling.

### Root Cause Analysis

| Pattern | Likely Cause | Remediation |
|---------|--------------|-------------|
| Topic clustering | Knowledge gap or prompt issue | Add approved training/knowledge content and retest |
| Time-based spike | Release, model, or source update | Review recent changes and incidents |
| Agent-specific | Configuration issue | Audit instructions, knowledge sources, and connectors |
| Source-linked | Bad RAG source | Validate source integrity |
| Groundedness failures | Unsupported response relative to source documents | Review grounding data and generation settings |

## Integration

### FINRA Supervision Workflow

Supervisor rejections feed into hallucination tracking:

```
Supervisor Rejects → Categorize → Pattern Analysis → Remediation
```

### Compliance Dashboard

Hallucination metrics contribute to Control 3.10 status in Compliance Dashboard.

## Current Limitations

| Area | Status | Notes |
|------|--------|-------|
| **Solution Artifacts** | Not implemented | No solution.xml, customizations.xml, or cloud flow definitions |
| **DLP Enforcement** | Not implemented | No data loss prevention policies for feedback data |
| **Sharing Restrictions** | Not implemented | No security role definitions or row-level security |
| **Audit Logging** | Partial | Dataverse table auditing is enabled in schema; environment-level audit configuration remains an admin responsibility |
| **Power BI Dashboard** | Not implemented | Template planned for future release |
| **Import Connectors** | Not implemented | Copilot Studio transcript and Microsoft 365 Product Feedback importers are documented patterns only |

> These controls are required for production use in regulated environments. The regulatory alignment
> claims below describe the *intended* coverage once the solution is fully implemented and configured.

## Regulatory Alignment

### FINRA Rule 2210 — Communications with the Public

> Communications must be fair, balanced, and not misleading.

**Coverage:** Helps track factual accuracy of agent communications. Implementation supports — but does not on its own satisfy — supervisory review obligations.

### SEC Rule 206(4)-1 (Investment Adviser Marketing Rule)

> Material claims in marketing communications must be substantiated.

**Coverage:** Helps monitor citation patterns to support substantiation evidence.

### CFPB Chatbot Guidance (June 2023, *Chatbots in Consumer Finance*)

> Chatbots in consumer finance must provide accurate information and avoid harm.

**Coverage:** Systematic accuracy tracking aids in detection of recurring inaccuracies.

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
| 1.2.0 | 2026-Q2 | Microsoft Learn refresh: feedback source guidance, managed-identity-first auth, enriched clustering fields |
| 1.1.0 | April 2026 | Dataverse and analyzer corrections |
| 1.0.0 | April 2026 | Full deployment scripts, governance automation, evidence export |
| 0.1.0-preview | February 2026 | Initial release |

## Support

For issues, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - Hallucination Feedback Tracker v1.2.0*
