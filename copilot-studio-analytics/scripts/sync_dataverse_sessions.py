#!/usr/bin/env python3
"""
Copilot Studio Analytics - Dataverse Session Sync Script.

Syncs Copilot Studio session data from Dataverse (msdyn_botsession) to
Application Insights as CopilotSessionOutcome custom events. Supports
incremental sync via watermark table and idempotent processing.

Usage:
    # Basic sync with config file
    python sync_dataverse_sessions.py --config config/config.yml

    # Dry run (no writes to App Insights or Dataverse)
    python sync_dataverse_sessions.py --config config/config.yml --dry-run

    # Tier 2 sync (includes transcript parsing)
    python sync_dataverse_sessions.py --config config/config.yml --tier 2

    # Verbose output for debugging
    python sync_dataverse_sessions.py --config config/config.yml --verbose

Sync Pipeline:
    1. Read watermark (last successful sync timestamp)
    2. Fetch msdyn_botsession records since watermark - lookback buffer
    3. Classify agents as Conversational or Autonomous via botcomponent
    4. Correlate knowledge sources (Tier 1: GenerativeAnswers check)
    5. Transform sessions to CopilotSessionOutcome custom events
    6. Send batches to Application Insights
    7. Update watermark on success

Exit Codes:
    0 - Sync completed successfully
    1 - Critical error (config, auth, API failure)
    2 - Partial sync (some batches failed)

Requirements:
    pip install -r requirements.txt
"""

import argparse
import json
import logging
import os
import sys
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import yaml

# Import shared Dataverse client
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

# Application Insights SDK for writing custom events
from applicationinsights import TelemetryClient

# Configure logging
logger = logging.getLogger("csa-sync")

# Dataverse session outcome option set values
SESSION_OUTCOMES = {
    192350001: "Resolved",
    192350002: "Escalated",
    192350003: "Abandoned",
    192350004: "Unengaged",
}

# Dataverse session outcome reason option set values
SESSION_OUTCOME_REASONS = {
    192350100: "TopicResolved",
    192350101: "UserEndedConversation",
    192350102: "HandoffInitiated",
    192350103: "AgentTransfer",
    192350104: "Timeout",
    192350105: "UserAbandoned",
    192350106: "NoEngagement",
}

# CSA Sync watermark table constants
WATERMARK_TABLE = "fsi_csasyncwatermarks"
WATERMARK_STATUS_SUCCESS = 100000000
WATERMARK_STATUS_FAILED = 100000001
WATERMARK_STATUS_IN_PROGRESS = 100000002
WATERMARK_STATUS_WARNING = 100000003
WATERMARK_TIER_1 = 100000000
WATERMARK_TIER_2 = 100000001


def load_config(config_path: str) -> dict[str, Any]:
    """
    Load and validate YAML configuration.

    Args:
        config_path: Path to YAML config file

    Returns:
        Configuration dictionary with defaults applied

    Raises:
        FileNotFoundError: If config file does not exist
        ValueError: If required fields are missing
    """
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with open(config_path, "r", encoding="utf-8") as f:
        config = yaml.safe_load(f)

    # Validate required sections
    required_sections = ["subscription_id", "resource_group", "application_insights", "dataverse"]
    missing = [s for s in required_sections if not config.get(s)]
    if missing:
        raise ValueError(f"Missing required config sections: {', '.join(missing)}")

    # Validate nested required fields
    ai_config = config.get("application_insights", {})
    if not ai_config.get("name"):
        raise ValueError("application_insights.name is required")

    dv_config = config.get("dataverse", {})
    dv_required = ["tenant_id", "environment_url", "client_id"]
    dv_missing = [f for f in dv_required if not dv_config.get(f)]
    if dv_missing:
        raise ValueError(f"Missing required dataverse fields: {', '.join(dv_missing)}")

    # Apply sync defaults
    config.setdefault("sync", {})
    config["sync"].setdefault("lookback_buffer_hours", 2)
    config["sync"].setdefault("tier", 1)
    config["sync"].setdefault("batch_size", 500)

    # Apply business impact defaults
    config.setdefault("business_impact", {})
    config["business_impact"].setdefault("conversational", {})
    config["business_impact"]["conversational"].setdefault("time_savings_minutes", 6)
    config["business_impact"]["conversational"].setdefault("resolved_no_ks_weight", 1.0)
    config["business_impact"]["conversational"].setdefault("escalated_abandoned_no_ks_weight", 0.7)
    config["business_impact"].setdefault("autonomous", {})
    config["business_impact"]["autonomous"].setdefault("info_retrieval_time_saving_minutes", 6)
    config["business_impact"]["autonomous"].setdefault("generic_action_multiplier_minutes", 3)
    config["business_impact"]["autonomous"].setdefault("generic_time_saving_minutes", 5)
    config["business_impact"]["autonomous"].setdefault("action_multipliers", {})
    config["business_impact"].setdefault("hourly_rate", 72)

    # Apply zone mapping defaults
    config.setdefault("zone_mapping", {})

    return config


def get_agent_classifications(client: DataverseClient) -> dict[str, str]:
    """
    Classify agents as Conversational or Autonomous by querying botcomponent.

    Autonomous agents have at least one botcomponent with componenttypename=17
    (External Trigger / Event-Driven). All others are Conversational.

    Args:
        client: DataverseClient instance

    Returns:
        Dict mapping bot ID to "Autonomous" or "Conversational"
    """
    logger.info("Fetching agent classifications from botcomponent...")

    # Query all bots
    bots = client.query(
        "bots",
        select=["botid", "name"],
    )

    classifications = {}
    for bot in bots:
        bot_id = bot.get("botid", "")
        classifications[bot_id] = "Conversational"  # Default

    # Query botcomponents with External Trigger type (componenttype 17)
    # to identify autonomous agents
    autonomous_components = client.query(
        "botcomponents",
        select=["_botid_value", "componenttype"],
        filter_expr="componenttype eq 17",
    )

    autonomous_bot_ids = set()
    for comp in autonomous_components:
        bot_id = comp.get("_botid_value", "")
        if bot_id:
            autonomous_bot_ids.add(bot_id)

    for bot_id in autonomous_bot_ids:
        classifications[bot_id] = "Autonomous"

    autonomous_count = len(autonomous_bot_ids)
    conversational_count = len(classifications) - autonomous_count
    logger.info(
        "Agent classification complete: %d conversational, %d autonomous",
        conversational_count,
        autonomous_count,
    )

    return classifications


def get_watermark(
    client: DataverseClient,
    environment_url: str,
    tier: int,
) -> Optional[datetime]:
    """
    Read the last successful sync timestamp from the watermark table.

    Args:
        client: DataverseClient instance
        environment_url: Environment URL to filter watermark records
        tier: Sync tier (1 or 2)

    Returns:
        Last sync timestamp or None if no watermark exists
    """
    tier_value = WATERMARK_TIER_1 if tier == 1 else WATERMARK_TIER_2

    # Validate environment_url to prevent OData filter injection
    import re
    if not re.match(r'^https://[a-zA-Z0-9._-]+\.dynamics\.com$', environment_url):
        raise ValueError(f"Invalid environment URL format: {environment_url}")

    records = client.query(
        WATERMARK_TABLE,
        select=["fsi_lastsynctimestamp", "fsi_syncstatus"],
        filter_expr=(
            f"fsi_environmenturl eq '{environment_url}' "
            f"and fsi_synctier eq {tier_value} "
            f"and fsi_syncstatus eq {WATERMARK_STATUS_SUCCESS}"
        ),
        orderby="fsi_lastsynctimestamp desc",
        top=1,
    )

    if not records:
        logger.info("No watermark found - performing initial sync")
        return None

    timestamp_str = records[0].get("fsi_lastsynctimestamp", "")
    if not timestamp_str:
        return None

    # Parse ISO 8601 datetime from Dataverse
    timestamp = datetime.fromisoformat(timestamp_str.replace("Z", "+00:00"))
    logger.info("Watermark found: %s", timestamp.isoformat())
    return timestamp


def update_watermark(
    client: DataverseClient,
    environment_url: str,
    tier: int,
    timestamp: datetime,
    records_synced: int,
    status: int,
    error_message: Optional[str] = None,
) -> None:
    """
    Create or update the sync watermark record.

    Args:
        client: DataverseClient instance
        environment_url: Environment URL
        tier: Sync tier (1 or 2)
        timestamp: Sync timestamp to record
        records_synced: Count of records synced
        status: Watermark status code
        error_message: Optional error message for failed syncs
    """
    tier_value = WATERMARK_TIER_1 if tier == 1 else WATERMARK_TIER_2

    data = {
        "fsi_environmenturl": environment_url,
        "fsi_lastsynctimestamp": timestamp.isoformat(),
        "fsi_recordssynced": records_synced,
        "fsi_syncstatus": status,
        "fsi_synctier": tier_value,
    }

    if error_message:
        data["fsi_errormessage"] = error_message[:100000]  # Respect Memo max length

    client.create_record(WATERMARK_TABLE, data)
    logger.info(
        "Watermark updated: %s (records: %d, status: %d)",
        timestamp.isoformat(),
        records_synced,
        status,
    )


def fetch_sessions(
    client: DataverseClient,
    watermark: Optional[datetime],
    lookback_hours: int,
) -> list[dict]:
    """
    Fetch msdyn_botsession records since the watermark minus lookback buffer.

    Args:
        client: DataverseClient instance
        watermark: Last sync timestamp (None for initial sync)
        lookback_hours: Safety buffer hours for late-arriving sessions

    Returns:
        List of session records from Dataverse
    """
    # Calculate the effective start time
    if watermark:
        start_time = watermark - timedelta(hours=lookback_hours)
    else:
        # Initial sync: go back 30 days
        start_time = datetime.now(timezone.utc) - timedelta(days=30)

    start_iso = start_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    logger.info("Fetching sessions since %s", start_iso)

    sessions = client.query(
        "msdyn_botsessions",
        select=[
            "msdyn_botsessionid",
            "_msdyn_botid_value",
            "msdyn_sessionoutcome",
            "msdyn_sessionoutcomereason",
            "msdyn_sessioncreatedon",
            "msdyn_sessionclosedon",
            "msdyn_isengaged",
            "msdyn_csatscore",
            "msdyn_topicname",
            "msdyn_channelid",
        ],
        filter_expr=f"msdyn_sessioncreatedon ge {start_iso}",
        orderby="msdyn_sessioncreatedon asc",
    )

    logger.info("Fetched %d sessions from Dataverse", len(sessions))
    return sessions


def correlate_knowledge_sources(
    client: DataverseClient,
    sessions: list[dict],
) -> dict[str, bool]:
    """
    Tier 1: Determine which sessions used knowledge sources by checking for
    GenerativeAnswers events in the conversation transcript metadata.

    For Tier 1, we check msdyn_botsession for the presence of generative
    answers topic references (a lightweight proxy for knowledge source usage).

    Args:
        client: DataverseClient instance
        sessions: List of session records

    Returns:
        Dict mapping session ID to has_knowledge_source boolean
    """
    logger.info("Correlating knowledge sources for %d sessions...", len(sessions))

    ks_map: dict[str, bool] = {}

    # Tier 1: Check if the topic name indicates generative answers usage
    # GenerativeAnswers topics are created automatically when knowledge sources are used
    for session in sessions:
        session_id = session.get("msdyn_botsessionid", "")
        topic_name = session.get("msdyn_topicname", "") or ""

        # Sessions with GenerativeAnswers or knowledge-related topics
        has_ks = any(
            keyword in topic_name.lower()
            for keyword in ["generativeanswers", "knowledge"]
        )
        ks_map[session_id] = has_ks

    ks_count = sum(1 for v in ks_map.values() if v)
    logger.info("Knowledge source correlation: %d/%d sessions with KS", ks_count, len(sessions))

    return ks_map


def resolve_zone(environment_url: str, zone_mapping: dict[str, str]) -> str:
    """
    Resolve governance zone from environment URL using zone mapping.

    Args:
        environment_url: Dataverse environment URL
        zone_mapping: Mapping of URL prefixes to zone names

    Returns:
        Zone name string
    """
    if not zone_mapping:
        return "Unclassified"

    # Extract the hostname from the URL
    hostname = environment_url.replace("https://", "").replace("http://", "").split("/")[0]

    for prefix, zone in zone_mapping.items():
        if prefix == "default":
            continue
        if hostname.startswith(prefix):
            return zone

    return zone_mapping.get("default", "Unclassified")


def transform_session(
    session: dict,
    agent_classifications: dict[str, str],
    ks_map: dict[str, bool],
    zone: str,
    tier: int,
) -> Optional[dict]:
    """
    Transform a Dataverse session record into a CopilotSessionOutcome event.

    Args:
        session: Raw Dataverse session record
        agent_classifications: Bot ID to agent mode mapping
        ks_map: Session ID to knowledge source boolean mapping
        zone: Governance zone name
        tier: Sync tier

    Returns:
        Dict with event name and customDimensions, or None if invalid
    """
    session_id = session.get("msdyn_botsessionid", "")
    bot_id = session.get("_msdyn_botid_value", "")

    if not session_id or not bot_id:
        logger.debug("Skipping session with missing ID or bot ID")
        return None

    # Determine agent mode
    agent_mode = agent_classifications.get(bot_id, "Conversational")

    # Map session outcome
    raw_outcome = session.get("msdyn_sessionoutcome")
    outcome_str = SESSION_OUTCOMES.get(raw_outcome, "Unknown")

    # Map outcome differently for autonomous agents
    if agent_mode == "Autonomous":
        if outcome_str == "Resolved":
            outcome_str = "Success"
        elif outcome_str in ("Abandoned", "Escalated"):
            outcome_str = "Failure"

    # Map outcome reason
    raw_reason = session.get("msdyn_sessionoutcomereason")
    reason_str = SESSION_OUTCOME_REASONS.get(raw_reason, "Unknown")

    # Calculate session duration
    created_on = session.get("msdyn_sessioncreatedon", "")
    closed_on = session.get("msdyn_sessionclosedon", "")
    duration_seconds = None
    if created_on and closed_on:
        try:
            start = datetime.fromisoformat(created_on.replace("Z", "+00:00"))
            end = datetime.fromisoformat(closed_on.replace("Z", "+00:00"))
            duration_seconds = int((end - start).total_seconds())
        except (ValueError, TypeError):
            pass

    # CSAT score (always null for autonomous agents)
    csat_score = None
    if agent_mode != "Autonomous":
        csat_score = session.get("msdyn_csatscore")

    # Knowledge source
    has_ks = ks_map.get(session_id, False)

    # Build customDimensions
    custom_dimensions = {
        "recipientId": bot_id,
        "sessionId": session_id,
        "sessionOutcome": outcome_str,
        "sessionOutcomeReason": reason_str,
        "isEngaged": str(session.get("msdyn_isengaged", False)).lower(),
        "csatScore": str(csat_score) if csat_score is not None else "",
        "sessionDurationSeconds": str(duration_seconds) if duration_seconds is not None else "",
        "hasKnowledgeSource": str(has_ks).lower(),
        "topicName": session.get("msdyn_topicname", "") or "",
        "agentMode": agent_mode,
        "channelId": session.get("msdyn_channelid", "") or "",
        "Zone": zone,
        "syncSource": "DataverseSync",
        "syncTier": f"Tier{tier}",
    }

    return {
        "name": "CopilotSessionOutcome",
        "timestamp": created_on,
        "customDimensions": custom_dimensions,
    }


def send_to_app_insights(
    events: list[dict],
    instrumentation_key: str,
    batch_size: int,
    dry_run: bool = False,
) -> tuple[int, int]:
    """
    Send CopilotSessionOutcome events to Application Insights in batches.

    Args:
        events: List of transformed event dicts
        instrumentation_key: App Insights instrumentation key
        batch_size: Number of events per batch
        dry_run: If True, log events without sending

    Returns:
        Tuple of (sent_count, failed_count)
    """
    if not events:
        logger.info("No events to send")
        return (0, 0)

    if dry_run:
        logger.info("[DRY RUN] Would send %d events to App Insights", len(events))
        for i, event in enumerate(events[:3]):
            logger.info(
                "  [DRY RUN] Event %d: %s (outcome=%s, mode=%s)",
                i + 1,
                event["customDimensions"]["sessionId"],
                event["customDimensions"]["sessionOutcome"],
                event["customDimensions"]["agentMode"],
            )
        if len(events) > 3:
            logger.info("  [DRY RUN] ... and %d more events", len(events) - 3)
        return (len(events), 0)

    tc = TelemetryClient(instrumentation_key)

    sent = 0
    failed = 0

    # Process in batches
    for batch_start in range(0, len(events), batch_size):
        batch = events[batch_start : batch_start + batch_size]
        batch_num = (batch_start // batch_size) + 1
        total_batches = (len(events) + batch_size - 1) // batch_size

        logger.info("Sending batch %d/%d (%d events)...", batch_num, total_batches, len(batch))

        try:
            for event in batch:
                tc.track_event(
                    event["name"],
                    properties=event["customDimensions"],
                )
            tc.flush()
            sent += len(batch)
            logger.info("Batch %d/%d sent successfully", batch_num, total_batches)
        except Exception as e:
            failed += len(batch)
            logger.error("Batch %d/%d failed: %s", batch_num, total_batches, e)

    logger.info("App Insights send complete: %d sent, %d failed", sent, failed)
    return (sent, failed)


def get_instrumentation_key(config: dict[str, Any]) -> str:
    """
    Retrieve the App Insights instrumentation key.

    Checks APPINSIGHTS_INSTRUMENTATIONKEY env var first, then attempts
    to resolve from Azure management API.

    Args:
        config: Configuration dictionary

    Returns:
        Instrumentation key string

    Raises:
        ValueError: If key cannot be resolved
    """
    # Check environment variable first
    ikey = os.environ.get("APPINSIGHTS_INSTRUMENTATIONKEY", "")
    if ikey:
        return ikey

    # Try to resolve from Azure management API
    try:
        from azure.identity import DefaultAzureCredential
        from azure.mgmt.applicationinsights import ApplicationInsightsManagementClient

        credential = DefaultAzureCredential()
        ai_client = ApplicationInsightsManagementClient(
            credential, config["subscription_id"]
        )
        component = ai_client.components.get(
            resource_group_name=config["resource_group"],
            resource_name=config["application_insights"]["name"],
        )
        return component.instrumentation_key
    except Exception as e:
        raise ValueError(
            f"Cannot resolve instrumentation key. Set APPINSIGHTS_INSTRUMENTATIONKEY "
            f"env var or provide Azure credentials: {e}"
        )


def print_banner():
    """Print sync banner."""
    print()
    print("=" * 70)
    print("  Copilot Studio Analytics - Dataverse Session Sync")
    print("=" * 70)
    print()


def print_sync_summary(
    sessions_fetched: int,
    events_transformed: int,
    sent: int,
    failed: int,
    duration_seconds: float,
) -> None:
    """Print sync summary."""
    print()
    print("=" * 70)
    print("  SYNC SUMMARY")
    print("=" * 70)
    print()
    print(f"    Sessions fetched:      {sessions_fetched}")
    print(f"    Events transformed:    {events_transformed}")
    print(f"    Events sent:           {sent}")
    print(f"    Events failed:         {failed}")
    print(f"    Duration:              {duration_seconds:.1f}s")
    print()

    if failed == 0 and sent > 0:
        print("  Status: SYNC COMPLETE")
    elif failed > 0 and sent > 0:
        print("  Status: PARTIAL SYNC (some batches failed)")
    elif sent == 0 and sessions_fetched == 0:
        print("  Status: NO NEW SESSIONS")
    else:
        print("  Status: SYNC FAILED")
    print()
    print("=" * 70)


def main():
    """CLI entry point for Dataverse session sync."""
    parser = argparse.ArgumentParser(
        description="Sync Copilot Studio sessions from Dataverse to Application Insights",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Basic sync with config file
    python sync_dataverse_sessions.py --config config/config.yml

    # Dry run (preview without changes)
    python sync_dataverse_sessions.py --config config/config.yml --dry-run

    # Tier 2 sync (includes transcript parsing)
    python sync_dataverse_sessions.py --config config/config.yml --tier 2
        """,
    )

    parser.add_argument(
        "--config",
        default="config/config.yml",
        help="Path to YAML configuration file (default: config/config.yml)",
    )
    parser.add_argument(
        "--tier",
        type=int,
        choices=[1, 2],
        help="Sync tier override (1=sessions only, 2=adds transcripts)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview sync operations without writing to App Insights or Dataverse",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Show detailed output",
    )

    args = parser.parse_args()

    # Configure logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    print_banner()

    sync_start = datetime.now(timezone.utc)

    try:
        # 1. Load configuration
        logger.info("Loading configuration from %s", args.config)
        config = load_config(args.config)

        tier = args.tier or config["sync"]["tier"]
        batch_size = config["sync"]["batch_size"]
        lookback_hours = config["sync"]["lookback_buffer_hours"]
        dv_config = config["dataverse"]

        if args.dry_run:
            print("  [DRY RUN MODE - No changes will be made]")
            print()

        print(f"  Config: {args.config}")
        print(f"  Tier: {tier}")
        print(f"  Batch size: {batch_size}")
        print(f"  Lookback buffer: {lookback_hours}h")
        print()

        # 2. Initialize Dataverse client
        client_secret = os.environ.get("DATAVERSE_CLIENT_SECRET", "")
        if not client_secret and not args.dry_run:
            raise ValueError(
                "DATAVERSE_CLIENT_SECRET environment variable is required. "
                "Set it before running the sync."
            )

        dv_client = DataverseClient(
            tenant_id=dv_config["tenant_id"],
            environment_url=dv_config["environment_url"],
            client_id=dv_config["client_id"],
            client_secret=client_secret or "dry-run-placeholder",
            dry_run=args.dry_run,
        )

        # 3. Get instrumentation key
        if not args.dry_run:
            ikey = get_instrumentation_key(config)
        else:
            ikey = "00000000-0000-0000-0000-000000000000"

        # 4. Read watermark
        watermark = get_watermark(dv_client, dv_config["environment_url"], tier)

        # 5. Update watermark to InProgress
        update_watermark(
            dv_client,
            dv_config["environment_url"],
            tier,
            sync_start,
            0,
            WATERMARK_STATUS_IN_PROGRESS,
        )

        # 6. Fetch agent classifications
        agent_classifications = get_agent_classifications(dv_client)

        # 7. Fetch sessions
        sessions = fetch_sessions(dv_client, watermark, lookback_hours)

        if not sessions:
            logger.info("No new sessions to sync")
            update_watermark(
                dv_client,
                dv_config["environment_url"],
                tier,
                sync_start,
                0,
                WATERMARK_STATUS_SUCCESS,
            )
            print_sync_summary(0, 0, 0, 0, 0.0)
            sys.exit(0)

        # 8. Correlate knowledge sources
        ks_map = correlate_knowledge_sources(dv_client, sessions)

        # 9. Resolve governance zone
        zone = resolve_zone(dv_config["environment_url"], config.get("zone_mapping", {}))
        logger.info("Governance zone: %s", zone)

        # 10. Transform sessions to events
        events = []
        for session in sessions:
            event = transform_session(
                session, agent_classifications, ks_map, zone, tier
            )
            if event:
                events.append(event)

        logger.info("Transformed %d/%d sessions to events", len(events), len(sessions))

        # 11. Send to App Insights
        sent, failed = send_to_app_insights(events, ikey, batch_size, args.dry_run)

        # 12. Update watermark
        if failed == 0:
            update_watermark(
                dv_client,
                dv_config["environment_url"],
                tier,
                sync_start,
                sent,
                WATERMARK_STATUS_SUCCESS,
            )
        elif sent > 0:
            update_watermark(
                dv_client,
                dv_config["environment_url"],
                tier,
                sync_start,
                sent,
                WATERMARK_STATUS_WARNING,
                error_message=f"Partial sync: {failed} events failed to send",
            )
        else:
            update_watermark(
                dv_client,
                dv_config["environment_url"],
                tier,
                sync_start,
                0,
                WATERMARK_STATUS_FAILED,
                error_message=f"All {failed} events failed to send",
            )

        # 13. Print summary
        duration = (datetime.now(timezone.utc) - sync_start).total_seconds()
        print_sync_summary(len(sessions), len(events), sent, failed, duration)

        # Exit codes
        if failed > 0 and sent > 0:
            sys.exit(2)  # Partial sync
        elif failed > 0:
            sys.exit(1)  # Full failure
        sys.exit(0)

    except FileNotFoundError as e:
        logger.error("Config error: %s", e)
        sys.exit(1)
    except ValueError as e:
        logger.error("Configuration error: %s", e)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\nSync cancelled by user.")
        sys.exit(130)
    except Exception as e:
        logger.error("Unexpected error: %s", e)
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
