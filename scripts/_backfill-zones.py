#!/usr/bin/env python3
"""One-shot backfill: add `zones` and `dataClassification` to every manifest.yaml.

Zone inference is best-guess based on solution domain, controls, and tier and
is INTENDED FOR PRODUCT-TEAM REVIEW. Each manifest receives a sentinel comment
flagging the inferred zones for review; subsequent edits should remove the
sentinel once a human has confirmed the choice.

Run once:
    python scripts/_backfill-zones.py

Idempotent: skips manifests that already declare `zones`.
"""
from __future__ import annotations

import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent

# Zone inference table. Keys are solution slugs (folder names). Values are
# (zones, dataClassification). All entries reviewed below by domain/tier:
#   - personal/team/enterprise = applies to all 3 zones (default)
#   - team/enterprise          = collaborative-only or shared-agent scope
#   - enterprise               = regulated/managed-only (Tier 3 governance,
#                                FINRA/SOX/OCC supervisory workflows)
ZONE_MAP: dict[str, tuple[list[str], str]] = {
    # --- Tier 1 foundational (apply across all zones) ---
    "agent-observability-foundation": (["personal", "team", "enterprise"], "internal"),
    "cross-solution-integration":     (["personal", "team", "enterprise"], "internal"),

    # --- Tier 3 / enterprise-only (regulated managed environments) ---
    "agent-365-lifecycle-governance":          (["enterprise"], "confidential"),
    "audit-compliance-manager":                (["team", "enterprise"], "confidential"),
    "compliance-dashboard":                    (["enterprise"], "confidential"),
    "conditional-access-automation":           (["team", "enterprise"], "confidential"),
    "cross-tenant-external-sharing-governance":(["enterprise"], "confidential"),
    "dr-testing-framework":                    (["enterprise"], "confidential"),
    "environment-lifecycle-management":        (["personal", "team", "enterprise"], "internal"),
    "finra-supervision-workflow":              (["enterprise"], "restricted"),
    "generative-ai-config-auditor":            (["team", "enterprise"], "internal"),
    "inactivity-timeout-enforcement":          (["team", "enterprise"], "internal"),
    "message-center-monitor":                  (["enterprise"], "internal"),
    "model-risk-management-automation":        (["enterprise"], "restricted"),
    "pipeline-governance-cleanup":             (["team", "enterprise"], "internal"),
    "session-security-configurator":           (["team", "enterprise"], "internal"),

    # --- Sharing/access detection (team & enterprise scope) ---
    "agent-access-monitor":                       (["team", "enterprise"], "confidential"),
    "agent-communication-restriction-detector":   (["team", "enterprise"], "internal"),
    "agent-sharing-access-restriction-detector":  (["team", "enterprise"], "confidential"),
    "segregation-detector":                       (["team", "enterprise"], "confidential"),
    "unrestricted-agent-sharing-detector":        (["team", "enterprise"], "confidential"),

    # --- Per-agent governance / detection (all zones) ---
    "action-confirmation-auditor":     (["personal", "team", "enterprise"], "internal"),
    "agent-knowledge-source-scanner":  (["personal", "team", "enterprise"], "confidential"),
    "agent-registry-automation":       (["personal", "team", "enterprise"], "internal"),
    "coi-testing":                     (["team", "enterprise"], "confidential"),
    "content-moderation-monitor":      (["personal", "team", "enterprise"], "internal"),
    "copilot-studio-analytics":        (["personal", "team", "enterprise"], "internal"),
    "credential-oversharing-detector": (["personal", "team", "enterprise"], "confidential"),
    "deny-event-correlation-report":   (["team", "enterprise"], "confidential"),
    "file-upload-security":            (["personal", "team", "enterprise"], "internal"),
    "hallucination-tracker":           (["personal", "team", "enterprise"], "internal"),
    "hitl-workflow-governance":        (["personal", "team", "enterprise"], "internal"),
    "mime-type-restrictions":          (["personal", "team", "enterprise"], "internal"),
    "rag-source-validator":            (["personal", "team", "enterprise"], "confidential"),
    "scope-drift-monitor":             (["personal", "team", "enterprise"], "confidential"),
}


def backfill(slug: str, manifest_path: Path) -> bool:
    text = manifest_path.read_text(encoding="utf-8")
    data = yaml.safe_load(text) or {}
    if "zones" in data and "dataClassification" in data:
        return False
    if slug not in ZONE_MAP:
        print(f"  SKIP: no zone mapping for {slug}", file=sys.stderr)
        return False
    zones, classification = ZONE_MAP[slug]
    sentinel = (
        "\n# zones/dataClassification backfilled by scripts/_backfill-zones.py\n"
        "# INFERRED from domain/tier/controls — product team must review.\n"
    )
    addition = sentinel + yaml.safe_dump(
        {"zones": zones, "dataClassification": classification},
        sort_keys=False,
        default_flow_style=False,
    )
    if not text.endswith("\n"):
        text += "\n"
    manifest_path.write_text(text + addition, encoding="utf-8")
    return True


def main() -> int:
    updated = 0
    for slug_dir in sorted(ROOT.iterdir()):
        if not slug_dir.is_dir():
            continue
        manifest = slug_dir / "manifest.yaml"
        if not manifest.is_file():
            continue
        if backfill(slug_dir.name, manifest):
            print(f"updated: {slug_dir.name}/manifest.yaml")
            updated += 1
    print(f"\nBackfilled {updated} manifest(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
