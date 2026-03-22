# Control Mapping

Complete mapping of the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/) controls to implementing solutions.

## Pillar 1 — Security

| Control | Description | Solutions |
|---------|-------------|-----------|
| 1.1 | Restrict Agent Publishing by Authorization | [Unrestricted Agent Sharing Detector](../solutions/unrestricted-agent-sharing-detector/index.md) |
| 1.2 | Agent Registry and Integrated Apps Management | [Agent 365 Lifecycle Governance](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/agent-365-lifecycle-governance/README.md), [Agent Registry Automation](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/agent-registry-automation/README.md), [Model Risk Management Automation](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/model-risk-management-automation/README.md) |
| 1.4 | Data Loss Prevention | [File Upload Security](../solutions/file-upload-security/index.md), [Scope Drift Monitor](../solutions/scope-drift-monitor/index.md) |
| 1.5 | Network & Endpoint Security | [MIME Type Restrictions](../solutions/mime-type-restrictions/index.md), [Deny Event Correlation Report](../solutions/deny-event-correlation-report/index.md), [Scope Drift Monitor](../solutions/scope-drift-monitor/index.md) |
| 1.7 | Audit Logging & Evidence | [Audit Compliance Manager](../solutions/audit-compliance-manager/index.md), [Cross-Solution Integration](../solutions/cross-solution-integration/index.md), [Environment Lifecycle Management](../solutions/environment-lifecycle-management/index.md), [FINRA Supervision Workflow](../solutions/finra-supervision-workflow/index.md), [RAG Source Validator](../solutions/rag-source-validator/index.md), [Deny Event Correlation Report](../solutions/deny-event-correlation-report/index.md) |
| 1.8 | Content Moderation | [Content Moderation Monitor](../solutions/content-moderation-monitor/index.md), [Cross-Solution Integration](../solutions/cross-solution-integration/index.md), [Deny Event Correlation Report](../solutions/deny-event-correlation-report/index.md) |
| 1.9 | Disaster Recovery | [DR Testing Framework](../solutions/dr-testing-framework/index.md) |
| 1.10 | Supervision & Review | [FINRA Supervision Workflow](../solutions/finra-supervision-workflow/index.md), [MIME Type Restrictions](../solutions/mime-type-restrictions/index.md) |
| 1.11 | Conditional Access | [Conditional Access Automation](../solutions/conditional-access-automation/index.md), [Cross-Solution Integration](../solutions/cross-solution-integration/index.md), [Session Security Configurator](../solutions/session-security-configurator/index.md), [MIME Type Restrictions](../solutions/mime-type-restrictions/index.md) |
| 1.13 | File & Attachment Controls | [MIME Type Restrictions](../solutions/mime-type-restrictions/index.md) |
| 1.14 | Content & Data Protection | [Content Moderation Monitor](../solutions/content-moderation-monitor/index.md), [File Upload Security](../solutions/file-upload-security/index.md), [Cross-Solution Integration](../solutions/cross-solution-integration/index.md), [MIME Type Restrictions](../solutions/mime-type-restrictions/index.md), [Scope Drift Monitor](../solutions/scope-drift-monitor/index.md) |
| 1.18 | Agent Sharing Restrictions | [Conditional Access Automation](../solutions/conditional-access-automation/index.md), [Agent Sharing Access Restriction Detector](../solutions/agent-sharing-access-restriction-detector/index.md) |
| 1.23 | Step-Up Authentication & Confirmation | [Action Confirmation Auditor](../solutions/action-confirmation-auditor/index.md), [Conditional Access Automation](../solutions/conditional-access-automation/index.md), [Cross-Solution Integration](../solutions/cross-solution-integration/index.md), [Inactivity Timeout Enforcement](../solutions/inactivity-timeout-enforcement/index.md), [Session Security Configurator](../solutions/session-security-configurator/index.md) |
| 1.25 | Secure File Handling | [MIME Type Restrictions](../solutions/mime-type-restrictions/index.md) |

## Pillar 2 — Management

| Control | Description | Solutions |
|---------|-------------|-----------|
| 2.1 | Managed Environments | [Environment Lifecycle Management](../solutions/environment-lifecycle-management/index.md), [Pipeline Governance Cleanup](../solutions/pipeline-governance-cleanup/index.md), [DR Testing Framework](../solutions/dr-testing-framework/index.md), [Segregation Detector](../solutions/segregation-detector/index.md) |
| 2.2 | Environment Provisioning | [Environment Lifecycle Management](../solutions/environment-lifecycle-management/index.md) |
| 2.3 | Environment Governance | [Environment Lifecycle Management](../solutions/environment-lifecycle-management/index.md), [Pipeline Governance Cleanup](../solutions/pipeline-governance-cleanup/index.md), [Message Center Monitor](../solutions/message-center-monitor/index.md), [Segregation Detector](../solutions/segregation-detector/index.md) |
| 2.4 | Business Continuity | [DR Testing Framework](../solutions/dr-testing-framework/index.md) |
| 2.5 | Agent Sharing Scope | [COI Testing](../solutions/coi-testing/index.md) |
| 2.6 | Model Risk Management | [Model Risk Management Automation](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/model-risk-management-automation/README.md) |
| 2.8 | Maker/Checker Separation | [Agent Sharing Access Restriction Detector](../solutions/agent-sharing-access-restriction-detector/index.md), [Segregation Detector](../solutions/segregation-detector/index.md), [Environment Lifecycle Management](../solutions/environment-lifecycle-management/index.md) |
| 2.9 | Output Quality | [Hallucination Tracker](../solutions/hallucination-tracker/index.md) |
| 2.10 | Platform Change Management | [Message Center Monitor](../solutions/message-center-monitor/index.md) |
| 2.11 | Conflict of Interest | [COI Testing](../solutions/coi-testing/index.md) |
| 2.12 | Supervision & Oversight | [FINRA Supervision Workflow](../solutions/finra-supervision-workflow/index.md), [Hallucination Tracker](../solutions/hallucination-tracker/index.md) |
| 2.13 | Knowledge Source Management | [RAG Source Validator](../solutions/rag-source-validator/index.md) |
| 2.16 | RAG Source Integrity | [RAG Source Validator](../solutions/rag-source-validator/index.md) |
| 2.17 | Multi-Agent Communication | [Agent Communication Restriction Detector](../solutions/agent-communication-restriction-detector/index.md) |
| 2.18 | Conflict of Interest Testing | [COI Testing](../solutions/coi-testing/index.md) |
| 2.22 | Session Timeout | [Inactivity Timeout Enforcement](../solutions/inactivity-timeout-enforcement/index.md) |
| 2.24 | GenAI Feature Governance | [Generative AI Config Auditor](../solutions/generative-ai-config-auditor/index.md) |

## Pillar 3 — Reporting

| Control | Description | Solutions |
|---------|-------------|-----------|
| 3.1 | Compliance Reporting | [Compliance Dashboard](../solutions/compliance-dashboard/index.md) |
| 3.2 | Analytics & Metrics | [Compliance Dashboard](../solutions/compliance-dashboard/index.md), [Copilot Studio Analytics](../solutions/copilot-studio-analytics/index.md) |
| 3.3 | Governance Dashboard | [Compliance Dashboard](../solutions/compliance-dashboard/index.md), [MIME Type Restrictions](../solutions/mime-type-restrictions/index.md) |
| 3.4 | Security Event Reporting | [Deny Event Correlation Report](../solutions/deny-event-correlation-report/index.md) |
| 3.7 | Timeout Reporting | [Inactivity Timeout Enforcement](../solutions/inactivity-timeout-enforcement/index.md), [MIME Type Restrictions](../solutions/mime-type-restrictions/index.md) |
| 3.8 | Copilot Hub & Governance Dashboard | [Agent Access Monitor](../solutions/agent-access-monitor/index.md), [Cross-Solution Integration](../solutions/cross-solution-integration/index.md), [Inactivity Timeout Enforcement](../solutions/inactivity-timeout-enforcement/index.md), [Unrestricted Agent Sharing Detector](../solutions/unrestricted-agent-sharing-detector/index.md) |
| 3.10 | Hallucination Reporting | [Hallucination Tracker](../solutions/hallucination-tracker/index.md) |

## Pillar 4 — Governance

| Control | Description | Solutions |
|---------|-------------|-----------|
| 4.3 | File Governance | [MIME Type Restrictions](../solutions/mime-type-restrictions/index.md) |

## Coverage Summary

- **Controls with implementations:** 39 of 78
- **Live top-level solution folders:** 33
- **Controls per solution (avg):** 3.2

!!! info "Framework Reference"
    Full control specifications are available in the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/controls/).
