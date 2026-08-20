#!/usr/bin/env python3
"""
Offline smoke test for the Agent Cost Reporting pipeline.

Exercises normalize -> correlate -> render -> package end to end against fixture raw extracts
(no network). Validates that produced cost facts satisfy the cost_fact schema, that the
deterministic subscription->policy->environment join fires, that the rendered HTML is
self-contained (no external references), and that the evidence package hashes are written.

Run with: python -m pytest tests/test_pipeline_smoke.py   (or execute directly).
"""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import sys
import tempfile

SOLUTION_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(SOLUTION_ROOT, "scripts")
for sub in ("shared", "normalize", "render"):
    sys.path.insert(0, os.path.join(SCRIPTS, sub))

SNAP = "20260616T000000Z-smoke01"
SUB = "11111111-1111-1111-1111-111111111111"
PERIOD = ("2026-06-01T00:00:00Z", "2026-06-16T23:59:59Z")


def _load(module_name: str, rel_path: str):
    spec = importlib.util.spec_from_file_location(module_name, os.path.join(SCRIPTS, rel_path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _write_fixtures(raw_dir: str) -> None:
    os.makedirs(raw_dir, exist_ok=True)
    fixtures = {
        f"raw_azure_cost_management_{SNAP}.jsonl": [
            {"MeterId": "m-1", "Meter": "Copilot Studio Credit", "ServiceName": "Microsoft Power Platform",
             "Cost": 184.0, "Currency": "USD", "ResourceGroupName": "rg-fsi", "subscriptionId": SUB},
        ],
        f"raw_graph_licenses_{SNAP}.jsonl": [
            {"skuId": "sku-copilot", "skuPartNumber": "Microsoft_365_Copilot",
             "consumedUnits": 120, "prepaidUnits": {"enabled": 150}},
        ],
        f"raw_powerplatform_billing_policies_{SNAP}.jsonl": [
            {"id": "bp-1", "billingPolicyId": "bp-1", "billingInstrument": {"subscriptionId": SUB},
             "environmentId": "env-1", "environmentName": "FSI Prod"},
        ],
        f"raw_manual_csv_{SNAP}.jsonl": [
            {"agent_id": "agent-1", "credits_or_messages_consumed": 1840, "quantity_unit": "credits",
             "user_or_group_scope": "jdoe@contoso.com", "manual_artifact_name": "credits.csv",
             "manual_artifact_sha256": "a" * 64},
        ],
    }
    for name, rows in fixtures.items():
        with open(os.path.join(raw_dir, name), "w", encoding="utf-8") as handle:
            for row in rows:
                handle.write(json.dumps(row) + "\n")


def test_pipeline_smoke() -> None:
    import jsonschema

    normalize = _load("normalize_cost_facts", "normalize/normalize_cost_facts.py")
    correlate = _load("correlate_identity_and_scope", "normalize/correlate_identity_and_scope.py")
    render = _load("render_report", "render/render_report.py")
    package = _load("package_evidence", "render/package_evidence.py")

    with open(os.path.join(SOLUTION_ROOT, "schemas", "cost_fact.schema.json"), encoding="utf-8") as handle:
        cost_fact_schema = json.load(handle)

    with tempfile.TemporaryDirectory() as work:
        raw_dir = os.path.join(work, "raw")
        _write_fixtures(raw_dir)

        facts = normalize.normalize(raw_dir, SNAP, PERIOD)
        assert facts, "normalize produced no facts"
        for fact in facts:
            jsonschema.validate(fact, cost_fact_schema)

        ledger = correlate.correlate(facts)
        assert ledger["subscriptions_with_policy_map"] == 1
        assert ledger["deterministic_joins"] >= 1, "expected the subscription->policy->environment join to fire"

        # The azure_cost fact should now carry the environment id from the join.
        azure_facts = [f for f in facts if f["fact_type"] == "azure_cost"]
        assert azure_facts and azure_facts[0]["environment_id"] == "env-1"

        manifest = {
            "snapshot_id": SNAP,
            "generated_at_utc": "2026-06-16T00:00:00Z",
            "generator_version": "0.1.0-preview",
            "git_commit_sha": None,
            "tenant_id": "00000000-0000-0000-0000-000000000000",
            "scope": {"subscriptions": [SUB]},
            "period": {"start_utc": PERIOD[0], "end_utc": PERIOD[1]},
            "surfaces": [{"surface": "azure_cost_management", "status": "succeeded", "rows": 1, "preview": False}],
            "artifacts": [],
        }
        html = render.render(facts, manifest, os.path.join(SOLUTION_ROOT, "templates"))
        assert "Control limitation" in html
        assert "<svg" in html
        assert "http://" not in html and "https://" not in html, "report must be self-contained (no external refs)"

        pkg_dir = os.path.join(work, "pkg")
        os.makedirs(pkg_dir, exist_ok=True)
        if os.name == "posix":
            for name in ("cost_facts.jsonl", "cost_facts.csv"):
                path = os.path.join(pkg_dir, name)
                with open(path, "w", encoding="utf-8"):
                    pass
                # Start owner-only but non-canonical so write_outputs must
                # tighten away the execute bit without exposing test data.
                os.chmod(path, 0o700)
        with open(os.path.join(pkg_dir, "report.html"), "w", encoding="utf-8") as handle:
            handle.write(html)
        jsonl_path, csv_path = normalize.write_outputs(facts, pkg_dir)
        with open(jsonl_path, encoding="utf-8") as handle:
            persisted_facts = [json.loads(line) for line in handle if line.strip()]
        persisted_azure = next(f for f in persisted_facts if f["fact_type"] == "azure_cost")
        assert persisted_azure["amount"] == 184.0
        assert persisted_azure["currency_code"] == "USD"
        assert persisted_azure["azure_subscription_id"] == SUB
        if os.name == "posix":
            assert stat.S_IMODE(os.stat(jsonl_path).st_mode) == 0o600
            assert stat.S_IMODE(os.stat(csv_path).st_mode) == 0o600
        manifest_path = os.path.join(pkg_dir, "manifest.json")
        with open(manifest_path, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle)
        package.package(pkg_dir, manifest, ["report.html", "cost_facts.jsonl", "cost_facts.csv"])

        assert os.path.exists(os.path.join(pkg_dir, "sha256.txt"))
        with open(manifest_path, encoding="utf-8") as handle:
            updated = json.load(handle)
        assert len(updated["artifacts"]) == 3


if __name__ == "__main__":
    test_pipeline_smoke()
    print("smoke test passed")
