#!/usr/bin/env python3
"""Simulate Power Platform data policy outcome for a proposed connector set.

Pulls tenant data policies via PPAC, then evaluates a candidate connector list
against Business, Non-business, and Blocked connector groups. Returns the
worst-case outcome for the target environment.

Endpoint used:
  GET https://api.bap.microsoft.com
      /providers/PowerPlatform.Governance/v2/policies?api-version=2018-01-01

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
    get_token_via_cli,
    get_token_via_managed_identity,
)

LOG = logging.getLogger("agent-intake.autodetect.dlp")

DLP_PATH = "/providers/PowerPlatform.Governance/v2/policies"
API_VERSION = "2018-01-01"

CLASSIFICATION_ALIASES = {
    "business": "business",
    "businessdataonly": "business",
    "confidential": "business",
    "non-business": "nonbusiness",
    "nonbusiness": "nonbusiness",
    "nonbusinessdataonly": "nonbusiness",
    "non-business data only": "nonbusiness",
    "default": "nonbusiness",
    "general": "nonbusiness",
    "blocked": "blocked",
    "blockedconnectors": "blocked",
}

DICT_GROUP_KEYS = {
    "businessDataOnly": "business",
    "nonBusinessDataOnly": "nonbusiness",
    "blockedConnectors": "blocked",
}


def fetch_policies(token: str) -> list[dict[str, Any]]:
    """Fetch Power Platform data policies from PPAC."""
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
    """Return whether the policy scope applies to the target environment."""
    env_type = policy.get("environmentType")
    if env_type in {None, "AllEnvironments"}:
        return True
    environments = policy.get("environments", [])
    if env_type == "OnlyEnvironments":
        return any(str(e.get("id", "")).lower() == environment_id.lower() for e in environments)
    if env_type == "ExceptEnvironments":
        return not any(str(e.get("id", "")).lower() == environment_id.lower() for e in environments)
    return False


def _connector_id(connector: Any) -> str:
    if isinstance(connector, str):
        return connector.lower()
    if isinstance(connector, dict):
        return str(
            connector.get("id")
            or connector.get("name")
            or connector.get("connectorId")
            or connector.get("apiName")
            or ""
        ).lower()
    return str(connector or "").lower()


def _normalize_classification(value: str) -> str:
    key = value.replace(" ", "").replace("_", "").replace("-", "").lower()
    return CLASSIFICATION_ALIASES.get(key, CLASSIFICATION_ALIASES.get(value.lower(), "unknown"))


def connector_groups(policy: dict[str, Any]) -> dict[str, set[str]]:
    """Extract connector IDs grouped as business/nonbusiness/blocked.

    Supports both the current dictionary shape (`businessDataOnly`,
    `nonBusinessDataOnly`, `blockedConnectors`) and older list-shaped policy
    exports with a `classification` field.
    """
    groups: dict[str, set[str]] = {"business": set(), "nonbusiness": set(), "blocked": set()}
    raw_groups = policy.get("connectorGroups") or {}

    if isinstance(raw_groups, dict):
        for key, classification in DICT_GROUP_KEYS.items():
            raw_connectors = raw_groups.get(key, [])
            if isinstance(raw_connectors, dict):
                raw_connectors = raw_connectors.get("connectors", [])
            for connector in raw_connectors or []:
                cid = _connector_id(connector)
                if cid:
                    groups[classification].add(cid)
    elif isinstance(raw_groups, list):
        for group in raw_groups:
            classification = _normalize_classification(str(group.get("classification", "nonbusiness")))
            if classification not in groups:
                classification = "nonbusiness"
            for connector in group.get("connectors", []) or []:
                cid = _connector_id(connector)
                if cid:
                    groups[classification].add(cid)

    # Some API variants expose blocked connectors at the policy root.
    for connector in policy.get("blockedConnectors", []) or []:
        cid = _connector_id(connector)
        if cid:
            groups["blocked"].add(cid)
    return groups


def _matches(connector: str, candidate_ids: set[str]) -> bool:
    c = connector.lower()
    return any(c == candidate or c in candidate or candidate.endswith("/" + c) for candidate in candidate_ids)


def simulate(policies: list[dict[str, Any]], environment_id: str, connectors: list[str]) -> dict[str, Any]:
    """Return per-connector classification and policy outcome."""
    findings: list[dict[str, Any]] = []
    blocked: list[str] = []
    business: list[str] = []
    nonbusiness: list[str] = []
    unknown: list[str] = []

    applicable = [p for p in policies if policy_applies_to_env(p, environment_id)]
    LOG.info("Found %d applicable policies for env %s", len(applicable), environment_id)

    for connector in connectors:
        matched_policy = None
        classification = "unknown"
        for policy in applicable:
            groups = connector_groups(policy)
            if _matches(connector, groups["blocked"]):
                classification = "blocked"
                matched_policy = policy.get("displayName")
                break
            if _matches(connector, groups["business"]):
                classification = "business"
                matched_policy = policy.get("displayName")
            elif _matches(connector, groups["nonbusiness"]):
                classification = "nonbusiness"
                matched_policy = policy.get("displayName")

        findings.append({"connector": connector, "classification": classification, "policy": matched_policy})
        if classification == "blocked":
            blocked.append(connector)
        elif classification == "business":
            business.append(connector)
        elif classification == "nonbusiness":
            nonbusiness.append(connector)
        else:
            unknown.append(connector)

    mixed = bool(business and nonbusiness)
    outcome = "blocked" if blocked else ("dlp-violation" if mixed else ("allowed" if not unknown else "review"))
    return {
        "environmentId": environment_id,
        "applicablePolicies": [p.get("displayName") for p in applicable],
        "outcome": outcome,
        "blockedConnectors": blocked,
        "businessConnectors": business,
        "nonBusinessConnectors": nonbusiness,
        "unknownConnectors": unknown,
        "mixedBusinessAndNonBusiness": mixed,
        "findings": findings,
    }


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Simulate DLP outcome for a proposed connector set")
    parser.add_argument("--connectors", type=Path, required=True, help="JSON list of connector names/IDs")
    parser.add_argument("--environment-id", required=True, help="Target Power Platform environment ID")
    parser.add_argument("--output", type=Path, required=True, help="Output JSON file")
    parser.add_argument("--token-source", choices=["mi", "cli"], default="mi")
    args = parser.parse_args()

    token = get_token_via_managed_identity() if args.token_source == "mi" else get_token_via_cli()
    policies = fetch_policies(token)
    LOG.info("Fetched %d DLP policies", len(policies))

    connectors = json.loads(args.connectors.read_text(encoding="utf-8"))
    if not isinstance(connectors, list) or not all(isinstance(c, str) for c in connectors):
        raise SystemExit("connectors.json must contain a JSON list of strings")

    result = simulate(policies, args.environment_id, connectors)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    LOG.info("Wrote %s — outcome: %s", args.output, result["outcome"])
    return 0 if result["outcome"] in {"allowed", "review"} else 2


if __name__ == "__main__":
    sys.exit(main())
