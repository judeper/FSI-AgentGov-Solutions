#!/usr/bin/env python3
"""Validate the agent-intake policy lookup YAML file."""
from __future__ import annotations

import argparse
import logging
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:  # pragma: no cover - exercised by CLI runtime
    raise SystemExit(f"Missing dependency: {exc}. Install pyyaml.") from exc

LOG = logging.getLogger("agent-intake.validate-policy-yaml")

REPO_ROOT = Path(__file__).resolve().parents[3]
POLICY_PATH = REPO_ROOT / "agent-intake" / "templates" / "policy-lookup-tables.yaml"
REQUIRED_TOP_LEVEL_KEYS = {
    "schema_version",
    "audience_to_zone",
    "connector_allowlist",
    "denial_appeal",
    "reviewer_routing",
    "quorum",
    "mrm",
    "parallel_routing",
}
SCHEMA_VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+(?:-preview)?$")

# The five audience labels the classifier expects to find in audience_to_zone.
# Kept in sync with REQUIRED_AUDIENCES in seed_classification_rules.py and the
# enum in templates/drift-handoff-payload-schema.json.
EXPECTED_AUDIENCE_KEYS = frozenset(
    {
        "Just me",
        "My team",
        "My department",
        "Anyone in the firm",
        "External users",
    }
)
VALID_ZONE_VALUES = frozenset({1, 2, 3})



def configure_logging() -> None:
    """Configure a simple validator logger."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")



def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    return parser.parse_args()



def main() -> int:
    """Run the policy-yaml validator."""
    parse_args()
    configure_logging()

    document = yaml.safe_load(POLICY_PATH.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        LOG.error("%s did not parse into a YAML mapping.", POLICY_PATH)
        return 1

    errors: list[str] = []
    missing_keys = sorted(REQUIRED_TOP_LEVEL_KEYS - set(document))
    if missing_keys:
        errors.append(
            f"missing required top-level keys: {', '.join(missing_keys)}"
        )

    schema_version = str(document.get("schema_version", ""))
    if not SCHEMA_VERSION_PATTERN.fullmatch(schema_version):
        errors.append(
            "schema_version must match ^\\d+\\.\\d+\\.\\d+(-preview)?$ "
            f"(found {schema_version!r})"
        )

    for key in sorted(REQUIRED_TOP_LEVEL_KEYS - {"schema_version"}):
        if key in document and not isinstance(document[key], dict):
            errors.append(f"{key} must parse as a mapping")

    audience_to_zone = document.get("audience_to_zone")
    if isinstance(audience_to_zone, dict):
        present_keys = frozenset(audience_to_zone)
        missing_audiences = sorted(EXPECTED_AUDIENCE_KEYS - present_keys)
        if missing_audiences:
            errors.append(
                "audience_to_zone is missing required audience labels: "
                f"{', '.join(missing_audiences)}"
            )
        for audience_label, zone_value in audience_to_zone.items():
            # bool is a subclass of int in Python; reject it explicitly so that
            # `True` / `False` typos in the YAML don't masquerade as zone 1/0.
            if isinstance(zone_value, bool) or not isinstance(zone_value, int):
                errors.append(
                    f"audience_to_zone[{audience_label!r}] must be an integer "
                    f"in {{1, 2, 3}} (found {zone_value!r}, "
                    f"type {type(zone_value).__name__})"
                )
            elif zone_value not in VALID_ZONE_VALUES:
                errors.append(
                    f"audience_to_zone[{audience_label!r}] must be one of "
                    f"{{1, 2, 3}} (found {zone_value})"
                )

    if errors:
        for error in errors:
            LOG.error("%s: %s", POLICY_PATH.name, error)
        return 1

    LOG.info("Validated %s required policy sections.", POLICY_PATH.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
