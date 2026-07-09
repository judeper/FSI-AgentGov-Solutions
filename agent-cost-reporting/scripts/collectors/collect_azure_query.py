#!/usr/bin/env python3
"""
Collector: Azure Cost Management -- Query (Usage).

Authoritative pay-as-you-go cost ($) by subscription / resource group / meter. This is the
strongest, GA, managed-identity-capable cost surface. It has NO agent dimension; per-agent
attribution is reconstructed later (heuristically) by the correlator, never invented here.

Endpoint: POST {AZURE_RM_HOST}/{scope}/providers/Microsoft.CostManagement/query?api-version=2025-03-01
Auth:     ARM token (managed identity / app-only), Cost Management Reader on the scope.

Meter names for Power Platform / Copilot Studio change over time and are NOT hardcoded -- they
are discovered from query output (group by MeterId/Meter) and filtered downstream.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
import cost_report_lib as lib  # noqa: E402
from auth_arm import get_arm_token  # noqa: E402

logger = logging.getLogger(__name__)


def build_query_body(start_utc: str, end_utc: str) -> dict:
    """Build the Cost Management query payload grouped by meter for dynamic discovery."""
    return {
        "type": "Usage",
        "timeframe": "Custom",
        "timePeriod": {"from": start_utc, "to": end_utc},
        "dataset": {
            "granularity": "Daily",
            "aggregation": {"totalCost": {"name": "Cost", "function": "Sum"}},
            "grouping": [
                {"type": "Dimension", "name": "MeterId"},
                {"type": "Dimension", "name": "Meter"},
                {"type": "Dimension", "name": "ServiceName"},
                {"type": "Dimension", "name": "ResourceGroupName"},
            ],
        },
    }


def collect(scope: str, start_utc: str, end_utc: str, token: str) -> list:
    """Call the Cost Management Query API and return raw result rows.

    Follows nextLink pagination when present. Returns the raw rows as dicts so the
    normalizer can map them to cost facts (filtering to Power Platform / Copilot Studio
    meters by observed ids).
    """
    import requests

    url = f"{lib.AZURE_RM_HOST}/{scope}/providers/Microsoft.CostManagement/query?api-version={lib.COST_MANAGEMENT_API_VERSION}"
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    body = build_query_body(start_utc, end_utc)
    rows: list = []
    while url:
        resp = requests.post(url, headers=headers, data=json.dumps(body), timeout=120)
        resp.raise_for_status()
        payload = resp.json()
        props = payload.get("properties", {})
        columns = [c["name"] for c in props.get("columns", [])]
        for raw in props.get("rows", []):
            rows.append(dict(zip(columns, raw)))
        url = props.get("nextLink")
        body = None  # nextLink encodes the query
    # Stamp the subscription id from the scope so the normalizer can join to billing policies.
    sub = scope.split("subscriptions/")[-1].split("/")[0] if "subscriptions/" in scope else None
    for row in rows:
        row.setdefault("subscriptionId", sub)
        row.setdefault("_scope", scope)
    return rows


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", required=True, help="e.g. subscriptions/{subscriptionId}")
    parser.add_argument("--start-utc", required=True)
    parser.add_argument("--end-utc", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--snapshot-id", required=True)
    parser.add_argument("--client-id")
    parser.add_argument("--tenant-id")
    parser.add_argument("--client-secret")
    parser.add_argument("--live", action="store_true", help="Actually call Azure (otherwise emit a skipped result).")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    result = lib.CollectorResult(surface=lib.SURFACE_AZURE_COST, status="skipped")
    if not args.live:
        result.note = "Dry run -- pass --live with valid credentials to call Azure Cost Management."
        logger.info(result.note)
        return 0

    token = get_arm_token(args.client_id, args.tenant_id, args.client_secret)
    rows = collect(args.scope, args.start_utc, args.end_utc, token)
    result.extract_path = lib.write_raw_extract(args.out_dir, lib.SURFACE_AZURE_COST, args.snapshot_id, rows)
    result.rows = len(rows)
    result.data_freshness_utc = lib.utc_now_iso()
    result.finish("succeeded")
    logger.info("Azure Cost Management query collected %d row(s).", result.rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
