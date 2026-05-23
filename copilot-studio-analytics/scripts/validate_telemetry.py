#!/usr/bin/env python3
"""
Copilot Studio Analytics - Telemetry Validation Script.

Validates that CopilotSessionOutcome events are flowing from the CSA sync
pipeline to Application Insights. Performs post-sync verification to help
confirm the pipeline is correctly configured and producing data.

Usage:
    # Basic validation with config file
    python validate_telemetry.py --config config/config.yml

    # Check telemetry from last 48 hours
    python validate_telemetry.py --config config/config.yml --hours 48

    # Verbose output for debugging
    python validate_telemetry.py --config config/config.yml --verbose

Verification Checks:
    1. Application Insights exists and is workspace-based
    2. CopilotSessionOutcome events present in time window
    3. Events have required customDimensions (recipientId, sessionOutcome, agentMode)
    4. Both conversational and autonomous events present (warning if only one type)

Exit Codes:
    0 - All checks passed
    1 - Critical checks failed (App Insights missing, no events)
    2 - Non-critical warnings (missing agent type, partial data)

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


def print_banner() -> None:
    """Print validation banner."""
    print()
    print("=" * 70)
    print("  Copilot Studio Analytics - Telemetry Validation")
    print("=" * 70)
    print()
    print("  This script verifies CopilotSessionOutcome events are flowing")
    print("  from the CSA sync pipeline to Application Insights.")
    print()


def load_config(args: argparse.Namespace) -> dict[str, Any]:
    """
    Load configuration from YAML file and merge CLI overrides.

    Args:
        args: Parsed command-line arguments

    Returns:
        Configuration dictionary with CLI overrides applied

    Raises:
        FileNotFoundError: If config file does not exist
        ValueError: If required fields are missing
    """
    config_path = args.config
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    # Validate required fields
    required = ["subscription_id", "resource_group"]
    missing = [f for f in required if not config.get(f)]
    if missing:
        raise ValueError(f"Missing required config fields: {', '.join(missing)}")

    # Validate application_insights section
    config.setdefault("application_insights", {})
    if not config["application_insights"].get("name"):
        raise ValueError("application_insights.name is required")

    return config


def verify_application_insights(
    config: dict[str, Any],
    credential: DefaultAzureCredential,
    verbose: bool = False,
) -> tuple[bool, Optional[str], Optional[str]]:
    """
    Verify Application Insights exists and is workspace-based.

    Args:
        config: Configuration dictionary
        credential: Azure credential
        verbose: Show detailed output

    Returns:
        Tuple of (success, workspace_id, instrumentation_key)
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
    print("    - Workspace-based")

    if verbose:
        redacted_key = component.instrumentation_key[:8] + "..." if component.instrumentation_key else "N/A"
        print(f"    - Instrumentation Key: {redacted_key} (redacted)")
        print(f"    - Workspace ID: {workspace_id}")

    return (True, workspace_id, component.instrumentation_key)


def verify_copilot_session_events(
    workspace_id: str,
    credential: DefaultAzureCredential,
    hours: int = 24,
    verbose: bool = False,
) -> tuple[bool, bool, bool, list[dict]]:
    """
    Query for CopilotSessionOutcome events and validate their structure.

    Args:
        workspace_id: Log Analytics workspace resource ID
        credential: Azure credential
        hours: Lookback window in hours
        verbose: Show detailed output

    Returns:
        Tuple of (has_events, has_required_dims, has_both_types, event_details)
    """
    if not LOGS_QUERY_AVAILABLE:
        print("  Telemetry query: SKIPPED (azure-monitor-query not installed)")
        print("    Install with: pip install azure-monitor-query>=1.3.0")
        return (False, False, False, [])

    logs_client = LogsQueryClient(credential)

    # The validate_telemetry config carries `workspace_id` as the ARM resource
    # ID (per config.schema.json), but LogsQueryClient.query_workspace expects
    # the Log Analytics workspace GUID. Detect the difference and dispatch to
    # the correct API:
    #   - GUID format -> query_workspace(workspace_id=GUID, ...)
    #   - ARM ID     -> query_resource(resource_id=ARM, ...)
    is_arm_id = isinstance(workspace_id, str) and workspace_id.startswith("/subscriptions/")

    def _run_query():
        if is_arm_id:
            return logs_client.query_resource(
                resource_id=workspace_id,
                query=query,
                timespan=timedelta(hours=hours),
            )
        return logs_client.query_workspace(
            workspace_id=workspace_id,
            query=query,
            timespan=timedelta(hours=hours),
        )

    # KQL query: check for CopilotSessionOutcome events. Support both the
    # classic Application Insights schema (`customEvents`/`customDimensions`)
    # and workspace-based Log Analytics schema (`AppEvents`/`Properties`).
    query = f"""
    let CSAEvents =
        union isfuzzy=true
            (customEvents
            | project EventTime = timestamp, EventName = name, EventProperties = customDimensions),
            (AppEvents
            | project EventTime = TimeGenerated, EventName = Name, EventProperties = Properties)
        | where EventName == "CopilotSessionOutcome"
        | extend SessionId = tostring(EventProperties["sessionId"])
        | extend SessionTime = coalesce(
            todatetime(EventProperties["sessionClosedOn"]),
            todatetime(EventProperties["sessionCreatedOn"]),
            EventTime)
        | where SessionTime > ago({hours}h)
        | extend DedupKey = iff(isempty(SessionId), strcat(tostring(EventTime), "|", tostring(EventProperties["recipientId"]), "|", EventName), SessionId)
        | summarize arg_max(EventTime, *) by DedupKey;
    CSAEvents
    | summarize
        EventCount=count(),
        DistinctSessions=dcount(SessionId),
        HasRecipientId=countif(isnotempty(tostring(EventProperties["recipientId"]))),
        HasSessionOutcome=countif(isnotempty(tostring(EventProperties["sessionOutcome"]))),
        HasAgentMode=countif(isnotempty(tostring(EventProperties["agentMode"]))),
        ConversationalCount=countif(tostring(EventProperties["agentMode"]) == "Conversational"),
        AutonomousCount=countif(tostring(EventProperties["agentMode"]) == "Autonomous")
    """

    try:
        response = _run_query()
    except HttpResponseError as e:
        # Only retry transient (429 / 5xx) failures. 4xx auth/config errors
        # should surface immediately so the operator can fix the cause.
        status_code = getattr(e, "status_code", None)
        retryable = status_code in (429, 500, 502, 503, 504) if status_code else False
        if not retryable:
            print(f"  Telemetry query: FAILED ({status_code}) - {e}")
            return (False, False, False, [])

        max_retries = 3
        last_error = e
        for attempt in range(1, max_retries + 1):
            import time
            delay = 2 ** attempt
            if verbose:
                print(f"  Transient query error (attempt {attempt}/{max_retries}), retrying in {delay}s...")
            time.sleep(delay)
            try:
                response = _run_query()
                last_error = None
                break
            except HttpResponseError as retry_e:
                last_error = retry_e
        if last_error is not None:
            print(f"  Telemetry query: FAILED after {max_retries} retries - {last_error}")
            return (False, False, False, [])

    if response.status == LogsQueryStatus.PARTIAL:
        print("  Telemetry query: PARTIAL results (query may have timed out)")
    elif response.status == LogsQueryStatus.FAILURE:
        print(f"  Telemetry query: FAILED - {response.partial_error}")
        return (False, False, False, [])

    # Process results
    has_events = False
    has_required_dims = False
    has_both_types = False
    event_details = []

    if response.tables:
        for table in response.tables:
            for row in table.rows:
                event_count = row[0] or 0
                distinct_sessions = row[1] or 0
                has_recipient_id = row[2] or 0
                has_session_outcome = row[3] or 0
                has_agent_mode = row[4] or 0
                conversational_count = row[5] or 0
                autonomous_count = row[6] or 0

                has_events = event_count > 0

                # Check required dimensions present in most events
                if has_events:
                    has_required_dims = (
                        has_recipient_id > 0
                        and has_session_outcome > 0
                        and has_agent_mode > 0
                    )

                    has_both_types = (
                        conversational_count > 0
                        and autonomous_count > 0
                    )

                event_details.append({
                    "event_count": event_count,
                    "distinct_sessions": distinct_sessions,
                    "conversational": conversational_count,
                    "autonomous": autonomous_count,
                    "has_recipient_id": has_recipient_id,
                    "has_session_outcome": has_session_outcome,
                    "has_agent_mode": has_agent_mode,
                })

    return (has_events, has_required_dims, has_both_types, event_details)


def query_outcome_distribution(
    workspace_id: str,
    credential: DefaultAzureCredential,
    hours: int = 24,
    verbose: bool = False,
) -> list[dict]:
    """
    Query outcome distribution for verbose reporting.

    Args:
        workspace_id: Log Analytics workspace resource ID
        credential: Azure credential
        hours: Lookback window in hours
        verbose: Show detailed output

    Returns:
        List of outcome distribution records
    """
    if not LOGS_QUERY_AVAILABLE:
        return []

    logs_client = LogsQueryClient(credential)

    is_arm_id = isinstance(workspace_id, str) and workspace_id.startswith("/subscriptions/")

    def _run_query():
        if is_arm_id:
            return logs_client.query_resource(
                resource_id=workspace_id,
                query=query,
                timespan=timedelta(hours=hours),
            )
        return logs_client.query_workspace(
            workspace_id=workspace_id,
            query=query,
            timespan=timedelta(hours=hours),
        )

    query = f"""
    let CSAEvents =
        union isfuzzy=true
            (customEvents
            | project EventTime = timestamp, EventName = name, EventProperties = customDimensions),
            (AppEvents
            | project EventTime = TimeGenerated, EventName = Name, EventProperties = Properties)
        | where EventName == "CopilotSessionOutcome"
        | extend SessionId = tostring(EventProperties["sessionId"])
        | extend SessionTime = coalesce(
            todatetime(EventProperties["sessionClosedOn"]),
            todatetime(EventProperties["sessionCreatedOn"]),
            EventTime)
        | where SessionTime > ago({hours}h)
        | extend DedupKey = iff(isempty(SessionId), strcat(tostring(EventTime), "|", tostring(EventProperties["recipientId"]), "|", EventName), SessionId)
        | summarize arg_max(EventTime, *) by DedupKey;
    CSAEvents
    | extend agentMode = tostring(EventProperties["agentMode"]),
             sessionOutcome = tostring(EventProperties["sessionOutcome"])
    | summarize Count=count() by agentMode, sessionOutcome
    | order by agentMode asc, Count desc
    """

    try:
        response = _run_query()
    except HttpResponseError:
        return []

    results = []
    if response.tables:
        for table in response.tables:
            for row in table.rows:
                results.append({
                    "agentMode": row[0],
                    "sessionOutcome": row[1],
                    "count": row[2],
                })

    return results


def print_event_summary(event_details: list[dict], hours: int) -> None:
    """Print event summary table."""
    if not event_details:
        print(f"  CopilotSessionOutcome (last {hours}h): No data")
        return

    for detail in event_details:
        print(f"  CopilotSessionOutcome (last {hours}h):")
        print()
        print(f"    {'Metric':<35} {'Value':>10}")
        print(f"    {'-'*35} {'-'*10}")
        print(f"    {'Total events':<35} {detail['event_count']:>10}")
        print(f"    {'Distinct sessions':<35} {detail['distinct_sessions']:>10}")
        print(f"    {'Conversational events':<35} {detail['conversational']:>10}")
        print(f"    {'Autonomous events':<35} {detail['autonomous']:>10}")
        print()
        print(f"    {'Required Dimensions Coverage':<35}")
        print(f"    {'  recipientId present':<35} {detail['has_recipient_id']:>10}")
        print(f"    {'  sessionOutcome present':<35} {detail['has_session_outcome']:>10}")
        print(f"    {'  agentMode present':<35} {detail['has_agent_mode']:>10}")
        print()


def print_outcome_distribution(outcomes: list[dict], hours: int) -> None:
    """Print outcome distribution table."""
    if not outcomes:
        return

    print(f"  Outcome Distribution (last {hours}h):")
    print()
    print(f"    {'Agent Mode':<20} {'Outcome':<20} {'Count':>10}")
    print(f"    {'-'*20} {'-'*20} {'-'*10}")

    for outcome in outcomes:
        mode = outcome["agentMode"] or "(empty)"
        result = outcome["sessionOutcome"] or "(empty)"
        print(f"    {mode:<20} {result:<20} {outcome['count']:>10}")

    print()


def print_verification_summary(
    ai_exists: bool,
    has_events: bool,
    has_required_dims: bool,
    has_both_types: bool,
) -> int:
    """
    Print verification summary and determine exit code.

    Args:
        ai_exists: Application Insights exists and is workspace-based
        has_events: CopilotSessionOutcome events present
        has_required_dims: Required customDimensions present
        has_both_types: Both conversational and autonomous events found

    Returns:
        Exit code (0=pass, 1=critical failure, 2=warnings)
    """
    print()
    print("=" * 70)
    print("  VALIDATION SUMMARY")
    print("=" * 70)
    print()

    checks = [
        ("Application Insights (workspace-based)", ai_exists, True),
        ("CopilotSessionOutcome events present", has_events, True),
        ("Required customDimensions present", has_required_dims, True),
        ("Both agent types present", has_both_types, False),
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
        print("  CSA sync pipeline is not producing expected telemetry.")
        print()
        print("  Next steps:")
        print("    1. Verify sync_dataverse_sessions.py ran successfully")
        print("    2. Check APPLICATIONINSIGHTS_CONNECTION_STRING is correct")
        print("    3. Verify Dataverse msdyn_botsession contains session data")
        print("    4. Run sync with --verbose for detailed diagnostics")
        print()
        return 1

    if has_warnings:
        print("  Status: PIPELINE OPERATIONAL (with warnings)")
        print()
        print("  CopilotSessionOutcome events are flowing but not all agent types")
        print("  are represented. This may be expected if your environment only has")
        print("  one type of agent deployed.")
        print()
        return 2

    print("  Status: ALL CHECKS PASSED")
    print("  CSA telemetry pipeline is operational.")
    print()
    return 0


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Validate CopilotSessionOutcome telemetry in Application Insights",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Basic validation with config file
    python validate_telemetry.py --config config/config.yml

    # Check telemetry from last 48 hours
    python validate_telemetry.py --config config/config.yml --hours 48

    # Verbose output for debugging
    python validate_telemetry.py --config config/config.yml --verbose
        """,
    )

    # Config file
    parser.add_argument(
        "--config",
        default="config/config.yml",
        help="Path to YAML configuration file (default: config/config.yml)",
    )

    # Query options
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
        help="Show detailed output including outcome distribution",
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
        ai_exists, workspace_id, ikey = verify_application_insights(
            config, credential, args.verbose
        )
        print()

        # 2-4. Query CopilotSessionOutcome events
        has_events = False
        has_required_dims = False
        has_both_types = False
        event_details = []

        if ai_exists and workspace_id:
            print(f"  Querying CopilotSessionOutcome events (last {args.hours} hours)...")
            has_events, has_required_dims, has_both_types, event_details = (
                verify_copilot_session_events(
                    workspace_id, credential, args.hours, args.verbose
                )
            )
            print()
            print_event_summary(event_details, args.hours)

            # Verbose: show outcome distribution
            if args.verbose and has_events:
                outcomes = query_outcome_distribution(
                    workspace_id, credential, args.hours, args.verbose
                )
                print_outcome_distribution(outcomes, args.hours)

        # Print summary and get exit code
        exit_code = print_verification_summary(
            ai_exists, has_events, has_required_dims, has_both_types
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
        print("  - Use workload identity or managed identity via DefaultAzureCredential")
        print("  - For legacy dev-only runs, set AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET")
        sys.exit(1)
    except AzureError as e:
        print(f"ERROR: Azure SDK error - {e.message}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\nValidation cancelled by user.")
        sys.exit(130)
    except Exception as e:
        print(f"ERROR: Unexpected error - {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
