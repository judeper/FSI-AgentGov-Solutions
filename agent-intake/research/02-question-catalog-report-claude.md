# FSI AI Agent Governance — Intake Question Catalog (Claude, full)

**Source:** Claude Sonnet 4.6 Thinking, 4 parts assembled 2026-04-30

---

## Part 1 — Sections 1-3 (catalog AT through MR-006)

| ID     | Category              | Question Text                                                                                                                                                                                                                                              | Why It Matters                                                                                                                                                                                                                                                                                                                                         | Decisions Driven | Answer Type   | Allowed Values / Validation                                                                                                                                                                                 | Default                              | Required?                                               | Auto-detectable?                                                                                           | Stage                 | Asked of          | Source Citation                                                                     |
| ------ | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------- | ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | --------------------- | ----------------- | ----------------------------------------------------------------------------------- |
| AT-001 | Agent Type            | Does the agent need to take autonomous actions on external systems — for example, sending an email, placing an order, calling an external API, or updating a record — without a human approving each individual action?                                    | Autonomous external action is the single strongest disqualifier for declarative agents (which use the M365 Copilot orchestrator and cannot execute HITL-gated tool calls at runtime). It also drives Tier-1 risk classification and mandatory action-confirmation controls. FINRA 3110 requires supervision of associated-person activities. finra     | 1, 2, 4, 6       | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Microsoft Learn declarative agent overview learn.microsoft; FINRA 3110              |
| AT-002 | Agent Type            | Does the agent need to use a large language model (LLM) other than the Microsoft-hosted models (GPT-4o, Phi, etc.) built into Copilot Studio or M365 Copilot — for example, an Anthropic, Mistral, Meta, or on-premises model?                             | Using a non-Microsoft LLM requires a custom-engine agent or Azure AI Foundry; it triggers third-party model-risk review under firm policy and Procurement/vendor-due-diligence. OCC 2026-13 excludes gen/agentic AI from regulatory MRM but reserves firm-level governance. sullcrom+1                                                                 | 1, 4, 6, 7       | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Microsoft Learn custom-engine agent overview learn.microsoft; OCC 2026-13 occ.treas |
| AT-003 | Agent Type            | What is the primary user interface through which users will interact with this agent?                                                                                                                                                                      | Interface determines which platform is eligible: Agent Builder and declarative agents surface only inside M365 Copilot (Teams, Copilot chat); Copilot Studio classic supports custom channels, voice, and embedded web; Foundry agents support any SDK-built surface. learn.microsoft+1                                                                | 1, 3, 5          | Single-select | M365 Copilot chat / Microsoft Teams / SharePoint / Power Pages / Custom web app / Voice / External customer portal / Other                                                                                  | M365 Copilot chat                    | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Microsoft Learn agent builder learn.microsoft; agents overview learn.microsoft      |
| AT-004 | Agent Type            | Does the agent require custom orchestration logic — for example, routing between multiple specialized agents, branching workflows based on intermediate results, or multi-step reasoning chains that you control?                                          | Custom orchestration is only possible with Copilot Studio custom-engine agents or Azure AI Foundry; declarative agents and Agent Builder use the M365 Copilot Sydney orchestrator with no customization. learn.microsoft+1                                                                                                                             | 1, 2, 4          | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Microsoft Learn custom-engine vs declarative learn.microsoft                        |
| AT-005 | Agent Type            | What is the maker's primary technical background for building and maintaining this agent?                                                                                                                                                                  | Technical depth maps directly to feasible platform options. No-code makers are confined to Agent Builder or Copilot Studio classic; pro-developers need Foundry access and Azure RBAC. This informs Maker Role grant (Decision 7). learn.microsoft                                                                                                     | 1, 7             | Single-select | No-code (no programming) / Low-code (Power Platform/Copilot Studio) / Pro-developer (Python, TypeScript, REST APIs) / Team mix                                                                              | Low-code                             | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Microsoft Learn copilot-studio-experience learn.microsoft                           |
| AT-006 | Agent Type            | Does the agent need to remember information across separate user sessions (persistent memory), or is each conversation self-contained?                                                                                                                     | Persistent memory requires either Copilot Studio with Dataverse storage or Foundry with a vector/relational store; declarative agents and Agent Builder do not support cross-session memory without a connector. This affects environment storage sizing and data-classification scope.                                                                | 1, 3, 8          | Single-select | Self-contained (no cross-session memory) / Persistent memory for the same user / Persistent memory shared across users / Not sure                                                                           | Self-contained                       | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Microsoft Learn declarative agent overview learn.microsoft                          |
| AT-007 | Agent Type            | Does the agent need to invoke other AI agents programmatically (agent-to-agent communication, multi-agent orchestration)?                                                                                                                                  | Agent-to-agent calls can cause a child agent to acquire the orchestrating agent's delegated permissions. This is an emerging attack surface flagged in the Entra Agent ID security advisory (April 2026) and requires explicit scope-delegation review. csoonline+1                                                                                    | 1, 2, 4, 8, 11   | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Entra Agent ID learn.microsoft; security advisory csoonline                         |
| AT-008 | Agent Type            | Does the agent need to handle real-time streaming data or respond to event triggers (e.g., a new trade execution, a compliance alert, an inbound customer message) without a human initiating the conversation?                                            | Event-triggered autonomous agents require Copilot Studio with Power Automate triggers or Azure AI Foundry with event-grid integration; declarative agents and Agent Builder require user-initiated conversations only. learn.microsoft+1                                                                                                               | 1, 2, 4          | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Microsoft Learn custom-engine agent learn.microsoft                                 |
| AT-009 | Agent Type            | What M365 Copilot licensing does the target user population currently hold?                                                                                                                                                                                | Agent Builder and declarative agents require an M365 Copilot license per consuming user. If users lack this license, these platform options are disqualified. This affects cost estimation and environment placement. learn.microsoft                                                                                                                  | 1, 3, 12         | Single-select | All users have M365 Copilot / Some users have M365 Copilot / No users have M365 Copilot / Unknown                                                                                                           | Unknown                              | Always                                                  | Partial — pre-fill from Microsoft Graph /v1.0/users/{id}/licenseDetails learn.microsoft                    | Stage 2 Capture       | Maker             | Microsoft Learn agent builder learn.microsoft                                       |
| AT-010 | Agent Type            | Will the agent be embedded in or accessible to external users (outside the firm's Entra tenant) — for example, customers, counterparties, or regulators?                                                                                                   | External access rules out Agent Builder and standard declarative agents (tenant-scoped only) and triggers cross-tenant sharing governance, GLBA/NYDFS data-sharing controls, and the cross-tenant-external-sharing-governance solution.                                                                                                                | 1, 2, 3, 5, 8    | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Microsoft Learn declarative agent learn.microsoft; CoE governance syskit            |
| CT-001 | Controls              | Will the agent access, display, or reason over data that identifies or could identify a specific customer (name, account number, SSN, email, phone, address)?                                                                                              | Triggers GLBA 501(b) safeguards requirement, NPI classification for all data sources, mandatory sensitivity-label enforcement in Purview, and item-level permission scan on knowledge sources. learn.microsoft+1                                                                                                                                       | 2, 4, 5, 8, 9    | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Purview DSPM-for-AI learn.microsoft; GLBA 501(b)                                    |
| CT-002 | Controls              | Could any information the agent accesses constitute material non-public information (MNPI) — for example, pre-announcement earnings data, pending M&A activity, non-public regulatory correspondence, or unreleased research ratings?                      | MNPI exposure triggers Reg FD controls, information-barrier enforcement, mandatory MNPI-flag sensitivity labeling in Purview, and Compliance/Legal review. No vendor intake template reviewed asked this question directly.                                                                                                                            | 2, 4, 6, 8, 9    | YES-NO        | Yes / No / Not sure                                                                                                                                                                                         | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Reg FD; FINRA 3110 finra; novel-by-author                                           |
| CT-003 | Controls              | Will the agent access or process payment-card data (PCI DSS in-scope: PANs, CVVs, expiry dates)?                                                                                                                                                           | PCI-scope data requires dedicated environment isolation (not shared with non-PCI workloads), tokenization of any stored card data, and PCI DSS-compliant data-residency.                                                                                                                                                                               | 2, 3, 4, 8, 9    | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | PCI DSS v4.0; novel-by-author                                                       |
| CT-004 | Controls              | Will the agent access or process protected health information (PHI, HIPAA in-scope data)?                                                                                                                                                                  | PHI triggers HIPAA Security Rule controls, BAA requirements for any Microsoft service handling PHI, and separate DLP policy scope.                                                                                                                                                                                                                     | 2, 3, 4, 8, 9    | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | HIPAA Security Rule; novel-by-author                                                |
| CT-005 | Controls              | Will the agent generate output that a regulated person could use to make a financial recommendation, suitability determination, credit decision, AML alert disposition, or trade decision — even if the agent is positioned as a "research assistant"?     | Output that influences regulated decisions triggers SR 11-7–style model-risk governance under firm policy (because OCC 2026-13 excludes gen/agentic AI from regulatory MRM, the firm must apply its own equivalent governance). FINRA suitability rules and FINRA Notice 24-09 require supervision of AI-generated customer communications. sullcrom+1 | 2, 4, 6          | YES-NO        | Yes / No / Sometimes                                                                                                                                                                                        | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | OCC 2026-13 occ.treas; FINRA Notice 24-09; SR 11-7                                  |
| CT-006 | Controls              | Will the agent send messages, documents, or any communications to customers on behalf of the firm?                                                                                                                                                         | Customer-facing communications are subject to FINRA Rule 2210 (communications with the public), supervised-principal review requirements, and recordkeeping under FINRA 4511 / SEC 17a-4. finra+1                                                                                                                                                      | 2, 4, 5, 9       | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | FINRA 2210; FINRA 4511 finra; FINRA 3110 finra                                      |
| CT-007 | Controls              | For every action the agent can take, does it need human approval before the action is executed (human-in-the-loop / HITL gating)?                                                                                                                          | HITL gating is the primary supervisory control for autonomous agents under FINRA 3110. It must be enabled on a per-action basis for any write, delete, send-external, or financial-transaction action type. finra                                                                                                                                      | 2, 4, 6          | Multi-select  | All actions require approval / Only write/delete actions / Only financial-transaction actions / Only external-send actions / No actions require approval                                                    | No actions require approval          | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | FINRA 3110 finra; novel-by-author                                                   |
| CT-008 | Controls              | What file types should users be allowed to upload to the agent as inputs?                                                                                                                                                                                  | File-upload restrictions prevent MIME-type exploits, data-exfiltration via disguised file formats, and macro-embedded document attacks. Copilot Studio supports MIME-type allow-listing.                                                                                                                                                               | 2, 3             | Multi-select  | PDF / DOCX / XLSX / CSV / Images (JPG/PNG) / Audio / Video / Any / None (no uploads allowed)                                                                                                                | PDF, DOCX                            | Conditional on AT-003 ≠ M365 Copilot chat               | No                                                                                                         | Stage 2 Capture       | Maker             | Power Platform admin docs; novel-by-author                                          |
| CT-009 | Controls              | Should the agent be allowed to search the public internet or access URLs outside the firm's knowledge graph?                                                                                                                                               | Web-grounding introduces data-leakage risk (queries sent to Bing/search APIs contain user prompts) and hallucination risk from unvetted sources. Web search is configurable per agent in Copilot Studio and must be explicitly toggled on by admin policy.                                                                                             | 2, 4             | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Microsoft Learn Copilot Studio admin; novel-by-author                               |
| CT-010 | Controls              | Should conversation transcripts from this agent be collected and stored for supervision, audit, or support purposes?                                                                                                                                       | Transcripts are a primary record artifact for FINRA 3110 supervision and SEC 17a-4 record preservation. Transcript logging must be enabled at the agent level in Copilot Studio or via Azure Monitor for Foundry agents. finra+1                                                                                                                       | 2, 9             | YES-NO        | Yes / No                                                                                                                                                                                                    | Yes                                  | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | FINRA 3110 finra; SEC 17a-4                                                         |
| CT-011 | Controls              | Should the agent collect user satisfaction or feedback ratings from conversations?                                                                                                                                                                         | Feedback data may constitute a business record subject to retention obligations and creates a training-data pipeline risk (user ratings could inadvertently fine-tune the underlying model). Copilot Studio feedback collection is configurable per agent.                                                                                             | 2, 9             | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Microsoft Learn Copilot Studio; novel-by-author                                     |
| CT-012 | Controls              | Will any knowledge sources contain sensitivity-labeled content (e.g., Purview labels: Confidential, Highly Confidential, Public)?                                                                                                                          | If yes, the agent must honor sensitivity-label access controls and not surface Confidential or Highly Confidential content to users lacking the corresponding label clearance. This requires item-level permission scan via agent-knowledge-source-scanner. alberthoitingh+1                                                                           | 2, 8, 9          | YES-NO        | Yes / No / Not sure                                                                                                                                                                                         | Not sure                             | Always                                                  | Partial — pre-fill from Purview API scan of SharePoint/OneDrive sources learn.microsoft                    | Stage 2 Capture       | Maker             | Purview sensitivity labels learn.microsoft; DSPM-for-AI learn.microsoft             |
| CT-013 | Controls              | Will the agent produce output that will be displayed to, or acted upon by, a regulated person without further human review (i.e., the agent's answer IS the end product, not a draft)?                                                                     | Unsupervised AI output in regulated workflows requires output-supervision queue and scope-drift monitoring controls. SR 11-7 principles require validation of model outputs before operational use. sullcrom                                                                                                                                           | 2, 4, 6          | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | SR 11-7 principles; OCC 2026-13 sullcrom                                            |
| CT-014 | Controls              | Should the agent be prevented from sharing its outputs outside the firm (e.g., copy-paste to external apps, export to personal OneDrive, forwarding via personal email)?                                                                                   | Exfiltration of agent outputs containing NPI, MNPI, or PCI data via personal channels is a GLBA / Reg FD / information-barrier risk. DLP policies and Conditional Access session controls must restrict output sharing.                                                                                                                                | 2, 3, 5          | YES-NO        | Yes / No                                                                                                                                                                                                    | Yes                                  | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | GLBA 501(b); Purview DLP learn.microsoft; novel-by-author                           |
| CT-015 | Controls              | Will the agent be configured to opt out of Microsoft's customer-content abuse monitoring (available for enterprise customers)?                                                                                                                             | Microsoft's default abuse-monitoring pipeline may log conversation content for safety purposes. Financial firms with MNPI or NPI data frequently opt out. The opt-out decision must be documented and approved by Privacy/InfoSec.                                                                                                                     | 2, 6             | YES-NO        | Yes (opt out) / No (leave on)                                                                                                                                                                               | No (leave on)                        | Always                                                  | No                                                                                                         | Stage 2 Capture       | InfoSec / Privacy | Microsoft Azure OpenAI opt-out docs; novel-by-author                                |
| CT-016 | Controls              | Should Prompt Shield (adversarial prompt injection detection) be enabled for this agent?                                                                                                                                                                   | Prompt injection attacks can cause an agent with write/delete/financial-transaction actions to take unintended actions. Azure AI Content Safety Prompt Shield is the primary mitigating control.                                                                                                                                                       | 2, 4             | YES-NO        | Yes / No                                                                                                                                                                                                    | Yes (if AT-001=Yes)                  | Always                                                  | Partial — auto-set Yes if AT-001=Yes                                                                       | Stage 3 Auto-classify | System            | Azure AI Content Safety docs; novel-by-author                                       |
| CT-017 | Controls              | Should content moderation (Azure AI Content Safety harm categories: hate, violence, sexual, self-harm) be enabled for both input and output?                                                                                                               | Content moderation is required for any customer-facing agent (CT-006=Yes) and recommended for all agents under FINRA suitability and duty-of-care principles. Copilot Studio and Azure AI Foundry both support configurable moderation thresholds.                                                                                                     | 2, 4, 5          | Single-select | Enabled — strict / Enabled — default / Enabled — lenient / Disabled                                                                                                                                         | Enabled — default                    | Always                                                  | Partial — auto-set Enabled–strict if CT-006=Yes                                                            | Stage 3 Auto-classify | System            | Azure AI Content Safety; novel-by-author                                            |
| EP-001 | Environment Placement | Should the data processed and stored by this agent remain within the United States (data residency requirement)?                                                                                                                                           | US data residency may be required by firm policy, state privacy laws (CCPA, NYDFS 23 NYCRR 500), or contractual data-processing agreements with clients. Power Platform environments and Azure AI Foundry projects are region-specific; selecting a non-US region requires explicit approval.                                                          | 3, 8             | YES-NO        | Yes (US only) / No (any approved region) / Not sure                                                                                                                                                         | Yes (US only)                        | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | NYDFS 23 NYCRR 500; Power Platform environment docs syskit                          |
| EP-002 | Environment Placement | Are there specific countries or regions where data processed by this agent must NOT be stored or transmitted?                                                                                                                                              | Cross-border data-transfer restrictions under GDPR, Swiss-US Privacy Shield, and firm data-processing agreements may prohibit certain regions. This drives Azure region selection and data-loss-prevention routing rules.                                                                                                                              | 3, 8             | Multi-select  | EU / UK / China / Russia / Any country without US adequacy decision / None / [free text for other]                                                                                                          | None                                 | Conditional on EP-001=No                                | No                                                                                                         | Stage 2 Capture       | Maker             | GDPR Art. 44–46; novel-by-author                                                    |
| EP-003 | Environment Placement | What is the maximum number of distinct users who will interact with this agent in any given month?                                                                                                                                                         | User count drives zone classification (Decision 5), environment-type selection (dedicated vs shared), and capacity-profile sizing (Copilot Studio messages, Power Platform requests).                                                                                                                                                                  | 3, 5, 12         | Numeric       | Integer ≥ 1; max 500,000                                                                                                                                                                                    | n/a                                  | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Power Platform capacity docs; novel-by-author                                       |
| EP-004 | Environment Placement | What is the estimated monthly conversation volume (number of conversations or sessions, not messages)?                                                                                                                                                     | Conversation volume drives Copilot Studio message capacity allocation and determines whether the shared environment's capacity pool is adequate or a dedicated environment with reserved capacity is required.                                                                                                                                         | 3, 10, 12        | Numeric       | Integer ≥ 1                                                                                                                                                                                                 | n/a                                  | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Power Platform capacity; novel-by-author                                            |
| EP-005 | Environment Placement | Does this agent require production-grade availability (uptime SLA, 24/7 availability, < 1-hour RTO)?                                                                                                                                                       | Production-grade SLA requires a dedicated Production-type environment (not Sandbox or Developer), formal DR configuration, and backup/restore procedures. This distinction is enforced by the environment-lifecycle-management solution's zone policy.                                                                                                 | 3, 10            | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Power Platform environment strategy; novel-by-author                                |
| EP-006 | Environment Placement | Which ALM stage is this request for?                                                                                                                                                                                                                       | Intake creates the dev-environment provisioning record. Test and production environments are created via subsequent ALM promotion requests. The answer affects which DLP policy group applies and whether auto-approval is eligible.                                                                                                                   | 3, 10            | Single-select | Development / Test / Production / Proof-of-concept (will not proceed to production)                                                                                                                         | Development                          | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Power Platform ALM; novel-by-author                                                 |
| EP-007 | Environment Placement | Does the agent need to coexist in an environment with other regulated applications (e.g., an existing Power Apps app with NPI data, a production CRM)?                                                                                                     | Co-location with regulated apps constrains environment selection to ones with matching DLP policy groups and may require blast-radius isolation analysis. The environment-lifecycle-management solution enforces zone-DLP alignment.                                                                                                                   | 3, 8, 11         | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Power Platform DLP learn.microsoft+1; novel-by-author                               |
| EP-008 | Environment Placement | What is the approximate Dataverse storage this agent will require (knowledge-base documents, conversation history, entity data)?                                                                                                                           | Dataverse storage is a finite per-environment capacity. Exceeding capacity causes environment blocking. Oversized agents require dedicated storage allocation.                                                                                                                                                                                         | 3, 10            | Single-select | < 1 GB / 1–10 GB / 10–100 GB / > 100 GB / Unknown                                                                                                                                                           | Unknown                              | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Power Platform capacity docs; novel-by-author                                       |
| EP-009 | Environment Placement | Does the agent need disaster recovery or business-continuity protection (e.g., geo-redundant backup, RPO < 4 hours)?                                                                                                                                       | DR requirements drive region-pair selection for Power Platform environments, Dataverse backup frequency, and Azure AI Foundry deployment topology for Foundry agents.                                                                                                                                                                                  | 3, 10            | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Conditional on EP-005=Yes                               | No                                                                                                         | Stage 2 Capture       | Maker             | Power Platform admin; novel-by-author                                               |
| EP-010 | Environment Placement | Which DLP policy group should govern this environment?                                                                                                                                                                                                     | DLP policy group determines which connectors are permitted in the environment. FSI environments typically use a tiered group structure (Restricted-NPI / Regulated-General / Personal-Productivity). The answer must align with the data sensitivity of connected sources. matthewdevaney+1                                                            | 3, 8             | Single-select | Restricted-NPI (highest restriction) / Regulated-General / Personal-Productivity / New policy needed (describe in BJ-001)                                                                                   | Regulated-General                    | Always                                                  | Partial — pre-fill from existing tenant DLP policy list via Power Platform Admin API learn.microsoft       | Stage 3 Auto-classify | InfoSec           | Power Platform DLP matthewdevaney+1                                                 |
| EP-011 | Environment Placement | Is this agent subject to Managed Environments governance (premium Power Platform governance controls)?                                                                                                                                                     | Managed Environments enable weekly digest, sharing limits, solution checker enforcement, and enhanced DLP for Copilot Studio agents. Required for any Zone-1 or Zone-2 agent under firm policy. learn.microsoft                                                                                                                                        | 3, 5, 7          | YES-NO        | Yes / No                                                                                                                                                                                                    | Yes (if ZN-001=Enterprise or Team)   | Conditional on ZN-001 result                            | Partial — auto-set Yes if Zone ≤ 2                                                                         | Stage 3 Auto-classify | System            | Power Platform Managed Environments learn.microsoft                                 |
| EP-012 | Environment Placement | What AI Builder credit allocation does this agent require per month (for document processing, form recognition, or predictive models embedded in the agent)?                                                                                               | AI Builder credits are a finite tenant resource. Allocation must be reserved during environment provisioning to avoid throttling production workflows.                                                                                                                                                                                                 | 3, 10, 12        | Single-select | None (agent does not use AI Builder) / < 500 credits / 500–5,000 credits / > 5,000 credits / Unknown                                                                                                        | None                                 | Conditional on AT-005=Pro-developer                     | No                                                                                                         | Stage 2 Capture       | Maker             | Power Platform capacity docs; novel-by-author                                       |
| RT-001 | Risk Tier             | Can the agent initiate, approve, or trigger a financial transaction (trade order, payment, wire, credit extension, fee waiver) — even on a conditional or proposed basis?                                                                                  | Financial-transaction authority is the highest-risk autonomy signal. Any Yes response immediately classifies the agent as Tier 1 under firm policy, triggers mandatory HITL gating, and requires InfoSec + Compliance + Legal parallel review.                                                                                                         | 2, 4, 6          | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | SR 11-7; novel-by-author                                                            |
| RT-002 | Risk Tier             | If the agent produces an incorrect or harmful output, can the effect be fully reversed without customer harm or regulatory consequence?                                                                                                                    | Irreversibility is a core risk multiplier in SR 11-7–style model-risk scoring and ISO/IEC 42001. Irreversible actions (sent emails, executed trades, filed regulatory reports) require higher supervisory controls than reversible ones. sullcrom                                                                                                      | 2, 4             | Single-select | Fully reversible / Partially reversible (some effort required) / Irreversible / Not sure                                                                                                                    | Not sure                             | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | SR 11-7; ISO/IEC 42001; novel-by-author                                             |
| RT-003 | Risk Tier             | What is the maximum estimated dollar amount of financial impact if the agent malfunctions or produces incorrect output for a single incident?                                                                                                              | Dollar-threshold banding is a standard component of SR 11-7–style materiality scoring. Thresholds: < $10K = Tier 3; $10K–$1M = Tier 2; > $1M = Tier 1.                                                                                                                                                                                                 | 4, 6             | Single-select | Under $10,000 / $10,000–$1,000,000 / Over $1,000,000 / Not quantifiable                                                                                                                                     | Not quantifiable                     | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker + Sponsor   | SR 11-7; novel-by-author                                                            |
| RT-004 | Risk Tier             | Is the agent directly interacting with customers or will customers see its output (even if a human reviews it first)?                                                                                                                                      | Customer-facing classification drives FINRA 2210 supervision, customer-experience controls, and escalates zone to Zone-1 (Enterprise) or Zone-2 (Team) minimum.                                                                                                                                                                                        | 2, 4, 5, 6       | Single-select | Directly customer-facing (no human review) / Customer-facing with human review / Internal only / Not sure                                                                                                   | Internal only                        | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | FINRA 2210; FINRA 3110 finra                                                        |
| RT-005 | Risk Tier             | Does the agent make, or does its output directly feed into, a regulated decision — such as a Know Your Customer (KYC) determination, Anti-Money Laundering (AML) alert disposition, credit-worthiness assessment, or investment-suitability determination? | Regulated decisions have the highest supervisory burden. SR 11-7 principles require model validation; FINRA suitability rules require principal approval. OCC 2026-13 scopes these explicitly to firm governance. sullcrom+1                                                                                                                           | 2, 4, 6          | YES-NO        | Yes / No / Partial (output is one of several inputs)                                                                                                                                                        | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | SR 11-7; FINRA suitability rules; OCC 2026-13 occ.treas                             |
| RT-006 | Risk Tier             | Does the agent operate without a human monitoring it in real time — that is, does it run autonomously on a schedule or in response to events, without a human watching each run?                                                                           | Unmonitored autonomous operation eliminates the real-time supervision layer required by FINRA 3110 and requires compensating controls: transcript logging, scope-drift monitoring, output-supervision queues, and anomaly alerting. finra                                                                                                              | 2, 4, 6, 10      | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | FINRA 3110 finra; novel-by-author                                                   |
| RT-007 | Risk Tier             | If the agent were disabled or unavailable for 24 hours, what would the business impact be?                                                                                                                                                                 | Business-impact rating drives criticality classification, which in turn drives environment-availability requirements, DR posture, and the deprovisioning-trigger threshold.                                                                                                                                                                            | 4, 5, 10         | Single-select | Minimal (workaround available) / Moderate (productivity loss, no revenue impact) / Significant (revenue or compliance impact) / Critical (regulatory or customer SLA breach)                                | Minimal                              | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker + Sponsor   | Novel-by-author                                                                     |
| RT-008 | Risk Tier             | Will the agent have access to employee personal data (compensation, performance reviews, HR records, health-related accommodations)?                                                                                                                       | Employee data access triggers GDPR (for EU staff), CCPA (for California employees), and internal HR privacy policies. It escalates Privacy review requirement and sensitivity-label enforcement.                                                                                                                                                       | 2, 4, 6, 8       | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | GDPR; CCPA; novel-by-author                                                         |
| RT-009 | Risk Tier             | Will the agent have write or delete access to any system of record (core banking, order management, CRM, HRIS, GRC platform)?                                                                                                                              | Write/delete access to systems of record is a Tier-1 risk signal due to data-integrity exposure and SOX 404 implications for financial reporting systems. Requires segregation-of-duties control design.                                                                                                                                               | 2, 4, 6, 8       | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | SOX 404; novel-by-author                                                            |
| RT-010 | Risk Tier             | Is the agent expected to scale to a broad user population without additional review — that is, will it be copy-promoted to many teams or environments after initial deployment?                                                                            | Agents with broad-scale promotion plans require Zone-1/Enterprise governance from the start, not after the fact. Auto-detection of sharing attempts is handled by unrestricted-agent-sharing-detector but intent should be declared upfront.                                                                                                           | 4, 5, 10         | YES-NO        | Yes / No / Possibly                                                                                                                                                                                         | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Novel-by-author                                                                     |
| ZN-001 | Zone                  | Who is the intended audience for this agent?                                                                                                                                                                                                               | Zone classification (Personal / Team / Enterprise) determines sharing scope, Managed Environments requirement, sponsorship routing, and which DLP policy group applies under the zone model.                                                                                                                                                           | 3, 5, 6, 7       | Single-select | Only me (the maker) / My immediate team (< 20 people) / A defined department or business unit (20–500 people) / The entire firm or multiple business units / External customers or partners                 | Only me                              | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Novel-by-author; Power Platform governance syskit                                   |
| ZN-002 | Zone                  | Will the agent be shared with users outside the maker's own Entra group or department?                                                                                                                                                                     | Cross-department sharing moves an agent from Zone-3 (Personal) toward Zone-2 (Team) or Zone-1 (Enterprise), triggering additional sponsorship and DLP requirements. unrestricted-agent-sharing-detector monitors post-deployment violations.                                                                                                           | 5, 6, 7          | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Novel-by-author                                                                     |
| ZN-003 | Zone                  | Will the agent be published to the Microsoft Teams app catalog (sideloaded or organization-wide)?                                                                                                                                                          | Teams app-catalog publication makes the agent available to all Teams users by default (Enterprise zone minimum). Requires Teams admin approval and additional testing in the Teams client.                                                                                                                                                             | 3, 5, 7          | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Microsoft Teams admin docs; novel-by-author                                         |
| ZN-004 | Zone                  | Will the agent be embedded in a customer-facing web property (firm website, client portal, mobile app)?                                                                                                                                                    | Customer-portal embedding is automatically Zone-1 (Enterprise), triggers FINRA 2210 supervision, customer-data DLP, and requires InfoSec penetration-test sign-off before go-live.                                                                                                                                                                     | 3, 5, 6, 8       | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | FINRA 2210; novel-by-author                                                         |
| ZN-005 | Zone                  | Will the agent be shared externally — that is, accessible to users outside the firm's Entra tenant (customers, vendors, regulators, counterparties)?                                                                                                       | External sharing requires cross-tenant governance, GLBA data-sharing controls, and activation of the cross-tenant-external-sharing-governance solution. It is an automatic Zone-1 (Enterprise) qualifier.                                                                                                                                              | 3, 5, 6, 8       | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | GLBA 501(b); Entra external identity docs; novel-by-author                          |
| ZN-006 | Zone                  | What is the maximum number of simultaneous active users anticipated at any given moment?                                                                                                                                                                   | Peak concurrency drives zone and environment-capacity decisions independently of monthly active user count (EP-003). A low-MAU agent used by a trading desk at open and close can have very high peak concurrency.                                                                                                                                     | 3, 5, 10         | Numeric       | Integer ≥ 1                                                                                                                                                                                                 | n/a                                  | Always                                                  | No                                                                                                         | Stage 2 Capture       | Maker             | Novel-by-author                                                                     |
| SP-001 | Sponsor               | Who is the named business sponsor for this agent — the manager-level or above person who is accountable for the business outcome and approves the use case?                                                                                                | FINRA 3110 requires that supervision responsibilities be assigned to a designated principal. Every agent must have an identifiable responsible person at the manager level or above. finra                                                                                                                                                             | 6                | Free text     | Valid firm employee UPN (validated against Entra)                                                                                                                                                           | n/a                                  | Always                                                  | Partial — pre-fill manager from Graph /v1.0/users/{id}/manager learn.microsoft                             | Stage 2 Capture       | Maker             | FINRA 3110 finra                                                                    |
| SP-002 | Sponsor               | Who is the business owner — the person responsible for ongoing operational oversight, access reviews, and deprovisioning decisions for this agent? (May be the same as SP-001.)                                                                            | The business owner is the ongoing governance accountability anchor. Owner departure triggers the deprovisioning-review workflow in agent-365-lifecycle-governance.                                                                                                                                                                                     | 6, 10            | Free text     | Valid firm employee UPN                                                                                                                                                                                     | Same as SP-001                       | Always                                                  | Partial — pre-fill from SP-001                                                                             | Stage 2 Capture       | Maker             | Novel-by-author                                                                     |
| SP-003 | Sponsor               | What business unit, cost center, and department owns this agent?                                                                                                                                                                                           | Cost-center attribution drives chargeback for capacity consumption (AI Builder credits, Copilot Studio messages, Dataverse storage) and identifies which compliance officer has supervisory jurisdiction.                                                                                                                                              | 6, 10, 12        | Free text     | Valid cost-center code from HR system                                                                                                                                                                       | n/a                                  | Always                                                  | Partial — pre-fill from Graph /v1.0/users/{id}?$select=department,companyName learn.microsoft              | Stage 2 Capture       | Maker             | Novel-by-author                                                                     |
| SP-004 | Sponsor               | Does this agent require model-risk management (MRM) review under firm policy? (Note: OCC Bulletin 2026-13 excludes generative and agentic AI from regulatory MRM scope, but firm policy applies SR 11-7–inspired review to all Tier-1 and Tier-2 agents.)  | Firm-policy MRM review is triggered by RT-001=Yes, RT-005=Yes, or Tier-1/2 classification from the risk-tier classifier. The question is asked of the Sponsor to confirm their awareness of this requirement. sullcrom+1                                                                                                                               | 4, 6             | YES-NO        | Yes / No / Unknown                                                                                                                                                                                          | Computed from RT                     | Conditional on RT outcome                               | Partial — auto-set from RT-001 and RT-005 signals                                                          | Stage 3 Auto-classify | Sponsor           | OCC 2026-13 occ.treas; SR 11-7 sullcrom                                             |
| SP-005 | Sponsor               | Does this agent require Privacy review (processing of personal data of EU/UK residents, California residents, or firm employees)?                                                                                                                          | Privacy review is triggered by CT-001=Yes (customer NPI), RT-008=Yes (employee data), or EP-002 containing EU/UK countries. GDPR Art. 35 DPIA may be required for high-risk processing.                                                                                                                                                                | 6                | YES-NO        | Yes / No                                                                                                                                                                                                    | Computed from CT-001, RT-008, EP-002 | Conditional                                             | Partial — auto-set from CT-001 and RT-008                                                                  | Stage 3 Auto-classify | System            | GDPR Art. 35; GLBA 501(b)                                                           |
| SP-006 | Sponsor               | Does this agent require Procurement / vendor due-diligence review because it calls a third-party API or uses a non-Microsoft LLM?                                                                                                                          | Third-party API calls and BYO-LLM deployments require vendor risk assessment under GLBA 501(b) third-party oversight requirements and OCC 2013-29 (third-party risk).                                                                                                                                                                                  | 6, 8             | YES-NO        | Yes / No                                                                                                                                                                                                    | Computed from AT-002, DS-006         | Conditional on AT-002=Yes or DS-006                     | Partial — auto-set from AT-002                                                                             | Stage 3 Auto-classify | System            | GLBA 501(b); OCC 2013-29; novel-by-author                                           |
| SP-007 | Sponsor               | Does this agent require Legal review (contract obligations with clients, IP concerns related to training data, litigation-hold implications, or employment law)?                                                                                           | Legal review is triggered by AT-010=Yes (external sharing), CT-002=Yes (MNPI), or RT-001=Yes (financial transaction). The question confirms Sponsor awareness.                                                                                                                                                                                         | 6                | YES-NO        | Yes / No                                                                                                                                                                                                    | Computed from AT-010, CT-002, RT-001 | Conditional                                             | Partial — auto-set from trigger signals                                                                    | Stage 3 Auto-classify | Sponsor           | Novel-by-author                                                                     |
| SP-008 | Sponsor               | Does this agent require Records Management review for determination of record series, retention schedule, and Purview label assignment?                                                                                                                    | Records review is required for any agent that produces artifacts subject to SEC 17a-4, FINRA 4511, CFTC 1.31, or SOX. smarsh+1                                                                                                                                                                                                                         | 6, 9             | YES-NO        | Yes / No                                                                                                                                                                                                    | Yes (if CT-010=Yes or CT-006=Yes)    | Conditional                                             | Partial — auto-set Yes if CT-010=Yes                                                                       | Stage 3 Auto-classify | System            | SEC 17a-4; FINRA 4511 finra                                                         |
| SP-009 | Sponsor               | Does this agent require Compliance review (FINRA/SEC rule applicability, information-barrier compliance, suitability, Reg FD)?                                                                                                                             | Compliance review is required for any customer-facing agent (RT-004 ≠ Internal only), any MNPI-touching agent (CT-002=Yes), or any agent making regulated decisions (RT-005=Yes). finra                                                                                                                                                                | 6                | YES-NO        | Yes / No                                                                                                                                                                                                    | Computed from RT-004, CT-002, RT-005 | Conditional                                             | Partial — auto-set from trigger signals                                                                    | Stage 3 Auto-classify | System            | FINRA 3110 finra; Reg FD                                                            |
| SP-010 | Sponsor               | Should the sponsor reviews above be conducted in parallel or serially?                                                                                                                                                                                     | Parallel review reduces time-to-approve for lower-risk agents and is the default for Tier-3 + Zone-1 auto-approve path. Serial review is required where one review's output is a prerequisite input for the next (e.g., Legal must opine on MNPI before Compliance can finalize).                                                                      | 6                | Single-select | Parallel (all reviewers simultaneously) / Serial (sequential, defined order) / Mixed (some parallel, some serial)                                                                                           | Parallel                             | Conditional on SP-004 through SP-009                    | No                                                                                                         | Stage 5 Review        | Sponsor           | Novel-by-author                                                                     |
| MR-001 | Maker Role            | Does the maker currently have access to a Power Platform environment in which to build, and if so, what type (Developer / Sandbox / Production)?                                                                                                           | Existing environment access determines whether a new environment must be provisioned or an existing one reused. Prevents unnecessary environment sprawl.                                                                                                                                                                                               | 3, 7             | Single-select | Yes — Developer environment / Yes — Sandbox / Yes — Production / No existing access                                                                                                                         | No existing access                   | Always                                                  | Yes — from Power Platform Admin API: GET /v2.0/environments?$filter=createdBy/userId eq '{userId}'         | Stage 2 Capture       | System            | Power Platform Admin API; novel-by-author                                           |
| MR-002 | Maker Role            | Does the maker have an active Copilot Studio license (per-tenant capacity or per-user license)?                                                                                                                                                            | Without a Copilot Studio license, the maker cannot create or manage Copilot Studio classic or custom-engine agents. A license must be provisioned before environment creation.                                                                                                                                                                         | 7                | YES-NO        | Yes / No                                                                                                                                                                                                    | Unknown                              | Conditional on AT-001 result pointing to Copilot Studio | Yes — from Microsoft Graph /v1.0/users/{id}/licenseDetails (filter for Copilot Studio SKU) learn.microsoft | Stage 2 Capture       | System            | Microsoft Graph licensing API learn.microsoft                                       |
| MR-003 | Maker Role            | Does the maker have an active M365 Copilot license?                                                                                                                                                                                                        | M365 Copilot license is required for Agent Builder and for publishing declarative agents. Without it, these platforms are disqualified.                                                                                                                                                                                                                | 7                | YES-NO        | Yes / No                                                                                                                                                                                                    | Unknown                              | Conditional on AT-003 pointing to M365 Copilot          | Yes — from Graph /v1.0/users/{id}/licenseDetails (filter M365 Copilot SKU) learn.microsoft+1               | Stage 2 Capture       | System            | Microsoft Graph learn.microsoft                                                     |
| MR-004 | Maker Role            | Does the maker need Azure AI Foundry project access (for custom-engine or Foundry agents)?                                                                                                                                                                 | Foundry project access requires Azure RBAC assignment (Azure AI Developer role minimum); the maker's Azure AD account must be in scope of the Foundry workspace's access policy. learn.microsoft                                                                                                                                                       | 7                | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Conditional on AT-002=Yes or AT-005=Pro-developer       | Partial — check existing Foundry role assignments via Azure RBAC API learn.microsoft                       | Stage 2 Capture       | System            | Azure Foundry RBAC learn.microsoft                                                  |
| MR-005 | Maker Role            | Will there be a secondary maker or co-owner who should share build and maintenance rights?                                                                                                                                                                 | Co-ownership ensures continuity if the primary maker is unavailable. It also affects the deprovisioning trigger: both owners must depart before auto-deprovisioning is triggered.                                                                                                                                                                      | 7, 10            | YES-NO        | Yes / No                                                                                                                                                                                                    | No                                   | Optional                                                | No                                                                                                         | Stage 2 Capture       | Maker             | Novel-by-author                                                                     |
| MR-006 | Maker Role            | Does the maker require the ability to publish and share the agent beyond their own use (i.e., do they need Publisher or Environment Admin role rather than Maker)?                                                                                         | The sharing scope requested must match the zone classification. A maker requesting Enterprise-zone publication must be granted Publisher rights in a Managed Environment with admin approval for each publish action.                                                                                                                                  | 5, 7             | Single-select | For my use only (Maker role sufficient) / Share within my team (Environment Contributor) / Publish org-wide (Publisher + Admin approval) / Publish externally (requires additional external-sharing policy) | For my use only                      | Always                                                  | No                                                                                                         | Stage                 |                   |                                                                                     |

---

## Part 2 — Catalog continued (MR-006+ through BJ)

Part 2 — Question Catalog (Continued)
Completing Maker Role (MR), then DS → BJ
Maker Role (MR) — continued
ID	Category	Question Text	Why It Matters	Decisions Driven	Answer Type	Allowed Values / Validation	Default	Required?	Auto-detectable?	Stage	Asked of	Source Citation
MR-006	Maker Role	Does the maker require the ability to publish and share the agent beyond their own use — for example, sharing with a team, publishing org-wide, or granting external access?	The sharing scope requested must match the zone classification. A maker requesting Enterprise-zone publication must hold Publisher rights in a Managed Environment with admin approval for each publish event; over-broad role grants violate least-privilege and trigger the unrestricted-agent-sharing-detector policy.	5, 7	Single-select	For my use only / Share within my immediate team / Publish to a department or business unit / Publish org-wide / Publish externally to non-tenant users	For my use only	Always	No	Stage 2 Capture	Maker	Power Platform Managed Environments 
; novel-by-author
MR-007	Maker Role	Does this agent require a dedicated service account or non-interactive identity for scheduled runs, API-to-API calls, or backend automation (rather than running under the maker's personal identity)?	Running automated agents under a personal user account violates least-privilege, creates a single point of failure when the employee leaves, and complicates audit trails. Microsoft Entra Agent ID (GA May 1, 2026) provides a workload-identity-backed agent principal that should be minted instead. 
7, 10	YES-NO	Yes / No	No	Always	Partial — check existing service principals in Entra via Graph /v1.0/servicePrincipals 
Stage 2 Capture	Maker	Entra Agent ID 
; novel-by-author
MR-008	Maker Role	Does any person in the build-and-operate team have a conflict of interest — for example, a developer who is also a trader building an agent that accesses their own trading desk's positions?	Segregation of duties (SoD) violations are a SOX 302/404 and FINRA 3110 concern. A developer with financial-data access in the production domain they are also building for must be flagged for SoD review before Maker Role is granted. 
2, 6, 7	YES-NO	Yes / No / Not sure	No	Always	No	Stage 2 Capture	Maker + Sponsor	SOX 302/404; FINRA 3110 
; novel-by-author
Data Source / Connector / Action (DS)
ID	Category	Question Text	Why It Matters	Decisions Driven	Answer Type	Allowed Values / Validation	Default	Required?	Auto-detectable?	Stage	Asked of	Source Citation
DS-001	Data Source	List every data source or knowledge base this agent will read from.	Every knowledge source must be classified by data sensitivity (NPI / MNPI / PCI / PHI / Employee / Public / Restricted) so the correct DLP policy, sensitivity-label enforcement, and item-level permission scan can be applied via agent-knowledge-source-scanner. 
2, 3, 8, 9	Multi-select + free text	SharePoint Online / OneDrive for Business / Dataverse / Azure Blob Storage / SQL Database / Dynamics 365 / Salesforce / Bloomberg / Refinitiv / Morningstar / Internal data warehouse / External public API / Other (describe)	None	Always	Partial — pre-fill connected data sources from Power Platform Admin API connector inventory	Stage 2 Capture	Maker	Purview DSPM-for-AI 
; novel-by-author
DS-002	Data Source	For each data source listed in DS-001, what is the highest sensitivity classification of data it contains?	Sensitivity classification drives DLP policy selection, Purview label enforcement, and environment-tier placement. A single Highly Confidential source elevates the entire agent to that classification tier. 
2, 3, 4, 8, 9	Multi-select per source	Public / Internal / Confidential / Highly Confidential / Restricted (maps to NPI/MNPI/PCI/PHI/Employee)	Internal	Always	Partial — pre-fill from Purview sensitivity scan of listed SharePoint/OneDrive sources 
Stage 2 Capture	Maker	Purview sensitivity labels 
DS-003	Data Source	Will any data source contain or be used to retrieve MNPI — material non-public information such as pre-announcement earnings, pending transactions, or non-public research ratings?	MNPI access requires information-barrier enforcement, dedicated MNPI-flagged Purview label on all retrieved content, and mandatory Compliance + Legal review. No vendor template reviewed asked this question.	2, 4, 6, 8, 9	YES-NO	Yes / No / Not sure	No	Always	No	Stage 2 Capture	Maker	Reg FD; FINRA 3110 
; novel-by-author
DS-004	Data Source	Will any knowledge source or data connection include client account data — such as account balances, holdings, transaction history, or client profile information?	Client account data is NPI under GLBA 501(b) and triggers the highest DLP restrictions, item-level permission enforcement, and mandatory sensitivity-label honoring in the agent's knowledge retrieval pipeline. 
2, 4, 8, 9	YES-NO	Yes / No	No	Always	No	Stage 2 Capture	Maker	GLBA 501(b); Purview DSPM-for-AI 
DS-005	Data Source	Will any data source reside outside the firm's Microsoft 365 / Azure tenant — for example, a third-party SaaS provider, vendor API, or on-premises system reached via an on-premises data gateway?	Out-of-tenant data sources require connector risk classification, network-path security review (on-prem gateway configuration), and may introduce cross-border data flow. They also expand the blast radius of a credential-oversharing incident.	2, 3, 8, 11	YES-NO	Yes / No	No	Always	No	Stage 2 Capture	Maker	Power Platform on-premises gateway docs; novel-by-author
DS-006	Data Source	Will the agent call any third-party API endpoints not covered by a standard Microsoft-certified connector?	Custom connectors to third-party APIs require connector-risk classification (read/write/delete/send-external/financial-transaction), OAuth-scope review, and — if the API belongs to a vendor — Procurement/vendor-due-diligence under GLBA 501(b) third-party risk requirements.	2, 6, 8	YES-NO	Yes / No	No	Always	No	Stage 2 Capture	Maker	GLBA 501(b); Power Platform DLP 
; novel-by-author
DS-007	Data Source	For any third-party API in DS-006, list the OAuth scopes or API key permissions the agent will request.	Over-broad OAuth scopes are the most common credential-oversharing vector, flagged by credential-oversharing-detector. Requested scopes must be limited to the minimum necessary for the agent's declared actions (least-privilege). 
2, 8	Free text	Comma-separated list of OAuth scopes or API permission names; max 2,000 chars	n/a	Conditional on DS-006=Yes	No	Stage 2 Capture	Maker	Entra security advisory 
; novel-by-author
DS-008	Data Source	List every Power Platform connector the agent will use.	Each connector must be classified (Business / Non-Business / Blocked) under the applicable DLP policy. Connectors not on the environment's approved list will block agent deployment. 
2, 3, 8	Multi-select + free text	[Dynamically populated from Power Platform certified connector catalog]; Other (custom connector, describe)	None	Always	Partial — pre-fill from Copilot Studio / Power Automate flow designer connector inventory if agent already in development	Stage 2 Capture	Maker	Power Platform DLP 
DS-009	Data Source	For each connector or action in DS-008, classify the side-effect type: does it read only, write/update, delete, send data externally, or execute a financial transaction?	Side-effect classification is the primary input to HITL-gating design (CT-007) and to action-level risk scoring. Write/delete/send-external/financial-transaction actions are automatically flagged for HITL unless explicitly approved otherwise.	2, 4, 8	Multi-select per connector	Read only / Write / Update / Delete / Send external (email, SMS, webhook) / Financial transaction (trade, payment, wire) / Admin action (provision, deprovision)	Read only	Always	No	Stage 2 Capture	Maker	Novel-by-author
DS-010	Data Source	Will the agent send any data to a recipient outside the firm's Entra tenant — for example, sending an email to a customer, posting to an external webhook, or calling a vendor's inbound API?	Cross-tenant data egress is the primary data-exfiltration risk vector. DLP policies must block or monitor each external-egress path. GLBA requires appropriate safeguards on all NPI leaving the firm.	2, 3, 8, 9	YES-NO	Yes / No	No	Always	No	Stage 2 Capture	Maker	GLBA 501(b); Power Platform DLP 
DS-011	Data Source	Will data processed by the agent cross an international border at any point in its flow — including API calls to services hosted outside the US?	Cross-border data flow triggers GDPR adequacy-mechanism requirements for EU-resident data, Swiss/UK transfer rules, and may conflict with data-residency commitments in client contracts.	3, 8	YES-NO	Yes / No / Not sure	No	Always	No	Stage 2 Capture	Maker	GDPR Art. 44–46; novel-by-author
DS-012	Data Source	Will the agent integrate with any Microsoft Graph API endpoints that expose organizational data (calendars, emails, Teams messages, directory data)?	Graph API access grants broad read (and sometimes write) access to organizational data. OAuth scopes must be declared and approved; application-level Graph permissions (not delegated) require explicit admin consent and are automatically flagged by credential-oversharing-detector. 
2, 7, 8	YES-NO	Yes / No	No	Always	Partial — detect existing app registrations with Graph permissions via Graph /v1.0/applications 
Stage 2 Capture	Maker	Microsoft Graph 
; security advisory 
DS-013	Data Source	Will the agent read from or write to a Dataverse table containing regulated or sensitive data?	Dataverse table-level security roles must be scoped to the agent's service identity. Broad Dataverse permissions granted to the agent principal are a leading cause of data oversharing in Power Platform estates. 
2, 3, 8	YES-NO	Yes / No	No	Always	Partial — check existing Dataverse security roles assigned to the maker via Power Platform Admin API	Stage 2 Capture	Maker	Power Platform governance 
; novel-by-author
DS-014	Data Source	Does the agent use Retrieval-Augmented Generation (RAG) — that is, does it retrieve documents or data chunks to inject into the LLM prompt at query time?	RAG pipelines introduce two governance risks: (1) retrieval of documents the querying user should not be able to see (item-level permission bypass) and (2) injection of unvalidated content into the prompt (indirect prompt injection). Both require the agent-knowledge-source-scanner and Prompt Shield controls. 
2, 4, 8	YES-NO	Yes / No	No	Always	No	Stage 2 Capture	Maker	Purview DSPM-for-AI 
; novel-by-author
DS-015	Data Source	For RAG sources (DS-014=Yes): does the retrieval pipeline enforce the querying user's item-level permissions, or could it surface documents the user cannot access directly?	Item-level permission enforcement is the primary control preventing a RAG agent from leaking Confidential or Highly Confidential documents to under-privileged users. agent-knowledge-source-scanner validates this at intake and on a scheduled basis post-deployment. 
2, 8	Single-select	Yes — item-level permissions enforced / No — all indexed content is retrievable by any user / Partial — some sources enforce permissions / Not sure	Not sure	Conditional on DS-014=Yes	No	Stage 2 Capture	Maker	Purview DSPM-for-AI 
; novel-by-author
DS-016	Data Source	Will the agent write outputs back into a system of record — such as updating a CRM opportunity, filing a compliance case, logging a trade note, or creating a support ticket?	Write-back to systems of record is a Tier-1 risk action under RT-009 and requires SOX-compliant audit trail, immutable logging of the write event, and — for financial-reporting systems — segregation-of-duties control design.	2, 4, 8, 9	YES-NO	Yes / No	No	Always	No	Stage 2 Capture	Maker	SOX 302/404; novel-by-author
DS-017	Data Source	Will the agent invoke any financial-system actions — such as placing or modifying an order in an OMS, initiating a payment or wire in a treasury system, or adjusting a credit limit?	Financial-system actions are automatically classified as Tier-1 under RT-001 and require HITL gating on every invocation, mandatory dual-control review in the approval workflow, and real-time anomaly detection on the action stream.	2, 4, 6, 8	YES-NO	Yes / No	No	Always	No	Stage 2 Capture	Maker	SR 11-7; SOX 302/404; novel-by-author
DS-018	Data Source	Will the agent use email or calendar integrations (e.g., Microsoft Exchange / Outlook connector, Graph Mail.Send, Calendar.ReadWrite)?	Email/calendar access is a high-sensitivity connector class. Mail.Send application permission allows sending as any user in the tenant — a major credential-oversharing risk. Delegated-only scopes are required for agent identities per Entra Agent ID least-privilege principles. 
2, 7, 8	YES-NO	Yes / No	No	Always	Partial — detect existing Exchange/Outlook permissions via Graph /v1.0/applications/{id}/requiredResourceAccess 
Stage 2 Capture	Maker	Entra Agent ID 
; security advisory 
DS-019	Data Source	Will the agent integrate with ServiceNow, Jira, or another IT service management / GRC platform for change-management or risk-registry purposes?	ITSM integration is required for the operational-handoff decision: every agent provisioning event should create a corresponding change record (RFC) in ServiceNow or Jira so it is auditable in the firm's change-management process.	8, 10, 11	Multi-select	ServiceNow / Jira / BMC Remedy / Archer (GRC) / None / Other	None	Always	No	Stage 2 Capture	Maker	Novel-by-author
DS-020	Data Source	Will the agent use Microsoft Teams connectors or webhooks to post messages into Teams channels or group chats?	Teams-channel posting by an agent is a form of automated communication that may constitute a record under FINRA 4511 if it involves business communications. Scope of Teams permissions must be declared and channel-level write access restricted to approved channels only. 
2, 8, 9	YES-NO	Yes / No	No	Always	No	Stage 2 Capture	Maker	FINRA 4511 
; novel-by-author
Records / Retention (RR)
ID	Category	Question Text	Why It Matters	Decisions Driven	Answer Type	Allowed Values / Validation	Default	Required?	Auto-detectable?	Stage	Asked of	Source Citation
RR-001	Records / Retention	What types of output artifacts will this agent produce that must be retained as business records?	Artifact type determines the applicable retention schedule and immutable-storage destination. FINRA 4511 and SEC 17a-4 require retention of all records made in the ordinary course of business, including AI-generated outputs that influence regulated decisions. 
9	Multi-select	Conversation transcripts / Agent-generated reports or summaries / Audit logs of actions taken / Sponsor approval records / Model-validation evidence / Feedback/rating data / Configuration snapshots / None	Conversation transcripts, Audit logs	Always	No	Stage 2 Capture	Maker	FINRA 4511 
; SEC 17a-4; novel-by-author
RR-002	Records / Retention	What retention period applies to the primary output artifacts of this agent?	Default firm retention is 7 years (aligned to SEC Rule 17a-4(b) and CFTC 1.31). Specific record series may require longer (e.g., WORM records required by 17a-4(f) for 6 years minimum with first 2 years immediately accessible). Records Management review must confirm the correct schedule. 
9	Single-select	3 years (FINRA 4511 minimum for some records) / 6 years (SEC 17a-4 standard) / 7 years (firm default) / 10 years / Permanent / Uncertain — Records review required	7 years (firm default)	Always	No	Stage 2 Capture	Records	FINRA 4511 
; SEC 17a-4; CFTC 1.31
RR-003	Records / Retention	Must conversation transcripts or outputs be stored in WORM (write-once, read-many) immutable storage compliant with SEC Rule 17a-4(f)?	SEC 17a-4(f) requires that electronic records subject to the rule be preserved in non-rewriteable, non-erasable format with an independent audit capability. If agent transcripts constitute 17a-4 records, they must flow to Azure Immutable Blob Storage or a Purview-configured immutable-retention label. 
9	YES-NO	Yes / No / Uncertain — Records review required	Uncertain	Always	No	Stage 2 Capture	Records	SEC 17a-4(f); novel-by-author
RR-004	Records / Retention	What Microsoft Purview retention label should be applied to this agent's output artifacts?	Purview retention labels enforce the retention-and-deletion schedule automatically and provide defensible-deletion proof for regulatory examination. The label must match the record series assigned by Records Management. 
9	Single-select	[Dynamically populated from Purview label taxonomy via Purview API] / New label needed — describe record series	n/a	Always	Partial — pre-fill candidate labels from Purview /beta/security/labels/retentionLabels 
Stage 5 Review	Records	Purview retention labels 
RR-005	Records / Retention	Where should retained records be stored — in Microsoft Purview / SharePoint immutable library, Azure Immutable Blob Storage, or a third-party compliance archive?	Storage destination determines the immutability mechanism, the backup cadence, and the eDiscovery surface. FINRA-4511-subject records must be accessible within the retention period and producible on regulatory demand within 24 hours. 
9, 10	Single-select	Purview / SharePoint immutable library / Azure Immutable Blob Storage (WORM) / Third-party archive (specify) / Not yet determined	Not yet determined	Always	No	Stage 5 Review	Records	FINRA 4511 
; SEC 17a-4(f); novel-by-author
RR-006	Records / Retention	Should this agent's records be placed on litigation hold due to any active or reasonably anticipated legal proceeding?	Litigation holds suspend normal retention-and-deletion schedules. If a hold applies, Purview eDiscovery hold must be placed on the agent's output containers before the agent is deployed. Legal must confirm.	9	YES-NO	Yes / No / Unknown — Legal review required	No	Always	No	Stage 5 Review	Legal	Purview eDiscovery; novel-by-author
RR-007	Records / Retention	Must the intake form itself — including all maker answers, auto-detected values, sponsor sign-off, and reviewer decisions — be retained as a compliance record?	The intake form is the primary evidence artifact for demonstrating that appropriate governance was applied to each agent. It must be retained for the same period as the agent's operational records (firm default: 7 years) and stored immutably.	9	YES-NO	Yes / No	Yes (always)	Always	Yes — auto-set Yes (firm policy)	Stage 3 Auto-classify	System	Novel-by-author; FINRA 3110 
RR-008	Records / Retention	Should sponsor approval records and reviewer sign-offs be captured as digitally signed, timestamped audit entries in the agent registry?	Digitally signed sponsor attestations provide non-repudiation evidence for regulatory examination. FINRA 3110 requires that supervision decisions be documented and attributable to a named principal. 
6, 9	YES-NO	Yes / No	Yes (always)	Always	Yes — auto-set Yes (firm policy)	Stage 3 Auto-classify	System	FINRA 3110 
; novel-by-author
RR-009	Records / Retention	Does the agent process voice or audio input or output that must be retained (e.g., a voice-channel agent in a contact center)?	Voice recordings of regulated communications (e.g., broker-customer calls routed through an AI agent) are subject to FINRA 3110 call-recording requirements and must be captured, time-stamped, and stored with the same immutability requirements as written records. 
2, 9	YES-NO	Yes / No	No	Conditional on AT-003 = Voice	No	Stage 2 Capture	Maker	FINRA 3110 
; novel-by-author
RR-010	Records / Retention	Will any records produced by this agent be subject to CFTC Rule 1.31 (commodity trading records)?	CFTC 1.31 requires retention of all records relating to commodity trading for 5 years (first 2 years in an immediately accessible location). CFTC-subject records require WORM storage and systematic retrieval capability on regulatory demand.	9	YES-NO	Yes / No / Unknown	No	Always	No	Stage 2 Capture	Compliance	CFTC 1.31; novel-by-author
Operational Handoff (OH)
ID	Category	Question Text	Why It Matters	Decisions Driven	Answer Type	Allowed Values / Validation	Default	Required?	Auto-detectable?	Stage	Asked of	Source Citation
OH-001	Operational Handoff	What is the target go-live date for this agent in its first production-eligible environment?	Go-live date drives ALM promotion scheduling, Entra Agent ID minting timing, and environment-provisioning SLA commitments from the environment-lifecycle-management solution.	10	Date	ISO 8601 date; must be ≥ 30 business days from intake submission for Tier-1 agents, ≥ 14 for Tier-2, ≥ 5 for Tier-3	n/a	Always	No	Stage 2 Capture	Maker	Novel-by-author
OH-002	Operational Handoff	Where should operational monitoring and logging for this agent be directed?	Every agent needs a defined monitoring destination for transcript logs, action-execution logs, and anomaly alerts. The destination must be configured before go-live in the compliance-dashboard and aligned with the firm's SIEM (e.g., Microsoft Sentinel).	10	Single-select	Microsoft Sentinel workspace / Azure Monitor Log Analytics workspace / Purview Audit Log / Third-party SIEM (specify) / Copilot Studio built-in analytics only	Azure Monitor Log Analytics	Always	No	Stage 5 Review	InfoSec	Microsoft Sentinel docs; novel-by-author
OH-003	Operational Handoff	What inactivity threshold should trigger automatic deprovisioning of this agent (no conversations, no runs) — for example, 90 days of zero activity?	Inactivity-based deprovisioning prevents orphaned agents from accumulating stale permissions and consuming capacity. The agent-365-lifecycle-governance solution enforces this threshold automatically.	10	Single-select	30 days / 60 days / 90 days / 180 days / 365 days / Manual deprovisioning only	90 days	Always	No	Stage 2 Capture	Maker + Sponsor	Novel-by-author
OH-004	Operational Handoff	What should happen to this agent if the named business owner (SP-002) leaves the firm or changes roles?	Owner departure without a transfer plan leaves the agent orphaned, with no one accountable for supervision obligations. agent-365-lifecycle-governance monitors owner-departure signals from Entra and triggers the transfer workflow.	10	Single-select	Auto-suspend and notify business unit head / Transfer to secondary owner (MR-005) / Auto-deprovision after 30-day grace / Escalate to Compliance for manual decision	Transfer to secondary owner	Always	No	Stage 2 Capture	Sponsor	Novel-by-author
OH-005	Operational Handoff	Who is the named secondary owner or successor who will inherit operational accountability if the primary business owner (SP-002) is unavailable?	A defined successor prevents governance gaps during business-owner leave, departure, or role change. Without a successor, the agent enters an unowned state that violates FINRA 3110 supervision-assignment requirements. 
10	Free text	Valid firm employee UPN; must differ from SP-002	n/a	Always	No	Stage 2 Capture	Sponsor	FINRA 3110 
; novel-by-author
OH-006	Operational Handoff	What are the success criteria — quantitative or qualitative — that will be used in the 90-day post-go-live review to determine whether the agent continues operating?	SR 11-7 principles require ongoing monitoring with defined performance thresholds. The 90-day review is the first formal checkpoint to validate that the agent is performing as intended and has not exhibited scope drift. 
10, 12	Free text	Minimum 1 measurable KPI required; max 2,000 chars	n/a	Always	No	Stage 2 Capture	Maker + Sponsor	SR 11-7 
; novel-by-author
OH-007	Operational Handoff	What circuit-breaker or kill-switch conditions should trigger automatic suspension of this agent without waiting for human review?	Automated kill-switch conditions (e.g., anomalous action volume spike, sensitivity-label violation detected, DLP policy breach) enable rapid response to a runaway or compromised agent. The compliance-dashboard and scope-drift monitoring solutions consume these conditions.	2, 10	Multi-select	Anomalous action-volume spike (> 3x 7-day average) / DLP policy breach detected / Sensitivity-label violation / Entra Agent ID credential compromise alert / Agent owner account disabled / Manual only	Anomalous action-volume spike, DLP policy breach	Always	No	Stage 2 Capture	InfoSec	Novel-by-author
OH-008	Operational Handoff	Should this agent be registered in the firm's ServiceNow CMDB or equivalent configuration management database as a configuration item?	CMDB registration makes the agent discoverable in the firm's IT asset inventory, links it to change records, and enables impact analysis during incidents. Without CMDB registration, the agent is invisible to IT operations and change-advisory-board processes.	10, 11	YES-NO	Yes / No	Yes (if ZN = Team or Enterprise)	Conditional on ZN-001 result	No	Stage 5 Review	IT Operations	Novel-by-author; DS-019
OH-009	Operational Handoff	Will this agent need a formal change-management record (Request for Change / RFC) in the firm's ITSM platform before each promotion from dev → test → production?	RFC-gated promotions ensure that production deployments of regulated agents are subject to the same change-advisory-board approval as other production changes, satisfying SOX 302/404 IT-general-controls requirements.	10	YES-NO	Yes / No	Yes (if RT = Tier 1 or Tier 2)	Conditional on RT outcome	No	Stage 5 Review	IT Operations	SOX 302/404; novel-by-author
OH-010	Operational Handoff	What is the decommissioning data-handling plan — what happens to Dataverse data, knowledge-base content, conversation history, and credentials when the agent is deprovisioned?	Decommissioning without a data-handling plan can leave orphaned NPI or PCI data in Dataverse or Azure storage, creating a GLBA compliance liability. All agent-associated data stores must be covered by a deletion or archive-and-transfer plan.	9, 10	Single-select	Delete all data immediately / Archive to long-term immutable storage per retention schedule / Transfer ownership to successor / Retention schedule governs — no extra action needed	Retention schedule governs	Always	No	Stage 2 Capture	Maker + Records	GLBA 501(b); novel-by-author
OH-011	Operational Handoff	Does the agent require a periodic access review (recertification) of its connected data sources and granted permissions — and if so, how frequently?	Periodic recertification of agent permissions prevents privilege creep (accumulation of excess permissions over time) and is a compensating control required under GLBA 501(b) safeguards and NIST AI RMF Govern 1.7.	2, 7, 10	Single-select	Quarterly / Semi-annually / Annually / Only at ownership change / Not required	Annually	Always	No	Stage 2 Capture	Sponsor	GLBA 501(b); NIST AI RMF; novel-by-author
OH-012	Operational Handoff	Should Microsoft Entra Agent ID be minted for this agent at handoff, and should the agent's workload identity be issued a certificate or federated credential rather than a client secret?	Entra Agent ID (GA May 1, 2026) provides a first-class workload identity for agents, enabling Conditional Access policies, audit trails, and phishing-resistant authentication. Client-secret-based identities are deprecated for new agents under firm policy. 
7, 10	YES-NO	Yes — mint Entra Agent ID with federated credential / Yes — mint with certificate / No — use existing service principal (document justification)	Yes — federated credential	Always	Partial — check existing service principals via Graph /v1.0/servicePrincipals?$filter=displayName eq '{agentName}' 
Stage 5 Review	System	Entra Agent ID 
Conflicts / Dependencies (CD)
ID	Category	Question Text	Why It Matters	Decisions Driven	Answer Type	Allowed Values / Validation	Default	Required?	Auto-detectable?	Stage	Asked of	Source Citation
CD-001	Conflicts / Deps	In 2–5 plain-English sentences, describe what this agent does so it can be checked for similarity against existing registered agents.	Semantic-similarity deduplication prevents multiple teams from building overlapping agents that consume redundant capacity, confuse users, and create inconsistent compliance postures. The agent-registry-automation solution seeds the duplicate-check vector search from this text.	11	Free text	50–500 chars; plain English; no jargon	n/a	Always	No	Stage 2 Capture	Maker	Novel-by-author
CD-002	Conflicts / Deps	Is the maker aware of any existing agent, bot, or automation in the firm that does something similar to this proposed agent?	Maker awareness of potential duplicates accelerates the deduplication check and may lead to extending an existing agent rather than building a new one, reducing governance overhead and cost.	11	YES-NO + free text	Yes (describe in text field) / No / Not sure	Not sure	Always	No	Stage 2 Capture	Maker	Novel-by-author
CD-003	Conflicts / Deps	Does this agent depend on the output or availability of another agent or automation (an upstream dependency) — for example, it receives a structured input from an orchestrator agent or a scheduled Power Automate flow?	Upstream dependencies mean this agent inherits the risk posture and data-access scope of its orchestrator. If the upstream agent is Tier-1, this agent's Tier cannot be lower than Tier-2 without explicit risk-acceptance.	11	YES-NO	Yes (identify upstream agent ID) / No	No	Always	No	Stage 2 Capture	Maker	Novel-by-author; Entra Agent ID 
CD-004	Conflicts / Deps	Do any downstream systems, teams, or automations depend on this agent's output — for example, a downstream Power Automate flow that reads this agent's responses, or a dashboard that consumes its structured outputs?	Downstream dependencies affect the blast radius of agent failure or deprovisioning. The environment-lifecycle-management solution's deprovisioning workflow must notify dependent system owners before the agent is retired.	10, 11	YES-NO + free text	Yes (describe downstream consumers) / No	No	Always	No	Stage 2 Capture	Maker	Novel-by-author
CD-005	Conflicts / Deps	Does this agent interact with, or pass data to, another AI agent within or outside the firm's tenant (agent-to-agent communication)?	Agent-to-agent data flows are an uncontrolled data-egress vector. A child agent can acquire the orchestrator's delegated permissions transitively, potentially accessing data it was not individually authorized to access. This is the top gap in all vendor templates reviewed. 
2, 4, 8, 11	YES-NO	Yes (identify counterpart agent) / No	No	Always	No	Stage 2 Capture	Maker	Entra Agent ID 
; security advisory 
; novel-by-author
CD-006	Conflicts / Deps	Are there regulatory, contractual, or policy constraints that prevent using AI for this specific use case — for example, a client contract that prohibits automated decision-making, or an information-barrier rule that prevents this data from being combined with other data in the LLM context window?	Regulatory or contractual prohibitions must be identified at intake, not post-deployment. Legal and Compliance reviews are the gatekeepers; this question ensures their review is triggered when relevant.	6, 11	YES-NO + free text	Yes (describe constraint) / No / Not sure	Not sure	Always	No	Stage 2 Capture	Maker + Legal	Novel-by-author
CD-007	Conflicts / Deps	Does this agent's intended use case overlap with a use case currently under review or recently rejected by the AI governance committee?	Re-submitting a recently rejected use case under a different name wastes reviewer time and undermines governance credibility. agent-registry-automation checks the rejection log as part of the duplicate-detection process.	11	YES-NO	Yes / No / Unknown	Unknown	Always	Partial — auto-check against agent registry rejection log	Stage 3 Auto-classify	System	Novel-by-author
CD-008	Conflicts / Deps	Does the agent consume any licensed data feeds (e.g., Bloomberg, Refinitiv, Morningstar, FactSet) whose terms of service restrict use for AI training or automated re-distribution?	Many financial data-feed license agreements explicitly prohibit feeding licensed data into LLM contexts or using it for AI-generated outputs distributed beyond the licensed user count. Violating these restrictions exposes the firm to license termination and contract damages.	6, 8, 11	YES-NO	Yes (identify feed and restriction) / No / Unknown	Unknown	Always	No	Stage 2 Capture	Maker + Legal + Procurement	Novel-by-author
CD-009	Conflicts / Deps	Will this agent's deployment require a change to an existing DLP policy, Conditional Access policy, or Entra application registration that affects other applications or users?	Policy changes with blast-radius beyond the agent itself require Change Advisory Board approval and must be modeled for unintended side effects on existing workloads.	3, 8, 11	YES-NO	Yes (describe change) / No / Unknown	Unknown	Always	No	Stage 2 Capture	InfoSec	Power Platform DLP 
; novel-by-author
CD-010	Conflicts / Deps	Does this agent need to integrate with an existing GRC or risk-management platform (e.g., Archer, ServiceNow GRC, MetricStream) to log risk-acceptance decisions, model-risk findings, or control attestations?	GRC-platform integration is required for Tier-1 and Tier-2 agents to maintain an auditable chain from intake → risk-acceptance decision → control implementation → ongoing monitoring in the firm's enterprise risk register.	10, 11	Single-select	ServiceNow GRC / Archer / MetricStream / Firm's internal GRC system (describe) / None	None	Always	No	Stage 2 Capture	Maker	Novel-by-author
Business Justification (BJ)
ID	Category	Question Text	Why It Matters	Decisions Driven	Answer Type	Allowed Values / Validation	Default	Required?	Auto-detectable?	Stage	Asked of	Source Citation
BJ-001	Business Justification	In plain language (max 500 characters), what problem does this agent solve, and why is an AI agent the right solution?	A clear problem statement is the primary input to the duplicate-agent deduplication check and the governance committee's prioritization scoring. It also establishes the documented purpose against which scope-drift is measured post-deployment.	11, 12	Free text	50–500 chars	n/a	Always	No	Stage 2 Capture	Maker	Novel-by-author
BJ-002	Business Justification	What is the total size of the target user population — the number of distinct people who will use this agent if fully deployed?	User-population size is a primary input to zone classification (Decision 5), capacity planning (EP-003), and ROI estimation. An agent targeting > 500 users is automatically Zone-1 (Enterprise).	5, 10, 12	Numeric	Integer ≥ 1	n/a	Always	No	Stage 2 Capture	Maker	Novel-by-author
BJ-003	Business Justification	How frequently will a typical user interact with this agent?	Interaction frequency, multiplied by user-population size, determines monthly conversation volume (EP-004) and drives capacity-allocation decisions. It also signals the intensity of supervisory monitoring required.	3, 12	Single-select	Multiple times per day / Once per day / A few times per week / Once per week / Once per month or less	A few times per week	Always	No	Stage 2 Capture	Maker	Novel-by-author
BJ-004	Business Justification	What measurable KPIs or OKRs will be used to evaluate whether the agent is delivering value — and what are the specific target values and measurement timeframes?	KPIs are the operational success criteria that drive the 90-day post-go-live review (OH-006) and justify continued capacity allocation. SR 11-7 principles require that model performance be measured against stated objectives. 
10, 12	Free text	At least 1 KPI with numeric target and timeframe; max 2,000 chars	n/a	Always	No	Stage 2 Capture	Maker + Sponsor	SR 11-7 
; novel-by-author
BJ-005	Business Justification	What is the estimated annual ROI or cost savings from this agent — in dollars or FTE hours saved?	ROI estimate enables the governance committee to prioritize high-value use cases and to assess whether the cost of governance controls (MRM review, dedicated environment, compliance monitoring) is proportionate to the business benefit.	12	Single-select	Under $50K annual value / $50K–$500K / $500K–$5M / Over $5M / Unable to quantify at this stage	Unable to quantify	Optional	No	Stage 2 Capture	Maker + Sponsor	Novel-by-author
BJ-006	Business Justification	What alternatives were considered before choosing an AI agent — for example, a non-AI automation, a Power Automate flow, a new UI feature, or a process change — and why were they rejected?	Documenting considered alternatives demonstrates that the AI solution is the right tool for the problem, not simply an AI-for-AI's-sake choice. This satisfies ISO/IEC 42001 Article 6.1 risk-and-opportunity assessment requirements.	12	Free text	Max 1,000 chars	n/a	Optional	No	Stage 2 Capture	Maker	ISO/IEC 42001; novel-by-author
BJ-007	Business Justification	What is the regulatory or compliance driver (if any) for this agent — is it being built to satisfy a regulatory requirement, an audit finding, a consent-order remediation, or a risk-committee mandate?	Regulatory-driven agents may have non-negotiable go-live deadlines and elevated documentation requirements. They should be flagged for expedited review track and their intake records must cross-reference the specific regulatory citation or audit finding.	6, 12	Single-select	Regulatory requirement (cite rule/notice) / Audit finding remediation / Consent-order or enforcement action / Risk-committee mandate / Business efficiency / No regulatory driver	Business efficiency	Always	No	Stage 2 Capture	Maker + Sponsor	Novel-by-author
BJ-008	Business Justification	Has this use case been reviewed or approved in principle by any senior stakeholder (e.g., CTO, CDO, CRO, CIO, Chief Compliance Officer) prior to this intake submission?	Pre-approved use cases from senior stakeholders should be flagged to avoid the governance process inadvertently blocking a firm-priority initiative. The flag is informational only — it does not bypass the intake controls.	6, 12	YES-NO + free text	Yes (name approver and date) / No	No	Optional	No	Stage 2 Capture	Maker	Novel-by-author
BJ-009	Business Justification	What is the anticipated end-of-life or sunset date for this agent — is it a permanent production tool, a time-limited pilot, or a proof-of-concept with a defined expiry?	Sunset date drives the deprovisioning trigger configuration in agent-365-lifecycle-governance and determines whether a full Tier-1 review is warranted for a short-lived POC. Time-limited agents receive a conditional approval with an embedded expiry date in the registry.	10, 12	Single-select	Permanent (no planned sunset) / Time-limited pilot (specify end date) / Proof-of-concept (expires in 90 days) / Unknown	Unknown	Always	No	Stage 2 Capture	Maker	Novel-by-author
BJ-010	Business Justification	What is the target business unit or team that will be the primary beneficiary of this agent (may differ from the maker's own team)?	The beneficiary business unit's compliance officer has supervisory jurisdiction and must be included in the review workflow even if they are not the maker or sponsor.	6, 12	Free text	Valid department or team name from HR system	Maker's own department	Always	Partial — pre-fill from SP-003 if same as maker's department	Stage 2 Capture	Maker	Novel-by-author
BJ-011	Business Justification	Has the proposed agent been through any proof-of-concept or prototype testing prior to this formal intake submission — and if so, what environment was it tested in and what data was used?	Shadow IT discovery: agents built and tested outside approved environments may have already processed regulated data without proper controls. Any prior testing in an unapproved environment must be disclosed and reviewed by InfoSec and Privacy before the formal approval proceeds.	3, 4, 12	YES-NO + free text	Yes (describe environment and data used) / No	No	Always	No	Stage 2 Capture	Maker	Novel-by-author; Power Platform governance 
BJ-012	Business Justification	Does the maker acknowledge and accept the firm's AI Acceptable Use Policy, and confirm that the described agent is consistent with firm values and the Microsoft Responsible AI Standard?	Formal acknowledgment of the AI AUP creates a documented attestation by the maker and is the final required field before the intake form is submitted for sponsor review. It supports SOX 302 sub-certification chains.	6, 9, 12	YES-NO	Yes (I confirm) / No (I have questions — describe)	n/a	Always	No	Stage 2 Capture	Maker	Microsoft Responsible AI Standard; SOX 302; novel-by-author
Catalog Summary at End of Part 2
Category	IDs	Count
Agent Type (AT)	AT-001 – AT-010	10
Controls (CT)	CT-001 – CT-017	17
Environment Placement (EP)	EP-001 – EP-012	12
Risk Tier (RT)	RT-001 – RT-010	10
Zone (ZN)	ZN-001 – ZN-006	6
Sponsor (SP)	SP-001 – SP-010	10
Maker Role (MR)	MR-001 – MR-008	8
Data Source / Connector / Action (DS)	DS-001 – DS-020	20
Records / Retention (RR)	RR-001 – RR-010	10
Operational Handoff (OH)	OH-001 – OH-012	12
Conflicts / Dependencies (CD)	CD-001 – CD-010	10
Business Justification (BJ)	BJ-001 – BJ-012	12
TOTAL		137
Auto-detectable (Yes or Partial): 43 of 137 questions — these are pre-filled by system and not presented to the maker

---

## Part 3 — Sections 4-6 (coverage matrix, auto-detect playbook, disqualifiers)

No additional searches needed — all source material is in hand. Here is Part 3: Sections 4–6.

Part 3 — Coverage Matrix, Auto-Detect Playbook & Disqualifier Rules
4. Cross-cutting Coverage Matrix
For each of the 12 decisions, every question ID that drives it is listed. Decisions with fewer than 3 supporting questions are flagged ⚠️ (none are under-covered in this catalog).

Decision #	Decision Name	Driving Question IDs	Count
1	Agent-type recommendation	AT-001, AT-002, AT-003, AT-004, AT-005, AT-006, AT-007, AT-008, AT-009, AT-010, MR-002, MR-003, MR-004	13
2	Controls / guardrails to enable	AT-001, AT-007, AT-008, AT-010, CT-001, CT-002, CT-003, CT-004, CT-005, CT-006, CT-007, CT-008, CT-009, CT-010, CT-011, CT-012, CT-013, CT-014, CT-015, CT-016, CT-017, DS-003, DS-009, DS-010, DS-014, DS-015, DS-017, DS-018, OH-007, RT-001, RT-002, RT-006, RR-009, ZN-004, MR-008, CD-005, CD-009	37
3	Environment placement	AT-003, AT-010, DS-005, DS-007, DS-013, EP-001, EP-002, EP-003, EP-004, EP-005, EP-006, EP-007, EP-008, EP-009, EP-010, EP-011, EP-012, ZN-001, ZN-003, ZN-004, ZN-005, BJ-011	22
4	Risk tier (1/2/3)	AT-001, AT-004, AT-007, AT-008, CT-001, CT-002, CT-005, CT-006, CT-007, CT-013, DS-003, DS-009, DS-014, DS-016, DS-017, RT-001, RT-002, RT-003, RT-004, RT-005, RT-006, RT-007, RT-008, RT-009, RT-010, SP-004, SP-005	27
5	Zone classification (1/2/3)	AT-003, AT-010, EP-003, RT-004, RT-010, ZN-001, ZN-002, ZN-003, ZN-004, ZN-005, ZN-006, BJ-002	12
6	Sponsor / approver routing	AT-001, AT-010, CT-002, CT-005, CT-006, CT-007, MR-008, RT-001, RT-003, RT-004, RT-005, RT-007, RT-008, RT-009, SP-001, SP-002, SP-003, SP-004, SP-005, SP-006, SP-007, SP-008, SP-009, SP-010, BJ-007, BJ-008, CD-006, CD-010	28
7	Maker role grant	AT-002, AT-005, AT-009, AT-010, EP-011, MR-001, MR-002, MR-003, MR-004, MR-005, MR-006, MR-007, MR-008, OH-011, OH-012, ZN-002	16
8	Connector / action / data-source approval	AT-007, AT-010, CT-001, CT-002, CT-003, CT-004, CT-012, DS-001, DS-002, DS-003, DS-004, DS-005, DS-006, DS-007, DS-008, DS-009, DS-010, DS-011, DS-012, DS-013, DS-014, DS-015, DS-016, DS-017, DS-018, DS-019, DS-020, EP-010, RT-008, RT-009, ZN-005, CD-005, CD-008, CD-009	34
9	Records & retention	CT-006, CT-010, CT-011, CT-012, DS-016, DS-020, OH-010, RR-001, RR-002, RR-003, RR-004, RR-005, RR-006, RR-007, RR-008, RR-009, RR-010, SP-008	18
10	Operational handoff	DS-019, EP-005, EP-006, EP-008, EP-009, EP-012, OH-001, OH-002, OH-003, OH-004, OH-005, OH-006, OH-007, OH-008, OH-009, OH-010, OH-011, OH-012, RT-007, SP-002, BJ-009, CD-003, CD-004, CD-010	24
11	Conflicts & dependencies	AT-007, BJ-001, CD-001, CD-002, CD-003, CD-004, CD-005, CD-006, CD-007, CD-008, CD-009, CD-010, DS-019, EP-007	14
12	Business justification & success metrics	AT-009, BJ-001, BJ-002, BJ-003, BJ-004, BJ-005, BJ-006, BJ-007, BJ-008, BJ-009, BJ-010, BJ-011, BJ-012, EP-003, EP-004, OH-006, RT-007, SP-003	18
Coverage verdict: Every decision is supported by ≥ 10 question IDs. No decision is under-covered. The two densest decision areas are Decision 2 (Controls — 37 questions) and Decision 8 (Connectors/Data Sources — 34 questions), which is appropriate given the regulatory density of those domains.

5. Auto-Detect Playbook
For every question marked Auto-detectable: Yes or Partial, the exact API call, required OAuth scopes, and sample response shape are provided. All Microsoft Graph calls use https://graph.microsoft.com as the base URL. Power Platform Admin API base: https://api.bap.microsoft.com. Purview API base: https://purview.microsoft.com.

AT-009 — M365 Copilot license check
Question: What M365 Copilot licensing does the target user population currently hold?

API call:

text
GET https://graph.microsoft.com/v1.0/users/{userId}/licenseDetails
Required scopes: User.Read.All (application) or User.Read (delegated for self-check)

Filter logic: Look for skuPartNumber containing MICROSOFT_365_COPILOT or COPILOT_FOR_MICROSOFT_365

Sample response shape:

json
{
  "value": [
    {
      "id": "...",
      "skuId": "639dec6b-bb19-468b-871c-c5c441c4b0cb",
      "skuPartNumber": "MICROSOFT_365_COPILOT",
      "servicePlans": [
        { "servicePlanName": "M365_COPILOT", "provisioningStatus": "Success" }
      ]
    }
  ]
}
Pre-fill logic: If provisioningStatus = Success → pre-fill "All users have M365 Copilot" (for the requesting user). For population-level check, run in batch via $batch endpoint.

MR-001 — Maker's existing Power Platform environment access
Question: Does the maker currently have access to a Power Platform environment?

API call:

text
GET https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments
    ?$filter=properties/createdBy/userId eq '{aadUserId}'
    &api-version=2021-04-01
Required scopes: https://service.powerapps.com/.default (application) or Power Platform Admin role

Sample response shape:

json
{
  "value": [
    {
      "name": "env-guid",
      "properties": {
        "displayName": "Dev - Jane Smith",
        "environmentSku": "Developer",
        "provisioningState": "Succeeded",
        "createdBy": { "userId": "aad-guid", "userPrincipalName": "jane@firm.com" }
      }
    }
  ]
}
Pre-fill logic: If value is non-empty → pre-fill environment type from environmentSku. If empty → default "No existing access".

MR-002 — Copilot Studio license check
Question: Does the maker have an active Copilot Studio license?

API call:

text
GET https://graph.microsoft.com/v1.0/users/{userId}/licenseDetails
Required scopes: User.Read.All

Filter logic: Look for skuPartNumber containing POWER_VIRTUAL_AGENTS_VIRAL, POWER_VIRTUAL_AGENTS, or COPILOT_STUDIO

Sample response shape: Same structure as AT-009 above; check skuPartNumber value.

MR-003 — M365 Copilot license check (same call as AT-009, reused for MR)
Reuse: Identical to AT-009 API call. Cache result from AT-009 — do not re-call. Pre-fill YES if MICROSOFT_365_COPILOT license present with provisioningStatus = Success.

MR-004 — Azure AI Foundry project access
Question: Does the maker need Azure AI Foundry project access?

API call (check existing role assignments):

text
GET https://management.azure.com/subscriptions/{subscriptionId}
    /resourceGroups/{resourceGroupName}
    /providers/Microsoft.MachineLearningServices/workspaces/{workspaceName}
    /providers/Microsoft.Authorization/roleAssignments
    ?$filter=assignedTo('{aadUserId}')
    &api-version=2022-04-01
Required scopes: https://management.azure.com/.default with Microsoft.Authorization/roleAssignments/read RBAC permission

Relevant role IDs:

Azure AI Developer: 64702f94-c441-49e6-a78b-ef80e0188fee

Azure AI Inference Deployment Operator: 3afb7f49-54cb-416e-8c09-6dc049efa503

Sample response shape:

json
{
  "value": [
    {
      "properties": {
        "roleDefinitionId": "/providers/Microsoft.Authorization/roleDefinitions/64702f94-...",
        "principalId": "aad-guid",
        "scope": "/subscriptions/.../workspaces/my-foundry-project"
      }
    }
  ]
}
Pre-fill logic: If role assignment present → pre-fill YES with existing project name. If empty → pre-fill NO.

MR-007 — Existing service principal check
Question: Does this agent require a dedicated service account or non-interactive identity?

API call:

text
GET https://graph.microsoft.com/v1.0/servicePrincipals
    ?$filter=displayName eq '{proposedAgentName}'
    &$select=id,displayName,appId,createdDateTime,accountEnabled
Required scopes: Application.Read.All

Sample response shape:

json
{
  "value": [
    {
      "id": "sp-guid",
      "displayName": "AI Agent - Trade Desk Assistant",
      "appId": "app-guid",
      "createdDateTime": "2025-11-01T00:00:00Z",
      "accountEnabled": true
    }
  ]
}
Pre-fill logic: If match found → surface to maker for confirmation of reuse vs. new identity. If empty → auto-queue Entra Agent ID minting at OH-012.

SP-001 — Manager pre-fill (Sponsor)
Question: Who is the named business sponsor?

API call:

text
GET https://graph.microsoft.com/v1.0/users/{makerId}/manager
    ?$select=displayName,userPrincipalName,jobTitle,department
Required scopes: User.Read.All

Sample response shape:

json
{
  "displayName": "Robert Chen",
  "userPrincipalName": "rchen@firm.com",
  "jobTitle": "Managing Director, Equities",
  "department": "Equities Trading"
}
Pre-fill logic: Pre-fill SP-001 with manager UPN; maker can override if the actual sponsor is a different person.

SP-003 — Department / cost-center pre-fill
Question: What business unit, cost center, and department owns this agent?

API call:

text
GET https://graph.microsoft.com/v1.0/users/{makerId}
    ?$select=department,companyName,officeLocation,employeeId
Required scopes: User.Read (delegated)

Sample response shape:

json
{
  "department": "Fixed Income Research",
  "companyName": "Acme Securities LLC",
  "officeLocation": "New York",
  "employeeId": "EMP-004821"
}
Pre-fill logic: Pre-fill department; cost center must be resolved by joining employeeId to HRIS (out-of-tenant; use Power Automate lookup action at intake form load).

CT-012 / DS-002 — Purview sensitivity scan of listed knowledge sources
Question: Do knowledge sources contain sensitivity-labeled content?

API call (scan SharePoint site for labeled items):

text
GET https://purview.microsoft.com/catalog/api/search/query
Request body:

json
{
  "keywords": "*",
  "limit": 1,
  "filter": {
    "and": [
      { "attributeName": "assetType", "operator": "eq", "attributeValue": "SharePoint" },
      { "attributeName": "sensitivityLabel", "operator": "ne", "attributeValue": null }
    ]
  },
  "facets": [{ "facet": "sensitivityLabel", "count": 10 }]
}
Required scopes: https://purview.azure.net/.default with Data Reader role on the Purview account

Sample response shape:

json
{
  "facetResults": [
    { "facetName": "sensitivityLabel", "count": 847, "value": "Confidential" },
    { "facetName": "sensitivityLabel", "count": 23, "value": "Highly Confidential" }
  ]
}
Pre-fill logic: If any Confidential or Highly Confidential items found in the declared sources → pre-fill CT-012=Yes and DS-002=Highly Confidential for that source. Maker must confirm.

EP-010 — DLP policy group pre-fill
Question: Which DLP policy group should govern this environment?

API call (list tenant DLP policies):

text
GET https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/apiPolicies
    ?api-version=2021-04-01
Required scopes: Power Platform Admin role

Sample response shape:

json
{
  "value": [
    {
      "name": "policy-guid",
      "properties": {
        "displayName": "Restricted-NPI-Production",
        "environmentType": "AllEnvironments",
        "connectorGroups": [
          { "classification": "Business", "connectors": [ { "id": "shared_office365" } ] },
          { "classification": "Blocked", "connectors": [ { "id": "shared_twitter" } ] }
        ]
      }
    }
  ]
}
Pre-fill logic: Present existing policy names in the single-select dropdown for EP-010. InfoSec selects the applicable one; new-policy option triggers a separate policy-creation workflow.

RR-004 — Purview retention label pre-fill
Question: What Purview retention label should be applied?

API call:

text
GET https://graph.microsoft.com/beta/security/labels/retentionLabels
    ?$select=displayName,id,retentionDuration,actionAfterRetentionPeriod
Required scopes: RecordsManagement.Read.All

Sample response shape:

json
{
  "value": [
    {
      "id": "label-guid",
      "displayName": "SEC-17a4-7yr-WORM",
      "retentionDuration": { "days": 2555 },
      "actionAfterRetentionPeriod": "delete"
    },
    {
      "id": "label-guid-2",
      "displayName": "FINRA-4511-3yr",
      "retentionDuration": { "days": 1095 },
      "actionAfterRetentionPeriod": "delete"
    }
  ]
}
Pre-fill logic: Populate RR-004 dropdown dynamically from this response. Records team selects the applicable label during Stage 5 Review.

OH-012 — Entra Agent ID / service principal existence check
Question: Should Microsoft Entra Agent ID be minted for this agent?

API call (check existing agent identities):

text
GET https://graph.microsoft.com/v1.0/applications
    ?$filter=displayName eq '{proposedAgentName}'
    &$select=id,displayName,appId,createdDateTime,requiredResourceAccess
Required scopes: Application.Read.All

Entra Agent ID minting call (at handoff):

text
POST https://graph.microsoft.com/v1.0/applications
Content-Type: application/json

{
  "displayName": "AgentID-{AgentRegistryID}-{AgentName}",
  "description": "Entra Agent ID for {AgentName} — provisioned by agent-registry-automation",
  "tags": ["AgentIdentity", "FSI-Governance", "Tier:{tier}", "Zone:{zone}"],
  "requiredResourceAccess": []
}
Required scopes for minting: Application.ReadWrite.All

Sample minting response shape:

json
{
  "id": "app-object-id",
  "appId": "client-id-guid",
  "displayName": "AgentID-REG-0042-TradeAssist",
  "createdDateTime": "2026-05-01T00:00:00Z"
}
Post-mint: Create a federated credential against the Power Platform / Foundry managed identity using:

text
POST https://graph.microsoft.com/v1.0/applications/{id}/federatedIdentityCredentials
Content-Type: application/json

{
  "name": "pp-env-federated",
  "issuer": "https://token.botframework.com/",
  "subject": "{environmentId}",
  "audiences": ["api://AzureADTokenExchange"]
}
DS-012 — Graph API application permissions check
Question: Will the agent use Microsoft Graph API endpoints?

API call:

text
GET https://graph.microsoft.com/v1.0/applications/{appId}/requiredResourceAccess
Required scopes: Application.Read.All

Sample response shape:

json
{
  "value": [
    {
      "resourceAppId": "00000003-0000-0000-c000-000000000000",
      "resourceAccess": [
        { "id": "df021288-bdef-4463-88db-98f22de89214", "type": "Role" },
        { "id": "e1fe6dd8-ba31-4d61-89e7-88639da4683d", "type": "Scope" }
      ]
    }
  ]
}
Pre-fill logic: If type = Role (application permission, not delegated) → auto-flag to credential-oversharing-detector and pre-fill DS-012=Yes with a warning note.

DS-008 — Connector inventory pre-fill (agents already in development)
Question: List every Power Platform connector the agent will use.

API call (if Copilot Studio bot already exists):

text
GET https://api.bap.microsoft.com/providers/Microsoft.PowerApps/environments/{environmentId}
    /connections?api-version=2020-06-01
    &$filter=properties.createdBy/id eq '{aadUserId}'
Required scopes: Power Platform Admin role

Sample response shape:

json
{
  "value": [
    {
      "name": "shared-sharepointonline-guid",
      "properties": {
        "displayName": "SharePoint",
        "apiId": "/providers/Microsoft.PowerApps/apis/shared_sharepointonline",
        "connectionParameters": { "siteUrl": "https://firm.sharepoint.com/sites/Research" }
      }
    }
  ]
}
Pre-fill logic: If agent is already in a dev environment, pre-populate DS-008 with detected connectors. Maker confirms and adds any not yet connected.

6. Disqualifier Rules
These are the if-then logic rules that turn intake answers into hard platform rule-outs. Downstream logic in agent-registry-automation evaluates these in order; the first matching disqualifier for a platform eliminates it from the recommendation set.

Platform: M365 Agent Builder
Rule AB-DQ-1 (Autonomous external action):

text
IF AT-001 = Yes (autonomous external action required)
THEN Agent Builder is DISQUALIFIED
REASON: Agent Builder uses the M365 Copilot Sydney orchestrator, which has no 
        runtime action-confirmation or HITL-gate capability for external tool calls.
Rule AB-DQ-2 (Non-Microsoft LLM):

text
IF AT-002 = Yes (BYO-LLM required)
THEN Agent Builder is DISQUALIFIED
REASON: Agent Builder is bound exclusively to Microsoft-hosted models in M365 Copilot; 
        no LLM override is supported.
Rule AB-DQ-3 (Custom orchestration):

text
IF AT-004 = Yes (custom orchestration logic required)
THEN Agent Builder is DISQUALIFIED
REASON: Agent Builder provides no orchestration customization beyond the Sydney defaults.
Rule AB-DQ-4 (Non-M365-Copilot surface):

text
IF AT-003 NOT IN [M365 Copilot chat, Microsoft Teams]
THEN Agent Builder is DISQUALIFIED
REASON: Agent Builder agents only surface inside the M365 Copilot chat experience and Teams.
Rule AB-DQ-5 (No M365 Copilot license):

text
IF AT-009 = No users have M365 Copilot
THEN Agent Builder is DISQUALIFIED
REASON: Agent Builder requires an M365 Copilot license for every consuming user.
Rule AB-DQ-6 (Real-time event trigger):

text
IF AT-008 = Yes (event-triggered / streaming)
THEN Agent Builder is DISQUALIFIED
REASON: Agent Builder is conversation-initiated only; no event-trigger capability.
Rule AB-DQ-7 (External user access):

text
IF AT-010 = Yes (external/non-tenant users)
THEN Agent Builder is DISQUALIFIED
REASON: Agent Builder is scoped to the M365 tenant; external user access is not supported.
Platform: M365 Declarative Agent (Copilot extensibility)
Rule DA-DQ-1 (Autonomous external action):

text
IF AT-001 = Yes (autonomous external action required)
THEN Declarative Agent is DISQUALIFIED
REASON: Declarative agents rely on the M365 Copilot orchestrator, which cannot 
        execute HITL-gated tool calls autonomously. All actions are user-initiated 
        within a single conversation turn.
Rule DA-DQ-2 (Non-Microsoft LLM):

text
IF AT-002 = Yes (BYO-LLM)
THEN Declarative Agent is DISQUALIFIED
REASON: Declarative agents use the M365 Copilot foundation model only; 
        no LLM substitution is possible.
Rule DA-DQ-3 (Custom orchestration):

text
IF AT-004 = Yes (custom orchestration)
THEN Declarative Agent is DISQUALIFIED
REASON: Declarative agents have no custom orchestration layer.
Rule DA-DQ-4 (Real-time event trigger):

text
IF AT-008 = Yes
THEN Declarative Agent is DISQUALIFIED
REASON: Declarative agents are conversation-initiated only.
Rule DA-DQ-5 (No M365 Copilot license — population-level):

text
IF AT-009 = No users have M365 Copilot
THEN Declarative Agent is DISQUALIFIED
REASON: Requires M365 Copilot license for every consuming user.
Rule DA-DQ-6 (External users):

text
IF AT-010 = Yes
THEN Declarative Agent is DISQUALIFIED
REASON: Declarative agents are tenant-scoped; external user access not supported 
        without additional Azure AD B2C configuration (not currently supported in GA).
Rule DA-DQ-7 (Non-Teams/M365 surface):

text
IF AT-003 NOT IN [M365 Copilot chat, Microsoft Teams, SharePoint]
THEN Declarative Agent is DISQUALIFIED
REASON: Declarative agents are only renderable in M365 Copilot surfaces.
Platform: Copilot Studio Classic Agent
Rule CS-DQ-1 (Non-Microsoft LLM with pro-developer requirements):

text
IF AT-002 = Yes AND AT-005 = Pro-developer
THEN Copilot Studio Classic is SOFT-DISQUALIFIED (custom-engine or Foundry preferred)
REASON: While Copilot Studio supports some BYO-LLM via custom generative actions, 
        pro-developer BYO-LLM at scale is better served by custom-engine agent or Foundry.
Rule CS-DQ-2 (Complex multi-agent orchestration):

text
IF AT-007 = Yes AND AT-004 = Yes (complex custom orchestration + agent-to-agent)
THEN Copilot Studio Classic is SOFT-DISQUALIFIED (Foundry preferred)
REASON: Copilot Studio orchestration capabilities are sufficient for simple 
        multi-agent hand-off but not for complex DAG-based or event-driven 
        multi-agent pipelines.
Rule CS-DQ-3 (No capacity):

text
IF EP-004 (monthly conversation volume) > 1,000,000 
AND EP-012 (dedicated capacity) = None
THEN Copilot Studio Classic is DISQUALIFIED pending capacity reservation
REASON: Without reserved Copilot Studio message capacity, the agent will be 
        throttled at high volume and cannot meet EP-005 production-availability requirements.
Platform: Copilot Studio Custom-Engine Agent
Rule CE-DQ-1 (No-code maker without pro-developer support):

text
IF AT-005 = No-code (no programming) 
AND MR-005 = No (no co-owner with pro-developer skills)
THEN Custom-Engine Agent is DISQUALIFIED
REASON: Custom-engine agents require SDK-level development (TypeScript/Python/C#); 
        no-code makers cannot build or maintain them.
Rule CE-DQ-2 (M365 Copilot surface only with no custom model need):

text
IF AT-003 IN [M365 Copilot chat, Microsoft Teams]
AND AT-002 = No (Microsoft-hosted models sufficient)
AND AT-004 = No (no custom orchestration)
THEN Custom-Engine Agent is SOFT-DISQUALIFIED (declarative agent preferred for simplicity)
REASON: Declarative agents are lower governance overhead when the M365 surface and 
        Microsoft models are sufficient.
Platform: Azure AI Foundry Agent
Rule FA-DQ-1 (No-code maker without pro-developer support):

text
IF AT-005 = No-code
AND MR-005 = No
THEN Azure AI Foundry Agent is DISQUALIFIED
REASON: Foundry agents require Azure SDK, Azure AI Studio, and infrastructure provisioning; 
        not accessible to no-code makers.
Rule FA-DQ-2 (No Azure subscription or Foundry project):

text
IF MR-004 = No (no Foundry access) 
AND SP-006 result does not include Azure provisioning approval
THEN Azure AI Foundry Agent is CONDITIONALLY DISQUALIFIED pending Azure provisioning
REASON: Foundry project must be provisioned before this platform is eligible.
Rule FA-DQ-3 (Data residency conflict):

text
IF EP-001 = Yes (US-only data residency) 
AND the only available Foundry region for the required model is non-US
THEN Azure AI Foundry Agent is DISQUALIFIED for that model selection
REASON: Model availability by Azure region may constrain Foundry eligibility; 
        maker must select a US-available model variant.
Combined Tier-Override Rules
Rule TIER-1-FORCE:

text
IF ANY OF:
  RT-001 = Yes (financial transaction authority)
  RT-005 = Yes (regulated decision)
  RT-003 = Over $1,000,000 (financial impact)
  DS-017 = Yes (financial-system write action)
THEN Risk Tier = 1 (override all other signals)
    AND HITL gating required on all write/send/financial-transaction actions (CT-007)
    AND MRM review required (SP-004 = Yes)
    AND InfoSec + Compliance + Legal parallel review required
Rule TIER-3-AUTO-APPROVE:

text
IF Risk Tier = 3
AND Zone = 3 (Personal)
AND CT-001 = No (no NPI)
AND CT-002 = No (no MNPI)
AND AT-001 = No (no autonomous external action)
AND RT-001 = No (no financial transaction)
AND Sponsor sign-off = obtained
THEN Auto-approve eligible
    AND InfoSec passive sample-log only (no active review required)
Rule ZONE-1-FORCE:

text
IF ANY OF:
  AT-010 = Yes (external users)
  ZN-004 = Yes (customer-facing portal)
  ZN-005 = Yes (cross-tenant sharing)
  EP-003 > 500 (monthly active users)
THEN Zone = 1 (Enterprise) — override all other signals
    AND Managed Environment required (EP-011 = Yes)
    AND Compliance review required (SP-009 = Yes)
Part 3 complete.

---

## Part 4 — Sections 7-10 (anti-patterns, gaps, open questions, bibliography)

No additional searches needed. Here is Part 4: Sections 7–10 — the final installment.

Part 4 — Anti-patterns, Coverage Gaps, Open Questions & Bibliography
7. Anti-patterns Observed in Existing Intake Processes
These are question types and design patterns that appear in existing CoE Starter Kit intake forms, vendor templates, and community intake examples — and that should be deliberately excluded from this catalog. Each anti-pattern is accompanied by a plain-language explanation of why it fails and what to replace it with.

AP-001 — Asking the maker "What tier is this agent?"
Anti-pattern: Presenting the risk-tier classification as a maker-answered question (e.g., "Is this a high-risk, medium-risk, or low-risk agent?").

Why it fails: Makers are incentivized to under-classify to reduce friction. Tier assignment must be a computed output of the classifier, not a maker-declared input. The CoE Starter Kit Innovation Backlog form makes this mistake — it asks the maker to self-classify their app/flow risk, resulting in systematic under-reporting.

Replace with: The RT-001 through RT-010 signal questions, which feed the auto-classifier. The tier result is shown to the maker as a read-only computed field, not an editable one.

AP-002 — Asking "Will your agent be compliant with FINRA Rule 3110?"
Anti-pattern: Asking makers to self-attest compliance with named regulatory rules they may not understand (e.g., "Does this agent comply with SEC Rule 17a-4?").

Why it fails: Makers are not compliance attorneys. A YES answer to a jargon-laden compliance question creates false assurance and is worthless as evidence in a regulatory examination. It also shifts liability to the maker inappropriately.

Replace with: The specific behavioral questions (CT-010 for transcript logging, RR-002 for retention period, RR-003 for WORM storage) that elicit the facts a compliance reviewer needs to make the compliance determination themselves.

AP-003 — Asking open-ended "What data does your agent use?"
Anti-pattern: A single free-text question asking the maker to describe all data their agent will use, without structured options.

Why it fails: Free-text data-description answers are inconsistent, incomplete, and cannot be processed programmatically to drive DLP policy assignment or sensitivity-label selection. Community intake templates frequently use this pattern because it requires no upfront taxonomy design.

Replace with: The structured DS-001 (multi-select data source list) + DS-002 (sensitivity classification per source) + DS-003/DS-004/CT-001 through CT-004 (specific data-type flags) combination, which produces machine-readable, actionable outputs.

AP-004 — Asking "Do you need a production environment?"
Anti-pattern: Asking makers to select environment type (Production / Sandbox / Developer) as the first environment question.

Why it fails: Makers universally select "Production" because it sounds more serious and they do not want a "lesser" environment. The real drivers of environment type — availability SLA (EP-005), ALM stage (EP-006), user population size (EP-003), and data sensitivity (DS-002) — must be collected first, then environment type is computed.

Replace with: The EP-001 through EP-012 signal questions that collectively determine environment placement, with environment type as a computed recommendation rather than a maker-declared choice.

AP-005 — Asking "Is this a Copilot Studio agent or a declarative agent?"
Anti-pattern: Asking the maker to name the platform type before the disqualifier questions have been run.

Why it fails: Most makers do not know the difference between a declarative agent, a custom-engine agent, and a Copilot Studio classic agent. Asking them to choose upfront produces random answers that then constrain the rest of the intake incorrectly. Vendor templates (including some ServiceNow AI Control Tower implementations) make this error.

Replace with: The AT-001 through AT-010 signal questions, which feed the disqualifier rules in Section 6, producing a recommended platform. The platform recommendation is then confirmed by the maker, not selected by them cold.

AP-006 — Asking "How sensitive is your data?" on a Likert scale
Anti-pattern: Presenting a 1–5 Likert scale for data sensitivity without anchored definitions.

Why it fails: Without anchored definitions (e.g., "5 = MNPI or PCI-in-scope data"), different makers interpret the scale entirely differently. A trader building an agent over their own positions and a marketing team building an agent over public brochures may both answer "3 — moderately sensitive" for completely different reasons.

Replace with: The specific binary flags CT-001 (NPI), CT-002 (MNPI), CT-003 (PCI), CT-004 (PHI), and DS-002 (per-source sensitivity classification against a defined taxonomy).

AP-007 — Asking "Will you follow the firm's AI policy?" as an attestation checkbox
Anti-pattern: Placing the AI Acceptable Use Policy attestation as the first or only governance question.

Why it fails: Leading with a checkbox attestation before any substantive questions are answered creates a paper-compliance façade. It is also psychologically anchoring — makers who have just checked "I agree" are less likely to disclose concerning details in subsequent questions.

Replace with: BJ-012 (the AUP acknowledgment) placed as the last question in the intake form, after all substantive questions have been answered. This ensures the maker has fully described their agent before attesting.

AP-008 — Asking "What is your agent's purpose?" with no minimum length or structure
Anti-pattern: A single short free-text "purpose" field with no length minimum and no semantic seed extraction.

Why it fails: "Research assistant" is a valid answer to this question but provides zero input to the semantic-similarity deduplication check, zero input to the risk classifier, and zero input to the compliance routing logic. This is the most common single-field intake anti-pattern seen in CoE Starter Kit and vendor templates.

Replace with: BJ-001 (50–500 char minimum, used as duplicate-check vector-search seed), supplemented by the structured signal questions that capture the specific behavioral attributes the purpose statement cannot reliably convey.

AP-009 — Asking makers to estimate "AI risk score" numerically
Anti-pattern: Asking "On a scale of 0–100, what is the risk score of this agent?" or similar numeric self-assessment.

Why it fails: Makers have no calibration reference for a numeric risk score. This produces meaningless ordinal data that cannot be compared across submissions or used for threshold-based routing decisions. Seen in several open-source governance templates on GitHub.

Replace with: The binary and single-select RT-001 through RT-010 signal questions that produce a computable Tier score via the auto-classifier.

AP-010 — Asking "Who are your stakeholders?" as a free-text field
Anti-pattern: A generic free-text field asking for a list of stakeholders without distinguishing sponsor, business owner, reviewer roles, or Entra UPN validation.

Why it fails: Unstructured stakeholder lists cannot drive automated routing in the review workflow. Without UPN validation, stakeholders may be entered with misspelled names or informal identifiers that cannot be resolved to Entra accounts.

Replace with: The structured SP-001 (sponsor UPN), SP-002 (business owner UPN), MR-005 (secondary maker UPN), and OH-005 (successor UPN) fields, each validated against Entra at form submission time.

AP-011 — Duplicating questions that are fully auto-detectable
Anti-pattern: Asking the maker "What Power Platform environment do you have access to?" when this is fully answerable from the Power Platform Admin API.

Why it fails: Asking humans questions that systems can answer exactly and instantly wastes maker time, introduces transcription errors, and creates inconsistency between declared and actual state. Every question in the CoE Starter Kit Innovation Backlog that asks about license type, existing environment, or department falls into this category.

Replace with: The 43 auto-detected fields in this catalog (Section 5). Present them to the maker as pre-filled read-only fields for confirmation, not as blank questions.

AP-012 — Asking "Do you need ongoing monitoring?" as YES/NO
Anti-pattern: A binary question asking whether the maker wants monitoring, implying it is optional.

Why it fails: Ongoing monitoring is not optional for regulated agents — it is a FINRA 3110 supervision requirement. Framing it as optional signals to makers that choosing NO is acceptable and may lead to compliance gaps.

Replace with: OH-002 (where monitoring logs are directed — a logistics question, not an opt-in question) combined with OH-007 (circuit-breaker conditions), both of which are required fields with no opt-out.

8. Coverage Gaps in Microsoft / Vendor / OSS Templates
What Existing Templates Miss (That This Catalog Covers)
Gap	Templates Affected	This Catalog's Response
MNPI-handling questions	All five Microsoft intake surfaces, AvePoint, ServiceNow AI Control Tower, Salesforce Agentforce ADLC	CT-002, DS-003: explicit MNPI flags with Reg FD / information-barrier routing
Agent-to-agent communication / orchestrator permission inheritance	All templates reviewed	AT-007, CD-005: dedicated A2A questions with Entra Agent ID scope-delegation review trigger 
Autonomous-action disqualifier for declarative agents	Microsoft Agent Builder UI, CoE Starter Kit, Copilot Studio Kit Compliance Hub	AT-001 + DA-DQ-1 disqualifier rule
Cross-border data flow as a standalone question	All templates reviewed	DS-011, EP-002: separate cross-border and data-residency questions
CFTC Rule 1.31 records question	All templates reviewed	RR-010: explicit CFTC flag for commodity-trading firms
Licensed data feed AI-use restriction check	All templates reviewed	CD-008: Bloomberg/Refinitiv/FactSet license-restriction question
Deprovisioning trigger and ownership-transfer plan	CoE Starter Kit partially addresses inactivity; all vendor templates omit	OH-003, OH-004, OH-005: full trio of deprovisioning triggers
Shadow-IT prior testing disclosure	All templates reviewed	BJ-011: disclosure of pre-intake POC environments and data used
Conflict-of-interest / segregation-of-duties check	All templates reviewed	MR-008: SoD conflict flag for maker in regulated domain
Circuit-breaker / kill-switch conditions	All templates reviewed	OH-007: kill-switch conditions as required intake field
GRC platform integration for risk-registry	ServiceNow AI Control Tower partially (self-referential)	CD-010: explicit GRC platform selection
Litigation hold check	All templates reviewed	RR-006: hold status check at intake, not just at eDiscovery event
Voice/audio record retention	All templates reviewed	RR-009: voice-channel specific retention question
Secondary owner / successor designation	CoE Starter Kit partially	MR-005, OH-005: co-owner and named successor
Inactivity threshold configuration	agent-365-lifecycle-governance solution handles detection but no intake input	OH-003: maker/sponsor configures threshold at intake
What Existing Templates Cover That We Should Confirm Is Present
Feature in Existing Templates	This Catalog's Coverage	Notes
Basic maker contact info and department	SP-003 (auto-detect), SP-001 (sponsor UPN)	Fully covered via Graph pre-fill 
App/agent display name and description	BJ-001, CD-001	Covered — BJ-001 enforces 50-char minimum for semantic search
Connector list declaration	DS-008	Covered with auto-detect pre-fill from Power Platform Admin API 
License check before environment creation	MR-002, MR-003	Covered via Graph license detection 
Business justification / value statement	BJ-001 through BJ-008	Fully covered — 8 questions in BJ category
Environment type selection	EP-005, EP-006 (computed, not maker-declared)	Covered — computed from signals, not freeform
DLP policy assignment	EP-010	Covered with admin pre-fill from Power Platform Admin API 
Sharing scope / audience	ZN-001 through ZN-006	Fully covered — 6 zone questions
Sensitivity label assignment	RR-004 (Records), CT-012 (knowledge sources)	Covered with Purview API pre-fill 
Sponsor approval workflow	SP-001 through SP-010	Fully covered — 10 sponsor/routing questions
Maker attestation / AUP sign-off	BJ-012	Covered — placed deliberately last
Inactivity / lifecycle management	OH-003, OH-004	Covered
CoE Innovation Backlog-style ROI estimate	BJ-005	Covered — made optional per anti-pattern AP-003 logic
What Vendor / Analyst Sources Cover That Was Considered and Intentionally Excluded
Feature Considered	Source	Decision
Bias and fairness testing questions (Credo AI, Holistic AI templates)	Credo AI, Holistic AI product summaries	Excluded from maker intake — folded into MRM review process (Tier-1/2 only). Bias testing is a reviewer workflow, not an intake question.
Model explainability score (Gartner AI governance framework)	Gartner AI Governance Magic Quadrant press excerpts	Excluded — no maker can honestly answer this at intake; it is an MRM output, not an input. Anti-pattern AP-009 applies.
Carbon / sustainability impact (ISO 42001 Annex B)	ISO/IEC 42001	Excluded — not currently a regulatory requirement for US FSI; deferred to firm ESG policy team.
Procurement vendor risk score (ServiceNow AI Control Tower)	ServiceNow summary materials	Collapsed into SP-006 trigger; detailed vendor risk scoring is a Procurement workflow, not an intake field.
"Responsible AI principles" Likert self-assessment (Salesforce Agentforce ADLC)	Salesforce Agentforce documentation summaries	Excluded — anti-pattern AP-006 and AP-009 apply; replaced by BJ-012 AUP attestation.
9. Open Questions for Stakeholders
These are items that could not be resolved from public sources and require firm-level policy decisions. Each is framed as a question for the appropriate internal stakeholder group. Resolution of these items will require catalog amendments before production deployment.

OQ-001 — Tier-3 Privacy review bypass
For: Chief Privacy Officer
Does the firm's privacy policy require Privacy review for ALL agents processing any personal data (even Tier-3 / Zone-3 agents with a single employee's data), or is there a de-minimis threshold below which Privacy review is waived? The catalog currently routes Privacy review based on CT-001=Yes (NPI) or RT-008=Yes (employee data) regardless of tier — this may be overly conservative for pure Zone-3 Personal agents.

OQ-002 — FINRA Notice 25-07 specific controls mapping
For: Chief Compliance Officer
FINRA Notice 25-07 (April 2025) provides updated AI guidance for broker-dealers. The full text was not retrievable in its entirety during research. The catalog's CT and SP categories were designed against the FINRA 3110/4511 baseline and Notice 24-09. Legal/Compliance should confirm whether Notice 25-07 introduces additional supervision or recordkeeping requirements that necessitate new questions not currently in the catalog.

OQ-003 — OCC 2026-13 "firm policy" MRM scope definition
For: Model Risk Management Committee
OCC Bulletin 2026-13 explicitly excludes generative and agentic AI from regulatory MRM scope, leaving it to firm policy. The catalog currently triggers firm-policy MRM review for all Tier-1 and Tier-2 agents. The MRM Committee should formally document: (a) what constitutes a "model" under firm policy for gen/agentic AI, (b) what validation evidence is required (holdout testing? red-teaming? vendor attestation?), and (c) whether Tier-2 agents require full MRM validation or a lighter-weight review.

OQ-004 — Entra Agent ID GA capability confirmation
For: Microsoft Account Team / Identity Platform Lead
Entra Agent ID is documented as GA on May 1, 2026. The catalog's OH-012 and MR-007 questions assume federated-credential minting is available at GA. The exact supported credential types (federated vs. certificate vs. managed identity) and the supported issuer types for Power Platform managed identities should be confirmed with Microsoft's Identity team before the OH-012 auto-mint workflow is activated.

OQ-005 — SEC Rule 17a-4(f) applicability to LLM conversation transcripts
For: Chief Compliance Officer / Legal / Records Management
SEC Rule 17a-4(f) requires WORM storage for electronic records subject to 17a-4. Whether AI agent conversation transcripts that do not directly constitute "order records," "blotter records," or customer account records fall within 17a-4(f) scope is a legal question that no public source resolves definitively. The catalog conservatively asks RR-003 (WORM requirement) as a Records review question. Legal should provide a bright-line determination for common agent categories (research assistants, onboarding agents, trading-support agents) so that WORM storage is not universally required for low-risk transcripts.

OQ-006 — NYDFS 23 NYCRR 500 AI-specific amendment scope
For: Legal / Compliance (NY-regulated entities)
NYDFS 23 NYCRR 500 has been amended to address cybersecurity for AI systems, but the precise scope of the amendments as applied to AI agents running in a broker-dealer or bank's M365 tenant was not definitively resolvable from public sources during research. If the firm operates under NYDFS jurisdiction, Compliance should confirm whether any intake questions need to be added to address NYDFS-specific CISO reporting, penetration-testing, or third-party risk requirements beyond what is already covered by EP-010, DS-006, and SP-006.

OQ-007 — Auto-approve eligibility for Tier-3 + Zone-1 combinations
For: AI Governance Committee
The locked design decision specifies auto-approve for Tier-3 + Zone-3 (Personal). However, there is a logical gap: a Tier-3 agent that is shared org-wide (Zone-1) — for example, a simple FAQ bot covering public information — may also be low-risk but is currently routed for full review due to its Zone-1 classification. The governance committee should define whether a Tier-3 + Zone-1 agent with zero regulated-data exposure is eligible for a streamlined (rather than full) review track.

OQ-008 — Agent-to-agent permission inheritance governance
For: Identity Platform Lead / InfoSec
CD-005 asks whether the agent communicates with other agents, but the controls question (CT-016 Prompt Shield, CT-017 content moderation) do not currently address the orchestrator-to-child permission delegation attack surface identified in the Entra Agent ID security advisory (April 2026). InfoSec should define the specific Conditional Access policy and Entra Agent ID scope-restriction controls that are required when AT-007=Yes or CD-005=Yes, so these can be added as auto-triggered controls in the CT category.

OQ-009 — Retention period for intake form records
For: Records Management
The catalog specifies 7-year default retention for intake records (RR-007, RR-008). However, if the agent itself is subject to a longer retention period (e.g., RR-002 = 10 years for certain CFTC records), the intake form that governs that agent should arguably be retained for at least as long. Records Management should confirm the retention rule for the intake form when it governs an agent with a longer-than-7-year record series.

OQ-010 — Microsoft Purview DSPM-for-AI GA feature set
For: Microsoft Account Team / Information Protection Lead
Microsoft Purview's DSPM-for-AI feature set (referenced in CT-012, DS-002 pre-fill playbook) was in preview as of early 2026. The auto-detect playbook in Section 5 assumes GA availability of the Purview catalog API for sensitivity-label faceting on SharePoint sources. The Information Protection Lead should confirm current GA status of this specific API surface before the auto-detect playbook is operationalized.

10. Bibliography
Every source cited in this document, with URL, retrieval date (April 30, 2026), and a one-line annotation. Sources marked (No public URL) were referenced by name from practitioner secondary sources only; their primary text was not directly retrieved.

Microsoft Primary Documentation
#	Title	URL	Annotation
1	Overview of agent identities in Microsoft Entra	https://learn.microsoft.com/en-us/entra/agent-id/agent-identities	Primary reference for Entra Agent ID architecture and workload-identity concepts. 
2	What are agent identities? — Microsoft Entra Agent ID	https://learn.microsoft.com/en-us/entra/agent-id/what-are-agent-identities	GA doc (April 7, 2026); defines agent identity types and Graph API surfaces used in auto-detect playbook. 
3	What is Microsoft Entra Agent ID?	https://learn.microsoft.com/en-us/entra/agent-id/what-is-microsoft-entra-agent-id	Overview doc confirming GA timeline and identity-minting capabilities. 
4	Microsoft Entra Agent ID key concepts	https://learn.microsoft.com/en-us/entra/agent-id/key-concepts	Defines federated credential, certificate, and managed-identity options for agent principals. 
5	Secure Agent Access with Microsoft Entra (product page)	https://www.microsoft.com/en-us/security/business/identity-access/microsoft-entra-agent-id	Product overview confirming Conditional Access and least-privilege controls for agent identities. 
6	Custom engine agents for Microsoft 365 overview	https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/overview-custom-engine-agent	Defines custom-engine agent architecture; primary source for AT-002 and AT-004 disqualifier design. 
7	Declarative Agents for Microsoft 365 Copilot	https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/overview-declarative-agent	Primary source for declarative agent capability constraints and disqualifier rules DA-DQ-1 through DA-DQ-7. 
8	Agent Builder in Microsoft 365 Copilot	https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/agent-builder	Primary source for Agent Builder licensing and surface constraints; informs AB-DQ-1 through AB-DQ-7. 
9	Agents for Microsoft 365 Copilot (overview)	https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/agents-overview	Cross-platform agent taxonomy; primary source for AT-003 and AT-005 design. 
10	Choose between Microsoft 365 Copilot and Copilot Studio	https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/copilot-studio-experience	Decision-tree for platform selection; source for AT-005 maker-skill mapping. 
11	Microsoft Purview data security and compliance protections for AI	https://learn.microsoft.com/en-us/purview/ai-microsoft-purview	Primary source for DSPM-for-AI capabilities, sensitivity scan API, and CT-012/DS-002 auto-detect design. 
12	Learn about sensitivity labels	https://learn.microsoft.com/en-us/purview/sensitivity-labels	Primary source for RR-004 label pre-fill and DS-002 classification taxonomy. 
13	Data policies for Managed Environments — Power Platform	https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-data-policies	Primary source for EP-010, EP-011, DS-008 auto-detect, and DLP policy group design. 
14	Microsoft Power Platform Center of Excellence Starter Kit	https://learn.microsoft.com/en-us/power-platform/guidance/coe/starter-kit	Primary source for anti-pattern analysis (AP-001, AP-003, AP-008, AP-011) and coverage gap section. 
15	CoE Starter Kit tips and FAQs	https://learn.microsoft.com/en-us/power-platform/guidance/coe/faq	Secondary CoE reference confirming Innovation Backlog intake form design patterns. 
16	Set up the CoE Starter Kit	https://learn.microsoft.com/en-us/power-platform/guidance/coe/setup	Source for understanding CoE intake data model and comparison to this catalog's structure. 
17	Governance and security for AI agents across the organization — Azure CAF	https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ai-agents/governance-security-across-organization	Primary source for Foundry governance patterns and multi-agent orchestration security design. 
18	Role-based access control for Microsoft Foundry	https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry	Primary source for MR-004 auto-detect API design and Foundry RBAC role IDs. 
Microsoft Community / Technical Secondary Sources
#	Title	URL	Annotation
19	Microsoft Entra Agent ID explained (Microsoft Mechanics blog)	https://techcommunity.microsoft.com/blog/microsoftmechanicsblog/microsoft-entra-agent-id-explained/4494408	Accessible explanation of agent identity architecture; confirms federated credential minting flow. 
20	Microsoft patched an 'agent-only' role that was not — CSO Online	https://www.csoonline.com/article/4163708/microsoft-patched-an-agent-only-role-that-was-not.html	April 2026 security advisory on Entra Agent ID Administrator role mis-scoping; primary source for DS-012 oversharing warning and CD-005 A2A attack surface. 
21	Securing AI with Microsoft Purview (Albert Hoitingh blog)	https://alberthoitingh.com/2025/08/07/securing-ai-with-microsoft-purview/	Community walkthrough of Purview sensitivity controls for AI; corroborates CT-012 design. 
22	How to Build Your Power Platform Governance Framework — Syskit	https://www.syskit.com/blog/power-platform-governance/	Practitioner governance framework; source for environment-sprawl anti-pattern analysis. 
23	8 Power Platform DLP Policy Best Practices — Matthew Devaney	https://www.matthewdevaney.com/8-power-platform-dlp-policy-best-practices/	Community best-practices source for EP-010 DLP policy group design and AP-004 anti-pattern. 
24	Developer's guide to declarative agents for M365 Copilot — Voitanos	https://www.voitanos.io/blog/microsoft-365-copilot-developers-guide-declarative-agents-webinar-recap-20260415/	April 2026 technical walkthrough confirming declarative agent capability constraints. 
25	CoE Starter Kit — Compliance process (YouTube)	https://www.youtube.com/watch?v=WXXFjHLt5ss	2022 CoE compliance video; architecturally current; primary source for anti-pattern AP-001 and AP-008. 
26	Azure AI Foundry: Building and Governing Enterprise AI Applications — Alrafayg Global	https://alrafayglobal.com/azure-ai-foundry-building-and-governing-enterprise-ai-applications/	Secondary source corroborating Foundry governance RBAC design in MR-004. 
Regulatory Primary Sources
#	Title	URL	Annotation
27	OCC Issues Updated Model Risk Management Guidance (NR-OCC-2026-29)	https://www.occ.treas.gov/news-issuances/news-releases/2026/nr-occ-2026-29.html	OCC press release confirming OCC 2026-13 issuance and April 17, 2026 effective date. 
28	OCC Bulletin 2026-13: Model Risk Management Revised Guidance	https://www.occ.treas.gov/news-issuances/bulletins/2026/bulletin-2026-13.html	Primary regulatory source confirming exclusion of generative and agentic AI from regulatory MRM scope; foundational for SP-004, RT design, and OQ-003. 
29	Federal Banking Agencies Issue Revised Guidance on Model Risk Management — Sullivan & Cromwell	https://www.sullcrom.com/insights/memo/2026/April/OCC-Fed-FDIC-Issue-Revised-Guidance-Model-Risk-Management	Legal analysis confirming OCC/Fed/FDIC joint interagency MRM guidance; source for SR 11-7 current operative status and firm-policy MRM design. 
30	FINRA Regulatory Notice 25-07	https://www.finra.org/rules-guidance/notices/25-07	FINRA's 2025 updated AI guidance for broker-dealers; cited in OQ-002 as requiring Compliance review for completeness confirmation. 
31	FINRA Rule 3110 — Supervision	https://www.finra.org/rules-guidance/rulebooks/finra-rules/3110	Primary source for all supervision-related questions (CT-007, CT-010, CT-013, SP-001, OH-005, MR-008, AP-012). 
32	FINRA Rule 4511 — General Requirements (Records)	https://www.finra.org/rules-guidance/rulebooks/finra-rules/4511	Primary source for all records-and-retention questions (RR-001, RR-002, DS-020). 
33	FINRA Rule 4511 Compliance Guide — Smarsh	https://www.smarsh.com/regulations/finra-rule-4511/	Secondary practitioner source confirming retention periods and accessibility requirements under FINRA 4511. 
34	OCC Updates Model Risk Management Guidance — LinkedIn (Brophy)	https://www.linkedin.com/posts/cbrophy_banking-riskmanagement-modelrisk-activity-7452447653260337152-wN_q	Practitioner commentary on OCC 2026-13 confirming industry interpretation of gen-AI exclusion. 
35	Federal Reserve SR 11-7: Guidance on Model Risk Management	(No public retrieval URL — FRRS reference)	Foundational interagency model-risk guidance; still operative per S&C memo 
; primary source for RT-001 through RT-005 risk-signal design and firm-policy MRM framework.
36	SEC Rule 17a-4 (including 2022 electronic-records amendments)	(No public retrieval URL — eCFR 17 CFR § 240.17a-4)	Primary source for RR-002, RR-003 WORM requirements, and OQ-005.
37	CFTC Rule 1.31	(No public retrieval URL — eCFR 17 CFR § 1.31)	Primary source for RR-010 commodity-records retention question.
38	GLBA Section 501(b) — Safeguards Rule	(No public retrieval URL — 15 U.S.C. § 6801(b))	Foundational source for NPI classification, third-party risk (SP-006), and data-egress controls (CT-014, DS-010).
39	SOX Sections 302 and 404	(No public retrieval URL — 15 U.S.C. §§ 7241, 7262)	Source for IT-general-controls requirements (OH-009), SoD controls (MR-008), and financial-system write-access risk (DS-017, RT-009).
Industry / Analyst / Community Sources
#	Title	URL	Annotation
#	Title	URL	Annotation
40	AI Agent Governance Checklist for Enterprise CISOs — Zenity	https://zenity.io/blog/security/ai-agent-governance	Practitioner CISO checklist; source for coverage-gap analysis and corroboration of A2A attack-surface gap. 
41	AI Agent Governance: A Practical Guide — Kore.ai	https://www.kore.ai/blog/ai-agent-governance-a-practical-guide	Industry overview; useful for calibrating catalog scope against non-Microsoft vendor approaches. 
42	AI Agent Governance: A Field Guide (IAPS, April 2025) — AIGL Blog	https://www.aigl.blog/ai-agent-governance-a-field-guide-iaps-apr-2025/	Academic/policy field guide; confirms regulatory coverage gaps in vendor templates. 
43	Compliance for AI Agents: What FSI Organizations Need to Know — Banking Exchange	https://www.bankingexchange.com/news-feed/item/10465-compliance-for-ai-agents-what-financial-services-organizations-need-to-know	FSI-specific compliance overview; corroborates MNPI and supervision gaps in vendor templates. 
44	NIST AI Risk Management Framework (AI RMF 1.0)	(No public retrieval URL — NIST AI 100-1)	Source for GOVERN 1.7 access-recertification requirement (OH-011) and ISO/IEC 42001 cross-reference.
45	ISO/IEC 42001:2023 — AI Management Systems	(No public retrieval URL — ISO standard)	Source for BJ-006 (considered-alternatives documentation) and RT-002 (reversibility as risk factor).
46	Power Platform Center of Excellence Governance Guide — Valoremreply	https://www.valoremreply.com/resources/insights/blog/power-platform-at-scale-the-ultimate-guide-to-governance-and-building-a-center-of-excellence/	Practitioner CoE guide; source for anti-pattern analysis in Section 7. 
47	Finance AI Agents: SOX Compliance and Governance Guide — Guru	https://www.getguru.com/reference/finance-ai-agent	SOX-specific AI governance guide; corroborates DS-017 and RT-009 financial-system write-access risk. 
48	AI agent security: New governance framework — Cybersecurity Dive	https://www.cybersecuritydive.com/spons/ai-agent-security-new-governance-framework-shows-progress-but-critical-gaps/813144/	March 2026 industry analysis; source for "critical gaps" framing in coverage gap section. 
49	Four AI governance questions your data catalog cannot answer — Solidatus	https://www.solidatus.com/blog/four-ai-governance-questions-your-data-catalog-cannot-answer/	Source for AP-003 free-text data description anti-pattern analysis. 
Document Complete
Total questions in catalog: 137 (AT: 10 · CT: 17 · EP: 12 · RT: 10 · ZN: 6 · SP: 10 · MR: 8 · DS: 20 · RR: 10 · OH: 12 · CD: 10 · BJ: 12)

Auto-detectable: 43 questions (31%) — pre-filled without asking the maker.

Maker-facing questions requiring human judgment: 94.

Sections delivered:

Part 1 — Executive Summary, Methodology, Question Catalog (AT through MR-005)

Part 2 — Question Catalog continued (MR-006 through BJ-012)

Part 3 — Cross-cutting Coverage Matrix, Auto-Detect Playbook, Disqualifier Rules

Part 4 — Anti-patterns, Coverage Gaps, Open Questions, Bibliography

The document is ready for stakeholder review and iteration. The ten Open Questions in Section 9 represent the highest-priority items for the AI Governance Committee, Chief Compliance Officer, and Records Management team to resolve before this catalog is operationalized as a live intake form.