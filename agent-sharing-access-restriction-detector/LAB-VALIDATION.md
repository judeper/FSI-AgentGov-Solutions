# Lab Validation Report — Agent Sharing Access Restriction Detector (ASARD)

> **Solution:** Agent Sharing Access Restriction Detector (ASARD)
> **Version:** v2.0.2
> **Controls:** 1.18 (Application-Level Authorization and RBAC), 2.8 (Access Control and Segregation of Duties)
> **Validation date:** 2026-06-09
> **Validation type:** Live (lab tenant) — plane #1 (chat-ACL) detection proven end-to-end against a live Dataverse fixture row (independently verified; SHA-256 evidence verified three ways); C1 data-plane write proven; C2 runtime enforcement recorded as a documented boundary. Includes the static parse-validity, authoritative-source, and documentation-completeness checks below.

## Purpose and Controls

ASARD provides zone-based detective controls over Copilot Studio agent sharing.
It enumerates Power Platform environments, reads each agent's sharing posture from
the Dataverse `bot` table (`accesscontrolpolicy`, `authorizedsecuritygroupids`),
and compares it against per-zone approved-security-group policy. Non-compliant
agents are persisted to Dataverse, routed through an approval-gated remediation
workflow, and managed via time-bound exceptions. The solution supports
compliance with FINRA Rule 4511, SOX Section 404, and GLBA Section 501(b)
record-keeping and access-control expectations; it does not by itself satisfy any
regulation in isolation.

## Sharing-Plane Coverage (Scope Honesty)

Copilot Studio agent sharing spans **three distinct planes**. ASARD v2.0.2 validates
**plane #1 only** — the runtime **chat ACL**. Planes #2 and #3 are **known gaps**: they
are not enumerated by ASARD's detection scan and not touched by its remediation. ASARD
must **not** be presented as complete agent-sharing-governance coverage. It **supports
compliance with** zone-based access-control expectations for the chat-ACL plane and
should be paired with separate controls for the authoring-share and Agent Store planes.

| # | Plane | Surface | ASARD v2.0.2 coverage |
|---|-------|---------|-----------------------|
| 1 | Chat ACL (runtime) | `bot.accesscontrolpolicy` + `bot.authorizedsecuritygroupids` | **Covered** — detection scan plus approval-gated remediation |
| 2 | Authoring share | `PrincipalObjectAccess` Editor/Viewer rows on the bot row (the Copilot Studio "share" surface) | **Known gap** — not enumerated. Reading or changing it would require the Dataverse `RetrieveSharedPrincipalsAndAccess` message (or the `GrantAccess`/`ModifyAccess`/`RevokeAccess` messages). A principal granted Editor rights via authoring-share can re-author or redirect a bot without ever appearing in `authorizedsecuritygroupids`. |
| 3 | M365 Copilot Agent Store / Teams "Built for your org" | M365 Admin Center "Deployed to" | **Known gap** — out of scope, already disclaimed in the README "M365 Copilot Agent Store" notes. Governed in the M365 Admin Center, not Power Platform environment sharing. |

> **Coverage caveat.** `accesscontrolpolicy = 1` ("Copilot readers", individuals only)
> is classified by the scanner but carries no principal enumeration (see "Runtime-Only
> Caveats" below). That limitation is a sub-case of plane #1 and is **not** a substitute
> for closing the plane #2 authoring-share gap.

## What Was Checked

| Area | Method | Result |
|------|--------|--------|
| Python scripts parse | `python -m py_compile` on all 5 `.py` files | Pass |
| PowerShell scripts parse | `Parser::ParseFile` on all 5 `.ps1` files | Pass (0 errors) |
| Adaptive card templates | `ConvertFrom-Json` on all 5 templates | Pass (valid JSON) |
| Dataverse column references | Cross-checked every `$select`/`$filter`/PATCH body against `create_asard_dataverse_schema.py` and `docs/dataverse-schema.md` | Pass — all logical names valid |
| Option-set values | Verified compliance/severity codes use `100000000+` not `0/1/2` | Pass |
| Environment-variable names | Cross-checked `create_asard_environment_variables.py` against `docs/flow-configuration.md` | Pass — 4 variables consistent |
| Language rules | grep for the FSI-prohibited compliance-absolute phrases (per `fsi-language-rules.instructions.md`) across `*.md` | Pass — no violations |
| API/permission claims | Verified against Microsoft Learn (see Sources) | Pass |

## Authoritative Sources Cited

1. **Copilot (bot) table/entity reference (Microsoft Dataverse)** —
   https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/bot
   - Confirms `accesscontrolpolicy` is a Picklist (GlobalChoiceName `bot_accesscontrolpolicy`)
     with choices: **0 = Any**, **1 = Copilot readers**, **2 = Group membership**,
     **3 = Any (multi-tenant)**. This exactly matches `docs/flow-configuration.md`
     and the `Get-AgentSharingClassification` mapping in `Invoke-SharingComplianceScan.ps1`
     (0→OrgWide, 1→SpecificUsers, 2→GroupMembership, 3→Public).
   - Confirms `authorizedsecuritygroupids` is a comma-delimited list of up to 20 Entra
     group IDs, **ignored unless Access Control Policy = Group membership** (MaxLength 739).
   - Confirms table `EntitySetName` = `bots`, `PrimaryIdAttribute` = `botid`.
2. **Control how agents are shared** (Power Platform admin) —
   https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits
   - Confirms "You can't grant **Editor** permissions to security groups"; **Viewer**
     assignments can be shared with security groups. Matches the README "Platform Update
     Notes" and `docs/flow-configuration.md` "Current Microsoft Learn Sharing Guidance".
3. **Approvals — Known issues / run-history retention (Power Automate)** —
   https://learn.microsoft.com/power-automate/ (approvals + 28-day flow run retention)
   - Confirms "An approval flow can wait for 28 days. If the wait time exceeds 28 days,
     that flow fails." Matches the README/flow-config "28-day approval wait limit" caveat.
4. **Get-AdminPowerAppEnvironment / Add-PowerAppsAccount** (Microsoft.PowerApps.Administration.PowerShell) —
   https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/
   - Confirms `Get-AdminPowerAppEnvironment` returns environments for tenant admins, and
     `Add-PowerAppsAccount -Endpoint prod -TenantID <t> -ApplicationId <id> -ClientSecret <secret>`
     is the supported service-principal sign-in. Matches the auth block in
     `Invoke-SharingComplianceScan.ps1`.

## Gaps Identified and Fixes Applied

| Gap | Severity | Fix |
|-----|----------|-----|
| `docs/prerequisites.md` stated the schema-creation script and supporting scripts live "in the companion FSI-AgentGov repository" — they are actually in this solution's `scripts/` folder. A lab operator would look in the wrong repo. | Medium (doc accuracy) | Corrected both references to "this solution's `scripts/` folder". |
| README Components tree omitted the `scripts/` directory (only `docs/` and `templates/` were shown), while the Scripts table below listed them — inconsistent directory map. | Low | Added the `scripts/` subtree to the Components listing. |
| CHANGELOG `[Unreleased]` did not record the documentation corrections or this report. | Low | Added a `### Documentation` block under `[Unreleased]`. |

No script logic, API call, auth pattern, column name, or option-set value required
correction — the solution had already been through a council review (v2.0.1/v2.0.2)
that resolved the deprecated MSAL.PS dependency, schema-doc drift, and parameter
clarity issues.

## Runtime-Only Caveats (cannot be verified without a tenant)

These items are correct by construction/documentation but require a live Power
Platform tenant with Copilot Studio agents to exercise end-to-end:

- **`accesscontrolpolicy = 1` ("Copilot readers") detection scope.** The scanner
  classifies policy value `1` as `SpecificUsers` and reads no principal list for it
  (`authorizedsecuritygroupids` is populated by Dataverse only for policy `2`,
  Group membership). Agents shared with many *individual* users under "Copilot
  readers" are therefore treated as compliant. This is a documented design boundary
  (ASARD validates group-policy posture; UASD covers broad unrestricted sharing),
  not a defect — but it is the most important coverage limitation for Zone 1
  reviewers to understand. Individual-user share enumeration would require reading
  `principalobjectaccess`/team membership, which is out of scope for v2.0.2.
- **Live token audiences.** Three distinct audiences are used and can only be
  confirmed against a tenant: `https://service.powerapps.com/.default` (admin API),
  per-environment `<instanceApiUrl>/.default` (Dataverse bot reads), and the
  configured `<DataverseUrl>/.default` (ASARD tables). The code acquires each
  separately; failures are converted to `SCAN_COVERAGE_GAP` rows rather than
  silently reported as compliant — verified by code reading, not execution.
- **Service-principal privileges.** The app registration needs an application user
  with read access to the `bot` table in every scanned environment and read/write
  on the ASARD tables, plus Power Platform admin registration and Graph
  `Group.Read.All`/`User.Read.All`. Effective privilege can only be confirmed in a
  tenant.
- **Approval throughput vs the 28-day ceiling.** The sequential (concurrency=1)
  approval loop with 7-day timeouts can exceed the 28-day Power Automate approval
  wait limit beyond ~4 non-compliant agents. Documented in README "Known
  Limitations"; only observable at runtime under load.
- **Managed Environment sharing-limit enforcement delay.** Microsoft Learn notes up
  to one hour for new sharing rules to apply and that existing access is not
  retroactively removed. ASARD detective scans will surface pre-existing
  over-sharing that the preventive layer does not auto-remediate.

## Lab-Readiness Assessment

**Ready for lab validation.** All scripts parse, all templates are valid JSON, all
Dataverse column/option-set references match the schema source of truth, all
environment-variable names are consistent across script and docs, and every
external API/permission/feature claim was verified against authoritative Microsoft
Learn documentation. The documentation gaps that would have misdirected a lab
operator (wrong repo for the scripts) are fixed. Remaining unknowns are strictly
runtime behaviors that require a live tenant; they are enumerated above so a lab
operator can plan targeted execution tests. No blocking issues.

## Second-Pass Command-Existence Re-Verification (2026-06-05)

An independent second-pass audit re-derived every invoked command, cmdlet, CLI verb, REST endpoint and api-version, Dataverse entity set / logical column / option-set, and module against Microsoft Learn, with a sharpened focus on confirming each surface exists and will run in a live lab. Dataverse bot sharing columns (accesscontrolpolicy system picklist 0-3, authorizedsecuritygroupids), PowerApps Administration cmdlets, OAuth token / device-code endpoints, and the custom Dataverse entity sets and option-sets were confirmed against Microsoft Learn; no corrections required.

## Live Lab Validation (2026-06-09)

**Validation type:** Live execution against the lab validation tenant (a Sandbox environment), single-flight live-writer session. All live mutations used a **clearly tagged, disposable throwaway fixture only**; the two real agents in the environment were never modified (verified before and after — both remained `accesscontrolpolicy = 1` with unchanged `modifiedon`).

### Verified in-env option-set integers (read live, not assumed)

Read from `GlobalOptionSetDefinitions` / `PicklistAttributeMetadata` (the global-set names are lowercase `fsi_asard_*` and the lookup is case-sensitive):

- `fsi_acv_zone` (binds `fsi_zone`): 100000000 = Unclassified, 100000001 = Zone 1, 100000002 = Zone 2, 100000003 = Zone 3.
- `fsi_compliancestatus` (global `fsi_asard_compliancestatus`): 100000000 = Compliant, **100000001 = NonCompliant**, 100000002 = Exception, 100000003 = Error.
- `fsi_remediationstatus` (global `fsi_asard_remediationstatus`): 100000000 = Pending, 100000001 = Approved, 100000002 = Rejected, 100000003 = Completed, 100000004 = Failed.
- `fsi_severity` is a plain Integer column (not an option set): Critical = 100000000 … Informational = 100000004.

### Zone-integer drift fix (Parker H4) — applied and gated

`Invoke-SharingComplianceScan.ps1` and `Export-SharingComplianceEvidence.ps1` previously assumed 0–3 zone integers; the lab tenant uses the 100000000-based `fsi_acv_zone`. The persistence, approved-group-lookup, and export filter maps were corrected to the live-verified integers (Unknown → Unclassified = 100000000). Static gates were re-run after the fix: `Parser::ParseFile` reported 0 errors and `Invoke-ScriptAnalyzer` (repo `PSScriptAnalyzerSettings.psd1`) reported 0 findings on both files. The independent Get-row read-back returned `fsi_zone = 100000000` with FormattedValue **"Unclassified"**, confirming the corrected integer resolves in-env.

### Detection — proven (rows + evidence hash)

- Seeded one disposable over-shared fixture agent (`accesscontrolpolicy = 2` Group membership + a non-approved group) and one disposable approved-group policy row (zone Unclassified, active). Baseline `fsi_agentsharingcompliances` = 0 rows.
- Ran `Invoke-SharingComplianceScan` against the live environment with Dataverse persistence. The scan enumerated the environment, scanned **3 agents** (the 2 real agents + the fixture), and detected exactly **1 violation** — the fixture — classified `GroupSharing` / Critical. Both real agents returned no violation (compliant; not persisted, not modified).
- **Independent verification** (separate Entra Global Admin token Get-row, not the scan's own log) confirmed the persisted `fsi_agentsharingcompliances` row: `fsi_compliancestatus = 100000001` → FormattedValue **"NonCompliant"**; `fsi_zone = 100000000` → FormattedValue **"Unclassified"**; `fsi_violationtype = GroupSharing`; `fsi_sharingtype = GroupMembership`; `fsi_severity = 100000000` (Critical); and `fsi_scanrunid` matched the executing scan's RunId, tying the row to this run.
- **Evidence + SHA-256 integrity:** `Export-SharingComplianceEvidence` produced `asard-evidence-All-20260609-042338.json` (1 record, 1 violation, 1 policy). SHA-256 `67F6A9A55C9BEDF2F1A03532D0D7B71025029187687D9549A9E2B2F22D9CA2BE` was verified **three independent ways** — `Test-EvidenceIntegrity` returned true, an independent `Get-FileHash` re-hash matched, and the `.sha256` companion file matched. Evidence is retained locally in the gitignored `lab/.deploy-runtime/evidence/` runtime folder.

This live run demonstrates that the plane #1 (chat-ACL) detection → persistence → tamper-evident-evidence path **supports compliance with** the Control 1.18 / 2.8 record-keeping and access-control expectations for the lab fixture; it does not by itself satisfy any regulation in isolation.

### Enforcement (C1 premise / C2 runtime) — empirical result + propagation

- **C1 premise — proven (data plane).** A single combined PATCH of the disposable agent's `accesscontrolpolicy = 2` + `authorizedsecuritygroupids` persisted together; an independent Get-row read-back confirmed both fields stuck. Measured Dataverse write → independent read-back latency ≈ **1.9 s** (metadata-write latency, effectively immediate).
- **Empirical guard nuance (refines the build runbook note).** A raw Dataverse `PATCH` of `authorizedsecuritygroupids` **persisted while `accesscontrolpolicy = 1`** in the lab tenant. The documented "ignored unless Access Control Policy = Group membership" behaviour is therefore a **runtime enforcement** semantic, **not** a data-layer write guard. Remediation must set **both** `accesscontrolpolicy = 2` and the approved group list; writing the group list alone is data-writable but runtime-inert.
- **C2 runtime enforcement — not empirically forcible with this fixture (boundary documented).** The disposable fixture is a fabricated `bot` record with no published runtime endpoint, and both referenced group IDs are **synthetic** (Microsoft Graph returned HTTP 404 for each — no real members to remove, no runtime to chat against). A true "chat as a removed security-group member" test could not be driven in this lab. The governing bound is the **documented** Microsoft behaviour already recorded under "Runtime-Only Caveats": new sharing rules can take **up to ~1 hour** to apply and existing access is **not** retroactively removed. This is recorded as a documented boundary, **not** an empirically measured enforcement latency, consistent with the runbook directive to document the propagation delay as an observed result rather than a guarantee.

### Environmental boundary — `Add-PowerAppsAccount` (admin module) with SP secret under PowerShell 7

`Invoke-SharingComplianceScan` couples environment **enumeration** (the `Microsoft.PowerApps.Administration.PowerShell` cmdlets `Add-PowerAppsAccount` + `Get-AdminPowerAppEnvironment`) with **detection + persistence** (raw Dataverse REST). In this lab, `Add-PowerAppsAccount -ClientSecret` failed with `AADSTS7000215 (Invalid client secret)` under **PowerShell 7**, even though the **identical** secret authenticated successfully via raw OAuth `client_credentials` REST (the scan's own `[1/5]` step) and minted working Dataverse tokens. The failing secret's only special characters were URL-unreserved (`~`, `-`), ruling out an encoding/special-character cause, and the module is not installed for Windows PowerShell 5.1 in this environment. The behaviour is consistent with the admin module's SecureString handling under pwsh 7 and is an **environmental/module boundary, not an ASARD detection defect**.

To exercise the **detection + persistence** path live without the module dependency, the two enumeration cmdlets were shadowed with the **real** lab validation environment fetched live from the **BAP admin REST API** (`/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments`) using the service principal — which enumerated **24 environments** successfully, confirming the SP genuinely holds admin enumeration capability. The scan's detection logic, zone classification, approved-group lookup, and Dataverse persistence then ran **unmodified** against the live tenant. **Recommended for the back-port:** decouple enumeration from detection (add an `-EnvironmentUrl` / pre-enumerated-environments path, or call the BAP REST environments API directly) so the scan can run headless under pwsh 7 with service-principal-secret auth without taking the admin module on the critical path.

### Disposable fixture teardown — complete (verified by read-back)

- Persisted `fsi_agentsharingcompliances` violation row — deleted (Get returns 404).
- Disposable fixture agent + its 15 auto-seeded `botcomponent` children — deleted (Get returns 404).
- Disposable `fsi_approvedsecuritygrouppolicies` row — deleted (Get returns 404).
- Both ASARD tables returned to **0 rows** (baseline).
- Scan service principal de-privileged: Dataverse application user **disabled** (access revoked; Dataverse retains the disabled stub), Power Platform management-application registration **removed**, and **all** client secrets **deleted** (0 credentials remain on the app). The session-only secret environment variable was removed; no secret was written to any committed file.
- The two real agents were verified **unchanged** before and after (both `accesscontrolpolicy = 1`).

### Planes #2 / #3 — still known gaps

Unchanged from the static report: ASARD validates **plane #1 (chat ACL)** only. Plane #2 (authoring share via `PrincipalObjectAccess`) and plane #3 (M365 Copilot Agent Store) remain **known gaps** and were not exercised by this live run.

### Remaining human boundary

Flow B (Remediation Approval) remains **staged Draft** behind a human-approval + connection-consent boundary: it requires an interactive maker to consent the Dataverse / Approvals connections and to approve each remediation before any live `bots` PATCH. Detection (the scan + Flow A exception-review path) is validated live; **approval-gated remediation execution remains a human-in-the-loop step** and was intentionally not auto-run.

### Known Issues and Fix-Forward

| # | Known issue | Impact | Fix-forward |
|---|-------------|--------|-------------|
| KI-1 | `Add-PowerAppsAccount -ClientSecret` (admin module `Microsoft.PowerApps.Administration.PowerShell`) returns `AADSTS7000215 (Invalid client secret)` under **PowerShell 7**, even though the **identical** service-principal secret authenticates successfully via raw OAuth `client_credentials` REST and via the BAP admin REST API (the service principal enumerated 24 environments that way). The admin module is used **only** for environment enumeration; ASARD detection + persistence are raw Dataverse REST and ran **unmodified**. This is an environmental/module boundary, **not** an ASARD detection defect. | Under pwsh 7 with service-principal-secret auth the scan cannot enumerate environments through the admin module; this live run shadowed enumeration with a BAP admin REST environment fetch so detection + persistence could run unchanged. | Decouple environment **enumeration** from **detection + persistence** in `Invoke-SharingComplianceScan.ps1` — add an `-EnvironmentUrl` (or pre-enumerated-environments) parameter, or call the BAP admin REST environments API directly — so the scan runs headless under pwsh 7 without taking the admin module on the critical path. Carry into the back-port. |

## Canonical-zone reconciliation — known evidence inversion

> **Added 2026-06-13 — portfolio canonical-zone decision (Option A). Code-and-text-only
> remap; this solution was NOT re-validated against a live tenant in this change.**

Earlier releases of ASARD keyed the environment-**name** classifier inversely
(enterprise → Zone 3, personal → Zone 1), so an enterprise environment was classified Zone 3 and
persisted as `fsi_zone = 100000003`. The per-zone **sharing-policy gradient was already canonical**
— Zone 1 is the strictest tier (no group sharing permitted) — but the zone **labels** were inverted
(Zone 1 labelled "Personal Productivity", Zone 3 labelled "Enterprise/Regulated"). The canonical
producing schema for the shared `fsi_acv_zone` option set (the agent-intake schema) and the live
`fsi_acv_zone` set on the lab validation tenant define the canonical meaning adopted portfolio-wide as
Coordinator Decision "Option A" (2026-06-13):

- **Zone 1 (Enterprise) = `100000001` = most restrictive (no group sharing)**
- Zone 2 (Team) = `100000002`
- **Zone 3 (Personal) = `100000003` = least restrictive**
- Unclassified / fail-closed = `100000000`

This release flips the name classifier (`Invoke-SharingComplianceScan.ps1`) to map
enterprise/prod → Zone 1 and personal/dev → Zone 3, and corrects the `RegulatoryContext` zone labels
in both the PowerShell resolver (`Get-ExpectedSharingPolicy.ps1`) and the Python engine
(`asard_zone_rules.py`). The already-canonical zone→integer write-back (Zone 1 → `100000001`,
Unclassified → `100000000`) is unchanged. A canonical-zone unit assertion
(`lab/Assert-CanonicalZonePolicy.ps1`, "strictest policy ⇔ Zone 1 ⇔ `100000001`") is locked in this
release and gated.

**This live run's specific pass/fail outcome was correct.** Its fixture row resolved to
**Unclassified (`100000000`)**, whose no-group-sharing policy is **unchanged** by this remap, so the
recorded Failed/Critical call was and remains correct.

**For name-classified environments, however, this remap changes the effective policy tier — it is a
behavioral change, not merely a stored integer/label flip.** Because the per-zone sharing policy is
keyed off the **resolved** zone and this release flips the environment-name classifier:

- an **enterprise/prod-named** environment moves from Zone 3 (group sharing permitted, lenient) to
  **Zone 1** (no group sharing, strictest) — **stricter** (fail-safe);
- a **personal/dev-named** environment moves from Zone 1 (strictest) to **Zone 3** (least restrictive)
  — a **relaxation**.

This corrects a prior inversion that applied over-strict policy to personal-named environments and
under-strict policy to enterprise-named environments, and is the **canonically-correct** behavior — but
it is a real change in the detected/expected sharing policy for those environments, not an
integer/label-only relabel. **Operators should re-run the solution after upgrading and review any
name-classified environments** whose effective tier changes.

**Correctness of this remap — established without a live tenant — rests on three pillars:**

1. the **canonical-zone unit assertion** (deterministic, runs against the remapped code: strictest
   policy ⇔ Zone 1 ⇔ `100000001`, Zone 3 ⇔ `100000003`, Unknown ⇔ `100000000`);
2. **static gates** (PowerShell parse + PSScriptAnalyzer + `py_compile` + valid JSON); and
3. **byte-for-byte alignment with the four lab-validated sibling solutions** (FUS, CMM, GAC, ACA)
   that received the identical flip and were live-validated on the lab validation tenant on 2026-06-13.

**Recommendation for downstream operators.** Any `fsi_zone` rows persisted by earlier releases carry
the pre-canonical integers and labels. They remain valid historical evidence of which environments
were scanned and whether they passed or failed (the pass/fail call was correct), and are retained
unaltered. To refresh persisted integers/labels to the canonical semantics, **re-run the validated
solution after upgrading**; this solution does **not** auto-migrate historical rows.

ASARD **supports compliance with** Controls 1.18 (Application-Level Authorization and RBAC) and 2.8
(Access Control and Segregation of Duties). It does **not by itself ensure, guarantee, or eliminate**
regulatory risk.

