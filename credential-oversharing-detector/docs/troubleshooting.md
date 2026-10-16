# Troubleshooting Guide

## Deployment Issues

### Schema creation fails with 403

- Verify the service principal has **System Administrator** role in the target environment
- Confirm the Dataverse URL is correct (format: `https://org.crm.dynamics.com`)
- For interactive/delegated authentication, check the delegated Dynamics CRM permission and consent; for app-only authentication, check the Dataverse application user and its security roles instead
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

- Do not interpret zero connectors or missing scope metadata as a passing credential review
- The extractor assumes nested `bot.configuration.connectorConfigurations` / `oauthScopes` fields. Microsoft documents the [bot table](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/bot), but the sources reviewed do not document this nested contract
- Compare sanitized extractor output with a known connector-bearing agent and verify connection-reference read permissions. Record missing fields and data coverage with the evidence; do not store credential values in troubleshooting logs
- [Roadmap ID 566873](https://www.microsoft.com/en-us/microsoft-365/roadmap?searchterms=566873) remains In development (preview target July 2026, general availability target September 2026; checked 2026-10-16). It describes safe sharing, not an API to enable for scope extraction. The [automatic security scan](https://learn.microsoft.com/en-us/microsoft-copilot-studio/security-scan) warns about maker credentials but does not establish scope telemetry

### Power Apps module fails under PowerShell 7

- COD scripts require PowerShell 7, while Microsoft's Power Apps module guidance specifies Windows PowerShell 5.x and warns of incompatibility with 6+. This is a host-support gap, not proof of an identity or permission failure
- Record the exact host/module versions and validate in an isolated lab. Do not simply switch the COD scripts to 5.1; see the [prerequisites](prerequisites.md)

### V2 connection reference shows the older admin connector

- Inspect the existing reference: V2 uses `shared_powerplatformadminv2`, not `shared_powerplatformforadmins`
- Existing references are skipped by setup, so rerunning it alone does not migrate them. Follow the manual correction and dependent-action review in the [flow guide](flow-configuration.md#connection-references)

### Graph helper fails or reports unexpected CA coverage

- The existing CA/auth helpers call Graph independently of the core scanner. Establish the Graph session with `Application.Read.All` and, for CA reads, `Policy.Read.All`; delegated reads also require the documented user role
- For delegated federated-credential reads, confirm application ownership or a supported application-administration/custom role; Security Reader alone is insufficient. Alternatively, use an app-only Graph session with application `Application.Read.All`. See the operation-specific [prerequisites](prerequisites.md#microsoft-entra-id) and [Microsoft permission requirements](https://learn.microsoft.com/en-us/graph/api/federatedidentitycredential-list)
- Do not treat `NoCredentials` / "No action required" as a successful authentication review until federated-credential enumeration is confirmed. The current auth helper suppresses lookup errors, so missing authorization can produce that result
- Workload-identity CA excludes managed identities and multitenant apps. Do not recommend adding such identities to CA policies
- Treat the helper as inventory, not effective coverage: it does not fully evaluate enabled state, exclusions, filters, or `ServicePrincipalsInMyTenant`. Verify those against [Microsoft's CA guidance](https://learn.microsoft.com/en-us/entra/identity/conditional-access/workload-identity) and service-principal sign-in logs

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
- Note: Microsoft 365 (O365) connectors / Teams incoming webhooks stop functioning after May 22, 2026 (deprecation rollout May 18-22, 2026); use the Power Automate Teams connector
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
4. Review the solution [README](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/credential-oversharing-detector/README.md) for known limitations

> **Note:** This solution aids in meeting credential governance requirements under GLBA Section 501(b) safeguard standards and supports compliance with OCC 2011-12 operational risk guidance. It is recommended to validate that the implementation addresses your organization's specific regulatory obligations.
