# Source Configuration

## Overview

The Hallucination Feedback Tracker collects feedback from multiple sources. Each source must be configured to write records to the `fsi_hallucinationreports` Dataverse table.

## Required Fields on Insert

Every `fsi_hallucinationreports` record **must** have the following columns populated. Inserts that omit any required field will fail with `0x80040220 RequiredFieldValueMissing`.

| Logical Name | Type | Notes |
|--------------|------|-------|
| `fsi_reportname` | Text | Unique business identifier — use an expression like `concat('HT-', utcNow(), '-', guid())` in Power Automate. |
| `fsi_category` | Choice (integer) | Map source signal to one of the `fsi_category` values below. |
| `fsi_severity` | Choice (integer) | Map source signal to one of the `fsi_severity` values below. |
| `fsi_source` | Choice (integer) | Identifies the source pipeline (User / Supervisor / Automated / Customer). |

### `fsi_category` value reference

| Category | `fsi_category` Value |
|----------|----------------------|
| Factual error | 100000000 |
| Outdated information | 100000001 |
| Misleading citation | 100000002 |
| Hallucinated source | 100000003 |
| Other | 100000004 |

### `fsi_severity` value reference

| Severity | `fsi_severity` Value |
|----------|----------------------|
| Low | 100000000 |
| Medium | 100000001 |
| High | 100000002 |
| Critical | 100000003 |

## Feedback Sources

### 1. User Feedback (Copilot Studio)

Configure the Copilot Studio feedback mechanism to capture thumbs-down reactions.

Set `fsi_source` to `100000000` (User) for all records from this source.

| Signal | Weight | `fsi_category` | `fsi_severity` |
|--------|--------|----------------|----------------|
| Thumbs down | High | 100000000 (Factual error) | 100000002 |
| Regenerate request | Medium | 100000004 (Other) | 100000001 |
| Abandonment | Low | 100000004 (Other) | 100000000 |

**Setup:**

1. In Copilot Studio, enable the feedback topic.
2. Create a Power Automate flow triggered by feedback events.
3. In the "Add a new row" Dataverse action, populate `fsi_reportname` (e.g., `concat('HT-USER-', utcNow(), '-', guid())`), `fsi_category`, `fsi_severity`, and `fsi_source` per the tables above.
4. Set additional optional fields (`fsi_agentid`, `fsi_description`) as available.

### 2. Supervisor Rejections (FINRA Supervision Workflow)

Configure the FINRA Supervision Workflow to forward rejections.

Set `fsi_source` to `100000001` (Supervisor) for all records from this source.

| Signal | Weight | `fsi_category` | `fsi_severity` |
|--------|--------|----------------|----------------|
| Factual rejection | Critical | 100000000 (Factual error) | 100000003 |
| Citation missing | High | 100000002 (Misleading citation) | 100000002 |
| Needs revision | Medium | 100000004 (Other) | 100000001 |

**Setup:**

1. In the FINRA Supervision Workflow solution, locate the rejection flow.
2. Add a Dataverse "Create a new row" action for `fsi_hallucinationreports`.
3. Populate `fsi_reportname` (e.g., `concat('HT-SUP-', utcNow(), '-', guid())`), `fsi_category`, `fsi_severity`, and `fsi_source`.

### 3. Automated Checks

Programmatic verification can be implemented via Power Automate flows or custom connectors.

Set `fsi_source` to `100000002` (Automated) for all records from this source.

| Check | `fsi_category` | `fsi_severity` |
|-------|----------------|----------------|
| Citation verification | 100000002 (Misleading citation) | 100000002 |
| Date validation | 100000001 (Outdated information) | 100000001 |
| Number sanity | 100000000 (Factual error) | 100000002 |

**Setup:**

1. Create a scheduled Power Automate flow.
2. Query recent agent responses.
3. Apply validation logic.
4. Write flagged items to `fsi_hallucinationreports` with `fsi_reportname` (e.g., `concat('HT-AUTO-', utcNow(), '-', guid())`), `fsi_category`, `fsi_severity`, and `fsi_source`.

### 4. Customer Complaints

Feedback derived from customer complaints routed through support channels.

Set `fsi_source` to `100000003` (Customer) for all records from this source.

| Signal | Weight | `fsi_category` | `fsi_severity` |
|--------|--------|----------------|----------------|
| Accuracy complaint | Critical | 100000000 (Factual error) | 100000003 |
| Misleading response | High | 100000002 (Misleading citation) | 100000002 |
| General dissatisfaction | Medium | 100000004 (Other) | 100000001 |

**Setup:**

1. Configure the customer complaint intake channel (e.g., support ticketing system).
2. Create a Power Automate flow triggered by complaint classification events.
3. Filter for complaints related to AI agent accuracy or misinformation.
4. Populate `fsi_reportname` (e.g., `concat('HT-CUST-', utcNow(), '-', guid())`), `fsi_category`, `fsi_severity`, and `fsi_source`.

## Environment Configuration

Set the required Microsoft Entra ID app credentials as environment variables, then run the pattern analyzer:

```powershell
$env:AZURE_TENANT_ID     = "<tenant-guid>"
$env:AZURE_CLIENT_ID     = "<app-registration-client-id>"
$env:AZURE_CLIENT_SECRET = "<client-secret>"
python scripts/analyze_patterns.py --environment "https://your-org.crm.dynamics.com"
```
