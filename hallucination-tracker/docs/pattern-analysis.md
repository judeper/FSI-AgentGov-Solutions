# Pattern Analysis

## Overview

The pattern analyzer (`scripts/analyze_patterns.py`) retrieves hallucination feedback from Dataverse and produces a report covering category distribution, severity distribution, agent scores, and detected patterns.

## Analysis Methods

### Category Distribution

Groups feedback by `fsi_category` and maps Dataverse option-set integers to human-readable labels via the `CATEGORIES` dictionary.

### Severity Distribution

Groups feedback by `fsi_severity` and maps option-set integers to labels (critical, high, medium, low) via the `SEVERITY_LABELS` dictionary. Missing severity values are labeled "unknown".

### Agent Scoring

Calculates an accuracy score (0–100) per agent based on weighted severity of reported issues.

| Severity | Weight |
|----------|--------|
| Critical | 4 |
| High | 3 |
| Medium | 2 |
| Low / Unknown | 1 |

**Formula:** `score = max(0, 100 - min((weighted_issues / total_reports) × 25, 100))`

| Score Range | Rating | Action |
|-------------|--------|--------|
| 95–100 | Excellent | Continue monitoring |
| 85–94 | Good | Review flagged items |
| 70–84 | Needs Improvement | Targeted retraining |
| < 70 | Critical | Immediate intervention |

### Pattern Detection

Identifies recurring patterns using frequency thresholds:

- **Category cluster:** Any category with 3+ occurrences
- **Agent cluster:** Any agent with 5+ reports

## Usage

### Live Mode

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

- Clustering and semantic similarity for advanced pattern detection
- Time-series trend analysis
- Automated remediation recommendations
