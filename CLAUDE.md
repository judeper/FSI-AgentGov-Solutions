# FSI-AgentGov-Solutions

## Purpose

Reference implementations for the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/).
These solutions help Financial Services organizations implement operational controls and monitoring for AI agents
(Copilot Studio, Agent Builder).

## Relationship to Framework

| Framework Site | This Repository |
|----------------|-----------------|
| Principles, zones, controls | Working implementations |
| Control Catalog (61 controls) | Scripts, packages, templates |
| Playbooks (step-by-step) | Deployable solutions |

Solutions here may address one or multiple controls from the framework.

## Target Audience

- **Power Platform Administrators**: Deploy and configure solutions
- **Agent Platform Teams**: Monitor platform changes affecting agents
- **Microsoft Partners**: Customize for client environments

## Solutions

| Solution | Description | Type | Version |
|----------|-------------|------|---------|
| [message-center-monitor](./message-center-monitor/) | M365 Message Center monitoring for platform changes | Power Automate/Dataverse | v2.0.0 |
| [pipeline-governance-cleanup](./pipeline-governance-cleanup/) | Discover, notify, and clean up personal pipelines before enforcing centralized ALM governance | PowerShell/Manual | v1.0.5 |
| [deny-event-correlation-report](./deny-event-correlation-report/) | Daily deny event correlation across Purview Audit, DLP, and Application Insights | PowerShell/KQL | v1.0.0 |

## Conventions

### Folder Structure
- Folder names: `kebab-case`
- Structure flexible by solution type (Power Automate, PowerShell, Python)

### Deployment
Solutions provide setup guides for:
1. Power Automate flows
2. Dataverse tables
3. Azure resources (Key Vault, App Registrations)

### Documentation
- Each solution: README.md with prerequisites, deployment, usage
- Supporting guides: Flow setup, Teams integration, secrets management

## Roadmap

Planned solution areas:
- Agent lifecycle management
- Environment governance
- Integration templates (Power Automate)
