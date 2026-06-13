# Lab Validation Report — File Upload Security Configurator

> **Validation type:** Static (no live tenant) — parse-validity + authoritative-source verification + documentation completeness
> **Solution version:** v1.1.2
> **Static validation date:** 2026-06-04
> **Live tenant validation:** 2026-06-13 against the lab validation tenant — see **"Live tenant validation outcome (2026-06-13)"** below
> **Branch:** `validation/file-upload-security` (static report) · `lab/file-upload-security` (live validation)

## Live tenant validation outcome (2026-06-13)

On 2026-06-13 the single-flight lab leg was run against the lab validation tenant. This
section records what was proven; the static report below remains the parse/source
record from 2026-06-04 and is unchanged.

**Schema deployed (retained deliverable).** The three FUS tables
(`fsi_fileuploadbaseline`, `fsi_fileuploadvalidationhistory`,
`fsi_fileuploadviolation`) and their 41 columns were deployed and verified on
the lab validation tenant. `fsi_severity` is a free **String** column (the label text
`Critical/High/Medium/Warning/Info`); `fsi_zone` is a Picklist bound to the
canonical shared `fsi_acv_zone` set (`Unclassified=100000000, Zone 1=100000001,
Zone 2=100000002, Zone 3=100000003`). An idempotent re-run created 0 new objects.
**The deployed schema is the retained deliverable** — it stays on the tenant after
the test fixtures are removed.

**Detection proven on disposable-bot fixtures.** Authored disposable Copilot Studio
bots exercised the bot-config-STATE detection path (`aISettings.isFileAnalysisEnabled`):

- **Violation** — an upload-enabled bot in an Enterprise (Zone 1) context resolved to
  Critical and persisted a violation row (`fsi_zone=100000001`, `fsi_severity="Critical"`
  written as a String).
- **Compliant** — an upload-disabled bot produced **no** violation row.
- **Discrimination (same-fixture flip)** — flipping the same fixture between enabled and
  disabled changed the outcome, so the detector is not tautologically green.
- **Indeterminate** — a bot with the nested node absent resolved to **Indeterminate**,
  never a false Compliant (fail-open-to-review).
- **Real-agent cross-check** — a real agent's configuration parsed correctly read-only,
  without mutation.

**Evidence integrity.** The SHA-256 evidence digest recomputed to an integrity match
(digest prefix `E195D5B5…`). 

**Teardown verified.** Every disposable fixture was removed: the violation table
returned 1→0, the three disposable bots were deleted (with their orphaned
botcomponents), and the two real agents on the tenant were left untouched. No
violation rows persist in the lab validation tenant.

**Committed-script fix during the leg.** `scripts/private/Get-ZoneClassification.ps1`
previously dot-sourced the parameterised shared zone script, which executed its
mandatory-parameter body at import and left the function undefined; it now invokes the
shared script via the call operator (`&`) with a naming-convention fallback.

**Evidence framing (lab evidence, not a production claim).** The above is **lab
evidence** gathered on disposable-bot fixtures in the lab validation tenant. It demonstrates
that the bot-config-STATE detection path runs and discriminates; it is **not** proof of
behavior in any customer's production tenant. A customer's tenant evidence is generated
by running the solution against that tenant. Coverage stays **PARTIAL**: only bot-config
STATE is in scope — runtime upload telemetry and Purview DLP evidence remain out of lab
scope. File Upload Security Configurator **supports compliance with** its named controls;
it does not by itself ensure, guarantee, or eliminate regulatory risk.

## Purpose and controls

File Upload Security Configurator performs automated validation of Copilot Studio
agent file-upload settings against governance-zone policies. It enumerates
Copilot Studio agents (the Dataverse `bot` table) across Power Platform
environments, evaluates whether file uploads should be allowed, restricted, or
disabled for each agent's zone, and records baselines, validation history, and
violations in Dataverse.

| Control | Role |
|---|---|
| **1.14** — Data Minimization and Agent Scope Control | Primary |
| **1.8** — Content Moderation Configuration | Cross-check (moderation level for upload-enabled agents) |
| **1.4** — Connector and DLP Policies | Data-boundary context |

Regulatory mapping (supporting, not dispositive): FINRA Rule 4511, FINRA
Regulatory Notice 25-07, SEC Rule 17a-3, GLBA 501(b), and the Interagency
Guidelines Establishing Information Security Standards (12 CFR 30 App. B).

## What was checked

- Parse-validity of every PowerShell (`.ps1`/`.psm1`) and Python (`.py`) file.
- Dataverse column references against the schema source of truth
  (`scripts/create_dataverse_schema.py`) and the logical-name convention.
- Option-set values (zone, severity) against the schema and `.ralph-config.json`.
- The core data-source claim: the `bot` table columns selected by the
  enumeration query, and how file-upload state is extracted.
- Authentication paths (PowerShell Az/MSAL token audience; Python
  managed-identity-first credential chain) and token scopes.
- `Get-AzAccessToken` parameter/return-type compatibility (Az.Accounts 5.x).
- Copilot Studio file-upload feature naming, supported file types, and limits.
- Regulatory/compliance language against the FSI language rules.

## Authoritative sources cited

1. Copilot (bot) table/entity reference (Microsoft Dataverse) —
   https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/bot
2. Allow file input from users (Copilot Studio) —
   https://learn.microsoft.com/microsoft-copilot-studio/image-input-analysis
3. Use uploaded files with generative answers nodes (knowledge-source uploads) —
   https://learn.microsoft.com/microsoft-copilot-studio/nlu-documents
4. `Get-AzAccessToken` reference (Az.Accounts) —
   https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken

## Verified claims (clean)

- **`bot` table query is valid.** `Get-AgentBots` selects
  `botid,name,statecode,statuscode,configuration,publishedon,schemaname`. Source 1
  confirms each of these is a documented column on the Copilot (`bot`) entity,
  including `configuration` (a Memo column described as "Used to store content of
  bot configuration data", MaxLength 1,048,576) and `statecode` (0 = Active).
- **`Get-AzAccessToken -ResourceUri` is correct.** Source 4 documents the
  parameter as `-ResourceUrl` with aliases `Resource, ResourceUri`, so the
  primary call in `Connect-EnvironmentDataverse.ps1` binds on Az.Accounts 5.x; the
  `ParameterBindingException` fallback to `-ResourceUrl` covers older modules. The
  script also handles the SecureString default return type that Source 4 notes for
  recent module versions.
- **Token audiences are correct.** Both the PowerShell MSAL paths
  (`"$DataverseUrl/.default"`) and the Python client
  (`f"{self.environment_url}/.default"`) request the Dataverse resource scope.
- **Python auth is managed-identity-first.** `fus_client.py` builds a
  `ChainedTokenCredential` that prefers `ManagedIdentityCredential` /
  `WorkloadIdentityCredential` before developer credentials, with client secret as
  a marked legacy fallback — consistent with the repo authentication standard.
- **Schema references align.** Column logical names used across scripts and docs
  (`fsi_fileuploadenabled`, `fsi_fileuploadexpected`, `fsi_fileuploadactual`,
  `fsi_runtimestamp`, `fsi_validationtime`, `fsi_contentmoderationlevel`, etc.)
  match `create_dataverse_schema.py`. Option-set values use the 100000000+ range
  (zone, severity) rather than 0/1/2.
- **Language rules pass.** No occurrences of the FSI-prohibited compliance-absolute
  phrases (per `fsi-language-rules.instructions.md`) in solution docs or scripts.
- **Parse-validity.** All `.ps1`/`.psm1` files parse with zero errors
  (`Parser::ParseFile`); all `.py` files compile (`python -m py_compile`).

## Gaps found and fixed

- **README file-input note had drifted from current Microsoft Learn.** The
  "Copilot Studio file input limits" note omitted **DOCX** from the supported
  user-upload types and asserted per-format limits (4 MB DirectLine cap, 40-page
  PDF, 180 KB TXT/CSV) that are no longer present on Source 2. Updated to the
  current authoritative values: supported types DOCX, CSV, PDF, TXT, JPG, PNG,
  WebP, nonanimated GIF (XLSX/PPTX experimental); 15 MB individual file size;
  30,000-character text limit without code interpreter (no limit with code
  interpreter). Also clarified that knowledge-source uploads are a separate
  feature with a 512 MB per-file limit (Source 3). (README "Platform Update
  Notes"; CHANGELOG `[Unreleased]`.)

## Runtime-only caveats (require a live tenant to confirm)

1. **`bot.configuration` JSON schema is undocumented.** Microsoft documents the
   `configuration` column only as opaque "bot configuration data"; it does not
   publish the internal JSON structure or guarantee that the file-upload-enabled
   flag is stored there or under a stable key name. `Get-BotFileUploadEnabled`
   mitigates this by probing several candidate key names and returning **`$null`
   (Indeterminate)** when none match — a fail-open-to-review design rather than a
   silent "disabled". The actual key (if any) must be confirmed against a real
   environment; until then, agents may legitimately resolve to Indeterminate. The
   authoritative maker-facing setting lives under **Settings > Generative AI >
   File processing capabilities > File uploads** (Source 2), which is not
   guaranteed to be surfaced 1:1 in the Dataverse `configuration` blob.
2. **MSAL.PS is deprecated.** `Export-FileUploadEvidence.ps1`,
   `Invoke-FileUploadBaselineCapture.ps1`, and `Start-FileUploadValidationRunbook.ps1`
   use MSAL.PS (`Get-MsalToken`) for certificate-based auth, and
   `docs/prerequisites.md` instructs installing it. MSAL.PS is archived/unmaintained
   by Microsoft. It remains functional, and the token scope is correct, but a future
   release should migrate these certificate paths to managed identity or the Az
   token stack. Not changed here to avoid shipping untested auth without a tenant.
3. **Runbook auth is certificate-only.** `Start-FileUploadValidationRunbook.ps1`
   implements only certificate auth, while the stated standard and
   `docs/prerequisites.md` recommend managed identity for Azure Automation.
   Recommended follow-up: add a managed-identity-first path
   (`Connect-AzAccount -Identity` + `Get-AzAccessToken`) ahead of the certificate
   fallback. Deferred to keep this change documentation-only and avoid unverified
   auth code.
4. **Zone classification fallback.** When ELM Dataverse lookup is unavailable,
   zone classification falls back to display-name pattern matching and defaults
   unclassifiable environments to Zone 1 (most restrictive). Accurate zoning
   requires passing `-DataverseUrl` so the `fsi_acv_environmentregistrations`
   lookup is used.

## Lab-readiness assessment

**Lab-ready for static deployment and dry-run, with documented runtime caveats.**

- Schema deployment (`create_dataverse_schema.py`), environment-variable and
  connection-reference provisioning, and the PowerShell enumeration/comparison
  pipeline are internally consistent, parse cleanly, and reference documented
  Dataverse columns and APIs.
- The single material correctness dependency that cannot be verified without a
  live tenant is whether the per-agent file-upload flag is recoverable from the
  `bot.configuration` blob (caveat 1). The solution degrades safely to
  "Indeterminate" rather than producing false negatives, so a first lab run should
  begin with `-DryRun`, then a scoped `-IncludeEnvironments` run to confirm how
  many agents resolve to Enabled / Disabled / Indeterminate before relying on the
  results for governance decisions.
- Auth modernization (caveats 2–3) is recommended but not blocking for a lab.
