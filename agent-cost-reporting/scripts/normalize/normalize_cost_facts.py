#!/usr/bin/env python3
"""
Normalizer: raw extracts -> normalized cost-fact dataset.

Reads every raw_*.jsonl extract produced by the collectors and maps each source row to a
cost_fact record (see schemas/cost_fact.schema.json), stamping provenance, confidence, and
attribution metadata. Emits cost_facts.jsonl and cost_facts.csv with deterministic ordering so
reruns over identical inputs are byte-stable.

Mapping is per source_surface. Surfaces whose response schema is not yet verified against a live
tenant (e.g. Power Platform capacity preview, Purview audit records) are passed through as
audit/metadata facts and flagged for review rather than dropped.
"""

from __future__ import annotations

import argparse
import csv
import glob
import json
import logging
import os
import sys
from typing import Optional

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
import cost_report_lib as lib  # noqa: E402

logger = logging.getLogger(__name__)

# Surface inferred from the raw extract filename prefix raw_{surface}_{snapshot}.jsonl
FILENAME_SURFACE_MAP = {
    lib.SURFACE_AZURE_COST: ("azure_cost", "authoritative_api"),
    lib.SURFACE_GRAPH_REPORTS: ("copilot_usage", "authoritative_api"),
    lib.SURFACE_GRAPH_LICENSES: ("license_inventory", "authoritative_api"),
    "powerplatform_billing_policies": ("billing_policy_map", "authoritative_api"),
    "powerplatform_billing_policy_environments": ("billing_policy_map", "authoritative_api"),
    "powerplatform_capacity_allocations_preview": ("billing_policy_map", "supplementary_audit"),
    lib.SURFACE_PURVIEW_AUDIT: ("audit_interaction", "supplementary_audit"),
    lib.SURFACE_MANUAL_CSV: ("manual_credit_consumption", "manual"),
}


def _base_fact(surface: str, fact_type: str, confidence: str, record_id: str, period: tuple, snapshot_id: str, tenant_id: Optional[str]) -> dict:
    """Create a cost_fact dict pre-populated with required provenance fields."""
    start_utc, end_utc = period
    return {
        "fact_id": lib.fact_id(surface, record_id, start_utc, fact_type),
        "snapshot_id": snapshot_id,
        "tenant_id": tenant_id,
        "fact_type": fact_type,
        "source_surface": surface,
        "source_endpoint": None,
        "source_method": "manual_override" if surface == lib.SURFACE_MANUAL_CSV else "api",
        "source_record_id": record_id,
        "collection_started_utc": None,
        "collection_completed_utc": None,
        "data_freshness_utc": None,
        "freshness_note": None,
        "confidence_class": confidence,
        "confidence_score": None,
        "attribution_status": "deterministic",
        "join_strategy": "native_id",
        "join_evidence": None,
        "period_start_utc": start_utc,
        "period_end_utc": end_utc,
        "currency_code": None,
        "amount": None,
        "quantity": None,
        "quantity_unit": None,
        "payment_model": None,
        "azure_scope": None,
        "azure_subscription_id": None,
        "azure_resource_group": None,
        "billing_policy_id": None,
        "environment_id": None,
        "environment_name": None,
        "agent_platform": None,
        "agent_id": None,
        "bot_id": None,
        "entra_agent_id": None,
        "copilot_package_id": None,
        "user_id": None,
        "user_upn": None,
        "sku_id": None,
        "sku_part_number": None,
        "meter_id": None,
        "meter_name": None,
        "meter_category": None,
        "manual_artifact_name": None,
        "manual_artifact_sha256": None,
        "row_note": None,
    }


def _surface_from_filename(path: str) -> Optional[str]:
    name = os.path.basename(path)
    if not name.startswith("raw_"):
        return None
    stem = name[len("raw_"):].rsplit("_", 1)[0]
    return stem


def _map_row(surface_key: str, raw: dict, period: tuple, snapshot_id: str, tenant_id: Optional[str]) -> dict:
    fact_type, confidence = FILENAME_SURFACE_MAP.get(surface_key, ("audit_interaction", "heuristic_join"))
    canonical_surface = (
        lib.SURFACE_POWERPLATFORM if surface_key.startswith("powerplatform") else surface_key
    )
    record_id = lib.stable_record_id(raw.get("id") or raw.get("MeterId") or raw.get("skuId"), raw)
    fact = _base_fact(canonical_surface, fact_type, confidence, record_id, period, snapshot_id, tenant_id)

    if fact_type == "azure_cost":
        fact["amount"] = raw.get("Cost") or raw.get("PreTaxCost") or raw.get("costInBillingCurrency")
        fact["currency_code"] = raw.get("Currency") or raw.get("billingCurrency") or "USD"
        fact["meter_id"] = raw.get("MeterId") or raw.get("meterId")
        fact["meter_name"] = raw.get("Meter") or raw.get("meterName")
        fact["meter_category"] = raw.get("ServiceName") or raw.get("meterCategory")
        fact["azure_resource_group"] = raw.get("ResourceGroupName") or raw.get("resourceGroup")
        fact["azure_subscription_id"] = raw.get("subscriptionId") or raw.get("SubscriptionId")
        fact["azure_scope"] = raw.get("_scope")
        fact["payment_model"] = "payg"
    elif fact_type == "license_inventory":
        prepaid = (raw.get("prepaidUnits") or {}).get("enabled")
        fact["quantity"] = raw.get("consumedUnits") if raw.get("consumedUnits") is not None else prepaid
        fact["quantity_unit"] = "seats"
        fact["sku_id"] = raw.get("skuId")
        fact["sku_part_number"] = raw.get("skuPartNumber")
        fact["payment_model"] = "seat"
    elif fact_type == "manual_credit_consumption":
        fact["quantity"] = raw.get("credits_or_messages_consumed")
        fact["quantity_unit"] = raw.get("quantity_unit")
        fact["agent_id"] = raw.get("agent_id")
        fact["user_upn"] = raw.get("user_or_group_scope")
        fact["manual_artifact_name"] = raw.get("manual_artifact_name")
        fact["manual_artifact_sha256"] = raw.get("manual_artifact_sha256")
        fact["attribution_status"] = "partially_deterministic"
        fact["join_strategy"] = "inferred_name_owner_env"
        fact["row_note"] = "Manual export; per-agent credit consumption has no supported API."
    elif fact_type == "billing_policy_map":
        fact["billing_policy_id"] = raw.get("billingPolicyId") or raw.get("id")
        fact["environment_id"] = raw.get("environmentId")
        fact["environment_name"] = raw.get("environmentName")
        fact["azure_subscription_id"] = (raw.get("billingInstrument") or {}).get("subscriptionId") or raw.get("azureSubscriptionId")
    elif fact_type == "copilot_usage":
        fact["quantity"] = 1
        fact["quantity_unit"] = "interactions"
        fact["user_upn"] = raw.get("userPrincipalName") or raw.get("User Principal Name")
        fact["agent_platform"] = "m365_copilot"
    elif fact_type == "audit_interaction":
        fact["quantity_unit"] = "interactions"
        fact["confidence_class"] = "supplementary_audit"
        fact["attribution_status"] = "heuristic"
        fact["join_strategy"] = "inferred_name_owner_env"
        fact["row_note"] = "Supplementary audit-log signal; not cost-authoritative."
    return fact


def normalize(in_dir: str, snapshot_id: str, period: tuple, tenant_id: Optional[str] = None) -> list:
    """Read all raw extracts in in_dir and return normalized cost_fact dicts."""
    facts: list = []
    for path in sorted(glob.glob(os.path.join(in_dir, "raw_*.jsonl"))):
        surface_key = _surface_from_filename(path)
        if not surface_key:
            continue
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                raw = json.loads(line)
                if isinstance(raw, dict):
                    facts.append(_map_row(surface_key, raw, period, snapshot_id, tenant_id))
    facts.sort(key=lambda f: (f["source_surface"], f["fact_type"], f["fact_id"]))
    return facts


def write_outputs(facts: list, out_dir: str) -> tuple:
    """Write cost_facts.jsonl and cost_facts.csv; return their paths."""
    os.makedirs(out_dir, exist_ok=True)
    jsonl_path = os.path.join(out_dir, "cost_facts.jsonl")
    csv_path = os.path.join(out_dir, "cost_facts.csv")
    with open(jsonl_path, "w", encoding="utf-8") as handle:
        for fact in facts:
            handle.write(json.dumps(fact, sort_keys=True, default=str))
            handle.write("\n")
    fieldnames = sorted({k for fact in facts for k in fact}) if facts else []
    with open(csv_path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for fact in facts:
            writer.writerow(fact)
    return jsonl_path, csv_path


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--in-dir", required=True, help="Directory of raw_*.jsonl extracts.")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--snapshot-id", required=True)
    parser.add_argument("--period-start-utc", required=True)
    parser.add_argument("--period-end-utc", required=True)
    parser.add_argument("--tenant-id", help="Tenant id stamped onto every fact for cross-surface joins.")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    facts = normalize(args.in_dir, args.snapshot_id, (args.period_start_utc, args.period_end_utc), args.tenant_id)
    jsonl_path, csv_path = write_outputs(facts, args.out_dir)
    logger.info("Normalized %d cost-fact row(s) -> %s, %s", len(facts), jsonl_path, csv_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
