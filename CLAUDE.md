# FSI-AgentGov-Solutions

## Purpose

Reference implementations for the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/).
These solutions help Financial Services organizations implement governance controls for AI agents
(Copilot Studio, Agent Builder) in compliance with SOX, FINRA, SEC, and other regulations.

## Relationship to Framework

| Framework Site | This Repository |
|----------------|-----------------|
| Principles, zones, controls | Working implementations |
| Control Catalog (61 controls) | Scripts, packages, templates |
| Playbooks (step-by-step) | Deployable solutions |

Solutions here may address one or multiple controls from the framework.

## Target Audience

- **Power Platform Administrators**: Deploy and configure solutions
- **Compliance Officers**: Evaluate governance capabilities
- **Microsoft Partners**: Customize for FSI client environments

## Solutions

| Solution | Description | Type |
|----------|-------------|------|
| platform-change-governance | M365 Message Center governance workflow | Python/Dataverse |

## Conventions

### Folder Structure
- Folder names: `kebab-case`
- Structure flexible by solution type (Python, PowerShell, Power Automate)

### Deployment
Solutions should provide both:
1. Script-based deployment (programmatic)
2. Solution packages (Power Platform import)

### Documentation
- Each solution: README.md with prerequisites, deployment, usage
- Compliance mapping: Single document at repository root (not per-solution)

## Roadmap

Planned solution areas:
- Agent lifecycle management
- Compliance reporting & dashboards
- Environment governance
- Integration templates (Power Automate)

Roadmap driven by framework requirements and FSI regulatory needs.
