# Troubleshooting

Common issues and solutions for the Segregation of Duties Detector.

---

## Authentication Issues

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
1. Verify rules: `Get-ConflictRules` returns active rules
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
1. Import solution: `pac solution import --path ./templates/SegregationDetector.zip`
2. Or create tables manually per schema documentation

### Cannot create violation records

**Cause:** Insufficient Dataverse permissions.

**Solution:**
1. Verify service principal has System Administrator role
2. Or grant specific table permissions (Create on fsi_sodviolation)

---

## Flow Issues

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

*Segregation of Duties Detector v1.0.0*
