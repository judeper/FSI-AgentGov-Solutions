# Agent Intake — Dataverse Schema

> Auto-generated from `scripts/create_fsi_intake_dataverse_schema.py`. Do not hand-edit.
> Regenerate with: `python scripts/create_fsi_intake_dataverse_schema.py --output-docs docs/dataverse-schema.md`

## Naming convention

Dataverse uses two names for every column:

- **SchemaName** (PascalCase with prefix): `fsi_RequestId`, `fsi_AgentDisplayName`
- **Logical name** (lowercase, no underscores between words): `fsi_requestid`, `fsi_agentdisplayname`

**In OData queries, scripts, and flow expressions, ALWAYS use the logical name.**

## Tables

### `fsi_intakerequest` — Intake Request

- **Schema name:** `fsi_IntakeRequest`
- **Entity set name (OData):** `fsi_intakerequests`
- **Ownership:** UserOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Maker-submitted request to build an AI agent across Express, Standard, and Full paths

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_requestid` | `fsi_RequestId` | String(100) | Yes | Globally unique intake request identifier (GUID) |
| `fsi_appealofid` | `fsi_AppealOfId` | String(100) | No | Original intake request that this request is appealing |
| `fsi_agentdisplayname` | `fsi_AgentDisplayName` | String(200) | Yes | Maker-provided name for the proposed agent |
| `fsi_agenttype` | `fsi_AgentType` | Choice (fsi_intake_agenttype) | Yes | Authoring tool / runtime type the maker intends to use |
| `fsi_businessoutcome` | `fsi_BusinessOutcome` | String(500) | Yes | Structured business outcome category (BJ-001 dropdown value) |
| `fsi_businessjustification` | `fsi_BusinessJustification` | Memo(4000) | No | Optional free-text business context (BJ-002, optional) |
| `fsi_makerupn` | `fsi_MakerUpn` | String(200) | Yes | Maker user principal name |
| `fsi_makerdepartment` | `fsi_MakerDepartment` | String(200) | No | Pre-filled from Microsoft Graph /me |
| `fsi_makercountry` | `fsi_MakerCountry` | String(100) | No | Pre-filled from Microsoft Graph /me (usageLocation) |
| `fsi_makerdisplayname` | `fsi_MakerDisplayName` | String(200) | No | Pre-filled from Microsoft Graph /me displayName |
| `fsi_makerjobtitle` | `fsi_MakerJobTitle` | String(200) | No | Pre-filled from Microsoft Graph /me jobTitle |
| `fsi_sponsorupn` | `fsi_SponsorUpn` | String(200) | Yes | Sponsor user principal name (pre-filled from /me/manager when available) |
| `fsi_intendedaudience` | `fsi_IntendedAudience` | String(100) | Yes | Maker-selected audience: Just me, My team, My department, Anyone in the firm, External users |
| `fsi_t1initiatesfinancialtxn` | `fsi_T1InitiatesFinancialTxn` | String(20) | Yes | Trigger answer: Yes, No, or Not sure |
| `fsi_t2customerfacing` | `fsi_T2CustomerFacing` | String(20) | Yes | Trigger answer: Yes, No, or Not sure |
| `fsi_t3autonomousunmonitored` | `fsi_T3AutonomousUnmonitored` | String(20) | Yes | Trigger answer: Yes, No, or Not sure |
| `fsi_t4handlesnpi` | `fsi_T4HandlesNpi` | String(20) | Yes | Trigger answer: Yes, No, or Not sure |
| `fsi_t5handlesmnpi` | `fsi_T5HandlesMnpi` | String(20) | Yes | Trigger answer: Yes, No, or Not sure |
| `fsi_t6crossborderdata` | `fsi_T6CrossborderData` | String(20) | Yes | Trigger answer: Yes, No, or Not sure |
| `fsi_makerattestation` | `fsi_MakerAttestation` | Boolean | Yes | Maker acknowledged the acceptable-use and accuracy attestation before submission |
| `fsi_pathused` | `fsi_PathUsed` | Choice (fsi_intake_pathused) | Yes | Express / Standard / Full — set by routing rules |
| `fsi_routingtopology` | `fsi_RoutingTopology` | Choice (fsi_intake_routingtopology) | No | Sequential / Parallel / Quorum topology selected by routing rules |
| `fsi_risktier` | `fsi_RiskTier` | Choice (fsi_intake_risktier) | Yes | Tier 1 / 2 / 3 per SR 11-7 mapping; computed from trigger Qs |
| `fsi_zone` | `fsi_Zone` | Choice (fsi_acv_zone) | Yes | Zone classification selected by policy and routing rules |
| `fsi_dataclassification` | `fsi_DataClassification` | Choice (fsi_intake_dataclassification) | Yes | Highest sensitivity of declared data sources used for intake routing |
| `fsi_status` | `fsi_Status` | Choice (fsi_intake_status) | Yes | Lifecycle status of the intake request |
| `fsi_targetenvironmentid` | `fsi_TargetEnvironmentId` | String(100) | No | Power Platform environment recommended/selected for the agent |
| `fsi_targetenvironmentname` | `fsi_TargetEnvironmentName` | String(200) | No | Display name of the recommended/selected environment |
| `fsi_environmentmanaged` | `fsi_EnvironmentManaged` | Boolean | Yes | True when PPAC reports a Managed Environment protection level |
| `fsi_dlppolicyoutcome` | `fsi_DlpPolicyOutcome` | String(100) | No | Result from the Power Platform data policy simulation |
| `fsi_decisionpath` | `fsi_DecisionPath` | String(100) | No | Express, Standard, Full, DeferredOutOfScope, or DefaultDeny computed by routing rules |
| `fsi_triggerhitcount` | `fsi_TriggerHitCount` | Integer | No | Count of trigger answers equal to Yes or Not sure |
| `fsi_quorumrequired` | `fsi_QuorumRequired` | Integer | No | Minimum reviewer approvals required before the request can advance |
| `fsi_nonmrmquorummet` | `fsi_NonMrmQuorumMet` | Boolean | Yes | TRUE when the non-MRM reviewer board (InfoSec/Privacy/Compliance/Legal) has reached quorum on a Tier-1 Full request; gates Flow 7 (MRM handoff) |
| `fsi_parallelreviewersjson` | `fsi_ParallelReviewersJson` | Memo(65536) | No | JSON array of reviewer role, UPN, due date, weight, and state for routed reviewers |
| `fsi_dataresidencycountry` | `fsi_DataResidencyCountry` | String(100) | No | Maker-declared or detected residency for data sources |
| `fsi_retentionyears` | `fsi_RetentionYears` | Integer | No | Effective retention period in years |
| `fsi_immutablestorage` | `fsi_ImmutableStorage` | Boolean | Yes | True when the decision pack is stamped with the WORM retention label |
| `fsi_privacyoverride` | `fsi_PrivacyOverride` | Boolean | Yes | Set only by Privacy to override the cross-border default-deny rule |
| `fsi_mrmrequired` | `fsi_MrmRequired` | Boolean | Yes | True when policy requires model-risk-management-automation handoff evidence |
| `fsi_mrmhandoffstatus` | `fsi_MrmHandoffStatus` | Choice (fsi_intake_mrmhandoffstatus) | No | Pending / Handed off / NotApplicable / Failed for the MRM handoff |
| `fsi_declareddatasourcesjson` | `fsi_DeclaredDataSourcesJson` | Memo(65536) | No | JSON snapshot of maker-declared data sources/connectors for drift comparison |
| `fsi_standardfullquestionsjson` | `fsi_StandardFullQuestionsJson` | Memo(65536) | No | JSON snapshot of the extended Standard and Full path question responses |
| `fsi_entraagentid` | `fsi_EntraAgentId` | String(100) | No | Microsoft Entra Agent ID service principal ID minted at handoff |
| `fsi_registryrecordid` | `fsi_RegistryRecordId` | String(100) | No | ID of the corresponding agent-registry-automation record after handoff |
| `fsi_submittedon` | `fsi_SubmittedOn` | DateTime | No | Timestamp the request was submitted (set on transition Draft to Submitted) |
| `fsi_decidedon` | `fsi_DecidedOn` | DateTime | No | Timestamp of final decision |
| `fsi_policyversionapplied` | `fsi_PolicyVersionApplied` | String(50) | Yes | Version of policy-lookup-tables.yaml in effect at submission |

### `fsi_intakedatasource` — Intake Data Source

- **Schema name:** `fsi_IntakeDataSource`
- **Entity set name (OData):** `fsi_intakedatasources`
- **Ownership:** UserOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Per-data-source declaration on an intake request (1..N per parent)

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_requestid` | `fsi_RequestId` | String(100) | Yes | FK to fsi_IntakeRequest.fsi_RequestId |
| `fsi_datasourcename` | `fsi_DataSourceName` | String(500) | Yes | Maker-declared data source identifier (e.g., SharePoint site URL, table name) |
| `fsi_datasourcetype` | `fsi_DataSourceType` | String(200) | Yes | Connector type (e.g., SharePoint, Dataverse, Outlook, custom HTTP) |
| `fsi_dataclassification` | `fsi_DataClassification` | Choice (fsi_intake_dataclassification) | Yes | Sensitivity declared for this source (Express: maker-declared) |
| `fsi_iscustomerdata` | `fsi_IsCustomerData` | Boolean | Yes | Does this source contain customer NPI? (Trigger T1 input) |
| `fsi_isrestricted` | `fsi_IsRestricted` | Boolean | Yes | Is this source restricted under MNPI / insider trading controls? (Trigger T2 input) |

### `fsi_intakerisksignal` — Intake Risk Signal

- **Schema name:** `fsi_IntakeRiskSignal`
- **Entity set name (OData):** `fsi_intakerisksignals`
- **Ownership:** UserOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Per-trigger-question outcome and any derived risk signals

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_requestid` | `fsi_RequestId` | String(100) | Yes | FK to fsi_IntakeRequest.fsi_RequestId |
| `fsi_triggercode` | `fsi_TriggerCode` | String(50) | Yes | T1..T7 trigger question identifier |
| `fsi_triggeranswer` | `fsi_TriggerAnswer` | String(20) | Yes | Maker's answer: Yes, No, or Not sure |
| `fsi_derivedsignal` | `fsi_DerivedSignal` | String(200) | No | Any computed signal raised by the answer (e.g., 'CustomerFacing', 'MNPI') |
| `fsi_capturedon` | `fsi_CapturedOn` | DateTime | Yes | Timestamp the signal was captured at intake |

### `fsi_intakereview` — Intake Review

- **Schema name:** `fsi_IntakeReview`
- **Entity set name (OData):** `fsi_intakereviews`
- **Ownership:** UserOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Reviewer activity (sample audit on Express; Standard/Full and MRM reviewer outcomes)

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_requestid` | `fsi_RequestId` | String(100) | Yes | FK to fsi_IntakeRequest.fsi_RequestId |
| `fsi_reviewerrole` | `fsi_ReviewerRole` | Choice (fsi_intake_reviewerrole) | Yes | InfoSec / Privacy / Compliance / Legal / MRM / Sponsor |
| `fsi_reviewerupn` | `fsi_ReviewerUpn` | String(200) | Yes | Reviewer user principal name |
| `fsi_reviewtype` | `fsi_ReviewType` | String(100) | Yes | SampleAudit / Standard / Full |
| `fsi_reviewoutcome` | `fsi_ReviewOutcome` | Choice (fsi_intake_reviewdecision) | No | Pending / Approved / Approved with conditions / Denied / Recused / Timeout |
| `fsi_reviewnotes` | `fsi_ReviewNotes` | Memo(4000) | No | Reviewer notes (optional) |
| `fsi_quorumweight` | `fsi_QuorumWeight` | Integer | No | Weight contributed by this reviewer toward quorum calculations |
| `fsi_dueon` | `fsi_DueOn` | DateTime | No | Date/time when the reviewer response is due under policy |
| `fsi_conditionstext` | `fsi_ConditionsText` | Memo(4000) | No | Reviewer conditions recorded when the decision is Approved with conditions |
| `fsi_startedon` | `fsi_StartedOn` | DateTime | No | Timestamp review started |
| `fsi_completedon` | `fsi_CompletedOn` | DateTime | No | Timestamp review completed |

### `fsi_intakeapproval` — Intake Approval

- **Schema name:** `fsi_IntakeApproval`
- **Entity set name (OData):** `fsi_intakeapprovals`
- **Ownership:** UserOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Per-approver decision (sponsor + sequential or parallel approvers)

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_requestid` | `fsi_RequestId` | String(100) | Yes | FK to fsi_IntakeRequest.fsi_RequestId |
| `fsi_approverrole` | `fsi_ApproverRole` | Choice (fsi_intake_reviewerrole) | Yes | Sponsor / InfoSec / Privacy / Compliance / Legal / MRM / Sponsor Manager |
| `fsi_approverupn` | `fsi_ApproverUpn` | String(200) | Yes | Approver user principal name |
| `fsi_decisionoutcome` | `fsi_DecisionOutcome` | Choice (fsi_intake_decisionoutcome) | Yes | Approved / AutoApproved / Denied / EscalatedToManager / WithdrawnByMaker |
| `fsi_decidedon` | `fsi_DecidedOn` | DateTime | Yes | Timestamp the approver clicked |
| `fsi_decisionmethod` | `fsi_DecisionMethod` | String(100) | Yes | TeamsAdaptiveCard / Portal / Email / API |
| `fsi_decisioncontexthash` | `fsi_DecisionContextHash` | String(200) | No | SHA-256 of the rendered decision context shown to the approver (tamper evidence) |
| `fsi_clientipaddress` | `fsi_ClientIpAddress` | String(100) | No | Source IP recorded at decision time (supervisory evidence) |
| `fsi_dependsonapprovalid` | `fsi_DependsOnApprovalId` | String(100) | No | Optional predecessor approval row ID used for sequential approval chains |

### `fsi_intakedecisionlog` — Intake Decision Log

- **Schema name:** `fsi_IntakeDecisionLog`
- **Entity set name (OData):** `fsi_intakedecisionlogs`
- **Ownership:** OrganizationOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Immutable decision-pack record (supports compliance with FINRA Rule 4511, SEC Rule 17a-4, CFTC Rule 1.31)

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_requestid` | `fsi_RequestId` | String(100) | Yes | FK to fsi_IntakeRequest.fsi_RequestId |
| `fsi_decisionoutcome` | `fsi_DecisionOutcome` | Choice (fsi_intake_decisionoutcome) | Yes | Final outcome of the request |
| `fsi_risktier` | `fsi_RiskTier` | Choice (fsi_intake_risktier) | Yes | Tier captured at decision time |
| `fsi_zone` | `fsi_Zone` | Choice (fsi_acv_zone) | Yes | Zone captured at decision time |
| `fsi_pathused` | `fsi_PathUsed` | Choice (fsi_intake_pathused) | Yes | Express / Standard / Full path used |
| `fsi_policyversionapplied` | `fsi_PolicyVersionApplied` | String(50) | Yes | Version of policy-lookup-tables.yaml at decision time |
| `fsi_decisionpackjson` | `fsi_DecisionPackJson` | Memo(1048576) | No | Full decision pack as JSON (all 137 catalog field values, computed and declared) |
| `fsi_decisionpackhash` | `fsi_DecisionPackHash` | String(200) | Yes | SHA-256 of fsi_DecisionPackJson for tamper evidence |
| `fsi_decidedon` | `fsi_DecidedOn` | DateTime | Yes | Timestamp of final decision |
| `fsi_retentionlabelapplied` | `fsi_RetentionLabelApplied` | String(200) | Yes | Purview retention label stamped (FSI-AgentIntake-7yr or override) |
| `fsi_retentionlabelappliedon` | `fsi_RetentionLabelAppliedOn` | DateTime | Yes | Timestamp the retention label was stamped |

### `fsi_intakesponsorship` — Intake Sponsorship

- **Schema name:** `fsi_IntakeSponsorship`
- **Entity set name (OData):** `fsi_intakesponsorships`
- **Ownership:** UserOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Sponsor attestation evidence (supports FINRA Rule 3110 supervision)

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_requestid` | `fsi_RequestId` | String(100) | Yes | FK to fsi_IntakeRequest.fsi_RequestId |
| `fsi_sponsorupn` | `fsi_SponsorUpn` | String(200) | Yes | Sponsor user principal name |
| `fsi_sponsorrole` | `fsi_SponsorRole` | String(200) | Yes | LineOfBusinessSponsor / RegisteredPrincipal / DataOwner |
| `fsi_attestationtext` | `fsi_AttestationText` | Memo(4000) | No | Verbatim attestation language presented to the sponsor (FINRA Rule 3110) |
| `fsi_attestedon` | `fsi_AttestedOn` | DateTime | No | Timestamp the sponsor attested |
| `fsi_attestationmethod` | `fsi_AttestationMethod` | String(100) | Yes | TeamsAdaptiveCard / Portal / Email |
| `fsi_renderedcardhash` | `fsi_RenderedCardHash` | String(200) | No | SHA-256 of the exact card content shown — tamper evidence |
| `fsi_isvalid` | `fsi_IsValid` | Boolean | Yes | False if sponsor attestation has been revoked |

### `fsi_intakeauditevent` — Intake Audit Event

- **Schema name:** `fsi_IntakeAuditEvent`
- **Entity set name (OData):** `fsi_intakeauditevents`
- **Ownership:** OrganizationOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Lifecycle event audit trail with path-phase checkpoints

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_requestid` | `fsi_RequestId` | String(100) | Yes | FK to fsi_IntakeRequest.fsi_RequestId |
| `fsi_eventtype` | `fsi_EventType` | String(100) | Yes | Lifecycle event name emitted by intake flows. Bundled values are catalogued in the fsi_intake_auditeventtype option set, but this column remains text so customers can extend the inventory without a schema change. |
| `fsi_pathphase` | `fsi_PathPhase` | String(100) | No | Submitted / RouterRouted / SponsorAttested / ReviewerQueued / ReviewerDecided / Escalated / Handed off |
| `fsi_actorupn` | `fsi_ActorUpn` | String(200) | No | UPN of the actor who triggered the event (system events use 'system') |
| `fsi_eventon` | `fsi_EventOn` | DateTime | Yes | Timestamp the event occurred |
| `fsi_eventpayloadjson` | `fsi_EventPayloadJson` | Memo(65536) | No | Optional JSON payload for the event (pre-state, post-state, error details) |

### `fsi_intakeretentionrecord` — Intake Retention Record

- **Schema name:** `fsi_IntakeRetentionRecord`
- **Entity set name (OData):** `fsi_intakeretentionrecords`
- **Ownership:** OrganizationOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Retention-label stamping evidence per intake decision

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_requestid` | `fsi_RequestId` | String(100) | Yes | FK to fsi_IntakeRequest.fsi_RequestId |
| `fsi_labelname` | `fsi_LabelName` | String(200) | Yes | Purview retention label name (e.g., FSI-AgentIntake-7yr) |
| `fsi_retentionyears` | `fsi_RetentionYears` | Integer | Yes | Effective retention in years |
| `fsi_stampedon` | `fsi_StampedOn` | DateTime | Yes | Timestamp the label was applied |
| `fsi_stampedby` | `fsi_StampedBy` | String(200) | Yes | System / managed-identity that stamped the label |
| `fsi_regulatorybasis` | `fsi_RegulatoryBasis` | String(500) | Yes | Comma-separated list (e.g., 'SEC 17a-4, FINRA 4511, CFTC 1.31') |

## Option Sets

All option sets are global (cross-table) so the same numeric value can be used in OData filters across tables.

### `fsi_acv_zone`

| Label | Value |
|-------|-------|
| Unclassified | 100000000 |
| Zone 1 (Enterprise) | 100000001 |
| Zone 2 (Team) | 100000002 |
| Zone 3 (Personal) | 100000003 |

### `fsi_intake_pathused`

| Label | Value |
|-------|-------|
| Express | 100000000 |
| Standard | 100000001 |
| Full | 100000002 |

### `fsi_intake_status`

| Label | Value |
|-------|-------|
| Draft | 100000000 |
| Submitted | 100000001 |
| AwaitingSponsor | 100000002 |
| AwaitingReviewers | 100000003 |
| Approved | 100000004 |
| Denied | 100000005 |
| Withdrawn | 100000006 |
| Escalated | 100000007 |
| AutoApproved | 100000008 |
| DeferredOutOfScope | 100000009 |
| SponsorTimeout | 100000010 |
| InReview | 100000011 |
| LiveTracking | 100000012 |

### `fsi_intake_routingtopology`

| Label | Value |
|-------|-------|
| Sequential | 100000000 |
| Parallel | 100000001 |
| Quorum | 100000002 |

### `fsi_intake_risktier`

| Label | Value |
|-------|-------|
| Tier 1 (High) | 100000000 |
| Tier 2 (Medium) | 100000001 |
| Tier 3 (Low) | 100000002 |

### `fsi_intake_agenttype`

| Label | Value |
|-------|-------|
| Agent Builder (M365 Copilot) | 100000000 |
| Copilot Studio (classic) | 100000001 |
| Declarative Agent (M365 Copilot) | 100000002 |
| Custom Engine Agent | 100000003 |
| Azure AI Foundry / Pro-Dev | 100000004 |

### `fsi_intake_dataclassification`

| Label | Value |
|-------|-------|
| Public | 100000000 |
| Internal | 100000001 |
| Confidential | 100000002 |
| Restricted | 100000003 |

### `fsi_intake_reviewerrole`

| Label | Value |
|-------|-------|
| InfoSec | 100000000 |
| Privacy | 100000001 |
| Compliance | 100000002 |
| Legal | 100000003 |
| MRM | 100000004 |
| Sponsor | 100000005 |
| Sponsor Manager | 100000006 |

### `fsi_intake_reviewdecision`

| Label | Value |
|-------|-------|
| Pending | 100000000 |
| Approved | 100000001 |
| Approved with conditions | 100000002 |
| Denied | 100000003 |
| Recused | 100000004 |
| Timeout | 100000005 |

### `fsi_intake_mrmhandoffstatus`

| Label | Value |
|-------|-------|
| Pending | 100000000 |
| Handed off | 100000001 |
| NotApplicable | 100000002 |
| Failed | 100000003 |

### `fsi_intake_decisionoutcome`

| Label | Value |
|-------|-------|
| Approved | 100000000 |
| AutoApproved | 100000001 |
| Denied | 100000002 |
| EscalatedToManager | 100000003 |
| WithdrawnByMaker | 100000004 |

### `fsi_intake_auditeventtype`

| Label | Value |
|-------|-------|
| RouterDecided | 100000000 |
| RouterFailed | 100000001 |
| SponsorDecided | 100000002 |
| SponsorTimeout | 100000003 |
| SponsorEscalated | 100000004 |
| SponsorCardFailed | 100000005 |
| ReviewerQueued | 100000006 |
| ReviewerQueueFailed | 100000007 |
| ReviewerDecided | 100000008 |
| QuorumReached | 100000009 |
| RequestDenied | 100000010 |
| ReviewerDecisionHandlerFailed | 100000011 |
| ReviewerEscalated | 100000012 |
| ReviewerEscalationFailed | 100000013 |
| MrmHandoffSubmitted | 100000014 |
| MRMHandoffPending | 100000015 |
| MrmDecisionMirrored | 100000016 |
| DecisionPackWritten | 100000017 |
| EntraAgentIdMinted | 100000018 |
| RegistryHandoffComplete | 100000019 |
| DriftHandoffSubmitted | 100000020 |
| AppealSubmitted | 100000021 |
| AppealRejected | 100000022 |
| AppealCreateFailed | 100000023 |
| RetentionLabelApplied | 100000024 |

## Alternate Keys

- `fsi_intakerequest` — schema name `fsi_RequestIdUniqueKey` (logical: `fsi_requestiduniquekey`); key columns: `fsi_requestid`

Use this alternate key for upsert-by-business-key:

```
PATCH /api/data/v9.2/fsi_intakerequests(fsi_requestid='<request-guid>')
```

## Relationships

All child tables (`fsi_intakedatasource`, `fsi_intakerisksignal`, `fsi_intakereview`, `fsi_intakeapproval`, `fsi_intakedecisionlog`, `fsi_intakesponsorship`, `fsi_intakeauditevent`, `fsi_intakeretentionrecord`) carry an `fsi_requestid` string column that references the parent `fsi_intakerequest.fsi_requestid`. This is intentionally a **soft FK** (not a Dataverse lookup) so that the immutable `fsi_intakedecisionlog` records survive deletion of the parent request — required for FINRA 4511 / SEC 17a-4 evidence retention.

Reviewer-board state for Standard and Full requests is intentionally stored in `fsi_intakerequest.fsi_parallelreviewersjson` in v1.0-preview to keep the schema small; a dedicated reviewer-assignment table is deferred until the reviewer app needs Dataverse sub-grid views.
