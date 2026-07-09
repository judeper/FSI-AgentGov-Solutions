#!/usr/bin/env python3
"""
Collector: Microsoft Graph -- Microsoft 365 Copilot usage reports.

Usage activity only (NOT cost or credits). GA on Graph v1.0; app-only / managed identity.

Endpoints:
  GET {GRAPH_V1_HOST}/reports/getMicrosoft365CopilotUsageUserDetail(period='{period}')
  GET {GRAPH_V1_HOST}/reports/getMicrosoft365CopilotUserCountSummary(period='{period}')
Auth: Graph token with Reports.Read.All.
Period values: D7 | D30 | D90 | D180 (no arbitrary ranges).
"""

from __future__ import annotations

import argparse
import csv
import io
import logging
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
import cost_report_lib as lib  # noqa: E402
from auth_graph import get_graph_token  # noqa: E402

logger = logging.getLogger(__name__)

VALID_PERIODS = {"D7", "D30", "D90", "D180"}


def collect_usage_user_detail(period: str, token: str) -> list:
    """Fetch per-user Copilot usage detail. Graph returns CSV for these report functions."""
    import requests

    url = f"{lib.GRAPH_V1_HOST}/reports/getMicrosoft365CopilotUsageUserDetail(period='{period}')"
    resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=120)
    resp.raise_for_status()
    text = resp.text.lstrip("\ufeff")
    return list(csv.DictReader(io.StringIO(text)))


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--period", default="D30", choices=sorted(VALID_PERIODS))
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--snapshot-id", required=True)
    parser.add_argument("--client-id")
    parser.add_argument("--tenant-id")
    parser.add_argument("--client-secret")
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    result = lib.CollectorResult(surface=lib.SURFACE_GRAPH_REPORTS, status="skipped")
    if not args.live:
        result.note = "Dry run -- pass --live with valid credentials to call Microsoft Graph."
        logger.info(result.note)
        return 0

    token = get_graph_token(args.client_id, args.tenant_id, args.client_secret)
    rows = collect_usage_user_detail(args.period, token)
    result.extract_path = lib.write_raw_extract(args.out_dir, lib.SURFACE_GRAPH_REPORTS, args.snapshot_id, rows)
    result.rows = len(rows)
    result.data_freshness_utc = lib.utc_now_iso()
    result.finish("succeeded")
    logger.info("Graph Copilot usage detail collected %d row(s).", result.rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
