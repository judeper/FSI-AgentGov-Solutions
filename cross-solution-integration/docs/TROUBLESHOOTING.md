# Troubleshooting — Cross-Solution Integration

## Common Issues

### Sync-SolutionAssessments fails with "Table not found"

**Symptom:** Error referencing `fsi_auditvalidationhistories` or similar table name.

**Cause:** The Tier 2 solution has not been deployed to the target Dataverse environment.

**Resolution:**
1. Verify all prerequisite solutions are deployed (see PREREQUISITES.md)
2. Confirm the Dataverse URL points to the correct environment
3. Check the entity set name matches — Dataverse pluralizes table names

### No CD assessments created after sync

**Symptom:** Script runs successfully but no records appear in `fsi_controlassessment`.

**Cause:** The `fsi_controlmaster` table may not have entries for the target control IDs.

**Resolution:**
1. Verify CD sample data is loaded: `fsi_controlmasters` should have 62 records
2. Check the `fsi_controlid` values match (e.g., "1.7", not "01.07")
3. Run with `-Verbose` to see per-solution processing details

### Evidence hash mismatch

**Symptom:** `Test-UnifiedEvidenceIntegrity.ps1` reports hash verification failure.

**Cause:** Evidence file was modified after export, or the SHA-256 companion file is corrupted.

**Resolution:**
1. Re-export evidence from the source solution
2. Verify the `.sha256` companion file contains the correct hash
3. Check for line-ending differences (export and verification must use same encoding)

### ELM provisioning hook not triggering

**Symptom:** New environments provisioned via ELM do not appear in ACV `fsi_environmentregistry`.

**Cause:** The `ELM-SolutionInitializer` flow may not be activated, or the trigger condition does not match.

**Resolution:**
1. Verify the flow is activated in Power Automate
2. Check the trigger condition: `fsi_action eq 13` (ProvisioningCompleted)
3. Verify the flow's Dataverse connection reference has read access to `fsi_provisioninglog`
4. Check flow run history for errors

### Authentication errors with service principal

**Symptom:** `Connect-Dataverse` fails with 401 or insufficient privileges.

**Resolution:**
1. Verify the app registration has `user_impersonation` Dataverse API permission
2. Confirm the service principal is added as an application user in Dataverse
3. Check security role assignments on the application user
4. For cross-environment scenarios, the SP must be registered in each environment

### Zone value appears as 100000001 instead of 1

**Symptom:** Assessment records show incorrect zone values.

**Cause:** Some solutions (ACV, SSC) use Dataverse-native option set values (100000001+) while others use logical values (1/2/3).

**Resolution:** This is handled automatically by `Get-CanonicalZoneValue` in `IntegrationConfig.psm1`. If you see raw values, ensure you're importing the integration module before running sync operations.

## Diagnostic Commands

```powershell
# Verify all solution tables are accessible
Import-Module .\IntegrationConfig.psm1
$config = Get-SolutionTableConfig
foreach ($solution in $config.Keys) {
    Write-Host "Checking $solution..." -NoNewline
    # Verify table exists and is queryable
}

# Check latest validation timestamp per solution
.\Sync-SolutionAssessments.ps1 -DataverseUrl $url -TenantId $tid -Interactive -DryRun -Verbose

# Verify CD control master entries
# Query: fsi_controlmasters?$filter=fsi_controlid eq '1.7'
```

## Support

For issues not covered here, check:
1. Individual solution TROUBLESHOOTING.md files
2. Power Automate flow run history
3. Dataverse audit log for permission issues

---

*Troubleshooting Guide v1.0.0 — February 2026*
