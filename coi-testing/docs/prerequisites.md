# Prerequisites

Requirements for deploying and running the COI Testing Framework.

## Python Environment

| Requirement | Minimum Version | Notes |
|-------------|----------------|-------|
| **Python** | 3.9+ | 3.11 or later recommended for performance |
| **pip** | Latest | Required for dependency installation |

## Package Dependencies

Install from the solution's requirements file:

```bash
pip install -r scripts/requirements.txt
```

| Package | Version | Purpose |
|---------|---------|---------|
| `msal` | ≥ 1.30.0 | Microsoft Authentication Library — acquires OAuth 2.0 tokens for Dataverse and Direct Line API access |
| `requests` | ≥ 2.32.0 | HTTP client for Dataverse Web API and Direct Line API calls |

## Microsoft Entra ID App Registration

The test runner authenticates using a confidential client (service principal). Register an application in Entra ID:

1. Navigate to **Azure Portal → Entra ID → App registrations → New registration**
2. Set a name (e.g., `COI-Testing-ServicePrincipal`)
3. Under **Certificates & secrets**, create a client secret
4. Record the following values — the script reads them from environment variables:

| Environment Variable | Source |
|---------------------|--------|
| `AZURE_TENANT_ID` | Directory (tenant) ID from the app's Overview blade |
| `AZURE_CLIENT_ID` | Application (client) ID from the app's Overview blade |
| `AZURE_CLIENT_SECRET` | Client secret value created above |

## API Permissions

Grant the app registration the following permissions:

| API | Permission | Type | Purpose |
|-----|-----------|------|---------|
| **Dataverse** (`{environment}/.default`) | `user_impersonation` | Application | Read/write COI test results to Dataverse tables |

> **Note:** Direct Line API access for agent interaction is planned but not yet implemented in the current release.

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows for scheduled test execution |
| **Dataverse capacity** | Storage for test results (`fsi_coitestresults` table) |
| **Copilot Studio** | Agent API access via Direct Line (future release) |

## Dataverse Requirements

The solution stores test results in a custom Dataverse table. The following columns are used by `run_coi_tests.py`:

| Logical Name | Type | Description |
|-------------|------|-------------|
| `fsi_scenarioid` | Text | Test scenario identifier (e.g., `PB-001`) |
| `fsi_scenarioname` | Text | Human-readable scenario name |
| `fsi_category` | Text | Test category (`proprietary_bias`, `suitability`, `fee_transparency`, `cross_selling`) |
| `fsi_status` | Choice | `1` = Pass, `2` = Fail, `3` = Skipped, `4` = Warn, `5` = Error |
| `fsi_executedon` | DateTime | UTC timestamp of test execution |
| `fsi_findings` | Text (multiline) | JSON array of finding details |

Deploy the Dataverse schema before running tests:

Create the `fsi_coitestresults` table using the schema documentation in this `docs/` directory or the solution's schema creation script when available. There is no pre-built solution zip to import.

## Role Requirements

| Role | Required For |
|------|--------------|
| **Agent Reader** | Query agent via Direct Line API |
| **System Administrator** or **Dataverse User** with table-level create/read | Write test results to `fsi_coitestresults` |

## Network Requirements

The test runner makes outbound HTTPS calls to:

| Endpoint | Purpose |
|----------|---------|
| `login.microsoftonline.com` | OAuth 2.0 token acquisition |
| `{your-org}.crm.dynamics.com` | Dataverse Web API (result storage) |
| Direct Line endpoint (future) | Agent interaction for test execution |

Verify these endpoints are reachable from the machine running the tests, especially in environments with proxy or firewall restrictions.

---

*FSI Agent Governance Framework — COI Testing*
