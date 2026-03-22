# Deployment Guide

> **Version:** v0.1 — Verified information only. Sections marked TODO require product team input.

This guide maps common customer questions to specific solutions and provides deployment sequencing based on documented solution dependencies.

## Use-Case Mapping

When a customer asks one of these questions, deploy the corresponding solutions:

| Customer Need | Solutions to Deploy | Notes |
|---------------|-------------------|-------|
| "How do we control who agents are shared with?" | [Unrestricted Agent Sharing Detector](./unrestricted-agent-sharing-detector/), [Agent Sharing Access Restriction Detector](./agent-sharing-access-restriction-detector/), [Agent Access Governance Monitor](./agent-access-monitor/) | UASD handles org-wide/public sharing violations with automated remediation; ASARD enforces zone-based sharing policies with approval workflows; AAM monitors overly permissive access configurations |
| "How do we monitor agent execution and platform changes?" | [Agent Observability Foundation](./agent-observability-foundation/), [Message Center Monitor](./message-center-monitor/), [Scope Drift Monitor](./scope-drift-monitor/) | AOF provides foundational telemetry; MCM tracks M365 platform changes; SDM detects data access beyond declared scope |
| "How do we track agent performance and feedback?" | [Hallucination Tracker](./hallucination-tracker/), [Agent Observability Foundation](./agent-observability-foundation/), [Copilot Studio Analytics](./copilot-studio-analytics/) | HT aggregates hallucination feedback patterns; AOF provides operational metrics; CSA provides business impact analytics |
| "How do we enforce conditional access for AI workloads?" | [Conditional Access Automation](./conditional-access-automation/), [Session Security Configurator](./session-security-configurator/) | CAA deploys and monitors CA policies; SSC validates session security per zone |
| "How do we handle regulatory compliance evidence?" | [Compliance Dashboard](./compliance-dashboard/), [Cross-Solution Integration](./cross-solution-integration/), [Audit Compliance Manager](./audit-compliance-manager/) | CD provides aggregated reporting across the 78-control baseline with Exchange coverage; CSI wires Tier 2 solutions into the dashboard; ACM validates configurations and remediates gaps |
| "How do we manage environment provisioning governance?" | [Environment Lifecycle Management](./environment-lifecycle-management/), [Pipeline Governance Cleanup](./pipeline-governance-cleanup/) | ELM provisions environments with zone classification; PGC enforces ALM governance |
| "How do we control file uploads and content moderation?" | [File Upload Security Configurator](./file-upload-security/), [MIME Type Restrictions](./mime-type-restrictions/), [Content Moderation Governance Monitor](./content-moderation-monitor/) | FUS validates file upload settings; MIME enforces type restrictions; CMM monitors content moderation per zone |

## Solution Layers

Solutions fall into three deployment layers. Deploy foundational solutions first, then add monitoring and governance solutions as needed.

### Layer 1: Foundational Infrastructure

These solutions provide shared infrastructure that other solutions depend on:

| Solution | Role | Version |
|----------|------|---------|
| [Environment Lifecycle Management](./environment-lifecycle-management/) | Zone-based environment provisioning and classification | v1.1.2 |
| [Agent Observability Foundation](./agent-observability-foundation/) | Foundational telemetry and monitoring infrastructure | v1.1.0 |

### Layer 2: Tier 2 Governance Solutions

These solutions operate independently but can be wired into the Compliance Dashboard via [Cross-Solution Integration](./cross-solution-integration/):

| Solution | Controls | Integration |
|----------|----------|-------------|
| [Audit Compliance Manager](./audit-compliance-manager/) | 1.7 | Dashboard Assessment |
| [Session Security Configurator](./session-security-configurator/) | 1.23, 1.11 | Dashboard Assessment |
| [Agent Access Governance Monitor](./agent-access-monitor/) | 3.8 | Dashboard Assessment |
| [Content Moderation Governance Monitor](./content-moderation-monitor/) | 1.8 | Dashboard Assessment |
| [File Upload Security Configurator](./file-upload-security/) | 1.14 | Dashboard Assessment |
| [Conditional Access Automation](./conditional-access-automation/) | 1.11, 1.23, 1.18 | Dashboard Assessment |

### Layer 3: Standalone Solutions

All other solutions operate independently and can be deployed in any order based on customer needs. See the [Solutions Index](https://judeper.github.io/FSI-AgentGov/reference/solutions-index/) for detailed descriptions and control mappings.

## Compliance Dashboard Integration

To stand up unified compliance reporting:

1. Deploy **Layer 1** solutions (ELM for zone classification)
2. Deploy the **Tier 2** solutions your customer needs (Layer 2)
3. Deploy **Compliance Dashboard** with `fsi_controlmaster` table populated
4. Deploy **Cross-Solution Integration** to wire Tier 2 results into the dashboard
5. Run `Sync-SolutionAssessments.ps1` for initial assessment sync
6. Deploy `CD-SolutionFeedCollector` flow for daily automated feeds

See [Cross-Solution Integration README](./cross-solution-integration/README.md) for prerequisites and setup.

## TODO: Full Dependency Tree

<!-- TODO: Document complete inter-solution dependencies beyond Tier 2 wiring.
     Requires product team architectural review to verify which standalone solutions
     have undocumented dependencies on shared infrastructure. -->

## TODO: Zone Deployment Roadmap

<!-- TODO: Define minimum viable solution sets per governance zone.
     Requires product team input on zone-specific regulatory requirements
     and recommended deployment sequences. -->

## Related Documentation

- [Solutions Index](https://judeper.github.io/FSI-AgentGov/reference/solutions-index/) — Detailed descriptions and framework alignment
- [Solutions Coverage Gaps](https://judeper.github.io/FSI-AgentGov/reference/solutions-coverage-gaps/) — Coverage analysis across the 78-control baseline
- [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov) — Full framework documentation
