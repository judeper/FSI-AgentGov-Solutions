# Flow Configuration Guide

Manual build instructions for Power Automate flows supporting the Credential Oversharing Detector. These flows should be built directly in the Power Automate designer — this solution does not include exported flow JSON artifacts.

## Connection References

| Reference | Connector | Purpose |
|-----------|-----------|---------|
| `fsi_cr_dataverse_credentialoversharing` | Dataverse | Read/write scan results and violations |
| `fsi_cr_teams_credentialoversharing` | Teams | Send alert notifications to governance channel |
| `fsi_cr_approvals_credentialoversharing` | Approvals | Exception request approval workflows |
| `fsi_cr_powerplatformadminv2_credentialoversharing` | Power Platform for Admins V2 | Query environment and agent (bot) configurations. **Do not use the legacy Power Apps for Admins connector** — Copilot Studio bot and environment control-plane actions live in V2. |

Create each connection reference in your solution before building the flows. Bind them to connections authenticated with accounts that have the permissions described in [Prerequisites](prerequisites.md).

## Environment Variables

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| `fsi_COD_ScanFrequencyHours` | Decimal | 24 | Scan schedule interval |
| `fsi_COD_DataverseUrl` | String | | Dataverse URL for persistence |
| `fsi_COD_TeamsGroupId` | String | | Teams group for alerts |
| `fsi_COD_TeamsChannelId` | String | | Teams channel for alerts |
| `fsi_COD_SecurityApproverEmail` | String | | Exception approval routing |
| `fsi_COD_ComplianceApproverEmail` | String | | Compliance approval routing |
| `fsi_COD_DefaultExceptionDays` | Decimal | 90 | Exception duration |
| `fsi_COD_MaxOAuthScopeThreshold` | Decimal | 10 | OAuth scope violation threshold |
| `fsi_COD_MaxCredentialAgeDays` | Decimal | 90 | Credential rotation threshold |
| `fsi_COD_AutoRemediateEnabled` | String | false | Auto-remediation toggle |
| `fsi_COD_ExpirationWarningDays` | Decimal | 14 | Exception expiration warning |

---

## Flow 1: COD — Scheduled Credential Scan

### Trigger

- **Recurrence:** every N hours (use `fsi_COD_ScanFrequencyHours`)

### Steps

1. **Get environment variable** — read `fsi_COD_DataverseUrl`
2. **List environments** — use Power Platform for Admins V2 connector
3. **Apply to each environment:**
   a. List agents (bots) in the environment
   b. For each agent, get connector configurations
   c. Evaluate connector OAuth scopes against zone policy
   d. If violations found, create `fsi_credentialviolations` rows (see required columns below)
4. **Create scan record** — write `fsi_credentialscans` with summary

> **Required columns when inserting Dataverse rows:**
> - `fsi_credentialscans` requires `fsi_scanid` (string), `fsi_scanrunid` (string), `fsi_scanstartedat` (datetime), `fsi_scanstatus` (option set: 100000000 Completed / 100000001 CompletedWithFindings / 100000002 Failed / 100000003 InProgress).
> - `fsi_credentialviolations` requires `fsi_violationid` (string, must be unique — append a GUID suffix), `fsi_violationstatus` (option set: 100000000 Open / 100000001 Remediated / 100000002 ExceptionApproved / 100000003 FalsePositive / 100000004 UnderReview), `fsi_severity`, `fsi_violationtype`, `fsi_zone`.
> - `fsi_credentialexceptions` requires `fsi_exceptionid` (string), `fsi_justification` (multiline string), `fsi_exceptionstatus` (option set: 100000000 Pending / 100000001 Approved / 100000002 Rejected / 100000003 Expired / 100000004 Revoked).
> See `docs/dataverse-schema.md` for the full column list and option-set values.
5. **Condition: violations found?**
   - **Yes:** Post adaptive card to Teams channel
   - **No:** Log successful scan

### Error Handling

- Configure run-after on failure for each critical action
- Use Scope with Try/Catch pattern for the main scanning loop
- Set concurrency to 1 for Dataverse writes to avoid throttling

### Performance Considerations

- Use `$top=5000` for environment queries
- Implement pagination with `@odata.nextLink` for large agent lists
- Set timeout to 30 minutes for large tenants

---

## Flow 2: COD — Exception Approval Workflow

### Trigger

- **Automated:** when a row is added to `fsi_credentialexceptions` with status Pending (`100000000`)

### Steps

1. **Get exception details** — read the triggering row
2. **Get agent details** — look up agent name and environment
3. **Start approval** — route to security approver (from `fsi_COD_SecurityApproverEmail`)
4. **Condition: approved?**
   - **Yes:** Update exception status to Approved (`100000001`), set expiration date
   - **No:** Update exception status to Rejected (`100000002`)
5. **Update related violations** — if approved, set matching violation status to ExceptionApproved (`100000002`)
6. **Notify requestor** — send email with decision

### Important Notes

- Exception duration uses `fsi_COD_DefaultExceptionDays` unless overridden by the approver
- When using decimal environment variables inside `addDays()`, wrap with `int()` to convert: `addDays(utcNow(), int(variables('DefaultExceptionDays')))`
- Concurrency must be set to 1 to prevent race conditions on violation status updates

---

## Flow 3: COD — Exception Expiration Monitor

### Trigger

- **Recurrence:** daily at 08:00 UTC

### Steps

1. **Calculate warning date** — `addDays(utcNow(), int(variables('ExpirationWarningDays')))`
2. **Query expiring exceptions** — filter `fsi_credentialexceptions` where status = Approved AND `fsi_expiresat` <= warning date
3. **For each expiring exception:**
   a. Post Teams notification with exception details
   b. Send email to exception owner
4. **Query expired exceptions** — filter where `fsi_expiresat` < `utcNow()` AND status = Approved
5. **For each expired exception:**
   a. Update status to Expired (`100000003`)
   b. Reopen related violations (set status back to Open)

---

## Deployment Validation

After building flows, perform the following validation steps:

1. **Run each flow manually** once to verify connections authenticate correctly
2. **Check Dataverse records** — confirm scan and violation rows are created with expected column values
3. **Verify Teams notifications** — confirm adaptive cards are posted to the configured channel
4. **Test exception approval** — submit an exception, approve it, and verify status transitions end-to-end
5. **Review flow run history** — check for warnings or errors in each flow's run history

> **Note:** These flows produce supporting evidence for FINRA Rule 3110 supervision, GLBA 501(b) safeguards, and SEC 17a-3/4 record-keeping reviews. They are management-reporting metrics — not standalone regulator-grade evidence. Organizations should verify their specific implementation helps meet applicable obligations.
