# Troubleshooting Guide

## Deployment Issues

### Schema creation fails with 403

- Verify the service principal has **System Administrator** role in the target environment
- Confirm the Dataverse URL is correct (format: `https://org.crm.dynamics.com`)
- Check that the app registration has Dynamics CRM `user_impersonation` permission
- If using a service principal, ensure it was added as an application user in the Dataverse environment

### Environment variables not visible in Power Automate

- Environment variables are created in the default solution; verify they appear in the correct environment
- Solution import may be required if using managed solutions
- Check the environment variable definition exists by querying `environmentvariabledefinitions` in Dataverse

### Connection references fail to bind

- Connection references require manual binding after creation
- Open each connection reference in Power Apps maker portal and select an active connection
- Verify the connected user has the permissions described in [Prerequisites](prerequisites.md)

---

## Authentication Issues

### "AADSTS700016: Application not found"

- Verify the client ID matches the Entra ID app registration
- Confirm the app registration is in the correct tenant
- Check that the app has not been deleted or disabled
- Ensure the `TenantId` parameter matches the home tenant of the app registration

### "Insufficient privileges" when scanning

- **Power Platform Admin** role is required for cross-environment scanning
- Environment-level System Customizer is insufficient; **System Administrator** is needed
- For Dataverse persistence, verify the app user has read/write access to COD tables (`fsi_credentialscans`, `fsi_credentialviolations`, `fsi_credentialexceptions`)

---

## Scanning Issues

### No agents found in environment

- Copilot Studio agents appear as `bots` in the Dataverse Web API
- Verify the environment has Copilot Studio enabled
- Check that the scanning identity has visibility to the bot records
- Query `bots` entity directly to verify: `GET /api/data/v9.2/bots?$top=10`

### Scan completes but reports zero connectors

- Connector scope information depends on the Microsoft safe-sharing feature (April 2026 preview)
- Verify the feature is enabled in the target tenant
- Check Power Platform admin center for feature availability status
- Note: this is a preview feature and behavior may change; review current Microsoft documentation

### False positives for cross-environment credentials

- Cross-environment detection relies on service principal ID matching
- Service principals legitimately shared across environments should be added as exceptions
- Use the exception approval workflow (Flow 2) to document approved cross-environment credentials
- Review exception records periodically to confirm they remain valid

---

## Alert Issues

### Teams notifications not received

- Verify `fsi_COD_TeamsGroupId` and `fsi_COD_TeamsChannelId` are set correctly
- Check that the Teams connection reference is bound to a user with access to the target channel
- Note: Teams incoming webhooks are retired as of March 31, 2026; use the Power Automate Teams connector
- Test the Teams connection by sending a manual message from a test flow

### Approval emails not sent

- Verify `fsi_COD_SecurityApproverEmail` is a valid, licensed mailbox
- Check the Approvals connector connection is authenticated with a licensed user
- Review the flow run history for specific error messages on the approval action
- Confirm the Approvals solution is installed in the environment

---

## Evidence Export Issues

### Hash verification fails

- Ensure the evidence JSON file has not been modified after export
- Verify the `.sha256` file is in the same directory as the evidence file
- Check for line-ending differences (CRLF vs LF) that may affect hash computation
- Regenerate the hash using: `Get-FileHash -Algorithm SHA256 evidence.json`

### Export returns empty results

- Verify the date range filter covers periods when scans were executed
- Check zone filter matches the target environments
- Confirm the Dataverse connection has read access to scan and violation tables
- Query the tables directly to verify records exist for the specified date range

---

## Performance Issues

### Scans timeout on large tenants

- Increase the flow timeout to 60 minutes for tenants with 100+ environments
- Use environment filters to scan zones in batches (e.g., production first, then development)
- Set `$top` parameter to manage page sizes for Dataverse queries
- Consider running scans during off-peak hours to reduce contention

### Dataverse throttling (429 errors)

- This release of the PowerShell scripts does **not** implement automatic retry/backoff for 429 responses — failures will surface immediately. Schedule scans accordingly and consider wrapping calls with your own retry policy in Power Automate (use a Scope with run-after configured, or the HTTP action's built-in retry policy).
- Reduce concurrency in Power Automate flows to 1 to avoid parallel write conflicts.
- Space out parallel scans across environments by adding delay actions.
- Inspect the `Retry-After` header on 429 responses to understand throttling duration.

---

## Getting Help

If issues persist after following this guide:

1. Review flow run history in Power Automate for detailed error messages
2. Check Dataverse system jobs for schema or import errors
3. Verify all prerequisites in [Prerequisites](prerequisites.md) are met
4. Review the solution [README](../README.md) for known limitations

> **Note:** This solution aids in meeting credential governance requirements under GLBA Section 501(b) safeguard standards and supports compliance with OCC 2011-12 operational risk guidance. It is recommended to validate that the implementation addresses your organization's specific regulatory obligations.
