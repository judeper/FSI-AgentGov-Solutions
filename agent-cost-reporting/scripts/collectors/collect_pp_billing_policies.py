#!/usr/bin/env python3
"""
Collector: Power Platform API -- billing policies.

The stable backbone for cost attribution: each billing policy links one Azure subscription /
resource group to one or more environments. Combined with the environments collector, this
yields the deterministic join environmentId -> billingPolicyId -> azureSubscriptionId that lets
subscription-scoped Azure cost be attributed to Power Platform environments.

Endpoint: GET {POWERPLATFORM_HOST}/licensing/billingPolicies?api-version=2024-10-01
Auth:     Service principal + Power Platform RBAC (delegated-only API; NO managed identity).
          See scripts/shared/auth_powerplatform.py for the auth model.
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


def collect_billing_policies(token: str) -> list:
    """List tenant billing policies, following nextLink/value pagination."""
    import requests

    url = f"{lib.POWERPLATFORM_HOST}/licensing/billingPolicies?api-version={lib.POWERPLATFORM_API_VERSION}"
    headers = {"Authorization": f"Bearer {token}"}
    rows: list = []
    while url:
        resp = requests.get(url, headers=headers, timeout=120)
        resp.raise_for_status()
        payload = resp.json()
        rows.extend(payload.get("value", payload if isinstance(payload, list) else []))
        url = payload.get("nextLink") if isinstance(payload, dict) else None
    return rows


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--snapshot-id", required=True)
    parser.add_argument("--tenant-id", required=True)
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--client-secret")
    parser.add_argument("--certificate-path")
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    result = lib.CollectorResult(surface=lib.SURFACE_POWERPLATFORM, status="skipped")
    if not args.live:
        result.note = "Dry run -- pass --live with an SP that has a Power Platform RBAC role."
        logger.info(result.note)
        return 0

    token = get_powerplatform_token(args.tenant_id, args.client_id, args.client_secret, args.certificate_path)
    rows = collect_billing_policies(token)
    result.extract_path = lib.write_raw_extract(args.out_dir, "powerplatform_billing_policies", args.snapshot_id, rows)
    result.rows = len(rows)
    result.data_freshness_utc = lib.utc_now_iso()
    result.finish("succeeded")
    logger.info("Collected %d billing policy row(s).", result.rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
