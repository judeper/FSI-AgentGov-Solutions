# Troubleshooting

## Common Issues

### Missing Environment Variables

**Error:**

```
Error: Missing required environment variables: AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET
```

**Solution:** Set the required environment variables before running the analyzer:

```bash
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
```

### Authentication Failed

**Error:**

```
Exception: Authentication failed: AADSTS7000215: Invalid client secret provided
```

**Solution:**

1. Verify the client secret has not expired in Azure AD
2. Regenerate the secret if needed
3. Update `AZURE_CLIENT_SECRET`

### API Returns Non-200 Status

**Warning:**

```
Warning: API returned status 403: {"error":{"code":"0x80040220"...}}
```

**Solution:**

1. Verify the app registration has Dataverse API permissions
2. Check that an application user exists in the target environment
3. Confirm the application user has the Basic User security role (or a custom role granting read access to the `fsi_hallucinationreports` table)

### No Feedback Data Retrieved

**Symptom:** Report shows "Total Reports: 0"

**Possible causes:**

1. No feedback has been recorded in the specified time period (default: 30 days)
2. Feedback sources are not configured — see [Source Configuration](source-configuration.md)
3. The `fsi_hallucinationreports` table does not exist — deploy the Dataverse schema first

### Required Packages Not Installed

**Error:**

```
Error: Required packages not installed.
Run: pip install msal requests
```

**Solution:**

```bash
pip install -r scripts/requirements.txt
```

## Dry Run Testing

Use `--dry-run` to validate the analyzer with sample data without requiring Azure credentials:

```bash
python scripts/analyze_patterns.py --environment "https://example.crm.dynamics.com" --dry-run
```
