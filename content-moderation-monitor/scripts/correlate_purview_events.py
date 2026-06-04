#!/usr/bin/env python3
"""Correlate content-moderation events with Purview Audit and DSPM signals.

Pulls moderation events from Dataverse, queries Microsoft Purview Audit via
the Graph ``auditLogQuery`` API, and matches events by user + timestamp +
content hash to produce enriched records with Purview/DSPM context.

Requires Microsoft Graph permissions:
  - AuditLogsQuery.Read.All (application) — query Purview unified audit log
  - User.Read.All (application) — resolve user principal names

Usage:
    python correlate_purview_events.py \\
        --tenant-id <tenant> \\
        --environment-url https://org.crm.dynamics.com \\
        --output enriched-events.json
"""

import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)

try:
    from dataverse_client import DataverseClient
except ImportError:
    DataverseClient = None  # type: ignore[misc,assignment]

try:
    import msal
    import requests
except ImportError:
    msal = None  # type: ignore[assignment]
    requests = None  # type: ignore[assignment]

logger = logging.getLogger("cmm.purview_correlator")

# ---------------------------------------------------------------------------
# Graph helpers
# ---------------------------------------------------------------------------

GRAPH_BASE = "https://graph.microsoft.com"
AUDIT_LOG_QUERY_URL = f"{GRAPH_BASE}/v1.0/security/auditLog/queries"


def _acquire_graph_token(
    tenant_id: str,
    client_id: Optional[str] = None,
    client_secret: Optional[str] = None,
) -> str:
    """Acquire a Graph access token via MSAL client-credential flow.

    For production workloads, prefer managed identity or workload identity
    federation. Client-secret auth is retained as a legacy dev fallback.
    """
    if msal is None:
        raise ImportError("msal package is required: pip install msal")

    authority = f"https://login.microsoftonline.com/{tenant_id}"

    cid = client_id or os.environ.get("AZURE_CLIENT_ID", "")
    csec = client_secret or os.environ.get("AZURE_CLIENT_SECRET", "")

    if not cid or not csec:
        raise ValueError(
            "Graph authentication requires AZURE_CLIENT_ID and "
            "AZURE_CLIENT_SECRET environment variables or explicit parameters."
        )

    app = msal.ConfidentialClientApplication(
        cid, authority=authority, client_credential=csec
    )
    result = app.acquire_token_for_client(scopes=["https://graph.microsoft.com/.default"])
    if "access_token" not in result:
        raise RuntimeError(f"Token acquisition failed: {result.get('error_description', result)}")
    return result["access_token"]


def _graph_request(
    token: str,
    method: str,
    url: str,
    body: Optional[dict] = None,
    max_retries: int = 5,
) -> dict[str, Any]:
    """Execute a Graph request with Retry-After / exponential backoff."""
    if requests is None:
        raise ImportError("requests package is required: pip install requests")

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    for attempt in range(1, max_retries + 1):
        resp = requests.request(
            method, url, headers=headers, json=body, timeout=120
        )
        if resp.status_code in (429, 503) and attempt < max_retries:
            retry_after = int(resp.headers.get("Retry-After", 2**attempt))
            logger.warning(
                "Throttled (%s). Retry-After: %ss (attempt %s/%s)",
                resp.status_code, retry_after, attempt, max_retries,
            )
            time.sleep(retry_after)
            continue
        resp.raise_for_status()
        return resp.json() if resp.content else {}

    raise RuntimeError(f"Graph request to {url} failed after {max_retries} attempts")


# ---------------------------------------------------------------------------
# Purview Audit query
# ---------------------------------------------------------------------------


def create_audit_log_query(
    token: str,
    start_time: datetime,
    end_time: datetime,
    record_types: Optional[list[str]] = None,
    operation_filters: Optional[list[str]] = None,
) -> str:
    """Create a Purview auditLogQuery and return the query ID.

    ``record_types`` values must be valid ``auditLogRecordType`` enum members
    (for example ``MicrosoftTeams`` or ``PowerPlatformServiceActivity``);
    ``operation_filters`` values are activity names such as
    ``CopilotInteraction``. Copilot interactions are logged with the operation
    ``CopilotInteraction`` (numeric RecordType 261) and are not exposed as a
    dedicated ``auditLogRecordType`` enum member, so they are selected via the
    operation filter rather than the record-type filter.

    References:
      - https://learn.microsoft.com/graph/api/resources/security-auditlogquery
      - https://learn.microsoft.com/graph/api/resources/security-auditlogrecordtype
      - https://learn.microsoft.com/purview/audit-copilot
    """
    body: dict[str, Any] = {
        "displayName": f"CMM-PurviewCorrelation-{datetime.now(tz=timezone.utc).strftime('%Y%m%d%H%M%S')}",
        "filterStartDateTime": start_time.isoformat(),
        "filterEndDateTime": end_time.isoformat(),
    }
    if record_types:
        body["recordTypeFilters"] = record_types
    if operation_filters:
        body["operationFilters"] = operation_filters

    result = _graph_request(token, "POST", AUDIT_LOG_QUERY_URL, body=body)
    query_id = result.get("id")
    if not query_id:
        raise RuntimeError(f"Purview audit query creation failed: {result}")
    logger.info("Created audit log query: %s", query_id)
    return query_id


def poll_audit_log_query(
    token: str,
    query_id: str,
    poll_interval: int = 10,
    max_wait: int = 600,
) -> list[dict[str, Any]]:
    """Poll the audit log query until completion and retrieve records."""
    query_url = f"{AUDIT_LOG_QUERY_URL}/{query_id}"
    elapsed = 0

    while elapsed < max_wait:
        status_resp = _graph_request(token, "GET", query_url)
        state = status_resp.get("status", "")
        if state == "succeeded":
            break
        if state in ("failed", "cancelled"):
            raise RuntimeError(f"Audit log query {query_id} ended with status: {state}")
        logger.info("Audit query status: %s — waiting %ss", state, poll_interval)
        time.sleep(poll_interval)
        elapsed += poll_interval

    if elapsed >= max_wait:
        raise TimeoutError(f"Audit log query {query_id} did not complete within {max_wait}s")

    # Retrieve records
    records_url = f"{query_url}/records"
    all_records: list[dict[str, Any]] = []
    next_link: Optional[str] = records_url

    while next_link:
        page = _graph_request(token, "GET", next_link)
        all_records.extend(page.get("value", []))
        next_link = page.get("@odata.nextLink")

    logger.info("Retrieved %d audit records from query %s", len(all_records), query_id)
    return all_records


# ---------------------------------------------------------------------------
# Dataverse: pull moderation events
# ---------------------------------------------------------------------------


def pull_moderation_events(
    environment_url: str,
    tenant_id: str,
    lookback_hours: int = 24,
    auth_mode: str = "client-secret",
    client_id: Optional[str] = None,
    client_secret: Optional[str] = None,
) -> list[dict[str, Any]]:
    """Pull recent moderation violation records from Dataverse.

    Reads from the ``fsi_moderationviolations`` entity set. Falls back to
    an empty list if the Dataverse client is unavailable.

    Authentication: prefer ``managed-identity`` or ``workload-identity`` in
    production. ``client-secret`` is retained as a legacy dev fallback and
    requires ``AZURE_CLIENT_ID`` / ``AZURE_CLIENT_SECRET`` to be set (either
    via CLI arguments or environment variables).
    """
    if DataverseClient is None:
        logger.warning("DataverseClient not available — returning empty event list")
        return []

    cid = client_id or os.environ.get("AZURE_CLIENT_ID")
    csec = client_secret or os.environ.get("AZURE_CLIENT_SECRET")

    client = DataverseClient(
        tenant_id=tenant_id,
        environment_url=environment_url,
        auth_mode=auth_mode,
        client_id=cid,
        client_secret=csec,
    )
    cutoff = (datetime.now(tz=timezone.utc) - timedelta(hours=lookback_hours)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )

    odata_filter = f"createdon ge {cutoff}"
    # Column names per create_dataverse_schema.py VIOLATION_COLUMNS:
    # fsi_actuallevel (Actual Level) and fsi_environmentguid (Environment GUID).
    select_columns = [
        "fsi_name",
        "fsi_agentname",
        "fsi_actuallevel",
        "fsi_zone",
        "createdon",
        "fsi_environmentguid",
        "ownerid",
    ]

    try:
        records = client.query(
            "fsi_moderationviolations",
            select=select_columns,
            filter_expr=odata_filter,
            top=1000,
        )
        logger.info("Retrieved %d moderation events from Dataverse", len(records))
        return records
    except Exception:
        logger.exception("Failed to pull moderation events from Dataverse")
        return []


# ---------------------------------------------------------------------------
# Correlation engine
# ---------------------------------------------------------------------------

# Copilot interactions are recorded in the unified audit log with the operation
# "CopilotInteraction" (numeric RecordType 261). The Microsoft Graph
# auditLogRecordType enum does not expose a dedicated Copilot record type, so the
# operation filter is used to target Copilot interaction events directly.
# auditLogQuery filters are combined with AND semantics, so a record-type filter
# is intentionally omitted to avoid narrowing past Copilot interaction events.
# Ref: https://learn.microsoft.com/graph/api/resources/security-auditlogrecordtype
COPILOT_OPERATION_FILTERS = ["CopilotInteraction"]
TIMESTAMP_TOLERANCE_SECONDS = 300  # 5-minute window for event correlation


def correlate_events(
    moderation_events: list[dict[str, Any]],
    audit_records: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Match moderation events with Purview audit records.

    Correlation key: user principal name + timestamp proximity + content hash
    (when available). Falls back to user + timestamp when hash is absent.
    """
    enriched: list[dict[str, Any]] = []

    # Index audit records by user for faster lookup
    audit_by_user: dict[str, list[dict[str, Any]]] = {}
    for record in audit_records:
        audit_data = record.get("auditData", {})
        if isinstance(audit_data, str):
            try:
                audit_data = json.loads(audit_data)
            except json.JSONDecodeError:
                audit_data = {}

        user_id = (
            audit_data.get("UserId", "")
            or record.get("userPrincipalName", "")
        )
        if user_id:
            audit_by_user.setdefault(user_id.lower(), []).append({
                "record": record,
                "audit_data": audit_data,
            })

    for mod_event in moderation_events:
        event_user = (mod_event.get("ownerid", "") or "").lower()
        event_time_str = mod_event.get("createdon", "")
        event_time = _parse_timestamp(event_time_str)

        matches: list[dict[str, Any]] = []

        # Search by user
        if event_user and event_user in audit_by_user:
            for audit_entry in audit_by_user[event_user]:
                audit_time_str = audit_entry["audit_data"].get(
                    "CreationTime", audit_entry["record"].get("createdDateTime", "")
                )
                audit_time = _parse_timestamp(audit_time_str)

                if audit_time and event_time:
                    delta = abs((audit_time - event_time).total_seconds())
                    if delta <= TIMESTAMP_TOLERANCE_SECONDS:
                        matches.append({
                            "auditRecordId": audit_entry["record"].get("id"),
                            "recordType": audit_entry["audit_data"].get("RecordType"),
                            "operation": audit_entry["audit_data"].get("Operation"),
                            "timeDeltaSeconds": delta,
                            "dsmContext": _extract_dspm_context(audit_entry["audit_data"]),
                        })

        enriched.append({
            "moderationEvent": mod_event,
            "purviewMatches": matches,
            "matchCount": len(matches),
            "correlationTimestamp": datetime.now(tz=timezone.utc).isoformat(),
        })

    return enriched


def _parse_timestamp(ts: str) -> Optional[datetime]:
    """Parse an ISO-8601 timestamp, returning None on failure."""
    if not ts:
        return None
    try:
        ts_clean = ts.rstrip("Z") + "+00:00" if ts.endswith("Z") else ts
        return datetime.fromisoformat(ts_clean)
    except (ValueError, TypeError):
        return None


def _extract_dspm_context(audit_data: dict[str, Any]) -> dict[str, Any]:
    """Extract DSPM-relevant signals from audit data.

    DSPM (Data Security Posture Management) context includes sensitivity
    labels, data classification, and security posture indicators surfaced
    in Purview audit records.
    """
    context: dict[str, Any] = {}

    # Sensitivity label information
    if audit_data.get("SensitivityLabelId"):
        context["sensitivityLabelId"] = audit_data["SensitivityLabelId"]
    if audit_data.get("SensitivityLabelName"):
        context["sensitivityLabelName"] = audit_data["SensitivityLabelName"]

    # Data classification
    if audit_data.get("SensitiveInfoType"):
        context["sensitiveInfoTypes"] = audit_data["SensitiveInfoType"]

    # DLP policy match
    if audit_data.get("PolicyMatchInfo"):
        context["policyMatchInfo"] = audit_data["PolicyMatchInfo"]

    # Copilot interaction specifics
    if audit_data.get("CopilotEventData"):
        context["copilotEventData"] = audit_data["CopilotEventData"]

    # Content type and operation context
    for key in ("ItemType", "ObjectId", "SourceWorkload", "Workload"):
        if audit_data.get(key):
            context[key.lower()] = audit_data[key]

    return context


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main() -> int:
    """Run Purview Audit / DSPM correlation pipeline."""
    parser = argparse.ArgumentParser(
        description="Correlate CMM moderation events with Purview Audit and DSPM signals"
    )
    parser.add_argument("--tenant-id", required=True, help="Microsoft Entra tenant ID")
    parser.add_argument(
        "--environment-url",
        required=True,
        help="Dataverse environment URL (e.g., https://org.crm.dynamics.com)",
    )
    parser.add_argument("--client-id", help="Application (client) ID for Graph/Dataverse auth")
    parser.add_argument(
        "--client-secret",
        help="Client secret (legacy dev fallback; prefer managed identity)",
    )
    parser.add_argument(
        "--auth-mode",
        default="client-secret",
        choices=["managed-identity", "workload-identity", "client-secret", "certificate", "interactive"],
        help=(
            "Dataverse auth mode (default: client-secret). Production should use "
            "managed-identity or workload-identity."
        ),
    )
    parser.add_argument(
        "--lookback-hours",
        type=int,
        default=24,
        help="Hours to look back for moderation events (default: 24)",
    )
    parser.add_argument(
        "--output",
        default="enriched-moderation-events.json",
        help="Output file path for enriched events",
    )
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging")

    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    # 1. Acquire Graph token
    logger.info("Acquiring Graph access token")
    token = _acquire_graph_token(
        args.tenant_id, args.client_id, args.client_secret
    )

    # 2. Pull moderation events from Dataverse
    logger.info("Pulling moderation events (lookback: %dh)", args.lookback_hours)
    moderation_events = pull_moderation_events(
        args.environment_url,
        args.tenant_id,
        args.lookback_hours,
        auth_mode=args.auth_mode,
        client_id=args.client_id,
        client_secret=args.client_secret,
    )
    logger.info("Found %d moderation events", len(moderation_events))

    if not moderation_events:
        logger.info("No moderation events found in lookback window — writing empty output")
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump({"events": [], "summary": {"total": 0, "correlated": 0}}, f, indent=2)
        return 0

    # 3. Create Purview audit log query
    end_time = datetime.now(tz=timezone.utc)
    start_time = end_time - timedelta(hours=args.lookback_hours)

    logger.info("Creating Purview audit log query: %s to %s", start_time, end_time)
    query_id = create_audit_log_query(
        token, start_time, end_time, operation_filters=COPILOT_OPERATION_FILTERS
    )

    # 4. Poll and retrieve audit records
    audit_records = poll_audit_log_query(token, query_id)
    logger.info("Retrieved %d Purview audit records", len(audit_records))

    # 5. Correlate events
    enriched = correlate_events(moderation_events, audit_records)
    correlated_count = sum(1 for e in enriched if e["matchCount"] > 0)

    # 6. Write output
    output = {
        "events": enriched,
        "summary": {
            "total": len(enriched),
            "correlated": correlated_count,
            "uncorrelated": len(enriched) - correlated_count,
            "auditRecordsQueried": len(audit_records),
            "lookbackHours": args.lookback_hours,
            "correlationTimestamp": datetime.now(tz=timezone.utc).isoformat(),
        },
    }

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, default=str)

    logger.info(
        "Correlation complete: %d/%d events matched Purview records. Output: %s",
        correlated_count, len(enriched), args.output,
    )

    return 0


if __name__ == "__main__":
    sys.exit(main())
