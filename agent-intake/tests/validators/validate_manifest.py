#!/usr/bin/env python3
"""Validate agent-intake/manifest.yaml against the repo manifest schema."""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Iterable

try:
    import yaml
    from jsonschema import Draft202012Validator, FormatChecker
except ImportError as exc:  # pragma: no cover - exercised by CLI runtime
    raise SystemExit(f"Missing dependency: {exc}. Install pyyaml and jsonschema.") from exc

LOG = logging.getLogger("agent-intake.validate-manifest")

REPO_ROOT = Path(__file__).resolve().parents[3]
MANIFEST_PATH = REPO_ROOT / "agent-intake" / "manifest.yaml"
SCHEMA_PATH = REPO_ROOT / "scripts" / "manifest.schema.json"



def configure_logging() -> None:
    """Configure a simple validator logger."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")



def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    return parser.parse_args()



def format_path(parts: Iterable[object]) -> str:
    """Render a jsonschema path as a readable selector."""
    path = "$"
    for part in parts:
        if isinstance(part, int):
            path += f"[{part}]"
        else:
            path += f".{part}"
    return path



def main() -> int:
    """Run the manifest validator."""
    parse_args()
    configure_logging()

    manifest = yaml.safe_load(MANIFEST_PATH.read_text(encoding="utf-8"))
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))

    if not isinstance(manifest, dict):
        LOG.error("%s did not parse into a YAML mapping.", MANIFEST_PATH)
        return 1

    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(manifest), key=lambda item: list(item.absolute_path))
    if errors:
        for error in errors:
            LOG.error(
                "%s: %s",
                format_path(error.absolute_path),
                error.message,
            )
        return 1

    LOG.info(
        "Validated %s version %s against %s.",
        MANIFEST_PATH.name,
        manifest.get("version", "<unknown>"),
        SCHEMA_PATH.name,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
