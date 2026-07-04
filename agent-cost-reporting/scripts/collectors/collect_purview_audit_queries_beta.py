#!/usr/bin/env python3
"""
Collector (BETA, feature-flagged, optional): Purview audit-log Copilot interactions.

Supplementary per-agent / per-user Copilot interaction counts (including unlicensed Copilot
Chat). This is USAGE evidence, NOT cost, and Microsoft states audit logs are not a full-fidelity
source of truth for billing -- so it is always labeled supplementary.

Constraints (must be respected):
  * BETA: "Use of these APIs in production applications is not supported."
  * NOT available in US Government (L4/L5/DoD) or China clouds -> degrade to surface_unavailable.
  * The records-fetch endpoint and CopilotInteraction record schema are UNVERIFIED at scaffold
    time; this collector creates the query and persists its metadata, and degrades gracefully if
    record retrieval is not yet wired.

Endpoints:
  POST {GRAPH_BETA_HOST}/security/auditLog/queries                    (create query)
  GET  {GRAPH_BETA_HOST}/security/auditLog/queries/{queryId}          (poll status)
  GET  {GRAPH_BETA_HOST}/security/auditLog/queries/{queryId}/records  (fetch records, paged)
Auth: Graph token with AuditLogsQuery.Read.All.

The records endpoint returns a collection of auditLogRecord objects using the standard
Microsoft Graph @odata.nextLink paging model; each CopilotInteraction is mapped to the
supplementary reporting shape (see map_copilot_interaction). Field mapping is UNVERIFIED
against a live tenant -- see docs/known-gaps.md.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
import cost_report_lib as lib  # noqa: E402
from auth_graph import get_graph_token  # noqa: E402

logger = logging.getLogger(__name__)

PREVIEW_ENV_FLAG = "COSTRPT_ENABLE_PURVIEW_AUDIT_BETA"
GOV_CLOUDS_UNSUPPORTED = {"usgov", "usgovdod", "ussec", "china"}
POLL_INTERVAL_SECONDS = 20
MAX_POLLS = 30


def create_audit_query(start_utc: str, end_utc: str, token: str) -> dict:
    """Create an audit-log query for Copilot interactions and return its metadata."""
    import requests

    url = f"{lib.GRAPH_BETA_HOST}/security/auditLog/queries"
    body = {
        "displayName": f"copilot-interactions-{start_utc}",
        "filterStartDateTime": start_utc,
        "filterEndDateTime": end_utc,
        "recordTypeFilters": ["copilotInteraction"],
        "operationFilters": [],
        "serviceFilter": "",
        "keywordFilter": "",
    }
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    resp = requests.post(url, headers=headers, data=json.dumps(body), timeout=120)
    resp.raise_for_status()
    return resp.json()


def poll_query(query_id: str, token: str) -> str:
    """Poll the query until it reaches a terminal status; return that status."""
    import requests

    url = f"{lib.GRAPH_BETA_HOST}/security/auditLog/queries/{query_id}"
    headers = {"Authorization": f"Bearer {token}"}
    for _ in range(MAX_POLLS):
        resp = requests.get(url, headers=headers, timeout=120)
        resp.raise_for_status()
        status = resp.json().get("status", "unknown")
        if status in {"succeeded", "failed", "cancelled"}:
            return status
        time.sleep(POLL_INTERVAL_SECONDS)
    return "running"


# ---------------------------------------------------------------------------
# Records fetch + CopilotInteraction field mapping.
#
# The records endpoint returns a collection of auditLogRecord objects using the
# standard Microsoft Graph @odata.nextLink paging model. The Copilot-specific
# detail lives in the opaque `auditData` blob; the copilotInteractionAuditRecord
# beta resource documents no explicit properties, so the auditData field names
# used below follow the Office 365 Management Activity API "CopilotInteraction"
# schema (AppHost, Contexts, ThreadId, MessageIds, AccessedResources, AgentId, ...).
# Casing and availability of these fields when surfaced through Graph beta are
# UNVERIFIED against a live tenant, so extraction is case-insensitive and every
# Copilot-specific field is optional. See docs/known-gaps.md.
# ---------------------------------------------------------------------------

# Hard stop so a misbehaving @odata.nextLink cannot page forever.
RECORDS_MAX_PAGES = 1000


def _default_get_json(url: str, headers: dict) -> dict:
    """Default transport: authenticated GET returning parsed JSON."""
    import requests

    resp = requests.get(url, headers=headers, timeout=120)
    resp.raise_for_status()
    return resp.json()


def fetch_query_records(query_id: str, token: str, get_json=None) -> list:
    """Fetch all auditLogRecord objects for a completed query, following @odata.nextLink.

    Handles the empty result set, a single page (no nextLink), and multi-page responses,
    and guards against a server that echoes an identical nextLink. `get_json` is injectable
    so the pagination logic can be unit-tested with mocked payloads and no network access.
    """
    get_json = get_json or _default_get_json
    headers = {"Authorization": f"Bearer {token}"}
    url = f"{lib.GRAPH_BETA_HOST}/security/auditLog/queries/{query_id}/records"
    records: list = []
    seen_links: set = set()
    pages = 0
    while url and pages < RECORDS_MAX_PAGES:
        payload = get_json(url, headers)
        pages += 1
        records.extend(payload.get("value") or [])
        next_link = payload.get("@odata.nextLink")
        if next_link and next_link in seen_links:
            logger.warning("Audit records nextLink repeated; stopping to avoid an infinite loop.")
            break
        if next_link:
            seen_links.add(next_link)
        url = next_link
    if url and pages >= RECORDS_MAX_PAGES:
        logger.warning("Stopped after %d record page(s); more records may remain.", pages)
    logger.info("Fetched %d Copilot audit record(s) across %d page(s).", len(records), pages)
    return records


def _audit_data_dict(record: dict) -> dict:
    """Return a record's auditData as a dict.

    Graph may return auditData as a nested JSON object or, for some workloads, as a
    JSON-encoded string. Both are handled; anything else yields an empty dict.
    """
    data = record.get("auditData")
    if isinstance(data, dict):
        return data
    if isinstance(data, str):
        try:
            parsed = json.loads(data)
        except (ValueError, TypeError):
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}


def _ci_get(data: dict, *names: str):
    """Case-insensitive lookup: return the first present key among `names`, else None."""
    lowered = {str(k).lower(): v for k, v in data.items()}
    for name in names:
        if name.lower() in lowered:
            return lowered[name.lower()]
    return None


def map_copilot_interaction(record: dict) -> dict:
    """Map one auditLogRecord to the supplementary Copilot-interaction reporting shape.

    Envelope fields come from the auditLogRecord itself; Copilot detail is pulled from the
    auditData blob (see the module note on schema uncertainty). This is USAGE evidence only
    and is never folded into authoritative cost totals.
    """
    audit_data = _audit_data_dict(record)
    return {
        "source_surface": lib.SURFACE_PURVIEW_AUDIT,
        "record_id": lib.stable_record_id(record.get("id"), record),
        "created_utc": record.get("createdDateTime"),
        "operation": record.get("operation"),
        "record_type": record.get("auditLogRecordType"),
        "organization_id": record.get("organizationId"),
        "service": record.get("service"),
        "user_id": record.get("userId"),
        "user_principal_name": record.get("userPrincipalName"),
        "user_type": record.get("userType"),
        "client_ip": record.get("clientIp"),
        # Copilot-specific detail from auditData (all optional; casing UNVERIFIED).
        "app_host": _ci_get(audit_data, "AppHost"),
        "app_identity": _ci_get(audit_data, "AppIdentity"),
        "agent_id": _ci_get(audit_data, "AgentId"),
        "ai_system_plugin": _ci_get(audit_data, "AISystemPlugin"),
        "contexts": _ci_get(audit_data, "Contexts"),
        "thread_id": _ci_get(audit_data, "ThreadId", "ThreadID"),
        "message_ids": _ci_get(audit_data, "MessageIds", "MessageIDs"),
        "accessed_resources": _ci_get(audit_data, "AccessedResources"),
        "model_transparency_details": _ci_get(audit_data, "ModelTransparencyDetails"),
    }


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start-utc", required=True)
    parser.add_argument("--end-utc", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--snapshot-id", required=True)
    parser.add_argument("--cloud", default="commercial", help="commercial | usgov | usgovdod | china")
    parser.add_argument("--client-id")
    parser.add_argument("--tenant-id")
    parser.add_argument("--client-secret")
    parser.add_argument("--enable-beta", action="store_true")
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    result = lib.CollectorResult(surface=lib.SURFACE_PURVIEW_AUDIT, status="skipped", preview=True)

    if args.cloud.lower() in GOV_CLOUDS_UNSUPPORTED:
        result.note = f"Purview audit-log query API is unavailable in cloud '{args.cloud}'."
        result.finish("surface_unavailable")
        logger.warning(result.note)
        return 0
    if not (args.enable_beta and os.environ.get(PREVIEW_ENV_FLAG)):
        result.note = f"Beta collector disabled. Set --enable-beta and {PREVIEW_ENV_FLAG}=1 to opt in."
        logger.info(result.note)
        return 0
    if not args.live:
        result.note = "Dry run -- pass --live with valid credentials to create the audit query."
        logger.info(result.note)
        return 0

    token = get_graph_token(args.client_id, args.tenant_id, args.client_secret)
    query = create_audit_query(args.start_utc, args.end_utc, token)
    query_id = query.get("id")
    status = poll_query(query_id, token) if query_id else "unknown"
    # When the query has completed, fetch its records (with @odata.nextLink paging) and
    # map each CopilotInteraction to the supplementary reporting shape. The auditData schema
    # is UNVERIFIED against a live tenant, so mapping is defensive and the surface stays
    # supplementary (usage evidence, never authoritative cost).
    if query_id and status == "succeeded":
        raw_records = fetch_query_records(query_id, token)
        mapped = [map_copilot_interaction(r) for r in raw_records]
        result.extract_path = lib.write_raw_extract(
            args.out_dir, lib.SURFACE_PURVIEW_AUDIT, args.snapshot_id, mapped
        )
        result.rows = len(mapped)
        result.data_freshness_utc = lib.utc_now_iso()
        if mapped:
            result.note = (
                f"Fetched {len(mapped)} Copilot interaction record(s). Supplementary usage "
                "evidence; auditData field mapping is unverified against a live tenant."
            )
            result.finish("partial")
        else:
            result.note = "Query succeeded with no Copilot interaction records in range."
            result.finish("succeeded")
    else:
        # Non-terminal or failed query: persist the query metadata for provenance only.
        result.extract_path = lib.write_raw_extract(
            args.out_dir, lib.SURFACE_PURVIEW_AUDIT, args.snapshot_id, [{"query": query, "status": status}]
        )
        result.rows = 0
        result.data_freshness_utc = lib.utc_now_iso()
        result.note = f"Audit query status='{status}'; no records fetched."
        result.finish("partial")
    logger.info("Purview audit query processed (status=%s, rows=%d).", status, result.rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
