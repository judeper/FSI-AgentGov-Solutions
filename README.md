# FSI-AgentGov-Solutions

Deployable Power Platform solutions for the [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov).

For detailed descriptions, regulatory alignment, and framework playbook links, see the [Solutions Index](https://judeper.github.io/FSI-AgentGov/reference/solutions-index/) in FSI-AgentGov.

## Available Solutions (24)

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Agent Access Governance Monitor](./agent-access-monitor/) | Automated detection of overly permissive agent access configurations per governance zone | v1.0.0 | 3.8 |
| [Agent Observability Foundation](./agent-observability-foundation/) | Foundational observability infrastructure for agent monitoring and diagnostics | v1.1.0 | — |
| [Agent Sharing Access Restriction Detector](./agent-sharing-access-restriction-detector/) | Zone-based agent sharing policy enforcement with approval workflows and exception management | v1.0.0 | 1.18, 2.8 |
| [Audit Compliance Manager](./audit-compliance-manager/) | Unified audit compliance — validates configurations, detects gaps, and remediates non-compliant environments (consolidates former ACV + ALCA) | v1.0.0 | 1.7 |
| [COI Testing Framework](./coi-testing/) | Conflict of interest testing for agent recommendations | v1.0.0 | 2.18, 2.11, 2.5 |
| [Compliance Dashboard](./compliance-dashboard/) | Aggregated compliance reporting across 71 controls with zone-based filtering | v1.0.0 | 3.3, 3.1, 3.2 |
| [Conditional Access Automation](./conditional-access-automation/) | CA policy deployment, compliance monitoring, and drift detection for AI workloads | v1.1.0 | 1.11, 1.23, 1.18 |
| [Content Moderation Governance Monitor](./content-moderation-monitor/) | Per-agent content moderation validation against zone-specific governance requirements | v1.0.0 | 1.8, 1.14 |
| [Cross-Solution Integration](./cross-solution-integration/) | Wires Tier 2 solutions into Compliance Dashboard with unified evidence export | v1.0.0 | 1.7, 1.23, 1.11, 3.8, 1.8, 1.14 |
| [Deny Event Correlation Report](./deny-event-correlation-report/) | Daily deny event correlation across Purview Audit, DLP, and Application Insights | v2.0.0 | 1.5, 1.7, 1.8, 3.4 |
| [DR Testing Framework](./dr-testing-framework/) | Automated disaster recovery testing for AI agent infrastructure | v1.0.0 | 2.4, 2.1, 1.9 |
| [Environment Lifecycle Management](./environment-lifecycle-management/) | Automated environment provisioning with zone-based governance classification | v1.1.2 | 2.1, 2.2, 2.3, 2.8, 1.7 |
| [File Upload Security Configurator](./file-upload-security/) | Per-agent file upload validation against zone governance policies with drift detection | v1.0.0 | 1.14, 1.8, 1.4 |
| [FINRA Supervision Workflow](./finra-supervision-workflow/) | Automated supervision queue for AI agent outputs (FINRA 3110) | v1.0.0 | 2.12, 1.10, 1.7 |
| [Hallucination Tracker](./hallucination-tracker/) | Feedback aggregation for hallucination pattern analysis | v1.0.0 | 3.10, 2.9, 2.12 |
| [Inactivity Timeout Enforcement](./inactivity-timeout-enforcement/) | Policy-driven inactivity timeout validation with zone-based duration requirements | v1.0.0 | 2.22, 1.23, 3.7, 3.8 |
| [Message Center Monitor](./message-center-monitor/) | M365 Message Center monitoring for platform changes affecting AI agents | v2.1.1 | 2.3, 2.10 |
| [MIME Type Restrictions for File Uploads](./mime-type-restrictions/) | Zone-based MIME type configuration with server-side validation and DLP integration | v1.0.0 | 1.5, 1.10, 1.11, 1.13, 1.14, 1.25, 3.3, 3.7, 4.3 |
| [Pipeline Governance Cleanup](./pipeline-governance-cleanup/) | Personal pipeline discovery and ALM governance enforcement | v1.0.8 | 2.3, 2.1 |
| [RAG Source Validator](./rag-source-validator/) | Integrity validation for RAG knowledge sources with change detection | v1.0.0 | 2.16, 1.7, 2.13 |
| [Scope Drift Monitor](./scope-drift-monitor/) | Detect agent data access beyond declared operational scope | v1.1.0 | 1.14, 1.4, 1.5 |
| [Segregation of Duties Detector](./segregation-detector/) | Role conflict detection for Maker/Checker enforcement in agent pipelines | v1.0.0 | 2.8, 2.1, 2.3 |
| [Session Security Configurator](./session-security-configurator/) | Session security validation per governance zone with drift detection and evidence export | v1.0.0 | 1.23, 1.11 |
| [Unrestricted Agent Sharing Detector](./unrestricted-agent-sharing-detector/) | Continuous detection of overly permissive agent sharing with automated remediation | v1.0.0 | 1.1, 3.8 |

## How to Use

1. Navigate to the solution folder
2. Follow the README for prerequisites
3. Set up Microsoft Entra ID app registration (where required)
4. Deploy Dataverse schema and Power Automate flows
5. Configure Teams notifications

## Documentation

Each solution folder contains a README with prerequisites, components, and deployment instructions.

For the complete solutions catalog with regulatory alignment, framework playbooks, and detailed descriptions, see the [Solutions Index](https://judeper.github.io/FSI-AgentGov/reference/solutions-index/) on the FSI-AgentGov documentation site.

Framework documentation: [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov)

## License

MIT
