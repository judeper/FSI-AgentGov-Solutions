# Lab Validation Report — Agent 365 Lifecycle Governance

**Solution version:** v1.1.5 · **Validation date:** 2026-06-04 · **Validation type:** Static (no live tenant)

## Purpose and controls

Automated lifecycle governance for AI agents using Microsoft Agent 365, Microsoft Entra
Agent ID, and Microsoft Entra ID Governance: sponsor/owner assignment, zone-based access
reviews, inactivity detection, approval-gated deactivation, and deletion holds.

Primary control 2.3 (Change Management); secondary 1.2, 1.11, 2.1, 2.8, 2.12, 3.1.

## What was checked

- Parse/compile validity of all scripts (Python + PowerShell).
- Correctness of every external API endpoint, version, permission/scope against
  authoritative Microsoft Learn documentation.
- Dataverse column logical-name correctness (verified against
  `scripts/create_alg_dataverse_schema.py`, the source of truth).
- Option-set integer values referenced in flow docs, Power BI DAX, and canvas guide vs the
  schema script.
- Schema doc currency (`--output-docs` regenerate + diff → no drift).
- Environment-variable count and key shape (script vs docs vs sample template).
- FSI regulatory language rules and version-footer consistency.

## Authoritative sources cited

- Get agentInstance (beta): https://learn.microsoft.com/graph/api/agentinstance-get?view=graph-rest-beta
- List agentInstances (beta): https://learn.microsoft.com/graph/api/agentregistry-list-agentinstances?view=graph-rest-beta
- Update agentInstance (beta): https://learn.microsoft.com/graph/api/agentinstance-update?view=graph-rest-beta
- agentInstance resource type (`ownerIds` String collection; May 2026 convergence notice):
  https://learn.microsoft.com/graph/api/resources/agentinstance?view=graph-rest-beta
- Agent Registry convergence with Microsoft Agent 365:
  https://learn.microsoft.com/entra/agent-id/agent-registry-convergence
- Agent 365 agent permissions / blueprint registration:
  https://learn.microsoft.com/microsoft-agent-365/developer/registration#agent-permissions
- `AgentInstance.*` are beta permissions (Dec 2025 note):
  https://learn.microsoft.com/microsoft-agent-365/developer/custom-client-app-registration#4-configure-api-permissions
- Microsoft Graph permissions reference (`AgentInstance.Read.All` / `AgentInstance.ReadWrite.All`):
  https://learn.microsoft.com/graph/permissions-reference#all-permissions
- accessReviewScheduleDefinition resource (`scope`, `reviewers`, `settings`):
  https://learn.microsoft.com/graph/api/resources/accessreviewscheduledefinition?view=graph-rest-1.0
- Configure access review scope (accessReviewQueryScope vs principalResourceMembershipsScope/`principalScopes`/`resourceScopes`):
  https://learn.microsoft.com/graph/accessreviews-scope-concept

## Verification outcomes (already correct)

- **Agent Registry endpoint** `GET/PATCH /beta/agentRegistry/agentInstances` is the current
  documented surface; `ownerIds` is the correct updatable owner property (the prior
  `sponsor@odata.bind` pattern is stale, as the docs already note). Scripts filter ownerless
  instances client-side on `ownerIds` — appropriate given undocumented server-side filter support.
- **Permissions** `AgentInstance.Read.All` (read/list) and `AgentInstance.ReadWrite.All`
  (create/update/delete) match Microsoft Learn exactly. Beta-permission caveat is documented.
- **Convergence caveat** (Agent Registry APIs replaced by Agent 365-powered APIs starting
  May 2026) matches the live Microsoft Learn notice; feature-flag gating is sound.
- **Dataverse**: schema doc regenerated with no diff; all column references use correct
  logical names (`fsi_iscurrent`, `fsi_approvalstatus`, `fsi_deletionholduntil`, etc.);
  option-set integers consistent across flow docs, DAX, and canvas guide.
- **Auth**: managed-identity-first; Az.Accounts 5.x SecureString token handling correct.
- **Language rules**: no prohibited phrases; regulatory claims appropriately hedged.
- **Versions**: all footers consistent at v1.1.5.

## Gaps found and fixes applied

| # | File | Issue | Fix |
|---|------|-------|-----|
| 1 | `docs/flow-configuration.md` | Managed-solution component table said "All 14 variables"; script deploys 16 and the reference table lists 16. | Corrected to 16. |
| 2 | `docs/troubleshooting.md` | Access-review 400 row claimed `principalScopes`/`resourceScopes` are "required", contradicting Flow 2 (which uses `accessReviewQueryScope`). Per Microsoft Graph those properties belong only to `principalResourceMembershipsScope`. | Rewrote to reference the `scope.query`/`queryType` shape Flow 2 sends. |
| 3 | `DELIVERY-CHECKLIST.md` (Phase 3) | Same `principalScopes`/`resourceScopes` inconsistency in the API-validation task. | Aligned to the `accessReviewQueryScope` shape. |

No script logic changes were required — Python and PowerShell parse cleanly and the API
calls match current documentation.

## Runtime-only caveats (cannot be validated statically)

- Agent Registry beta APIs may change before GA / May 2026 convergence; validate
  `agentInstances` list/PATCH and `ownerIds` behavior in a non-production tenant (Phase 3).
- Server-side OData `$filter` support for `ownerIds` is unconfirmed; client-side filtering
  is the documented fallback.
- PPAC Bots API (`api-version=2022-03-01-preview`) is an internal BAP endpoint not covered by
  Microsoft Learn; `flow-configuration.md` and `troubleshooting.md` show slightly different
  paths (the latter includes `/scopes/admin/`). Confirm the working path and that
  `lastModifiedTime`/`publishedOn` are returned (Phase 3) — left as-is pending tenant validation.
- `AuditLog.Read.All` may be restricted in some FSI tenants; Flow 3 degrades to PPAC data.
- Dataverse alternate-key activation latency and LTR/no-delete role configuration are
  tenant-side operational steps.

## Lab-readiness assessment

**Ready for lab deployment**, gated by the existing `IsAgent365LifecycleEnabled` feature flag
and the Phase 3 non-production API validation already mandated in `DELIVERY-CHECKLIST.md`.
Static validation found no blocking defects; the three doc-drift corrections remove
contradictions that would have misled an operator building Flow 2 or sizing environment
variables. No version bump applied (doc-only corrections; avoids manifest/catalog churn).
