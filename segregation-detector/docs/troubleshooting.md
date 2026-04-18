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

**Cause:** Service principal lacks required permissions.

**Solution:**
1. Verify API permissions in app registration
2. Ensure admin consent is granted
3. Check permissions:
   - `RoleManagement.Read.Directory`
   - `User.Read.All`
   - `Directory.Read.All`

### "Invalid client secret"

**Cause:** Client secret expired or incorrect.

**Solution:**
1. Check secret expiration date
2. Regenerate secret if expired
3. Update stored secret value

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
1. Verify service principal has System Administrator role
2. Or grant specific table permissions (Create on fsi_sodviolation)

---

## Flow Issues (Planned)

> **Note:** Power Automate flows are not yet implemented. The current solution uses PowerShell scripts for detection. This section documents planned flow-based capabilities.

### Detection flow not triggering

**Possible Causes:**
1. Flow disabled
2. Connection expired
3. Schedule misconfigured

**Solutions:**
1. Check flow status in Power Automate
2. Re-authenticate connections
3. Verify trigger schedule

### Alerts not sending

**Cause:** Notification connection issues.

**Solutions:**
1. Verify email/Teams connections valid
2. Check recipient addresses
3. Review flow run history for errors

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
| "AADSTS7000215" | Invalid client secret | Regenerate secret |
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

*Segregation of Duties Detector v1.1.0*
