# FSI-AgentGov-Solutions

Deployable Power Platform solutions for the [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov).

## Available Solutions

| Solution | Description | Status |
|----------|-------------|--------|
| [Message Center Monitor](./message-center-monitor/) | Monitor M365 Message Center for platform changes affecting AI agents | v2.0.0 |
| [Pipeline Governance Cleanup](./pipeline-governance-cleanup/) | Discover, notify, and clean up personal pipelines before enforcing centralized ALM governance | v1.0.5 |
| [Deny Event Correlation Report](./deny-event-correlation-report/) | Daily deny event correlation across Purview Audit, DLP, and Application Insights | v1.0.0 |

## How to Use

1. Navigate to the solution folder
2. Follow the README for prerequisites
3. Set up Azure AD app registration
4. Create Power Automate flow
5. Configure Teams notifications

## Documentation

All detailed documentation lives in each solution folder:

- [Message Center Monitor](./message-center-monitor/README.md)
- [Pipeline Governance Cleanup](./pipeline-governance-cleanup/README.md)
- [Deny Event Correlation Report](./deny-event-correlation-report/README.md)

Framework documentation:

- [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov)

## License

MIT
