"""Dataverse logical-name convention tests for copilot-agent-inventory.

Parses ``scripts/create_cai_dataverse_schema.py`` to extract every Dataverse
COLUMN SchemaName, then asserts each one lowercases to a well-formed logical
name: it carries the ``fsi_`` publisher prefix and contains no inter-word
underscore after that prefix. Dataverse never inserts underscores between words
in a logical name, so ``fsi_AgentId`` becomes ``fsi_agentid`` (not
``fsi_agent_id``). This guards against the column-name drift class that the
2026-04-16 council review flagged as the most common defect across the
solutions repo.

Modeled on ``audit-compliance-manager/tests/test_dataverse_logical_names.py``
and adapted to this solution's schema-declaration style: columns are declared
through ``_string_col("fsi_AgentId", ...)``-style helper calls whose first
argument already carries the prefix. Option-set names (passed as a later helper
argument and carrying the ``fsi_cai_`` / ``fsi_acv_`` infix) and table names are
excluded — only column attribute names are checked.

A second, low-risk scan checks that no ``fsi_`` token used inside an OData query
context (``$select=`` / ``$filter=`` / Web API path) in this solution's scripts
or docs carries an inter-word underscore, which helps detect hand-written query
typos such as ``fsi_agent_id``.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

SOLUTION_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_FILE = SOLUTION_ROOT / "scripts" / "create_cai_dataverse_schema.py"

# Column declared via _string_col("fsi_AgentId", ...) — first arg already has
# the prefix. _picklist_col's option-set arg is a LATER arg, so it is not
# captured by this first-argument regex.
_COL_HELPER_RE = re.compile(
    r"\b_(?:string|memo|integer|boolean|datetime|picklist)_col\(\s*"
    r"[\"'](fsi_[A-Za-z0-9_]+)[\"']"
)


def _schema_text() -> str:
    return SCHEMA_FILE.read_text(encoding="utf-8") if SCHEMA_FILE.is_file() else ""


def _column_schema_names() -> list[str]:
    """Return the column SchemaNames declared in the CAI schema generator."""
    text = _schema_text()
    if not text:
        return []
    return sorted(set(_COL_HELPER_RE.findall(text)))


COLUMN_SCHEMA_NAMES = _column_schema_names()
_PREFIX = "fsi_"
_MIN_EXPECTED_COLUMNS = 50


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
_NON_COLUMN_INFIX_RE = re.compile(r"fsi_(?:cai|acv|cr)_")
_NON_COLUMN_TOKENS: set[str] = set()


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


# ---------------------------------------------------------------------------
# DEFECT 1 regression — fsi_copilotagent alternate-key idempotency
#
# Yen added fsi_PackageKey alongside fsi_AgentEnvKey so that package-only rows
# (no environment-scoped bot GUID) can be upserted without accumulating
# duplicates.  Both keys must coexist in TABLES["fsi_copilotagent"]["alt_keys"].
# ---------------------------------------------------------------------------

try:
    _SCRIPTS_DIR = SOLUTION_ROOT / "scripts"
    if str(_SCRIPTS_DIR) not in sys.path:
        sys.path.insert(0, str(_SCRIPTS_DIR))
    import create_cai_dataverse_schema as _cai_schema

    _SCHEMA_IMPORT_ERROR: Exception | None = None
except Exception as _exc:  # pragma: no cover — only when a dep is absent
    _cai_schema = None  # type: ignore[assignment]
    _SCHEMA_IMPORT_ERROR = _exc

_schema_skip = pytest.mark.skipif(
    _cai_schema is None,
    reason=(
        "create_cai_dataverse_schema could not be imported "
        f"(missing dependency): {_SCHEMA_IMPORT_ERROR}"
    ),
)


@_schema_skip
def test_fsi_copilotagent_has_agent_env_key() -> None:
    """fsi_AgentEnvKey (agentid + environmentid) must be present — pre-existing key."""
    alt_keys = _cai_schema.TABLES["fsi_copilotagent"]["alt_keys"]
    matches = [k for k in alt_keys if k.get("schema_name") == "fsi_AgentEnvKey"]
    assert len(matches) == 1, (
        f"expected exactly one fsi_AgentEnvKey entry; got {len(matches)}"
    )
    assert matches[0]["key_attributes"] == ["fsi_agentid", "fsi_environmentid"], (
        f"fsi_AgentEnvKey key_attributes mismatch: {matches[0]['key_attributes']!r}"
    )


@_schema_skip
def test_fsi_copilotagent_has_package_key() -> None:
    """fsi_PackageKey (packageid) must be present — Yen's new dedup key."""
    alt_keys = _cai_schema.TABLES["fsi_copilotagent"]["alt_keys"]
    matches = [k for k in alt_keys if k.get("schema_name") == "fsi_PackageKey"]
    assert len(matches) == 1, (
        f"expected exactly one fsi_PackageKey entry; got {len(matches)}"
    )
    assert matches[0]["key_attributes"] == ["fsi_packageid"], (
        f"fsi_PackageKey key_attributes mismatch: {matches[0]['key_attributes']!r}"
    )


@_schema_skip
def test_fsi_copilotagent_both_alt_keys_coexist() -> None:
    """Adding fsi_PackageKey must not silently drop fsi_AgentEnvKey."""
    alt_keys = _cai_schema.TABLES["fsi_copilotagent"]["alt_keys"]
    schema_names = {k["schema_name"] for k in alt_keys}
    assert "fsi_AgentEnvKey" in schema_names, (
        "fsi_AgentEnvKey is missing — Yen's change may have replaced it"
    )
    assert "fsi_PackageKey" in schema_names, (
        "fsi_PackageKey is missing — package-only rows have no dedup key"
    )
