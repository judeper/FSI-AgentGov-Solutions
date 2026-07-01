#!/usr/bin/env python3
"""
Collector: Azure Cost Management -- Generate Cost Details Report (async).

Bulk, line-item cost extract (ActualCost) for evidence snapshots and meter discovery. This
is the GA replacement for the legacy UsageDetails API. The call is asynchronous: POST to start,
poll the operation-status URL from the response, then download the resulting CSV/manifest.

Endpoint: POST {AZURE_RM_HOST}/{scope}/providers/Microsoft.CostManagement/generateCostDetailsReport?api-version=2025-03-01
Auth:     ARM token (managed identity / app-only), Cost Management Reader on the scope.
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
from auth_arm import get_arm_token  # noqa: E402

logger = logging.getLogger(__name__)

POLL_INTERVAL_SECONDS = 20
MAX_POLLS = 60


def start_report(scope: str, start: str, end: str, token: str) -> str:
    """Start the async report and return the operation-status polling URL."""
    import requests

    url = f"{lib.AZURE_RM_HOST}/{scope}/providers/Microsoft.CostManagement/generateCostDetailsReport?api-version={lib.COST_MANAGEMENT_API_VERSION}"
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    body = {"metric": "ActualCost", "timePeriod": {"start": start, "end": end}}
    resp = requests.post(url, headers=headers, data=json.dumps(body), timeout=120)
    resp.raise_for_status()
    location = resp.headers.get("Location") or resp.headers.get("Azure-AsyncOperation")
    if not location:
        raise RuntimeError("generateCostDetailsReport did not return a polling Location header.")
    return location


def poll_and_download(status_url: str, token: str) -> list:
    """Poll the operation until complete, then download and parse the blob(s)."""
    import csv
    import io

    import requests

    headers = {"Authorization": f"Bearer {token}"}
    for _ in range(MAX_POLLS):
        resp = requests.get(status_url, headers=headers, timeout=120)
        resp.raise_for_status()
        if resp.status_code == 200:
            blobs = resp.json().get("manifest", {}).get("blobs", [])
            rows: list = []
            for blob in blobs:
                data = requests.get(blob["blobLink"], timeout=300).text
                rows.extend(list(csv.DictReader(io.StringIO(data))))
            return rows
        time.sleep(POLL_INTERVAL_SECONDS)
    raise TimeoutError("generateCostDetailsReport did not complete within the poll budget.")


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", required=True, help="e.g. subscriptions/{subscriptionId}")
    parser.add_argument("--start", required=True, help="YYYY-MM-DD")
    parser.add_argument("--end", required=True, help="YYYY-MM-DD")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--snapshot-id", required=True)
    parser.add_argument("--client-id")
    parser.add_argument("--tenant-id")
    parser.add_argument("--client-secret")
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    result = lib.CollectorResult(surface=lib.SURFACE_AZURE_COST, status="skipped")
    if not args.live:
        result.note = "Dry run -- pass --live with valid credentials to generate the cost details report."
        logger.info(result.note)
        return 0

    token = get_arm_token(args.client_id, args.tenant_id, args.client_secret)
    status_url = start_report(args.scope, args.start, args.end, token)
    rows = poll_and_download(status_url, token)
    result.extract_path = lib.write_raw_extract(args.out_dir, lib.SURFACE_AZURE_COST, args.snapshot_id, rows)
    result.rows = len(rows)
    result.data_freshness_utc = lib.utc_now_iso()
    result.finish("succeeded")
    logger.info("Cost Details report collected %d row(s).", result.rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
