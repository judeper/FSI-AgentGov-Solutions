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
  POST {GRAPH_BETA_HOST}/security/auditLog/queries
  GET  {GRAPH_BETA_HOST}/security/auditLog/queries/{queryId}
Auth: Graph token with AuditLogsQuery.Read.All.
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
    # Records-fetch endpoint + CopilotInteraction schema are unverified at scaffold time.
    # Persist the query metadata and degrade gracefully until record retrieval is wired.
    result.extract_path = lib.write_raw_extract(
        args.out_dir, lib.SURFACE_PURVIEW_AUDIT, args.snapshot_id, [{"query": query, "status": status}]
    )
    result.rows = 0
    result.data_freshness_utc = lib.utc_now_iso()
    if status == "succeeded":
        result.note = "Query succeeded; records-fetch not yet implemented -- verify the records endpoint on a live tenant."
        result.finish("partial")
    else:
        result.note = f"Audit query status='{status}'."
        result.finish("partial")
    logger.info("Purview audit query created (status=%s).", status)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
