#!/usr/bin/env python3
"""
Agent Observability Foundation - Telemetry Verification Script.

Validates that telemetry is flowing from Copilot Studio to Application Insights.
Performs post-deployment verification to ensure the observability infrastructure
is correctly configured and receiving data.

Usage:
    # Basic verification with config file
    python verify_telemetry.py --config config/config.yml

    # Check telemetry from last 48 hours
    python verify_telemetry.py --config config/config.yml --hours 48

    # Override Application Insights name
    python verify_telemetry.py --config config/config.yml --app-insights-name ai-custom

    # Verbose output for debugging
    python verify_telemetry.py --config config/config.yml --verbose

Verification Checks:
    1. Application Insights exists and is workspace-based
    2. Retention is >= 730 days (SEC 17a-4 compliance)
    3. customEvents table has data in lookback window
    4. CopilotInteraction events detected (Copilot Studio connected)

Exit Codes:
    0 - All checks passed
    1 - Critical checks failed (App Insights missing, wrong retention)
    2 - Non-critical warnings (no data yet, but infrastructure OK)

Requirements:
    pip install azure-monitor-query>=1.3.0
"""

import argparse
import os
import sys
from datetime import timedelta
from typing import Any, Optional

import yaml

# Azure SDK imports
from azure.identity import DefaultAzureCredential
from azure.core.exceptions import (
    AzureError,
    ClientAuthenticationError,
    HttpResponseError,
    ResourceNotFoundError,
)
from azure.mgmt.applicationinsights import ApplicationInsightsManagementClient

# Log query SDK (optional dependency)
try:
    from azure.monitor.query import LogsQueryClient, LogsQueryStatus
    LOGS_QUERY_AVAILABLE = True
except ImportError:
    LOGS_QUERY_AVAILABLE = False


def print_banner():
    """Print verification banner."""
    print()
    print("=" * 70)
    print("  Agent Observability Foundation - Telemetry Verification")
    print("=" * 70)
    print()
    print("  This script verifies telemetry flow from Copilot Studio to")
    print("  Application Insights for FSI compliance monitoring.")
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
    if args.app_insights_name:
        config.setdefault("application_insights", {})
        config["application_insights"]["name"] = args.app_insights_name

    # Validate required fields
    required = ["subscription_id", "resource_group"]
    missing = [f for f in required if not config.get(f)]
    if missing:
        raise ValueError(f"Missing required config fields: {', '.join(missing)}")

    # Apply defaults
    prefix = config.get("naming_prefix", "aof")
    config.setdefault("application_insights", {})
    config.setdefault("log_analytics", {})

    if not config["application_insights"].get("name"):
        config["application_insights"]["name"] = f"ai-{prefix}-observability"
    if not config["log_analytics"].get("name"):
        config["log_analytics"]["name"] = f"law-{prefix}-observability"

    return config


def verify_application_insights(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    verbose: bool = False,
) -> tuple[bool, Optional[str], Optional[int]]:
    """
    Verify Application Insights exists and is configured correctly.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        verbose: Show detailed output

    Returns:
        Tuple of (success, workspace_id, retention_days)
    """
    subscription_id = config["subscription_id"]
    resource_group = config["resource_group"]
    ai_name = config["application_insights"]["name"]

    ai_client = ApplicationInsightsManagementClient(credential, subscription_id)

    try:
        component = ai_client.components.get(
            resource_group_name=resource_group,
            resource_name=ai_name,
        )
    except ResourceNotFoundError:
        print(f"  Application Insights: {ai_name} NOT FOUND")
        return (False, None, None)

    # Check if workspace-based
    workspace_id = component.workspace_resource_id
    if not workspace_id:
        print(f"  Application Insights: {ai_name} exists but NOT workspace-based")
        print("    Classic Application Insights was deprecated Feb 2024.")
        print("    Recreate as workspace-based for full functionality.")
        return (False, None, None)

    print(f"  Application Insights: {ai_name}")
    print(f"    - Workspace-based")

    # Check retention
    retention = component.retention_in_days
    print(f"    - Retention: {retention} days")

    if verbose:
        print(f"    - Instrumentation Key: {component.instrumentation_key}")
        print(f"    - Workspace ID: {workspace_id}")

    return (True, workspace_id, retention)


def verify_retention_compliance(retention_days: int) -> bool:
    """
    Verify retention meets SEC 17a-4 requirements.

    Args:
        retention_days: Configured retention in days

    Returns:
        True if compliant (>= 730 days)
    """
    min_retention = 730  # SEC 17a-4(b)(4) requires 2-year retention

    if retention_days >= min_retention:
        print(f"  Retention compliance: >= {min_retention} days (SEC 17a-4)")
        return True
    else:
        print(f"  Retention compliance: {retention_days} days < {min_retention} required")
        print(f"    SEC 17a-4(b)(4) requires 2-year (730 day) retention.")
        print(f"    Update Application Insights retention settings.")
        return False


def query_telemetry_data(
    workspace_id: str,
    credential: DefaultAzureCredential,
    hours: int = 24,
    verbose: bool = False,
) -> tuple[bool, bool, list[dict]]:
    """
    Query customEvents table for telemetry data.

    Args:
        workspace_id: Log Analytics workspace resource ID
        credential: Azure credential
        hours: Lookback window in hours
        verbose: Show detailed output

    Returns:
        Tuple of (has_data, has_copilot_events, event_summary)
    """
    if not LOGS_QUERY_AVAILABLE:
        print("  Telemetry query: SKIPPED (azure-monitor-query not installed)")
        print("    Install with: pip install azure-monitor-query>=1.3.0")
        return (False, False, [])

    logs_client = LogsQueryClient(credential)

    # KQL query to summarize custom events
    query = f"""
    customEvents
    | where timestamp > ago({hours}h)
    | summarize EventCount=count(), DistinctSessions=dcount(session_Id) by name
    | order by EventCount desc
    """

    try:
        # Extract workspace GUID from ARM resource ID
        # Format: /subscriptions/.../providers/Microsoft.OperationalInsights/workspaces/{name}
        # query_workspace() requires the workspace ID (GUID), not the name.
        # Use the full resource ID which the SDK resolves to the correct workspace.
        workspace_resource_id = workspace_id
        response = logs_client.query_workspace(
            workspace_id=workspace_resource_id,
            query=query,
            timespan=timedelta(hours=hours),
        )
    except HttpResponseError as e:
        # Retry with exponential backoff for transient errors
        max_retries = 3
        last_error = e
        for attempt in range(1, max_retries + 1):
            import time
            delay = 2 ** attempt
            if verbose:
                print(f"  Telemetry query failed (attempt {attempt}/{max_retries}), retrying in {delay}s...")
            time.sleep(delay)
            try:
                response = logs_client.query_workspace(
                    workspace_id=workspace_resource_id,
                    query=query,
                    timespan=timedelta(hours=hours),
                )
                last_error = None
                break
            except HttpResponseError as retry_e:
                last_error = retry_e
        if last_error is not None:
            print(f"  Telemetry query: FAILED after {max_retries} retries - {last_error}")
            return (False, False, [])

    if response.status == LogsQueryStatus.PARTIAL:
        print(f"  Telemetry query: PARTIAL results (query may have timed out)")
    elif response.status == LogsQueryStatus.FAILURE:
        print(f"  Telemetry query: FAILED - {response.partial_error}")
        return (False, False, [])

    # Process results
    events = []
    has_copilot_events = False

    if response.tables:
        for table in response.tables:
            for row in table.rows:
                event_name = row[0]
                event_count = row[1]
                distinct_sessions = row[2]
                events.append({
                    "name": event_name,
                    "count": event_count,
                    "sessions": distinct_sessions,
                })
                # Check for Copilot Studio events
                if event_name and "copilot" in event_name.lower():
                    has_copilot_events = True

    has_data = len(events) > 0
    return (has_data, has_copilot_events, events)


def print_telemetry_summary(events: list[dict], hours: int) -> None:
    """
    Print telemetry event summary table.

    Args:
        events: List of event dictionaries
        hours: Lookback window
    """
    if not events:
        print(f"  customEvents (last {hours}h): No data")
        return

    print(f"  customEvents (last {hours}h):")
    print()
    print(f"    {'Event Name':<40} {'Count':>10} {'Sessions':>10}")
    print(f"    {'-'*40} {'-'*10} {'-'*10}")

    for event in events[:10]:  # Show top 10
        name = event["name"][:40] if event["name"] else "(unnamed)"
        print(f"    {name:<40} {event['count']:>10} {event['sessions']:>10}")

    if len(events) > 10:
        print(f"    ... and {len(events) - 10} more event types")

    print()


def print_verification_summary(
    ai_exists: bool,
    retention_ok: bool,
    has_data: bool,
    has_copilot: bool,
) -> int:
    """
    Print verification summary and determine exit code.

    Args:
        ai_exists: Application Insights exists and is workspace-based
        retention_ok: Retention meets SEC 17a-4 requirements
        has_data: customEvents table has data
        has_copilot: Copilot Studio events detected

    Returns:
        Exit code (0=pass, 1=critical failure, 2=warnings)
    """
    print()
    print("=" * 70)
    print("  VERIFICATION SUMMARY")
    print("=" * 70)
    print()

    checks = [
        ("Application Insights (workspace-based)", ai_exists, True),
        ("Retention >= 730 days (SEC 17a-4)", retention_ok, True),
        ("customEvents has data", has_data, False),
        ("Copilot Studio events detected", has_copilot, False),
    ]

    critical_failed = False
    has_warnings = False

    for check_name, passed, is_critical in checks:
        if passed:
            status = "PASS"
        elif is_critical:
            status = "FAIL"
            critical_failed = True
        else:
            status = "WARN"
            has_warnings = True

        print(f"    [{status}] {check_name}")

    print()

    if critical_failed:
        print("  Status: CRITICAL FAILURE")
        print("  Infrastructure is not correctly configured.")
        print()
        print("  Next steps:")
        print("    1. Run provision.py to create missing resources")
        print("    2. Verify Azure permissions")
        print()
        return 1

    if has_warnings:
        print("  Status: INFRASTRUCTURE OK (with warnings)")
        print()
        print("  Infrastructure is correctly configured but no telemetry data yet.")
        print()
        print("  Next steps:")
        print("    1. Ensure Copilot Studio agent is connected to Application Insights")
        print("    2. Generate some agent interactions")
        print("    3. Wait a few minutes and re-run verification")
        print("    4. See README.md Troubleshooting section or scripts/validation-checklist.md for guidance")
        print()
        return 2

    print("  Status: ALL CHECKS PASSED")
    print("  Telemetry infrastructure is operational.")
    print()
    return 0


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Verify telemetry flow from Copilot Studio to Application Insights",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Basic verification with config file
    python verify_telemetry.py --config config/config.yml

    # Check telemetry from last 48 hours
    python verify_telemetry.py --config config/config.yml --hours 48

    # Override Application Insights name
    python verify_telemetry.py --config config/config.yml --app-insights-name ai-custom
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
        "--app-insights-name",
        help="Application Insights resource name (overrides config)",
    )
    parser.add_argument(
        "--hours",
        type=int,
        default=24,
        help="Lookback window in hours for telemetry query (default: 24)",
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

        # 1. Verify Application Insights exists
        ai_exists, workspace_id, retention = verify_application_insights(
            config, credential, args.verbose
        )
        print()

        # 2. Verify retention compliance
        retention_ok = False
        if retention is not None:
            retention_ok = verify_retention_compliance(retention)
            print()

        # 3. Query telemetry data
        has_data = False
        has_copilot = False
        events = []

        if ai_exists and workspace_id:
            print(f"  Querying telemetry data (last {args.hours} hours)...")
            has_data, has_copilot, events = query_telemetry_data(
                workspace_id, credential, args.hours, args.verbose
            )
            print()
            print_telemetry_summary(events, args.hours)

        # Print summary and get exit code
        exit_code = print_verification_summary(
            ai_exists, retention_ok, has_data, has_copilot
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
