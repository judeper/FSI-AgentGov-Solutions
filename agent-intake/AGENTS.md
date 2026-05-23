# agent-intake — AI Agent / Maintainer Notes

> **Read me first** when resuming work on `agent-intake/` in a new session or on a fresh machine. This is **not** customer-facing — for that, start at [`README.md`](README.md). This file is dev/AI-agent context only.

| | |
|---|---|
| **Solution** | agent-intake |
| **Version** | v1.0.0-preview |
| **Status** | Ready for customer pilot · PR #142 merged |
| **Owner** | judeper / FSI Agent Governance |

One-sentence intent: a pre-build maker-intake layer that captures FSI AI-agent requests, classifies risk into Express / Standard / Full paths, routes for sponsor or reviewer approval with FINRA 3110 attestation, records an immutable decision pack with 7-year retention, and hands the approved request off to `agent-registry-automation` via a Microsoft Entra Agent ID.

---

## 🛑 Before you do ANYTHING on a new machine

**Copy your `lab/config.local.json` into `agent-intake/lab/` before running any script.**

This file is **gitignored on purpose** (contains tenant ID, env GUID, billing policy ID, Purview operator UPN). It is not on GitHub and never will be. You stored a copy of it outside this repo when you closed the previous machine's session — retrieve it now from your secure source (password manager / OneDrive note / key vault) and drop it at:

```
agent-intake\lab\config.local.json
```

If you skip this step, `Invoke-Deploy.ps1` and every other lab script will fail with a missing-config error. Full bootstrap checklist below in [Resuming on a different dev machine](#resuming-on-a-different-dev-machine).

---

## Active Development Status (2026-05-17)

> ⚠️ When work resumes, refresh this section with a new date and new content. Keep the structure; the date-stamp tells the next session whether this is current.

**What just shipped (v1.0.0-preview):**

- 17 automated workstreams — schema (9 tables · 11 option sets · 1 alt-key), solution containers, reviewer-app provisioning, 12 documented Power Automate flows, identity stage (6 security roles + reviewer-app SP), Purview retention-label hydration, policy hydration, seed-test-data CLI (5 scenarios), smoke-test CLI (8 checks), teardown CLI, deploy orchestrator, lab wrapper, 42 pytest cases, manifest schema 1.5.0 compliance, full docs set.
- Live-lab e2e validated on the user's Autonomous Demo Sandbox in tenant `M365CPI57786004`: teardown (~646s) → fresh redeploy (~2200s · 8 stages all green) → seed 5 scenarios → post-seed smoke (5 PASS · 2 MANUAL · 1 WARN — all expected).
- Six bug-fixes from live validation consolidated in commit `53a09c4`.

**Open PR:** [#142 — feat(agent-intake): v1.0.0-preview customer-deliverable](https://github.com/judeper/FSI-AgentGov-Solutions/pull/142) was merged. The branch and worktree have moved on; the council-review remediation work now lands via `fix/agent-intake-council-review` on top of the merged `main`.

**In-flight (this session, pending push):**

- Per-solution AGENTS.md pattern landed (this file)
- Stale version-ref cleanup in `README.md`, `docs/decisions.md`, `docs/onboarding-checklist.md`, `docs/auto-detect-playbook.md`
- P1 / P2 / P5 polish items (see [Pending Work](#pending-work) below)
- CI alignment: `agent-intake-ci.yml` language-rules now mirrors the root workflow's `AGENTS.md` exclude

> ✅ Update: all of the above landed in PR #142 across 7 commits (`1730ad8`..`81c80b1`). The "Pending work" checklist below is now fully checked. Refresh this entire status block when next session starts.

**Next action when work resumes:**

1. On the new machine, follow [Resuming on a different dev machine](#resuming-on-a-different-dev-machine).
2. `cd agent-intake/lab; .\Invoke-Deploy.ps1 -DryRun` as a sanity-check before any live test.
3. Decision on the table: merge PR #142 to `main` or keep iterating.

---

## Resuming on a different dev machine

The session-state folder (`~\.copilot\session-state\`) lives on the **previous** machine only. All persistent context lives in this repo — read it on the new machine.

```powershell
# 1. Clone or update
git clone https://github.com/judeper/FSI-AgentGov-Solutions
cd FSI-AgentGov-Solutions
git checkout feature/agent-intake
git pull origin feature/agent-intake

# 2. Fix the gh-account credential helper FIRST (see Auth quirks below)
gh auth setup-git --hostname github.com
gh auth switch --user judeper

# 3. Verify the toolchain
pac --version          # need v2.6+
az --version           # any recent
python --version       # 3.11+
pwsh --version         # 7+

# 4. Recreate your lab config (NOT committed)
cd agent-intake\lab
Copy-Item config.example.json config.local.json
# Edit config.local.json with: environment.url / environment.environmentId / tenant.tenantId /
# billing.policyId / purview.operatorUpn — from your own secure source (OneDrive note,
# password manager, etc.). Real values for the existing Autonomous Demo Sandbox are NOT in
# this repo and will never be.

# 5. Sign in
az login --tenant <your-tenant-id>
pac auth create --name <profile> --environment <env-url>

# 6. Dry-run first, always
.\Invoke-Deploy.ps1 -DryRun

# 7. Live cycle when ready
.\Invoke-Deploy.ps1                 # full deploy + seed + smoke
.\Invoke-Deploy.ps1 -Teardown       # destroy everything created
.\Invoke-Deploy.ps1 -SkipSmoke      # deploy without smoke
```

`config.example.json` documents every field — no separate reference doc needed.

---

## Auth quirks (gotchas that bit us this session)

### Two GitHub accounts on a Microsoft-managed machine

If you have BOTH a personal `judeper` GitHub account AND an EMU `judep_microsoft` account signed in via `gh`, git's credential helper presents the EMU account by default. Result: `git push` to `judeper/FSI-AgentGov-Solutions` returns HTTP 403, and `gh pr create` returns `Unauthorized: As an Enterprise Managed User, you cannot access this content`.

**Fix (every fresh machine):**

```powershell
gh auth status                          # confirm both accounts visible
gh auth setup-git --hostname github.com # reconfigure git credential helper to use gh
gh auth switch --user judeper           # make the owner-account active
```

After these three commands, `git push` and `gh pr create` work normally.

### Dataverse alternate-key activation latency

The `fsi_intakerequest` table has an alternate key `fsi_RequestIdUniqueKey` on `fsi_requestid`. Dataverse takes 30–90 seconds after the key is created to build the supporting index. During that window, the alt-key URI form `fsi_intakerequests(fsi_requestid='...')` returns HTTP 400 "key in the request URI is not valid".

**Resilient pattern (already implemented in `seed-test-data.ps1` and `smoke_test.ps1`):** filter by `fsi_requestid eq '...'`, get the GUID `fsi_intakerequestid` from the result, then operate via the primary-key URI `fsi_intakerequests(<guid>)`. Works regardless of activation state. **Do not** revert to the alt-key URI form in scripts.

### PowerShell `if` is not an expression

`(if ($cond) { 'a' } else { 'b' })` as an argument value throws `'if' is not recognized as a name of a cmdlet`. Use the subexpression operator: `$(if ($cond) { 'a' } else { 'b' })`. Audit any new `Add-Member` / format-string / parameter-value site for this.

### `git commit -m … -m … -m …` hang

Many `-m` flags hang the PowerShell tool harness silently. For multi-paragraph commit messages use `git commit -F <file>` instead.

---

## Pending work

P1 polish items from the v1.0 rubber-duck pass. All landed in PR #142.

- [x] **P1.** Managed-identity-first for billing-policy validation. `Get-AzureAccessTokenForResource` in `scripts/deploy.ps1` now honors env-var-supplied tokens (`BAP_ACCESS_TOKEN`, `POWERPLATFORM_API_TOKEN`) before falling back to az CLI; the az path is marked `# legacy: dev-only — replace with managed identity in production`. Commit `535a3d6`.
- [x] **P2.** Tenant cross-check warning in `lab/Invoke-Deploy.ps1`. Compares `config.environment.tenantId` against `az account show --query tenantId` and emits `Write-Warning` (non-fatal) on mismatch. Commit `de3b416`.
- [x] **P3.** `@odata.nextLink` pagination — verified already implemented in `scripts/shared/dataverse_client.py:227–234` (`query()` follows `@odata.nextLink` to completion). No change needed.
- [x] **P4.** `ValidateSet` ordering for `AllowedEnvironmentType` — verified already correct in `scripts/deploy.ps1:72–73` (attribute before declaration, default value `'Sandbox,Production'`). No change needed.
- [x] **P5.** Help-block refresh. Added missing `.PARAMETER` blocks for `BillingPolicyId`, `EnvironmentId`, `AllowedEnvironmentType` in `deploy.ps1`; documented env-var token hooks in the `AuthMode` description; named the 5 seed scenarios in `seed-test-data.ps1`; enumerated the 8 deployment checks in `smoke_test.ps1`. Commit `3537488`.

Next-iteration follow-ups (not in scope of v1.0.0-preview):

- `fsi_appealofid` is currently a Single Line of Text column — convert to self-lookup in v1.1.
- Microsoft Entra Agent ID `fsiReviewerAttestations` open-type field acceptance pending live-tenant verification.
- PAC CLI cannot programmatically create Power Pages multistep form bindings; Stage 4 of `deploy.ps1` keeps **MANUAL STEP REQUIRED** markers until PAC adds the capability.
- Two legacy PSScriptAnalyzer warnings in `provision_power_pages.ps1` remain soft-gated as the current baseline.

---

## Repo conventions specifically in effect

These are repo-wide rules — see root `AGENTS.md` for the full list — but flagged here because they bite often when extending agent-intake:

- **No exported Power Platform runtime artifacts.** Flows are documented for manual build in [`docs/flow-configuration.md`](docs/flow-configuration.md). The only exception is `templates/reviewer-app-spec.json` (model-driven app spec), explicitly allowed per ADR-011.
- **Dataverse logical names everywhere** in scripts/docs (`fsi_requestid`, never `fsi_request_id`). The single source of truth for column names is [`scripts/create_fsi_intake_dataverse_schema.py`](scripts/create_fsi_intake_dataverse_schema.py); the SchemaName lowercased equals the logical name.
- **FSI language rules:** no "ensures compliance" / "guarantees" / "will prevent" / "eliminates risk" anywhere. Use "supports compliance with" / "helps meet" / "required for".
- **Privacy guardrail:** no tenant IDs / env GUIDs / billing-policy IDs / UPNs in any committed file. They live in `config.local.json` (gitignored). The lab-tenant values are kept by the developer outside the repo.
- **Auth: managed-identity-first.** `# legacy: dev-only — replace with managed identity in production` comment on client-secret / az-CLI-only paths.

---

## Recent design decisions (why things are the way they are)

| Decision | Why |
|---|---|
| Filter-then-GUID lookups instead of alt-key URI | Resilient through the 30–90s alt-key index activation latency. See [Auth quirks](#auth-quirks-gotchas-that-bit-us-this-session). |
| `Invoke-Deploy.ps1` plumbs `config.purview.operatorUpn` → `AGENT_INTAKE_PURVIEW_ADMIN_UPN` env var | Avoids interactive `Read-Host` prompt in Stage 3 of `deploy.ps1` when running unattended. |
| Single consolidated commit for the bug-fix pack (`53a09c4`) | Many `-m` flags hang the tool harness; using `-F <file>` worked and kept the 6 fixes together for atomic revert. |
| ADR-011 model-driven reviewer queue app (managed `.zip`) | App-only packaging is the **only** Power Platform artifact form allowed in this repo. Flows remain doc-only. |
| 5 deterministic seed scenarios | Exercise Express-happy, Standard-conditional, Full-parallel-board, cross-border-deny, sponsor-self-approval-deny — every code path in the classifier and routing engine. |
| `dataverse_client.py` lives in `scripts/shared/` | Shared across 30+ solutions. Any additive change must keep the existing call contract; never break existing solutions. |

For the full architectural decision record, see [`docs/decisions.md`](docs/decisions.md).

---

## Where to look

| Need to … | Look here |
|---|---|
| Understand the solution end-to-end | [`README.md`](README.md) |
| See version history | [`CHANGELOG.md`](CHANGELOG.md) |
| Trace a Dataverse column | [`scripts/create_fsi_intake_dataverse_schema.py`](scripts/create_fsi_intake_dataverse_schema.py) |
| Build a flow manually | [`docs/flow-configuration.md`](docs/flow-configuration.md) |
| Run the lab cycle | [`lab/README.md`](lab/README.md) + [`lab/Invoke-Deploy.ps1`](lab/Invoke-Deploy.ps1) |
| Investigate a failed deploy | `lab/.deploy-runtime/agent-intake-deploy-*.log` (gitignored; per-run) |
| Run the test suite | `pytest agent-intake/tests` (42 cases) |
| Understand the orchestrator | [`docs/orchestrator-architecture.md`](docs/orchestrator-architecture.md) |
| Understand drift integration | [`docs/drift-detection-integration.md`](docs/drift-detection-integration.md) |
| Find the open PR | [PR #142 on GitHub](https://github.com/judeper/FSI-AgentGov-Solutions/pull/142) |

---

## Things NOT to do

- ❌ Do not export and commit Power Automate flow JSON. Flows stay documented in `docs/flow-configuration.md`.
- ❌ Do not put tenant identifiers (tenant ID, env GUID, billing-policy GUID, UPN) in any committed file, including this one.
- ❌ Do not edit anything under `site-docs/solutions/agent-intake/` — that path is gitignored and regenerated by `python scripts/build-manifest.py`. Edit source in `agent-intake/manifest.yaml` and `agent-intake/docs/` instead.
- ❌ Do not revert to alt-key URI lookups in seed / smoke / teardown scripts.
- ❌ Do not delete `lab/.deploy-runtime/*.log` from inside scripts; they're per-run forensic evidence.
