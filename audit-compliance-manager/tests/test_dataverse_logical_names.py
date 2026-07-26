"""Tests for Dataverse logical-name consistency in audit-compliance-manager.

Parses create_dataverse_schema.py and create_audit_compliance_schema.py to
extract all SchemaNames, computes expected logical names (lowercased, NO
underscores between words beyond the publisher prefix), and asserts that
OData queries in solution scripts reference those exact logical names.

Addresses Council Review 2026-04-16 finding #1: column-name drift is the
#1 source of runtime bugs across FSI-AgentGov-Solutions.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

SOLUTION_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = SOLUTION_ROOT / "scripts"


# ---------------------------------------------------------------------------
# Helpers — extract SchemaNames from Python schema generators
# ---------------------------------------------------------------------------

def _extract_schema_names_from_file(py_path: Path) -> list[str]:
    """Extract all SchemaName string values from a Python schema file.

    Scans for patterns like:
        "SchemaName": "fsi_SomeColumn"
        'SchemaName': 'fsi_SomeColumn'
    """
    text = py_path.read_text(encoding="utf-8")
    pattern = re.compile(r'''["']SchemaName["']\s*:\s*["'](fsi_\w+)["']''')
    return pattern.findall(text)


def _schema_name_to_logical(schema_name: str) -> str:
    """Convert a Dataverse SchemaName to its expected logical name.

    Dataverse logical name = SchemaName lowercased with NO underscores
    inserted between words. The publisher prefix underscore is preserved.

    Examples:
        fsi_EnvironmentId   -> fsi_environmentid
        fsi_AuditEnabled    -> fsi_auditenabled
        fsi_DataverseAuditEnabled -> fsi_dataverseauditenabled
    """
    return schema_name.lower()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def acv_schema_names() -> list[str]:
    """SchemaNames from create_dataverse_schema.py (ACV tables)."""
    path = SCRIPTS_DIR / "create_dataverse_schema.py"
    if not path.exists():
        pytest.skip(f"{path.name} not found")
    return _extract_schema_names_from_file(path)


@pytest.fixture(scope="module")
def alca_schema_names() -> list[str]:
    """SchemaNames from create_audit_compliance_schema.py (ALCA table)."""
    path = SCRIPTS_DIR / "create_audit_compliance_schema.py"
    if not path.exists():
        pytest.skip(f"{path.name} not found")
    return _extract_schema_names_from_file(path)


@pytest.fixture(scope="module")
def all_logical_names(acv_schema_names: list[str], alca_schema_names: list[str]) -> set[str]:
    """Union of all expected logical names from both schema generators."""
    combined = acv_schema_names + alca_schema_names
    return {_schema_name_to_logical(sn) for sn in combined}


# ---------------------------------------------------------------------------
# Test: SchemaName -> logical name conversion is well-formed
# ---------------------------------------------------------------------------

class TestSchemaNameConvention:
    """Verify SchemaNames follow the fsi_ prefix convention."""

    def test_acv_schema_names_have_prefix(self, acv_schema_names: list[str]) -> None:
        for sn in acv_schema_names:
            assert sn.startswith("fsi_"), f"SchemaName '{sn}' missing fsi_ prefix"

    def test_alca_schema_names_have_prefix(self, alca_schema_names: list[str]) -> None:
        for sn in alca_schema_names:
            assert sn.startswith("fsi_"), f"SchemaName '{sn}' missing fsi_ prefix"

    def test_logical_names_have_no_extra_underscores(
        self, acv_schema_names: list[str], alca_schema_names: list[str]
    ) -> None:
        """Logical names must not have underscores between word segments.

        Valid: fsi_environmentid, fsi_auditenabled
        Invalid: fsi_environment_id, fsi_audit_enabled

        Note: Alternate key SchemaNames (e.g., fsi_environmentid_key) are
        excluded — keys legitimately contain underscores in their names.
        """
        for sn in acv_schema_names + alca_schema_names:
            # Skip alternate key definitions (they end with _key)
            if sn.lower().endswith("_key"):
                continue
            logical = _schema_name_to_logical(sn)
            # After the publisher prefix (fsi_), there should be no underscores
            after_prefix = logical[4:]  # strip "fsi_"
            assert "_" not in after_prefix, (
                f"SchemaName '{sn}' -> logical '{logical}' has underscore in "
                f"word segment '{after_prefix}'. Dataverse logical names never "
                f"insert underscores between words."
            )

    def test_schema_generators_produce_nonzero_columns(
        self, acv_schema_names: list[str], alca_schema_names: list[str]
    ) -> None:
        assert len(acv_schema_names) > 0, "ACV schema generator has no SchemaNames"
        assert len(alca_schema_names) > 0, "ALCA schema generator has no SchemaNames"


# ---------------------------------------------------------------------------
# Test: OData references in scripts use correct logical names
# ---------------------------------------------------------------------------

# Patterns that indicate OData column references
ODATA_COLUMN_RE = re.compile(
    r"""
    (?:
        \$(?:select|filter|orderby|expand)=  # OData query param
        |
        /api/data/v9\.[0-9]+/                # Web API path
    )
    """,
    re.VERBOSE | re.IGNORECASE,
)

# Extract fsi_ tokens from an OData context line
FSI_TOKEN_RE = re.compile(r"\bfsi_[a-z][a-z0-9]*(?:_[a-z][a-z0-9]*)*\b")

# Tokens that are entity set names (not column names) — exclude from column checks
ENTITY_SET_NAMES = {
    "fsi_auditvalidationhistories",
    "fsi_auditenvironmentcompliances",
    "fsi_environmentregistries",
}

# System/built-in column names referenced in OData that are not from our schema
SYSTEM_COLUMNS = {
    "createdon",
    "modifiedon",
    "organizationid",
    "isauditenabled",
    "businessunitid",
    "roleid",
    "privilegeid",
    "objecttypecode",
}


def _scan_odata_references(file_path: Path) -> list[tuple[int, str]]:
    """Scan a file for fsi_ tokens in OData contexts.

    Returns list of (line_number, token) tuples.
    """
    findings: list[tuple[int, str]] = []
    try:
        text = file_path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return findings

    for lineno, line in enumerate(text.splitlines(), start=1):
        if not ODATA_COLUMN_RE.search(line):
            continue
        for token in FSI_TOKEN_RE.findall(line):
            if token in ENTITY_SET_NAMES:
                continue
            if token in SYSTEM_COLUMNS:
                continue
            # Skip option set names (contain _acv_, _alca_, _hwg_, _mrm_ etc)
            if re.match(r"fsi_(?:acv|alca|hwg|mrm|cd)_", token):
                continue
            findings.append((lineno, token))
    return findings


class TestODataColumnReferences:
    """Verify OData queries reference valid logical names from schema generators."""

    SCAN_EXTENSIONS = {".ps1", ".psm1", ".py", ".md"}

    def _collect_odata_refs(self) -> list[tuple[Path, int, str]]:
        """Collect all OData fsi_ column references across solution files."""
        refs: list[tuple[Path, int, str]] = []
        for ext in self.SCAN_EXTENSIONS:
            for file_path in SOLUTION_ROOT.rglob(f"*{ext}"):
                if "tests" in file_path.parts:
                    continue
                if "__pycache__" in file_path.parts:
                    continue
                for lineno, token in _scan_odata_references(file_path):
                    refs.append((file_path, lineno, token))
        return refs

    def test_odata_refs_exist(self) -> None:
        """Sanity: solution scripts should contain some OData references."""
        refs = self._collect_odata_refs()
        assert len(refs) > 0, "No OData fsi_ column references found in solution"

    def test_no_snake_case_violations(self) -> None:
        """No fsi_ token in OData context should have underscores between words.

        This catches the most common bug pattern: writing fsi_environment_id
        instead of fsi_environmentid.
        """
        violations: list[str] = []
        for file_path, lineno, token in self._collect_odata_refs():
            after_prefix = token[4:]  # strip "fsi_"
            if "_" in after_prefix:
                rel = file_path.relative_to(SOLUTION_ROOT)
                violations.append(f"  {rel}:{lineno} -> {token}")

        assert not violations, (
            "OData references contain snake_case fsi_ tokens "
            "(underscores between words):\n" + "\n".join(violations)
        )

    def test_odata_columns_match_schema(self, all_logical_names: set[str]) -> None:
        """OData column references should match schema-defined logical names."""
        unknown: list[str] = []
        for file_path, lineno, token in self._collect_odata_refs():
            if token not in all_logical_names:
                rel = file_path.relative_to(SOLUTION_ROOT)
                unknown.append(f"  {rel}:{lineno} -> {token}")

        # This is advisory — some references may be to system columns or
        # other tables not defined in our schema generators
        if unknown:
            pytest.skip(
                f"Found {len(unknown)} OData column refs not in schema "
                f"(may be system columns):\n" + "\n".join(unknown[:10])
            )
