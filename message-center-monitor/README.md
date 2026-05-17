---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P4, P5, P6]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: scale
---
# Message Center Monitor

> **Status:** Live

Monitor Microsoft 365 Message Center for platform changes that could impact AI agent deployments (Copilot Studio, Agent Builder).

## What This Solution Does

- Polls Microsoft Message Center daily for new announcements
- Stores posts in Dataverse for tracking and assessment
- Alerts your team via Teams when high-severity or action-required posts appear
- Lets you assess and document which changes impact your agents

**This is operational monitoring** - it helps your platform team stay informed about Microsoft updates. It is not a compliance or audit system.

## Lab dry-run

Want to validate this solution end-to-end in a non-prod tenant before
deploying to production? See **[`docs/lab-dry-run.md`](docs/lab-dry-run.md)**
for an idempotent, numbered automation sequence (`lab/00..06_*.ps1`) that
provisions everything, runs a 10-step smoke test (including the C1
admin-field-clobber regression check end-to-end against live wires), and
tears down cleanly.

## Who Should Use This

| Audience | Use Case |
|----------|----------|
| Agent Platform Team | Need to know about breaking changes |
| Agent Governance Committee | Transparency on platform changes |
| Power Platform Admins | Track M365 changes affecting environments |

## Prerequisites

### 1. Microsoft Entra ID App Registration

Create an app registration for Message Center access:

1. Go to [Microsoft Entra admin center](https://entra.microsoft.com) > **Applications** > **App registrations**
2. Create new registration (single tenant)
3. Under "API permissions":
   - Add permission > Microsoft Graph > **Application permissions**
   - Select `ServiceMessage.Read.All`
   - Click **Grant admin consent** (requires an administrator with permission to consent)
4. Note the Application (client) ID and Directory (tenant) ID

### 1.5. Recommended: Certificate or Federated Credential

Per the repository [authentication standard](../AGENTS.md#authentication-standard-managed-identity-first), credentials follow this priority order: managed identity → workload identity federation → certificate (uploaded to the app registration; consumed via `-AuthMode WorkloadIdentity`/MSAL token, not as its own AuthMode value) → device-code → client secret (legacy fallback). For app registrations that cannot use managed identity (Power Automate cloud flows fall into this category), prefer **certificates** or **workload identity federation** over client secrets.

In your app registration, under **Certificates & secrets**:

- **Certificate (recommended for on-prem or hybrid runners):** click **Certificates** > **Upload certificate**, then upload a PEM/CRT issued by your internal CA. Store the corresponding private key in Azure Key Vault as a certificate object.
- **Federated credential (recommended for GitHub Actions / Azure DevOps):** click **Federated credentials** > **Add credential**, choose the appropriate scenario (e.g., GitHub Actions deploying Azure resources), and bind the credential to your CI workflow. No long-lived secret needs to be stored.

```powershell
# Example: upload a certificate via Microsoft Graph PowerShell
Connect-MgGraph -Scopes "Application.ReadWrite.All"
$cert = Get-Item Cert:\CurrentUser\My\<thumbprint>
$keyCreds = @{
    Type        = "AsymmetricX509Cert"
    Usage       = "Verify"
    Key         = $cert.RawData
    DisplayName = "MessageCenterMonitor-Prod"
}
Update-MgApplication -ApplicationId <object-id> -KeyCredentials @($keyCreds)
```

### 1.6. Recommended: Apply Conditional Access policy to the service principal

Restrict the app registration's sign-ins to expected source IPs (the Power Automate Azure region IP ranges, or your CI runner egress) and require workload identity policies where supported. The companion [conditional-access-automation](../conditional-access-automation/) solution can deploy and monitor these CA policies.

### 2. Client Secret (Fallback)

Use a client secret only when certificate-based or federated credential auth is not available. Secrets land in shell history (`~/.bash_history`) and process listings (`ps`) when passed as CLI args — always pull them from Key Vault into an environment variable instead.

1. In your app registration, go to **Certificates & secrets** > **Client secrets** > **+ New client secret**
2. Set expiration (≤ 90 days for production, ≤ 365 days for non-prod — see [Secrets Management — Rotation cadence](docs/secrets-management.md#rotation-cadence))
3. Store the value in Azure Key Vault immediately (see Section 3 below)

### 3. Azure Key Vault

Store credentials securely (cert thumbprint preferred; client secret only as fallback):

1. Create a Key Vault in Azure Portal
2. Add your certificate or client secret
3. Grant your Power Automate connection (or managed identity) read access

See [Secrets Management](docs/secrets-management.md) for detailed steps.

### Authentication

The PowerShell governance scripts (`Invoke-MessageCenterSync.ps1`, `Get-MessageCenterAssessmentStatus.ps1`, `Export-MessageCenterEvidence.ps1`) accept an `-AuthMode` parameter with values `ManagedIdentity` (default), `WorkloadIdentity`, `Interactive`, `DeviceCode`, or `ClientSecret`. The Python schema/setup scripts use the shared `scripts/shared/dataverse_client.py`, which accepts an MSAL token from any source (managed identity, device-code, or client secret). Pick the strongest auth method available in your environment.

### Microsoft Learn validation notes (2026-Q2)

- The flow and sync script use the Microsoft Graph **v1.0** service communications endpoint: `GET /admin/serviceAnnouncement/messages`.
- `ServiceMessage.Read.All` is the only Graph application permission required for Message Center posts. Do not request `ServiceHealth.Read.All` unless you extend this solution to call `healthOverviews` or `issues`.
- Message Center message categories are Graph enum values (`planForChange`, `stayInformed`, `preventOrFixIssue`) mapped to Dataverse choice integers in `create_mcm_dataverse_schema.py`.
- `services[]` and `tags[]` are Microsoft-provided strings. Use configurable routing rules for service names such as Power Platform or Microsoft Copilot Studio instead of hard-coding a closed taxonomy.
- Power Platform release plans are not ingested by this solution. Review the Microsoft Learn release plan pages and Release planner separately during release-wave readiness.

### 4. Power Platform Environment

- Dataverse environment (included with most Power Platform licenses)
- Power Automate Premium license (required for Dataverse and HTTP connectors)

### 5. Dataverse Application User (required for governance scripts)

The PowerShell governance scripts call the Dataverse Web API as the same app registration used for Microsoft Graph. Without an application user with read/write access to `fsi_messagecenterlog`, the scripts will fail with `401 Unauthorized` or `403 Forbidden`.

1. Power Platform admin center → **Environments** → select your environment → **Settings** → **Users + permissions** → **Application users** → **+ New app user**
2. Add the app from Step 1 by Application (client) ID
3. Assign a security role with read/write/append/append-to access to `fsi_messagecenterlog` (a custom role scoped to the table is recommended; **System Administrator** is acceptable for non-prod)
4. Confirm the application user appears under **Application users** with status **Enabled**

### 6. DLP Policy (If Applicable)

If your environment has DLP policies:

1. Go to Power Platform Admin Center > Data policies
2. Ensure HTTP connector can access `graph.microsoft.com`
3. Ensure Azure Key Vault connector is allowed (if using Key Vault for secrets)
4. Or add both connectors to the "Business" group

## Quick Start

### Step 1: Deploy the Dataverse Schema

The packaged schema uses the `fsi_` publisher prefix and is the **canonical deployment path** — the included PowerShell governance scripts (`Invoke-MessageCenterSync.ps1`, `Get-MessageCenterAssessmentStatus.ps1`, `Export-MessageCenterEvidence.ps1`) all target `fsi_messagecenterlog`. Manual table creation under a different publisher prefix (such as a tenant default `cr123_`) is **not supported** by the shipped automation.

Run the schema script to create the table, columns, option sets, and alternate key. Pull the client secret from Key Vault into an environment variable rather than passing it as a CLI argument (CLI args are visible in shell history and process listings):

```powershell
# PowerShell — recommended pattern
$env:MCM_CLIENT_SECRET = (Get-Secret -Vault MyVault -Name MessageCenterClientSecret -AsPlainText)
python scripts\create_mcm_dataverse_schema.py `
    --tenant-id <tenant-guid> `
    --client-id <app-id> `
    --environment-url https://<org>.crm.dynamics.com `
    --output-docs
```

```bash
# bash — recommended pattern
export MCM_CLIENT_SECRET=$(az keyvault secret show --vault-name kv-mcm --name MessageCenterClientSecret --query value -o tsv)
python scripts/create_mcm_dataverse_schema.py \
    --tenant-id <tenant-guid> \
    --client-id <app-id> \
    --environment-url https://<org>.crm.dynamics.com \
    --output-docs
```

> **Note:** The schema script also accepts MSAL device-code or managed-identity tokens via the shared `scripts/shared/dataverse_client.py`. See [Secrets Management](docs/secrets-management.md) for production patterns.

The script provisions:

- Table: `fsi_messagecenterlog` (entity set `fsi_messagecenterlogs`)
- 20 columns (see `docs/dataverse-schema.md` for the auto-generated reference, including required columns, MaxLength, and option-set integer values)
- 3 global option sets: `fsi_MCM_messagecategory`, `fsi_MCM_messageseverity`, `fsi_MCM_assessmentstatus`
- Alternate key on `fsi_messagecenterid` (used by Sync upsert)

> **Naming Convention Note:** Dataverse uses two naming systems. **Display names** (in the schema script) are human-readable labels shown in Power Apps. **Logical names** are always all-lowercase with the publisher prefix (e.g., `fsi_messagecenterid` — Dataverse does NOT insert underscores between words). When configuring Power Automate, OData queries, or scripts, always use the logical name.

### Step 2: Create the Power Automate Flow

See [Flow Configuration](docs/flow-configuration.md) for complete flow creation instructions.

**Summary:**

1. Trigger: Daily recurrence (e.g., 9 AM)
2. HTTP with Microsoft Entra ID action: GET `https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages`
3. Parse JSON: Extract message fields
4. For each message: Upsert to Dataverse using `fsi_messagecenterid`
5. Condition: If severity = high/critical OR actionRequiredByDateTime is set
6. Teams notification: Post adaptive card to your channel

### Step 3: Set Up Teams Notifications

See [Teams Integration](docs/teams-integration.md) for Teams setup.

**Summary:**

1. Create a Teams channel for platform alerts
2. Use the provided adaptive card template
3. Configure the flow to post high-severity alerts

> **Note on Office 365 Connectors Deprecation:** Microsoft retired Office 365 incoming webhook connectors on **2026-03-31**. This solution uses the native **Power Automate "Post card in a chat or channel" Teams connector** with an Adaptive Card payload, which is unaffected by this retirement. If you have other integrations using custom incoming webhooks, plan migration to Power Automate Workflows connector or Adaptive Card actions.

### Step 4: Verify It Works

1. Run the flow manually
2. Check Dataverse for imported posts
3. Verify Teams notifications appear for high-severity items

## Workflow

```text
Microsoft Message Center
        │
        ▼
Daily Polling (9 AM)
        │
        ▼
Dataverse MessageCenterLog Table
        │
        ▼
Alert if severity=high/critical OR action-required
        │
        ▼
Agent Platform Team Review
        │
        ▼
Assess: "Does this affect our agents?"
        │
        ▼
Log assessment + take action if needed
```

## Data Model

### MessageCenterLog (Single Table)

This solution uses a single table design for simplicity:

```text
MessageCenterLog
├── messagecenterid (PK, MC######)
├── title
├── category (Feature/Admin/Security)
├── severity (High/Normal/Critical)
├── services (comma-separated)
├── startDateTime
├── actionRequiredByDateTime
├── endDateTime
├── body (HTML)
├── assessmentStatus (enum)
├── assessment (notes)
├── impactsAgents (boolean)
├── assessedBy (text)
├── assessedDate
├── actionsTaken (notes)
├── tags (comma-separated)
├── hasAttachments (boolean)
└── notifiedOn (duplicate prevention)
```

### Permissions

Use standard Dataverse permissions:

| Role | Access |
|------|--------|
| Platform Ops Team | Full CRUD |
| Agent Governance Committee | Read + Edit assessments |
| Viewers | Read-only |

No custom security roles required.

## Polling Interval

Microsoft Message Center has no webhook/push notification. The solution polls Graph API.

| Interval | Use Case |
|----------|----------|
| Daily (recommended) | Standard operations - most posts aren't urgent |
| Every 6 hours | Higher urgency environments |
| Hourly | Not recommended - excessive API calls |

## Documentation

| Document | Description |
|----------|-------------|
| [Flow Configuration](docs/flow-configuration.md) | Step-by-step Power Automate flow build guide |
| [Secrets Management](docs/secrets-management.md) | Key Vault integration for secure credential storage |
| [Setup Checklist](docs/setup-checklist.md) | End-to-end deployment checklist (~12 steps) |
| [Teams Integration](docs/teams-integration.md) | Teams channel notification setup |

## Customization

This solution is designed to be modified:

- **Add columns:** Track additional metadata
- **Change notifications:** Route to Slack, email, or ServiceNow
- **Add views:** Filter by service, category, or date
- **Integrate:** Connect to your change management system
- **Plain-text body:** The `body` field stores HTML from Microsoft. For search or cleaner display, add a `bodyPlainText` column and use Power Automate's `stripHtml()` expression or a custom function to convert content

> **Security note:** The `fsi_body` field stores raw HTML from Microsoft Graph. Do not render it directly in custom HTML web resources or canvas-app HTML controls without sanitization. The shipped Teams adaptive card intentionally excludes the body field. If you add a `bodyPlainText` column, prefer that for display surfaces.

> **Environment Promotion Tip:** When moving this solution between environments (dev → test → prod), use [Dataverse environment variables](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/environmentvariables) instead of hardcoding values in the flow. Store the polling schedule (recurrence interval), severity thresholds, and Teams channel ID as environment variables so they can be updated per-environment without editing the flow definition. This aligns with ALM best practices and simplifies managed solution deployments.

## Troubleshooting

### Flow fails with 401/403

- Verify app registration has `ServiceMessage.Read.All` permission
- Confirm admin consent was granted
- Check the configured credential has not expired (certificate, federated credential, or legacy client secret)

### No posts appearing

- Run flow manually and check run history
- Verify HTTP action is returning data
- Check Dataverse upsert action for errors

### Teams notifications not posting

- Verify Teams channel connector is configured
- Check flow condition logic for high-severity posts
- Review Teams action in flow run history

## Version

2.5.1 - May 2026

See [CHANGELOG.md](./CHANGELOG.md) for version history.

<!-- BEGIN:IMPLEMENTED_CONTROLS -->
<!-- Generated by scripts/build-manifest.py from manifest.yaml.controls — do not edit by hand. -->

## Implemented Controls

Canonical control coverage for this solution is declared in `manifest.yaml.controls` and exported in `solutions.json` as `solutions.<solution-id>.controls`. Downstream consumers should sync from that machine-readable list rather than parsing hand-maintained README prose.

| Control | Description |
|---------|-------------|
| [2.3](https://judeper.github.io/FSI-AgentGov-Solutions/reference/control-mapping/#control-2-3) | Change Management and Release Planning |

<!-- END:IMPLEMENTED_CONTROLS -->

## Playbook Reference

- [Platform Change Governance Playbook](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/platform-change-governance/index.md)

## License

MIT - See LICENSE in repository root
