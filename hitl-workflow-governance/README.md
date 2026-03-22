# HITL Workflow Governance

> **Status:** Preview placeholder — documentation-only. This folder reserves the solution namespace for Copilot Studio human-review governance content. No deployable flows, scripts, Dataverse schema, or runtime solution artifacts are included yet.
>
> ⚠️ **Preview Feature:** The capability documented here is currently in Microsoft preview.
> Microsoft Learn shows the Copilot Studio **Request for information** action in public preview, and the **Human in the loop** connector actions remain marked as preview.
> Do not deploy in production without reviewing the current Microsoft release-plan status and [Power Platform preview terms](https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/).
> This documentation will be updated when the feature reaches general availability.

## Overview

HITL Workflow Governance is a future documentation-first placeholder for organizations that want consistent evidence around human review checkpoints inside Copilot Studio agent flows. The intended scope is governance telemetry for native human-review steps, such as **Request for information**, where a flow pauses and waits for a reviewer response before continuing.

This placeholder exists to document the future boundary now without introducing premature Power Platform artifacts or duplicating capabilities already covered by existing supervision solutions.

## Intended Control Alignment

| Control | Intended relationship |
|---------|------------------------|
| **2.12** | Supports supervision evidence showing that required human review checkpoints were invoked and resolved. |
| **2.17** | Helps document human checkpoints inside multi-step or multi-agent workflow patterns. |
| **1.10** | Supports retention of reviewer identity, decision context, and timestamps for output review workflows. |

## Boundary with Existing Solutions

| Existing solution | Current role | Boundary for this placeholder |
|------------------|--------------|-------------------------------|
| [FINRA Supervision Workflow](../finra-supervision-workflow/) | Routes items that require supervisory review and tracks queue activity. | HITL Workflow Governance is intended for native Copilot Studio in-flow human checkpoints, not general supervision queue management. |
| [Hallucination Tracker](../hallucination-tracker/) | Analyzes feedback and override patterns after execution. | This placeholder is not a quality analytics solution; its intended scope is human-review event evidence. |
| [Cross-Solution Integration](../cross-solution-integration/) | Normalizes evidence into the Compliance Dashboard. | This placeholder would contribute review evidence only after GA guidance and stable telemetry are available. |

## Microsoft Feature Status

- Microsoft lists **Request information from humans in the loop in agent flows** as public preview in the Copilot Studio 2025 release wave 1 plan.
- The current Copilot Studio documentation states that **Request for information** is available only in agent flows.
- The Microsoft **Human in the loop** connector reference still labels **Request for information** and **Run a multistage approval** as preview.
- A general availability date was not listed in the Microsoft release-plan material reviewed for this placeholder on March 22, 2026.
- Microsoft preview terms note that preview features can have reduced or different security, compliance, data residency, and data retention commitments. Organizations should verify whether the specific preview is designated as production ready before using regulated data.

## What Is Intentionally Not Included Yet

- Deployable Power Platform solution packages
- Power Automate flow JSON or other runtime artifacts
- Dataverse schema scripts or table definitions
- SLA, retention, or evidence claims beyond the intended future scope described here

## Recommended Current Approach

1. Use [FINRA Supervision Workflow](../finra-supervision-workflow/) for current supervisory queueing and review tracking.
2. Use the FSI-AgentGov [Human-in-the-Loop trigger guidance](https://judeper.github.io/FSI-AgentGov/playbooks/advanced-implementations/human-in-the-loop-triggers/) when building preview human-review steps.
3. Revisit this folder when Microsoft publishes stable GA guidance for HITL governance signals, retention behavior, and admin controls.

## Microsoft References

- [Request information from humans in the loop](https://learn.microsoft.com/en-us/microsoft-copilot-studio/flows-request-for-information)
- [Request information from humans in the loop in agent flows](https://learn.microsoft.com/en-us/power-platform/release-plan/2025wave1/microsoft-copilot-studio/request-information-humans-loop-agent-flows)
- [Human in the loop connector reference](https://learn.microsoft.com/en-us/connectors/advancedapprovals/)
- [Power Platform and Dynamics 365 preview terms](https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v0.1.0-preview | March 2026 | Initial documentation-only placeholder. No deployable artifacts are included while Microsoft HITL capabilities remain preview-only. |
