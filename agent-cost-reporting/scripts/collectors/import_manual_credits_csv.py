#!/usr/bin/env python3
"""
Importer: manual Copilot Credits CSV (per-agent credit consumption).

This is the documented MANUAL placeholder for the single most important cost-attribution data
point -- per-agent credit consumption -- which has no supported API egress today. An admin
exports the CSV from the Microsoft 365 admin center (Reports > Usage > Copilot > Credits) or the
Power Platform admin center, and this importer validates it, computes a SHA-256 of the source
file, maps the (version-variable) headers to the manual_credit_import schema, and tags every row
source_method=ui_export_csv / confidence_class=manual.

Malformed files are rejected with an explicit header-diff so drift is caught immediately.
"""

from __future__ import annotations

import argparse
import csv
import logging
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
import cost_report_lib as lib  # noqa: E402

logger = logging.getLogger(__name__)

# Map observed portal header variants -> canonical schema field. Extend as new exports appear.
HEADER_ALIASES = {
    "agent": "agent_name",
    "agent name": "agent_name",
    "agentid": "agent_id",
    "agent id": "agent_id",
    "user": "user_or_group_scope",
    "user or group": "user_or_group_scope",
    "service": "service",
    "billing policy": "policy_or_environment_scope",
    "environment": "policy_or_environment_scope",
    "credits used": "credits_or_messages_consumed",
    "credits consumed": "credits_or_messages_consumed",
    "messages": "credits_or_messages_consumed",
}

REQUIRED_FIELDS = {"agent_name", "credits_or_messages_consumed", "quantity_unit"}


def _normalize_header(header: str) -> str:
    key = header.strip().lower()
    return HEADER_ALIASES.get(key, key.replace(" ", "_"))


def import_csv(path: str, unit: str) -> list:
    """Parse and map the manual CSV; raise ValueError with a header diff on mismatch."""
    with open(path, newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        mapped_headers = {_normalize_header(h) for h in (reader.fieldnames or [])}
        rows = []
        for raw in reader:
            row = {_normalize_header(k): (v.strip() if isinstance(v, str) else v) for k, v in raw.items()}
            row["quantity_unit"] = unit
            rows.append(row)

    missing = REQUIRED_FIELDS - (mapped_headers | {"quantity_unit"})
    if missing:
        raise ValueError(
            f"Manual credits CSV is missing required fields after header mapping: {sorted(missing)}. "
            f"Observed mapped headers: {sorted(mapped_headers)}. Update HEADER_ALIASES if the portal export changed."
        )
    return rows


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", required=True, help="Path to the exported Copilot Credits CSV.")
    parser.add_argument("--unit", choices=["credits", "messages"], required=True, help="Unit the export uses.")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--snapshot-id", required=True)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    result = lib.CollectorResult(surface=lib.SURFACE_MANUAL_CSV, status="failed", preview=False)
    rows = import_csv(args.csv, args.unit)
    file_hash = lib.sha256_file(args.csv)
    artifact_name = os.path.basename(args.csv)
    for row in rows:
        row["manual_artifact_name"] = artifact_name
        row["manual_artifact_sha256"] = file_hash

    result.extract_path = lib.write_raw_extract(args.out_dir, lib.SURFACE_MANUAL_CSV, args.snapshot_id, rows)
    result.rows = len(rows)
    result.data_freshness_utc = lib.utc_now_iso()
    result.note = f"Imported manual export '{artifact_name}' (sha256={file_hash[:12]}...), unit={args.unit}."
    result.finish("succeeded")
    logger.info(result.note)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
