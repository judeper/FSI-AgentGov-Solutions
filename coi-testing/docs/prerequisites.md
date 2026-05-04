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
| `azure-identity` | ≥ 1.25.0 | Microsoft Entra token authentication using managed identity, workload identity federation, certificate, Azure CLI, device code, or legacy client secret credentials |
| `requests` | ≥ 2.32.0 | HTTP client for Dataverse Web API and future Direct Line API calls |

## Authentication

The runner uses a managed-identity-first authentication chain for Dataverse writes. The default `--auth-mode auto` order is:

1. Managed identity (`ManagedIdentityCredential`)
2. Workload identity federation (`WorkloadIdentityCredential`)
3. Certificate credential (`CertificateCredential`)
4. Azure CLI credential for administrator workstations (`AzureCliCredential`)
5. Client secret credential only as a legacy development fallback

### Recommended production setup

1. Run the scheduled COI runner from an Azure-hosted workload such as Azure Functions, Azure Automation hybrid worker, Azure Container Apps, or an approved CI runner.
2. Enable a system-assigned managed identity, or assign a user-assigned managed identity and set `AZURE_MANAGED_IDENTITY_CLIENT_ID` to its client ID.
3. In Dataverse, create an application user for the managed identity or app registration and assign a least-privilege security role with Create and Read access to `fsi_coitestresults`.
4. Run the runner without client secret variables:

```bash
python scripts/run_coi_tests.py --environment "https://your-org.crm.dynamics.com" --allow-skipped
```

### Workload identity federation

For GitHub Actions or other OIDC-capable runners, configure a federated identity credential on the Microsoft Entra app registration and set:

| Environment Variable | Source |
|---------------------|--------|
| `AZURE_TENANT_ID` | Microsoft Entra tenant ID |
| `AZURE_CLIENT_ID` | Application (client) ID trusted by the federated identity credential |
| `AZURE_FEDERATED_TOKEN_FILE` | Path to the OIDC token file provided by the runner |

Run with:

```bash
python scripts/run_coi_tests.py --environment "https://your-org.crm.dynamics.com" --auth-mode workload-identity --allow-skipped
```

### Certificate authentication

For non-Azure automation where managed identity or workload identity federation isn't available, use certificate-based app-only authentication:

| Environment Variable | Source |
|---------------------|--------|
| `AZURE_TENANT_ID` | Microsoft Entra tenant ID |
| `AZURE_CLIENT_ID` | Application (client) ID |
| `AZURE_CLIENT_CERTIFICATE_PATH` | PEM or PKCS12 certificate file including the private key |
| `AZURE_CLIENT_CERTIFICATE_PASSWORD` | Optional certificate password |

### Local administrator runs

For local smoke tests, sign in with Azure CLI and use `--auth-mode azure-cli`, or run without Dataverse persistence:

```bash
python scripts/run_coi_tests.py --environment "https://your-org.crm.dynamics.com" --dry-run --allow-skipped
```

### Legacy development fallback

`AZURE_CLIENT_SECRET` is supported only for isolated development testing with `--auth-mode client-secret`. Do not use client secrets for production scheduled execution.

## API Permissions and Dataverse Authorization

Dataverse authorization for this runner is based on Dataverse application users and security roles. Configure a least-privilege security role with Create and Read privileges on the `fsi_coitestresults` table and assign it to the application user that represents the managed identity or app registration.

> **Note:** Direct Line API access for agent interaction is planned but not yet implemented in the current release. Future Direct Line integration must handle Direct Line token generation/refresh and OAuthCard sign-in flows for agents that require user authentication.

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Planned Power Automate or pipeline-driven scheduled test execution |
| **Dataverse capacity** | Storage for test results (`fsi_coitestresults` table) |
| **Copilot Studio** | Agent API access via Direct Line or Microsoft 365 Agents SDK in a future release |

## Dataverse Requirements

The solution stores test results in a custom Dataverse table. The following columns are used by `run_coi_tests.py`:

| Logical Name | Type | Description |
|-------------|------|-------------|
| `fsi_scenarioid` | Text | Test scenario identifier (e.g., `PB-001`) |
| `fsi_scenarioname` | Text | Human-readable scenario name |
| `fsi_category` | Text | Test category (`proprietary_bias`, `suitability`, `fee_transparency`, `cross_selling`) |
| `fsi_status` | Choice | PASS=`100000000`, FAIL=`100000001`, SKIPPED=`100000002`, WARN=`100000003`, ERROR=`100000004` |
| `fsi_executedon` | DateTime | UTC timestamp of test execution |
| `fsi_findings` | Text (multiline) | JSON array of finding details |

Deploy the Dataverse schema before running tests:

Create the `fsi_coitestresults` table using the schema documentation in this `docs/` directory or the solution's schema creation script when available. There is no pre-built solution zip to import.

## Role Requirements

| Role | Required For |
|------|--------------|
| **Power Platform Admin** | Create the custom Dataverse table, application user, and least-privilege security role |
| **Dataverse application user** | Write test results to `fsi_coitestresults` using managed identity, workload identity, certificate, or legacy development credentials |
| **Copilot Studio maker/admin** | Future Direct Line or Microsoft 365 Agents SDK setup for published agent invocation |

## Network Requirements

The test runner makes outbound HTTPS calls to:

| Endpoint | Purpose |
|----------|---------|
| `login.microsoftonline.com` | Microsoft Entra token acquisition for non-managed-identity auth modes |
| Azure managed identity endpoint | Token acquisition for Azure-hosted managed identities |
| `{your-org}.crm.dynamics.com` | Dataverse Web API result storage |
| Direct Line endpoint (future) | Agent interaction for test execution |

Verify these endpoints are reachable from the machine running the tests, especially in environments with proxy or firewall restrictions.

---

*FSI Agent Governance Framework — COI Testing*
