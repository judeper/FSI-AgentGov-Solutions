#!/usr/bin/env python3
"""Mint a Microsoft Entra Agent ID for an approved intake request.

Called from Power Automate Flow 3 (`docs/flow-configuration.md`) after a
sponsor approves an Express-path request. The returned `agentId` is written
back to `fsi_intakerequest.fsi_entra_agentid` and forwarded to
`agent-registry-automation` as the canonical identity for the new agent.

Endpoint (verified roadmap; live after GA May 1, 2026):
  POST https://graph.microsoft.com/beta/identityGovernance/agentIdentities

Required app permission: AgentIdentity.ReadWrite.All

Authentication: managed-identity-first. Falls back to azure-cli for dev.

Usage:
  python setup_entra_agent_id.py \
      --intake-request-id <guid> \
      --display-name "Cash Reconciliation Helper" \
      --owner-upn alice@contoso.com \
      --output result.json
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Any

import requests

from autodetect_environments import get_token_via_cli, get_token_via_managed_identity

LOG = logging.getLogger("agent-intake.entra")

GRAPH_BASE = "https://graph.microsoft.com"
GRAPH_RESOURCE = "https://graph.microsoft.com/"
AGENT_ID_PATH = "/beta/identityGovernance/agentIdentities"


def mint_agent_id(token: str, *, display_name: str, owner_upn: str, intake_request_id: str) -> dict[str, Any]:
    payload = {
        "displayName": display_name,
        "description": f"FSI agent intake request {intake_request_id}",
        "owners": [{"userPrincipalName": owner_upn}],
        "tags": [
            "fsi-agent-intake",
            f"intake-request:{intake_request_id}",
        ],
    }
    resp = requests.post(
        f"{GRAPH_BASE}{AGENT_ID_PATH}",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json=payload,
        timeout=60,
    )
    if resp.status_code == 403:
        raise PermissionError("AgentIdentity.ReadWrite.All app permission required and admin-consented")
    if resp.status_code == 404:
        raise RuntimeError("Endpoint not found — verify Entra Agent ID GA (May 1, 2026) and tenant licensing")
    resp.raise_for_status()
    return resp.json()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    p = argparse.ArgumentParser(description="Mint an Entra Agent ID for an approved intake request")
    p.add_argument("--intake-request-id", required=True)
    p.add_argument("--display-name", required=True)
    p.add_argument("--owner-upn", required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--token-source", choices=["mi", "cli"], default="mi")
    p.add_argument("--dry-run", action="store_true", help="Skip the POST; emit the planned payload only")
    args = p.parse_args()

    if args.dry_run:
        LOG.info("Dry-run mode")
        result = {
            "dryRun": True,
            "wouldPost": {
                "url": f"{GRAPH_BASE}{AGENT_ID_PATH}",
                "displayName": args.display_name,
                "owner": args.owner_upn,
                "intakeRequestId": args.intake_request_id,
            },
        }
    else:
        token = get_token_via_managed_identity(GRAPH_RESOURCE) if args.token_source == "mi" else get_token_via_cli(GRAPH_RESOURCE)
        result = mint_agent_id(
            token,
            display_name=args.display_name,
            owner_upn=args.owner_upn,
            intake_request_id=args.intake_request_id,
        )
        LOG.info("Minted agent ID: %s", result.get("id"))

    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
