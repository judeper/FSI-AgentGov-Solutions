# Pattern Analysis

## Overview

The pattern analyzer (`scripts/analyze_patterns.py`) retrieves hallucination feedback from Dataverse and produces a report covering category distribution, severity distribution, source distribution, topic/channel/day distributions, agent risk scores, and detected patterns.

## Analysis Methods

### Category Distribution

Groups feedback by `fsi_category` and maps Dataverse option-set integers to human-readable labels via the `CATEGORIES` dictionary.

### Severity Distribution

Groups feedback by `fsi_severity` and maps option-set integers to labels (critical, high, medium, low) via the `SEVERITY_LABELS` dictionary. Missing severity values are labeled `unknown`.

### Source Distribution

Groups feedback by `fsi_source`, including user, supervisor, automated, customer, and Microsoft 365 Copilot Product Feedback export sources.

### Topic and Channel Distribution

When source data provides metadata, the analyzer groups records by:

- `fsi_topicname` or `fsi_topicid` for topic-level clusters.
- `fsi_channelid` for channel-level review.
- `fsi_reportedat` or `createdon` for daily feedback volume.

These fields support current Microsoft Learn guidance that Copilot Studio reactions/comments are stored with conversation transcripts and that session transcript downloads include `TopicName`, `TopicId`, `ChannelId`, `CSAT`, and `Comments`.

### Agent Risk Scoring

Calculates a risk score (0–100) per agent based on weighted severity of reported issues. This is not an accuracy rate because the denominator is the agent's hallucination report count, not total response volume.

| Severity | Weight |
|----------|--------|
| Critical | 4 |
| High | 3 |
| Medium | 2 |
| Low / Unknown | 1 |

**Formula:** `score = max(0, 100 - min((weighted_issues / total_reports) × 25, 100))`

Agents with fewer than three reports return `InsufficientData` because a single low-volume report can dominate the score.

| Score Range | Rating | Action |
|-------------|--------|--------|
| 95–100 | Excellent | Continue monitoring |
| 85–94 | Good | Review flagged items |
| 70–84 | Needs Improvement | Targeted retraining |
| < 70 | Critical | Immediate intervention |

### Pattern Detection

Identifies recurring patterns using frequency thresholds:

- **Category cluster:** Any category with 3+ occurrences.
- **Agent cluster:** Any agent with 5+ reports.
- **Topic cluster:** Any topic with 3+ reports when topic metadata is populated.
- **Time spike:** A UTC day with at least three reports and at least 2× the observed daily average for the analysis window.

## Current best practices

- Normalize negative-feedback records with topic, agent, channel, source, timestamp, and comment fields before clustering.
- Keep raw prompt/response/comment fields subject to tenant data-handling approvals and retention policy.
- Use deterministic thresholds for operational triage, then review clusters manually before remediation.
- Compare feedback spikes with recent releases, knowledge-source changes, prompt updates, or incidents.
- Use Microsoft Foundry evaluations for offline regression testing and post-production sampled evaluation where approved. Built-in evaluators include groundedness and relevance metrics, and Foundry cluster analysis can help triage evaluation failures.
- Treat Azure AI Content Safety groundedness detection as an optional automated signal. The groundedness API is documented as preview; validate API version, region availability, and data-handling requirements before production use.

## Usage

### Microsoft 365 Product Feedback import

```bash
python scripts/import_product_feedback_csv.py \
  --input exports/product-feedback.csv \
  --output normalized-product-feedback.json \
  --dry-run

python scripts/import_product_feedback_csv.py \
  --input exports/product-feedback.csv \
  --output dataverse \
  --environment-url https://your-org.crm.dynamics.com \
  --interactive
```

Imported rows land in `fsi_hallucinationreports` with `fsi_source = 100000004`; `analyze_patterns.py` reads them directly for source, topic, channel, and day-level analysis.

### Live Mode

```bash
# Preferred for Azure-hosted automation: managed identity / workload identity.
python scripts/analyze_patterns.py --environment "https://your-org.crm.dynamics.com"
```

### Legacy dev-only client-secret fallback

```bash
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"

python scripts/analyze_patterns.py --environment "https://your-org.crm.dynamics.com"
```

### Dry Run (Sample Data)

```bash
python scripts/analyze_patterns.py --environment "https://example.crm.dynamics.com" --dry-run
```

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--environment` | (required) | Dataverse environment URL |
| `--days` | 30 | Analysis period in days |
| `--dry-run` | false | Use sample data instead of live API |
| `--format` | text | Output format (`text` or `json`) |
| `--verbose` / `-v` | false | Verbose output |

## Future Enhancements

- CSV/Dataverse importer for Copilot Studio transcript reactions and comments.
- Semantic clustering and similarity search after governance approval for prompt/response/comment data handling.
- Dedicated CSAT and groundedness score columns if product-team review confirms reporting requirements.
- Automated remediation recommendations.
