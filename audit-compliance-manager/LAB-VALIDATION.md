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

8. **Live blocker: canonical Dataverse environment missing `fsi` publisher and `AuditComplianceManager` solution shell, causing 404 on solution-scoped writes.**
   - Disposition: added idempotent ACV/ALCA solution-context bootstrap that reuses or creates publisher `FSIPublisher` (`customizationprefix=fsi`, `customizationoptionvalueprefix=10000`) and unmanaged solution `AuditComplianceManager` before write calls attach `MSCRM.SolutionUniqueName`.

9. **Live blocker: Dataverse CreateEntity returned `0x80040203` (`Required field 'PrimaryAttribute' is missing for RequestName='CreateEntity'`) after option-set + solution bootstrap fixes.**
   - Disposition: updated all ACM CreateEntity payloads to mark the primary name column inline in `Attributes` via `IsPrimaryName: true` (`AuditValidationHistory`, `EnvironmentRegistry`, `AuditEnvironmentCompliance`) while preserving `PrimaryNameAttribute` values. Direct live replay of corrected AuditValidationHistory payload returned HTTP 204 in the ACM solution context.

10. **Live blocker: after first column creation succeeded, next metadata-read call failed with repeated 500s until manual publish.**
    - Observed sequence: table create succeeded, first column `fsi_runid` created, then `GET EntityDefinitions(LogicalName='fsi_auditvalidationhistory')/Attributes` exhausted retry (`total=3`, `backoff_factor=1`) on repeated HTTP 500. Manual `POST /PublishAllXml` returned HTTP 204; after ~30 seconds the same metadata GET returned HTTP 200.
    - Disposition: added explicit `publish_all_customizations()` and bounded metadata-readiness polling in ACV/ALCA clients; schema scripts now publish + wait after table creation and after each column creation before the next metadata mutation.

11. **Live blocker: service-principal attribute existence probe exhausted retryable 500s on alternate-key lookup endpoint.**
    - Observed sequence: after metadata publication/readiness improvements, deployment progressed to column probes, found existing `fsi_runid`, then `GET EntityDefinitions(LogicalName='...')/Attributes(LogicalName='fsi_scope')` repeatedly returned HTTP 500 under service-principal auth. Admin comparison showed missing-attribute alternate-key probe can return 404 while the collection query `.../Attributes?$select=...&$filter=LogicalName eq 'fsi_scope'` returns stable HTTP 200 with empty `value`.
    - Disposition: replaced ACV/ALCA `get_attribute_metadata` and attribute-readiness polling with filtered Attributes collection queries (escaped OData string literal, minimal `$select`, first match/`None` contract), added pytest regression coverage for existing/missing/escaped names, and asserted that no `Attributes(LogicalName='...')` URL is generated. Full canonical deployment rerun remains pending.

12. **Live blocker: one-missing-column-per-query filtered metadata probes remained brittle immediately after publish.**
    - Observed sequence: table/Attributes readiness returned 200 and existing `fsi_runid` lookup succeeded, but the next missing-column filtered query still hit repeated transient 500s under service-principal auth. A later probe showed the same missing filtered query returning 200, indicating immediate post-publish brittleness rather than a permanent absence/read failure.
    - Disposition: added ACV/ALCA attribute inventory via full Attributes collection (`$select=LogicalName` with `@odata.nextLink` handling) and changed `create_columns` to read existing names once per entity, skip from that set, create missing columns, wait for exact created-column readiness, then update the local name set. Added pytest coverage for single inventory GET usage, pagination, skip/create sequencing, name-set update behavior, ACV/ALCA parity, and regression guard preventing missing-column filtered lookup calls before create.

13. **Live blocker: projected Attributes inventory query itself (`Attributes?$select=LogicalName`) remained transiently unstable immediately after metadata readiness 200s.**
    - Observed sequence: `wait_for_entity_metadata_readiness` succeeded on unprojected Attributes collection, then projected inventory query returned repeated transient 500s in the same service-principal session before later settling to 200. Equivalent calls with/without `Prefer: odata.include-annotations=*` both returned 200 after settling.
    - Disposition: moved ACV/ALCA attribute inventory to a bounded metadata-propagation loop owned by `list_attribute_logical_names` (timeout + poll interval constants, retries on 429/500/502/503/504 + propagation 404 + `RequestException`/`RetryError`, immediate 400/401/403 `RuntimeError`, pagination preserved, timeout reporting `last_status`/`attempts`/`last_error`) and routed inventory through a metadata-specific no-retry session to keep total wait bounded without nested adapter backoff inflation. Full canonical rerun remains pending.

 14. **Dry-run 404→TimeoutError: `create_columns` called `list_attribute_logical_names` unconditionally.**
     - Observed sequence: in `--dry-run` against a fresh environment the entity was only previewed (not created), so `EntityDefinitions(...)/Attributes` returned 404. `list_attribute_logical_names` treated 404 as a post-publish propagation transient and polled for ~180 seconds before raising `TimeoutError`.
     - Disposition: added entity-existence guard at the top of the dry-run branch in both `create_dataverse_schema.create_columns` and `create_audit_compliance_schema.create_columns`. In dry-run mode `get_entity_metadata` is called first (single GET; returns `None` on 404 immediately); if the entity already exists, `list_attribute_logical_names` is called normally so existing columns are skipped accurately; if the entity does not yet exist, an empty set is used and all custom columns are previewed. Non-dry-run call sequence is unchanged. Pytest regression tests added to `tests/test_metadata_publish_readiness.py` covering ACV and ALCA parity for both the missing-entity and existing-entity dry-run cases.

 15. **Live blocker: `fsi_scope` create-attribute POST returned repeated HTTP 500 — `PicklistAttributeMetadata` payload missing required Dataverse Web API contract fields.**
     - Observed sequence: after the full-collection attribute inventory fix (`fsi_runid` found existing), the next `POST EntityDefinitions(LogicalName='fsi_auditvalidationhistory')/Attributes` for `fsi_scope` returned repeated HTTP 500. A settled operator metadata query after the failures confirmed `fsi_scope` was absent, establishing this as a create-attribute request failure rather than a readiness-polling failure. Existing payloads included `@odata.type`, `SchemaName`, `DisplayName`/`Description` labels, `RequiredLevel`, and `GlobalOptionSet@odata.bind` but omitted `AttributeType`, `AttributeTypeName`, and `SourceTypeMask`.
     - Authoritative source: Microsoft Learn "Create a choice column using a global option set" — the current published contract requires `"AttributeType": "Picklist"`, `"AttributeTypeName": {"Value": "PicklistType"}`, and `"SourceTypeMask": 0` alongside the `GlobalOptionSet@odata.bind` Name-key binding. The Name-key binding form itself is explicitly supported per the same doc.
     - Disposition: added the three missing contract fields to all six `PicklistAttributeMetadata` column definitions across `scripts/create_dataverse_schema.py` (`fsi_Scope`, both `fsi_Zone` definitions, `fsi_Severity`, `fsi_EnvironmentType`) and `scripts/create_audit_compliance_schema.py` (`fsi_ComplianceStatus`). Added pytest regression coverage in `tests/test_picklist_attribute_contract.py` that enumerates all six current Picklist definitions and asserts their full three-field contract and expected global option-set bindings. Full canonical deployment rerun remains pending.

 16. **Live blocker: corrected `PicklistAttributeMetadata` POST returned HTTP 500 "Guid should contain 32 digits with 4 dashes" — `GlobalOptionSet@odata.bind` Name alternate-key form rejected by create-attribute endpoint.**
     - Observed sequence: one-shot service-principal POST with the fully corrected payload (including `AttributeType`, `AttributeTypeName`, `SourceTypeMask`) returned HTTP 500 with response body `{"error":{"code":"0x0","message":"Guid should contain 32 digits with 4 dashes (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)."}}`. The payload contained no GUID-shaped property other than the `GlobalOptionSet@odata.bind = "/GlobalOptionSetDefinitions(Name='fsi_acv_scope')"` value. Microsoft Learn documents the Name alternate-key form but uses the MetadataId GUID form (`/GlobalOptionSetDefinitions(<guid>)`) in its primary create-column request; the canonical environment rejected the Name form on this create-attribute POST.
     - Authoritative source: https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-optionsets#create-a-choice-column-using-a-global-option-set
     - Disposition: added `_resolve_global_optionset_binding` to both `ACVClient` and `ALCAClient`. Before any non-dry-run `create_attribute` POST, the method detects the Name alternate-key form, resolves the option set via `get_global_optionset(name)`, requires a valid UUID `MetadataId`, deep-copies the payload, and rewrites the binding to `/GlobalOptionSetDefinitions(<normalized-uuid>)`. Missing option sets and malformed bindings fail before POST. Non-choice attributes, valid MetadataId bindings, and dry-run behavior remain unchanged. Added pytest regression coverage in `tests/test_global_optionset_bind_resolution.py`. Full canonical deployment rerun remains pending.

 17. **Live blocker: `BooleanAttributeMetadata` POST for `fsi_OverrideInclude` returned HTTP 400 — `OptionSet` with two options required by Dataverse Boolean-column create contract.**
     - Observed sequence (commit 40f92ce): ACV had successfully created all AuditValidationHistory custom columns and EnvironmentRegistry columns through `fsi_lastvalidated`. The POST for the next column, `fsi_OverrideInclude` (`BooleanAttributeMetadata`), returned HTTP 400 with body `{"error":{"code":"0x80048403","message":"The option set for a Boolean attribute must have two options for true and false values."}}`. The existing payload included `@odata.type`, `SchemaName`, `DisplayName`/`Description` labels, `RequiredLevel`, and `DefaultValue` but omitted the required `OptionSet` key and its `BooleanOptionSetMetadata` contents. The same missing-`OptionSet` pattern was present in `fsi_AuditEnabled` and `fsi_DataverseAuditEnabled` in `create_audit_compliance_schema.py`. Additionally, `AttributeType` and `AttributeTypeName` were absent from all three columns, which the Dataverse Web API Boolean-column create contract also requires.
     - Authoritative source: https://learn.microsoft.com/power-apps/developer/data-platform/webapi/create-update-column-definitions-using-web-api#create-a-boolean-column
     - Disposition: added the full Boolean-column create contract to all three `BooleanAttributeMetadata` column definitions — `"AttributeType": "Boolean"`, `"AttributeTypeName": {"Value": "BooleanType"}`, and `"OptionSet"` containing `BooleanOptionSetMetadata` with `OptionSetType=Boolean`, `TrueOption Value=1 / "Yes"`, and `FalseOption Value=0 / "No"`. Added a private `_boolean_optionset()` helper in each script that returns a fresh dict per call to prevent shared mutable state across column definitions. Existing `DefaultValue: False` values are preserved on all three columns. Added pytest regression coverage in `tests/test_boolean_attribute_contract.py`. Full canonical deployment rerun remains pending.

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
- Dataverse solution-context bootstrap fix for canonical-environment 404s:
  - `scripts/solution_context_bootstrap.py`
  - `scripts/acv_client.py`
  - `scripts/alca_client.py`
  - `tests/test_solution_context_bootstrap.py` (publisher/solution no-op/create-order/header/404-contract guards)
- Dataverse CreateEntity primary-name metadata fix for live `0x80040203` blocker:
  - `scripts/create_dataverse_schema.py` (`AuditValidationHistory`, `EnvironmentRegistry`)
  - `scripts/create_audit_compliance_schema.py` (`AuditEnvironmentCompliance`)
  - `tests/test_entity_primary_attributes.py` (all entity-factory primary-name guard + live `0x80040203` error-shape regression contract)
- Dataverse metadata publication/readiness reliability fix for post-create transient metadata 500s:
  - `scripts/acv_client.py` (`publish_all_customizations`, bounded metadata readiness polling helpers)
  - `scripts/alca_client.py` (`publish_all_customizations`, bounded metadata readiness polling helpers)
  - `scripts/create_dataverse_schema.py` (publish + wait after table creation; publish + attribute readiness wait after each column)
  - `scripts/create_audit_compliance_schema.py` (publish + wait after table creation; publish + attribute readiness wait after each column)
  - `tests/test_metadata_publish_readiness.py` (transient 500 readiness sequence, publish header behavior, timeout contract, ACV/ALCA create-order gating)
- Dataverse attribute metadata existence/readiness contract fix for service-principal stability:
  - `scripts/acv_client.py` (`get_attribute_metadata` + `wait_for_attribute_metadata_readiness` now use filtered Attributes collection query with OData quote escaping)
  - `scripts/alca_client.py` (`get_attribute_metadata` + `wait_for_attribute_metadata_readiness` now use filtered Attributes collection query with OData quote escaping)
  - `tests/test_attribute_metadata_collection_lookup.py` (existing match, missing empty collection, quote escaping, and regression guard that no alternate-key Attributes URL is generated)
- Dataverse create-loop reliability fix for immediate post-publish missing-column probes:
  - `scripts/acv_client.py` (`list_attribute_logical_names` full-collection inventory helper with `@odata.nextLink`)
  - `scripts/alca_client.py` (`list_attribute_logical_names` full-collection inventory helper with `@odata.nextLink`)
  - `scripts/create_dataverse_schema.py` (one-time per-entity inventory set + skip/create/update-set flow in `create_columns`)
  - `scripts/create_audit_compliance_schema.py` (one-time inventory set + skip/create/update-set flow in `create_columns`)
  - `tests/test_attribute_metadata_collection_lookup.py` (single inventory GET and pagination coverage for ACV/ALCA)
  - `tests/test_metadata_publish_readiness.py` (skip/create ordering, no per-column filtered metadata lookup before create, and in-memory set update behavior for ACV/ALCA)
- Dataverse projected-attribute inventory reliability fix for service-principal transient propagation:
  - `scripts/acv_client.py` (`list_attribute_logical_names` now owns bounded metadata retries, permanent-error fail-fast, timeout diagnostics, and metadata-specific no-retry request path)
  - `scripts/alca_client.py` (same bounded projected inventory behavior + no-retry metadata request path)
  - `tests/test_attribute_metadata_collection_lookup.py` (transient 500→200 retry, `RetryError`/connection exception retry, permanent 403 fail-fast, timeout diagnostics, pagination retention, ACV/ALCA parity)
- Dry-run 404→TimeoutError fix for `create_columns` entity-existence guard:
  - `scripts/create_dataverse_schema.py` (entity-existence guard in `create_columns` dry-run branch for both `fsi_auditvalidationhistory` and `fsi_environmentregistry`)
  - `scripts/create_audit_compliance_schema.py` (same guard for `fsi_auditenvironmentcompliance`)
  - `tests/test_metadata_publish_readiness.py` (extended `ACVSchemaRecorder`/`ALCASchemaRecorder` with configurable `entity_data`; added four regression tests covering ACV/ALCA dry-run missing-entity and existing-entity parity)
- `BooleanAttributeMetadata` create-contract fix for live HTTP 400 0x80048403 on `fsi_OverrideInclude` column creation:
  - `scripts/create_dataverse_schema.py` (added `_boolean_optionset()` helper; added `AttributeType`, `AttributeTypeName`, `OptionSet` to `fsi_OverrideInclude`)
  - `scripts/create_audit_compliance_schema.py` (added `_boolean_optionset()` helper; added same three fields to `fsi_AuditEnabled`, `fsi_DataverseAuditEnabled`)
  - `tests/test_boolean_attribute_contract.py` (new: full-contract, distinct-OptionSet-identity, and DefaultValue regression guards for all three Boolean definitions)
- `PicklistAttributeMetadata` create-contract fix for live HTTP 500 on `fsi_scope` column creation:
  - `scripts/create_dataverse_schema.py` (added `AttributeType`, `AttributeTypeName`, `SourceTypeMask` to `fsi_Scope`, both `fsi_Zone` definitions, `fsi_Severity`, `fsi_EnvironmentType`)
  - `scripts/create_audit_compliance_schema.py` (same three fields added to `fsi_ComplianceStatus`)
  - `tests/test_picklist_attribute_contract.py` (new: full-contract and expected-binding regression guards for all six Picklist definitions)
- GlobalOptionSet Name-key → MetadataId binding resolution fix for live HTTP 500 "Guid should contain 32 digits with 4 dashes" on corrected PicklistAttributeMetadata POST:
  - `scripts/acv_client.py` (`_resolve_global_optionset_binding` helper; `create_attribute` rewrites Name binding to MetadataId GUID form before POST)
  - `scripts/alca_client.py` (identical behavior)
  - `tests/test_global_optionset_bind_resolution.py` (new: ACV/ALCA parity for Name binding resolution, POST payload rewrite, original dict immutability, missing option set, absent MetadataId, invalid MetadataId UUID, existing GUID pass-through, non-choice pass-through, dry-run no-op)
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
- [ ] ACV and ALCA writes succeed in canonical Dataverse environment when `FSIPublisher` and `AuditComplianceManager` are absent initially (bootstrap creates/reuses shell without pre-solution `MSCRM.SolutionUniqueName` headers)
- [ ] Full ACV+ALCA schema deploy rerun in canonical Dataverse environment after the `IsPrimaryName`, metadata-publication/readiness, filtered Attributes collection-lookup, one-time full-collection attribute-inventory create-loop, and projected-collection bounded-retry inventory fixes (single-table live replay returned HTTP 204; metadata GET 500→manual `PublishAllXml`→200 sequence reproduced; projected inventory 500 bursts in same service-principal session reproduced; complete deployment pass still pending)
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
