# Intake questions — Express path

> Path: Express  
> Target: Tier 3 / Zone 3 requests  
> Approver topology: Sponsor 1-click  
> Target completion time: 3-5 minutes

## Path summary

The Express path is the conservative default for personal-scope requests in commercial Microsoft 365 when the maker can satisfy ADR-002: `fsi_intendedaudience = Just me`, the six trigger questions are all `No`, and no cross-border exception is needed under ADR-005. It supports firm-level AI governance under OCC Bulletin 2026-13, keeps SR 11-7-style tiering available where a firm applies it by policy, and captures the books-and-records evidence firms use for FINRA Rule 4511, FINRA Rule 3110, SEC Rules 17a-3 and 17a-4, CFTC Rule 1.31, and GLBA 501(b).

The maker completes the portal form, the sponsor receives a Teams adaptive card, and the approval decision is written into the immutable decision pack. All wording and defaults assume commercial Microsoft 365 and en-US maker-facing text. These questions help firms collect evidence and route the right reviewers; they do not certify compliance.

For v1.0.0-preview, every maker-entered Express answer maps to a first-class Dataverse column on `fsi_intakerequest`. When a request routes beyond Express, the additional Standard and Full answers are stored in `fsi_intakerequest.fsi_standardfullquestionsjson.<jsonKey>`, where `<jsonKey>` uses a stable lower-camel-case form of the proposed v1.1 field name (for example, `s1AudienceExtension`). If v1.1 adds first-class `fsi_s*` or `fsi_f*` columns, treat them as mirrors of the preview JSON payload rather than a rename of the preview storage contract.

## Section A — Maker identity & sponsor (auto-prefilled from Graph)

| Field (Dataverse logical name) | Source | Use in decision pack |
|---|---|---|
| `fsi_makerdisplayname` | Microsoft Graph `/me.displayName` | Human-readable maker identity on sponsor and reviewer views |
| `fsi_makerupn` | Microsoft Graph `/me.userPrincipalName` | Primary accountability key across all intake artifacts |
| `fsi_makerdepartment` | Microsoft Graph `/me.department` | Reviewer routing and business-unit context |
| `fsi_makerjobtitle` | Microsoft Graph `/me.jobTitle` | Reviewer context for scope and role fit |
| `fsi_makercountry` | Microsoft Graph `/me.usageLocation` or profile country | ADR-005 cross-border default-deny comparison input |
| `fsi_sponsorupn` | Microsoft Graph `/me/manager.userPrincipalName`; maker can correct if the manager lookup is blank or wrong | Sponsor routing and approval evidence |
| `fsi_requestid` | GUID generated on form load or pre-submit flow | Correlation key across request, approval, review, and decision-log rows |
| `fsi_status` | System default (`Draft` → `Submitted`) | Workflow lifecycle state |
| `fsi_policyversionapplied` | Deployment policy version from `policy-lookup-tables.yaml` | Audit traceability for the rule set in force at submission |

## Section B — Agent scope & business case

| # | Field (Dataverse logical name) | Question shown to maker | Type | Required | Routing impact | Control mapping |
|---|---|---|---|---|---|---|
| B1 | `fsi_agentdisplayname` | What should the agent be called? | Text 5-200 | Yes | Informational only — carried into the sponsor card, registry handoff, and retained decision pack. | 1.2, 2.13, 3.1 |
| B2 | `fsi_businessoutcome` | What business outcome should this support? | Choice or short text | Yes | Informational only — used for registry metadata, reviewer context, and 90-day value review setup. | 1.2, 2.13, 3.1 |
| B3 | `fsi_businessjustification` | In one or two sentences, what will it do? | Multiline text 50-500 | Yes | Informational only — appears on the sponsor card and supports proportional supervision under FINRA Rule 3110. | 2.12, 2.13, 3.1 |
| B4 | `fsi_agenttype` | What type of agent will you build? | Choice (`fsi_intake_agenttype`) | Yes | Informational only — helps determine environment fit and downstream handoff details. | 1.2, 2.1, 3.1 |
| B5 | `fsi_intendedaudience` | Who will use it? | Choice: Just me / My team / My department / Anyone in the firm / External users | Yes | Gating — `Just me` can remain on Express; `My team` or `My department` routes to Standard; `Anyone in the firm` or `External users` routes to Full. | 1.18, 2.1, 3.1 |

## Section C — Risk triggers & residency

| # | Field (Dataverse logical name) | Question shown to maker | Type | Required | Routing impact | Control mapping |
|---|---|---|---|---|---|---|
| C1 | `fsi_t1initiatesfinancialtxn` | Will it initiate financial transactions or move money? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` routes to Full. | 2.5, 2.12, 2.13 |
| C2 | `fsi_t2customerfacing` | Will it interact directly with customers or external parties? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` routes to Full. | 1.7, 2.12, 2.13 |
| C3 | `fsi_t3autonomousunmonitored` | Can it act without a human reviewing each action? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` makes the request ineligible for Express and routes to Standard or Full depending on the rest of the record. | 2.12, 2.13, 2.24 |
| C4 | `fsi_t4handlesnpi` | Will it process customer nonpublic personal information (NPI)? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` routes to Standard at minimum; if combined with autonomy, customer-facing output, or cross-border activity it routes to Full. | 1.5, 1.14, 2.13 |
| C5 | `fsi_t5handlesmnpi` | Will it process material nonpublic information (MNPI) or information-barrier data? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` routes to Full and makes Compliance review mandatory. | 1.22, 2.12, 2.13 |
| C6 | `fsi_t6crossborderdata` | Will data cross country or regional residency boundaries? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` blocks Express, triggers ADR-005 default-deny handling, and routes to Full unless Privacy approves an override. | 1.14, 2.12, 2.13 |
| C7 | `fsi_dataresidencycountry` | Where is the data expected to reside? | Country/region text or choice | Yes if C6 is not `No` | Gating when C6 is not `No` — if the maker country and declared residency differ, the router applies ADR-005 default-deny pending Privacy override. | 1.14, 2.1, 2.13 |

## Section D — Maker attestation

| # | Field (Dataverse logical name) | Question shown to maker | Type | Required | Routing impact | Control mapping |
|---|---|---|---|---|---|---|
| D1 | `fsi_makerattestation` | I confirm this request follows firm acceptable-use policy and is accurate to the best of my knowledge. | Checkbox | Yes | Gating — unchecked requests cannot be submitted. | 2.13, 3.1 |

## Customer override notes

Customers should tune this path through configuration, not by forking the schema: update the `fsi_businessoutcome` choice list, sponsor SLA, sampling rate, retention label mapping, audience-to-zone routing, and optional NY DFS trigger in `templates/policy-lookup-tables.yaml`. Keep the 13 Express field names stable so the portal, reviewer app, flow documentation, and training materials all reference the same canonical labels.

If a firm needs extra local prompts, add them as customer-specific extensions or serialize them into `fsi_decisionpackjson` while preserving the canonical Express fields above. The Express baseline should remain the same source of truth even when the customer adds local policy overlays.

## Acceptance evidence collected

- Maker-entered Express values are stored on `fsi_intakerequest` alongside the auto-prefilled identity block.
- Sponsor approval evidence is captured in `fsi_intakeapproval` and `fsi_intakesponsorship`, then retained immutably in `fsi_intakedecisionlog`.
- Routing outputs such as `fsi_pathused`, `fsi_decisionpath`, `fsi_risktier`, `fsi_zone`, reviewer flags, and retention metadata are written into the decision pack.
- The authoritative audit artifact is `fsi_decisionpackjson` plus the stamped retention evidence (`fsi_retentionlabelapplied`, `fsi_retentionlabelappliedon`, approval timestamps, and card-render/hash evidence where implemented).
