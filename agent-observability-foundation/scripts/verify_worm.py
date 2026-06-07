#!/usr/bin/env python3
"""
Agent Observability Foundation - WORM Policy Verification Script.

IMPORTANT: This script ONLY VERIFIES WORM (Write Once Read Many) policy.
It does NOT create, modify, or lock immutability policies.

WORM verification is read-only by design because:
- Locked immutability policies CANNOT be removed or shortened
- Accidental WORM lockdown could prevent legitimate data management
- SEC 17a-4(f) compliance requires intentional, documented policy application

See docs/worm-configuration.md for manual WORM setup steps.

Usage:
    # Basic verification with config file
    python verify_worm.py --config config/config.yml

    # Verify the primary audit-of-record container (Copilot Studio interaction
    # events export to the AppEvents category -> insights-logs-appevents).
    python verify_worm.py --config config/config.yml \\
        --storage-account staofsec17a4export \\
        --container-name insights-logs-appevents

    # Verbose output for debugging
    python verify_worm.py --config config/config.yml --verbose

Container scope:
    Each verification run checks a single container. Azure diagnostic-settings
    export creates one container per enabled log category
    (insights-logs-appevents, insights-logs-apptraces, insights-logs-apprequests,
    insights-logs-appexceptions). WORM immutability is scoped per container, so
    run this script once per audit-of-record container. The Copilot Studio
    interaction events that back this solution's books-and-records evidence land
    in insights-logs-appevents. See docs/worm-configuration.md.

Verification Checks:
    1. Storage account exists and is StorageV2 (not HNS-enabled)
    2. Container exists
    3. Immutability policy is present
    4. Policy state is "Locked" (required for SEC 17a-4(f))
    5. Retention period meets minimum (>= 2555 days for 7-year)

Compliance Status:
    - COMPLIANT: Locked policy with adequate retention
    - PARTIALLY_COMPLIANT: Unlocked policy (not yet SEC 17a-4(f) compliant)
    - NOT_CONFIGURED: No immutability policy found

Exit Codes:
    0 - Fully compliant (locked policy with adequate retention)
    1 - Not configured (no policy found)
    2 - Partially compliant (policy exists but unlocked or insufficient retention)
"""

import argparse
import os
import sys
from typing import Any, Optional

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
    from azure.mgmt.storage import StorageManagementClient
except ImportError:
    print("Missing dependencies. Run: pip install -r requirements.txt", file=sys.stderr)
    sys.exit(4)


# Compliance constants
MIN_RETENTION_DAYS_SEC17A4 = 2555  # ~7 years for SEC 17a-4(a) long-term retention


def print_banner() -> None:
    """Print verification banner with warnings."""
    print()
    print("=" * 70)
    print("  Agent Observability Foundation - WORM Policy Verification")
    print("=" * 70)
    print()
    print("  This script ONLY VERIFIES WORM policy. It does NOT create or")
    print("  modify immutability policies.")
    print()
    print("  For WORM configuration, see docs/worm-configuration.md")
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
    if args.storage_account:
        config.setdefault("storage", {})
        config["storage"]["name"] = args.storage_account
    if args.container_name:
        config.setdefault("storage", {})
        config["storage"]["container_name"] = args.container_name

    # Validate required fields
    required = ["subscription_id", "resource_group"]
    missing = [f for f in required if not config.get(f)]
    if missing:
        raise ValueError(f"Missing required config fields: {', '.join(missing)}")

    # Apply defaults
    prefix = config.get("naming_prefix", "aof")
    config.setdefault("storage", {})

    if not config["storage"].get("name"):
        config["storage"]["name"] = f"st{prefix}telemetry"[:24].lower()
    if not config["storage"].get("container_name"):
        config["storage"]["container_name"] = "insights-logs-apptraces"

    return config


def verify_storage_account(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    verbose: bool = False,
) -> tuple[bool, bool]:
    """
    Verify storage account exists and is correct type.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        verbose: Show detailed output

    Returns:
        Tuple of (exists, is_correct_type)
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    account_name = config["storage"]["name"]

    storage_client = StorageManagementClient(credential, subscription_id)

    try:
        account = storage_client.storage_accounts.get_properties(
            resource_group_name=resource_group,
            account_name=account_name,
        )
    except ResourceNotFoundError:
        print(f"  Storage account: {account_name} NOT FOUND")
        return (False, False)

    print(f"  Storage account: {account_name}")
    print(f"    - Kind: {account.kind}")

    # Check if hierarchical namespace is enabled (HNS-enabled StorageV2 is unsupported by diagnostic export)
    hns_enabled = account.is_hns_enabled or False
    if hns_enabled:
        print("    - Hierarchical namespace: ENABLED (not compatible with diagnostic settings)")
        print()
        print("    WARNING: StorageV2 with hierarchical namespace enabled is not supported for")
        print("    diagnostic settings export. WORM policy may exist but telemetry export")
        print("    will not work. Consider recreating as StorageV2 without HNS.")
        return (True, False)
    else:
        print("    - Hierarchical namespace: disabled (correct)")

    if verbose:
        print(f"    - Primary location: {account.primary_location}")
        print(f"    - Replication: {account.sku.name}")

    return (True, True)


def verify_container_exists(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    verbose: bool = False,
) -> bool:
    """
    Verify blob container exists.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        verbose: Show detailed output

    Returns:
        True if container exists
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    account_name = config["storage"]["name"]
    container_name = config["storage"]["container_name"]

    storage_client = StorageManagementClient(credential, subscription_id)

    try:
        container = storage_client.blob_containers.get(
            resource_group_name=resource_group,
            account_name=account_name,
            container_name=container_name,
        )
        print(f"  Container: {container_name}")
        if verbose:
            print(f"    - Public access: {container.public_access or 'None'}")
        return True
    except ResourceNotFoundError:
        print(f"  Container: {container_name} NOT FOUND")
        print()
        print("    The container may not have been created yet.")
        print("    Diagnostic settings export creates containers automatically.")
        print("    Verify diagnostic settings are configured and working.")
        return False


def get_immutability_policy(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    verbose: bool = False,
) -> Optional[dict]:
    """
    Get immutability policy from container (READ-ONLY operation).

    Args:
        config: Configuration dictionary
        credential: Azure credential
        verbose: Show detailed output

    Returns:
        Policy details dict or None if not configured
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    account_name = config["storage"]["name"]
    container_name = config["storage"]["container_name"]

    storage_client = StorageManagementClient(credential, subscription_id)

    try:
        # READ-ONLY: Get immutability policy
        policy = storage_client.blob_containers.get_immutability_policy(
            resource_group_name=resource_group,
            account_name=account_name,
            container_name=container_name,
        )

        # Extract policy details
        policy_details = {
            "state": policy.immutability_policy_property.state if policy.immutability_policy_property else None,
            "retention_days": policy.immutability_policy_property.immutability_period_since_creation_in_days if policy.immutability_policy_property else None,
            "allow_protected_append_writes": policy.immutability_policy_property.allow_protected_append_writes if policy.immutability_policy_property else None,
            "etag": policy.etag,
        }

        return policy_details

    except ResourceNotFoundError:
        return None
    except HttpResponseError as e:
        # Policy may not exist yet
        if "ImmutabilityPolicyNotFound" in str(e) or "NotFound" in str(e):
            return None
        raise


def verify_immutability_policy(policy_details: Optional[dict], verbose: bool = False) -> tuple[bool, bool, bool, bool]:
    """
    Verify immutability policy compliance.

    Args:
        policy_details: Policy details from get_immutability_policy
        verbose: Show detailed output

    Returns:
        Tuple of (policy_exists, is_locked, retention_adequate, append_writes_allowed)

    Note:
        Azure Diagnostic Settings export to a blob container performs *append*
        writes against existing blobs. A locked time-based immutability policy
        without ``allowProtectedAppendWrites`` will block those appends and
        silently halt telemetry export. For SEC 17a-4(f) export pipelines,
        ``allowProtectedAppendWrites`` MUST be enabled on the locked policy.
    """
    if not policy_details:
        print("  Immutability policy: NOT CONFIGURED")
        print()
        print("    No WORM policy found on this container.")
        print("    For SEC 17a-4(f) compliance, configure immutable storage.")
        print()
        print("    See docs/worm-configuration.md for manual setup steps.")
        return (False, False, False, False)

    state = policy_details.get("state")
    retention = policy_details.get("retention_days")
    allow_append = policy_details.get("allow_protected_append_writes")
    append_ok = bool(allow_append)

    print("  Immutability policy:")
    print(f"    - State: {state}")
    print(f"    - Retention: {retention} days")
    print(f"    - Protected append writes: {allow_append}")
    if not append_ok:
        print()
        print("    WARNING: Protected append writes are DISABLED. Azure Monitor")
        print("    diagnostic export performs append writes; a locked policy")
        print("    without this flag will block telemetry from landing in the")
        print("    container, creating an audit gap. Enable allowProtectedAppendWrites.")

    # Check if locked
    is_locked = state == "Locked"
    if is_locked:
        print("    - SEC 17a-4(f) locked state")
    else:
        print("    - Policy is UNLOCKED (not yet SEC 17a-4(f) compliant)")
        print()
        print("    An unlocked policy can still be modified or deleted.")
        print("    To achieve SEC 17a-4(f) compliance, the policy must be LOCKED.")
        print("    WARNING: Once locked, the policy CANNOT be removed or shortened.")

    # Check retention
    retention_adequate = False
    if retention is not None:
        retention_adequate = retention >= MIN_RETENTION_DAYS_SEC17A4
        if retention_adequate:
            print(f"    - Retention >= {MIN_RETENTION_DAYS_SEC17A4} days (7-year compliance)")
        else:
            print(f"    - Retention {retention} < {MIN_RETENTION_DAYS_SEC17A4} days required")
            print()
            print("    SEC 17a-4(a) requires 6-year retention for broker-dealer records.")
            print(f"    Recommended minimum: {MIN_RETENTION_DAYS_SEC17A4} days (~7 years).")

    return (True, is_locked, retention_adequate, append_ok)


def print_compliance_summary(
    storage_ok: bool,
    storage_correct_type: bool,
    container_exists: bool,
    policy_exists: bool,
    is_locked: bool,
    retention_adequate: bool,
    append_writes_allowed: bool,
) -> int:
    """
    Print compliance summary and determine exit code.

    Returns:
        Exit code (0=compliant, 1=not configured, 2=partially compliant)
    """
    print()
    print("=" * 70)
    print("  COMPLIANCE SUMMARY")
    print("=" * 70)
    print()

    checks = [
        ("Storage account exists", storage_ok),
        ("Storage account correct type (no HNS)", storage_correct_type),
        ("Blob container exists", container_exists),
        ("Immutability policy configured", policy_exists),
        ("Policy state: Locked (SEC 17a-4(f))", is_locked),
        (f"Retention >= {MIN_RETENTION_DAYS_SEC17A4} days", retention_adequate),
        ("Protected append writes enabled (export-pipeline-safe)", append_writes_allowed),
    ]

    for check_name, passed in checks:
        status = "PASS" if passed else "FAIL"
        print(f"    [{status}] {check_name}")

    print()

    # Determine overall compliance status
    if not storage_ok:
        print("  Status: NOT CONFIGURED")
        print("  Storage account does not exist. Run provision.py first.")
        return 1

    if not policy_exists:
        print("  Status: NOT CONFIGURED")
        print()
        print("  WORM policy is not configured on the telemetry export container.")
        print("  This is expected for new deployments (WORM is intentionally manual).")
        print()
        print("  To configure SEC 17a-4(f) compliant storage:")
        print("    1. Review docs/worm-configuration.md")
        print("    2. Test in non-production first")
        print("    3. Apply policy manually via Azure portal")
        print("    4. Lock policy only when ready (IRREVERSIBLE)")
        return 1

    if not is_locked or not retention_adequate or not append_writes_allowed:
        print("  Status: PARTIALLY COMPLIANT")
        print()
        if not is_locked:
            print("  Policy exists but is not LOCKED.")
            print("  Unlocked policies do not meet SEC 17a-4(f) requirements.")
        if not retention_adequate:
            print(f"  Retention period is less than {MIN_RETENTION_DAYS_SEC17A4} days.")
            print("  SEC 17a-4(a) requires 6-year retention minimum.")
        if not append_writes_allowed:
            print("  allowProtectedAppendWrites is DISABLED.")
            print("  Azure Monitor diagnostic export will be blocked once the")
            print("  policy is locked, creating an audit gap.")
        return 2

    print("  Status: COMPLIANT")
    print()
    print("  Storage is configured with locked immutability policy")
    print("  meeting SEC 17a-4(f) WORM requirements.")
    return 0


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Verify WORM policy on telemetry export storage (READ-ONLY)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Basic verification with config file
    python verify_worm.py --config config/config.yml

    # Override storage account and container
    python verify_worm.py --config config/config.yml \\
        --storage-account staofsec17a4export \\
        --container-name insights-logs-apptraces

IMPORTANT: This script ONLY VERIFIES WORM policy.
           It does NOT create, modify, or lock immutability policies.
           See docs/worm-configuration.md for manual WORM setup.
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
        "--storage-account",
        help="Storage account name (overrides config)",
    )
    parser.add_argument(
        "--container-name",
        help="Blob container name (default: insights-logs-apptraces)",
    )

    # Execution options
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Show detailed output",
    )

    args = parser.parse_args()

    print_banner()

    try:
        # Load configuration
        print("[Loading Configuration]")
        config = load_config(args)
        print(f"  Config loaded from: {args.config}")
        print()

        # Initialize Azure credential
        credential = DefaultAzureCredential()

        # Verification checks
        print("[Verification Checks]")
        print()

        # 1. Verify storage account exists
        storage_ok, storage_correct_type = verify_storage_account(
            config, credential, args.verbose
        )
        print()

        # 2. Verify container exists
        container_exists = False
        if storage_ok:
            container_exists = verify_container_exists(config, credential, args.verbose)
            print()

        # 3. Get and verify immutability policy (READ-ONLY)
        policy_exists = False
        is_locked = False
        retention_adequate = False
        append_writes_allowed = False

        if container_exists:
            print("  Checking immutability policy (read-only)...")
            policy_details = get_immutability_policy(config, credential, args.verbose)
            policy_exists, is_locked, retention_adequate, append_writes_allowed = verify_immutability_policy(
                policy_details, args.verbose
            )
            print()

        # Print compliance summary and get exit code
        exit_code = print_compliance_summary(
            storage_ok,
            storage_correct_type,
            container_exists,
            policy_exists,
            is_locked,
            retention_adequate,
            append_writes_allowed,
        )

        print("=" * 70)
        sys.exit(exit_code)

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
        print("\n\nVerification cancelled by user.")
        sys.exit(130)
    except Exception as e:
        print(f"ERROR: Unexpected error - {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
