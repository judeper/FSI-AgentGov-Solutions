# Intake questions — Full path

> Path: Full  
> Target: Tier 1 / Zone 1 requests  
> Approver topology: Sponsor + 5-reviewer parallel  
> Target completion time: 2-4 weeks

## Path summary

The Full path is the enterprise and high-risk route for agents with customer-facing exposure, MNPI or NPI handling, cross-border movement, autonomous action, financial authority, or other characteristics that require the broadest reviewer pack. It preserves the same intake evidence foundation as Express and Standard, then adds the questions needed for enterprise-scale supervision, privacy, legal, model-risk, resilience, and records review.

The default reviewer pack is Sponsor plus five parallel reviewer roles: InfoSec, Privacy, Compliance, Legal, and MRM. The default quorum is three of five plus Sponsor, but Tier-1 requests keep MRM as a non-waivable reviewer under firm policy, and Records, Procurement, or IT Operations can become mandatory when the questions below trigger them. All wording and defaults assume commercial Microsoft 365 and en-US maker-facing text. The catalog supports evidence collection for OCC Bulletin 2026-13 firm-level governance, SR 11-7-style tiering where the firm applies it, FINRA Rule 3110 supervision, FINRA Rule 4511 and SEC Rules 17a-3 and 17a-4 recordkeeping, CFTC Rule 1.31 retention, GLBA 501(b) safeguards, and optional NY DFS 23 NYCRR 500 §500.11 review; it does not certify compliance.

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
| B3 | `fsi_businessjustification` | In one or two sentences, what will it do? | Multiline text 50-500 | Yes | Informational only — reviewers use this baseline narrative when deciding whether the enterprise control set is proportional and complete. | 2.12, 2.13, 3.1 |
| B4 | `fsi_agenttype` | What type of agent will you build? | Choice (`fsi_intake_agenttype`) | Yes | Informational only — helps determine environment fit, routing notes, and downstream handoff detail. | 1.2, 2.1, 3.1 |
| B5 | `fsi_intendedaudience` | Who will use it? | Choice: Just me / My team / My department / Anyone in the firm / External users | Yes | Gating — `Anyone in the firm` or `External users` typically keep the request on Full; narrower audiences can still remain on Full when other high-risk triggers fire. | 1.18, 2.1, 3.1 |

## Section C — Risk triggers & residency

| # | Field (Dataverse logical name) | Question shown to maker | Type | Required | Routing impact | Control mapping |
|---|---|---|---|---|---|---|
| C1 | `fsi_t1initiatesfinancialtxn` | Will it initiate financial transactions or move money? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` keeps the request on Full and makes MRM, Compliance, and InfoSec mandatory. | 2.5, 2.12, 2.13 |
| C2 | `fsi_t2customerfacing` | Will it interact directly with customers or external parties? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` keeps the request on Full and makes Compliance mandatory. | 1.7, 2.12, 2.13 |
| C3 | `fsi_t3autonomousunmonitored` | Can it act without a human reviewing each action? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` keeps the request on Full and increases required control and kill-switch evidence. | 2.12, 2.13, 2.24 |
| C4 | `fsi_t4handlesnpi` | Will it process customer nonpublic personal information (NPI)? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` keeps the request on Full and makes Privacy mandatory. | 1.5, 1.14, 2.13 |
| C5 | `fsi_t5handlesmnpi` | Will it process material nonpublic information (MNPI) or information-barrier data? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` keeps the request on Full and makes Compliance and Legal mandatory. | 1.22, 2.12, 2.13 |
| C6 | `fsi_t6crossborderdata` | Will data cross country or regional residency boundaries? | Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` keeps the request on Full and applies ADR-005 default-deny handling until Privacy approves an override. | 1.14, 2.12, 2.13 |
| C7 | `fsi_dataresidencycountry` | Where is the data expected to reside? | Country/region text or choice | Yes if C6 is not `No` | Gating when C6 is not `No` — if the maker country and declared residency differ, the router applies ADR-005 default-deny pending Privacy override. | 1.14, 2.1, 2.13 |

## Section D — Team scope, integrations, and data handling

> Note: Fields prefixed `fsi_s` and `fsi_f` below are proposed logical names; schema columns are added in the foundation-schema workstream.

| # | Field (Dataverse logical name) | Question shown to maker | Type | Required | Routing impact | Control mapping |
|---|---|---|---|---|---|---|
| D1 | `fsi_s1audienceextension` | Which teams or named Microsoft 365 groups will receive this agent, and about how many users do you expect in the first 90 days? | Composite: group picker + integer band | Yes | Gating — unresolved group scope, external guests, or very broad distribution keep the request on Full and may add Legal or Records review. | 1.2, 1.18, 2.1, 3.1 |
| D2 | `fsi_s2connectorinventory` | Which Power Platform connectors, Graph scopes, or external endpoints will the agent use? | Multiselect + free text | Yes | Gating — premium/custom connectors or write/send-external endpoints keep InfoSec mandatory; any financial-action endpoint confirms Tier-1 handling. | 1.4, 1.5, 1.14, 2.13 |
| D3 | `fsi_s3datasources` | List the SharePoint sites, Dataverse tables, mailboxes, or other data sources the agent will read from. | Multirow text or linked records | Yes | Gating — missing source names blocks approval; regulated, privileged, or out-of-tenant sources keep Privacy, Compliance, or Legal mandatory. | 1.14, 2.13, 2.16, 4.8 |
| D4 | `fsi_s4outputdestinations` | Where can the agent send or post outputs? | Multiselect: Teams / email / SharePoint / Dataverse / CRM / other | Yes | Gating — customer-directed, public-channel, or broad email distribution keeps Compliance and Records mandatory. | 1.7, 1.18, 2.12, 2.13 |
| D5 | `fsi_s5outputclassification` | What sensitivity label and retention class should reviewers assume for typical outputs? | Composite: sensitivity choice + retention choice | Yes | Gating — Confidential or Restricted output, custom retention, or likely WORM scope keeps Privacy or Records mandatory. | 1.5, 1.7, 2.13, 4.3 |
| D6 | `fsi_s6makertrainingack` | Have you completed the firm's AI maker training for team-scope agents? | Choice: Completed / In progress / Not yet taken | Yes | Gating — `In progress` or `Not yet taken` pauses the request until training is complete or waived by policy. | 2.14, 3.1 |
| D7 | `fsi_s7deploymentpattern` | Will this agent be promoted across dev/test/prod environments, and will it use Power Fx, custom actions, or custom skills? | Composite: environment choice + Yes/No + short text | Yes | Gating — production promotion requires Managed Environment and change-management checks; custom logic keeps InfoSec mandatory. | 2.1, 2.3, 2.15, 2.24 |
| D8 | `fsi_s8agentrouting` | Will this agent call other agents or allow other agents to call it? | Yes / No + linked agent IDs if `Yes` | Yes | Gating — `Yes` keeps InfoSec mandatory and may add architecture review under multi-agent orchestration limits. | 1.18, 2.17, 2.13 |
| D9 | `fsi_s9sponsorbackupupn` | Who is the backup business sponsor or successor approver if the primary sponsor is unavailable? | UPN picker | Yes | Gating — blank, external, or maker-matches-sponsor values block submission until a valid successor is named. | 2.12, 2.13, 3.1 |
| D10 | `fsi_s10monitoringplan` | What monthly invocation volume do you expect, and how will you sample or monitor outputs after go-live? | Composite: volume band + sampling/monitoring plan | Yes | Gating — high volume, no monitoring plan, or no sampling rate keeps InfoSec and Compliance mandatory. | 1.7, 2.9, 3.2, 3.10 |

## Section E — Enterprise, legal, and model-risk specifics

> Note: Fields prefixed `fsi_f` below are proposed logical names; schema columns are added in the foundation-schema workstream.

| # | Field (Dataverse logical name) | Question shown to maker | Type | Required | Routing impact | Control mapping |
|---|---|---|---|---|---|---|
| E1 | `fsi_f1externalexposure` | Will any customer, prospect, counterparty, regulator, or other external party directly receive the agent's output, and is any part of that output a recordable business communication? | Composite: exposure choice + Yes/No | Yes | Gating — `Yes` makes Compliance and Records mandatory and keeps the request on Full. | 1.7, 2.12, 2.13, 2.19 |
| E2 | `fsi_f2mnpibarrierdata` | Will the agent access MNPI, research under information barriers, or other restricted dealing data? | Choice: Yes / No / Not sure | Yes | Gating — `Yes` or `Not sure` makes Compliance and Legal mandatory; unsupported information-barrier use cases may be denied. | 1.22, 2.12, 2.13 |
| E3 | `fsi_f3npiprivacyimpact` | Describe any NPI, sensitive personal data, privileged material, or legal-hold/eDiscovery content the agent will handle, and whether a DPIA or privacy impact assessment is required. | Composite: multiline text + choice | Yes | Gating — NPI, privileged data, or `DPIA required` makes Privacy mandatory and keeps approval pending until the assessment is complete. | 1.5, 1.14, 1.19, 2.13 |
| E4 | `fsi_f4crossborderassessment` | Will prompts, outputs, logs, or supporting data cross US borders at any point? If yes, which jurisdictions are involved and what lawful basis or contractual mechanism applies? | Yes / No + jurisdiction list + short text | Yes | Gating — `Yes` or `Not sure` applies ADR-005 default-deny until Privacy and Legal approve the transfer basis. | 1.14, 2.12, 2.13 |
| E5 | `fsi_f5autonomylevel` | What autonomy level (0-5) best describes this agent, and which actions require human-in-the-loop approval? | Composite: level choice + multiselect | Yes | Gating — higher autonomy levels or missing HITL coverage keep the request on Full and can block approval until control design is updated. | 1.23, 2.12, 2.13, 2.24 |
| E6 | `fsi_f6financialauthority` | Can the agent move money, place or change orders, adjust positions or limits, or write to a regulated system of record? | Multiselect | Yes | Gating — any affirmative answer makes MRM, Compliance, and InfoSec mandatory and confirms Tier-1 handling. | 2.5, 2.6, 2.8, 2.12, 2.13 |
| E7 | `fsi_f7modelriskpackage` | What firm model-risk tier applies, and what validation evidence already exists (validation report, benchmark results, drift-test plan, owner)? | Composite: tier choice + document references | Yes | Gating — missing validation evidence keeps MRM approval pending; Tier-1 makes MRM non-waivable under firm policy. | 2.5, 2.6, 2.13, 3.1 |
| E8 | `fsi_f8fairnessexplainability` | What bias or fairness checks, explainability standards, and inspection rights must be met before go-live? | Composite: multiselect + short text | Yes | Gating — customer-affecting or regulated decisions without test and inspection plans remain on hold. | 2.5, 2.11, 2.13 |
| E9 | `fsi_f9reviewerassuranceplan` | Which reviewer attestations, independent test steps, and champion/challenger or pre-production comparison activities are required before release? | Composite: multiselect | Yes | Gating — independent testing is mandatory for Tier-1; named reviewers become mandatory approvers in the parallel pack. | 2.5, 2.6, 2.12, 2.13 |
| E10 | `fsi_f10shutdownandresilience` | What shutdown criteria, kill-switch owner, and BCM/DR classification apply if the agent must be suspended or recovered quickly? | Composite: multiselect + short text | Yes | Gating — missing kill-switch or recovery ownership blocks approval and may add IT Operations review. | 2.4, 2.9, 2.13, 3.4 |
| E11 | `fsi_f11vendorandliability` | Which third-party model or vendor supports this agent, what liability or insurance class applies, and does NY DFS 23 NYCRR 500 §500.11 review trigger for your firm? | Composite: choice + short text | Yes | Gating — non-Microsoft or third-party vendor use makes Legal and Procurement mandatory; NY DFS trigger adds the optional T7 review path where enabled. | 2.7, 2.13, 2.24 |
| E12 | `fsi_f12observabilityincidentresponse` | What logging and observability plan, and which incident response playbook reference, apply if the agent misbehaves? | Composite: short text + link/reference | Yes | Gating — missing log destination or playbook reference blocks approval and adds SOC or Compliance follow-up. | 1.7, 2.9, 2.13, 3.2, 3.4 |
| E13 | `fsi_f13regulatornotificationplan` | If this agent causes a material incident, which regulator-notification or customer-notification thresholds apply? | Choice + short text | Yes | Gating — unclear notification obligations keep Compliance and Legal mandatory before go-live. | 1.7, 2.12, 2.13, 3.4 |

## Customer override notes

Customers can split any composite Full-path prompt into multiple UI controls if needed, but they should preserve the canonical logical names and routing semantics above so the reviewer app, classification engine, and flow docs stay aligned. Reviewer quorum, MRM committee naming, NY DFS enablement, label taxonomies, lawful-basis templates, and vendor-risk criteria should be adjusted in configuration rather than by forking the baseline catalog.

The preferred schema pattern is to add the `fsi_s1`-`fsi_s10` and `fsi_f1`-`fsi_f13` fields directly on `fsi_intakerequest`, then mirror those values into `fsi_decisionpackjson` for immutable retention. If a customer needs more granular storage than the composite prompts provide, the downstream schema workstream can add linked tables or helper columns while keeping the canonical question text and routing impacts intact.

## Acceptance evidence collected

- All Express and Standard-path evidence plus the enterprise-scale review inputs needed for Full-path approval.
- Proposed `fsi_s1`-`fsi_s10` and `fsi_f1`-`fsi_f13` values should land in first-class intake columns once the schema workstream ships; until then they can be serialized into `fsi_decisionpackjson` with the same labels.
- Parallel reviewer approvals, overrides, rationale, and required-attestation outcomes are captured in `fsi_intakereview`; sponsor approval remains in `fsi_intakeapproval` and `fsi_intakedecisionlog`.
- Model-risk evidence, privacy assessments, lawful-basis notes, playbook references, and resilience decisions should also flow into the immutable decision pack so auditors can reconstruct the exact approval basis later.
