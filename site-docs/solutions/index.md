# Solutions Catalog

28 reference implementations organized by functional domain. Each solution includes PowerShell/Python scripts, Dataverse schemas, and step-by-step deployment documentation.

---

## Access & Identity

Solutions for controlling who can access, share, and publish AI agents.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Agent Access Monitor](agent-access-monitor/index.md) | Automated detection of overly permissive agent access configurations | v1.0.0 | 3.8 |
| [Conditional Access Automation](conditional-access-automation/index.md) | CA policy deployment, compliance monitoring, and drift detection | v1.1.0 | 1.11, 1.23, 1.18 |
| [Inactivity Timeout Enforcement](inactivity-timeout-enforcement/index.md) | Policy-driven inactivity timeout validation with zone-based durations | v1.0.0 | 2.22, 1.23, 3.7, 3.8 |
| [Agent Sharing Access Restriction Detector](agent-sharing-access-restriction-detector/index.md) | Zone-based agent sharing policy enforcement with approval workflows | v1.0.0 | 1.18, 2.8 |
| [Unrestricted Agent Sharing Detector](unrestricted-agent-sharing-detector/index.md) | Continuous detection of overly permissive agent sharing with remediation | v1.0.2 | 1.1, 3.8 |

## Content & Data Protection

Solutions for securing agent content, file handling, and knowledge sources.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Content Moderation Monitor](content-moderation-monitor/index.md) | Per-agent content moderation validation against zone requirements | v1.0.0 | 1.8, 1.14 |
| [File Upload Security](file-upload-security/index.md) | Per-agent file upload validation against zone governance policies | v1.0.0 | 1.14, 1.8, 1.4 |
| [MIME Type Restrictions](mime-type-restrictions/index.md) | Zone-based MIME type configuration with server-side validation | v1.0.0 | 1.5, 1.10, 1.11, 1.13, 1.14, 1.25, 3.3, 3.7, 4.3 |
| [RAG Source Validator](rag-source-validator/index.md) | Integrity validation for RAG knowledge sources with change detection | v1.0.0 | 2.16, 1.7, 2.13 |

## Compliance & Audit

Solutions for audit management, compliance reporting, and regulatory workflows.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Audit Compliance Manager](audit-compliance-manager/index.md) | Unified audit compliance — validates configs, detects gaps, remediates | v1.0.0 | 1.7 |
| [Compliance Dashboard](compliance-dashboard/index.md) | Aggregated compliance reporting across 71 controls | v1.0.0 | 3.3, 3.1, 3.2 |
| [Cross-Solution Integration](cross-solution-integration/index.md) | Wires Tier 2 solutions into Compliance Dashboard with evidence export | v1.0.0 | 1.7, 1.23, 1.11, 3.8, 1.8, 1.14 |
| [FINRA Supervision Workflow](finra-supervision-workflow/index.md) | Automated supervision queue for AI agent outputs (FINRA 3110) | v1.0.0 | 2.12, 1.10, 1.7 |
| [Segregation Detector](segregation-detector/index.md) | Role conflict detection for Maker/Checker enforcement in agent pipelines | v1.0.0 | 2.8, 2.1, 2.3 |

## Monitoring & Analytics

Solutions for observability, analytics, event correlation, and drift detection.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Agent Observability Foundation](agent-observability-foundation/index.md) | Foundational observability infrastructure for agent monitoring | v1.1.0 | — |
| [Copilot Studio Analytics](copilot-studio-analytics/index.md) | Business impact analytics for Copilot Studio agents | v1.0.0 | 3.2 |
| [Deny Event Correlation Report](deny-event-correlation-report/index.md) | Daily deny event correlation across Purview, DLP, App Insights | v2.0.0 | 1.5, 1.7, 1.8, 3.4 |
| [Scope Drift Monitor](scope-drift-monitor/index.md) | Detect agent data access beyond declared operational scope | v1.1.0 | 1.14, 1.4, 1.5 |
| [Hallucination Tracker](hallucination-tracker/index.md) | Feedback aggregation for hallucination pattern analysis | v1.0.0 | 3.10, 2.9, 2.12 |

## Agent Configuration

Solutions for validating and enforcing agent configuration settings.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Generative AI Config Auditor](generative-ai-config-auditor/index.md) | GenAI feature configuration validation per zone governance policy | v1.0.0 | 2.24 |
| [Session Security Configurator](session-security-configurator/index.md) | Session security validation per governance zone with drift detection | v1.0.0 | 1.23, 1.11 |
| [Agent Communication Restriction Detector](agent-communication-restriction-detector/index.md) | Inter-agent communication restriction validation per zone routing policy | v1.0.0 | 2.17 |
| [Action Confirmation Auditor](action-confirmation-auditor/index.md) | Step-up confirmation validation for agent action invocations | v1.0.0 | 1.23 |

## Lifecycle & Operations

Solutions for environment management, pipeline governance, and operational testing.

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Environment Lifecycle Management](environment-lifecycle-management/index.md) | Power Platform environment provisioning with zone-based governance | v1.1.2 | 2.1, 2.2, 2.3, 2.8, 1.7 |
| [Pipeline Governance Cleanup](pipeline-governance-cleanup/index.md) | Discover, notify, clean up personal pipelines | v1.0.8 | 2.3, 2.1 |
| [DR Testing Framework](dr-testing-framework/index.md) | Automated disaster recovery testing for AI agent infrastructure | v1.0.0 | 2.4, 2.1, 1.9 |
| [Message Center Monitor](message-center-monitor/index.md) | M365 Message Center monitoring for platform changes | v2.1.1 | 2.3, 2.10 |
| [COI Testing](coi-testing/index.md) | Conflict of interest testing for agent recommendations | v1.0.0 | 2.18, 2.11, 2.5 |

---

## Control Cross-Reference

See the full [Control Mapping](../reference/control-mapping.md) for a complete mapping of all 71 framework controls to their implementing solutions.
