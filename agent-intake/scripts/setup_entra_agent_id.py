#!/usr/bin/env python3
"""Mint a Microsoft Entra Agent ID for an approved intake request.

Called from Power Automate Flow 3 (`docs/flow-configuration.md`) after a
sponsor approves an Express-path request. The returned service principal ID is
written back to `fsi_intakerequest.fsi_entraagentid` and forwarded to
`agent-registry-automation` as the canonical identity for the new agent.

Current Microsoft Graph shape:
  POST https://graph.microsoft.com/v1.0/servicePrincipals/microsoft.graph.agentIdentity

The create action requires a display name, an agentIdentityBlueprintId, and a
sponsor relationship. The least-privileged create permissions documented by
Microsoft are AgentIdentity.CreateAsManager or AgentIdentity.Create.All.

Authentication: managed-identity-first. Falls back to Azure CLI for admin
workstation testing.

Usage:
  python setup_entra_agent_id.py \
      --intake-request-id <guid> \
      --display-name "Cash Reconciliation Helper" \
      --sponsor-upn alice@contoso.com \
      --blueprint-id <agentIdentityBlueprintId> \
      --output result.json
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote

import requests

from autodetect_environments import get_token_via_cli, get_token_via_managed_identity

LOG = logging.getLogger("agent-intake.entra")

GRAPH_BASE = "https://graph.microsoft.com"
GRAPH_RESOURCE = "https://graph.microsoft.com/"
AGENT_ID_CREATE_PATH = "/v1.0/servicePrincipals/microsoft.graph.agentIdentity"
AGENT_ID_LIST_PATH = "/v1.0/servicePrincipals/microsoft.graph.agentIdentity"
REQUIRED_CREATE_PERMISSIONS = ("AgentIdentity.CreateAsManager", "AgentIdentity.Create.All")
OPTIONAL_READ_PERMISSION = "AgentIdentity.Read.All"


def get_user(token: str, upn: str) -> dict[str, Any]:
    """Resolve a sponsor UPN to a Microsoft Graph user ID."""
    encoded = quote(upn, safe="")
    resp = requests.get(
        f"{GRAPH_BASE}/v1.0/users/{encoded}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        params={"$select": "id,userPrincipalName,displayName"},
        timeout=60,
    )
    if resp.status_code == 404:
        raise ValueError(f"Sponsor user not found: {upn}")
    resp.raise_for_status()
    return resp.json()


def planned_payload(*, display_name: str, sponsor_id: str, blueprint_id: str, intake_request_id: str) -> dict[str, Any]:
    """Return the payload sent to Graph for agent identity creation."""
    return {
        "displayName": display_name,
        "agentIdentityBlueprintId": blueprint_id,
        "sponsors@odata.bind": [f"{GRAPH_BASE}/v1.0/users/{sponsor_id}"],
        "tags": [
            "fsi-agent-intake",
            f"intake-request:{intake_request_id}",
        ],
    }


def mint_agent_id(
    token: str,
    *,
    display_name: str,
    sponsor_upn: str,
    blueprint_id: str,
    intake_request_id: str,
) -> dict[str, Any]:
    """Create a Microsoft Entra Agent ID service principal."""
    sponsor = get_user(token, sponsor_upn)
    payload = planned_payload(
        display_name=display_name,
        sponsor_id=sponsor["id"],
        blueprint_id=blueprint_id,
        intake_request_id=intake_request_id,
    )
    resp = requests.post(
        f"{GRAPH_BASE}{AGENT_ID_CREATE_PATH}",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "Accept": "application/json"},
        json=payload,
        timeout=60,
    )
    if resp.status_code in {401, 403}:
        raise PermissionError(
            "Agent ID create permission required. Grant either "
            f"{REQUIRED_CREATE_PERMISSIONS[0]} or {REQUIRED_CREATE_PERMISSIONS[1]} and verify the caller has an eligible Agent ID admin/developer role."
        )
    if resp.status_code == 404:
        raise RuntimeError("Agent Identity create action not available in this tenant/cloud; verify Microsoft Entra Agent ID availability.")
    resp.raise_for_status()
    result = resp.json()
    result["sponsor"] = sponsor
    return result


def check_consent(token: str) -> dict[str, Any]:
    """Best-effort readiness check for Graph access and documented permissions."""
    result: dict[str, Any] = {
        "requiredCreatePermissions": list(REQUIRED_CREATE_PERMISSIONS),
        "optionalReadPermission": OPTIONAL_READ_PERMISSION,
        "checks": [],
        "readyForCreate": "unknown",
    }
    resp = requests.get(
        f"{GRAPH_BASE}{AGENT_ID_LIST_PATH}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        params={"$top": "1", "$select": "id,displayName"},
        timeout=60,
    )
    if resp.ok:
        result["checks"].append({"name": "listAgentIdentities", "status": "passed"})
    elif resp.status_code in {401, 403}:
        result["checks"].append({
            "name": "listAgentIdentities",
            "status": "warning",
            "detail": "Read check failed; this is expected if only create permissions were consented. Verify create permission grants in Entra admin center.",
            "httpStatus": resp.status_code,
        })
    else:
        result["checks"].append({"name": "listAgentIdentities", "status": "failed", "httpStatus": resp.status_code, "body": resp.text[:500]})
    return result


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Mint an Entra Agent ID for an approved intake request")
    parser.add_argument("--intake-request-id")
    parser.add_argument("--display-name")
    parser.add_argument("--sponsor-upn", dest="sponsor_upn")
    parser.add_argument("--owner-upn", dest="sponsor_upn", help="Deprecated alias for --sponsor-upn")
    parser.add_argument("--blueprint-id", default=None, help="Agent identity blueprint ID created via POST /applications/microsoft.graph.agentIdentityBlueprint")
    parser.add_argument("--output", type=Path, help="Where to write result JSON; if omitted, prints to stdout")
    parser.add_argument("--token-source", choices=["mi", "cli"], default="mi")
    parser.add_argument("--dry-run", action="store_true", help="Skip the POST; emit the planned payload only")
    parser.add_argument("--check-consent", action="store_true", help="Print readiness checks and documented permission requirements")
    args = parser.parse_args()

    if args.check_consent:
        token = get_token_via_managed_identity(GRAPH_RESOURCE) if args.token_source == "mi" else get_token_via_cli(GRAPH_RESOURCE)
        result = check_consent(token)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result, indent=2))
        return 0

    missing = [name for name, value in {
        "--intake-request-id": args.intake_request_id,
        "--display-name": args.display_name,
        "--sponsor-upn": args.sponsor_upn,
        "--blueprint-id": args.blueprint_id,
    }.items() if not value]
    if missing:
        parser.error("Missing required arguments for minting: " + ", ".join(missing))

    if args.dry_run:
        LOG.info("Dry-run mode")
        result = {
            "dryRun": True,
            "wouldPost": {
                "url": f"{GRAPH_BASE}{AGENT_ID_CREATE_PATH}",
                "payload": planned_payload(
                    display_name=args.display_name,
                    sponsor_id="<resolved-sponsor-user-id>",
                    blueprint_id=args.blueprint_id,
                    intake_request_id=args.intake_request_id,
                ),
                "requiredCreatePermissions": list(REQUIRED_CREATE_PERMISSIONS),
            },
        }
    else:
        token = get_token_via_managed_identity(GRAPH_RESOURCE) if args.token_source == "mi" else get_token_via_cli(GRAPH_RESOURCE)
        result = mint_agent_id(
            token,
            display_name=args.display_name,
            sponsor_upn=args.sponsor_upn,
            blueprint_id=args.blueprint_id,
            intake_request_id=args.intake_request_id,
        )
        LOG.info("Minted agent ID service principal: %s", result.get("id"))

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    else:
        print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
