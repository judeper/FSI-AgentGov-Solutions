# Changelog

All notable changes to the Segregation of Duties Detector.

---

## [Unreleased] — 2026-Q2 Microsoft Learn refresh

### Changed

- Added managed-identity-first authentication with WorkloadIdentity support for `Invoke-SoDScan.ps1` and `Import-ConflictRules.ps1`; ClientSecret remains only as a legacy dev fallback.
- Updated Entra role scanning to use Microsoft Graph v1.0 active role assignment schedule instances (`/roleManagement/directory/roleAssignmentScheduleInstances`) so active PIM assignments are covered.
- Added `scripts/create_sd_dataverse_schema.py` as the schema source of truth and regenerated `docs/dataverse-schema.md` from it.
- Aligned conflict-rule and violation choice values to Dataverse-style `100000000+` custom choice values used by the generated schema.
- Updated prerequisite and troubleshooting guidance to prioritize managed identity and workload identity federation over client secrets.
- Reworded default rule descriptions and documentation to avoid prevention/enforcement claims for detection-only capabilities.
- Bumped solution manifest version to `1.2.0` for script behavior changes.

---

## [1.1.0] - 2026-04-16

### Fixed (council review — Opus 4.7 + Goldeneye)

- **`Invoke-SoDScan.ps1` — Power Platform principal-type filter:** non-user principals (Groups, ServicePrincipals) returned by the BAP role-assignment API were merged into the user role map and could surface as false-positive SoD violations against group/SP GUIDs. The collector now skips anything where `principal.type -ne 'User'`. (Council Opus #1 / Goldeneye #4 — agreed)
- **`Invoke-SoDScan.ps1` — Dataverse application-user filter:** `systemusers` query now adds `applicationid eq null` so that service-principal `systemuser` rows are excluded from the user role map. (Opus #2)
- **`Invoke-SoDScan.ps1` — BAP fail-closed behavior:** when ALL Power Platform environment role queries fail (e.g., because the service principal was not registered with `New-PowerAppManagementApp`), the scan now throws and exits non-zero instead of silently producing an empty PP role data set that would be misread as "no violations." Added `-AllowPartialResults` switch for explicit override. (Opus #3 / Goldeneye #2)
- **`Invoke-SoDScan.ps1` — silent-drop principal counter:** Entra role assignments without an expanded user principal are now counted and reported via `Write-Warning`, surfacing missing `Directory.Read.All` consent or deleted-principal scenarios that previously vanished into the gap between the `if (...)` and the missing `else`. (Opus #5)
- **`Invoke-SoDScan.ps1` — pipeline-gate exit code:** the gate previously fired only on **newly created** violations, allowing a repeat scan to return exit 0 while the same SoD conflict remained open. The gate now exits non-zero whenever any active conflicts exist (pre-existing OR new), and exits 0 in `-DryRun` mode regardless of findings so dry-run evidence collection does not break CI. (Opus #13 / Goldeneye #1)
- **`Invoke-SoDScan.ps1` & `Import-ConflictRules.ps1` — secret guidance:** removed `[ValidateNotNullOrEmpty()]` from `$ClientSecret` so the manual "set FSI_CLIENT_SECRET / AZURE_CLIENT_SECRET" error message is reachable instead of being masked by the validator's generic message. (Opus #6)
- **`Import-ConflictRules.ps1` — disabled aspirational default rules:** rules referencing `DLP Policy Author` / `DLP Policy Approver` / `Environment Approver` are now `fsi_enabled = $false` by default with explanatory descriptions, since these role names are not produced by the BAP role-assignment API the collector queries. Operators must wire a custom collector or rename the rule before enabling. (Goldeneye #3)
- **`README.md` — language and control-mapping accuracy:** removed "prevents" / "enforcement" / "automated SoD enforcement" claims for capabilities that are explicitly "(planned)" in the Features table. The shipped solution is detection-only with a CI-gate exit-code; runtime pipeline blocking is roadmap. (Opus #7)
- **`docs/conflict-rules.md` — canonical regulatory citations:** "FINRA 3110" → "FINRA Rule 3110", "SOX 404" → "SOX Section 404", "OCC 2011-12" → "OCC Bulletin 2011-12". (Opus #9)
- **`docs/troubleshooting.md` — corrected OData URL:** the broken `fsi_conflictrules?$filter=...` snippet is now a complete `GET https://<env>.crm.dynamics.com/api/data/v9.2/...` URL with PowerShell escape guidance. (Opus #8)
- **`docs/prerequisites.md` — `New-PowerAppManagementApp` step:** added a new "Register Service Principal as Power Platform Admin" subsection documenting the required `New-PowerAppManagementApp` registration without which BAP role queries return 403. (Opus #3)
- **`README.md` — Known Limitations expanded:** added entries for PIM-eligible role assignments not being evaluated, and clarified `Write-AuditLog` console-only behavior including the technical reason (`Write-Host` bypasses the pipeline). (Opus #4, Opus #11)

### Notes

- Council artifacts archived under `files/sd/` (Opus + Goldeneye outputs).
- Opus #10 (lookup column naming collision between `fsi_conflictruleid` PK and the violation table's lookup of the same name) was reviewed but not modified — Dataverse permits identical logical-column names across distinct tables, and the script's `@odata.bind` / `_value` reads are consistent with the documented schema. Operators following `docs/dataverse-schema.md` exactly will produce a working schema; deferring rename to avoid breaking existing customer deployments.

---

## [1.0.0] - 2026-02-15

### Added

- Initial release of Segregation of Duties Detector
- **Dataverse Schema:**
  - `fsi_conflictrule` - Conflict rule definitions
  - `fsi_sodviolation` - Detected violations
  - `fsi_sodexception` - Approved exceptions
  - `fsi_sodauditlog` - Audit trail
- **Security Roles:**
  - SoD Viewer - Read-only compliance access
  - SoD Analyst - Exception management
  - SoD Admin - Full administrative access
- **PowerShell Scripts:**
  - `Invoke-SoDScan.ps1` - Full directory scan for violations
  - `Import-ConflictRules.ps1` - Rule set import
  - `SoDShared.ps1` - Shared helper module (Invoke-WithRetry, Get-AccessToken, Get-LoginEndpoint, Get-GraphEndpoint, Get-BapApiBaseUrl)
- **Default Rule Sets:**
  - Maker/Checker rules (5 rules)
  - Segregation rules (5 rules)
  - Privileged Access rules (4 rules)
- **Documentation:**
  - Prerequisites and licensing
  - Dataverse schema definitions
  - Conflict rules configuration
  - Troubleshooting guide

### Regulatory Alignment

- SOX Section 404 (IT General Controls)
- COSO Framework (Control Activities)
- OCC Heightened Standards (Risk Management)

---

*Segregation of Duties Detector - FSI Agent Governance Framework*
