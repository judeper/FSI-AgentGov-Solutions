#!/usr/bin/env python3
"""Auto-detect Power Platform environments for intake routing.

Pulls the tenant's Power Platform environments via PPAC and maps each to a
zone classification hint based on `properties.environmentSku` and
`properties.governanceConfiguration.protectionLevel`. The output is consumed
by the router flow to suggest a target environment for approved Express-path
requests.

Authentication: managed-identity-first. Falls back to azure-cli-cached
delegated tokens for dev. See `scripts/shared/dataverse_client.py` for the
canonical pattern.

Endpoint verified in `research/04-api-verification-spike.md`:
  GET https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform
      /scopes/admin/environments?api-version=2020-10-01

Usage:
  python autodetect_environments.py --output environments.json
  python autodetect_environments.py --output environments.json --token-source cli
"""
from __future__ import annotations

import argparse
import json
import logging
import subprocess
import sys
from pathlib import Path
from typing import Any

import requests

LOG = logging.getLogger("agent-intake.autodetect.envs")

PPAC_BASE = "https://api.bap.microsoft.com"
PPAC_RESOURCE = "https://api.bap.microsoft.com/"
ENV_PATH = "/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments"
API_VERSION = "2020-10-01"


def get_token_via_cli(resource: str = PPAC_RESOURCE) -> str:
    """Dev fallback — get an access token from azure-cli cache."""
    # legacy: dev-only — replace with managed identity in production
    # On Windows, `az` is `az.cmd`. Python's subprocess does not honour PATHEXT
    # for the first argument of a list invocation, so we resolve via shutil.which
    # to get the full path (with .cmd extension on Windows) and fall back to the
    # bare name on Unix where the launcher is a real binary.
    import shutil

    az_executable = shutil.which("az") or "az"
    out = subprocess.check_output(
        [az_executable, "account", "get-access-token", "--resource", resource.rstrip("/"), "--query", "accessToken", "-o", "tsv"],
        text=True,
    )
    return out.strip()


def get_token_via_managed_identity(resource: str = PPAC_RESOURCE) -> str:
    """Production path — uses azure-identity DefaultAzureCredential."""
    from azure.identity import DefaultAzureCredential
    cred = DefaultAzureCredential()
    return cred.get_token(resource.rstrip("/") + "/.default").token


def fetch_environments(token: str) -> list[dict[str, Any]]:
    url = f"{PPAC_BASE}{ENV_PATH}"
    resp = requests.get(
        url,
        params={"api-version": API_VERSION},
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json().get("value", [])


def classify_environment(env: dict[str, Any]) -> dict[str, Any]:
    """Suggest a zone classification hint based on PPAC properties."""
    props = env.get("properties", {})
    sku = props.get("environmentSku", "Unknown")
    protection = props.get("governanceConfiguration", {}).get("protectionLevel", "None")
    is_managed = protection in {"Basic", "Standard"}

    # Heuristic mapping (customers should override per their firm's topology)
    if sku == "Production" and is_managed:
        zone_hint = 1   # Enterprise candidate
    elif sku in {"Sandbox", "Production"}:
        zone_hint = 2   # Team candidate
    else:
        zone_hint = 3   # Personal / dev / trial

    return {
        "id": env.get("id"),
        "name": props.get("displayName"),
        "sku": sku,
        "managed": is_managed,
        "protectionLevel": protection,
        "region": props.get("azureRegion"),
        "zoneHint": zone_hint,
        "expressPathEligible": (zone_hint == 3),
    }


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    p = argparse.ArgumentParser(description="Auto-detect Power Platform environments for intake routing")
    p.add_argument("--output", type=Path, required=True, help="Output JSON file")
    p.add_argument("--token-source", choices=["mi", "cli"], default="mi", help="Token source: managed identity (default) or azure-cli")
    args = p.parse_args()

    LOG.info("Acquiring PPAC token via %s", args.token_source)
    token = get_token_via_managed_identity() if args.token_source == "mi" else get_token_via_cli()

    LOG.info("Fetching environments from PPAC")
    envs = fetch_environments(token)
    LOG.info("Retrieved %d environments", len(envs))

    classified = [classify_environment(e) for e in envs]
    eligible = [c for c in classified if c["expressPathEligible"]]
    LOG.info("Express-path eligible: %d of %d", len(eligible), len(classified))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(classified, indent=2), encoding="utf-8")
    LOG.info("Wrote %s", args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
