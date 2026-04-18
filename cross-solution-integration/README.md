# Cross-Solution Integration

Integration layer that connects the 6 Tier 2 governance solutions into the Compliance Dashboard and Environment Lifecycle Management workflow.

> **Status:** Completed

## Overview

The FSI Agent Governance Framework includes standalone governance solutions that each validate specific aspects of Copilot Studio agent compliance. This integration layer:

1. **Dashboard Feeds** — Pulls daily validation results from 6 Tier 2 solutions into the Compliance Dashboard for unified scoring
2. **ELM Provisioning Hooks** — Automatically registers newly provisioned environments in downstream solutions
3. **Unified Evidence Export** — Aggregates per-solution compliance evidence into a single regulatory examination package

## Connected Solutions

| Solution | Controls Fed | Feed Type |
|----------|-------------|-----------|
| Audit Configuration Validator (ACV) | 1.7 | Dashboard Assessment |
| Session Security Configurator (SSC) | 1.23, 1.11 | Dashboard Assessment |
| Agent Access Governance Monitor (AAM) | 3.8 | Dashboard Assessment |
| Content Moderation Governance Monitor (CMM) | 1.8 | Dashboard Assessment |
| File Upload Security Configurator (FUS) | 1.14 | Dashboard Assessment |
| Conditional Access Automation (CAA) | 1.11, 1.23, 1.18 | Dashboard Assessment |
| Environment Lifecycle Management (ELM) | — | Provisioning Hook |
| Compliance Dashboard (CD) | — | Assessment Target |

## Components

### PowerShell Scripts

| Script | Purpose |
|--------|---------|
| `IntegrationConfig.psd1` | Module manifest (metadata, GUID, FunctionsToExport) for IntegrationConfig.psm1 |
| `IntegrationConfig.psm1` | Shared constants, mappings, and translation functions |
| `Sync-SolutionAssessments.ps1` | Pull Tier 2 results → CD assessments |
| `Export-UnifiedComplianceEvidence.ps1` | Aggregate per-solution evidence into unified package |
| `Register-ProvisionedEnvironment.ps1` | Register newly provisioned environment in ACV registry |
| `Test-UnifiedEvidenceIntegrity.ps1` | Verify SHA-256 chain integrity of unified evidence package |

### Power Automate Flows

| Flow | Purpose |
|------|---------|
| CD-SolutionFeedCollector | Daily automated dashboard feed from all Tier 2 solutions |
| ELM-SolutionInitializer | Post-provisioning cascade to register environments in ACV |

> **Build instructions:** See [docs/flow-configuration.md](docs/flow-configuration.md) for step-by-step manual build instructions for both flows in Power Automate designer.

### Documentation

| Document | Purpose |
|----------|---------|
| `SCHEMA_CONTRACT.md` | Canonical option set values and cross-solution data contract |
| `STATUS_MAPPING.md` | Per-solution status → CD assessment translation logic |
| `CONFIGURATION.md` | Setup and configuration guide |
| `ELM_INTEGRATION.md` | ELM provisioning hook integration guide |
| `EVIDENCE_EXPORT.md` | Evidence export and regulatory packaging guide |
| `SCORE_CALCULATOR_UPDATE.md` | Score calculation update procedures |
| `TROUBLESHOOTING.md` | Common issues and resolution |

## Quick Start

### Prerequisites

- All 6 Tier 2 solutions deployed (ACV, SSC, AAM, CMM, FUS, CAA)
- Compliance Dashboard deployed with `fsi_controlmaster` table populated
- Environment Lifecycle Management deployed (for provisioning hooks)
- PowerShell 7.x with Microsoft.PowerApps.Administration.PowerShell module
- MSAL.PS module for Dataverse authentication

### Steps

1. Import `IntegrationConfig.psm1` module
2. Run `Sync-SolutionAssessments.ps1` to perform initial assessment sync
3. Build `CD-SolutionFeedCollector` flow per [docs/flow-configuration.md](docs/flow-configuration.md) for daily automation
4. (Optional) Build `ELM-SolutionInitializer` flow per [docs/flow-configuration.md](docs/flow-configuration.md) for provisioning hooks
5. Verify dashboard reflects automated assessments

## Version

v2.0.0 — April 2026
