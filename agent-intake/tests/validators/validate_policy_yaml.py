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

    if errors:
        for error in errors:
            LOG.error("%s: %s", POLICY_PATH.name, error)
        return 1

    LOG.info("Validated %s required policy sections.", POLICY_PATH.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
