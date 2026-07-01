#!/usr/bin/env python3
"""
Collector: Power Platform API -- environments for each billing policy.

Resolves the environment side of the join spine. For each billing policy id (from the billing
policies collector), lists the linked environments, producing
environmentId -> billingPolicyId rows.

Endpoint: GET {POWERPLATFORM_HOST}/licensing/billingPolicies/{billingPolicyId}/environments?api-version=2024-10-01
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


def collect_policy_environments(billing_policy_id: str, token: str) -> list:
    """List the environments linked to one billing policy."""
    import requests

    url = (
        f"{lib.POWERPLATFORM_HOST}/licensing/billingPolicies/{billing_policy_id}"
        f"/environments?api-version={lib.POWERPLATFORM_API_VERSION}"
    )
    resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=120)
    resp.raise_for_status()
    payload = resp.json()
    rows = payload.get("value", payload if isinstance(payload, list) else [])
    for row in rows:
        if isinstance(row, dict):
            row.setdefault("billingPolicyId", billing_policy_id)
    return rows


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--billing-policy-ids", required=True, help="Comma-separated billing policy ids.")
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
    all_rows: list = []
    for policy_id in [p.strip() for p in args.billing_policy_ids.split(",") if p.strip()]:
        all_rows.extend(collect_policy_environments(policy_id, token))
    result.extract_path = lib.write_raw_extract(
        args.out_dir, "powerplatform_billing_policy_environments", args.snapshot_id, all_rows
    )
    result.rows = len(all_rows)
    result.data_freshness_utc = lib.utc_now_iso()
    result.finish("succeeded")
    logger.info("Collected %d policy-environment link row(s).", result.rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
