# Squad Decisions

## 2026-06-06: Issue #123 agent-intake Preflight Session

### Issue #123 agent-intake preflight (dry-run hardening) — Rusty

**Scope:** `agent-intake/scripts/setup_entra_agent_id.py`, `setup_purview_retention_label.py`, `setup_purview_retention_label.ps1`

**Decision:** Made the `--dry-run` / `-DryRun` modes on both live-tenant setup paths produce a **pure-offline** preview of the exact outbound request, and corrected Path A least-privilege permission ordering. Create request shapes are unchanged.

**Implications:**
- **Behavior change (dry-run only):** `setup_purview_retention_label.ps1 -DryRun` and `setup_purview_retention_label.py --dry-run` no longer install `ExchangeOnlineManagement` or call `Connect-IPPSSession`. They print the exact `New-ComplianceTag` commands offline. The connected idempotency check (`Get-ComplianceTag` "already present?") is no longer performed under dry-run. The real create path (no `-DryRun`) is untouched.
- **Test constraint for everyone:** `tests/test_purview_retention_label.py` asserts `graphBetaCreateSample.url` contains `"beta"`. The Graph retention-label create API is now GA at v1.0, but do **not** repoint that sample without coordinating a test update (Saul owns tests).
- **Still requires a live tenant (issue #123 remains open):** a `201` from `POST .../servicePrincipals/microsoft.graph.agentIdentity`, acceptance of the open-type `fsiReviewerAttestations`/`notes` fields (and the PATCH fallback), and actual `New-ComplianceTag` label creation cannot be confirmed from here.
- **Verified accurate, no change needed:** Path A endpoint (v1.0), `tags`, `sponsors@odata.bind`, required body, PATCH fallback path; Path B PowerShell cmdlet + params; Path B permission claim (delegated `RecordsManagement.ReadWrite.All`, application not supported).

### agent-intake #123 — dry-run offline-safety is now a tested invariant — Saul

**Context:** Rusty's safety fix made both Windows setup scripts' `--dry-run` / `-DryRun` paths fully OFFLINE (previously the PS path called `Connect-IPPSSession` — a live tenant connection — before skipping the write).

**Decision:** Locked the create request shapes AND dry-run offline safety as regression tests in `agent-intake\tests\`. Future drift in URL / api-version / body keys, or any regression that lets `--dry-run` reconnect or POST, now fails CI.

**Team-relevant notes:**
- **Pattern for other setup scripts:** dry-run safety should be tested by monkeypatching every egress symbol to raise (token providers + `requests` verbs + `subprocess.run`) and asserting `rc==0`, PLUS a positive-control test proving the sentinel is on the live path (so the offline test can't pass vacuously). Recommend applying this pattern to any solution that ships a `--dry-run` against a live tenant.
- **Static guard caveat:** the `.ps1` static check must anchor on the executable `Connect-IPPSSession -UserPrincipalName` and the top-level offline comment, because `Connect-IPPSSession` also appears in a `.PARAMETER` doc comment and the `if ($DryRun.IsPresent)` guard appears twice.
- **Coverage boundary (unchanged):** live `New-ComplianceTag` / `Connect-IPPSSession` behavior remains human-validated per #123; only the offline `-DryRun` branch is asserted from Python.

**Status:** 51 passed (was 40), ruff clean. Test coverage added.

### agent-intake live-tenant prerequisites — home + dangling-ref fix — Linus

**Issue:** #123 (agent-intake live-tenant validation, v1.0.0-preview)

**Decision:**
1. **Prerequisite/consent/role content lives in `docs/identity-records-automation.md`**, not a new `setup-prerequisites.md`. That doc already owns the Stage-3 permissions table and both manual fallbacks, so it is the single source of truth for per-path setup. New section: "Live-tenant prerequisites and admin consent" with Path A / Path B subsections, offline `--dry-run` note, and a live-acceptance caveat.
2. **The `setup-prerequisites.md` references in `pilot-validation-gap-analysis.md` were dangling** (file never existed). Repointed them to the new section rather than creating the missing file — consistent with the "don't invent a new file if a good one exists" rule, and avoids an extra mkdocs nav entry.

**Ground truth applied (verified by Rusty vs. Microsoft Learn):**
- **Path A — Entra Agent ID create:** `POST /v1.0/servicePrincipals/microsoft.graph.agentIdentity` (GA). Least-privilege app permission `AgentIdentity.Create.All`; higher `AgentIdentity.CreateAsManager` / `AgentIdentity.ReadWrite.All`. Admin role **Agent ID Administrator** / **Agent ID Developer**. Ref: https://learn.microsoft.com/graph/api/agentidentity-post?view=graph-rest-1.0
- **Path B — Purview retention label:** production = PowerShell `New-ComplianceTag` (`Connect-IPPSSession`), role group **Compliance Administrator** / **Records Management**. Graph create now **GA at v1.0** (`POST /v1.0/security/labels/retentionLabels`), DELEGATED `RecordsManagement.ReadWrite.All`, application NOT supported. Refs: https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag and https://learn.microsoft.com/graph/api/security-labelsroot-post-retentionlabel?view=graph-rest-1.0

**Open items:**
- `--check` shows pre-existing 238-artifact `site-docs/` drift across all 36 solutions (worktree never ran the generator). Run `python scripts/build-manifest.py` during consolidation to regenerate before building/committing.
- Live acceptance (real `201` / label creation + portal screenshots) still requires a tenant — this PR is preparation only.

### Issue #123 — Review Verdict (Danny, Lead)

**Date:** 2026-06-06

**Verdict:** APPROVED (re-reviewed after Yen's fix)

**Context:** Previously REJECTED for one defect: broken intra-page anchor in agent-intake/docs/identity-records-automation.md (#manual-fallback---purview-retention-labels). Yen fixed it.

**Fix verification:**
- Fragment corrected to single-hyphen #manual-fallback-purview-retention-labels.
- Heading unchanged: "## Manual fallback - Purview retention labels" (line 113).
- Zero manual-fallback--- (triple-hyphen) leftovers in agent-intake/docs/*.md.
- Scope clean: no heading or unrelated content altered by the fix.

**Gate results:**
- `build-manifest.py`: exit 0 (0 generated artifacts written)
- `build-manifest.py --check`: exit 0 (no drift; no solutions.json/README/control-mapping/manifest changes)
- `mkdocs build --strict`: exit 0 (no anchor error for identity-records-automation.md triple-hyphen; only acceptable pre-existing decisions.md INFO adr-006/adr-007)
- `pytest` (entra + purview): 51 passed
- `git status` tracked files: exactly 8 (3 scripts, 2 tests, 2 docs, 1 CHANGELOG)

**Outcome:**
- Committed 7ec764c, pushed, opened PR #309: https://github.com/judeper/FSI-AgentGov-Solutions/pull/309
- PR uses Refs #123 / Part of #123 (NOT Closes).

**Issue #123 stays OPEN:** Live-tenant sign-off still outstanding: real 201 from agentIdentity POST, reviewer-evidence 400→PATCH fallback, open-type extension acceptance, New-ComplianceTag creation + idempotent detect, portal screenshots.

## Active Decisions

No decisions recorded yet.

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
