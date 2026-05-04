# Prerequisites

This document lists all requirements for deploying the Agent Observability Foundation solution.

## Azure Subscription Requirements

| Resource | Required Role | License Tier | Notes |
|----------|---------------|--------------|-------|
| Azure Subscription | Owner OR Contributor + User Access Admin | Pay-As-You-Go or EA | For resource creation and RBAC assignment |
| Resource Group | Contributor | (included in subscription) | Target for all telemetry resources |
| Application Insights | Contributor | Azure Monitor (included) | Workspace-based resource; 730-day retention may incur additional cost |
| Log Analytics Workspace | Log Analytics Contributor | Azure Monitor (included) | PerGB2018 pricing tier; 730-day retention |
| Storage Account (StorageV2) | Storage Account Contributor | Standard | For Diagnostic Settings export to Azure Blob Storage |
| RBAC Assignments | User Access Admin | (included in subscription) | For Monitoring Reader / Storage Blob Data Reader roles |

### Cost Considerations

| Resource | Estimated Monthly Cost | Cost Driver |
|----------|----------------------|-------------|
| Application Insights | $2.30/GB ingested | Telemetry volume |
| Log Analytics | $2.76/GB (730-day retention tier) | Retention period and query volume |
| Azure Blob Storage (StorageV2) | $0.018/GB (Cool tier) | Stored data volume |

> **Note:** Costs scale with telemetry volume. See [docs/cost-tuning-guide.md](docs/cost-tuning-guide.md) for sampling configuration to manage costs.

## Entra ID Requirements

| Requirement | Purpose |
|-------------|---------|
| Managed identity or workload identity | Recommended for hosted automation and CI/CD deployments |
| DefaultAzureCredential-compatible authentication | Script authentication discovery for managed identity, workload identity, interactive, or legacy development credentials |
| Service principal secret (optional, legacy dev-only) | Development fallback only; prefer managed identity or workload identity for production automation |
| Entra ID Application Administrator (if creating legacy service principal fallback) | Required only for legacy dev-only service principal fallback |

### Authentication Methods

The provisioning scripts use `DefaultAzureCredential` from the Azure Identity library. Configure credentials in this order of preference:

1. **System-assigned managed identity** for Azure-hosted runners or automation accounts
2. **User-assigned managed identity** for cross-resource automation
3. **Workload identity federation** for GitHub Actions or other CI/CD platforms
4. **Azure CLI / Azure PowerShell interactive login** for administrator workstation validation
5. **Service principal secret** only as a legacy development fallback (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_SECRET`)

For lab deployments, `az login` is the simplest method. For production CI/CD, prefer managed identity or workload identity federation instead of client secrets.

## Software Requirements

| Software | Version | Purpose |
|----------|---------|---------|
| Python | 3.9+ | Provisioning scripts |
| pip | Latest | Package management |
| Azure CLI (optional) | 2.60+ | Interactive authentication via `az login`; required for alert deployment |

### Python Packages

Install via `pip install -r scripts/requirements.txt`:

| Package | Version | Purpose |
|---------|---------|---------|
| azure-identity | 1.18.0+ | Authentication (DefaultAzureCredential) |
| azure-mgmt-applicationinsights | 4.1.0+ | Application Insights management |
| azure-mgmt-loganalytics | 13.0.0+ | Log Analytics workspace management |
| azure-mgmt-monitor | Latest | Diagnostic Settings configuration |
| azure-mgmt-storage | Latest | Storage account management |
| azure-mgmt-authorization | Latest | RBAC role assignment |
| pyyaml | Latest | Configuration file parsing |

## Network Requirements

The provisioning scripts require outbound HTTPS (port 443) access to:

- `management.azure.com` - Azure Resource Manager API
- `login.microsoftonline.com` - Entra ID authentication
- `*.blob.core.windows.net` - Azure Storage (for verification scripts)

> **Note:** If deploying from a corporate network with firewall restrictions, ensure these endpoints are accessible or use a jump box in Azure.

## Pre-Deployment Checklist

Complete these steps before running the provisioning scripts:

- [ ] **Azure subscription ID** - Note your subscription ID (visible in Azure Portal > Subscriptions)
- [ ] **Resource group** - Create resource group OR verify permissions to create one
- [ ] **Location selection** - Choose Azure region (e.g., `eastus`, `westus2`) near your Copilot Studio deployment
- [ ] **Entra ID authentication** - Configure managed identity/workload identity for hosted automation, or run `az login` for workstation validation
- [ ] **Python environment** - Verify Python 3.9+: `python --version`
- [ ] **Install dependencies** - Run: `pip install -r scripts/requirements.txt`
- [ ] **Configuration file** - Copy and edit: `cp config/config.example.yml config/config.yml`
- [ ] **Dry run test** - Preview deployment: `python scripts/provision.py --dry-run`

## Role Assignment Reference

After deployment, assign these roles for operational access:

| Role | Assignee | Scope | Purpose |
|------|----------|-------|---------|
| Monitoring Reader | SOC Analyst Group | Resource Group | Query telemetry for monitoring |
| Storage Blob Data Reader | Compliance Team Group | Storage Account | Access audit archives for examination |
| Log Analytics Reader | Platform Operations | Log Analytics Workspace | View queries and dashboards |

## Copilot Studio Integration

To capture telemetry from Copilot Studio agents, configure the Application Insights connector:

1. Navigate to Copilot Studio > Your Agent > **Settings** > **Advanced**
2. In the **Application Insights** section, enter the Application Insights connection string (output by `provision.py` or retrieved from Azure Monitor)
3. Enable **Log activities** to capture incoming and outgoing messages and events
4. Optionally enable **Log sensitive Activity properties** (see [docs/pii-sanitization-guide.md](docs/pii-sanitization-guide.md) for PII implications)

> **Important:** Enabling "Log sensitive Activity properties" captures conversation text in `Properties.text` or legacy `customDimensions.text`. Review PII handling requirements before enabling.

---

*Prerequisites version: 1.2.1*
*Last updated: 2026-Q2*
