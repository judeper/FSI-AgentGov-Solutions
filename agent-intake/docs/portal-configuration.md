# Power Pages intake form configuration

## Overview

The `agent-intake` maker form now supports all three intake paths through progressive disclosure:

- **Express** — the existing ~13-field maker experience remains the full maker-visible form for low-risk requests.
- **Standard** — adds the catalog-backed Standard questions after the initial route is known.
- **Full** — adds the catalog-backed Full questions after the Standard step when the classifier returns Full.

The maker always sees:

- **Section A** — auto-prefilled identity and sponsorship fields.
- **Section B** — baseline agent scope fields.
- **Section C** — audience plus the six trigger questions that determine `fsi_pathused` and `fsi_decisionpath`.

After Section C is saved, the classifier determines the path and the form reveals only the next step that applies to that request.

Use Dataverse **logical names** in table permissions, form metadata, JavaScript, and flow expressions. The logical name is the schema name lowercased with no extra underscores.

## Prerequisites

| Requirement | Why it is required | Notes |
|---|---|---|
| Power Pages site named `agent-intake` | Hosts the maker-facing page and multistep form. | Use any supported starter site; the PAC CLI can validate/download/upload site content, but classic site creation still needs a manual step. |
| PAC CLI | Required for the provisioning script and lab orchestration. | Install with `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`. Use `pac pages` (the current alias for `pac powerpages`). |
| Dataverse tables already provisioned | The form binds to `fsi_intakerequest` and related child tables. | The maker surface depends on `fsi_intakerequest`, `fsi_intakedatasource`, and `fsi_intakerisksignal` existing before the site is configured. |
| Portal Management app access | Required to configure multistep form condition steps and metadata reliably. | The design studio creates the page shell; Portal Management app adds the Standard/Full step gating. |
| Microsoft Graph pre-fill or an equivalent cloud-flow wrapper | Prefills the maker and sponsor identity fields before submission. | Use `/me` and `/me/manager`, or have a server-side flow populate the same values before the first save. |

## Form architecture

Use a Power Pages **Multistep Form** for v1.0.0-preview.

| Step | Sections / components | Purpose | Applies to |
|---|---|---|---|
| 1 | Sections A, B, C | Capture the baseline request, save a draft record, then run the classifier. | All paths |
| 2 | Section D — Standard catalog renderer | Capture the Standard-only questions and serialize them into `fsi_standardfullquestionsjson`. | Standard and Full |
| 3 | Section E — Full catalog renderer | Capture the Full-only questions and serialize them into `fsi_standardfullquestionsjson`. | Full only |
| 4 | Section F — maker attestation + submit | Reconfirm the route banner, collect the attestation, and submit the request. | All paths |

Recommended behavior between steps:

1. Step 1 creates the `fsi_intakerequest` row with `fsi_status = Draft`.
2. A pre-submit classifier flow (or equivalent server-side action) evaluates the Step 1 answers and writes `fsi_pathused`, `fsi_decisionpath`, and the initial `fsi_standardfullquestionsjson` payload.
3. Multistep Form condition steps evaluate `fsi_pathused` to decide whether Step 2 and/or Step 3 should be shown.
4. Step 4 is always the terminal maker step unless `fsi_decisionpath = DefaultDeny`, in which case the session should redirect to a read-only denial/status panel instead of collecting more inputs.

## Table permissions

Keep the current narrow permissions model:

| Table | Permission | Web role |
|---|---|---|
| `fsi_intakerequest` | Create, Read own, Update own while Draft | Authenticated Users |
| `fsi_intakedatasource` | Create, Read own, Update own while Draft | Authenticated Users |
| `fsi_intakerisksignal` | Read own | Authenticated Users |

Administrators and reviewers should continue to use model-driven app security roles rather than broad portal write access. If you add child permissions in the design studio, inherit roles from the parent permission instead of creating a separate global-access permission.

## Existing Express field bindings (retained)

These bindings stay unchanged. They are the full maker-visible surface for the Express path, and they remain the shared baseline shown before the Standard or Full additions are evaluated.

| Step | Dataverse logical name | Prompt | Control | Requirement |
|---|---|---|---|---|
| 1 | `fsi_agentdisplayname` | What should the agent be called? | Text (5–200 chars) | Required |
| 2 | `fsi_businessoutcome` | What business outcome should this support? | Choice or text per customer policy | Required |
| 3 | `fsi_businessjustification` | In one or two sentences, what will it do? | Multiline text (50–500 chars) | Required |
| 4 | `fsi_agenttype` | What type of agent will you build? | Choice `fsi_intake_agenttype` | Required |
| 5 | `fsi_intendedaudience` | Who will use it? | Choice: Just me / My team / My department / Anyone in the firm / External users | Required |
| 6 | `fsi_t1initiatesfinancialtxn` | Will it initiate financial transactions or move money? | Yes / No / Not sure | Required |
| 7 | `fsi_t2customerfacing` | Will it interact directly with customers or external parties? | Yes / No / Not sure | Required |
| 8 | `fsi_t3autonomousunmonitored` | Can it act without a human reviewing each action? | Yes / No / Not sure | Required |
| 9 | `fsi_t4handlesnpi` | Will it process customer nonpublic personal information (NPI)? | Yes / No / Not sure | Required |
| 10 | `fsi_t5handlesmnpi` | Will it process material nonpublic information (MNPI) or information-barrier data? | Yes / No / Not sure | Required |
| 11 | `fsi_t6crossborderdata` | Will data cross country or regional residency boundaries? | Yes / No / Not sure | Required |
| 12 | `fsi_dataresidencycountry` | Where is the data expected to reside? | Country/region text or choice | Required when T6 is Yes/Not sure |
| 13 | `fsi_makerattestation` | I confirm this request follows firm acceptable-use policy and is accurate to the best of my knowledge. | Checkbox | Required |

> `fsi_businessoutcome` is the canonical schema column. If you prefer a separate customer-specific choice for expected outcome, add it as a managed customization and include it in `fsi_decisionpackjson`.

## Standard path additions (catalog-backed)

For v1.0.0-preview, render the Standard questions as custom controls on the Step 2 page and serialize the answers into the canonical memo field `fsi_standardfullquestionsjson`.

| Catalog ID | Capture key in `fsi_standardfullquestionsjson` | Control | Catalog reference | Notes |
|---|---|---|---|---|
| `S1` (`DS-006`) | `standard.s1AdditionalSystems` | Multi-select + free-text Other | `docs/intake-questions-standard.md` | Record any system beyond the baseline Express sources. |
| `S2` (`DS-008`) | `standard.s2PremiumOrCustomConnectors` | Yes / No / Not sure | `docs/intake-questions-standard.md` | Keep the confirmed connector list in the same JSON object if a follow-up picker is used. |
| `S3` (`CT-007`) | `standard.s3HumanApprovalActions` | Multi-select | `docs/intake-questions-standard.md` | Default to “all write/delete/send actions require approval” until the maker changes it. |
| `S4` (`DS-015`) | `standard.s4SharePointReadIdentity` | Single-select | `docs/intake-questions-standard.md` | Capture whether the agent uses the maker identity or a service identity. |
| `S5` (`RT-008`) | `standard.s5EmployeePersonalData` | Yes / No | `docs/intake-questions-standard.md` | Drives the Privacy reviewer signal. |
| `S6` (`OH-005`) | `standard.s6BackupBusinessOwnerUpn` | Microsoft Entra ID UPN picker | `docs/intake-questions-standard.md` | Use the same UPN validation pattern as `fsi_sponsorupn`. |
| `S7` (`BJ-004`) | `standard.s7NinetyDayOutcome` | Free text | `docs/intake-questions-standard.md` | Supports the 90-day outcome review. |
| `S8` (`BJ-013`) | `standard.s8RequestType` | Single-select + existing-agent picker when needed | `docs/intake-questions-standard.md` | Include the referenced approved agent ID when this is a modification. |
| `S9` (`OH-001`) | `standard.s9OperationalSla` | Single-select | `docs/intake-questions-standard.md` | Used by the downstream environment/DR workflow. |
| `S10` (`RR-005`) | `standard.s10TranscriptRetentionOverride` | Yes / No / Not sure | `docs/intake-questions-standard.md` | If the maker requests longer retention, leave the final approval to Records review. |

## Full path additions (catalog-backed)

Render the Full questions as custom controls on the Step 3 page and append them to the same JSON payload.

| Catalog ID | Capture key in `fsi_standardfullquestionsjson` | Control | Catalog reference | Notes |
|---|---|---|---|---|
| `F1` (`RT-002`) | `full.f1Reversibility` | Single-select | `docs/intake-questions-full.md` | Materiality / reversibility input for Tier-1 scoring. |
| `F2` (`RT-003`) | `full.f2DollarImpact` | Single-select | `docs/intake-questions-full.md` | Capture the maximum estimated incident impact band. |
| `F3` (`RT-005`) | `full.f3RegulatedDecisioning` | Yes / No / Partial | `docs/intake-questions-full.md` | Drives the MRM reviewer signal. |
| `F4` (`RT-009`) | `full.f4WriteDeleteSystemOfRecordAccess` | Yes / No | `docs/intake-questions-full.md` | Required before the write-target list is shown. |
| `F5` (`DS-017`) | `full.f5WritableSystems` | Multi-select | `docs/intake-questions-full.md` | Show only when `full.f4WriteDeleteSystemOfRecordAccess = Yes`. |
| `F6` (`CT-006`) | `full.f6CustomerDisclosureLanguage` | Free text or default choice | `docs/intake-questions-full.md` | Show only when the agent is customer-facing. |
| `F7` (`AT-007`) | `full.f7InterAgentDelegation` | Yes / No / Planned future | `docs/intake-questions-full.md` | Feeds inter-agent review and Entra Agent ID delegation review. |
| `F8` (`CD-005`) | `full.f8RelatedAgentIds` | Free text + linked-agent picker | `docs/intake-questions-full.md` | Show only when `full.f7InterAgentDelegation = Yes`. |
| `F9` (`CT-019`) | `full.f9VoiceChannelConsent` | Yes / No / Not voice channel | `docs/intake-questions-full.md` | Show only for voice experiences. |
| `F10` (`OH-014`) | `full.f10SentinelPlan` | Acknowledged / Need help scoping | `docs/intake-questions-full.md` | Confirms SOC monitoring work before go-live. |
| `F11` (`OH-007`) | `full.f11KillSwitchProcedure` | Single-select + optional free text | `docs/intake-questions-full.md` | Required Tier-1 shutdown path. |
| `F12` (`OH-013`) | `full.f12CloudDeploymentTarget` | Single-select | `docs/intake-questions-full.md` | Drives parity and deployment checks. |
| `F13` (`CD-008`) | `full.f13LicensedDataAiRestriction` | Yes / No / Need vendor confirmation | `docs/intake-questions-full.md` | Routes to Procurement / Legal where appropriate. |
| `F14` (`CD-011`) | `full.f14BuildSource` | Single-select | `docs/intake-questions-full.md` | Used for procurement/vendor due diligence. |
| `F15` (`BJ-012`) | `full.f15AcceptableUseAttestation` | Acknowledged checkbox | `docs/intake-questions-full.md` | Keep this last in the Full step per the catalog guidance. |

## Fields per path (see catalogs for full question text)

- **Express path** — use the retained baseline bindings above and the full question text in `docs/intake-questions-express.md`.
- **Standard path** — use the baseline bindings plus the `S1`–`S10` catalog entries in `docs/intake-questions-standard.md`.
- **Full path** — use the baseline bindings plus the `S1`–`S10` Standard entries and the `F1`–`F15` catalog entries in `docs/intake-questions-full.md`.

## Standard/Full extended question capture

Use `fsi_intakerequest.fsi_standardfullquestionsjson` as the **canonical** storage field for the Standard and Full answers in v1.0.0-preview.

Example payload shape:

```json
{
  "catalogVersion": "v1.0.0-preview",
  "pathUsed": "Full",
  "standard": {
    "s1AdditionalSystems": ["ServiceNow", "Custom REST API"],
    "s2PremiumOrCustomConnectors": "Yes"
  },
  "full": {
    "f1Reversibility": "Partially reversible (some effort)",
    "f15AcceptableUseAttestation": true
  }
}
```

Trade-off for the preview release:

- **Option B (recommended for v1.0.0-preview)** — keep the JSON blob canonical so customers can refine the Standard/Full catalog without a Dataverse schema migration for every wording or answer-set change.
- **Option A (v1.1 evolution)** — introduce dedicated `fsi_s*` / `fsi_f*` columns once the question catalogs stabilize and strongly typed reporting is worth the schema expansion.

Do **not** render computed router fields such as `fsi_quorumrequired`, `fsi_parallelreviewersjson`, `fsi_mrmrequired`, or `fsi_mrmhandoffstatus` on the maker form.

## Auto-filled fields

Populate these before submission using Microsoft Graph `/me` and `/me/manager`, or a server-side cloud flow that writes the same values:

| Dataverse logical name | Source |
|---|---|
| `fsi_makerupn` | `/me.userPrincipalName` |
| `fsi_makerdisplayname` | `/me.displayName` |
| `fsi_makerdepartment` | `/me.department` |
| `fsi_makerjobtitle` | `/me.jobTitle` |
| `fsi_makercountry` | `/me.usageLocation` or country |
| `fsi_sponsorupn` | `/me/manager.userPrincipalName`; allow maker override if no manager is returned |
| `fsi_requestid` | New GUID generated on form load or in Flow 1 |
| `fsi_status` | `Draft` until submit; `Submitted` when maker clicks Submit |
| `fsi_policyversionapplied` | `1.0.0-preview` or customer policy version |

Additional rules:

- Block submission when `fsi_makerupn` and `fsi_sponsorupn` match.
- Keep the auto-filled identity fields read-only on the page after the prefill step completes.
- If client-side Graph consent is not approved, prefill these values server-side and refresh the draft before the maker reaches Step 1.

## Routing banner per path

| Path | Maker banner |
|---|---|
| Express | `Your sponsor will receive a Teams approval card. Expected response within 3 business days.` |
| Standard | `This request needs review by ${reviewerList}. Expected response within ${reviewerSlaBusinessDays} business days.` |
| Full | `This request needs review by ${reviewerList}. Expected response within ${reviewerSlaBusinessDays} business days. MRM review will run in parallel for Tier-1 model risk assessment.` |

If `fsi_decisionpath = DefaultDeny`, replace the normal banner with a read-only status message and stop the multistep session instead of revealing more questions.

## PAC CLI provisioning

See `scripts/provision_power_pages.ps1`.

The script uses PAC CLI where the documented command surface exists today:

- `pac auth who`
- `pac env select`
- `pac model list-tables`
- `pac pages list`
- `pac pages download`
- `pac pages upload`

Per the Microsoft Learn pages reference, PAC CLI currently documents site discovery plus download/upload of website content. It does **not** document first-party commands to create a classic Power Pages site, create a classic page, add a multistep form definition, or configure table permissions directly. For those gaps, follow the manual fallback steps in `docs/maker-form-progressive-disclosure.md`.

## Power Pages notes

- **Recommend Multistep Form for v1.0.0-preview.** Use step-level gating for Standard and Full. A single-page JavaScript approach is acceptable only as a fallback when the tenant cannot use Portal Management app condition steps.
- Keep approval, routing, reviewer-list calculation, and MRM flags in Power Automate / Dataverse. The portal should collect maker inputs, serialize Standard/Full answers into `fsi_standardfullquestionsjson`, and display status.
- Keep `fsi_dataresidencycountry` hidden until `fsi_t6crossborderdata` is `Yes` or `Not sure`.
- If the site uses custom JavaScript to call Microsoft Graph, use delegated user context and document consent in customer change control.
- If optional `fsi_s*` / `fsi_f*` columns are introduced later, treat them as read-only mirrors while `fsi_standardfullquestionsjson` stays canonical for the preview release.
