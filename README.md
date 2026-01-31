# FSI-AgentGov-Solutions

Deployable Power Platform solutions for the [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov).

## Available Solutions

| Solution | Description | Version | Controls |
|----------|-------------|---------|----------|
| [Environment Lifecycle Management](./environment-lifecycle-management/) | Automated environment provisioning with zone-based governance | v1.0.1 | 2.1, 2.2, 2.3, 2.8, 1.7 |
| [Message Center Monitor](./message-center-monitor/) | M365 Message Center monitoring for platform changes | v2.0.0 | 2.3, 2.10 |
| [Pipeline Governance Cleanup](./pipeline-governance-cleanup/) | Personal pipeline discovery and ALM governance enforcement | v1.0.8 | 2.3, 2.1 |
| [Deny Event Correlation Report](./deny-event-correlation-report/) | Daily deny event correlation across Purview and App Insights | v1.1.0 | 1.5, 1.7, 3.4 |

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

Framework documentation:

- [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov)

## License

MIT
