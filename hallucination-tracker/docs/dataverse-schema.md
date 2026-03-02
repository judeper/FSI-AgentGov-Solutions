# Dataverse Schema

## Tables

### fsi_hallucinationreports

Primary table for storing hallucination feedback reports.

| Column | Type | Description |
|--------|------|-------------|
| `fsi_hallucinationreportid` | Uniqueidentifier | Primary key |
| `fsi_category` | Option Set | Hallucination category |
| `fsi_severity` | Option Set | Severity level |
| `fsi_agentid` | Text (100) | Agent identifier |
| `fsi_description` | Multiline Text | Description of the hallucination |
| `fsi_source` | Option Set | Feedback source type |
| `createdon` | DateTime | Record creation timestamp |
| `modifiedon` | DateTime | Last modification timestamp |

### Category Option Set (`fsi_category`)

| Value | Label |
|-------|-------|
| 100000000 | Factual Error |
| 100000001 | Fabricated Data |
| 100000002 | Citation Missing |
| 100000003 | Outdated Info |
| 100000004 | Confidence Overstatement |

### Severity Option Set (`fsi_severity`)

| Value | Label | Weight |
|-------|-------|--------|
| 100000000 | Low | 1 |
| 100000001 | Medium | 2 |
| 100000002 | High | 3 |
| 100000003 | Critical | 4 |

## Deployment Status

> **Note:** This schema is currently documented as a specification. Deployable Dataverse
> entity XML (solution.xml, customizations.xml) will be added in a future release.
> See the [README](../README.md) for current solution status.
