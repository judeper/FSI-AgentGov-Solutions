# FSI-AgentGov-Solutions

Deployable Power Platform solutions for the [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov).

For detailed descriptions, regulatory alignment, and framework playbook links, see the [Solutions Index](https://judeper.github.io/FSI-AgentGov/reference/solutions-index/) in FSI-AgentGov.

This repository currently includes **33 live solution implementations** and **2 documentation-only preview placeholder folders**. The preview placeholders are tracked separately until they move beyond placeholder scope and gain deployable implementation guidance.

## Current Solutions (33)

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Action Confirmation Auditor](./action-confirmation-auditor/) | Step-up confirmation validation for agent action invocations per zone policy | v1.0.0 | 1.23 |
| [Agent 365 Lifecycle Governance](./agent-365-lifecycle-governance/) | Automated lifecycle governance for AI agents using Agent 365 and Entra ID Governance | v1.1.0 | 2.3, 1.2, 1.11, 2.1, 2.8, 2.12, 3.1 |
| [Agent Access Governance Monitor](./agent-access-monitor/) | Automated detection of overly permissive agent access configurations per governance zone | v1.0.0 | 3.8 |
| [Agent Communication Restriction Detector](./agent-communication-restriction-detector/) | Inter-agent communication restriction validation per zone routing policy | v1.0.0 | 2.17 |
| [Agent Knowledge Source Scanner](./agent-knowledge-source-scanner/) | Item-level permission scanning for agent knowledge source SharePoint libraries | v1.0.0 | 4.3, 1.4, 1.5 |
| [Agent Observability Foundation](./agent-observability-foundation/) | Foundational observability infrastructure for agent monitoring and diagnostics | v1.1.0 | 1.7, 2.8, 2.9, 3.2 |
| [Agent Registry Automation](./agent-registry-automation/) | Automated discovery, registration, approval, and lifecycle governance of AI agents | v1.0.0 | 1.2, 1.7, 2.1, 2.13 |
| [Agent Sharing Access Restriction Detector](./agent-sharing-access-restriction-detector/) | Zone-based agent sharing policy enforcement with approval workflows and exception management | v1.0.1 | 1.18, 2.8 |
| [Audit Compliance Manager (ACM)](./audit-compliance-manager/) | Unified audit compliance — validates configurations, detects gaps, and remediates non-compliant environments (consolidates former ACV + ALCA) | v1.0.1 | 1.7 |
| [Conflict of Interest Testing](./coi-testing/) | Conflict of interest testing for agent recommendations | v1.0.0 | 2.18, 2.11, 2.5 |
| [Compliance Dashboard](./compliance-dashboard/) | Aggregated compliance reporting across 78 controls with Exchange coverage | v1.0.0 | 3.3, 3.1, 3.2 |
| [Conditional Access Automation](./conditional-access-automation/) | CA policy deployment, compliance monitoring, and drift detection for AI workloads | v1.1.1 | 1.11, 1.23, 1.18 |
| [Content Moderation Monitor](./content-moderation-monitor/) | Per-agent content moderation validation against zone-specific governance requirements | v1.0.1 | 1.8, 1.14 |
| [Copilot Studio Analytics](./copilot-studio-analytics/) | Business impact analytics for Copilot Studio agents (Viva Insights alternative) | v1.1.0 | 3.2 |
| [Cross-Solution Integration](./cross-solution-integration/) | Wires Tier 2 solutions into Compliance Dashboard with unified evidence export | v1.0.0 | 1.7, 1.23, 1.11, 3.8, 1.8, 1.14 |
| [Cross-Tenant and External Sharing Governance](./cross-tenant-external-sharing-governance/) | Three-layer cross-tenant access governance (tenant isolation, Entra CTA, agent shares) | v1.0.0 | 1.1, 1.18, 2.1, 2.8, 3.1, 1.11 |
| [Deny Event Correlation Report](./deny-event-correlation-report/) | Daily deny event correlation across Purview Audit, DLP, and Application Insights | v2.0.0 | 1.5, 1.7, 1.8, 3.4 |
| [DR Testing Framework](./dr-testing-framework/) | Automated disaster recovery testing for AI agent infrastructure | v1.1.0 | 2.4, 2.1, 1.9 |
| [Environment Lifecycle Management](./environment-lifecycle-management/) | Automated environment provisioning with zone-based governance classification | v1.1.2 | 2.1, 2.2, 2.3, 2.8, 1.7 |
| [File Upload Security Configurator](./file-upload-security/) | Per-agent file upload validation against zone governance policies with drift detection | v1.0.0 | 1.14, 1.8, 1.4 |
| [FINRA Supervision Workflow](./finra-supervision-workflow/) | Automated supervision queue for AI agent outputs (FINRA 3110) | v1.0.0 | 2.12, 1.10, 1.7 |
| [Generative AI Config Auditor](./generative-ai-config-auditor/) | GenAI feature configuration validation per zone governance policy | v1.0.0 | 2.24 |
| [Hallucination Feedback Tracker](./hallucination-tracker/) | Feedback aggregation for hallucination pattern analysis | v0.1.0-preview | 3.10, 2.9, 2.12 |
| [Inactivity Timeout Enforcement](./inactivity-timeout-enforcement/) | Policy-driven inactivity timeout validation with zone-based duration requirements | v1.0.2 | 2.22, 1.23, 3.7, 3.8 |
| [Message Center Monitor](./message-center-monitor/) | M365 Message Center monitoring for platform changes affecting AI agents | v2.1.2 | 2.3, 2.10 |
| [MIME Type Restrictions for File Uploads](./mime-type-restrictions/) | Zone-based MIME type configuration with server-side validation and DLP integration | v1.0.1 | 1.5, 1.10, 1.11, 1.13, 1.14, 1.25, 3.3, 3.7, 4.3 |
| [Model Risk Management Automation](./model-risk-management-automation/) | OCC 2011-12 / SR 11-7 model risk management with inventory, risk scoring, validation workflows, and Agent Card generation (requires agent-registry-automation) | v1.0.0 | 2.6, 2.5, 2.9, 2.11, 2.13, 3.1, 1.2 |
| [Pipeline Governance Cleanup](./pipeline-governance-cleanup/) | Personal pipeline discovery and ALM governance enforcement | v1.0.8 | 2.3, 2.1 |
| [RAG Source Validator](./rag-source-validator/) | Integrity validation for RAG knowledge sources with change detection | v1.0.1 | 2.16, 1.7, 2.13 |
| [Scope Drift Monitor](./scope-drift-monitor/) | Detect agent data access beyond declared operational scope | v1.1.0 | 1.14, 1.4, 1.5 |
| [Segregation of Duties Detector](./segregation-detector/) | Role conflict detection for Maker/Checker enforcement in agent pipelines | v1.0.0 | 2.8, 2.1, 2.3 |
| [Session Security Configurator](./session-security-configurator/) | Session security validation per governance zone with drift detection and evidence export | v1.0.0 | 1.23, 1.11 |
| [Unrestricted Agent Sharing Detector](./unrestricted-agent-sharing-detector/) | Continuous detection of overly permissive agent sharing with automated remediation | v1.0.2 | 1.1, 3.8 |

## Preview Placeholders (2)

These folders reserve validated namespaces for upcoming Microsoft capabilities. They are intentionally excluded from the 33-live-solution count until they move beyond placeholder scope.

| Solution | Status | Controls | Summary |
|----------|--------|----------|---------|
| [HITL Workflow Governance](./hitl-workflow-governance/) | Preview placeholder | 2.12, 2.17, 1.10 | Planned evidence-collection workflow for supervisory approvals, request-for-information routing, and audit-trail capture around human-in-the-loop checkpoints. |
| [Credential Oversharing Detector](./credential-oversharing-detector/) | Planned preview placeholder | 1.14, 1.4, 1.18 | Planned zone-aware review pattern for Copilot Studio safe-sharing and credential-scope signals before broader deployable guidance is available. |

## How to Use

1. Navigate to the solution folder
2. Follow the README for prerequisites
3. Set up Microsoft Entra ID app registration (where required)
4. Deploy Dataverse schema and follow the documented Power Automate build guidance
5. Configure Teams notifications

## Documentation

Each solution folder contains a README with prerequisites, components, and deployment instructions.

**[Deployment Guide](./DEPLOYMENT-GUIDE.md)** — Maps customer questions to solutions, documents deployment layers, and provides sequencing guidance for Compliance Dashboard integration.

For the complete solutions catalog with regulatory alignment, framework playbooks, and detailed descriptions, see the [Solutions Index](https://judeper.github.io/FSI-AgentGov/reference/solutions-index/) on the FSI-AgentGov documentation site.

Framework documentation: [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov)

## License

MIT
