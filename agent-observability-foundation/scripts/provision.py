#!/usr/bin/env python3
"""
Agent Observability Foundation - Provisioning Script.

Provisions FSI-compliant Azure telemetry infrastructure:
- Log Analytics workspace (730-day retention for SEC 17a-4)
- Application Insights (workspace-based)
- Storage account for diagnostic settings export
- Diagnostic settings for Application Insights log export
- RBAC role assignments (separation of duties)

Usage:
    # Full deployment with default config
    python provision.py --config config/config.yml

    # Dry run to preview changes
    python provision.py --config config/config.yml --dry-run

    # Override config values via CLI
    python provision.py --config config/config.yml \\
        --resource-group rg-test \\
        --location westus2 \\
        --retention-days 365

    # Verbose output for debugging
    python provision.py --config config/config.yml --verbose

Requirements:
    pip install -r requirements.txt

IMPORTANT:
    - WORM policy is NOT configured by this script intentionally
    - Reason: WORM policies cannot be unlocked once applied
    - See docs/worm-configuration.md for manual WORM setup
"""

import argparse
import os
import sys
import uuid
from typing import Any, Optional

import yaml

# Azure SDK imports
from azure.identity import DefaultAzureCredential
from azure.core.exceptions import (
    AzureError,
    ClientAuthenticationError,
    HttpResponseError,
    ResourceExistsError,
    ResourceNotFoundError,
)
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.loganalytics import LogAnalyticsManagementClient
from azure.mgmt.loganalytics.models import Workspace, WorkspaceSku
from azure.mgmt.applicationinsights import ApplicationInsightsManagementClient
from azure.mgmt.applicationinsights.models import (
    ApplicationInsightsComponent,
    ApplicationType,
)
from azure.mgmt.monitor import MonitorManagementClient
from azure.mgmt.monitor.models import (
    DiagnosticSettingsResource,
    LogSettings,
    RetentionPolicy,
)
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.storage.models import (
    StorageAccountCreateParameters,
    Sku,
    Kind,
)
from azure.mgmt.authorization import AuthorizationManagementClient
from azure.mgmt.authorization.models import RoleAssignmentCreateParameters


# Built-in role definition IDs (common roles)
# See: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
BUILTIN_ROLES = {
    "Monitoring Reader": "43d0d8ad-25c7-4714-9337-8ba259a9fe05",
    "Monitoring Contributor": "749f88d5-cbae-40b8-bcfc-e573ddc772fa",
    "Log Analytics Reader": "73c42c96-874c-492b-b04d-ab87d138a893",
    "Log Analytics Contributor": "92aaf0da-9dab-42b6-94a3-d43ce8d16293",
    "Storage Blob Data Reader": "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1",
    "Storage Blob Data Contributor": "ba92f5b4-2d11-453d-a403-e96b0029c9fe",
    "Reader": "acdd72a7-3385-48ef-bd42-f606fba81ae7",
    "Contributor": "b24988ac-6180-42a0-ab88-20f7382dd24c",
}


def print_banner() -> None:
    """Print deployment banner."""
    print()
    print("=" * 70)
    print("  Agent Observability Foundation - Azure Provisioning")
    print("=" * 70)
    print()
    print("  This script provisions FSI-compliant telemetry infrastructure:")
    print("    - Log Analytics workspace (730-day retention)")
    print("    - Application Insights (workspace-based)")
    print("    - Storage account for diagnostic export")
    print("    - Diagnostic settings (App Insights to storage)")
    print("    - RBAC role assignments (operational/compliance separation)")
    print()
    print("  NOTE: WORM policy is NOT configured by this script.")
    print("        See docs/worm-configuration.md for manual setup.")
    print()


def load_config(args: argparse.Namespace) -> dict[str, Any]:
    """
    Load configuration from YAML file and merge CLI overrides.

    Args:
        args: Parsed command-line arguments

    Returns:
        Configuration dictionary with CLI overrides applied

    Raises:
        FileNotFoundError: If config file doesn't exist
        ValueError: If required fields are missing
    """
    config_path = args.config
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    # CLI arguments override config file values
    if args.subscription_id:
        config["subscription_id"] = args.subscription_id
    if args.resource_group:
        config["resource_group"] = args.resource_group
    if args.location:
        config["location"] = args.location
    if args.retention_days:
        config["retention_days"] = args.retention_days

    # Validate required fields
    required = ["subscription_id", "resource_group", "location"]
    missing = [f for f in required if not config.get(f)]
    if missing:
        raise ValueError(f"Missing required config fields: {', '.join(missing)}")

    # Apply defaults
    config.setdefault("retention_days", 730)
    config.setdefault("naming_prefix", "aof")
    config.setdefault("tags", {})
    config.setdefault("application_insights", {})
    config.setdefault("log_analytics", {})
    config.setdefault("storage", {})
    config.setdefault("diagnostic_settings", {})
    config.setdefault("rbac", [])

    # Generate resource names from prefix if not specified
    prefix = config["naming_prefix"]
    if not config["application_insights"].get("name"):
        config["application_insights"]["name"] = f"ai-{prefix}-observability"
    if not config["log_analytics"].get("name"):
        config["log_analytics"]["name"] = f"law-{prefix}-observability"
    if not config["storage"].get("name"):
        # Storage names must be 3-24 lowercase alphanumeric
        config["storage"]["name"] = f"st{prefix}telemetry"[:24].lower()

    # Apply resource defaults
    config["application_insights"].setdefault("kind", "web")
    config["log_analytics"].setdefault("sku", "PerGB2018")
    config["storage"].setdefault("account_kind", "StorageV2")
    config["storage"].setdefault("replication", "Standard_GRS")
    config["diagnostic_settings"].setdefault("name", "export-to-storage")
    config["diagnostic_settings"].setdefault("log_categories", ["AppTraces", "AppEvents"])

    return config


def preflight_check(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    verbose: bool = False,
) -> bool:
    """
    Perform pre-flight validation.

    Checks:
    - Azure authentication
    - Subscription access
    - Resource group existence (creates if not exists)

    Args:
        config: Configuration dictionary
        credential: Azure credential
        verbose: Show detailed output

    Returns:
        True if preflight passes
    """
    print("[Pre-flight Validation]")
    print()

    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    location = config["location"]

    # Test authentication
    print("  Checking Azure authentication...")
    try:
        resource_client = ResourceManagementClient(credential, subscription_id)
        # List resource groups to verify access
        list(resource_client.resource_groups.list())
        print(f"    Subscription {subscription_id[:8]}... ✓")
    except ClientAuthenticationError as e:
        print(f"    Authentication failed ✗")
        print(f"    Error: {e.message}")
        print()
        print("    Run one of the following to authenticate:")
        print("      - az login (Azure CLI)")
        print("      - Connect-AzAccount (PowerShell)")
        print("      - Set AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET (Service Principal)")
        return False
    except HttpResponseError as e:
        print(f"    Subscription access failed ✗")
        print(f"    Error: {e.message}")
        return False

    # Check/create resource group
    print()
    print("  Checking resource group...")
    try:
        rg = resource_client.resource_groups.get(resource_group)
        print(f"    {resource_group}: exists ✓")
    except ResourceNotFoundError:
        print(f"    {resource_group}: not found, will be created ○")

    print()
    print("  Configuration summary:")
    print(f"    Subscription:    {subscription_id}")
    print(f"    Resource Group:  {resource_group}")
    print(f"    Location:        {location}")
    print(f"    Retention Days:  {config['retention_days']}")
    print(f"    Log Analytics:   {config['log_analytics']['name']}")
    print(f"    App Insights:    {config['application_insights']['name']}")
    print(f"    Storage Account: {config['storage']['name']}")
    print(f"    RBAC Assignments: {len(config['rbac'])}")
    print()

    return True


def ensure_resource_group(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    dry_run: bool = False,
    verbose: bool = False,
) -> None:
    """
    Ensure resource group exists, create if not.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        dry_run: Preview without making changes
        verbose: Show detailed output
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    location = config["location"]
    tags = config.get("tags", {})

    resource_client = ResourceManagementClient(credential, subscription_id)

    try:
        rg = resource_client.resource_groups.get(resource_group)
        print(f"  Resource group {resource_group}: exists ○")
    except ResourceNotFoundError:
        if dry_run:
            print(f"  Resource group {resource_group}: would be created (dry-run)")
        else:
            print(f"  Creating resource group {resource_group}...")
            rg = resource_client.resource_groups.create_or_update(
                resource_group,
                {"location": location, "tags": tags},
            )
            print(f"  Resource group {resource_group}: created ✓")


def create_log_analytics_workspace(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    dry_run: bool = False,
    verbose: bool = False,
) -> Optional[str]:
    """
    Create or update Log Analytics workspace with 730-day retention.

    IMPORTANT: Sets retention_in_days (interactive/hot retention). When
    retention_in_days equals total_retention_in_days (the default behavior),
    only retention_in_days needs to be specified.
    (Pitfall #2 from research: confusing analytics vs total retention)

    Args:
        config: Configuration dictionary
        credential: Azure credential
        dry_run: Preview without making changes
        verbose: Show detailed output

    Returns:
        Workspace resource ID or None if dry-run
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    location = config["location"]
    retention_days = config["retention_days"]
    tags = config.get("tags", {})

    la_config = config["log_analytics"]
    workspace_name = la_config["name"]
    sku = la_config.get("sku", "PerGB2018")

    la_client = LogAnalyticsManagementClient(credential, subscription_id)

    if dry_run:
        print(f"  Log Analytics workspace {workspace_name}: would be created (dry-run)")
        print(f"    - Location: {location}")
        print(f"    - SKU: {sku}")
        print(f"    - Retention (interactive): {retention_days} days")
        print(f"    - Retention (total): {retention_days} days")
        return None

    print(f"  Creating Log Analytics workspace {workspace_name}...")

    # Build workspace parameters
    # Set retention_in_days (interactive/hot); total_retention_in_days defaults to
    # match retention_in_days when not explicitly specified
    workspace_params = Workspace(
        location=location,
        sku=WorkspaceSku(name=sku),
        retention_in_days=retention_days,
        tags=tags,
    )

    # Use begin_create_or_update which returns a poller for async operation
    poller = la_client.workspaces.begin_create_or_update(
        resource_group_name=resource_group,
        workspace_name=workspace_name,
        parameters=workspace_params,
    )

    # Wait for completion
    workspace = poller.result()

    # Note: total_retention_in_days must be set via separate API call if needed
    # For 730-day retention where interactive=total, retention_in_days is sufficient

    print(f"  Log Analytics workspace {workspace_name}: created ✓")
    print(f"    - Workspace ID: {workspace.customer_id}")
    print(f"    - Retention: {retention_days} days")

    if verbose:
        print(f"    - Resource ID: {workspace.id}")

    return workspace.id


def create_application_insights(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    workspace_id: str,
    dry_run: bool = False,
    verbose: bool = False,
) -> Optional[str]:
    """
    Create or update Application Insights (workspace-based).

    Args:
        config: Configuration dictionary
        credential: Azure credential
        workspace_id: Log Analytics workspace resource ID
        dry_run: Preview without making changes
        verbose: Show detailed output

    Returns:
        Application Insights resource ID or None if dry-run
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    location = config["location"]
    retention_days = config["retention_days"]
    tags = config.get("tags", {})

    ai_config = config["application_insights"]
    ai_name = ai_config["name"]
    kind = ai_config.get("kind", "web")

    ai_client = ApplicationInsightsManagementClient(credential, subscription_id)

    if dry_run:
        print(f"  Application Insights {ai_name}: would be created (dry-run)")
        print(f"    - Kind: {kind}")
        print(f"    - Retention: {retention_days} days")
        print(f"    - Linked workspace: {workspace_id or '(pending)'}")
        return None

    print(f"  Creating Application Insights {ai_name}...")

    # Build App Insights component
    # Note: workspace-based App Insights is required (classic deprecated Feb 2024)
    component_params = ApplicationInsightsComponent(
        location=location,
        kind=kind,
        application_type=ApplicationType.WEB,
        retention_in_days=retention_days,
        workspace_resource_id=workspace_id,
        tags=tags,
    )

    component = ai_client.components.create_or_update(
        resource_group_name=resource_group,
        resource_name=ai_name,
        insight_properties=component_params,
    )

    print(f"  Application Insights {ai_name}: created ✓")
    print(f"    - Instrumentation Key: {component.instrumentation_key[:8]}...{component.instrumentation_key[-4:]} (masked)")

    if verbose:
        print(f"    - Connection String: {component.connection_string[:40]}... (masked, retrieve full value from Azure Portal)")
        print(f"    - Resource ID: {component.id}")

    return component.id


def create_storage_account(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    dry_run: bool = False,
    verbose: bool = False,
) -> Optional[str]:
    """
    Create or update Storage account for diagnostic settings export.

    IMPORTANT: Creates StorageV2 WITHOUT hierarchical namespace.
    Diagnostic settings export does NOT support ADLS Gen2 with hierarchical
    namespace enabled. (Pitfall #1 from research)

    Args:
        config: Configuration dictionary
        credential: Azure credential
        dry_run: Preview without making changes
        verbose: Show detailed output

    Returns:
        Storage account resource ID or None if dry-run
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    location = config["location"]
    tags = config.get("tags", {})

    storage_config = config["storage"]
    account_name = storage_config["name"]
    account_kind = storage_config.get("account_kind", "StorageV2")
    replication = storage_config.get("replication", "Standard_GRS")

    storage_client = StorageManagementClient(credential, subscription_id)

    if dry_run:
        print(f"  Storage account {account_name}: would be created (dry-run)")
        print(f"    - Kind: {account_kind}")
        print(f"    - Replication: {replication}")
        print(f"    - Hierarchical namespace: DISABLED (required for diagnostic settings)")
        return None

    # Check if exists
    try:
        existing = storage_client.storage_accounts.get_properties(
            resource_group_name=resource_group,
            account_name=account_name,
        )
        print(f"  Storage account {account_name}: exists ○")
        print(f"    - Resource ID: {existing.id}")
        return existing.id
    except ResourceNotFoundError:
        pass

    print(f"  Creating storage account {account_name}...")

    # CRITICAL: Do NOT enable hierarchical namespace
    # Diagnostic settings export to ADLS Gen2 with HNS enabled is NOT supported
    storage_params = StorageAccountCreateParameters(
        location=location,
        sku=Sku(name=replication),
        kind=Kind(account_kind),
        # is_hns_enabled=False is the default, but explicit for clarity
        # Hierarchical namespace MUST be disabled for diagnostic settings export
        tags=tags,
    )

    poller = storage_client.storage_accounts.begin_create(
        resource_group_name=resource_group,
        account_name=account_name,
        parameters=storage_params,
    )

    account = poller.result()

    print(f"  Storage account {account_name}: created ✓")
    print(f"    - Primary endpoint: {account.primary_endpoints.blob}")

    if verbose:
        print(f"    - Resource ID: {account.id}")

    return account.id


def create_diagnostic_settings(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    app_insights_id: str,
    storage_id: str,
    dry_run: bool = False,
    verbose: bool = False,
) -> None:
    """
    Create diagnostic settings to export Application Insights logs to storage.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        app_insights_id: Application Insights resource ID
        storage_id: Storage account resource ID
        dry_run: Preview without making changes
        verbose: Show detailed output
    """
    subscription_id = config["subscription_id"]

    ds_config = config["diagnostic_settings"]
    ds_name = ds_config.get("name", "export-to-storage")
    log_categories = ds_config.get("log_categories", ["AppTraces", "AppEvents"])

    monitor_client = MonitorManagementClient(credential, subscription_id)

    if dry_run:
        print(f"  Diagnostic settings {ds_name}: would be created (dry-run)")
        print(f"    - Source: {app_insights_id or '(pending)'}")
        print(f"    - Destination: {storage_id or '(pending)'}")
        print(f"    - Log categories: {', '.join(log_categories)}")
        return

    print(f"  Creating diagnostic settings {ds_name}...")

    # Build log settings for each category
    logs = []
    for category in log_categories:
        logs.append(
            LogSettings(
                category=category,
                enabled=True,
                # DEPRECATED: Azure ignores retentionPolicy on diagnostic settings (Sept 2023).
                # Actual retention must be managed via storage account lifecycle management
                # policies or WORM immutability (see docs/worm-configuration.md).
                retention_policy=RetentionPolicy(
                    enabled=False,
                    days=0,
                ),
            )
        )

    # Create diagnostic settings
    ds_params = DiagnosticSettingsResource(
        storage_account_id=storage_id,
        logs=logs,
    )

    result = monitor_client.diagnostic_settings.create_or_update(
        resource_uri=app_insights_id,
        name=ds_name,
        parameters=ds_params,
    )

    print(f"  Diagnostic settings {ds_name}: created ✓")
    print(f"    - Export to: {storage_id.split('/')[-1]}")
    print(f"    - Categories: {', '.join(log_categories)}")


def create_rbac_assignments(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    dry_run: bool = False,
    verbose: bool = False,
) -> None:
    """
    Create RBAC role assignments for separation of duties.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        dry_run: Preview without making changes
        verbose: Show detailed output
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    rbac_assignments = config.get("rbac", [])

    if not rbac_assignments:
        print("  RBAC assignments: none configured ○")
        return

    auth_client = AuthorizationManagementClient(credential, subscription_id)

    # Scope at resource group level
    scope = f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}"

    for assignment in rbac_assignments:
        role_name = assignment["role_name"]
        principal_id = assignment["principal_id"]
        principal_type = assignment.get("principal_type", "Group")
        description = assignment.get("description", "")

        # Get role definition ID
        role_id = BUILTIN_ROLES.get(role_name)
        if not role_id:
            print(f"  Role assignment {role_name}: unknown role, skipping ✗")
            continue

        role_definition_id = f"{scope}/providers/Microsoft.Authorization/roleDefinitions/{role_id}"

        if dry_run:
            print(f"  Role assignment {role_name}: would be assigned (dry-run)")
            print(f"    - Principal: {principal_id[:8]}... ({principal_type})")
            if description:
                print(f"    - Purpose: {description}")
            continue

        # Check if assignment already exists
        # Role assignments are uniquely identified by name (GUID)
        assignment_name = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"{role_name}-{principal_id}-{scope}"))

        try:
            existing = auth_client.role_assignments.get(
                scope=scope,
                role_assignment_name=assignment_name,
            )
            print(f"  Role assignment {role_name}: exists ○")
            continue
        except ResourceNotFoundError:
            pass

        print(f"  Creating role assignment {role_name}...")

        assignment_params = RoleAssignmentCreateParameters(
            role_definition_id=role_definition_id,
            principal_id=principal_id,
            principal_type=principal_type,
        )

        try:
            result = auth_client.role_assignments.create(
                scope=scope,
                role_assignment_name=assignment_name,
                parameters=assignment_params,
            )
            print(f"  Role assignment {role_name}: created ✓")
            print(f"    - Principal: {principal_id[:8]}... ({principal_type})")
        except ResourceExistsError:
            print(f"  Role assignment {role_name}: already exists ○")
        except HttpResponseError as e:
            print(f"  Role assignment {role_name}: failed ✗")
            print(f"    Error: {e.message}")


def print_summary(
    config: dict[str, Any],
    workspace_id: Optional[str],
    app_insights_id: Optional[str],
    storage_id: Optional[str],
) -> None:
    """
    Print deployment summary table.

    Args:
        config: Configuration dictionary
        workspace_id: Log Analytics workspace resource ID
        app_insights_id: Application Insights resource ID
        storage_id: Storage account resource ID
    """
    print()
    print("=" * 70)
    print("  DEPLOYMENT SUMMARY")
    print("=" * 70)
    print()
    print("  Resources Provisioned:")
    print()
    print(f"  {'Resource':<30} {'Name':<30}")
    print(f"  {'-'*30} {'-'*30}")
    print(f"  {'Log Analytics Workspace':<30} {config['log_analytics']['name']:<30}")
    print(f"  {'Application Insights':<30} {config['application_insights']['name']:<30}")
    print(f"  {'Storage Account':<30} {config['storage']['name']:<30}")
    print(f"  {'Diagnostic Settings':<30} {config['diagnostic_settings'].get('name', 'export-to-storage'):<30}")
    print()

    if config.get("rbac"):
        print("  RBAC Assignments:")
        print()
        for assignment in config["rbac"]:
            print(f"    - {assignment['role_name']}: {assignment['principal_id'][:8]}...")
        print()

    print("  Next Steps:")
    print()
    print("    1. Configure WORM policy (manual - see docs/worm-configuration.md)")
    print("    2. Set up cost alerts in Azure Monitor (50%, 75%, 90% thresholds)")
    print("    3. Configure ingestion sampling at workspace level via portal")
    #     Note: Sampling is configured at workspace level, not SDK-configurable
    #     for Copilot Studio telemetry
    print("    4. Review PII handling (see docs/pii-sanitization-guide.md)")
    print()
    print("=" * 70)


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Provision FSI-compliant Azure telemetry infrastructure",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Full deployment with default config
    python provision.py --config config/config.yml

    # Dry run to preview changes
    python provision.py --config config/config.yml --dry-run

    # Override config values via CLI
    python provision.py --config config/config.yml \\
        --resource-group rg-test \\
        --location westus2 \\
        --retention-days 365
        """,
    )

    # Config file
    parser.add_argument(
        "--config",
        default="config/config.yml",
        help="Path to YAML configuration file (default: config/config.yml)",
    )

    # CLI overrides
    parser.add_argument(
        "--subscription-id",
        help="Azure subscription ID (overrides config)",
    )
    parser.add_argument(
        "--resource-group",
        help="Azure resource group name (overrides config)",
    )
    parser.add_argument(
        "--location",
        help="Azure region (overrides config)",
    )
    parser.add_argument(
        "--retention-days",
        type=int,
        help="Data retention days (overrides config)",
    )

    # Execution options
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without making any modifications",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Show detailed output including resource IDs",
    )

    args = parser.parse_args()

    print_banner()

    if args.dry_run:
        print("*** DRY RUN MODE - No changes will be made ***")
        print()

    try:
        # Load configuration
        print("[Loading Configuration]")
        config = load_config(args)
        print(f"  Config loaded from: {args.config}")
        print()

        # Initialize Azure credential
        # DefaultAzureCredential supports:
        # - Environment variables (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET)
        # - Azure CLI (az login)
        # - Managed Identity
        # - Visual Studio Code
        credential = DefaultAzureCredential()

        # Pre-flight validation
        if not preflight_check(config, credential, args.verbose):
            print()
            print("Pre-flight validation failed. Exiting.")
            sys.exit(1)

        # Ensure resource group exists
        print("[Provisioning Resources]")
        print()
        ensure_resource_group(config, credential, args.dry_run, args.verbose)

        # Create Log Analytics workspace
        workspace_id = create_log_analytics_workspace(
            config, credential, args.dry_run, args.verbose
        )

        # Create Application Insights (linked to workspace)
        app_insights_id = create_application_insights(
            config, credential, workspace_id, args.dry_run, args.verbose
        )

        # Create Storage account (for diagnostic export)
        storage_id = create_storage_account(
            config, credential, args.dry_run, args.verbose
        )

        # Create Diagnostic Settings
        if not args.dry_run and app_insights_id and storage_id:
            create_diagnostic_settings(
                config, credential, app_insights_id, storage_id,
                args.dry_run, args.verbose
            )
        elif args.dry_run:
            create_diagnostic_settings(
                config, credential, None, None,
                args.dry_run, args.verbose
            )

        # Create RBAC assignments
        print()
        print("[RBAC Role Assignments]")
        print()
        create_rbac_assignments(config, credential, args.dry_run, args.verbose)

        # Print summary
        if not args.dry_run:
            print_summary(config, workspace_id, app_insights_id, storage_id)
        else:
            print()
            print("=" * 70)
            print("  DRY RUN COMPLETE")
            print("=" * 70)
            print()
            print("  Review output above to see what would be created.")
            print("  Run without --dry-run to apply changes.")
            print()

        sys.exit(0)

    except FileNotFoundError as e:
        print(f"ERROR: {e}")
        sys.exit(1)
    except ValueError as e:
        print(f"ERROR: Configuration error - {e}")
        sys.exit(1)
    except ClientAuthenticationError as e:
        print(f"ERROR: Authentication failed - {e.message}")
        print()
        print("Run one of the following to authenticate:")
        print("  - az login (Azure CLI)")
        print("  - Connect-AzAccount (PowerShell)")
        print("  - Set AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET")
        sys.exit(1)
    except HttpResponseError as e:
        print(f"ERROR: Azure API error - {e.status_code}: {e.message}")
        if args.verbose:
            print(f"  Error code: {e.error.code if e.error else 'N/A'}")
        sys.exit(1)
    except AzureError as e:
        print(f"ERROR: Azure SDK error - {e.message}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\nProvisioning cancelled by user.")
        sys.exit(130)
    except Exception as e:
        print(f"ERROR: Unexpected error - {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
