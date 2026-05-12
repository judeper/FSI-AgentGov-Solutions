"""Tests for cross-solution-integration alternate key definitions.

Validates that alternate key definitions are well-formed and follow
Dataverse naming conventions (no snake_case in logical names).
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

import pytest

SOLUTION_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = SOLUTION_ROOT / "scripts"


def _load_alternate_keys() -> list[dict]:
    """Import ALTERNATE_KEYS from create_csi_alternate_keys.py."""
    script_path = SCRIPTS_DIR / "create_csi_alternate_keys.py"
    if not script_path.exists():
        pytest.skip("create_csi_alternate_keys.py not found")

    spec = importlib.util.spec_from_file_location("csi_keys", script_path)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.ALTERNATE_KEYS


class TestAlternateKeyDefinitions:
    """Validate alternate key structure and naming conventions."""

    @pytest.fixture(scope="class")
    def keys(self) -> list[dict]:
        return _load_alternate_keys()

    def test_at_least_one_key_defined(self, keys: list[dict]) -> None:
        assert len(keys) > 0, "No alternate keys defined"

    def test_key_has_required_fields(self, keys: list[dict]) -> None:
        required = {
            "table_logical", "key_schema_name", "key_logical",
            "columns", "description",
        }
        for key_def in keys:
            missing = required - set(key_def.keys())
            assert not missing, (
                f"Key '{key_def.get('key_schema_name', '?')}' missing: {missing}"
            )

    def test_key_logical_name_no_snake_case(self, keys: list[dict]) -> None:
        """Key logical names must follow Dataverse convention."""
        for key_def in keys:
            logical = key_def["key_logical"]
            after_prefix = logical[4:]  # strip "fsi_"
            assert "_" not in after_prefix, (
                f"Key logical name '{logical}' has underscores between words"
            )

    def test_column_logical_names_no_snake_case(self, keys: list[dict]) -> None:
        """Column logical names in key must follow Dataverse convention."""
        for key_def in keys:
            for col in key_def["columns"]:
                logical = col["LogicalName"]
                after_prefix = logical[4:]  # strip "fsi_"
                assert "_" not in after_prefix, (
                    f"Column '{logical}' in key "
                    f"'{key_def['key_schema_name']}' has snake_case"
                )

    def test_key_has_multiple_columns(self, keys: list[dict]) -> None:
        """Alternate keys should be composite (multiple columns)."""
        for key_def in keys:
            assert len(key_def["columns"]) >= 2, (
                f"Key '{key_def['key_schema_name']}' has only "
                f"{len(key_def['columns'])} column(s) — alternate keys "
                f"should be composite for meaningful upsert"
            )

    def test_upsert_example_present(self, keys: list[dict]) -> None:
        """Each key should include a usage example."""
        for key_def in keys:
            assert "upsert_example" in key_def, (
                f"Key '{key_def['key_schema_name']}' has no upsert_example"
            )


class TestAlternateKeyDocs:
    """Verify generated documentation exists and is consistent."""

    def test_docs_file_exists(self) -> None:
        docs_path = SOLUTION_ROOT / "docs" / "alternate-keys.md"
        assert docs_path.exists(), "docs/alternate-keys.md not generated"

    def test_docs_mention_all_keys(self) -> None:
        docs_path = SOLUTION_ROOT / "docs" / "alternate-keys.md"
        if not docs_path.exists():
            pytest.skip("docs not generated")

        text = docs_path.read_text(encoding="utf-8")
        keys = _load_alternate_keys()
        for key_def in keys:
            assert key_def["key_schema_name"] in text, (
                f"Key '{key_def['key_schema_name']}' not in docs"
            )
