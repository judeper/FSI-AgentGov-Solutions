# Credential Oversharing Detector

> **Status:** Planned preview placeholder — documentation-only. This folder reserves the solution namespace for Copilot Studio credential-scope governance content. No deployable flows, scripts, Dataverse schema, or runtime solution artifacts are included yet.
>
> ⚠️ **Planned Preview Feature:** The capability documented here is listed in the Microsoft 2026 release plan.
> Microsoft currently shows **Enforce safe sharing by detecting credential oversharing** as public preview in **April 2026** and general availability in **June 2026**. Delivery dates may change.
> Do not deploy in production without reviewing the current Microsoft release-plan status and [Power Platform preview terms](https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/).
> This documentation will be updated when the feature reaches general availability.

## Overview

Credential Oversharing Detector is a future documentation-first placeholder for organizations that need governance evidence around agent credentials that are broader than the agent's approved operating scope. The intended scope is configuration-time review of connector authorizations, service accounts, and safe-sharing signals exposed by Copilot Studio once the underlying feature is available.

This placeholder exists to preserve the namespace and describe the future boundary without creating premature flows, schemas, or remediation logic before Microsoft publishes stable feature behavior and admin guidance.

## Intended Control Alignment

| Control | Intended relationship |
|---------|------------------------|
| **1.14** | Supports review of least-privilege access for agent data connections and connector credentials. |
| **1.4** | Helps document governance for approved connector configurations and authentication patterns. |
| **1.18** | Adds credential-scope context to agent sharing reviews so shared agents can be evaluated beyond recipient scope alone. |

## Boundary with Existing Solutions

| Existing solution | Current role | Boundary for this placeholder |
|------------------|--------------|-------------------------------|
| [Agent Sharing Access Restriction Detector](../agent-sharing-access-restriction-detector/) | Governs who an agent can be shared with. | Credential Oversharing Detector is intended for the credentials or authorizations the agent carries, not the recipient list itself. |
| [Scope Drift Monitor](../scope-drift-monitor/) | Monitors runtime data access beyond declared scope. | This placeholder is intended for configuration-time credential oversharing signals rather than runtime usage drift. |
| [File Upload Security Configurator](../file-upload-security/) | Governs file-upload controls for agents. | This placeholder is broader and would focus on connector and service-account scope across agent sharing scenarios. |

## Microsoft Feature Status

- The Copilot Studio 2026 release wave 1 plan lists **Enforce safe sharing by detecting credential oversharing** with public preview in April 2026 and general availability in June 2026.
- The Power Platform governance administration 2026 release plan also lists enhanced admin controls with preview in March 2026 and general availability in April 2026.
- Microsoft preview terms note that preview features can have reduced or different security, compliance, data residency, and data retention commitments. Organizations should verify preview status before using regulated data with this capability.
- Until Microsoft publishes stable admin surfaces and implementation guidance, this folder remains documentation-only.

## What Is Intentionally Not Included Yet

- Deployable Power Platform solution packages
- Power Automate flow JSON or other runtime artifacts
- Dataverse schema, alerting workflows, or remediation scripts
- Claims that credential oversharing telemetry is already available before Microsoft releases the feature

## Recommended Current Approach

1. Use [Agent Sharing Access Restriction Detector](../agent-sharing-access-restriction-detector/) for current sharing-principal governance.
2. Use [Scope Drift Monitor](../scope-drift-monitor/) for runtime access monitoring and exception workflows.
3. Review connector and service-account scope manually for high-risk agents until Microsoft releases supported credential-oversharing signals.

## Microsoft References

- [Enforce safe sharing by detecting credential oversharing](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/microsoft-copilot-studio/enforce-safe-sharing-detecting-credential-oversharing)
- [New and planned features for Microsoft Copilot Studio, 2026 release wave 1](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/microsoft-copilot-studio/planned-features)
- [Manage Copilot security with enhanced admin controls](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/power-platform-governance-administration/manage-copilot-security-enhanced-admin-controls)
- [Power Platform and Dynamics 365 preview terms](https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v0.1.0-preview | March 2026 | Initial documentation-only placeholder. No deployable artifacts are included before the Microsoft safe-sharing feature enters preview. |
