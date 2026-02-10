---
phase: 3
plan: summary
title: "ELM Provisioning Hooks — Phase Summary"
status: COMPLETE
requirements: [ELM-01, ELM-02, ELM-03]
---

# Phase 3 Summary — ELM Provisioning Hooks

## What Was Done

### Plan 03-01: ELM-SolutionInitializer Child Flow (ELM-01, ELM-03)
Created `flows/elm-solution-initializer.json` — a Power Automate flow that triggers on `fsi_provisioninglog` records where `fsi_action eq 13` (ProvisioningCompleted) and `fsi_success eq true`. The flow:

1. Reads the parent `fsi_environmentrequest` for zone, name, URL, type
2. Checks ACV `fsi_environmentregistry` for existing record
3. Creates or updates the registry record with zone mapping
4. Logs initialization back to `fsi_provisioninglog` (action=11)
5. Posts Teams notification with registration summary

**Idempotency:** If `fsi_environmentid` already exists, the flow updates zone/status instead of creating a duplicate.

### Plan 03-02: Register-ProvisionedEnvironment.ps1 (ELM-02)
Created `scripts/powershell/Register-ProvisionedEnvironment.ps1` — PowerShell equivalent of the flow for environments without Power Automate:

- Interactive or service principal auth via MSAL
- Uses `Get-CanonicalZoneValue` from IntegrationConfig.psm1
- Duplicate detection by `fsi_environmentid` filter
- DryRun mode for validation before writing
- Auto-populates notes with ELM request number reference

### Plan 03-03: ELM Integration Documentation (ELM-03)
Created `docs/ELM_INTEGRATION.md` — cascade contract documentation:

- Trigger mechanism and data flow from ELM provisioning log
- Phase 1 scope: ACV registration only (with rationale)
- Phase 2 planned cascade: AAM, CMM, FUS auto-registration
- Field mapping from ELM request to ACV registry
- Logging format and action codes

## Requirements Satisfied

| ID | Requirement | Status |
|----|-------------|--------|
| ELM-01 | ProvisioningCompleted event triggers downstream init | ✅ SATISFIED |
| ELM-02 | ACV auto-registration with zone mapping | ✅ SATISFIED |
| ELM-03 | Cascade contract documented | ✅ SATISFIED |

## Artifacts Produced

| File | Purpose |
|------|---------|
| `flows/elm-solution-initializer.json` | Power Automate flow template |
| `scripts/powershell/Register-ProvisionedEnvironment.ps1` | PowerShell registration script |
| `docs/ELM_INTEGRATION.md` | Cascade contract and data flow documentation |

## Key Design Decisions

1. **Phase 1 = ACV only** — AAM/CMM/FUS discover environments during daily scans; ACV uniquely needs pre-registration because it maintains a persistent environment registry
2. **Webhook trigger** — uses Dataverse SubscribeWebhookTrigger for near-zero latency vs. polling
3. **Action code 11** — reuses BaselineConfigApplied for integration init logging (distinct from ProvisioningCompleted=13)
4. **Idempotent upsert** — handles re-provisioning without creating duplicates

## Dependency Graph

```
ELM (upstream)
  └── fsi_provisioninglog [fsi_action=13, fsi_success=true]
       └── ELM-SolutionInitializer
            ├── reads: fsi_environmentrequest (zone, name, URL)
            ├── writes: ACV fsi_environmentregistry (create/update)
            ├── writes: fsi_provisioninglog (action=11, init log)
            └── notifies: Teams channel
```
