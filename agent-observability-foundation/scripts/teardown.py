#!/usr/bin/env python3
"""
Agent Observability Foundation - Teardown Script.

Safely deletes all Azure resources provisioned by provision.py for lab cycling.
Deletes resources in reverse dependency order to avoid orphaned dependencies.

Usage:
    # Preview what would be deleted (dry run)
    python teardown.py --config config/config.yml --dry-run

    # Delete all resources with confirmation prompt
    python teardown.py --config config/config.yml

    # Skip confirmation prompt (use with caution)
    python teardown.py --config config/config.yml --force

    # Verbose output for debugging
    python teardown.py --config config/config.yml --verbose

IMPORTANT:
    - This script does NOT delete resource groups (too dangerous)
    - If WORM policy is applied to storage, deletion will fail
    - See docs/worm-configuration.md for WORM storage deletion guidance

Deletion Order (reverse of provisioning):
    1. Diagnostic settings (depends on App Insights + Storage)
    2. RBAC role assignments
    3. Application Insights
    4. Log Analytics workspace
    5. Storage account (may fail if WORM-locked)
"""

import argparse
import os
import sys
import uuid
from typing import Any

import yaml

# Azure SDK imports (guarded so --help and arg validation work without the
# full azure-mgmt stack installed; matches the repo's graceful-degradation
# pattern, e.g. environment-lifecycle-management/scripts/register_service_principal.py)
try:
    from azure.identity import DefaultAzureCredential
    from azure.core.exceptions import (
        AzureError,
        ClientAuthenticationError,
        HttpResponseError,
        ResourceNotFoundError,
    )
    from azure.mgmt.applicationinsights import ApplicationInsightsManagementClient
    from azure.mgmt.loganalytics import LogAnalyticsManagementClient
    from azure.mgmt.monitor import MonitorManagementClient
    from azure.mgmt.storage import StorageManagementClient
    from azure.mgmt.authorization import AuthorizationManagementClient
except ImportError:
    print("Missing dependencies. Run: pip install -r requirements.txt", file=sys.stderr)
    sys.exit(4)


# Built-in role definition IDs (same as provision.py)
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
    """Print teardown banner with warning."""
    print()
    print("=" * 70)
    print("  Agent Observability Foundation - Teardown")
    print("=" * 70)
    print()
    print("  WARNING: This script will PERMANENTLY DELETE resources:")
    print("    - Diagnostic settings")
    print("    - RBAC role assignments")
    print("    - Application Insights (telemetry data will be LOST)")
    print("    - Log Analytics workspace (logs will be LOST)")
    print("    - Storage account (archived data will be LOST)")
    print()
    print("  This action CANNOT be undone.")
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

    # Validate required fields
    required = ["subscription_id", "resource_group"]
    missing = [f for f in required if not config.get(f)]
    if missing:
        raise ValueError(f"Missing required config fields: {', '.join(missing)}")

    # Apply defaults for resource names
    prefix = config.get("naming_prefix", "aof")
    config.setdefault("application_insights", {})
    config.setdefault("log_analytics", {})
    config.setdefault("storage", {})
    config.setdefault("diagnostic_settings", {})
    config.setdefault("rbac", [])

    # Generate resource names from prefix if not specified
    if not config["application_insights"].get("name"):
        config["application_insights"]["name"] = f"ai-{prefix}-observability"
    if not config["log_analytics"].get("name"):
        config["log_analytics"]["name"] = f"law-{prefix}-observability"
    if not config["storage"].get("name"):
        config["storage"]["name"] = f"st{prefix}telemetry"[:24].lower()

    config["diagnostic_settings"].setdefault("name", "export-to-storage")

    return config


def print_resources_to_delete(config: dict[str, Any]) -> None:
    """
    Print list of resources that will be deleted.

    Args:
        config: Configuration dictionary
    """
    print()
    print("  Resources targeted for deletion:")
    print()
    print(f"    - Diagnostic Settings: {config['diagnostic_settings'].get('name', 'export-to-storage')}")
    print(f"    - Application Insights: {config['application_insights']['name']}")
    print(f"    - Log Analytics:        {config['log_analytics']['name']}")
    print(f"    - Storage Account:      {config['storage']['name']}")

    rbac_assignments = config.get("rbac", [])
    if rbac_assignments:
        print(f"    - RBAC Assignments:     {len(rbac_assignments)} roles")
        for assignment in rbac_assignments:
            print(f"        - {assignment['role_name']}: {assignment['principal_id'][:8]}...")

    print()
    print(f"  Resource Group: {config['resource_group']}")
    print(f"  Subscription:   {config['subscription_id']}")
    print()


def confirm_deletion(force: bool = False) -> bool:
    """
    Prompt user to confirm deletion.

    Args:
        force: Skip confirmation if True

    Returns:
        True if user confirms or force=True
    """
    if force:
        print("  --force flag provided, skipping confirmation.")
        print()
        return True

    print("  To proceed, type 'yes' exactly:")
    print()

    try:
        user_input = input("  > ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        print()
        print("  Cancelled.")
        return False

    if user_input == "yes":
        print()
        return True
    else:
        print()
        print("  Deletion cancelled. You typed:", repr(user_input))
        return False


def delete_diagnostic_settings(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    dry_run: bool = False,
    verbose: bool = False,
) -> tuple[int, int, int]:
    """
    Delete diagnostic settings from Application Insights.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        dry_run: Preview without making changes
        verbose: Show detailed output

    Returns:
        Tuple of (deleted, already_absent, failed) counts
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    ai_name = config["application_insights"]["name"]
    ds_name = config["diagnostic_settings"].get("name", "export-to-storage")

    deleted, absent, failed = 0, 0, 0

    # Build App Insights resource ID
    app_insights_id = (
        f"/subscriptions/{subscription_id}"
        f"/resourceGroups/{resource_group}"
        f"/providers/Microsoft.Insights/components/{ai_name}"
    )

    monitor_client = MonitorManagementClient(credential, subscription_id)

    if dry_run:
        print(f"  Diagnostic settings {ds_name}: would be deleted (dry-run)")
        return (0, 0, 0)

    try:
        monitor_client.diagnostic_settings.delete(
            resource_uri=app_insights_id,
            name=ds_name,
        )
        print(f"  Diagnostic settings {ds_name}: deleted")
        deleted = 1
    except ResourceNotFoundError:
        print(f"  Diagnostic settings {ds_name}: already deleted")
        absent = 1
    except HttpResponseError as e:
        print(f"  Diagnostic settings {ds_name}: failed - {e.message}")
        failed = 1

    return (deleted, absent, failed)


def delete_rbac_assignments(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    dry_run: bool = False,
    verbose: bool = False,
) -> tuple[int, int, int]:
    """
    Delete RBAC role assignments.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        dry_run: Preview without making changes
        verbose: Show detailed output

    Returns:
        Tuple of (deleted, already_absent, failed) counts
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    rbac_assignments = config.get("rbac", [])

    deleted, absent, failed = 0, 0, 0

    if not rbac_assignments:
        print("  RBAC assignments: none configured")
        return (0, 0, 0)

    auth_client = AuthorizationManagementClient(credential, subscription_id)
    scope = f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}"

    for assignment in rbac_assignments:
        role_name = assignment["role_name"]
        principal_id = assignment["principal_id"]

        # Generate deterministic assignment name (same as provision.py)
        assignment_name = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"{role_name}-{principal_id}-{scope}"))

        if dry_run:
            print(f"  Role assignment {role_name}: would be deleted (dry-run)")
            continue

        try:
            auth_client.role_assignments.delete(
                scope=scope,
                role_assignment_name=assignment_name,
            )
            print(f"  Role assignment {role_name}: deleted")
            deleted += 1
        except ResourceNotFoundError:
            print(f"  Role assignment {role_name}: already deleted")
            absent += 1
        except HttpResponseError as e:
            print(f"  Role assignment {role_name}: failed - {e.message}")
            failed += 1

    return (deleted, absent, failed)


def delete_application_insights(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    dry_run: bool = False,
    verbose: bool = False,
) -> tuple[int, int, int]:
    """
    Delete Application Insights component.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        dry_run: Preview without making changes
        verbose: Show detailed output

    Returns:
        Tuple of (deleted, already_absent, failed) counts
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    ai_name = config["application_insights"]["name"]

    deleted, absent, failed = 0, 0, 0

    ai_client = ApplicationInsightsManagementClient(credential, subscription_id)

    if dry_run:
        print(f"  Application Insights {ai_name}: would be deleted (dry-run)")
        return (0, 0, 0)

    try:
        ai_client.components.delete(
            resource_group_name=resource_group,
            resource_name=ai_name,
        )
        print(f"  Application Insights {ai_name}: deleted")
        deleted = 1
    except ResourceNotFoundError:
        print(f"  Application Insights {ai_name}: already deleted")
        absent = 1
    except HttpResponseError as e:
        print(f"  Application Insights {ai_name}: failed - {e.message}")
        failed = 1

    return (deleted, absent, failed)


def delete_log_analytics_workspace(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    dry_run: bool = False,
    verbose: bool = False,
) -> tuple[int, int, int]:
    """
    Delete Log Analytics workspace.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        dry_run: Preview without making changes
        verbose: Show detailed output

    Returns:
        Tuple of (deleted, already_absent, failed) counts
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    workspace_name = config["log_analytics"]["name"]

    deleted, absent, failed = 0, 0, 0

    la_client = LogAnalyticsManagementClient(credential, subscription_id)

    if dry_run:
        print(f"  Log Analytics workspace {workspace_name}: would be deleted (dry-run)")
        return (0, 0, 0)

    try:
        # Use begin_delete for async operation and wait for completion
        poller = la_client.workspaces.begin_delete(
            resource_group_name=resource_group,
            workspace_name=workspace_name,
            force=True,  # Force delete even if workspace has linked resources
        )
        poller.result()  # Wait for completion
        print(f"  Log Analytics workspace {workspace_name}: deleted")
        deleted = 1
    except ResourceNotFoundError:
        print(f"  Log Analytics workspace {workspace_name}: already deleted")
        absent = 1
    except HttpResponseError as e:
        print(f"  Log Analytics workspace {workspace_name}: failed - {e.message}")
        failed = 1

    return (deleted, absent, failed)


def delete_storage_account(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    dry_run: bool = False,
    verbose: bool = False,
) -> tuple[int, int, int]:
    """
    Delete storage account.

    IMPORTANT: If WORM (immutable storage) policy is applied and locked,
    deletion will fail. User must wait for retention period to expire or
    delete via Azure portal with special permissions.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        dry_run: Preview without making changes
        verbose: Show detailed output

    Returns:
        Tuple of (deleted, already_absent, failed) counts
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    account_name = config["storage"]["name"]

    deleted, absent, failed = 0, 0, 0

    storage_client = StorageManagementClient(credential, subscription_id)

    if dry_run:
        print(f"  Storage account {account_name}: would be deleted (dry-run)")
        return (0, 0, 0)

    try:
        storage_client.storage_accounts.delete(
            resource_group_name=resource_group,
            account_name=account_name,
        )
        print(f"  Storage account {account_name}: deleted")
        deleted = 1
    except ResourceNotFoundError:
        print(f"  Storage account {account_name}: already deleted")
        absent = 1
    except HttpResponseError as e:
        # Check for immutable storage policy error
        error_msg = str(e.message).lower() if e.message else ""
        if "immutable" in error_msg or "immutability" in error_msg or "legal hold" in error_msg:
            print(f"  Storage account {account_name}: WORM policy prevents deletion")
            print()
            print("    Storage account has immutable storage policy applied.")
            print("    This is expected for SEC 17a-4(f) compliance.")
            print()
            print("    To delete:")
            print("    1. Wait for immutability retention period to expire, OR")
            print("    2. Delete manually via Azure portal after policy expiration")
            print()
            print("    See docs/worm-configuration.md for details.")
            print()
        else:
            print(f"  Storage account {account_name}: failed - {e.message}")
        failed = 1

    return (deleted, absent, failed)


def print_summary(
    deleted: int,
    absent: int,
    failed: int,
    dry_run: bool = False,
) -> None:
    """
    Print teardown summary.

    Args:
        deleted: Number of resources deleted
        absent: Number of resources already absent
        failed: Number of resources that failed to delete
        dry_run: Whether this was a dry run
    """
    print()
    print("=" * 70)
    if dry_run:
        print("  DRY RUN COMPLETE")
    else:
        print("  TEARDOWN SUMMARY")
    print("=" * 70)
    print()

    if dry_run:
        print("  No resources were modified. Run without --dry-run to apply.")
    else:
        print(f"  Resources deleted:       {deleted}")
        print(f"  Already absent:          {absent}")
        print(f"  Failed to delete:        {failed}")

        if failed > 0:
            print()
            print("  Some resources failed to delete. Check output above for details.")
            print("  Common causes:")
            print("    - WORM policy prevents storage deletion")
            print("    - Insufficient permissions")
            print("    - Resource has dependencies")

    print()
    print("=" * 70)


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Safely delete Azure resources provisioned by provision.py",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Preview what would be deleted (dry run)
    python teardown.py --config config/config.yml --dry-run

    # Delete all resources with confirmation prompt
    python teardown.py --config config/config.yml

    # Skip confirmation prompt (use with caution)
    python teardown.py --config config/config.yml --force
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

    # Execution options
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without making any modifications",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Skip confirmation prompt (use with caution)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Show detailed output",
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

        # Show what will be deleted
        print_resources_to_delete(config)

        # Confirm deletion (unless --force or --dry-run)
        if not args.dry_run and not confirm_deletion(args.force):
            print("Teardown cancelled.")
            sys.exit(0)

        # Initialize Azure credential
        credential = DefaultAzureCredential()

        # Track totals
        total_deleted = 0
        total_absent = 0
        total_failed = 0

        # Delete in reverse dependency order
        print("[Deleting Resources]")
        print()
        print("  Deletion order: diagnostic settings -> RBAC -> App Insights -> Log Analytics -> Storage")
        print()

        # 1. Delete diagnostic settings first (depends on App Insights)
        d, a, f = delete_diagnostic_settings(config, credential, args.dry_run, args.verbose)
        total_deleted += d
        total_absent += a
        total_failed += f

        # 2. Delete RBAC assignments
        d, a, f = delete_rbac_assignments(config, credential, args.dry_run, args.verbose)
        total_deleted += d
        total_absent += a
        total_failed += f

        # 3. Delete Application Insights
        d, a, f = delete_application_insights(config, credential, args.dry_run, args.verbose)
        total_deleted += d
        total_absent += a
        total_failed += f

        # 4. Delete Log Analytics workspace
        d, a, f = delete_log_analytics_workspace(config, credential, args.dry_run, args.verbose)
        total_deleted += d
        total_absent += a
        total_failed += f

        # 5. Delete Storage account (may fail if WORM-locked)
        d, a, f = delete_storage_account(config, credential, args.dry_run, args.verbose)
        total_deleted += d
        total_absent += a
        total_failed += f

        # Print summary
        print_summary(total_deleted, total_absent, total_failed, args.dry_run)

        # Exit code based on failures
        if total_failed > 0:
            sys.exit(1)
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
    except AzureError as e:
        print(f"ERROR: Azure SDK error - {e.message}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\nTeardown cancelled by user.")
        sys.exit(130)
    except Exception as e:
        print(f"ERROR: Unexpected error - {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
