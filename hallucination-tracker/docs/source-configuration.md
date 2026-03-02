# Source Configuration

## Overview

The Hallucination Feedback Tracker collects feedback from multiple sources. Each source must be configured to write records to the `fsi_hallucinationreports` Dataverse table.

## Feedback Sources

### 1. User Feedback (Copilot Studio)

Configure the Copilot Studio feedback mechanism to capture thumbs-down reactions.

| Signal | Weight | `fsi_severity` Value |
|--------|--------|----------------------|
| Thumbs down | High | 100000002 |
| Regenerate request | Medium | 100000001 |
| Abandonment | Low | 100000000 |

**Setup:**

1. In Copilot Studio, enable the feedback topic
2. Create a Power Automate flow triggered by feedback events
3. Map the feedback payload to `fsi_hallucinationreports` columns

### 2. Supervisor Rejections (FINRA Supervision Workflow)

Configure the FINRA Supervision Workflow to forward rejections.

| Signal | Weight | `fsi_severity` Value |
|--------|--------|----------------------|
| Factual rejection | Critical | 100000003 |
| Citation missing | High | 100000002 |
| Needs revision | Medium | 100000001 |

**Setup:**

1. In the FINRA Supervision Workflow solution, locate the rejection flow
2. Add a Dataverse "Create a new row" action for `fsi_hallucinationreports`
3. Map rejection fields to the appropriate category and severity values

### 3. Automated Checks

Programmatic verification can be implemented via Power Automate flows or custom connectors.

| Check | Capability |
|-------|------------|
| Citation verification | Verify cited URLs return 200 |
| Date validation | Check dates are in plausible range |
| Number sanity | Flag outlier numeric values |

**Setup:**

1. Create a scheduled Power Automate flow
2. Query recent agent responses
3. Apply validation logic
4. Write flagged items to `fsi_hallucinationreports`

### 4. Customer Complaints

Feedback derived from customer complaints routed through support channels.

| Signal | Weight | `fsi_severity` Value |
|--------|--------|----------------------|
| Accuracy complaint | Critical | 100000003 |
| Misleading response | High | 100000002 |
| General dissatisfaction | Medium | 100000001 |

**Setup:**

1. Configure the customer complaint intake channel (e.g., support ticketing system)
2. Create a Power Automate flow triggered by complaint classification events
3. Filter for complaints related to AI agent accuracy or misinformation
4. Map complaint fields to `fsi_hallucinationreports` columns with appropriate category and severity values

## Environment Configuration

Set the Dataverse environment URL when running the pattern analyzer:

```bash
python scripts/analyze_patterns.py --environment "https://your-org.crm.dynamics.com"
```
