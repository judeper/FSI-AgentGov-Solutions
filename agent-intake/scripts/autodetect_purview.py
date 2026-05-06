#!/usr/bin/env python3
"""Auto-detect Microsoft Purview retention labels relevant to agent intake.

Used to verify that the `FSI-AgentIntake-7yr` retention label exists in the
tenant before approving an Express-path request. If the label is missing,
the router flow surfaces a one-time admin prompt to run
`scripts/setup_purview_retention_label.py`.

STATUS: stub for v0.1.0-preview. The Microsoft Graph beta endpoint
`/security/labels/retentionLabels` requires the
`RecordsManagement.Read.All` application permission, which the spike
identity did not have. Customers must grant this permission and verify
behaviour during pilot. See `research/04-api-verification-spike.md` for
the test results and remediation steps.

Usage:
  python autodetect_purview.py --label-name FSI-AgentIntake-7yr
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from typing import Any

import requests

from autodetect_environments import get_token_via_cli, get_token_via_managed_identity

LOG = logging.getLogger("agent-intake.autodetect.purview")

GRAPH_BASE = "https://graph.microsoft.com"
GRAPH_RESOURCE = "https://graph.microsoft.com/"
RETENTION_LABELS_PATH = "/beta/security/labels/retentionLabels"


def fetch_retention_labels(token: str) -> list[dict[str, Any]]:
    url = f"{GRAPH_BASE}{RETENTION_LABELS_PATH}"
    resp = requests.get(
        url,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        timeout=60,
    )
    if resp.status_code == 401:
        raise PermissionError(
            "Graph 401 — RecordsManagement.Read.All app permission required. "
            "See research/04-api-verification-spike.md for setup."
        )
    resp.raise_for_status()
    return resp.json().get("value", [])


def verify_label(label_name: str, token: str) -> dict[str, Any]:
    try:
        labels = fetch_retention_labels(token)
    except PermissionError as exc:
        LOG.warning("Permission gap — falling back to manual verification: %s", exc)
        return {"verified": False, "reason": str(exc), "remediation": "Grant RecordsManagement.Read.All and rerun, or verify the label manually in Purview portal."}

    match = next((lbl for lbl in labels if lbl.get("displayName") == label_name), None)
    if not match:
        return {"verified": False, "reason": f"Label '{label_name}' not found", "remediation": "Run scripts/setup_purview_retention_label.py."}
    return {
        "verified": True,
        "labelId": match.get("id"),
        "retentionDuration": match.get("retentionDuration"),
        "behaviorDuringRetentionPeriod": match.get("behaviorDuringRetentionPeriod"),
    }


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    p = argparse.ArgumentParser(description="Verify a Purview retention label exists")
    p.add_argument("--label-name", default="FSI-AgentIntake-7yr")
    p.add_argument("--token-source", choices=["mi", "cli"], default="mi")
    args = p.parse_args()

    token = get_token_via_managed_identity(GRAPH_RESOURCE) if args.token_source == "mi" else get_token_via_cli(GRAPH_RESOURCE)
    result = verify_label(args.label_name, token)
    print(json.dumps(result, indent=2))
    return 0 if result.get("verified") else 2


if __name__ == "__main__":
    sys.exit(main())
