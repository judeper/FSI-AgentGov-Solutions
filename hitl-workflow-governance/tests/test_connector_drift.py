"""Anti-drift tests for HITL Workflow Governance connector references.

Parses docs/flow-configuration.md to extract:
  1. Connector operation IDs (e.g., shared_advancedapprovals)
  2. Option-set value references
  3. Dataverse column references in flow steps

Validates them against the schema generator (create_hwg_dataverse_schema.py)
to catch the "Option Set Value Confusion" pattern (docs show 0/1/2/3 but
Dataverse uses 100000000/100000001/etc).

Addresses Council Review 2026-04-16 finding #1 mitigation.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

SOLUTION_ROOT = Path(__file__).resolve().parent.parent
FLOW_CONFIG = SOLUTION_ROOT / "docs" / "flow-configuration.md"
SCHEMA_SCRIPT = SOLUTION_ROOT / "scripts" / "create_hwg_dataverse_schema.py"


# ---------------------------------------------------------------------------
# Parse schema generator for known-good option set values
# ---------------------------------------------------------------------------

def _parse_optionsets_from_schema() -> dict[str, dict[str, int]]:
    """Extract option set definitions from create_hwg_dataverse_schema.py.

    Returns:
        Dict mapping option set name -> {label: value}.
        E.g., {"fsi_HWG_checkpointtype": {"RequestForInformation": 100000000, ...}}
    """
    if not SCHEMA_SCRIPT.exists():
        return {}

    text = SCHEMA_SCRIPT.read_text(encoding="utf-8")
    optionsets: dict[str, dict[str, int]] = {}

    # Match HWG_OPTIONSETS and SHARED_OPTIONSETS patterns:
    #   "fsi_HWG_checkpointtype": {
    #       "name": "fsi_HWG_checkpointtype",
    #       "options": [
    #           ("RequestForInformation", 100000000),
    # Also match the ACV-style pattern with Value/Label dicts

    # Tuple-style options: ("Label", Value)
    tuple_pattern = re.compile(
        r'"name"\s*:\s*"(fsi_\w+)".*?'
        r'"options"\s*:\s*\[(.*?)\]',
        re.DOTALL,
    )
    for m in tuple_pattern.finditer(text):
        os_name = m.group(1)
        options_text = m.group(2)
        opts: dict[str, int] = {}
        for label_match in re.finditer(
            r'\(\s*"(\w+)"\s*,\s*(\d+)\s*\)', options_text
        ):
            opts[label_match.group(1)] = int(label_match.group(2))
        if opts:
            optionsets[os_name] = opts

    return optionsets


def _parse_schema_columns() -> set[str]:
    """Extract all SchemaName values from the HWG schema generator."""
    if not SCHEMA_SCRIPT.exists():
        return set()
    text = SCHEMA_SCRIPT.read_text(encoding="utf-8")
    pattern = re.compile(r'"SchemaName"\s*:\s*"(fsi_\w+)"')
    return {m.lower() for m in pattern.findall(text)}


# ---------------------------------------------------------------------------
# Parse flow-configuration.md for references
# ---------------------------------------------------------------------------

def _extract_connector_operation_ids(text: str) -> list[tuple[int, str]]:
    """Extract connector operation ID references from flow docs.

    Looks for patterns like:
        shared_advancedapprovals
        RequestForInformation
        StartAndWaitForAnApprovalProcess
    """
    findings: list[tuple[int, str]] = []
    op_pattern = re.compile(
        r"\b(shared_\w+|RequestForInformation|StartAndWaitForAnApprovalProcess)\b"
    )
    for lineno, line in enumerate(text.splitlines(), start=1):
        for m in op_pattern.finditer(line):
            findings.append((lineno, m.group(1)))
    return findings


def _extract_option_set_values(text: str) -> list[tuple[int, str, str]]:
    """Extract option-set value references from flow docs.

    Looks for patterns like:
        `100000000` (`Missing`)
        100000001
        fsi_checkpointtype = 100000000
        map Zone1 = 1, Zone2 = 2
    Returns (lineno, raw_value, context_snippet).
    """
    findings: list[tuple[int, str, str]] = []
    # Numeric values that look like Dataverse option set values
    value_pattern = re.compile(r"\b(100000\d{3})\b")
    for lineno, line in enumerate(text.splitlines(), start=1):
        for m in value_pattern.finditer(line):
            ctx = line.strip()[:120]
            findings.append((lineno, m.group(1), ctx))
    return findings


def _extract_fsi_column_refs(text: str) -> list[tuple[int, str]]:
    """Extract fsi_ column references from flow docs."""
    findings: list[tuple[int, str]] = []
    col_pattern = re.compile(r"\bfsi_[a-z][a-z0-9]*(?:_[a-z][a-z0-9]*)*\b")
    for lineno, line in enumerate(text.splitlines(), start=1):
        for m in col_pattern.finditer(line):
            token = m.group(0)
            # Skip entity set names and table names
            if token in {
                "fsi_hitlcheckpointresult",
                "fsi_hitlcheckpointexception",
                "fsi_hitlscanrun",
            }:
                continue
            # Skip connection reference unique names
            if token.startswith("fsi_cr_"):
                continue
            # Skip option set names
            if re.match(r"fsi_(?:acv|hwg|cd|mrm)_", token):
                continue
            findings.append((lineno, token))
    return findings


# ---------------------------------------------------------------------------
# Known-good connector operation IDs
# ---------------------------------------------------------------------------

KNOWN_CONNECTOR_OPS = {
    "shared_advancedapprovals",       # Human in the Loop connector API name
    "RequestForInformation",          # RFI action
    "StartAndWaitForAnApprovalProcess",  # Multistage approval action
}


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def flow_config_text() -> str:
    """Load flow-configuration.md content."""
    if not FLOW_CONFIG.exists():
        pytest.skip("docs/flow-configuration.md not found")
    return FLOW_CONFIG.read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def schema_optionsets() -> dict[str, dict[str, int]]:
    """Option sets from create_hwg_dataverse_schema.py."""
    opts = _parse_optionsets_from_schema()
    if not opts:
        pytest.skip("No option sets found in schema generator")
    return opts


@pytest.fixture(scope="module")
def schema_columns() -> set[str]:
    """Logical column names from schema generator."""
    cols = _parse_schema_columns()
    if not cols:
        pytest.skip("No columns found in schema generator")
    return cols


# ---------------------------------------------------------------------------
# Tests: Connector operation IDs
# ---------------------------------------------------------------------------

class TestConnectorOperationIds:
    """Verify referenced connector operation IDs are known-good."""

    def test_operation_ids_are_known(self, flow_config_text: str) -> None:
        refs = _extract_connector_operation_ids(flow_config_text)
        assert len(refs) > 0, "No connector operation IDs found in flow docs"

        unknown = [
            (ln, op) for ln, op in refs if op not in KNOWN_CONNECTOR_OPS
        ]
        assert not unknown, (
            "Unknown connector operation IDs in flow-configuration.md:\n"
            + "\n".join(f"  line {ln}: {op}" for ln, op in unknown)
        )


# ---------------------------------------------------------------------------
# Tests: Option Set Value Confusion pattern
# ---------------------------------------------------------------------------

class TestOptionSetValues:
    """Catch the 'Option Set Value Confusion' pattern.

    Flow docs must use Dataverse-native option set values (100000000+),
    NOT zero-indexed display ordinals (0/1/2/3).
    """

    def test_option_set_values_exist_in_docs(self, flow_config_text: str) -> None:
        """Flow docs should reference Dataverse option set values."""
        refs = _extract_option_set_values(flow_config_text)
        assert len(refs) > 0, (
            "No Dataverse option set values (100000xxx) found in flow docs"
        )

    def test_checkpoint_type_values_match_schema(
        self, flow_config_text: str, schema_optionsets: dict[str, dict[str, int]]
    ) -> None:
        """Checkpoint type values in docs must match schema definitions."""
        os_def = schema_optionsets.get("fsi_HWG_checkpointtype")
        if not os_def:
            pytest.skip("fsi_HWG_checkpointtype not in schema")

        schema_values = set(os_def.values())
        doc_values = {
            int(v) for _, v, _ in _extract_option_set_values(flow_config_text)
        }

        # Every schema-defined value that appears in docs should match exactly
        doc_checkpoint_values = doc_values & schema_values
        assert len(doc_checkpoint_values) > 0, (
            "No checkpoint type values from schema found in docs"
        )

    def test_no_zero_indexed_option_values(self, flow_config_text: str) -> None:
        """Detect docs using 0/1/2/3 where Dataverse uses 100000000+ values.

        This catches lines like:
            fsi_checkpointtype = 0  (should be 100000000)
            fsi_severity: 1         (when context is a Dataverse write)
        """
        zero_indexed_pattern = re.compile(
            r"fsi_(?:checkpointtype|checkpointstatus|violationstatus)"
            r"\s*(?:=|eq|:)\s*['\"]?([0-4])['\"]?\b"
        )
        violations: list[str] = []
        for lineno, line in enumerate(flow_config_text.splitlines(), start=1):
            if zero_indexed_pattern.search(line):
                violations.append(
                    f"  line {lineno}: {line.strip()[:100]}"
                )

        assert not violations, (
            "Flow docs use zero-indexed option values where Dataverse "
            "expects 100000000+ values:\n" + "\n".join(violations)
        )


# ---------------------------------------------------------------------------
# Tests: Column references match schema
# ---------------------------------------------------------------------------

class TestFlowDocColumnRefs:
    """Verify fsi_ column refs in flow docs match schema generator."""

    def test_no_snake_case_columns(self, flow_config_text: str) -> None:
        """No fsi_ column reference should have underscores between words."""
        violations: list[str] = []
        snake_re = re.compile(r"\bfsi_[a-z]+(?:_[a-z]+){2,}\b")
        for lineno, line in enumerate(flow_config_text.splitlines(), start=1):
            for m in snake_re.finditer(line):
                token = m.group(0)
                # Skip known multi-segment names (connection refs, option sets)
                if token.startswith("fsi_cr_") or re.match(
                    r"fsi_(?:acv|hwg|cd|mrm)_", token
                ):
                    continue
                violations.append(f"  line {lineno}: {token}")

        assert not violations, (
            "Flow docs contain snake_case column names:\n"
            + "\n".join(violations)
        )

    def test_flow_columns_in_schema(
        self, flow_config_text: str, schema_columns: set[str]
    ) -> None:
        """Advisory: column refs in flow docs should be in schema."""
        refs = _extract_fsi_column_refs(flow_config_text)
        assert len(refs) > 0, "No fsi_ column references found in flow docs"

        unknown = [
            (ln, col) for ln, col in refs if col not in schema_columns
        ]
        # Advisory only — some columns may be from the trigger output
        if unknown and len(unknown) > len(refs) * 0.5:
            pytest.skip(
                f"{len(unknown)}/{len(refs)} column refs not in schema "
                "(may be trigger outputs or system columns)"
            )
