#!/usr/bin/env python3
"""
Collector: Microsoft Graph -- license / seat inventory.

Seat counts and assignments for Microsoft 365 Copilot and Agent 365 (NO dollar amount; unit
price is not exposed by Graph). GA on v1.0; app-only / managed identity.

Endpoints:
  GET {GRAPH_V1_HOST}/subscribedSkus
  GET {GRAPH_V1_HOST}/users/{userId}/licenseDetails   (optional per-user enrichment)
Auth: Graph token with Organization.Read.All (subscribedSkus) / Directory.Read.All.

Note: the exact Agent 365 skuPartNumber values are not yet pinned in primary docs; resolve at
runtime from the subscribedSkus output.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
import cost_report_lib as lib  # noqa: E402
from auth_graph import get_graph_token  # noqa: E402

logger = logging.getLogger(__name__)


def collect_subscribed_skus(token: str) -> list:
    """Fetch tenant subscribed SKUs (purchased vs consumed seat counts), following nextLink."""
    import requests

    url = f"{lib.GRAPH_V1_HOST}/subscribedSkus"
    headers = {"Authorization": f"Bearer {token}"}
    rows: list = []
    while url:
        resp = requests.get(url, headers=headers, timeout=120)
        resp.raise_for_status()
        payload = resp.json()
        rows.extend(payload.get("value", []))
        url = payload.get("@odata.nextLink")
    return rows


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--snapshot-id", required=True)
    parser.add_argument("--client-id")
    parser.add_argument("--tenant-id")
    parser.add_argument("--client-secret")
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    result = lib.CollectorResult(surface=lib.SURFACE_GRAPH_LICENSES, status="skipped")
    if not args.live:
        result.note = "Dry run -- pass --live with valid credentials to call Microsoft Graph."
        logger.info(result.note)
        return 0

    token = get_graph_token(args.client_id, args.tenant_id, args.client_secret)
    rows = collect_subscribed_skus(token)
    result.extract_path = lib.write_raw_extract(args.out_dir, lib.SURFACE_GRAPH_LICENSES, args.snapshot_id, rows)
    result.rows = len(rows)
    result.data_freshness_utc = lib.utc_now_iso()
    result.finish("succeeded")
    logger.info("Graph license inventory collected %d SKU row(s).", result.rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
