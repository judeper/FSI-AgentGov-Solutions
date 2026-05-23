#!/usr/bin/env python3
"""Validate agent-intake Adaptive Card templates."""
from __future__ import annotations

import argparse
import json
import logging
import re
import sys
from pathlib import Path
from typing import Any, Iterable

try:
    from jsonschema import Draft202012Validator
except ImportError:  # pragma: no cover - exercised by CLI runtime, not tests
    Draft202012Validator = None

LOG = logging.getLogger("agent-intake.validate-adaptive-cards")

REPO_ROOT = Path(__file__).resolve().parents[3]
TEMPLATES_DIR = REPO_ROOT / "agent-intake" / "templates"
TOKEN_PATTERN = re.compile(r"\$\{([^}]+)\}")

ADAPTIVE_CARD_SCHEMA: dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["type", "version", "body"],
    "properties": {
        "$schema": {"type": "string"},
        "type": {"const": "AdaptiveCard"},
        "version": {"type": "string", "pattern": r"^\d+\.\d+$"},
        "body": {"type": "array", "items": {"type": "object"}},
        "actions": {"type": "array", "items": {"type": "object"}},
        "msteams": {"type": "object"},
    },
    "additionalProperties": True,
}

CARD_TOKEN_ALLOWLIST: dict[str, set[str]] = {
    "reviewer-notification-card.json": {
        "fsi_agentdisplayname",
        "fsi_businessjustification",
        "fsi_declareddatasourcessummary",
        "fsi_intendedaudience",
        "fsi_makerdisplayname",
        "fsi_makerupn",
        "fsi_pathused",
        "fsi_quorumrequired",
        "fsi_requestid",
        "fsi_reviewdueon",
        "fsi_reviewerappurl",
        "fsi_reviewerattestation",
        "fsi_reviewid",
        "fsi_reviewerrole",
        "fsi_risktier",
        "fsi_submittedon",
        "fsi_zone",
    },
    "sponsor-approval-card.json": {
        "fsi_agentdisplayname",
        "fsi_businessjustification",
        "fsi_intendedaudience",
        "fsi_makerdisplayname",
        "fsi_makerupn",
        "fsi_requestid",
        "fsi_risktier",
        "fsi_submittedon",
        "fsi_zone",
    },
}



def configure_logging() -> None:
    """Configure a simple validator logger."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")



def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    return parser.parse_args()



def iter_string_values(node: Any) -> Iterable[str]:
    """Yield every string value nested within a JSON-like structure."""
    if isinstance(node, str):
        yield node
        return
    if isinstance(node, list):
        for item in node:
            yield from iter_string_values(item)
        return
    if isinstance(node, dict):
        for value in node.values():
            yield from iter_string_values(value)



def collect_tokens(card: dict[str, Any]) -> set[str]:
    """Collect ${token} placeholders from a card payload."""
    tokens: set[str] = set()
    for value in iter_string_values(card):
        tokens.update(TOKEN_PATTERN.findall(value))
    return tokens



def format_path(parts: Iterable[Any]) -> str:
    """Render a jsonschema path as a readable selector."""
    path = "$"
    for part in parts:
        if isinstance(part, int):
            path += f"[{part}]"
        else:
            path += f".{part}"
    return path



def validate_card_schema(card: dict[str, Any], card_name: str) -> list[str]:
    """Validate the minimal Adaptive Card shape."""
    errors: list[str] = []
    if Draft202012Validator is not None:
        validator = Draft202012Validator(ADAPTIVE_CARD_SCHEMA)
        for error in sorted(validator.iter_errors(card), key=lambda item: list(item.absolute_path)):
            errors.append(
                f"{card_name}: schema error at {format_path(error.absolute_path)}: {error.message}"
            )
        return errors

    if card.get("type") != "AdaptiveCard":
        errors.append(f"{card_name}: top-level type must be 'AdaptiveCard'")
    if not card.get("version"):
        errors.append(f"{card_name}: top-level version is required")
    if not isinstance(card.get("body"), list):
        errors.append(f"{card_name}: body must be an array")
    return errors



def validate_card(path: Path) -> list[str]:
    """Validate one Adaptive Card template."""
    errors: list[str] = []
    try:
        card = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"{path.name}: invalid JSON: {exc}"]

    if not isinstance(card, dict):
        return [f"{path.name}: top-level JSON value must be an object"]

    errors.extend(validate_card_schema(card, path.name))

    allowed_tokens = CARD_TOKEN_ALLOWLIST.get(path.name)
    if allowed_tokens is None:
        errors.append(f"{path.name}: no token allowlist entry is defined for this card")
        return errors

    discovered_tokens = collect_tokens(card)
    undocumented_tokens = sorted(discovered_tokens - allowed_tokens)
    if undocumented_tokens:
        errors.append(
            f"{path.name}: undocumented ${'{'}token{'}'} placeholders: {', '.join(undocumented_tokens)}"
        )

    unused_allowlist_tokens = sorted(allowed_tokens - discovered_tokens)
    if unused_allowlist_tokens:
        LOG.info(
            "%s: allowlist entries not currently used: %s",
            path.name,
            ", ".join(unused_allowlist_tokens),
        )

    LOG.info(
        "%s: validated %s documented placeholder tokens.",
        path.name,
        len(discovered_tokens),
    )
    return errors



def main() -> int:
    """Run the Adaptive Card validator."""
    parse_args()
    configure_logging()

    card_paths = sorted(TEMPLATES_DIR.glob("*-card.json"))
    if not card_paths:
        LOG.error("No Adaptive Card templates found under %s", TEMPLATES_DIR)
        return 1

    errors: list[str] = []
    for path in card_paths:
        errors.extend(validate_card(path))

    if errors:
        for error in errors:
            LOG.error(error)
        return 1

    LOG.info("Validated %s Adaptive Card template(s).", len(card_paths))
    return 0


if __name__ == "__main__":
    sys.exit(main())
