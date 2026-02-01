# FSI-AgentGov-Solutions

Deployable Power Platform solutions for the [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov).

## Available Solutions

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Environment Lifecycle Management](./environment-lifecycle-management/) | Automated environment provisioning with zone-based governance | v1.1.2 | 2.1, 2.2, 2.3, 2.8, 1.7 |
| [Message Center Monitor](./message-center-monitor/) | M365 Message Center monitoring for platform changes | v2.1.1 | 2.3, 2.10 |
| [Pipeline Governance Cleanup](./pipeline-governance-cleanup/) | Personal pipeline discovery and ALM governance enforcement | v1.0.8 | 2.3, 2.1 |
| [Deny Event Correlation Report](./deny-event-correlation-report/) | Daily deny event correlation across Purview and App Insights | v1.1.0 | 1.5, 1.7, 3.4 |
| [FINRA Supervision Workflow](./finra-supervision-workflow/) | Automated supervision queue for AI agent outputs (FINRA 3110) | v1.0.0 | 2.12, 1.10, 1.7 |
| [Conditional Access Automation](./conditional-access-automation/) | CA policy deployment and compliance monitoring for AI workloads | v1.0.0 | 1.11, 1.23, 1.18 |
| [Compliance Dashboard](./compliance-dashboard/) | Aggregated compliance reporting across 62 controls | v1.0.0-beta | 3.3, 3.1, 3.2 |
| [Segregation of Duties Detector](./segregation-detector/) | Role conflict detection for Maker/Checker enforcement | v1.0.0 | 2.8, 2.1, 2.3 |
| [Scope Drift Monitor](./scope-drift-monitor/) | Detect agent data access beyond declared scope | v1.0.0 | 1.14, 1.4, 1.5 |
| [RAG Source Validator](./rag-source-validator/) | Integrity validation for RAG knowledge sources | v1.0.0 | 2.16, 1.7, 2.13 |

> **Note:** Solutions marked with `-beta` have complete documentation and schemas but require manual Power BI template creation. See solution README for details.

## How to Use

1. Navigate to the solution folder
2. Follow the README for prerequisites
3. Set up Azure AD app registration
4. Create Power Automate flow
5. Configure Teams notifications

## Documentation

All detailed documentation lives in each solution folder:

- [Environment Lifecycle Management](./environment-lifecycle-management/README.md)
- [Message Center Monitor](./message-center-monitor/README.md)
- [Pipeline Governance Cleanup](./pipeline-governance-cleanup/README.md)
- [Deny Event Correlation Report](./deny-event-correlation-report/README.md)
- [FINRA Supervision Workflow](./finra-supervision-workflow/README.md)
- [Conditional Access Automation](./conditional-access-automation/README.md)
- [Compliance Dashboard](./compliance-dashboard/README.md) *(beta)*
- [Segregation of Duties Detector](./segregation-detector/README.md)
- [Scope Drift Monitor](./scope-drift-monitor/README.md)
- [RAG Source Validator](./rag-source-validator/README.md)

Framework documentation:

- [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov)

## License

MIT
