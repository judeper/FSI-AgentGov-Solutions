# Auto-detect playbook — what the system fills in vs. what the maker types

> The intake form asks the maker only **10 questions** for the Express path. This document lists every other field the back-office decision-pack record carries, and **how each is populated automatically**. Source: `research/04-api-verification-spike.md` (verified endpoints) and the 137-question Claude catalog (`research/02-question-catalog-report-claude.md`).

## Endpoints used (verified during spike)

| # | Field family | Source | Endpoint | Auth | Spike status |
|---|---|---|---|---|---|
| 1 | Maker profile | Microsoft Graph v1.0 | `GET /me` | Delegated | ✅ Verified |
| 2 | Sponsor (default) | Microsoft Graph v1.0 | `GET /me/manager` | Delegated | ⚠️ Returns 404 if no manager — fall back to manual entry |
| 3 | Tenant environments | PPAC | `GET https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01` | Delegated or App | ✅ Verified (35 envs returned) |
| 4 | DLP policies | PPAC | `GET https://api.bap.microsoft.com/providers/PowerPlatform.Governance/v2/policies?api-version=2018-01-01` | Delegated or App | ✅ Verified (path corrected from earlier `/policies`) |
| 5 | Purview retention labels | Microsoft Graph beta | `GET /beta/security/labels/retentionLabels` | App (`RecordsManagement.Read.All`) | ❌ 401 in spike — customer must grant permission pre-deploy |
| 6 | Purview catalog (sensitivity tags) | Purview Catalog | `GET https://<account>.purview.azure.com/catalog/api/...` | App (Purview Data Reader) | ⚠️ Not testable in spike (no Purview account) — verify during pilot |
| 7 | Entra Agent ID minting | Microsoft Graph beta | `POST /beta/identityGovernance/agentIdentities` | App (`AgentIdentity.ReadWrite.All`) | ⏳ Verify after Entra Agent ID GA (May 1, 2026) |

## Field-by-field auto-detect map

### Maker profile (5 fields — Graph `/me`, `/me/manager`)

| Dataverse column | Graph field | Notes |
|---|---|---|
| `fsi_makerupn` | `userPrincipalName` | Read-only on form |
| `fsi_makerdisplayname` | `displayName` | Read-only |
| `fsi_makerdepartment` | `department` | Editable; null tolerated |
| `fsi_makercountry` | `usageLocation` | Drives data-residency check |
| `fsi_makerjobtitle` | `jobTitle` | Captured for sponsor card display |
| `fsi_sponsorupn` | `manager.userPrincipalName` | Fallback to manual entry on 404 |

### Environment & DLP context (4 fields — PPAC)

Run `scripts/autodetect_environments.py` on a 1-hour cache to populate environment dropdowns:

| Computed field | How |
|---|---|
| `fsi_targetenvironmentid` | Filter to `expressPathEligible: true` from `autodetect_environments.py` output |
| `fsi_targetenvironmentname` | Display name from PPAC |
| `fsi_environmentmanaged` | `protectionLevel in {Basic, Standard}` |
| `fsi_dlppolicyoutcome` | Run `scripts/autodetect_dlp_simulation.py` for the proposed connector set |

### Records (3 fields — Purview)

| Computed field | How |
|---|---|
| `fsi_retentionlabelapplied` | `autodetect_purview.py` verifies `FSI-AgentIntake-7yr` exists; surfaces remediation if missing |
| `fsi_retentionyears` | Constant `7` (locked decision #5) |
| `fsi_immutablestorage` | Constant `true` for Express decision-log entries |

### Classification (4 fields — computed by `seed_classification_rules.py`)

| Computed field | Rule |
|---|---|
| `fsi_decisionpath` | `Express` if all 6 trigger answers are "No"; else `DeferredOutOfScope`; `DefaultDeny` if cross-border + maker country ≠ data residency country |
| `fsi_tier` | `3` for Express; `2` if 1-2 triggers; `1` if 3+ triggers |
| `fsi_zone` | Mapped from `fsi_intendedaudience` via `policy-lookup-tables.yaml` audience_to_zone |
| `fsi_triggerhitcount` | Count of trigger answers that are "Yes" or "Not sure" |

### Identity (1 field — Entra Agent ID)

| Computed field | How |
|---|---|
| `fsi_entra_agentid` | `scripts/setup_entra_agent_id.py` mints on approval |

## Customer pre-deployment checklist (per spike)

Before pilot, the customer admin must:

1. **Grant Graph app permissions** to the intake automation app registration:
   - `User.Read.All` (for sponsor lookup at scale)
   - `RecordsManagement.Read.All` (for Purview retention label verification)
   - `AgentIdentity.ReadWrite.All` (for Entra Agent ID minting; available after GA May 1, 2026)
2. **Grant Power Platform admin scope** — service principal with Power Platform Administrator role for PPAC environment + DLP reads.
3. **Verify Purview catalog account** exists and the intake app has Data Reader role (or document that step 6 in the table above is deferred to manual review).
4. **Run `scripts/setup_purview_retention_label.py`** once to create the `FSI-AgentIntake-7yr` label.
5. **Confirm Entra Agent ID licensing** is enabled on the tenant (GA May 1, 2026).

## Out of scope for v0.1.0-preview

- Defender for Cloud Apps signal enrichment (planned v0.3.0)
- Microsoft Entra ID Governance access-package integration (planned v0.2.0)
- Purview DSPM-for-AI signal pull-through (planned v0.2.0)
- ServiceNow CMDB sync for sponsor / cost-centre validation (out of scope; customer-specific)
