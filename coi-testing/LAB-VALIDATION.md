# COI Testing — Lab-Readiness Validation

> **Validator:** Autonomous engineering pass (static validation; no live tenant)
> **Date:** 2026-06-04
> **Solution version:** v1.1.2
> **Branch:** `validation/coi-testing`

## Purpose and Controls

The COI Testing solution defines a library of conflict-of-interest (COI) test
scenarios for AI agent recommendations, drives them (in a future release) against
a Copilot Studio agent, and records results to a Dataverse table
(`fsi_coitestresults`) for supervisory review.

Primary framework controls: **2.18** (Automated Conflict of Interest Testing),
**2.11** (Bias Testing and Fairness Assessment), **2.5** (Testing, Validation and
Quality Assurance). Regulatory alignment: FINRA Rules 2111, 2010, 2210, 3110 and
SEC Regulation Best Interest (supporting/contributing role only — no single
control satisfies a regulation in isolation).

This is a **scaffold release**: the scenario library, the Dataverse result schema,
and the runner shell exist; the Direct Line agent-interaction layer and pass/fail
response evaluation are intentionally **not yet implemented**, so every scenario
reports `SKIPPED`.

## What Was Checked

| Area | Method | Result |
|------|--------|--------|
| `scripts/run_coi_tests.py` parse-validity | `python -m py_compile` | Pass (exit 0) |
| `scripts/Get-CoiInventory.ps1` parse-validity | `[Parser]::ParseFile` | Pass (0 errors) |
| Runner behavior — all scenarios dry-run | `--dry-run --allow-skipped` | 10 scenarios, all `SKIPPED`, exit 0 |
| Runner behavior — category filter | `--category proprietary_bias --report json` | 3 records returned, valid JSON |
| Runner exit code — all skipped, no flag | `--category cross_selling --dry-run` | exit 3 (as documented) |
| Runner exit code — bad category | `--category nonexistent` | exit 2 (as documented) |
| Report formats | text / json / html | All render; JSON is clean on stdout (banners on stderr) |
| Dataverse column references | Cross-check runner ↔ `docs/dataverse-schema.md` ↔ `.ralph-config.json` | Consistent logical names |
| Option-set values | Runner `status_map` ↔ schema doc ↔ README | Consistent `100000000`–`100000004` |
| Language rules | grep for the FSI-prohibited compliance-absolute phrases (per `fsi-language-rules.instructions.md`, excl. CHANGELOG) | Clean |

### Column / option-set consistency

The runner `save_results()` writes `fsi_scenarioid`, `fsi_scenarioname`,
`fsi_category`, `fsi_status`, `fsi_executedon`, `fsi_findings` — all logical names
(all-lowercase, no inter-word underscores), matching `docs/dataverse-schema.md`
and the `.ralph-config.json` domain facts. POST target is the **entity set**
`fsi_coitestresults` (plural) while the table logical name is `fsi_coitestresult`
(singular) — correct Dataverse OData convention. The `fsi_status` Choice values
(`PASS=100000000` … `ERROR=100000004`) match across script, schema doc, README,
prerequisites, and troubleshooting.

## Authoritative Sources Cited

| Claim | Authoritative source |
|-------|----------------------|
| Dataverse Web API record create returns **204 No Content** (runner accepts `[201, 204]`) | https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/use-insomnia-web-api · https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/create-entity-web-api |
| Custom Dataverse Choice (option set) values live in the **100000000+** range | https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/create-update-options-web-api |
| App-only / confidential-client Dataverse token scope is `<environment-url>/.default` (runner uses `f"{environment}/.default"`) | https://learn.microsoft.com/en-us/power-apps/developer/data-platform/authenticate-oauth |
| `pac admin list`, `pac solution list`, `pac connection list`, `--json` are valid PAC CLI commands | https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/admin · https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/solution · https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/connection |
| `azure-identity` credential classes used by the runner (`ManagedIdentityCredential`, `WorkloadIdentityCredential`, `CertificateCredential`, `AzureCliCredential`, `DeviceCodeCredential`, `ClientSecretCredential`, `ChainedTokenCredential`) | https://learn.microsoft.com/en-us/python/api/overview/azure/identity-readme |
| Direct Line 3.0 concepts (referenced as future/not-implemented in a `TODO`) | https://learn.microsoft.com/azure/bot-service/rest-api/bot-framework-rest-direct-line-3-0-concepts |

## Gaps Found and Fixes Applied

| Severity | Gap | Fix |
|----------|-----|-----|
| Minor (docs) | `README.md` carried a **truncated/orphaned note blockquote** at the top — it began mid-sentence ("> implemented; the agent-interaction layer…") with its lead-in clause lost. | Reconstructed it into a complete scaffold-status note consistent with *Overview* / *Implementation Status*. Added an `[Unreleased]` CHANGELOG entry. |

No other defects were found. Scripts parse and run, exit codes match documentation,
column names and option-set values are internally consistent, authentication is
managed-identity-first with a clearly-marked dev-only client-secret fallback, and
no prohibited compliance-language phrases are present.

## Runtime-Only Caveats (not verifiable without a live tenant)

- **Dataverse writes** cannot be exercised here. The 204/201 response handling,
  application-user authorization, and least-privilege role assignment are verified
  against documentation only.
- **Persistence vs `--allow-skipped`:** `save_results()` runs whenever `--dry-run`
  is *not* passed, independent of `--allow-skipped`; `--allow-skipped` controls only
  the exit code (0 vs 3). So a non-dry run without `--allow-skipped` would still POST
  the `SKIPPED` rows before exiting 3. The `manifest.yaml` verification step and
  `.ralph-config.json` fact phrase this as "`--allow-skipped` is required to persist"
  — practically true for a clean (exit-0) persisted run, but persistence itself is
  gated only by the absence of `--dry-run`. Left as documented behavior; no code
  change, since altering persistence gating would change runtime semantics.
- **Agent interaction (Direct Line / Microsoft 365 Agents SDK)** is not implemented;
  all COI pass/fail evaluation is future work. Token generation/refresh and OAuthCard
  sign-in flows will need to be handled when that layer ships.
- **PAC CLI inventory** (`Get-CoiInventory.ps1`) requires an authenticated `pac`
  context and Power Platform Admin role; only static parse and command-name validity
  were checked.

## Lab-Readiness Assessment

**Ready for lab use as a scaffold.** All scripts parse and execute, the runner's
documented exit-code contract and report formats behave exactly as specified, every
Dataverse column/option-set reference is internally consistent and matches
authoritative Dataverse conventions, prerequisites and auth guidance are accurate
and managed-identity-first, and the one documentation defect (a truncated README
note) has been repaired. The solution honestly advertises its scaffold status; the
only items that cannot be exercised in a lab without a live tenant and a future
Direct Line integration are flagged above as runtime-only caveats.
