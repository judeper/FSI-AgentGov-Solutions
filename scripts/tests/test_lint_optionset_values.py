"""Unit tests for scripts/lint-optionset-values.py."""
from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "lint-optionset-values.py"
SPEC = importlib.util.spec_from_file_location("lint_optionset_values", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load {SCRIPT_PATH}")

lint_optionset_values = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = lint_optionset_values
SPEC.loader.exec_module(lint_optionset_values)


def _defs(text: str):
    return lint_optionset_values.collect_definitions_from_text(text)


class CollectDefinitionsTests(unittest.TestCase):
    """Detect Picklist option-set definitions with low values."""

    def test_two_option_zero_one_has_no_finding(self) -> None:
        """Boolean attributes legitimately use Value:0 (False) and Value:1 (True)."""
        text = """
DEF = {
    "@odata.type": "#Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
    "SchemaName": "fsi_IsActive",
    "OptionSet": {
        "TrueOption": {"Value": 1, "Label": "Yes"},
        "FalseOption": {"Value": 0, "Label": "No"},
    },
}
"""
        # TrueOption/FalseOption pattern has no `Options` list so it isn't a
        # candidate. The linter must not flag it.
        self.assertEqual([], _defs(text))

    def test_picklist_above_floor_has_no_finding(self) -> None:
        """Picklist defined with 100000000+ Values is the correct convention."""
        text = """
OPTIONSETS = {
    "fsi_demo_status": {
        "Name": "fsi_demo_status",
        "OptionSetType": "Picklist",
        "Options": [
            {"Value": 100000000, "Label": "A"},
            {"Value": 100000001, "Label": "B"},
        ],
    },
}
"""
        self.assertEqual([], _defs(text))

    def test_picklist_below_floor_is_flagged(self) -> None:
        """Picklist defined with low values produces a finding for the linter."""
        text = """
OPTIONSETS = {
    "fsi_demo_status": {
        "Name": "fsi_demo_status",
        "OptionSetType": "Picklist",
        "Options": [
            {"Value": 0, "Label": "A"},
            {"Value": 1, "Label": "B"},
        ],
    },
}
"""
        definitions = _defs(text)
        self.assertEqual(1, len(definitions))
        self.assertEqual("fsi_demo_status", definitions[0].name)
        self.assertEqual((0, 1), definitions[0].low_values)

    def test_picklist_default_type_is_flagged_when_low(self) -> None:
        """Absent OptionSetType defaults to Picklist; low values still flagged."""
        text = """
OPTIONSETS = {
    "fsi_demo_pillar": {
        "Name": "fsi_demo_pillar",
        "Options": [
            {"Value": 1, "Label": "X"},
            {"Value": 2, "Label": "Y"},
        ],
    },
}
"""
        definitions = _defs(text)
        self.assertEqual(1, len(definitions))
        self.assertEqual("Picklist", definitions[0].option_set_type)


class AllowlistTests(unittest.TestCase):
    """Suppress findings via the three layered allowlists."""

    def _flag(self, name: str, user_allowlist=None):
        return lint_optionset_values.is_allowlisted(name, user_allowlist or set())

    def test_shared_acv_zone_is_allowlisted(self) -> None:
        """§9 shared `fsi_acv_zone` is deferred and suppressed in either direction."""
        self.assertTrue(self._flag("fsi_acv_zone"))

    def test_shared_acv_severity_is_allowlisted(self) -> None:
        """§9 shared `fsi_acv_severity` is deferred and suppressed."""
        self.assertTrue(self._flag("fsi_acv_severity"))

    def test_asard_acv_zone_is_allowlisted_in_either_casing(self) -> None:
        """Allowlist comparison is case-insensitive (logical names lowercase)."""
        self.assertTrue(self._flag("Fsi_ACV_Zone"))

    def test_internally_consistent_cd_pillar_is_allowlisted(self) -> None:
        """compliance-dashboard `fsi_cd_pillar` is allowlisted (1-based)."""
        self.assertTrue(self._flag("fsi_cd_pillar"))

    def test_internally_consistent_rsv_sourcetype_is_allowlisted(self) -> None:
        """rag-source-validator `fsi_rsv_sourcetype` is allowlisted (1-based)."""
        self.assertTrue(self._flag("fsi_rsv_sourcetype"))

    def test_internally_consistent_drt_teststatus_is_allowlisted(self) -> None:
        """dr-testing-framework `fsi_drt_teststatus` is allowlisted (1/2)."""
        self.assertTrue(self._flag("fsi_drt_teststatus"))

    def test_unknown_set_is_not_allowlisted_by_default(self) -> None:
        """A novel 0-based picklist must be reported."""
        self.assertFalse(self._flag("fsi_demo_someset"))

    def test_user_allowlist_suppresses_finding(self) -> None:
        """User-managed allowlist entries are honored."""
        self.assertTrue(self._flag("fsi_demo_someset", {"fsi_demo_someset"}))


class LoadAllowlistFileTests(unittest.TestCase):
    """Load the user-managed allowlist file."""

    def test_comments_and_blank_lines_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "allow.txt"
            path.write_text(
                "# header\n"
                "\n"
                "fsi_demo_a\n"
                "Fsi_Demo_B  # inline note\n"
                "  \n",
                encoding="utf-8",
            )
            tokens = lint_optionset_values.load_allowlist(path)
            self.assertEqual({"fsi_demo_a", "fsi_demo_b"}, tokens)

    def test_missing_file_returns_empty_set(self) -> None:
        self.assertEqual(set(), lint_optionset_values.load_allowlist(Path("/no/such/file.txt")))


class LintScriptTests(unittest.TestCase):
    """End-to-end lint behavior against a synthetic schema script."""

    def test_findings_filtered_by_allowlist(self) -> None:
        """Allowlisted names produce zero findings even with low values."""
        schema = """
OPTIONSETS = {
    "fsi_acv_zone": {
        "Name": "fsi_acv_zone",
        "OptionSetType": "Picklist",
        "Options": [{"Value": 0, "Label": "A"}],
    },
    "fsi_demo_new": {
        "Name": "fsi_demo_new",
        "OptionSetType": "Picklist",
        "Options": [{"Value": 0, "Label": "A"}],
    },
}
"""
        with tempfile.TemporaryDirectory() as tmp:
            script_path = Path(tmp) / "create_demo_dataverse_schema.py"
            script_path.write_text(schema, encoding="utf-8")
            findings = lint_optionset_values.lint_script(script_path, set())
            self.assertEqual(1, len(findings))
            self.assertEqual("fsi_demo_new", findings[0].definition.name)


class SchemaScriptDiscoveryTests(unittest.TestCase):
    """Discover all three schema-script naming conventions."""

    def test_glob_matches_three_naming_conventions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            scripts = root / "scripts"
            scripts.mkdir()
            (scripts / "create_xyz_dataverse_schema.py").write_text("# slug form")
            (scripts / "create_xyz_schema.py").write_text("# acm-style form")
            (scripts / "create_dataverse_schema.py").write_text("# slugless form")
            (scripts / "create_xyz_environment_variables.py").write_text("# unrelated")
            found = lint_optionset_values.schema_scripts(root)
            self.assertEqual(
                [
                    "create_dataverse_schema.py",
                    "create_xyz_dataverse_schema.py",
                    "create_xyz_schema.py",
                ],
                sorted(p.name for p in found),
            )


if __name__ == "__main__":
    unittest.main()
