#!/usr/bin/env python3
"""
Collector (PREVIEW, feature-flagged, disabled by default): Power Platform API capacity allocations.

WARNING -- Microsoft documents the capacity-allocation endpoints as "under active development.
Do not use this API in production." This collector is therefore OFF unless --enable-preview is
passed AND the COSTRPT_ENABLE_PP_CAPACITY_PREVIEW environment variable is set. It must never be a
gating dependency; the billing-policy + environment collectors are the stable join spine.

Capacity allocations are also believed to return ALLOCATED (not CONSUMED) credits -- so even when
enabled, this does not close the per-agent credit-consumption gap. Treat output as supplementary.

Endpoint: GET {POWERPLATFORM_HOST}/licensing/capacityAllocations?api-version=2024-10-01  (preview)
Auth:     Service principal + Power Platform RBAC (delegated-only API; NO managed identity).
"""

from __future__ import annotations

import argparse
import logging
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
import cost_report_lib as lib  # noqa: E402
from auth_powerplatform import get_powerplatform_token  # noqa: E402

logger = logging.getLogger(__name__)

PREVIEW_ENV_FLAG = "COSTRPT_ENABLE_PP_CAPACITY_PREVIEW"


def collect_capacity_allocations(token: str) -> list:
    """List capacity allocations (preview). Response schema is unverified -- raw rows only."""
    import requests

    url = f"{lib.POWERPLATFORM_HOST}/licensing/capacityAllocations?api-version={lib.POWERPLATFORM_API_VERSION}"
    resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=120)
    resp.raise_for_status()
    payload = resp.json()
    return payload.get("value", payload if isinstance(payload, list) else [])


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--snapshot-id", required=True)
    parser.add_argument("--tenant-id", required=True)
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--client-secret")
    parser.add_argument("--certificate-path")
    parser.add_argument("--enable-preview", action="store_true", help="Opt in to the preview API.")
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    result = lib.CollectorResult(surface=lib.SURFACE_POWERPLATFORM, status="skipped", preview=True)
    if not (args.enable_preview and os.environ.get(PREVIEW_ENV_FLAG)):
        result.note = (
            f"Preview collector disabled. Set --enable-preview and {PREVIEW_ENV_FLAG}=1 to opt in. "
            "Microsoft marks this API 'do not use in production'."
        )
        logger.info(result.note)
        return 0
    if not args.live:
        result.note = "Dry run -- pass --live to call the preview capacity-allocations API."
        logger.info(result.note)
        return 0

    token = get_powerplatform_token(args.tenant_id, args.client_id, args.client_secret, args.certificate_path)
    rows = collect_capacity_allocations(token)
    result.extract_path = lib.write_raw_extract(
        args.out_dir, "powerplatform_capacity_allocations_preview", args.snapshot_id, rows
    )
    result.rows = len(rows)
    result.data_freshness_utc = lib.utc_now_iso()
    result.finish("succeeded")
    logger.info("Collected %d preview capacity-allocation row(s) (supplementary, allocated not consumed).", result.rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
