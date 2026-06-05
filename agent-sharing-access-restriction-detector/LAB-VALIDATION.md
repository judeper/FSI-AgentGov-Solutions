# Lab Validation Report — Agent Sharing Access Restriction Detector (ASARD)

> **Solution:** Agent Sharing Access Restriction Detector (ASARD)
> **Version:** v2.0.2
> **Controls:** 1.18 (Application-Level Authorization and RBAC), 2.8 (Access Control and Segregation of Duties)
> **Validation date:** 2026-06-04
> **Validation type:** Static (no live tenant) — parse-validity, authoritative-source verification, documentation completeness

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

