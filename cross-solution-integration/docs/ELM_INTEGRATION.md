# ELM Integration — Provisioning Hooks

This document describes how the Cross-Solution Integration layer connects to Environment Lifecycle Management (ELM) to automatically initialize governance solutions when new environments are provisioned.

---

## Overview

When ELM provisions a new Power Platform environment, the integration layer automatically:

1. **Detects** the ProvisioningCompleted event via Dataverse trigger
2. **Extracts** environment metadata (ID, name, URL, zone, security group)
3. **Registers** the environment in ACV's `fsi_environmentregistry` table
4. **Logs** the initialization action back to ELM's `fsi_provisioninglog`
5. **Notifies** administrators via Teams

This closes the lifecycle gap where new environments existed but were unknown to governance solutions until their next scheduled scan.

---

## Trigger Mechanism

### Event Source

The `ELM-SolutionInitializer` flow triggers on new records in `fsi_provisioninglog` where:

```
fsi_action eq 13 (ProvisioningCompleted) AND fsi_success eq true
```

This event is written by ELM's Main Provisioning flow as the final step after all creation, configuration, and security group binding steps complete.

### Data Available from ELM

| Field | Source | Description |
|-------|--------|-------------|
| `fsi_environmentid` | `fsi_environmentrequest` | Power Platform environment GUID |
| `fsi_environmentname` | `fsi_environmentrequest` | Display name (DEPT-Purpose-TYPE) |
| `fsi_environmenturl` | `fsi_environmentrequest` | Dataverse URL |
| `fsi_zone` | `fsi_environmentrequest` | Zone classification (1/2/3) |
| `fsi_securitygroupid` | `fsi_environmentrequest` | Entra security group (Zone 2/3) |
| `fsi_requestnumber` | `fsi_environmentrequest` | ELM request reference |
| `fsi_environmenttype` | `fsi_environmentrequest` | Sandbox/Production/Developer |

---

## Cascade Contract

### Phase 1 (v1.0.0) — ACV Registration Only

On ProvisioningCompleted, the integration layer:

| Downstream Solution | Action | Data Written |
|--------------------|--------|-------------|
| **ACV** | Create `fsi_environmentregistry` record | name, environmentId, zone, status=Active, environmentType, environmentUrl, discoveredOn, notes |

**ACV idempotency:** If `fsi_environmentid` already exists in `fsi_environmentregistry`, the flow updates the existing record's zone and status instead of creating a duplicate.

### Phase 2 (v1.1.0+) — Extended Cascade

Future integration could cascade to additional solutions:

| Downstream Solution | Action | Data | Status |
|--------------------|--------|------|--------|
| **AAM** | Trigger initial access scan | environmentId, zone | Planned |
| **CMM** | Register for moderation monitoring | environmentId, zone | Planned |
| **FUS** | Register for file upload monitoring | environmentId, zone | Planned |
| **SSC** | No action (tenant-level) | — | N/A |

**Rationale for Phase 1 scope:** AAM, CMM, and FUS naturally discover environments during their daily scans. ACV is the exception because it maintains a persistent environment registry that other solutions don't. Registering in ACV ensures the first daily scan includes the new environment.

---

## PowerShell Alternative

For environments where Power Automate is not available, use `Register-ProvisionedEnvironment.ps1`:

```powershell
.\Register-ProvisionedEnvironment.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "tenant-guid" `
    -EnvironmentId "env-guid" `
    -EnvironmentName "TRADING-AgentOps-PROD" `
    -EnvironmentUrl "https://trading-agentops.crm.dynamics.com" `
    -Zone 3 `
    -EnvironmentType 1 `
    -Interactive
```

---

## Logging

The integration flow logs its actions back to ELM's `fsi_provisioninglog` table:

| Field | Value |
|-------|-------|
| `fsi_name` | `INT-Init-{environmentName}` |
| `fsi_action` | 11 (BaselineConfigApplied — reused for integration init) |
| `fsi_actiondetails` | JSON with action, acvRegistered, zone, environmentId |
| `fsi_actor` | `CrossSolutionIntegration` |
| `fsi_actortype` | 3 (System) |
| `fsi_success` | true/false |

---

*ELM Integration Guide v1.0.0 — February 2026*
