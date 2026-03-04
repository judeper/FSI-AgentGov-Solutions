# Architecture

## Deployment Layers

Solutions are organized into layers that build on each other:

```mermaid
graph TB
    subgraph Layer 3 - Integration
        CSI[Cross-Solution Integration]
        CD[Compliance Dashboard]
    end

    subgraph Layer 2 - Domain Solutions
        AI[Access & Identity<br/>5 solutions]
        CDP[Content & Data<br/>4 solutions]
        CA[Compliance & Audit<br/>3 solutions]
        MA[Monitoring & Analytics<br/>4 solutions]
        AC[Agent Configuration<br/>4 solutions]
        LO[Lifecycle & Operations<br/>5 solutions]
    end

    subgraph Layer 1 - Foundation
        AOF[Agent Observability Foundation]
    end

    AOF --> AI & CDP & CA & MA & AC & LO
    AI & CDP & CA & MA & AC & LO --> CD
    CD --> CSI
```

## Data Flow

All solutions follow a consistent data flow pattern:

```mermaid
graph LR
    subgraph Sources
        PP[Power Platform API]
        UAL[Unified Audit Log]
        Graph[Microsoft Graph]
    end

    subgraph Processing
        PS[PowerShell Scripts]
        PY[Python Scripts]
        KQL[KQL Queries]
    end

    subgraph Storage
        DV[(Dataverse)]
        LA[(Log Analytics)]
    end

    subgraph Reporting
        PBI[Power BI]
        Teams[Teams Alerts]
        Email[Email Reports]
    end

    PP --> PS & PY
    UAL --> KQL & PY
    Graph --> PS & PY
    PS & PY --> DV
    KQL --> LA
    DV --> PBI & CSI2[Cross-Solution Integration]
    LA --> PBI
    PS & PY --> Teams & Email
```

## Integration Patterns

### Solution → Dataverse

Each solution writes to its own Dataverse tables using the `fsi_` publisher prefix. Tables follow a consistent naming convention:

```
fsi_{solutionprefix}{entityname}
```

Examples: `fsi_agentaccessvalidation`, `fsi_scopedriftviolation`, `fsi_contentmoderationresult`

### Solution → Compliance Dashboard

Solutions integrate with the Compliance Dashboard through the [Cross-Solution Integration](../solutions/cross-solution-integration/index.md) solution, which:

1. Reads validation results from each solution's Dataverse tables
2. Normalizes status values to a common schema (Compliant / Non-Compliant / Partial / Unknown)
3. Writes aggregated results to the Compliance Dashboard tables
4. Exports evidence packages for regulatory examinations

### Alert Patterns

Solutions use two alert channels:

| Channel | Use Case | Latency |
|---------|----------|---------|
| **Teams Adaptive Cards** | Real-time violation alerts for governance teams | Near real-time |
| **Email Reports** | Scheduled compliance summaries for management | Scheduled (daily/weekly) |

## Authentication

All solutions authenticate using one of two patterns:

| Pattern | Use Case | Configuration |
|---------|----------|---------------|
| **Interactive** | Local development and testing | `Add-PowerAppsAccount` / browser-based |
| **Service Principal** | Production automation | App registration with certificate or secret |

Service principals are configured per-solution with least-privilege permissions. See individual solution prerequisites for required Graph and Dataverse permissions.

## Environment Topology

```mermaid
graph TB
    subgraph Production
        GOV[Governance Environment<br/>Dataverse + Flows]
        Z3[Zone 3 Environments<br/>Enterprise Agents]
    end

    subgraph Non-Production
        Z2[Zone 2 Environments<br/>Team Agents]
        Z1[Zone 1 Environments<br/>Personal Agents]
        DEV[Development<br/>Solution Testing]
    end

    GOV -->|monitors| Z3
    GOV -->|monitors| Z2
    GOV -->|monitors| Z1
    DEV -->|promotes to| GOV
```

The recommended topology is a dedicated **Governance Environment** that runs all monitoring solutions and stores compliance data. This environment monitors agent configurations across all Zone 1/2/3 environments.
