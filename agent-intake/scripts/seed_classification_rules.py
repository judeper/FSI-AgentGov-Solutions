#!/usr/bin/env python3
"""Express-path classification rules for agent-intake v0.2.0-preview.

Computes tier, zone, retention class, and decision path from the 6 trigger
answers and the maker-facing audience field.

The Power Automate router flow (`docs/flow-configuration.md`, Flow 1) calls
this logic via a child flow OR mirrors it inline. This script is the canonical
reference and can be invoked standalone for unit testing or batch
reclassification of historical requests.

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
    "fsi_t1initiatesfinancialtxn",
    "fsi_t2customerfacing",
    "fsi_t3autonomousunmonitored",
    "fsi_t4handlesnpi",
    "fsi_t5handlesmnpi",
    "fsi_t6crossborderdata",
)

def load_policy(path: Path = _DEFAULT_POLICY) -> dict[str, Any]:
    """Load classification policy defaults from YAML."""
    with path.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def field_value(request: dict[str, Any], field: str) -> Any:
    """Return a request value by canonical Dataverse logical name."""
    return request.get(field, "")


def is_positive_answer(value: Any) -> bool:
    """Treat Yes and Not sure as routing-trigger hits."""
    return str(value or "").strip().lower() in {"yes", "not sure", "not-sure"}


def trigger_hits(request: dict[str, Any]) -> int:
    """Count trigger answers that are 'Yes' or 'Not sure'."""
    return sum(1 for field in TRIGGER_FIELDS if is_positive_answer(field_value(request, field)))


def classify(request: dict[str, Any], policy: dict[str, Any]) -> dict[str, Any]:
    """Return classification dict: tier, zone, decisionPath, retentionLabel, routing.

    Express-path criteria:
      - All 6 trigger answers == "No"
      - Intended audience maps to Zone 3 (personal)

    Any trigger hit or wider audience is captured but routed to Standard/Full
    follow-up rather than auto-approval in this preview.

    Cross-border default-deny:
      - If T6 == "Yes" and maker country != data-residency country, route to
        DefaultDeny unless Privacy has set `fsi_privacyoverride`.
    """
    hits = trigger_hits(request)

    audience = (
        request.get("fsi_intendedaudience")
        or request.get("fsi_intendedaudiencelabel")
        or request.get("fsi_intendedaudienceLabel")
        or "Just me"
    )
    audience_zone = int(policy["audience_to_zone"].get(str(audience), 3))

    if hits == 0:
        tier = 3
        zone = audience_zone
        decision_path = "Express" if audience_zone == 3 else "DeferredOutOfScope"
    else:
        decision_path = "DeferredOutOfScope"
        tier = 1 if hits >= 3 else 2
        zone = audience_zone

    crossborder = is_positive_answer(field_value(request, "fsi_t6crossborderdata"))
    if crossborder:
        maker_country = (request.get("fsi_makercountry") or "").upper()
        data_country = (request.get("fsi_dataresidencycountry") or maker_country).upper()
        if maker_country and maker_country != data_country and not request.get("fsi_privacyoverride"):
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
        "dlpConnectorGroup": policy["dlp_connector_group"].get(retention_key, "nonBusinessDataOnly"),
    }


def _self_test() -> int:
    policy = load_policy()
    cases = [
        {
            "name": "all-no personal Express",
            "input": {f: "No" for f in TRIGGER_FIELDS} | {
                "fsi_intendedaudience": "Just me",
                "fsi_makercountry": "US",
            },
            "expect_path": "Express",
            "expect_tier": 3,
            "expect_zone": 3,
        },
        {
            "name": "all-no team -> deferred",
            "input": {f: "No" for f in TRIGGER_FIELDS} | {
                "fsi_intendedaudience": "My team",
                "fsi_makercountry": "US",
            },
            "expect_path": "DeferredOutOfScope",
            "expect_tier": 3,
            "expect_zone": 2,
        },
        {
            "name": "MNPI yes -> deferred",
            "input": {f: "No" for f in TRIGGER_FIELDS} | {
                "fsi_t5handlesmnpi": "Yes",
                "fsi_intendedaudience": "My team",
                "fsi_makercountry": "US",
            },
            "expect_path": "DeferredOutOfScope",
        },
        {
            "name": "cross-border default-deny",
            "input": {f: "No" for f in TRIGGER_FIELDS} | {
                "fsi_t6crossborderdata": "Yes",
                "fsi_intendedaudience": "Just me",
                "fsi_makercountry": "US",
                "fsi_dataresidencycountry": "EU",
            },
            "expect_path": "DefaultDeny",
        },
    ]
    failed = 0
    for case in cases:
        result = classify(case["input"], policy)
        ok = result["decisionPath"] == case["expect_path"]
        if "expect_tier" in case:
            ok = ok and result["tier"] == case["expect_tier"]
        if "expect_zone" in case:
            ok = ok and result["zone"] == case["expect_zone"]
        marker = "PASS" if ok else "FAIL"
        print(f"[{marker}] {case['name']}: {result}")
        if not ok:
            failed += 1
    return 1 if failed else 0


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Classify an agent-intake request (Express path)")
    parser.add_argument("--request-json", type=Path, help="Path to a JSON file with request fields")
    parser.add_argument("--policy", type=Path, default=_DEFAULT_POLICY, help="Path to policy-lookup-tables.yaml")
    parser.add_argument("--self-test", action="store_true", help="Run built-in test cases and exit")
    args = parser.parse_args()

    if args.self_test:
        return _self_test()
    if not args.request_json:
        parser.error("--request-json is required (or use --self-test)")
    policy = load_policy(args.policy)
    with args.request_json.open(encoding="utf-8") as fh:
        request = json.load(fh)
    result = classify(request, policy)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
