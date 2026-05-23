"""Unit tests for scripts/lint-odata-existence.py."""
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "lint-odata-existence.py"
SPEC = importlib.util.spec_from_file_location("lint_odata_existence", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load {SCRIPT_PATH}")

lint_odata_existence = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = lint_odata_existence
SPEC.loader.exec_module(lint_odata_existence)


class LintODataExistenceTests(unittest.TestCase):
    """Validate core OData existence linting behavior."""

    SCHEMA = """
PUBLISHER_PREFIX = "fsi"
TABLES = {
    "fsi_TestRecord": {
        "SchemaName": "fsi_TestRecord",
        "Attributes": [
            {"SchemaName": "fsi_AgentId"},
        ],
    }
}
"""

    def _findings(self, content: str):
        schema_tokens = lint_odata_existence.collect_schema_tokens_from_text(self.SCHEMA)
        context_tokens = lint_odata_existence.scan_text_for_odata_tokens(content)
        return lint_odata_existence.find_unknown_tokens(context_tokens, schema_tokens)

    def test_declared_column_has_no_finding(self) -> None:
        """Positive case: declared fsi_AgentId is valid in $select."""
        findings = self._findings("$select=fsi_agentid")
        self.assertEqual([], findings)

    def test_unknown_column_has_finding(self) -> None:
        """Negative case: unknown fsi_agentnamez is reported."""
        findings = self._findings("$select=fsi_agentnamez")
        self.assertEqual(1, len(findings))
        self.assertEqual("fsi_agentnamez", findings[0].token)

    def test_lookup_value_column_resolves_to_base_lookup(self) -> None:
        """Lookup _value projection resolves to the declared base column."""
        findings = self._findings("$select=_fsi_agentid_value")
        self.assertEqual([], findings)

    def test_system_columns_have_no_finding(self) -> None:
        """System columns are ignored by the fsi-token existence validator."""
        findings = self._findings("$select=createdon,modifiedon")
        self.assertEqual([], findings)

    def test_snake_case_spell_errors_are_deferred_to_spell_linter(self) -> None:
        """Spell errors remain owned by scripts/lint-odata-columns.py."""
        findings = self._findings("$select=fsi_agent_id")
        self.assertEqual([], findings)


if __name__ == "__main__":
    unittest.main()
