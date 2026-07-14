# Lab Validation Report — Audit Compliance Manager (ACM)

> **Solution:** `audit-compliance-manager` · **Version under review:** v1.0.6 (static-review draft)
>
> **Date:** 2026-07-14
>
> **Validation state:** **Static review complete; private live validation pending**

## Scope and guardrails used for this pass

- One solution at a time (`audit-compliance-manager` only)
- Revalidated against current first-party Microsoft sources
- No overclaiming: this report does **not** claim live-tenant success
- Hybrid evidence model retained:
  - `runtime` channel for script/API behavior
  - `playwright` channel for portal/UI checks only
- Keep one draft PR open until private harness evidence is attached

## Source revalidation table (first-party, checked 2026-07-14)

| Topic | Source URL | Last-updated metadata seen during review | Static finding |
|---|---|---|---|
| EXO module runtime compatibility | https://www.powershellgallery.com/packages/ExchangeOnlineManagement/3.10.0 | PSGallery release notes for v3.10.0 | `ExchangeOnlineManagement` 3.10.0 raises PS7 minimum to 7.6; ACM pinned to 3.0.0-3.9.2 for current Azure Automation PS 7.4 path |
| Azure Automation PS runtime support | https://learn.microsoft.com/en-us/azure/automation/automation-runbook-types | `updated_at: 2026-06-29` | PS 7.4 is supported; 7.2 is no longer supported by parent PowerShell lifecycle |
| Unified audit cmdlet guidance | https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/search-unifiedauditlog?view=exchange-ps | `updated_at: 2026-06-01` | `Search-UnifiedAuditLog` remains supported; Microsoft recommends Management Activity API for scripted bulk download |
| Mailbox cmdlet deprecation wording | https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/search-mailboxauditlog?view=exchange-ps | `updated_at: 2026-02-27` | Deprecation is announced, but no fixed retirement date is stated |
| Purview retention constraints | https://learn.microsoft.com/en-us/purview/audit-solutions-overview | `updated_at: 2026-07-08` | Non-user records are fixed at one-year retention; custom retention policies don't apply |
| Purview retention policy mechanics | https://learn.microsoft.com/en-us/purview/audit-log-retention-policies | `updated_at: 2026-06-24` | Custom policy behavior and licensing constraints remain as documented |
| Graph audit query API | https://learn.microsoft.com/en-us/graph/api/resources/security-auditlogquery | Current Learn endpoint | Graph `auditLogQuery` remains a valid modern alternative; monitor-only for ACM in this PR |
| Dataverse auditing behavior | https://learn.microsoft.com/en-us/power-apps/developer/data-platform/configure-entity-auditing | Current Learn endpoint | Org/table audit checks used by ACM remain aligned with docs |

## Findings and dispositions

1. **Manifest hard dependency on AOF was incorrect for ACM runtime.**
   - Disposition: removed hard dependency from `manifest.yaml`; documented AOF as optional integration in README.

2. **Runbook wrappers still used `MSAL.PS` despite migration claim in prior history.**
   - Disposition: migrated both `Start-TenantValidationRunbook.ps1` and `Start-EnvironmentValidationRunbook.ps1` drift-token acquisition to `Connect-PowerPlatform` (`Az.Accounts` path), removed `Get-MsalToken` usage.

3. **EXO module drift risk with Azure Automation runtime.**
   - Disposition: bounded ExchangeOnlineManagement to `3.0.0-3.9.2` in script `#Requires` and documentation where runbook module requirements are defined.

4. **Mailbox cmdlet retirement date language was overstated.**
   - Disposition: removed fixed-date wording; retained deprecation-without-date wording.

5. **Programmatic bulk-download guidance changed (cmdlet vs API).**
   - Disposition: documented Management Activity API recommendation and Graph `auditLogQuery` as monitor/evaluate items; no migration in this PR.

6. **Non-user record retention limit conflicts with Zone 3 target in some classes.**
   - Disposition: documented limit and caveat in README/LAB narrative; no speculative code migration in this PR.

7. **Live blocker: Dataverse global option-set POST payloads missing polymorphic metadata discriminators.**
   - Disposition: added root `@odata.type = Microsoft.Dynamics.CRM.OptionSetMetadata` and per-option `@odata.type = Microsoft.Dynamics.CRM.OptionMetadata` to ACM ACV/ALCA option-set definitions, plus pytest guards validating discriminator presence and client pass-through semantics.

## Static changes implemented in this pass

- `manifest.yaml`
  - Version `1.0.5` → `1.0.6`
  - Removed hard dependency on `agent-observability-foundation`
- `README.md`
  - Updated runtime/module guidance (Az.Accounts; EXO compatibility band)
  - Added optional AOF integration note (non-prerequisite)
  - Added non-user-record fixed-retention caveat
  - Canonicalized Exchange PowerShell links with `?view=exchange-ps`
- `scripts/Start-TenantValidationRunbook.ps1`
  - Removed `MSAL.PS` dependency and `Get-MsalToken`
  - Added `Connect-PowerPlatform` helper usage for Dataverse drift token
  - Added explicit parameter guard for cert-based drift detection
- `scripts/Start-EnvironmentValidationRunbook.ps1`
  - Removed `MSAL.PS` dependency and `Get-MsalToken`
  - Added `Connect-PowerPlatform` helper usage for Dataverse drift token
- Option-set metadata payload fix for live Dataverse compatibility:
  - `scripts/create_dataverse_schema.py` (ACV global option sets)
  - `scripts/create_audit_compliance_schema.py` (ALCA global option set)
  - `tests/test_optionset_discriminators.py` (root/option discriminator guards + ACV/ALCA client POST pass-through guard)
- ExchangeOnlineManagement compatibility bounds added in scripts:
  - `Enable-AuditLogging.ps1`
  - `Invoke-TenantAuditValidation.ps1`
  - `private/Connect-AuditServices.ps1`
  - `Test-AuditLoggingCompliance.ps1`
  - `Test-MailboxAudit.ps1`
  - `Test-PurviewRetention.ps1`
  - `Test-UnifiedAuditLog.ps1`
  - `Start-TenantValidationRunbook.ps1`
- Documentation sync updates:
  - `docs/deployment-guide.md`
  - `docs/flow-setup.md`
  - `docs/evidence-export-guide.md`
  - `docs/testing-scenarios.md`

## Runtime vs Playwright check split (explicit)

### Runtime channel (public/static verification completed here)

- Script parse/compile checks
- Pester + pytest static/contract checks
- Manifest build/check and generated-artifact consistency
- Language/commercial/docs-autonomy policy checks
- MkDocs strict build

### Playwright channel (private live harness only; pending)

- Portal reachability and auth UX checks only
- No claim that Playwright validates backend runtime controls

## Private harness lab prerequisites (not hardcoded with private values)

1. Private lab repository with persistent runner registration
2. Tenant-specific secure config present outside this public repo
3. Runtime plan declaring separate `runtime` and `playwright` steps
4. Evidence root outside Git; redaction and SHA-256 manifest generation enabled

## Pending private live checks (required before readiness claim)

- [ ] Tenant runbook execution in private lab (certificate path)
- [ ] Environment runbook execution in private lab (certificate and legacy-secret fallback path)
- [ ] Drift detection path verifies Dataverse token acquisition via Az.Accounts helper
- [ ] ACV and ALCA global option-set POST calls succeed in canonical Dataverse environment with discriminator-enriched payloads
- [ ] `Search-UnifiedAuditLog` and canary retrieval checks in target tenant
- [ ] Purview retention validation with actual policy set and licensing context
- [ ] Portal smoke artifacts (Playwright channel) attached separately from runtime evidence
- [ ] Sanitized evidence summary + hash manifest attached to draft PR

## Live evidence placeholder

No private live evidence is attached in this public static pass.

When private harness execution completes, append:

- private run ID
- runtime evidence summary path/hash
- playwright evidence summary path/hash
- disposition of pending checks above

## Status statement

**Static review/fix phase complete.**  
**Live validation remains pending** until private harness runtime + portal evidence is attached to the draft PR.
