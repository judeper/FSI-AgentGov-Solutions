"""Dataverse logical-name convention tests for copilot-billing-governance.

Parses ``scripts/create_cbg_dataverse_schema.py`` to extract every Dataverse
COLUMN SchemaName, then asserts each one lowercases to a well-formed logical
name: it carries the ``fsi_`` publisher prefix and contains no inter-word
underscore after that prefix. Dataverse never inserts underscores between words
in a logical name, so ``fsi_PolicyType`` becomes ``fsi_policytype`` (not
``fsi_policy_type``). This guards against the column-name drift class that the
2026-04-16 council review flagged as the most common defect across the
solutions repo.

Modeled on ``audit-compliance-manager/tests/test_dataverse_logical_names.py``
and adapted to this solution's schema-declaration style: columns are declared
through ``_string("PolicyType", ...)``-style helper calls (PascalCase first
argument, prefix added by the helper) and through lookup ``"SchemaName":
f"{PUBLISHER_PREFIX}_RelatedCoverageGapId"`` f-strings. One-to-many
relationship SchemaNames (which legitimately join two table fragments with an
underscore) and option-set names (which carry the ``fsi_cbg_`` infix) are
excluded — only column attribute names are checked.

A second, low-risk scan checks that no ``fsi_`` token used inside an OData query
context (``$select=`` / ``$filter=`` / Web API path) in this solution's scripts
or docs carries an inter-word underscore, which helps detect hand-written query
typos such as ``fsi_policy_type``.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

SOLUTION_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_FILE = SOLUTION_ROOT / "scripts" / "create_cbg_dataverse_schema.py"

# Column declared via _string("PolicyType", ...) helper — first arg is the
# PascalCase name WITHOUT the prefix; the helper prepends fsi_.
_COL_HELPER_RE = re.compile(
    r"\b_(?:string|memo|picklist|boolean|integer|decimal|datetime)\(\s*"
    r"[\"']([A-Za-z][A-Za-z0-9_]*)[\"']"
)
# Lookup/primary columns declared via "SchemaName": f"{PUBLISHER_PREFIX}_Name".
_FSTRING_SCHEMA_RE = re.compile(
    r'"SchemaName":\s*f"\{PUBLISHER_PREFIX\}_([A-Za-z0-9_]+)"'
)
# One-to-many relationship SchemaName (NOT a column) — Referenced_Referencing.
_REL_SCHEMA_RE = re.compile(
    r'OneToManyRelationshipMetadata",\s*'
    r'"SchemaName":\s*f"\{PUBLISHER_PREFIX\}_([A-Za-z0-9_]+)"',
    re.DOTALL,
)


def _schema_text() -> str:
    return SCHEMA_FILE.read_text(encoding="utf-8") if SCHEMA_FILE.is_file() else ""


def _column_schema_names() -> list[str]:
    """Return the column SchemaNames declared in the CBG schema generator."""
    text = _schema_text()
    if not text:
        return []
    relationship_names = set(_REL_SCHEMA_RE.findall(text))
    helper_columns = ["fsi_" + name for name in _COL_HELPER_RE.findall(text)]
    fstring_columns = [
        "fsi_" + name
        for name in _FSTRING_SCHEMA_RE.findall(text)
        if name not in relationship_names
    ]
    return sorted(set(helper_columns) | set(fstring_columns))


COLUMN_SCHEMA_NAMES = _column_schema_names()
_PREFIX = "fsi_"
_MIN_EXPECTED_COLUMNS = 40


def test_schema_file_present() -> None:
    assert SCHEMA_FILE.is_file(), f"schema generator not found at {SCHEMA_FILE}"


def test_columns_discovered() -> None:
    assert len(COLUMN_SCHEMA_NAMES) >= _MIN_EXPECTED_COLUMNS, (
        f"expected at least {_MIN_EXPECTED_COLUMNS} column SchemaNames, parsed "
        f"{len(COLUMN_SCHEMA_NAMES)} — the extraction regex may be out of date"
    )


@pytest.mark.parametrize("schema_name", COLUMN_SCHEMA_NAMES)
def test_column_has_fsi_prefix(schema_name: str) -> None:
    assert schema_name.lower().startswith(_PREFIX), (
        f"column SchemaName '{schema_name}' is missing the fsi_ publisher prefix"
    )


@pytest.mark.parametrize("schema_name", COLUMN_SCHEMA_NAMES)
def test_column_logical_name_has_no_interword_underscore(schema_name: str) -> None:
    logical = schema_name.lower()
    body = logical[len(_PREFIX):]
    assert "_" not in body, (
        f"column SchemaName '{schema_name}' -> logical '{logical}' has an "
        "inter-word underscore; Dataverse logical names never insert "
        "underscores between words"
    )


# ---------------------------------------------------------------------------
# OData reference scan — no snake_case fsi_ column tokens in query contexts
# ---------------------------------------------------------------------------

_SCAN_EXTENSIONS = {".ps1", ".psm1", ".py", ".md", ".kql"}
_ODATA_CONTEXT_RE = re.compile(
    r"(?:\$(?:select|filter|orderby|expand|apply)=|/api/data/v9\.[0-9]+/)",
    re.IGNORECASE,
)
_FSI_TOKEN_RE = re.compile(r"\bfsi_[a-z][a-z0-9]*(?:_[a-z0-9]+)*\b")
# Option-set and connection-reference namespaces carry an infix and are not
# columns; exclude them from the column-token snake_case check.
_NON_COLUMN_INFIX_RE = re.compile(r"fsi_(?:cbg|acv|cr)_")
# Relationship SchemaName (lowercased) is not a column.
_NON_COLUMN_TOKENS = {"fsi_cbgcoveragegap_cbgentitlementmaterialized"}


def _collect_odata_tokens() -> list[tuple[Path, int, str]]:
    findings: list[tuple[Path, int, str]] = []
    for ext in _SCAN_EXTENSIONS:
        for file_path in SOLUTION_ROOT.rglob(f"*{ext}"):
            if "tests" in file_path.parts or "__pycache__" in file_path.parts:
                continue
            try:
                text = file_path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for lineno, line in enumerate(text.splitlines(), start=1):
                if not _ODATA_CONTEXT_RE.search(line):
                    continue
                for token in _FSI_TOKEN_RE.findall(line):
                    if _NON_COLUMN_INFIX_RE.match(token):
                        continue
                    if token in _NON_COLUMN_TOKENS:
                        continue
                    findings.append((file_path, lineno, token))
    return findings


def test_no_snake_case_in_odata_contexts() -> None:
    violations: list[str] = []
    for file_path, lineno, token in _collect_odata_tokens():
        if "_" in token[len(_PREFIX):]:
            rel = file_path.relative_to(SOLUTION_ROOT)
            violations.append(f"  {rel}:{lineno} -> {token}")
    assert not violations, (
        "OData contexts reference fsi_ column tokens with inter-word "
        "underscores (likely typos):\n" + "\n".join(violations)
    )
