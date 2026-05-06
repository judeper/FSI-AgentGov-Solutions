#!/usr/bin/env python3
"""Express-path classification rules for agent-intake v0.1.0-preview.

Computes tier, zone, retention class, and decision-path from the 6 trigger
answers and the audience field captured by the maker-facing portal.

The Power Automate router flow (`docs/flow-configuration.md`, Flow 1) calls
this logic via a child flow OR mirrors it inline. This script is the
canonical reference and can be invoked standalone for unit testing or
batch reclassification of historical requests.

Usage:
  python seed_classification_rules.py --request-json input.json
  python seed_classification_rules.py --self-test
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Any

import yaml

LOG = logging.getLogger("agent-intake.classify")

_SCRIPT_DIR = Path(__file__).resolve().parent
_DEFAULT_POLICY = _SCRIPT_DIR.parent / "templates" / "policy-lookup-tables.yaml"

TRIGGER_FIELDS = (
    "fsi_t1_initiates_financial_txn",
    "fsi_t2_customer_facing",
    "fsi_t3_autonomous_unmonitored",
    "fsi_t4_handles_npi",
    "fsi_t5_handles_mnpi",
    "fsi_t6_crossborder_data",
)


def load_policy(path: Path = _DEFAULT_POLICY) -> dict[str, Any]:
    with path.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def trigger_hits(request: dict[str, Any]) -> int:
    """Count trigger answers that are 'Yes' or 'Not sure'."""
    return sum(
        1 for f in TRIGGER_FIELDS
        if str(request.get(f, "")).strip().lower() in {"yes", "not sure"}
    )


def classify(request: dict[str, Any], policy: dict[str, Any]) -> dict[str, Any]:
    """Return classification dict: tier, zone, decisionPath, retentionLabel, routing.

    Express-path criteria (locked decision #1):
      - All 6 trigger answers == "No" → Tier 3 + Zone 3 + Express
      - Any trigger == "Yes"/"Not sure" → DeferredOutOfScope (v0.2.0 handles)

    Cross-border default-deny (OQ-D):
      - If T6 == "Yes" and maker_country != data_residency_country
        → DefaultDeny unless Privacy override flag set on the request
    """
    hits = trigger_hits(request)

    audience = request.get("fsi_intendedaudienceLabel") or request.get("fsi_intendedaudience") or "Just me"
    audience_zone = policy["audience_to_zone"].get(audience, 3)

    if hits == 0:
        decision_path = "Express"
        tier = 3
        zone = max(audience_zone, 3) if audience_zone == 3 else min(audience_zone, 3)
    else:
        decision_path = "DeferredOutOfScope"
        tier = 1 if hits >= 3 else 2
        zone = audience_zone

    # Cross-border check
    crossborder = str(request.get("fsi_t6_crossborder_data", "")).strip().lower() == "yes"
    if crossborder:
        maker_country = (request.get("fsi_makercountry") or "").upper()
        data_country = (request.get("fsi_dataresidencycountry") or maker_country).upper()
        if maker_country and maker_country != data_country:
            if not request.get("fsi_privacyoverride"):
                action = policy["data_residency"].get("default_action", "deny")
                if action == "deny":
                    decision_path = "DefaultDeny"

    retention_key = f"tier_{tier}"
    retention_label = policy["retention_labels"].get(retention_key, "FSI-AgentIntake-7yr")

    routing = policy["zone_routing"].get(f"zone_{zone}", {})

    return {
        "decisionPath": decision_path,
        "tier": tier,
        "zone": zone,
        "triggerHits": hits,
        "retentionLabel": retention_label,
        "routing": routing,
        "managedEnvironment": policy["managed_environment"].get(retention_key, "recommended"),
        "dlpConnectorGroup": policy["dlp_connector_group"].get(retention_key, "General"),
    }


def _self_test() -> int:
    policy = load_policy()
    cases = [
        {
            "name": "all-no Express",
            "input": {f: "No" for f in TRIGGER_FIELDS} | {
                "fsi_intendedaudienceLabel": "Just me",
                "fsi_makercountry": "US",
            },
            "expect_path": "Express",
            "expect_tier": 3,
        },
        {
            "name": "MNPI yes -> deferred",
            "input": {f: "No" for f in TRIGGER_FIELDS} | {
                "fsi_t5_handles_mnpi": "Yes",
                "fsi_intendedaudienceLabel": "My team",
                "fsi_makercountry": "US",
            },
            "expect_path": "DeferredOutOfScope",
        },
        {
            "name": "cross-border default-deny",
            "input": {f: "No" for f in TRIGGER_FIELDS} | {
                "fsi_t6_crossborder_data": "Yes",
                "fsi_intendedaudienceLabel": "Just me",
                "fsi_makercountry": "US",
                "fsi_dataresidencycountry": "EU",
            },
            "expect_path": "DefaultDeny",
        },
    ]
    failed = 0
    for c in cases:
        result = classify(c["input"], policy)
        ok = result["decisionPath"] == c["expect_path"]
        if "expect_tier" in c:
            ok = ok and result["tier"] == c["expect_tier"]
        marker = "PASS" if ok else "FAIL"
        print(f"[{marker}] {c['name']}: {result}")
        if not ok:
            failed += 1
    return 1 if failed else 0


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    p = argparse.ArgumentParser(description="Classify an agent-intake request (Express path)")
    p.add_argument("--request-json", type=Path, help="Path to a JSON file with request fields")
    p.add_argument("--policy", type=Path, default=_DEFAULT_POLICY, help="Path to policy-lookup-tables.yaml")
    p.add_argument("--self-test", action="store_true", help="Run built-in test cases and exit")
    args = p.parse_args()

    if args.self_test:
        return _self_test()
    if not args.request_json:
        p.error("--request-json is required (or use --self-test)")
    policy = load_policy(args.policy)
    with args.request_json.open(encoding="utf-8") as fh:
        request = json.load(fh)
    result = classify(request, policy)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
