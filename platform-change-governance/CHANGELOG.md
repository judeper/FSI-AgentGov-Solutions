# Changelog

## [1.0.0] - January 2026

### Initial Release

**Solution Components:**

- MessageCenterPost, AssessmentLog, DecisionLog tables
- 4 security roles (MC Admin, MC Owner, MC Compliance Reviewer, MC Auditor)
- Model-driven app with forms, views, and dashboard
- Business Process Flow (New → Triage → Assess → Decide → Closed)
- Environment variables: MCG_TenantId, MCG_PollingInterval (default: 6 hours)

**Repository Structure:**

- Unmanaged solution .zip for portal import
- Unpacked src/ folder for version control and customization
- Comprehensive README with prerequisites (DLP, Solution Checker)

### Prerequisites

Before importing, verify:

- DLP policy allows HTTP connector to graph.microsoft.com
- Solution Checker enforcement mode (if Managed Environment)
- Required permissions (Environment Maker, Application Administrator)

### Documentation

Full documentation available in FSI-AgentGov:

- [Platform Change Governance Playbook](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/platform-change-governance/index.md)
