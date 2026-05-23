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

    def test_primary_key_column_resolves_via_table_name(self) -> None:
        """Dataverse auto-generates <tablelogicalname>id as the primary key column.

        The schema script declares the table but not the PK column; the linter
        must add the `id`-suffixed variant for every fsi_* token.
        """
        schema_tokens = lint_odata_existence.collect_schema_tokens_from_text(
            """
PUBLISHER_PREFIX = "fsi"
TABLES = {
    "fsi_DRTestResult": {
        "SchemaName": "fsi_DRTestResult",
        "Attributes": [],
    }
}
"""
        )
        context_tokens = lint_odata_existence.scan_text_for_odata_tokens(
            "$select=fsi_drtestresultid"
        )
        findings = lint_odata_existence.find_unknown_tokens(context_tokens, schema_tokens)
        self.assertEqual([], findings)

    def test_multi_segment_lookup_value_resolves(self) -> None:
        """Multi-segment lookup _value (with underscores in base name) resolves correctly."""
        schema_tokens = lint_odata_existence.collect_schema_tokens_from_text(
            """
PUBLISHER_PREFIX = "fsi"
TABLES = {
    "fsi_ModelInventory": {
        "SchemaName": "fsi_ModelInventory",
        "Attributes": [
            {"SchemaName": "fsi_ModelInventory_Lookup"},
        ],
    }
}
"""
        )
        context_tokens = lint_odata_existence.scan_text_for_odata_tokens(
            "$select=_fsi_modelinventory_lookup_value"
        )
        findings = lint_odata_existence.find_unknown_tokens(context_tokens, schema_tokens)
        self.assertEqual([], findings)


class SchemaScriptsGlobTests(unittest.TestCase):
    """Validate that schema_scripts() finds both naming conventions."""

    def test_glob_matches_slugless_schema_script(self) -> None:
        """All three naming conventions must be discovered:
            - create_<slug>_dataverse_schema.py  (most solutions)
            - create_<slug>_schema.py            (audit-compliance-manager)
            - create_dataverse_schema.py         (slugless: ELM, ARA, ...)
        """
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            scripts = root / "scripts"
            scripts.mkdir()
            (scripts / "create_xyz_dataverse_schema.py").write_text("# slug form")
            (scripts / "create_xyz_schema.py").write_text("# acm-style form")
            (scripts / "create_dataverse_schema.py").write_text("# slugless form")
            (scripts / "create_xyz_environment_variables.py").write_text("# unrelated")
            found = lint_odata_existence.schema_scripts(root)
            found_names = sorted(p.name for p in found)
            self.assertEqual(
                [
                    "create_dataverse_schema.py",
                    "create_xyz_dataverse_schema.py",
                    "create_xyz_schema.py",
                ],
                found_names,
            )


if __name__ == "__main__":
    unittest.main()
