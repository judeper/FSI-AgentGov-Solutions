# Troubleshooting — Cross-Solution Integration

## Common Issues

### Sync-SolutionAssessments fails with "Table not found"

**Symptom:** Error referencing `fsi_auditvalidationhistories` or similar table name.

**Cause:** The Tier 2 solution has not been deployed to the target Dataverse environment.

**Resolution:**
1. Verify all prerequisite solutions are deployed (see PREREQUISITES.md)
2. Confirm the Dataverse URL points to the correct environment
3. Check the entity set name against the Dataverse Web API service document; AAM and CMM use explicit singular entity sets

### No CD assessments created after sync

**Symptom:** Script runs successfully but no records appear in `fsi_controlassessment`.

**Cause:** The `fsi_controlmaster` table may not have entries for the target control IDs.

**Resolution:**
1. Verify CD sample data is loaded: `fsi_controlmasters` should have 78 records
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
2. Check the trigger condition: `fsi_action eq 100000013` (ProvisioningCompleted)
3. Verify the flow's Dataverse connection reference has read access to `fsi_provisioninglog`
4. Check flow run history for errors

### Authentication errors with managed identity or legacy service principal

**Symptom:** `Connect-DataverseApi` fails with 401 or insufficient privileges.

**Resolution:**
1. Verify the app registration has `user_impersonation` Dataverse API permission
2. Confirm the service principal is added as an application user in Dataverse
3. Check security role assignments on the application user
4. For cross-environment scenarios, the managed identity or legacy service principal must be registered as an application user in each environment

### Zone value appears as 100000001 instead of 1

**Symptom:** Assessment records show incorrect zone values.

**Cause:** Tier 2 source tables can use Dataverse-native ACV option-set values (100000001+) while Compliance Dashboard assessments use logical values (1/2/3).

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

## Known Limitations

### ListRecords pagination not handled

All Dataverse `ListRecords` operations in both `CD-SolutionFeedCollector` and `ELM-SolutionInitializer` lack `@odata.nextLink` pagination handling. This is currently mitigated by `$top: 1` on every query (only the latest record is needed). However, if `$top` is removed or increased in future edits, results will be silently truncated at the Dataverse default page size (5000). When modifying any `ListRecords` operation, verify that `$top` is appropriate or add pagination logic.

### No $select on Dataverse queries (partially resolved)

`$select` parameters have been added to all `ListRecords` and `GetItem` operations in both `CD-SolutionFeedCollector` (15 operations: 6 solution queries + 9 upsert-existence checks) and `ELM-SolutionInitializer` (2 operations: 1 GetItem + 1 ListRecords). Each `$select` includes only the columns referenced by downstream expressions. The actual minimum Dataverse call count per `CD-SolutionFeedCollector` run is 24+ (ACV=3, SSC=5, AAM=3, CMM=3, FUS=3, CAA=7+), so the `$select` optimization reduces payload size significantly across all calls.

### ELM flow null validation on required fields (resolved)

The `ELM-SolutionInitializer` flow now validates that `fsi_environmentid` and `fsi_environmentname` are non-null and non-empty after `Extract_Provisioning_Data`. If either field is empty, the flow logs a validation failure to `fsi_provisioninglogs` and terminates with a `NullRequiredField` error, preventing corrupt ACV registry entries.

### Non-atomic upsert pattern

All assessment upserts (ACV, SSC, AAM, CMM, FUS, CAA) use a non-atomic `ListRecords` → if-exists → `Create`/`Update` sequence. The `SingleInstance` trigger option on `CD-SolutionFeedCollector` mitigates same-flow overlap, but manual re-runs or clock drift could produce duplicate same-day assessments. A Dataverse alternate-key upsert would be the proper fix but requires schema changes (adding an alternate key on `fsi_controlmasterid` + `fsi_assessmentdate`) outside this solution.

### No staleness detection for Tier 2 solution data

If a Tier 2 solution stops producing validation records (e.g., broken flow, expired credentials, decommissioned environment), `CD-SolutionFeedCollector` silently skips it — the `{Solution}_Has_Records` condition evaluates to false and the empty else branch executes. The Compliance Dashboard continues showing the last known assessment with no indication of data age.

**Recommended mitigation:** Compare each solution's latest validation timestamp (`fsi_timestamp` for ACV/SSC, `fsi_validationtime` for AAM/CMM/FUS/CAA) against a configurable staleness threshold (e.g., 48 hours). If the latest record is older than the threshold, write a `status=2` (Partial) assessment with notes indicating stale data, and send a Teams alert. This can be implemented as an additional check within each Sync scope, after the `Query_{Solution}_Latest` action, or as a separate scheduled flow.

**Monitoring workaround (no code changes):** Create a Dataverse view or Power BI report that shows the maximum validation timestamp per solution table. Set a Power Automate alert if any solution's latest timestamp exceeds 48 hours.

### No centralized error aggregation

Each flow logs errors to separate mechanisms: `CD-SolutionFeedCollector` writes per-solution errors to `fsi_integrationerrorlogs`, while `ELM-SolutionInitializer` writes failures to `fsi_provisioninglogs`. There is no single view across all integration errors.

**Current state:** `CD-SolutionFeedCollector` already logs per-solution errors to `fsi_integrationerrorlogs` with `fsi_solution`, `fsi_runid`, `fsi_errormessage`, and `fsi_timestamp` fields. This provides a queryable error history for the feed collector.

**Recommended mitigation:** Create a unified Dataverse view or Power BI dashboard that joins `fsi_integrationerrorlogs` (feed collector errors) and `fsi_provisioninglogs` (ELM initializer errors where `fsi_success = false`) to surface all integration failures in a single pane. Alternatively, add a consolidated error summary to the existing Teams notification in `Send_Summary_Teams`.

---

*Troubleshooting Guide v2.0.2 — May 2026*
