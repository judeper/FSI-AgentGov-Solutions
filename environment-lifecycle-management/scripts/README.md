# Python Scripts

Automation scripts for Environment Lifecycle Management.

## Overview

| Script | Purpose |
|--------|---------|
| `elm_client.py` | Dataverse Web API client wrapper |
| `register_service_principal.py` | Entra app registration and Key Vault integration |
| `export_quarterly_evidence.py` | Quarterly evidence export with integrity hashing |
| `verify_role_privileges.py` | Security role privilege audit |
| `validate_immutability.py` | ProvisioningLog immutability verification |

## Prerequisites

### Python Version

Python 3.10 or higher required.

```bash
python --version  # Should be 3.10+
```

### Install Dependencies

```bash
pip install -r requirements.txt
```

### Authentication

Scripts use MSAL Confidential Client (app-only) authentication. You need:

| Parameter | Source |
|-----------|--------|
| `--tenant-id` | Entra ID > Overview > Tenant ID |
| `--client-id` | App registration > Application (client) ID |
| `--client-secret` | From Azure Key Vault or during registration |
| `--environment-url` | Dataverse environment URL (e.g., https://org.crm.dynamics.com) |

### Environment Variables (Optional)

Set environment variables to avoid passing credentials on command line:

```bash
export ELM_TENANT_ID="your-tenant-id"
export ELM_CLIENT_ID="your-client-id"
export ELM_CLIENT_SECRET="your-client-secret"
export ELM_ENVIRONMENT_URL="https://your-org.crm.dynamics.com"
```

## Script Details

### elm_client.py

Dataverse Web API wrapper with MSAL authentication.

**Usage as library:**

```python
from elm_client import ELMClient

client = ELMClient(
    tenant_id="...",
    client_id="...",
    client_secret="...",
    environment_url="https://org.crm.dynamics.com"
)

# Query EnvironmentRequest
requests = client.query("fsi_environmentrequests", select=["fsi_requestnumber", "fsi_state"])

# Create ProvisioningLog entry
client.create("fsi_provisioninglogs", {
    "fsi_action": 1,
    "fsi_actor": "script",
    "fsi_actortype": 3,
    "fsi_success": True
})
```

**Usage as CLI:**

```bash
# Test connection
python elm_client.py \
  --tenant-id <tenant> \
  --client-id <client> \
  --environment-url https://org.crm.dynamics.com \
  --test-connection
```

### register_service_principal.py

Creates Entra app registration and stores credentials in Key Vault.

**Usage:**

```bash
# Dry run (validate without creating)
python register_service_principal.py \
  --tenant-id <tenant> \
  --app-name ELM-Provisioning-ServicePrincipal \
  --key-vault-name <vault> \
  --dry-run

# Create new Service Principal
python register_service_principal.py \
  --tenant-id <tenant> \
  --app-name ELM-Provisioning-ServicePrincipal \
  --key-vault-name <vault> \
  --secret-name ELM-ServicePrincipal-Secret

# Rotate existing secret
python register_service_principal.py \
  --tenant-id <tenant> \
  --app-name ELM-Provisioning-ServicePrincipal \
  --key-vault-name <vault> \
  --rotate-secret
```

**Output:**

- Application ID (for PPAC registration)
- Secret stored in Key Vault
- Next steps for manual PPAC registration

### export_quarterly_evidence.py

Exports EnvironmentRequest and ProvisioningLog tables with SHA-256 integrity hashing.

**Usage:**

```bash
# Export Q1 2026
python export_quarterly_evidence.py \
  --environment-url https://org.crm.dynamics.com \
  --tenant-id <tenant> \
  --client-id <client> \
  --output-path ./exports \
  --start-date 2026-01-01 \
  --end-date 2026-03-31

# With verbose output
python export_quarterly_evidence.py \
  --environment-url https://org.crm.dynamics.com \
  --output-path ./exports \
  --start-date 2026-01-01 \
  --end-date 2026-03-31 \
  --verbose
```

**Output files:**

```
exports/
├── EnvironmentRequest-2026-Q1.json
├── ProvisioningLog-2026-Q1.json
└── manifest.json
```

**Manifest format:**

```json
{
  "exportDate": "2026-04-01T09:00:00Z",
  "dateRange": {
    "start": "2026-01-01",
    "end": "2026-03-31"
  },
  "files": [
    {
      "name": "EnvironmentRequest-2026-Q1.json",
      "recordCount": 42,
      "sha256": "abc123..."
    },
    {
      "name": "ProvisioningLog-2026-Q1.json",
      "recordCount": 380,
      "sha256": "def456..."
    }
  ]
}
```

### verify_role_privileges.py

Audits security role privileges to ensure correct configuration.

**Usage:**

```bash
# Basic check
python verify_role_privileges.py \
  --environment-url https://org.crm.dynamics.com \
  --tenant-id <tenant> \
  --client-id <client>

# Export to JSON
python verify_role_privileges.py \
  --environment-url https://org.crm.dynamics.com \
  --output-path ./reports/role-audit.json

# Check specific role
python verify_role_privileges.py \
  --environment-url https://org.crm.dynamics.com \
  --role-name "ELM Admin"
```

**Expected output:**

```
ELM Role Privilege Audit
========================

Checking ELM Requester...
  fsi_environmentrequest: Create(User) Read(User) Write(User) ✓
  fsi_provisioninglog: Read(User) ✓

Checking ELM Approver...
  fsi_environmentrequest: Read(BU) Write(BU) ✓
  fsi_provisioninglog: Read(BU) ✓

Checking ELM Admin...
  fsi_environmentrequest: Create(Org) Read(Org) Write(Org) Append(Org) AppendTo(Org) ✓
  fsi_provisioninglog: Create(Org) Read(Org) ✓
  [VERIFY] No Write privilege on fsi_provisioninglog ✓
  [VERIFY] No Delete privilege on fsi_provisioninglog ✓

Checking ELM Auditor...
  fsi_environmentrequest: Read(Org) ✓
  fsi_provisioninglog: Read(Org) ✓

Summary: All roles configured correctly
```

### validate_immutability.py

Verifies ProvisioningLog table has no unauthorized modifications.

**Usage:**

```bash
# Check last 7 days
python validate_immutability.py \
  --environment-url https://org.crm.dynamics.com \
  --tenant-id <tenant> \
  --client-id <client>

# Check specific date range
python validate_immutability.py \
  --environment-url https://org.crm.dynamics.com \
  --start-date 2026-01-01 \
  --end-date 2026-01-31

# Verbose output
python validate_immutability.py \
  --environment-url https://org.crm.dynamics.com \
  --verbose
```

**What it checks:**

1. No Update (operation=2) audit entries on fsi_provisioninglog
2. No Delete (operation=3) audit entries on fsi_provisioninglog
3. All log entries have required fields populated
4. No orphaned log entries (missing parent request)

**Expected output:**

```
ProvisioningLog Immutability Validation
=======================================

Date range: 2026-01-22 to 2026-01-29
Records checked: 156

Audit Log Analysis:
  Update attempts: 0 ✓
  Delete attempts: 0 ✓

Data Integrity:
  Records with missing fields: 0 ✓
  Orphaned records: 0 ✓

Result: PASSED - No immutability violations detected
```

**If violations found:**

```
ALERT: Immutability violations detected!

Update attempts: 3
  - 2026-01-25 14:32:00 by user@contoso.com (record: abc-123)
  - 2026-01-25 14:33:00 by user@contoso.com (record: abc-123)
  - 2026-01-26 09:15:00 by admin@contoso.com (record: def-456)

Delete attempts: 1
  - 2026-01-26 09:20:00 by admin@contoso.com (record: def-456)

Result: FAILED - Investigate immediately

Recommended actions:
1. Review security role assignments
2. Check for System Administrator overrides
3. Document incident per security policy
```

## Common Options

All scripts support these common options:

| Option | Description |
|--------|-------------|
| `--dry-run` | Validate without making changes |
| `--verbose` | Show detailed output |
| `--help` | Show usage information |

## Error Handling

Scripts return exit codes:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Authentication failure |
| 2 | API error |
| 3 | Validation failure |
| 4 | Configuration error |

## Logging

Scripts log to stderr. Redirect to file:

```bash
python validate_immutability.py ... 2> audit.log
```

## Security Notes

- Never commit credentials to source control
- Use environment variables or Key Vault for secrets
- Scripts support `--dry-run` for safe testing
- Review output before acting on results
