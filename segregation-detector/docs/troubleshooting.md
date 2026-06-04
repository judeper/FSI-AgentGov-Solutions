# Troubleshooting

Common issues and solutions for the Segregation of Duties Detector.

---

## Authentication Issues

### Token expires during long-running scans

**Cause:** Access tokens expire after ~60 minutes. In large tenants with thousands of users, the scan may exceed this duration.

**Symptoms:** `401 Unauthorized` errors partway through a scan that initially authenticates successfully.

**Solutions:**
1. Run scans during off-peak hours to reduce API latency
2. Filter to specific user groups to reduce scan duration
3. Implement an external token refresh wrapper that re-invokes the script in segments

### "Access Denied" when querying Graph API

**Cause:** The managed identity, workload identity, or legacy service principal lacks required permissions.

**Solution:**
1. Verify API permissions in the managed identity or app registration
2. Ensure admin consent is granted
3. Check permissions:
   - `RoleAssignmentSchedule.Read.Directory`
   - `RoleManagement.Read.Directory`
   - `User.Read.All`
   - `Directory.Read.All`

### Managed identity token request fails

**Cause:** The script is running with `-AuthMode ManagedIdentity` on a host without an enabled managed identity, or the user-assigned identity client ID is incorrect.

**Solution:**
1. Verify the Azure resource has a system-assigned or user-assigned managed identity enabled.
2. For user-assigned identities, pass `-ManagedIdentityClientId` or set `MANAGED_IDENTITY_CLIENT_ID`.
3. Verify Graph and Dataverse permissions are granted to the identity and admin consent is complete.

### Workload identity federation token exchange fails

**Cause:** The federated credential issuer, subject, audience, or token file path does not match the runner configuration.

**Solution:**
1. Verify `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_FEDERATED_TOKEN_FILE`.
2. Confirm the federated identity credential values are case-sensitive matches for the pipeline issuer and subject.
3. Re-run with `-AuthMode WorkloadIdentity -Verbose`.

### "Invalid client secret" (legacy dev-only mode)

**Cause:** `-AuthMode ClientSecret` was explicitly selected and the local development secret expired or is incorrect.

**Solution:**
1. Prefer `-AuthMode ManagedIdentity` or `-AuthMode WorkloadIdentity` for production.
2. For local development only, rotate the secret and update `FSI_CLIENT_SECRET`.

---

## Scan Issues

### No violations detected (unexpected)

**Possible Causes:**
1. Rules not enabled
2. Rules not imported
3. Scope mismatch

**Solutions:**
1. Verify rules exist in Dataverse. Use the full OData URL (escape `$` in PowerShell with a backtick):
   ```
   GET https://<env>.crm.dynamics.com/api/data/v9.2/fsi_conflictrules?$filter=fsi_enabled eq true
   ```
   Or run `.\Invoke-SoDScan.ps1 -DryRun -Verbose` and check the "Found N active rules" output.
2. Import default rules: `.\Import-ConflictRules.ps1 -RuleSet Default`
3. Check role context matches actual assignments

### Too many false positives

**Cause:** Rules too broad or context mismatch.

**Solutions:**
1. Add environment scope to rules
2. Refine role name matching
3. Add exceptions for justified cases

### Scan timeout

**Cause:** Large directory with many users/roles.

**Solutions:**
1. Add pagination handling
2. Filter to specific user groups
3. Run during off-peak hours

---

## Dataverse Issues

### "Entity fsi_conflictrule not found"

**Cause:** Dataverse solution not deployed.

**Solution:**
1. Create tables manually per [schema documentation](dataverse-schema.md)

### Cannot create violation records

**Cause:** Insufficient Dataverse permissions.

**Solution:**
1. Verify the managed identity, workload identity, or legacy service principal has the System Administrator role
2. Or grant specific table permissions (Create on fsi_sodviolation)

---

## Performance Issues

### Slow role enumeration

**Cause:** Large Entra ID directory.

**Solutions:**
1. Use `$select` to limit returned fields
2. Add filters to reduce result set
3. Implement incremental sync

### High API throttling

**Cause:** Too many Graph API requests.

**Solutions:**
1. Add delays between requests
2. Use batch requests where possible
3. Implement retry with backoff

---

## Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| "AADSTS700016" | App not found in tenant | Verify client ID |
| "AADSTS500011" | BAP token resource/audience not found | The Power Platform BAP admin REST API token audience is `https://service.powerapps.com/` (Power Apps Service, App ID `475226c6-020e-4fb2-8a90-7a972cbfc1d4`), not the request host. The scanner derives this automatically; if it still fails (e.g., sovereign cloud), pass `-BapResource` or set `FSI_BAP_RESOURCE`. |
| "AADSTS7000215" | Invalid client secret in legacy dev-only mode | Prefer ManagedIdentity or WorkloadIdentity; rotate local dev secret if ClientSecret mode is unavoidable |
| "403 Forbidden" | Insufficient permissions | Grant required permissions |
| "Resource not found" | Wrong environment URL | Verify Dataverse URL |
| "Duplicate key" | Rule already exists | Use update instead of create |

---

## Support

For additional help:
1. Review script verbose output: `-Verbose`
2. Check Dataverse audit logs
3. Open issue in [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues)

---

*Segregation of Duties Detector v1.2.1*
