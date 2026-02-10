# Dataverse Schema

> **Status:** Stub — Full schema documentation will be added in Phase 2.

## Tables

| Table | Purpose | Phase |
|-------|---------|-------|
| `fsi_moderationbaseline` | Captured moderation baselines per agent | Phase 2 |
| `fsi_moderationvalidationhistory` | Immutable validation run records | Phase 2 |
| `fsi_moderationviolation` | Individual agent-level violations | Phase 2 |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `fsi_CMM_GovernanceEnvironmentUrl` | Central governance Dataverse URL | — |

## Connection References

| Reference | Purpose |
|-----------|---------|
| Dataverse (current environment) | Read/write governance tables |

See `src/dataverse/` for schema definitions when available.
