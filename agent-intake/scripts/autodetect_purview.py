#!/usr/bin/env python3
"""Auto-detect Microsoft Purview retention labels relevant to agent intake.

Used to verify that the `FSI-AgentIntake-7yr` retention label exists before
routing Express-path approvals. If the label is missing, the router surfaces a
one-time admin prompt to run `scripts/setup_purview_retention_label.py`.

The Microsoft Graph beta endpoint `/security/labels/retentionLabels` supports
retention-label reads with delegated RecordsManagement.Read.All. Application
permissions are not supported on the current beta surface, so this verifier
defaults to an Azure CLI delegated token.

Usage:
  python autodetect_purview.py --label-name FSI-AgentIntake-7yr --token-source cli
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
    """Fetch retention labels from the Microsoft Graph beta security endpoint."""
    resp = requests.get(
        f"{GRAPH_BASE}{RETENTION_LABELS_PATH}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        timeout=60,
    )
    if resp.status_code in {401, 403}:
        raise PermissionError(
            "Graph retention-label read requires delegated RecordsManagement.Read.All/ReadWrite.All on the beta endpoint; "
            "application permissions are not supported. Use --token-source cli with a Records Management admin or verify manually in Purview."
        )
    resp.raise_for_status()
    return resp.json().get("value", [])


def verify_label(label_name: str, token: str) -> dict[str, Any]:
    """Return verification status for a Purview retention label."""
    try:
        labels = fetch_retention_labels(token)
    except PermissionError as exc:
        LOG.warning("Permission gap — falling back to manual verification: %s", exc)
        return {
            "verified": False,
            "reason": str(exc),
            "remediation": "Grant delegated RecordsManagement.Read.All/ReadWrite.All and rerun, or verify the label manually in the Purview portal.",
        }

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
    parser = argparse.ArgumentParser(description="Verify a Purview retention label exists")
    parser.add_argument("--label-name", default="FSI-AgentIntake-7yr")
    parser.add_argument("--token-source", choices=["cli", "mi"], default="cli")
    args = parser.parse_args()

    token = get_token_via_cli(GRAPH_RESOURCE) if args.token_source == "cli" else get_token_via_managed_identity(GRAPH_RESOURCE)
    result = verify_label(args.label_name, token)
    print(json.dumps(result, indent=2))
    return 0 if result.get("verified") else 2


if __name__ == "__main__":
    sys.exit(main())
