# Intake questions — Standard path

> Path: Standard  
> Target: Tier 2 / Zone 2 requests  
> Approver topology: Sponsor + 2-of-3 reviewer quorum  
> Target completion time: 3-5 business days

## Path summary

The Standard path is used when the initial audience and trigger answers make Express unavailable, but the request still fits a team-scope or department-scope review pattern: internal productivity use, moderate risk, broader sharing than a personal agent, or action-taking behavior that does not justify the full enterprise control pack by default. The path keeps the same books-and-records baseline as Express while adding the evidence reviewers need to apply managed-environment, privacy, connector, and supervision controls proportionally.

The default reviewer pool is InfoSec, Privacy, and Compliance. Sponsor approval is still required, and the router expects any two of the three reviewer roles to approve, while making a specific reviewer mandatory when the answers below indicate sensitive data, regulated communications, or other gating conditions. All wording and defaults assume commercial Microsoft 365 and en-US maker-facing text. The catalog supports evidence collection for OCC Bulletin 2026-13 firm-level governance, SR 11-7-style tiering where used by the firm, FINRA Rule 3110 supervision, FINRA Rule 4511 and SEC Rule 17a-4 recordkeeping, CFTC Rule 1.31 retention, and GLBA 501(b) safeguards; it does not certify compliance.

For v1.0.0-preview, the common baseline answers continue to map to first-class `fsi_intakerequest` columns, while every Standard-only answer below is stored in `fsi_intakerequest.fsi_standardfullquestionsjson.<jsonKey>`. The `<jsonKey>` convention uses a stable lower-camel-case form of the proposed v1.1 field name (for example, `s1AudienceExtension`), and any future first-class `fsi_s*` columns should mirror that preview JSON payload rather than replace it.

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
| B1 | `fsi_agentdisplayname` | What should the agent be called? | Text 5-200 | Yes | Informational only — carried into the sponsor and reviewer packs, registry handoff, and retained decision pack. | 1.2, 2.13, 3.1 |
| B2 | `fsi_businessoutcome` | What business outcome should this support? | Choice or short text | Yes | Informational only — used for registry metadata, reviewer context, and post-launch value tracking. | 1.2, 2.13, 3.1 |
| B3 | `fsi_businessjustification` | In one or two sentences, what will it do? | Multiline text 50-500 | Yes | Informational only — used by sponsor and reviewer quorum members when deciding whether the controls are proportional to the use case. | 2.12, 2.13, 3.1 |
| B4 | `fsi_agenttype` | What type of agent will you build? | Choice (`fsi_intake_agenttype`) | Yes | Informational only — helps determine environment fit, routing notes, and downstream handoff detail. | 1.2, 2.1, 3.1 |
| B5 | `fsi_intendedaudience` | Who will use it? | Choice: Just me / My team / My department / Anyone in the firm / External users | Yes | Gating — `My team` or `My department` keeps the request in Standard unless another answer escalates it; `Anyone in the firm` or `External users` escalates to Full; `Just me` remains in Standard only if another gating signal already fired. | 1.18, 2.1, 3.1 |

## Section C — Risk triggers & residency

| # | Field (Dataverse logical name) | Question shown to maker | Type | Required | Routing impact | Control mapping |
|---|---|---|---|---|---|---|
| C1 | `fsi_t1initiatesfinancialtxn` | Will it initiate financial transactions or move money? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` escalates to Full. | 2.5, 2.12, 2.13 |
| C2 | `fsi_t2customerfacing` | Will it interact directly with customers or external parties? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` escalates to Full and makes Compliance mandatory. | 1.7, 2.12, 2.13 |
| C3 | `fsi_t3autonomousunmonitored` | Can it act without a human reviewing each action? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` keeps the request out of Express and makes InfoSec mandatory; combined with sensitive data or external exposure it escalates to Full. | 2.12, 2.13, 2.24 |
| C4 | `fsi_t4handlesnpi` | Will it process customer nonpublic personal information (NPI)? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` makes Privacy mandatory; combined with autonomy, external exposure, or cross-border activity it escalates to Full. | 1.5, 1.14, 2.13 |
| C5 | `fsi_t5handlesmnpi` | Will it process material nonpublic information (MNPI) or information-barrier data? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` escalates to Full and makes Compliance mandatory. | 1.22, 2.12, 2.13 |
| C6 | `fsi_t6crossborderdata` | Will data cross country or regional residency boundaries? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` escalates to Full and applies ADR-005 default-deny handling until Privacy approves an override. | 1.14, 2.12, 2.13 |
| C7 | `fsi_dataresidencycountry` | Where is the data expected to reside? | Country/region text or choice | Yes if C6 is not `No` | Gating when C6 is not `No` — if the maker country and declared residency differ, the router applies ADR-005 default-deny pending Privacy override. | 1.14, 2.1, 2.13 |

## Section D — Team scope, integrations, and data handling

> Storage model: for v1.0.0-preview, the Standard-only answers below are stored in `fsi_intakerequest.fsi_standardfullquestionsjson` using lower-camel-case keys derived from the proposed v1.1 column names (`s1AudienceExtension` through `s10MonitoringPlan`). If v1.1 adds first-class `fsi_s*` columns, treat them as mirrors of the preview JSON blob rather than a rename of the preview contract.

| # | Canonical storage reference | Question shown to maker | Type | Required | Routing impact | Control mapping |
|---|---|---|---|---|---|---|
| D1 | `fsi_intakerequest.fsi_standardfullquestionsjson.s1AudienceExtension` | Which teams or named Microsoft 365 groups will receive this agent, and about how many users do you expect in the first 90 days? | Composite: group picker + integer band | Yes | Gating — unresolved group scope, external guests, or very broad distribution pushes the request to Full; otherwise this defines reviewer scope and sharing constraints. | 1.2, 1.18, 2.1, 3.1 |
| D2 | `fsi_intakerequest.fsi_standardfullquestionsjson.s2ConnectorInventory` | Which Power Platform connectors, Graph scopes, or external endpoints will the agent use? | Multiselect + free text | Yes | Gating — premium/custom connectors or write/send-external endpoints make InfoSec mandatory; any financial-action endpoint escalates to Full. | 1.4, 1.5, 1.14, 2.13 |
| D3 | `fsi_intakerequest.fsi_standardfullquestionsjson.s3DataSources` | List the SharePoint sites, Dataverse tables, mailboxes, or other data sources the agent will read from. | Multirow text or linked records | Yes | Gating — missing source names returns the request to the maker; regulated or out-of-tenant sources make Privacy or Compliance mandatory and may escalate to Full. | 1.14, 2.13, 2.16, 4.8 |
| D4 | `fsi_intakerequest.fsi_standardfullquestionsjson.s4OutputDestinations` | Where can the agent send or post outputs? | Multiselect: Teams / email / SharePoint / Dataverse / CRM / other | Yes | Gating — customer-directed, public-channel, or broad email distribution makes Compliance and Records mandatory and may escalate to Full. | 1.7, 1.18, 2.12, 2.13 |
| D5 | `fsi_intakerequest.fsi_standardfullquestionsjson.s5OutputClassification` | What sensitivity label and retention class should reviewers assume for typical outputs? | Composite: sensitivity choice + retention choice | Yes | Gating — Confidential or Restricted output, custom retention, or likely WORM scope makes Privacy or Records mandatory. | 1.5, 1.7, 2.13, 4.3 |

## Section E — Operational readiness & reviewer routing

> Storage model: continue using `fsi_intakerequest.fsi_standardfullquestionsjson` for the operational questions below, with the stable keys `s6MakerTrainingAck` through `s10MonitoringPlan`. If v1.1 adds first-class `fsi_s*` columns, treat them as mirrors of the preview JSON blob rather than a rename of the preview contract.

| # | Canonical storage reference | Question shown to maker | Type | Required | Routing impact | Control mapping |
|---|---|---|---|---|---|---|
| E1 | `fsi_intakerequest.fsi_standardfullquestionsjson.s6MakerTrainingAck` | Have you completed the firm's AI maker training for team-scope agents? | Choice: Completed / In progress / Not yet taken | Yes | Gating — `In progress` or `Not yet taken` pauses the request until training is complete or waived by policy. | 2.14, 3.1 |
| E2 | `fsi_intakerequest.fsi_standardfullquestionsjson.s7DeploymentPattern` | Will this agent be promoted across dev/test/prod environments, and will it use Power Fx, custom actions, or custom skills? | Composite: environment choice + Yes/No + short text | Yes | Gating — production promotion requires Managed Environment and change-management checks; custom logic makes InfoSec mandatory and may escalate to Full. | 2.1, 2.3, 2.15, 2.24 |
| E3 | `fsi_intakerequest.fsi_standardfullquestionsjson.s8AgentRouting` | Will this agent call other agents or allow other agents to call it? | Yes / No + linked agent IDs if `Yes` | Yes | Gating — `Yes` makes InfoSec mandatory and may escalate the request under multi-agent orchestration limits. | 1.18, 2.17, 2.13 |
| E4 | `fsi_intakerequest.fsi_standardfullquestionsjson.s9SponsorBackupUpn` | Who is the backup business sponsor or successor approver if the primary sponsor is unavailable? | UPN picker | Yes | Gating — blank, external, or maker-matches-sponsor values block submission until a valid successor is named. | 2.12, 2.13, 3.1 |
| E5 | `fsi_intakerequest.fsi_standardfullquestionsjson.s10MonitoringPlan` | What monthly invocation volume do you expect, and how will you sample or monitor outputs after go-live? | Composite: volume band + sampling/monitoring plan | Yes | Gating — high volume, no monitoring plan, or no sampling rate makes InfoSec and Compliance mandatory and may escalate to Full. | 1.7, 2.9, 3.2, 3.10 |

## Customer override notes

Customers can split these Standard prompts into multiple UI controls if needed, but they should still map back to the canonical storage references and routing semantics above. Reviewer quorum, mandatory reviewer rules, label taxonomies, retention options, connector allow lists, and training prerequisites should be tuned through policy/configuration rather than by renaming the preview JSON keys.

For v1.0.0-preview, keep the Standard-only answers in `fsi_intakerequest.fsi_standardfullquestionsjson` under the documented `s1AudienceExtension` through `s10MonitoringPlan` keys. If v1.1 adds first-class `fsi_s1` through `fsi_s10` columns, treat them as mirrored projections of the JSON blob so the preview payload contract stays stable for the portal, reviewer app, and onboarding material.

## Acceptance evidence collected

- All Express-path evidence plus the Standard additions needed for reviewer quorum decisions.
- Standard-path answers are stored in `fsi_intakerequest.fsi_standardfullquestionsjson` under the stable keys `s1AudienceExtension` through `s10MonitoringPlan` in v1.0.0-preview; v1.1 can add first-class mirrors without changing the preview payload contract.
- Reviewer outcomes, overrides, and rationale are captured in `fsi_intakereview`; sponsor approval remains in `fsi_intakeapproval` and `fsi_intakedecisionlog`.
- Monitoring, retention, and route decisions should also populate computed fields such as `fsi_pathused`, `fsi_zone`, `fsi_risktier`, reviewer-required flags, retention metadata, and downstream handoff references.
