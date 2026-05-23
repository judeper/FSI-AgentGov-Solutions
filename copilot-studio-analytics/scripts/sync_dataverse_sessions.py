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

    # Tier 2 sync (planned -- currently sets syncTier label only)
    python sync_dataverse_sessions.py --config config/config.yml --tier 2

    # Verbose output for debugging
    python sync_dataverse_sessions.py --config config/config.yml --verbose

Sync Pipeline:
    1. Read watermark (last successful sync timestamp)
    2. Fetch msdyn_botsession records since watermark - lookback buffer
    3. Classify agents as Conversational or Autonomous via botcomponent
    4. Correlate knowledge sources (Tier 1: topic name heuristic)
    5. Transform sessions to CopilotSessionOutcome custom events
    6. Send batches to Application Insights
    7. Update watermark to last session timestamp on success

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
from pathlib import Path
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
RECENT_SESSION_STATE_FILE = "sync_dataverse_sessions.state.json"
RECENT_SESSION_STATE_VERSION = 1


def format_utc_datetime(value: datetime) -> str:
    """Format a timezone-aware datetime as an ISO 8601 UTC string."""
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_iso_datetime(value: Any) -> Optional[datetime]:
    """Parse an ISO 8601 timestamp into an aware UTC datetime."""
    if not value:
        return None

    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def get_session_created_timestamp(session: dict[str, Any]) -> Optional[datetime]:
    """Return the session creation timestamp used by the Dataverse lookback filter."""
    return parse_iso_datetime(session.get("msdyn_sessioncreatedon"))


def get_session_effective_timestamp(session: dict[str, Any]) -> Optional[datetime]:
    """Return the session timestamp used for watermark advancement."""
    return parse_iso_datetime(session.get("msdyn_sessionclosedon")) or get_session_created_timestamp(session)


def get_latest_session_timestamp(sessions: list[dict[str, Any]], fallback: datetime) -> datetime:
    """Return the latest created/closed timestamp across the fetched session set."""
    timestamps = [
        timestamp
        for session in sessions
        if (timestamp := get_session_effective_timestamp(session)) is not None
    ]
    return max(timestamps, default=fallback)


def get_recent_session_state_path() -> Path:
    """Return the on-disk state path used to suppress lookback replays."""
    return Path(__file__).resolve().parent.parent / "output" / RECENT_SESSION_STATE_FILE


def get_recent_session_scope_key(environment_url: str, tier: int) -> str:
    """Return the per-environment/per-tier key used inside the dedup state file."""
    return f"{environment_url}|tier:{tier}"


def load_recent_session_state(state_path: Path) -> dict[str, Any]:
    """Load recent-session dedup state from disk, tolerating missing/corrupt files."""
    default_state = {"version": RECENT_SESSION_STATE_VERSION, "scopes": {}}

    if not state_path.exists():
        return default_state

    try:
        with state_path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        logger.warning("Could not read recent-session state from %s: %s", state_path, exc)
        return default_state

    if not isinstance(data, dict):
        logger.warning("Ignoring unexpected recent-session state shape in %s", state_path)
        return default_state

    scopes = data.get("scopes")
    if data.get("version") != RECENT_SESSION_STATE_VERSION or not isinstance(scopes, dict):
        logger.warning("Ignoring unexpected recent-session state shape in %s", state_path)
        return default_state

    return {"version": RECENT_SESSION_STATE_VERSION, "scopes": scopes}


def save_recent_session_state(state_path: Path, state: dict[str, Any]) -> None:
    """Persist recent-session dedup state atomically."""
    state_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = state_path.with_suffix(state_path.suffix + ".tmp")

    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
        handle.write("\n")

    temp_path.replace(state_path)


def prune_recent_session_index(
    session_index: dict[str, dict[str, str]],
    cutoff: datetime,
) -> dict[str, dict[str, str]]:
    """Keep only session IDs that can still reappear inside the lookback window."""
    pruned: dict[str, dict[str, str]] = {}

    for session_id, metadata in session_index.items():
        if not isinstance(metadata, dict):
            continue

        session_timestamp = parse_iso_datetime(metadata.get("sessionCreatedOn")) or parse_iso_datetime(
            metadata.get("recordedAt")
        )
        if session_timestamp is None or session_timestamp >= cutoff:
            pruned[session_id] = metadata

    return pruned


def get_recent_emitted_session_ids(
    state_path: Path,
    environment_url: str,
    tier: int,
    lookback_hours: int,
    watermark: Optional[datetime],
) -> set[str]:
    """Return the session IDs emitted in the current overlap window."""
    if watermark is None:
        return set()

    state = load_recent_session_state(state_path)
    scope = state["scopes"].get(get_recent_session_scope_key(environment_url, tier), {})
    session_index = scope.get("sessions", {}) if isinstance(scope, dict) else {}
    if not isinstance(session_index, dict):
        return set()

    cutoff = watermark - timedelta(hours=lookback_hours)
    return set(prune_recent_session_index(session_index, cutoff).keys())


def partition_sessions_for_emit(
    sessions: list[dict[str, Any]],
    previously_emitted_session_ids: set[str],
) -> tuple[list[dict[str, Any]], int]:
    """Filter out sessions that were already emitted inside the overlapping lookback window."""
    pending: list[dict[str, Any]] = []
    seen_session_ids = set(previously_emitted_session_ids)
    skipped = 0

    for session in sessions:
        session_id = session.get("msdyn_botsessionid", "")
        if session_id and session_id in seen_session_ids:
            skipped += 1
            continue

        if session_id:
            seen_session_ids.add(session_id)
        pending.append(session)

    return pending, skipped


def build_recent_session_index(
    session_index: dict[str, dict[str, str]],
    sent_events: list[dict[str, Any]],
    lookback_hours: int,
    watermark: datetime,
    recorded_at: datetime,
) -> dict[str, dict[str, str]]:
    """Merge sent events into the bounded recent-session dedup index."""
    next_index = dict(session_index)

    for event in sent_events:
        custom_dimensions = event.get("customDimensions", {})
        if not isinstance(custom_dimensions, dict):
            continue

        session_id = custom_dimensions.get("sessionId", "")
        if not session_id:
            continue

        session_created_on = custom_dimensions.get("sessionCreatedOn", "")
        recorded_timestamp = parse_iso_datetime(session_created_on) or parse_iso_datetime(
            event.get("timestamp")
        ) or recorded_at
        next_index[session_id] = {
            "sessionCreatedOn": format_utc_datetime(recorded_timestamp),
            "recordedAt": format_utc_datetime(recorded_at),
        }

    cutoff = watermark - timedelta(hours=lookback_hours)
    return prune_recent_session_index(next_index, cutoff)


def record_sent_events(
    state_path: Path,
    environment_url: str,
    tier: int,
    sent_events: list[dict[str, Any]],
    lookback_hours: int,
    watermark: datetime,
    recorded_at: datetime,
) -> None:
    """Persist recently emitted session IDs so overlap windows stay idempotent across runs."""
    state = load_recent_session_state(state_path)
    scope_key = get_recent_session_scope_key(environment_url, tier)
    scope = state["scopes"].get(scope_key, {})
    session_index = scope.get("sessions", {}) if isinstance(scope, dict) else {}
    if not isinstance(session_index, dict):
        session_index = {}

    state["scopes"][scope_key] = {
        "updatedAt": format_utc_datetime(recorded_at),
        "watermark": format_utc_datetime(watermark),
        "sessions": build_recent_session_index(
            session_index,
            sent_events,
            lookback_hours,
            watermark,
            recorded_at,
        ),
    }
    save_recent_session_state(state_path, state)


def load_config(config_path: str, auth_mode_override: Optional[str] = None) -> dict[str, Any]:
    """
    Load and validate YAML configuration.

    Args:
        config_path: Path to YAML config file
        auth_mode_override: Optional Dataverse auth mode from CLI

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
    dv_auth_mode = (
        auth_mode_override
        or os.environ.get("DATAVERSE_AUTH_MODE")
        or dv_config.get("auth_mode")
        or ("client-secret" if os.environ.get("DATAVERSE_CLIENT_SECRET") else "managed-identity")
    )
    config["dataverse"]["auth_mode"] = dv_auth_mode

    dv_required = ["environment_url"]
    if dv_auth_mode in {"client-secret", "workload-identity", "certificate", "interactive"}:
        dv_required.extend(["tenant_id", "client_id"])
    elif dv_auth_mode != "managed-identity":
        raise ValueError(f"Unsupported dataverse.auth_mode: {dv_auth_mode}")

    dv_missing = [f for f in dv_required if not dv_config.get(f)]
    if dv_missing:
        raise ValueError(f"Missing required dataverse fields for {dv_auth_mode}: {', '.join(dv_missing)}")

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

    Autonomous agents have at least one botcomponent with componenttype=17
    (External Trigger / Event-Driven; the integer optionset value, NOT the
    string `componenttypename`). All others are Conversational.

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

    # Validate environment_url to prevent OData filter injection.
    # Accept commercial cloud (.dynamics.com), US Gov (.dynamics.us /
    # .crm.dynamics.us), Germany (.microsoftdynamics.de), and China
    # (.crm.dynamics.cn) sovereign cloud hosts.
    import re
    if not re.match(
        r'^https://[a-zA-Z0-9._-]+\.(dynamics\.com|dynamics\.us|microsoftdynamics\.de|crm\.dynamics\.cn)$',
        environment_url,
    ):
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


# Maximum duration (in minutes) an InProgress watermark can be held before
# it is considered stale and a new sync is allowed to proceed.
STALE_LOCK_TIMEOUT_MINUTES = 30


def check_sync_lock(
    client: DataverseClient,
    environment_url: str,
    tier: int,
) -> bool:
    """
    Check whether another sync is already in progress for this environment/tier.

    Returns True if the lock is held (caller should abort), False if safe to proceed.
    Stale locks older than STALE_LOCK_TIMEOUT_MINUTES are ignored with a warning.
    """
    tier_value = WATERMARK_TIER_1 if tier == 1 else WATERMARK_TIER_2

    records = client.query(
        WATERMARK_TABLE,
        select=["fsi_lastsynctimestamp", "fsi_syncstatus"],
        filter_expr=(
            f"fsi_environmenturl eq '{environment_url}' "
            f"and fsi_synctier eq {tier_value} "
            f"and fsi_syncstatus eq {WATERMARK_STATUS_IN_PROGRESS}"
        ),
        orderby="fsi_lastsynctimestamp desc",
        top=1,
    )

    if not records:
        return False  # No lock held

    # Check if the lock is stale
    lock_ts_str = records[0].get("fsi_lastsynctimestamp", "")
    if lock_ts_str:
        try:
            lock_ts = datetime.fromisoformat(lock_ts_str.replace("Z", "+00:00"))
            age_minutes = (datetime.now(timezone.utc) - lock_ts).total_seconds() / 60
            if age_minutes > STALE_LOCK_TIMEOUT_MINUTES:
                logger.warning(
                    "Found stale InProgress watermark from %s (%.0f min ago) — proceeding",
                    lock_ts.isoformat(),
                    age_minutes,
                )
                return False
        except (ValueError, TypeError):
            pass

    logger.error("Another sync is already in progress for this environment/tier")
    return True


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
    Upsert the sync watermark record for (environment_url, tier).

    Looks up the existing watermark row by (environment_url, tier) and
    PATCHes it; if none exists, INSERTs the first one. Prevents the
    table from growing unboundedly across runs. (Bug: prior versions
    always called create_record on every sync — every InProgress claim,
    success, and failure inserted a fresh row.)
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

    # Look up existing row for this (env, tier).
    existing = client.query(
        WATERMARK_TABLE,
        select=["fsi_csasyncwatermarkid"],
        filter_expr=(
            f"fsi_environmenturl eq '{environment_url}' "
            f"and fsi_synctier eq {tier_value}"
        ),
        orderby="fsi_lastsynctimestamp desc",
        top=1,
    )

    if existing:
        record_id = existing[0].get("fsi_csasyncwatermarkid")
        if record_id:
            client.update_record(WATERMARK_TABLE, record_id, data)
            logger.info(
                "Watermark patched: %s (records: %d, status: %d)",
                timestamp.isoformat(),
                records_synced,
                status,
            )
            return

    # First sync for this (env, tier) — insert the row.
    client.create_record(WATERMARK_TABLE, data)
    logger.info(
        "Watermark created (first sync): %s (records: %d, status: %d)",
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
    Tier 1 (current): Best-effort heuristic. Marks a session as
    "knowledge-source-using" when its `msdyn_topicname` contains the
    substring `generativeanswers` or `knowledge` (case-insensitive).

    LIMITATIONS:
      - Will UNDER-COUNT any agent whose KS-grounded topic uses a custom
        display name (e.g., "PolicyLookup", "AccountFAQ").
      - Will OVER-COUNT topics that happen to contain those substrings
        without actually invoking a knowledge source.
      - Does NOT correlate with App Insights `GenerativeAnswers` events,
        despite older docs saying so. That correlation is planned for
        Tier 2 along with `conversationtranscript` parsing.

    Operators should inspect the distribution of `topicName` in their
    environment before relying on aggregate KS metrics; if topic names
    are heavily customized, edit the keyword list below or wait for Tier 2.

    Args:
        client: DataverseClient instance (currently unused — reserved for
            Tier 2 botcomponent / conversationtranscript queries)
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


def classify_usage_type(channel_id: str) -> str:
    """
    Classify usage type from the session channel identifier.

    Args:
        channel_id: The msdyn_channelid value from the session record

    Returns:
        "Internal" or "External"
    """
    if not channel_id:
        return "Internal"

    channel_lower = channel_id.lower()

    external_keywords = ["webchat", "directline", "website"]
    if any(kw in channel_lower for kw in external_keywords):
        return "External"

    internal_keywords = ["msteams", "teams"]
    if any(kw in channel_lower for kw in internal_keywords):
        return "Internal"

    return "Internal"


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

    # Derive usage type from channel
    channel_id = session.get("msdyn_channelid", "") or ""
    usage_type = classify_usage_type(channel_id)

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
        "channelId": channel_id,
        "usageType": usage_type,
        "Zone": zone,
        "syncSource": "DataverseSync",
        "syncTier": f"Tier{tier}",
        # True session times — needed by KQL/workbooks because TelemetryClient
        # stamps Application Insights' `timestamp` column with sync-execution
        # time, NOT the session time. Always re-bin trends on these in KQL:
        #   extend SessionTime = todatetime(customDimensions['sessionClosedOn'])
        "sessionCreatedOn": created_on or "",
        "sessionClosedOn": closed_on or "",
    }

    # Use session end time as event timestamp (preferred for time-series alignment),
    # falling back to start time if session hasn't closed yet.
    # NOTE: opencensus / applicationinsights TelemetryClient.track_event ignores
    # this field and stamps send-time instead. Future v2.x will move to
    # azure-monitor-opentelemetry which supports custom timestamps.
    event_timestamp = closed_on if closed_on else created_on

    return {
        "name": "CopilotSessionOutcome",
        "timestamp": event_timestamp,
        "customDimensions": custom_dimensions,
    }


def send_to_app_insights(
    events: list[dict[str, Any]],
    instrumentation_key: str,
    batch_size: int,
    dry_run: bool = False,
) -> tuple[int, int, list[dict[str, Any]]]:
    """
    Send CopilotSessionOutcome events to Application Insights in batches.

    Args:
        events: List of transformed event dicts
        instrumentation_key: App Insights instrumentation key
        batch_size: Number of events per batch
        dry_run: If True, log events without sending

    Returns:
        Tuple of (sent_count, failed_count, sent_events)
    """
    if not events:
        logger.info("No events to send")
        return (0, 0, [])

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
        return (len(events), 0, list(events))

    tc = TelemetryClient(instrumentation_key)

    sent = 0
    failed = 0
    sent_events: list[dict[str, Any]] = []

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
            sent_events.extend(batch)
            logger.info("Batch %d/%d sent successfully", batch_num, total_batches)
        except Exception as e:
            failed += len(batch)
            logger.error("Batch %d/%d failed: %s", batch_num, total_batches, e)

    logger.info("App Insights send complete: %d sent, %d failed", sent, failed)
    return (sent, failed, sent_events)


def get_app_insights_credential(config: dict[str, Any]) -> str:
    """
    Retrieve the App Insights credential to pass to TelemetryClient.

    Resolution order (Microsoft now recommends connection strings over
    legacy instrumentation keys; this function supports both):
      1. APPLICATIONINSIGHTS_CONNECTION_STRING env var (preferred)
      2. APPINSIGHTS_INSTRUMENTATIONKEY env var (legacy, still accepted)
      3. Azure management API: prefer component.connection_string, fall
         back to component.instrumentation_key

    Returns either a connection string (preferred) or a raw ikey GUID.
    Both are accepted by opencensus-ext-azure / azure-monitor-opentelemetry.

    Raises:
        ValueError: If no credential can be resolved.
    """
    conn_str = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING", "")
    if conn_str:
        return conn_str

    ikey = os.environ.get("APPINSIGHTS_INSTRUMENTATIONKEY", "")
    if ikey:
        logger.warning(
            "Using legacy APPINSIGHTS_INSTRUMENTATIONKEY. Microsoft recommends "
            "APPLICATIONINSIGHTS_CONNECTION_STRING — see "
            "https://learn.microsoft.com/azure/azure-monitor/app/connection-strings"
        )
        return ikey

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
        # Prefer connection_string when SDK exposes it (recent versions do).
        cs = getattr(component, "connection_string", None)
        if cs:
            return cs
        return component.instrumentation_key
    except Exception as e:
        raise ValueError(
            "Cannot resolve Application Insights credential. Set "
            "APPLICATIONINSIGHTS_CONNECTION_STRING (preferred) or "
            f"APPINSIGHTS_INSTRUMENTATIONKEY env var, or provide Azure credentials: {e}"
        )


# Backwards-compatible alias; prefer get_app_insights_credential going forward.
def get_instrumentation_key(config: dict[str, Any]) -> str:
    """Deprecated: use get_app_insights_credential. Retained for callers."""
    return get_app_insights_credential(config)


def print_banner() -> None:
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


def main() -> None:
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

    # Tier 2 sync (planned -- currently sets syncTier label only)
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
        help=(
            "Sync tier override (1=sessions only [implemented], "
            "2=planned for future release — currently behaves the same as "
            "Tier 1 but sets syncTier label to 'Tier2')"
        ),
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
    parser.add_argument(
        "--auth-mode",
        choices=["managed-identity", "workload-identity", "certificate", "interactive", "client-secret"],
        default=os.environ.get("DATAVERSE_AUTH_MODE"),
        help=(
            "Dataverse authentication mode. Defaults to managed identity unless "
            "DATAVERSE_CLIENT_SECRET is set, which selects legacy client-secret auth."
        ),
    )
    parser.add_argument(
        "--certificate-path",
        default=os.environ.get("DATAVERSE_CERTIFICATE_PATH"),
        help="Path to certificate for --auth-mode certificate",
    )
    parser.add_argument(
        "--certificate-password",
        default=os.environ.get("DATAVERSE_CERTIFICATE_PASSWORD"),
        help="Certificate password for --auth-mode certificate",
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
        config = load_config(args.config, auth_mode_override=args.auth_mode)

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
        auth_mode = dv_config.get("auth_mode") or args.auth_mode or "managed-identity"
        client_secret = os.environ.get("DATAVERSE_CLIENT_SECRET", "")
        if auth_mode == "client-secret":
            # legacy: dev-only — replace with managed identity in production
            if not client_secret and not args.dry_run:
                raise ValueError(
                    "DATAVERSE_CLIENT_SECRET environment variable is required for legacy client-secret auth. "
                    "Use --auth-mode managed-identity, workload-identity, or certificate in production."
                )

        dataverse_client_id = dv_config.get("client_id")
        if auth_mode == "managed-identity":
            dataverse_client_id = dv_config.get("managed_identity_client_id")

        dv_client = DataverseClient(
            tenant_id=dv_config.get("tenant_id"),
            environment_url=dv_config["environment_url"],
            client_id=dataverse_client_id,
            client_secret=(client_secret or "dry-run-placeholder") if auth_mode == "client-secret" else None,
            dry_run=args.dry_run,
            auth_mode=auth_mode,
            certificate_path=args.certificate_path or dv_config.get("certificate_path"),
            certificate_password=args.certificate_password,
        )

        # 3. Get instrumentation key
        if not args.dry_run:
            ikey = get_instrumentation_key(config)
        else:
            ikey = "00000000-0000-0000-0000-000000000000"

        # 4. Check for concurrent sync (advisory lock)
        if not args.dry_run and check_sync_lock(dv_client, dv_config["environment_url"], tier):
            logger.error("Aborting: another sync is in progress. Retry later.")
            sys.exit(1)

        # 5. Read watermark and the recent-session dedup ledger
        watermark = get_watermark(dv_client, dv_config["environment_url"], tier)
        recent_session_state_path = get_recent_session_state_path()
        recent_emitted_session_ids = get_recent_emitted_session_ids(
            recent_session_state_path,
            dv_config["environment_url"],
            tier,
            lookback_hours,
            watermark,
        )
        if recent_emitted_session_ids:
            logger.info(
                "Loaded %d recently emitted session IDs from %s",
                len(recent_emitted_session_ids),
                recent_session_state_path,
            )

        # 6. Update watermark to InProgress (advisory lock)
        update_watermark(
            dv_client,
            dv_config["environment_url"],
            tier,
            sync_start,
            0,
            WATERMARK_STATUS_IN_PROGRESS,
        )

        try:
            # 7. Fetch agent classifications
            agent_classifications = get_agent_classifications(dv_client)

            # 8. Fetch sessions
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

            last_session_timestamp = get_latest_session_timestamp(sessions, watermark or sync_start)

            # 9. Drop sessions that were already emitted by the previous overlapping run(s)
            pending_sessions, skipped_replays = partition_sessions_for_emit(
                sessions,
                recent_emitted_session_ids,
            )
            if skipped_replays:
                logger.info(
                    "Skipping %d previously emitted session(s) from the lookback overlap",
                    skipped_replays,
                )

            if not pending_sessions:
                logger.info("All fetched sessions were already emitted in the current lookback window")
                update_watermark(
                    dv_client,
                    dv_config["environment_url"],
                    tier,
                    last_session_timestamp,
                    0,
                    WATERMARK_STATUS_SUCCESS,
                )
                duration = (datetime.now(timezone.utc) - sync_start).total_seconds()
                print_sync_summary(len(sessions), 0, 0, 0, duration)
                sys.exit(0)

            # 10. Correlate knowledge sources
            ks_map = correlate_knowledge_sources(dv_client, pending_sessions)

            # 11. Resolve governance zone
            zone = resolve_zone(dv_config["environment_url"], config.get("zone_mapping", {}))
            logger.info("Governance zone: %s", zone)

            # 12. Transform sessions to events
            events = []
            for session in pending_sessions:
                event = transform_session(
                    session, agent_classifications, ks_map, zone, tier
                )
                if event:
                    events.append(event)

            logger.info(
                "Transformed %d/%d sessions to events after dedup",
                len(events),
                len(pending_sessions),
            )

            # 13. Send to App Insights
            sent, failed, sent_events = send_to_app_insights(events, ikey, batch_size, args.dry_run)

            # 14. Persist the recent-session dedup ledger after successful emits
            if sent_events and not args.dry_run:
                record_sent_events(
                    recent_session_state_path,
                    dv_config["environment_url"],
                    tier,
                    sent_events,
                    lookback_hours,
                    last_session_timestamp,
                    sync_start,
                )

            # 15. Update watermark to last session timestamp (not sync_start)
            if failed == 0:
                update_watermark(
                    dv_client,
                    dv_config["environment_url"],
                    tier,
                    last_session_timestamp,
                    sent,
                    WATERMARK_STATUS_SUCCESS,
                )
            elif sent > 0:
                update_watermark(
                    dv_client,
                    dv_config["environment_url"],
                    tier,
                    last_session_timestamp,
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

            # 16. Print summary
            duration = (datetime.now(timezone.utc) - sync_start).total_seconds()
            print_sync_summary(len(sessions), len(events), sent, failed, duration)

            # Exit codes
            if failed > 0 and sent > 0:
                sys.exit(2)  # Partial sync
            elif failed > 0:
                sys.exit(1)  # Full failure
            sys.exit(0)

        except Exception:
            # Release the InProgress watermark lock so subsequent runs aren't blocked
            try:
                update_watermark(
                    dv_client,
                    dv_config["environment_url"],
                    tier,
                    sync_start,
                    0,
                    WATERMARK_STATUS_FAILED,
                    error_message="Sync aborted due to unhandled exception",
                )
            except Exception:
                pass  # Best-effort cleanup; don't mask the original error
            raise

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
