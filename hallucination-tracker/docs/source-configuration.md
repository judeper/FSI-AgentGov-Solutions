# Source Configuration

## Overview

The Hallucination Feedback Tracker collects feedback from multiple sources. Each source writes normalized records to the `fsi_hallucinationreports` Dataverse table; the solution does not ship exported Power Automate flow artifacts.

## Required Fields on Insert

Every `fsi_hallucinationreports` record **must** have the following columns populated. Inserts that omit any required field fail with `0x80040220 RequiredFieldValueMissing`.

| Logical Name | Type | Notes |
|--------------|------|-------|
| `fsi_reportname` | Text | Unique business identifier — use an expression like `concat('HT-', utcNow(), '-', guid())` in Power Automate. |
| `fsi_category` | Choice (integer) | Map source signal to one of the `fsi_category` values below. |
| `fsi_severity` | Choice (integer) | Map source signal to one of the `fsi_severity` values below. |
| `fsi_source` | Choice (integer) | Identifies the source pipeline. |

### Optional enrichment fields

Populate these fields when available to support topic, agent, channel, and time-window clustering:

| Logical Name | Type | Recommended source |
|--------------|------|--------------------|
| `fsi_conversationid` | Text | Copilot Studio `SessionID`, Graph `sessionId`, or support-ticket conversation ID. |
| `fsi_userquery` | Memo | Initial user message or prompt. |
| `fsi_agentresponse` | Memo | Response that received negative feedback or failed evaluation. |
| `fsi_topicname` | Text | Copilot Studio `TopicName`, Microsoft 365 Copilot app area, or support taxonomy. |
| `fsi_topicid` | Text | Copilot Studio `TopicId`, Graph app/session identifier, or internal topic ID. |
| `fsi_channelid` | Text | Copilot Studio `ChannelId` such as `msteams` or `webchat`. |
| `fsi_feedbackcomment` | Memo | User comment, supervisor note, evaluator rationale, or complaint text. |
| `fsi_groundednessdetected` | Boolean | `true` when an automated groundedness check flags ungrounded content. |
| `fsi_reportedat` | DateTime | Source-system timestamp in UTC where available. |

### `fsi_category` value reference

| Category | `fsi_category` Value |
|----------|----------------------|
| Factual error | 100000000 |
| Fabricated data | 100000001 |
| Citation missing | 100000002 |
| Outdated information | 100000003 |
| Confidence overstatement | 100000004 |

### `fsi_severity` value reference

| Severity | `fsi_severity` Value |
|----------|----------------------|
| Low | 100000000 |
| Medium | 100000001 |
| High | 100000002 |
| Critical | 100000003 |

### `fsi_source` value reference

| Source | `fsi_source` Value |
|--------|--------------------|
| User | 100000000 |
| Supervisor | 100000001 |
| Automated | 100000002 |
| Customer | 100000003 |
| Microsoft 365 Copilot | 100000004 |

## Feedback Sources

### 1. User reactions and comments (Copilot Studio custom agents)

Copilot Studio custom agents can collect thumbs-up/thumbs-down reactions and comments for individual agent responses. User reactions are on by default for supported channels and can be turned off under **Settings > User feedback** by disabling **Collect user reactions to agent messages**. To view comments in Analytics, reviewers need the **Bot Transcript Viewer** security role.

Current Microsoft Learn caveats:

- Reactions/comments are shown on the Copilot Studio **Analytics > Effectiveness > Reactions** experience.
- Feedback data is stored with conversation transcript data in Dataverse; session transcript CSV downloads also include `CSAT` and `Comments` fields.
- Comments are available in the Analytics page for 28 days, while session transcript downloads are available for the past 29 days. Dataverse transcript retention defaults to 30 days unless changed by administrators.
- Agents published to the Microsoft 365 Copilot channel don't support Copilot Studio reactions.
- Session transcript CSV response text is truncated to 512 characters per agent response; use Dataverse transcript data when complete text is required.

Set `fsi_source` to `100000000` (User) for Copilot Studio custom-agent records.

| Signal | Weight | `fsi_category` | `fsi_severity` | Enrichment guidance |
|--------|--------|----------------|----------------|---------------------|
| Thumbs down + factual comment | High | 100000000 (Factual error) | 100000002 | Map `Comments` to `fsi_feedbackcomment`; map `TopicName`, `TopicId`, `ChannelId`, and `SessionID`. |
| Thumbs down + missing citation comment | High | 100000002 (Citation missing) | 100000002 | Include the response excerpt in `fsi_agentresponse` when permitted by data-handling policy. |
| Low CSAT with negative comment | Medium | 100000004 (Confidence overstatement) | 100000001 | Store the CSAT value in the description or remediation notes until a dedicated CSAT field is added. |

**Setup options:**

1. **Dataverse transcript ingestion:** Build a scheduled Power Automate flow or script that reads the Copilot Studio conversation transcript table and related feedback/comment records, filters for negative reactions or low CSAT, and creates `fsi_hallucinationreports` rows with the mappings above.
2. **CSV transcript ingestion:** Download sessions from the Copilot Studio Analytics page for the review period, then import rows with negative comments or low CSAT into `fsi_hallucinationreports`.
3. **Custom topic logging:** For agent designs that need immediate feedback capture, add an explicit feedback collection topic or adaptive card and write directly to `fsi_hallucinationreports`. Treat this as a custom extension, not the built-in Copilot Studio reaction pipeline.

**Application Insights note:** Copilot Studio telemetry documentation still shows `customEvents` and `customDimensions` for Application Insights examples. In workspace-based Application Insights, equivalent data can surface through `AppEvents` with custom properties in `Properties`. If you add KQL ingestion later, normalize both table shapes before mapping feedback records.

### 2. Microsoft 365 Copilot product feedback

Microsoft 365 Copilot feedback is governed by Microsoft 365 feedback policies. Users can provide thumbs-up/thumbs-down feedback and comments from Microsoft 365 Copilot experiences when tenant policy allows it. Administrators can view and export organizational feedback from **Microsoft 365 admin center > Health > Product Feedback**.

Set `fsi_source` to `100000004` (Microsoft 365 Copilot) for records imported from Product Feedback export.

| Signal | Weight | `fsi_category` | `fsi_severity` | Enrichment guidance |
|--------|--------|----------------|----------------|---------------------|
| Copilot thumbs down with incorrect/incomplete comment | High | 100000000 (Factual error) | 100000002 | Map Product, Date Submitted, Feedback Type, and Comments into `fsi_description` / `fsi_feedbackcomment`. |
| Feedback indicates missing sources or unsupported claim | High | 100000002 (Citation missing) | 100000002 | Include only prompt/response content permitted by tenant feedback policy and privacy review. |
| Repeated app-specific feedback | Medium | 100000004 (Confidence overstatement) | 100000001 | Use `fsi_topicname` for app or workload area (for example, Teams, Outlook, Word). |

**Graph note:** Microsoft Graph Copilot interaction history can retrieve Microsoft 365 Copilot prompts/responses for licensed users with `AiEnterpriseInteraction.Read.All`, but it is not a user-feedback API and does not retrieve interactions in agents created by Copilot Studio. Use it only as governed context for an approved investigation, not as the primary feedback source.

### 3. Supervisor rejections (FINRA Supervision Workflow)

Configure the FINRA Supervision Workflow to forward rejections.

Set `fsi_source` to `100000001` (Supervisor) for all records from this source.

| Signal | Weight | `fsi_category` | `fsi_severity` |
|--------|--------|----------------|----------------|
| Factual rejection | Critical | 100000000 (Factual error) | 100000003 |
| Citation missing | High | 100000002 (Citation missing) | 100000002 |
| Outdated guidance | Medium | 100000003 (Outdated information) | 100000001 |

**Setup:**

1. In the FINRA Supervision Workflow solution, locate the rejection flow.
2. Add a Dataverse **Create a new row** action for `fsi_hallucinationreports`.
3. Populate `fsi_reportname` (for example, `concat('HT-SUP-', utcNow(), '-', guid())`), `fsi_category`, `fsi_severity`, and `fsi_source`.
4. Map supervisor notes to `fsi_feedbackcomment` and retained prompt/response excerpts to `fsi_userquery` / `fsi_agentresponse` when permitted.

### 4. Automated checks

Programmatic verification can be implemented via scheduled jobs, approved custom connectors, or Microsoft Foundry evaluation pipelines.

Set `fsi_source` to `100000002` (Automated) for all records from this source.

| Check | `fsi_category` | `fsi_severity` | Notes |
|-------|----------------|----------------|-------|
| Azure AI Content Safety groundedness detection (preview) | 100000000 (Factual error) | 100000002 | Use groundedness output such as `ungroundedDetected` to set `fsi_groundednessdetected`. Preview APIs can change; validate before production use. |
| Microsoft Foundry offline groundedness evaluation | 100000002 (Citation missing) | 100000001 | Use evaluation datasets for regression testing and store evaluator rationale in `fsi_feedbackcomment`. |
| Date validation | 100000003 (Outdated information) | 100000001 | Scope to dates that matter for the agent's business domain. |
| Number sanity | 100000000 (Factual error) | 100000002 | Use domain thresholds approved by model-risk owners. |

**Setup:**

1. Create a scheduled workflow, Azure Function, or CI evaluation job using managed identity or workload identity federation.
2. Query recent agent responses from approved transcript, telemetry, or evaluation datasets.
3. Apply validation logic, Azure AI Content Safety groundedness detection, or Microsoft Foundry evaluators.
4. Write flagged items to `fsi_hallucinationreports` with `fsi_reportname` (for example, `concat('HT-AUTO-', utcNow(), '-', guid())`), `fsi_category`, `fsi_severity`, `fsi_source`, and enrichment fields.

### 5. Customer complaints

Feedback can be derived from customer complaints routed through support channels.

Set `fsi_source` to `100000003` (Customer) for all records from this source.

| Signal | Weight | `fsi_category` | `fsi_severity` |
|--------|--------|----------------|----------------|
| Accuracy complaint | Critical | 100000000 (Factual error) | 100000003 |
| Misleading or unsupported response | High | 100000002 (Citation missing) | 100000002 |
| Outdated information | Medium | 100000003 (Outdated information) | 100000001 |

**Setup:**

1. Configure the customer complaint intake channel (for example, support ticketing system).
2. Create a Power Automate flow or approved integration triggered by complaint classification events.
3. Filter for complaints related to AI agent accuracy, unsupported claims, stale information, or misinformation.
4. Populate `fsi_reportname` (for example, `concat('HT-CUST-', utcNow(), '-', guid())`), `fsi_category`, `fsi_severity`, `fsi_source`, and enrichment fields.

## Environment Configuration

Use managed identity first for Azure-hosted automation and workload identity federation for CI. Interactive authentication is appropriate for one-off admin workstation runs. Client-secret authentication is a legacy development fallback only and should not be the recommended production path.

```powershell
# Preferred for Azure-hosted automation: assign a managed identity with Dataverse access.
python scripts/analyze_patterns.py --environment "https://your-org.crm.dynamics.com"

# Legacy dev-only fallback — replace with managed identity or workload identity in production.
$env:AZURE_TENANT_ID     = "<tenant-guid>"
$env:AZURE_CLIENT_ID     = "<app-registration-client-id>"
$env:AZURE_CLIENT_SECRET = "<client-secret>"
python scripts/analyze_patterns.py --environment "https://your-org.crm.dynamics.com"
```
