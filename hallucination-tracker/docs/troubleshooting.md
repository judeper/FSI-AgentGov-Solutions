# Troubleshooting

## Common Issues

### No credential available

**Error:**

```
Error: Authentication failed. Configure a managed identity, workload identity federation, Azure CLI/PowerShell sign-in for workstation runs, or legacy dev-only AZURE_CLIENT_SECRET credentials.
```

**Solution:**

1. For Azure-hosted automation, assign a managed identity and grant it Dataverse access.
2. For CI, configure workload identity federation and set `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_FEDERATED_TOKEN_FILE`.
3. For admin workstations, sign in with Azure CLI or Azure PowerShell before running the analyzer.
4. For development only, set `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_CLIENT_SECRET`.

### Legacy client secret expired

**Error:**

```
Authentication failed: AADSTS7000215: Invalid client secret provided
```

**Solution:**

1. Replace the legacy secret flow with managed identity or workload identity federation where possible.
2. If a development fallback is still required, verify the secret has not expired in Microsoft Entra ID.
3. Regenerate the secret and update `AZURE_CLIENT_SECRET` only for the development environment.

### API returns non-200 status

**Warning:**

```
Warning: API returned status 403: {"error":{"code":"0x80040220"...}}
```

**Solution:**

1. Verify the managed identity, workload identity, or application user has Dataverse table permissions.
2. Check that an application user exists in the target environment when using app-only authentication.
3. Confirm the identity has the Basic User security role or a custom role granting read access to the `fsi_hallucinationreports` table.

### Enriched feedback columns unavailable

**Warning:**

```
Warning: enriched feedback columns are unavailable; falling back to legacy v1.1.0 columns.
```

**Solution:** Redeploy the v1.2.0 Dataverse schema so optional clustering columns such as `fsi_topicname`, `fsi_channelid`, and `fsi_feedbackcomment` are available.

### No feedback data retrieved

**Symptom:** Report shows `Total Reports: 0`.

**Possible causes:**

1. No feedback has been recorded in the specified time period (default: 30 days).
2. Feedback sources are not configured — see [Source Configuration](source-configuration.md).
3. Copilot Studio reactions/comments are unsupported for the selected channel (for example, Microsoft 365 Copilot channel).
4. Transcript or Product Feedback retention windows expired before ingestion.
5. The `fsi_hallucinationreports` table does not exist — deploy the Dataverse schema first.
6. Product Feedback CSV was validated with `--dry-run` but never written to Dataverse.

### Product Feedback CSV missing required columns

**Error:**

```
Error: Missing required CSV columns: App, Comments, Date Submitted, Feedback Type
```

**Solution:**

1. Re-export the file from **Microsoft 365 admin center > Health > Product Feedback**.
2. Confirm the export still includes `Comments`, `Date Submitted`, and `Feedback Type`.
3. The importer accepts the current `App` header and a legacy `Product` alias.

### Product Feedback rows skipped during import

**Symptom:** Import summary shows skipped rows such as `invalid_date`, `not_negative_feedback`, `duplicate_row`, or `already_exists`.

**Solution:**

1. Run `python scripts/import_product_feedback_csv.py --input exports/product-feedback.csv --output normalized-product-feedback.json --dry-run` to preview normalized rows before writing to Dataverse.
2. Correct malformed timestamps in the source export before rerunning.
3. Positive or non-actionable feedback is skipped intentionally so the tracker stays focused on hallucination investigations.
4. Duplicate and `already_exists` skips are expected on reruns because the importer uses deterministic `fsi_reportname` values for idempotence.

### Product Feedback rows land in single-record clusters

**Symptom:** Imported rows have `fsi_topicid` values ending with `record-<hash>` and do not group with other Product Feedback rows.

**Possible causes:**

1. The export omitted usable `Comments` and `Survey Responses`, so the importer had no shared text signal to normalize.
2. `Feature Area`, `App module`, or `Channel` differed between rows even though the app name looked similar.

**Solution:**

1. Re-export Product Feedback with comment text when tenant policy allows it.
2. Compare `fsi_topicname`, `fsi_channelid`, and `fsi_conversationid` to confirm whether the rows should share a cluster.
3. Use `fsi_topicname`, `fsi_channelid`, and `fsi_reportedat` for broader app/feature/day triage when per-record fallback clustering is expected.

### Required packages not installed

**Error:**

```
Error: Required package not installed: requests
```

**Solution:**

```bash
pip install -r scripts/requirements.txt
```

## Dry Run Testing

Use `--dry-run` to validate the analyzer with sample data without requiring credentials:

```bash
python scripts/analyze_patterns.py --environment "https://example.crm.dynamics.com" --dry-run
```
