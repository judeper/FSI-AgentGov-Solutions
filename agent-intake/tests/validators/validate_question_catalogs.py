#!/usr/bin/env python3
"""Validate agent-intake question catalogs against the Dataverse schema."""
from __future__ import annotations

import argparse
import importlib.util
import logging
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType

LOG = logging.getLogger("agent-intake.validate-question-catalogs")

REPO_ROOT = Path(__file__).resolve().parents[3]
SOLUTION_ROOT = REPO_ROOT / "agent-intake"
SCHEMA_SCRIPT = SOLUTION_ROOT / "scripts" / "create_fsi_intake_dataverse_schema.py"

EXPECTED_QUESTION_COUNTS: dict[str, int] = {
    # Counts derived from the corresponding docs/intake-questions-<path>.md
    # catalog (each table row prefixed with "| <ID>" is one question). Update
    # this dict whenever a question is added to or removed from a catalog file;
    # the validator's `_count_questions` helper enforces the floor at runtime.
    "express": 13,
    "standard": 22,
    "full": 35,
}
CATALOG_PATHS: dict[str, Path] = {
    name: SOLUTION_ROOT / "docs" / f"intake-questions-{name}.md"
    for name in EXPECTED_QUESTION_COUNTS
}
QUESTION_ROW_PATTERN = re.compile(r"^\|\s*([A-Z]\d+)\s*\|", re.MULTILINE)
QUESTION_HEADING_PATTERN = re.compile(
    r"^##\s+(?:Question\s*)?(Q\d+)[\.:]?",
    re.IGNORECASE | re.MULTILINE,
)
CODE_SPAN_PATTERN = re.compile(r"`([^`]+)`")
CATALOG_TOKEN_PATTERN = re.compile(r"\bfsi_[a-z0-9]+(?:\.[A-Za-z0-9_]+){0,2}\b")
RANGE_SHORTHAND_PATTERN = re.compile(r"^fsi_[a-z]\d+$")
PREFIX_PLACEHOLDERS = {"fsi_f", "fsi_s"}
JSON_BLOB_TABLE = "fsi_intakerequest"
JSON_BLOB_FIELD = "fsi_standardfullquestionsjson"
JSON_KEY_PATTERN = re.compile(r"^[a-z][A-Za-z0-9_]*$")


@dataclass(frozen=True)
class SchemaInventory:
    """In-memory view of the schema symbols referenced by the catalogs."""

    table_fields: dict[str, set[str]]
    allowed_symbols: set[str]


@dataclass(frozen=True)
class ValidationResult:
    """Validation details for a single catalog."""

    question_count: int
    errors: tuple[str, ...]


def configure_logging() -> None:
    """Configure a simple validator logger."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")



def load_schema_module(path: Path) -> ModuleType:
    """Load the Dataverse schema script as a Python module."""
    spec = importlib.util.spec_from_file_location("agent_intake_schema", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load schema module from {path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module



def build_schema_inventory(module: ModuleType) -> SchemaInventory:
    """Build the set of allowed Dataverse symbols from the schema script."""
    table_fields: dict[str, set[str]] = {}
    allowed_symbols: set[str] = set()

    tables: dict[str, dict[str, object]] = getattr(module, "TABLES")
    for table_name, table_def in tables.items():
        fields = {
            str(column["SchemaName"]).lower()
            for column in table_def["columns"]
        }
        table_fields[table_name] = fields
        allowed_symbols.add(table_name)
        allowed_symbols.update(fields)
        entity_set_name = table_def.get("entity_set_name")
        if isinstance(entity_set_name, str):
            allowed_symbols.add(entity_set_name)

    for option_set_name in getattr(module, "SHARED_OPTIONSETS", {}).keys():
        allowed_symbols.add(option_set_name)
    for option_set_name in getattr(module, "INTAKE_OPTIONSETS", {}).keys():
        allowed_symbols.add(option_set_name)

    alternate_key = getattr(module, "ALTERNATE_KEY", {})
    for key_column in alternate_key.get("key_columns", []):
        allowed_symbols.add(str(key_column))
    schema_name = alternate_key.get("schema_name")
    if isinstance(schema_name, str):
        allowed_symbols.add(schema_name.lower())

    return SchemaInventory(table_fields=table_fields, allowed_symbols=allowed_symbols)



def question_sort_key(question_id: str) -> tuple[str, int]:
    """Sort mixed question identifiers such as B1, E10, or Q7."""
    match = re.match(r"([A-Z]+)(\d+)$", question_id)
    if match is None:
        return question_id, 0
    return match.group(1), int(match.group(2))



def collect_question_ids(text: str) -> list[str]:
    """Collect numbered question markers from the catalog markdown."""
    question_ids = {match.group(1).upper() for match in QUESTION_ROW_PATTERN.finditer(text)}
    question_ids.update(
        match.group(1).upper().rstrip(".:")
        for match in QUESTION_HEADING_PATTERN.finditer(text)
    )
    return sorted(question_ids, key=question_sort_key)



def collect_catalog_tokens(text: str) -> set[str]:
    """Collect Dataverse-like symbols from markdown code spans."""
    tokens: set[str] = set()
    for span in CODE_SPAN_PATTERN.findall(text):
        for token in CATALOG_TOKEN_PATTERN.findall(span):
            if RANGE_SHORTHAND_PATTERN.fullmatch(token) or token in PREFIX_PLACEHOLDERS:
                continue
            tokens.add(token)
    return tokens



def validate_catalog(
    catalog_name: str,
    catalog_path: Path,
    expected_count: int,
    inventory: SchemaInventory,
) -> ValidationResult:
    """Validate a single catalog file against the schema inventory."""
    errors: list[str] = []
    if not catalog_path.exists():
        return ValidationResult(
            question_count=0,
            errors=(f"{catalog_name}: missing catalog file: {catalog_path}",),
        )

    text = catalog_path.read_text(encoding="utf-8")
    question_ids = collect_question_ids(text)
    question_count = len(question_ids)
    if question_count < expected_count:
        errors.append(
            f"{catalog_name}: found {question_count} numbered questions "
            f"({', '.join(question_ids) if question_ids else 'none'}); expected >= {expected_count}"
        )

    missing_symbols: set[str] = set()
    for token in collect_catalog_tokens(text):
        parts = token.split(".")
        if len(parts) == 3:
            table_name, field_name, json_key = parts
            if table_name != JSON_BLOB_TABLE or field_name != JSON_BLOB_FIELD:
                missing_symbols.add(token)
                continue
            if table_name not in inventory.table_fields:
                missing_symbols.add(token)
                continue
            if field_name not in inventory.table_fields[table_name]:
                missing_symbols.add(token)
                continue
            if not JSON_KEY_PATTERN.fullmatch(json_key):
                missing_symbols.add(token)
            continue

        if len(parts) == 2:
            table_name, field_name = parts
            if table_name not in inventory.table_fields:
                missing_symbols.add(token)
                continue
            if field_name not in inventory.table_fields[table_name]:
                missing_symbols.add(token)
            continue

        if token not in inventory.allowed_symbols:
            missing_symbols.add(token)

    if missing_symbols:
        errors.append(
            f"{catalog_name}: references undeclared Dataverse symbols: "
            f"{', '.join(sorted(missing_symbols))}"
        )

    return ValidationResult(question_count=question_count, errors=tuple(errors))



def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    return parser.parse_args()



def main() -> int:
    """Run the question-catalog validator."""
    parse_args()
    configure_logging()

    try:
        schema_module = load_schema_module(SCHEMA_SCRIPT)
    except Exception as exc:  # pragma: no cover - surfaced by CLI smoke test
        LOG.error("Could not load schema script %s: %s", SCHEMA_SCRIPT, exc)
        return 1

    inventory = build_schema_inventory(schema_module)

    total_questions = 0
    all_errors: list[str] = []
    for catalog_name, expected_count in EXPECTED_QUESTION_COUNTS.items():
        result = validate_catalog(
            catalog_name=catalog_name,
            catalog_path=CATALOG_PATHS[catalog_name],
            expected_count=expected_count,
            inventory=inventory,
        )
        total_questions += result.question_count
        all_errors.extend(result.errors)

    if all_errors:
        for error in all_errors:
            LOG.error(error)
        return 1

    LOG.info(
        "Validated %s catalog questions across %s files against %s Dataverse tables.",
        total_questions,
        len(CATALOG_PATHS),
        len(inventory.table_fields),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
