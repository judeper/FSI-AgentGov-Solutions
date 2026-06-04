from __future__ import annotations

import importlib.util
import sys
import types
from datetime import datetime, timedelta, timezone
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "sync_dataverse_sessions.py"


def load_sync_module():
    """Import sync_dataverse_sessions.py with stubbed runtime dependencies."""
    fake_dataverse = types.ModuleType("dataverse_client")

    class DataverseClient:  # pragma: no cover - simple import stub
        pass

    fake_dataverse.DataverseClient = DataverseClient
    sys.modules["dataverse_client"] = fake_dataverse

    fake_app_insights = types.ModuleType("applicationinsights")

    class TelemetryClient:  # pragma: no cover - simple import stub
        def __init__(self, *args, **kwargs):
            pass

        def track_event(self, *args, **kwargs):
            pass

        def flush(self):
            pass

    fake_app_insights.TelemetryClient = TelemetryClient
    sys.modules["applicationinsights"] = fake_app_insights

    spec = importlib.util.spec_from_file_location("sync_dataverse_sessions_under_test", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


sync_mod = load_sync_module()


def iso(value: str) -> datetime:
    """Parse a UTC ISO 8601 string into an aware datetime."""
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def make_session(session_id: str, created_on: str, closed_on: str | None = None) -> dict[str, str]:
    """Build a minimal Dataverse session fixture."""
    session = {
        "msdyn_botsessionid": session_id,
        "msdyn_startedon": created_on,
    }
    if closed_on is not None:
        session["msdyn_endedon"] = closed_on
    return session


def make_event(session_id: str, created_on: str, closed_on: str | None = None) -> dict[str, object]:
    """Build a minimal emitted-event fixture."""
    return {
        "name": "CopilotSessionOutcome",
        "timestamp": closed_on or created_on,
        "customDimensions": {
            "sessionId": session_id,
            "sessionCreatedOn": created_on,
            "sessionClosedOn": closed_on or "",
        },
    }


def test_overlapping_lookback_only_emits_new_session_ids():
    watermark = iso("2026-05-17T12:00:00Z")
    recorded_at = iso("2026-05-17T12:05:00Z")
    recent_index = sync_mod.build_recent_session_index(
        {},
        [
            make_event("A", "2026-05-17T10:05:00Z", "2026-05-17T10:15:00Z"),
            make_event("B", "2026-05-17T10:25:00Z", "2026-05-17T10:35:00Z"),
            make_event("C", "2026-05-17T10:45:00Z", "2026-05-17T10:55:00Z"),
        ],
        lookback_hours=2,
        watermark=watermark,
        recorded_at=recorded_at,
    )
    recent_ids = set(
        sync_mod.prune_recent_session_index(recent_index, watermark - timedelta(hours=2)).keys()
    )

    pending, skipped = sync_mod.partition_sessions_for_emit(
        [
            make_session("A", "2026-05-17T10:05:00Z", "2026-05-17T10:15:00Z"),
            make_session("B", "2026-05-17T10:25:00Z", "2026-05-17T10:35:00Z"),
            make_session("C", "2026-05-17T10:45:00Z", "2026-05-17T10:55:00Z"),
            make_session("D", "2026-05-17T11:05:00Z", "2026-05-17T11:15:00Z"),
            make_session("E", "2026-05-17T11:25:00Z", "2026-05-17T11:35:00Z"),
        ],
        recent_ids,
    )

    assert [session["msdyn_botsessionid"] for session in pending] == ["D", "E"]
    assert skipped == 3


def test_late_arriving_session_within_overlap_still_emits_if_unseen():
    watermark = iso("2026-05-17T12:00:00Z")
    recorded_at = iso("2026-05-17T12:05:00Z")
    recent_index = sync_mod.build_recent_session_index(
        {},
        [
            make_event("A", "2026-05-17T10:05:00Z", "2026-05-17T10:15:00Z"),
            make_event("B", "2026-05-17T10:25:00Z", "2026-05-17T10:35:00Z"),
            make_event("C", "2026-05-17T10:45:00Z", "2026-05-17T10:55:00Z"),
        ],
        lookback_hours=2,
        watermark=watermark,
        recorded_at=recorded_at,
    )
    recent_ids = set(
        sync_mod.prune_recent_session_index(recent_index, watermark - timedelta(hours=2)).keys()
    )

    pending, skipped = sync_mod.partition_sessions_for_emit(
        [
            make_session("A", "2026-05-17T10:05:00Z", "2026-05-17T10:15:00Z"),
            make_session("B", "2026-05-17T10:25:00Z", "2026-05-17T10:35:00Z"),
            make_session("late-D", "2026-05-17T11:20:00Z", "2026-05-17T11:22:00Z"),
            make_session("E", "2026-05-17T12:10:00Z", "2026-05-17T12:15:00Z"),
        ],
        recent_ids,
    )

    assert [session["msdyn_botsessionid"] for session in pending] == ["late-D", "E"]
    assert skipped == 2


def test_latest_session_timestamp_uses_max_effective_time():
    fallback = iso("2026-05-17T08:00:00Z")
    latest = sync_mod.get_latest_session_timestamp(
        [
            make_session("A", "2026-05-17T09:00:00Z", "2026-05-17T15:00:00Z"),
            make_session("B", "2026-05-17T10:00:00Z", "2026-05-17T12:00:00Z"),
        ],
        fallback,
    )

    assert latest == iso("2026-05-17T15:00:00Z")
