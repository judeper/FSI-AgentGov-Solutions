# Shared Utilities

Two shared utilities in `scripts/shared/` are used across multiple solutions.

## Dataverse Client (`dataverse_client.py`)

Python client for the Dataverse Web API with MSAL authentication, automatic retry, and dry-run support.

### Features

| Feature | Description |
|---------|-------------|
| **MSAL Authentication** | Client credential flow with certificate or secret |
| **Automatic Retry** | Exponential backoff for transient failures (429, 500, 503) |
| **Dry-Run Mode** | Preview operations without writing to Dataverse |
| **Batch Operations** | Efficient bulk create/update with `$batch` endpoint |
| **Pagination** | Automatic handling of `@odata.nextLink` |

### Usage

```python
from scripts.shared.dataverse_client import DataverseClient

client = DataverseClient(
    environment_url="https://org.crm.dynamics.com",
    tenant_id="your-tenant-id",
    client_id="your-client-id",
    client_secret="your-secret",  # or certificate_path
)

# Query records
results = client.query("fsi_agentaccessvalidations", select=["fsi_agentid", "fsi_status"])

# Create record
client.create("fsi_agentaccessvalidations", {
    "fsi_agentid": "agent-001",
    "fsi_status": "Compliant"
})
```

### Configuration

| Parameter | Description | Required |
|-----------|-------------|----------|
| `environment_url` | Dataverse environment URL | Yes |
| `tenant_id` | Microsoft Entra ID tenant ID | Yes |
| `client_id` | App registration client ID | Yes |
| `client_secret` | Client secret (alternative to certificate) | One of |
| `certificate_path` | PFX certificate path | One of |
| `dry_run` | Preview mode (default: `False`) | No |

## Zone Classification (`Get-ZoneClassification.ps1`)

PowerShell function that determines the governance zone (1, 2, or 3) for a Power Platform environment.

### Zone Definitions

| Zone | Name | Description |
|------|------|-------------|
| 1 | Personal | Individual productivity, lowest governance |
| 2 | Team | Departmental use, moderate governance |
| 3 | Enterprise | Organization-wide, highest governance |

### Usage

```powershell
. ./scripts/shared/Get-ZoneClassification.ps1

# Get zone for an environment
$zone = Get-ZoneClassification -EnvironmentId "env-guid-here"

# Use in validation
if ($zone -ge 2) {
    # Apply team/enterprise governance rules
}
```

### Classification Logic

Zone classification is based on environment properties:

1. **Environment type** — Default and developer environments are Zone 1
2. **DLP policy assignment** — Environments with restrictive DLP policies indicate Zone 2+
3. **Managed environment status** — Managed environments are Zone 2 or 3
4. **Custom metadata** — `fsi_GovernanceZone` environment variable override

### Solutions Using These Utilities

| Solution | `dataverse_client.py` | `Get-ZoneClassification.ps1` |
|----------|----------------------|------------------------------|
| Agent Access Monitor | Yes | Yes |
| Conditional Access Automation | Yes | Yes |
| Content Moderation Monitor | Yes | Yes |
| File Upload Security | Yes | Yes |
| Scope Drift Monitor | Yes | Yes |
| Session Security Configurator | Yes | Yes |
| Environment Lifecycle Management | Yes | Yes |
| Cross-Solution Integration | Yes | — |
