#!/usr/bin/env python3
"""Simulate DLP policy outcome for a proposed connector set.

Pulls tenant DLP policies via PPAC, then evaluates a candidate connector
list against each policy's connector groups (General / Confidential /
Blocked). Returns the worst-case outcome — used by the router flow to flag
intake requests that would be DLP-blocked in their target environment.

Endpoint verified in `research/04-api-verification-spike.md`:
  GET https://api.bap.microsoft.com
      /providers/PowerPlatform.Governance/v2/policies?api-version=2018-01-01

Authentication: managed-identity-first. See companion script
`autodetect_environments.py` for token-acquisition helpers.

Usage:
  python autodetect_dlp_simulation.py \
      --connectors connectors.json \
      --environment-id /providers/.../environments/<envid> \
      --output simulation.json
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Any

import requests

from autodetect_environments import (
    PPAC_BASE,
    PPAC_RESOURCE,
    get_token_via_cli,
    get_token_via_managed_identity,
)

LOG = logging.getLogger("agent-intake.autodetect.dlp")

DLP_PATH = "/providers/PowerPlatform.Governance/v2/policies"
API_VERSION = "2018-01-01"


def fetch_policies(token: str) -> list[dict[str, Any]]:
    url = f"{PPAC_BASE}{DLP_PATH}"
    resp = requests.get(
        url,
        params={"api-version": API_VERSION},
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json().get("value", [])


def policy_applies_to_env(policy: dict[str, Any], environment_id: str) -> bool:
    env_type = policy.get("environmentType")
    if env_type == "AllEnvironments":
        return True
    if env_type == "OnlyEnvironments":
        return any(e.get("id", "").lower() == environment_id.lower() for e in policy.get("environments", []))
    if env_type == "ExceptEnvironments":
        return not any(e.get("id", "").lower() == environment_id.lower() for e in policy.get("environments", []))
    return False


def simulate(policies: list[dict[str, Any]], environment_id: str, connectors: list[str]) -> dict[str, Any]:
    """Return per-connector classification under the highest-precedence applicable policy."""
    findings: list[dict[str, Any]] = []
    blocked: list[str] = []
    confidential: list[str] = []
    general: list[str] = []
    unknown: list[str] = []

    applicable = [p for p in policies if policy_applies_to_env(p, environment_id)]
    LOG.info("Found %d applicable policies for env %s", len(applicable), environment_id)

    for connector in connectors:
        worst = "general"
        matched_policy = None
        for policy in applicable:
            for group in policy.get("connectorGroups", []):
                classification = group.get("classification", "General").lower()
                for c in group.get("connectors", []):
                    cid = (c.get("id") or c.get("name") or "").lower()
                    if connector.lower() in cid or cid.endswith("/" + connector.lower()):
                        if classification == "blocked":
                            worst = "blocked"
                            matched_policy = policy.get("displayName")
                            break
                        if classification == "confidential" and worst != "blocked":
                            worst = "confidential"
                            matched_policy = policy.get("displayName")
                if worst == "blocked":
                    break
            if worst == "blocked":
                break

        finding = {"connector": connector, "classification": worst, "policy": matched_policy}
        findings.append(finding)
        if worst == "blocked":
            blocked.append(connector)
        elif worst == "confidential":
            confidential.append(connector)
        elif worst == "general":
            general.append(connector)
        else:
            unknown.append(connector)

    outcome = "blocked" if blocked else ("confidential-only" if confidential else "general-allowed")
    return {
        "environmentId": environment_id,
        "applicablePolicies": [p.get("displayName") for p in applicable],
        "outcome": outcome,
        "blockedConnectors": blocked,
        "confidentialConnectors": confidential,
        "generalConnectors": general,
        "findings": findings,
    }


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    p = argparse.ArgumentParser(description="Simulate DLP outcome for a proposed connector set")
    p.add_argument("--connectors", type=Path, required=True, help="JSON list of connector names/IDs")
    p.add_argument("--environment-id", required=True, help="Target Power Platform environment ID")
    p.add_argument("--output", type=Path, required=True, help="Output JSON file")
    p.add_argument("--token-source", choices=["mi", "cli"], default="mi")
    args = p.parse_args()

    token = get_token_via_managed_identity() if args.token_source == "mi" else get_token_via_cli()
    policies = fetch_policies(token)
    LOG.info("Fetched %d DLP policies", len(policies))

    connectors = json.loads(args.connectors.read_text(encoding="utf-8"))
    if not isinstance(connectors, list):
        raise SystemExit("connectors.json must contain a JSON list of strings")

    result = simulate(policies, args.environment_id, connectors)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    LOG.info("Wrote %s — outcome: %s", args.output, result["outcome"])
    return 0 if result["outcome"] != "blocked" else 2


if __name__ == "__main__":
    sys.exit(main())
