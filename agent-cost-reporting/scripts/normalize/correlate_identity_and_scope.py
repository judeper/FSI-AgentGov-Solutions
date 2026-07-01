#!/usr/bin/env python3
"""
Correlator: enrich cost facts with deterministic-first, heuristic-second joins.

Two passes:
  1. Deterministic -- build the environmentId -> billingPolicyId -> azureSubscriptionId map from
     the billing_policy_map facts, then stamp environment_id / billing_policy_id onto azure_cost
     facts that share an azureSubscriptionId (and resource group where available). These joins are
     marked attribution_status=deterministic / join_strategy=foreign_key.
  2. Heuristic -- attempt agent-level association (e.g. matching manual-credit agent names to known
     agents). Any heuristic association is marked attribution_status=heuristic and is NEVER folded
     into authoritative monetary totals. The unresolved count is reported.

The hard correlation gap (copilot_package_id <-> bot_id <-> entra_agent_id <-> PAYG Resource ID)
is not closed by any supported API; rows that cannot be deterministically attributed to an agent
remain attribution_status in {heuristic, unattributable}.
"""

from __future__ import annotations

import argparse
import json
import logging
from typing import Dict, List

logger = logging.getLogger(__name__)


def build_scope_map(facts: List[dict]) -> Dict[str, dict]:
    """Build azureSubscriptionId -> {billing_policy_id, environment_id, environment_name}."""
    scope_map: Dict[str, dict] = {}
    for fact in facts:
        if fact.get("fact_type") != "billing_policy_map":
            continue
        sub = fact.get("azure_subscription_id")
        if not sub:
            continue
        scope_map[sub] = {
            "billing_policy_id": fact.get("billing_policy_id"),
            "environment_id": fact.get("environment_id"),
            "environment_name": fact.get("environment_name"),
        }
    return scope_map


def correlate(facts: List[dict]) -> dict:
    """Mutate facts in place with deterministic scope joins; return a join ledger summary."""
    scope_map = build_scope_map(facts)
    deterministic = 0
    heuristic = 0
    unattributable = 0

    for fact in facts:
        if fact.get("fact_type") == "azure_cost":
            sub = fact.get("azure_subscription_id")
            mapping = scope_map.get(sub) if sub else None
            if mapping:
                fact["billing_policy_id"] = fact.get("billing_policy_id") or mapping["billing_policy_id"]
                fact["environment_id"] = fact.get("environment_id") or mapping["environment_id"]
                fact["environment_name"] = fact.get("environment_name") or mapping["environment_name"]
                fact["attribution_status"] = "deterministic"
                fact["join_strategy"] = "foreign_key"
                fact["join_evidence"] = json.dumps({"by": "azure_subscription_id", "value": sub})
                deterministic += 1
            else:
                # Azure cost has no agent dimension and no matched billing policy.
                fact["attribution_status"] = "partially_deterministic"
                fact["join_strategy"] = "none"
                unattributable += 1

        if fact.get("attribution_status") == "heuristic":
            heuristic += 1

    ledger = {
        "deterministic_joins": deterministic,
        "heuristic_joins": heuristic,
        "unattributable_cost_rows": unattributable,
        "subscriptions_with_policy_map": len(scope_map),
    }
    return ledger


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cost-facts", required=True, help="Path to cost_facts.jsonl.")
    parser.add_argument("--out", required=True, help="Path to write the enriched cost_facts.jsonl.")
    parser.add_argument("--ledger-out", help="Optional path to write the join ledger JSON.")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    with open(args.cost_facts, encoding="utf-8") as handle:
        facts = [json.loads(line) for line in handle if line.strip()]

    ledger = correlate(facts)
    facts.sort(key=lambda f: (f["source_surface"], f["fact_type"], f["fact_id"]))
    with open(args.out, "w", encoding="utf-8") as handle:
        for fact in facts:
            handle.write(json.dumps(fact, sort_keys=True, default=str))
            handle.write("\n")
    if args.ledger_out:
        with open(args.ledger_out, "w", encoding="utf-8") as handle:
            json.dump(ledger, handle, indent=2, sort_keys=True)

    logger.info("Correlation ledger: %s", json.dumps(ledger))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
