# Solutions Catalog

35 live reference implementations organized by functional domain. Published site detail pages are linked where available; remaining entries link to the repository README.

---

## Access & Identity

Solutions for controlling who can access, share, and publish AI agents.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Agent Access Governance Monitor](agent-access-monitor/index.md) | Automated detection of overly permissive agent access configurations per governance zone | v1.0.1 | 3.8 |
| [Conditional Access Automation](conditional-access-automation/index.md) | CA policy deployment, compliance monitoring, and drift detection for AI workloads | v1.1.2 | 1.11, 1.23, 1.18 |
| [Cross-Tenant and External Sharing Governance](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/cross-tenant-external-sharing-governance/README.md) | Three-layer cross-tenant access governance (tenant isolation, Entra CTA, agent shares) | v1.0.0 | 1.1, 1.18, 2.1, 2.8, 3.1, 1.11 |
| [Inactivity Timeout Enforcement](inactivity-timeout-enforcement/index.md) | Policy-driven inactivity timeout validation with zone-based duration requirements | v1.0.3 | 2.22, 1.23, 3.7, 3.8 |
| [Agent Sharing Access Restriction Detector](agent-sharing-access-restriction-detector/index.md) | Zone-based agent sharing policy enforcement with approval workflows and exception management | v1.0.2 | 1.18, 2.8 |
| [Unrestricted Agent Sharing Detector](unrestricted-agent-sharing-detector/index.md) | Continuous detection of overly permissive agent sharing with automated remediation | v1.0.2 | 1.1, 3.8 |

## Content & Data Protection

Solutions for securing agent content, file handling, and knowledge sources.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Agent Knowledge Source Scanner](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/agent-knowledge-source-scanner/README.md) | Item-level permission scanning for agent knowledge source SharePoint libraries | v1.0.1 | 4.3, 1.4, 1.5 |
| [Content Moderation Monitor](content-moderation-monitor/index.md) | Per-agent content moderation validation against zone-specific governance requirements | v1.0.2 | 1.8, 1.14 |
| [File Upload Security Configurator](file-upload-security/index.md) | Per-agent file upload validation against zone governance policies with drift detection | v1.0.1 | 1.14, 1.8, 1.4 |
| [MIME Type Restrictions for File Uploads](mime-type-restrictions/index.md) | Zone-based MIME type configuration with server-side validation and DLP integration | v1.0.2 | 1.5, 1.10, 1.11, 1.13, 1.14, 1.25, 3.3, 3.7, 4.3 |
| [RAG Source Validator](rag-source-validator/index.md) | Integrity validation for RAG knowledge sources with change detection | v1.0.1 | 2.16, 1.7, 2.13 |

## Compliance & Audit

Solutions for audit management, compliance reporting, and regulatory workflows.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Agent Registry Automation](agent-registry-automation/index.md) | Automated discovery, registration, approval, and lifecycle governance of AI agents | v1.0.1 | 1.2, 1.7, 2.1, 2.13 |
| [Audit Compliance Manager (ACM)](audit-compliance-manager/index.md) | Unified audit compliance — validates configurations, detects gaps, and remediates non-compliant environments | v1.0.1 | 1.7 |
| [Compliance Dashboard](compliance-dashboard/index.md) | Aggregated compliance reporting across 78 controls with Exchange coverage | v1.0.1 | 3.3, 3.1, 3.2 |
| [Cross-Solution Integration](cross-solution-integration/index.md) | Wires Tier 2 solutions into Compliance Dashboard with unified evidence export | v1.0.0 | 1.7, 1.23, 1.11, 3.8, 1.8, 1.14 |
| [FINRA Supervision Workflow](finra-supervision-workflow/index.md) | Automated supervision queue for AI agent outputs (FINRA 3110) | v1.0.0 | 2.12, 1.10, 1.7 |
| [HITL Workflow Governance](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/hitl-workflow-governance/README.md) | Zone-based governance for Human in the Loop checkpoints in Copilot Studio agent flows | v1.0.0 | 2.12, 2.17, 1.10 |
| [Model Risk Management Automation](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/model-risk-management-automation/README.md) | OCC 2011-12 / SR 11-7 model risk management with inventory, risk scoring, validation workflows, and Agent Card generation | v1.0.0 | 2.6, 2.5, 2.9, 2.11, 2.13, 3.1, 1.2 |
| [Segregation of Duties Detector](segregation-detector/index.md) | Role conflict detection for Maker/Checker enforcement in agent pipelines | v1.0.0 | 2.8, 2.1, 2.3 |

## Monitoring & Analytics

Solutions for observability, analytics, event correlation, and drift detection.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Agent Observability Foundation](agent-observability-foundation/index.md) | Foundational observability infrastructure for agent monitoring and diagnostics | v1.1.0 | 1.7, 2.8, 2.9, 3.2 |
| [Copilot Studio Analytics](copilot-studio-analytics/index.md) | Business impact analytics for Copilot Studio agents | v1.1.0 | 3.2 |
| [Deny Event Correlation Report](deny-event-correlation-report/index.md) | Daily deny event correlation across Purview, DLP, App Insights | v2.0.0 | 1.5, 1.7, 1.8, 3.4 |
| [Scope Drift Monitor](scope-drift-monitor/index.md) | Detect agent data access beyond declared operational scope | v1.1.1 | 1.14, 1.4, 1.5 |
| [Hallucination Feedback Tracker](hallucination-tracker/index.md) | Feedback aggregation for hallucination pattern analysis | v0.1.0-preview | 3.10, 2.9, 2.12 |

## Agent Configuration

Solutions for validating and enforcing agent configuration settings.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Generative AI Config Auditor](generative-ai-config-auditor/index.md) | GenAI feature configuration validation per zone governance policy | v1.0.0 | 2.24 |
| [Session Security Configurator](session-security-configurator/index.md) | Session security validation per governance zone with drift detection | v1.0.1 | 1.23, 1.11 |
| [Agent Communication Restriction Detector](agent-communication-restriction-detector/index.md) | Inter-agent communication restriction validation per zone routing policy | v1.0.0 | 2.17 |
| [Action Confirmation Auditor](action-confirmation-auditor/index.md) | Step-up confirmation validation for agent action invocations | v1.0.0 | 1.23 |
| [Credential Oversharing Detector](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/credential-oversharing-detector/README.md) | Configuration-time credential scope governance for agent connectors | v1.0.0 | 1.14, 1.4, 1.18 |

## Lifecycle & Operations

Solutions for environment management, pipeline governance, and operational testing.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Agent 365 Lifecycle Governance](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/agent-365-lifecycle-governance/README.md) | Automated lifecycle governance for AI agents using Agent 365 and Entra ID Governance | v1.1.0 | 2.3, 1.2, 1.11, 2.1, 2.8, 2.12, 3.1 |
| [Environment Lifecycle Management](environment-lifecycle-management/index.md) | Power Platform environment provisioning with zone-based governance | v1.1.2 | 2.1, 2.2, 2.3, 2.8, 1.7 |
| [Pipeline Governance Cleanup](pipeline-governance-cleanup/index.md) | Discover, notify, clean up personal pipelines | v1.1.0 | 2.3, 2.1 |
| [DR Testing Framework](dr-testing-framework/index.md) | Automated disaster recovery testing for AI agent infrastructure | v1.1.0 | 2.4, 2.1, 1.9 |
| [Message Center Monitor](message-center-monitor/index.md) | M365 Message Center monitoring for platform changes | v2.1.3 | 2.3, 2.10 |
| [Conflict of Interest Testing](coi-testing/index.md) | Conflict of interest testing for agent recommendations | v1.0.1 | 2.18, 2.11, 2.5 |

## Preview Placeholders

All previously tracked preview placeholders have been promoted to live solution implementations.

---

## Control Cross-Reference

See the full [Control Mapping](../reference/control-mapping.md) for current solution coverage against the 78-control framework baseline.
