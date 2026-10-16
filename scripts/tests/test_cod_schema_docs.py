"""Offline regression checks for COD evidence-field documentation."""

from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

import pytest

ROOT = Path(__file__).resolve().parents[2]
SOLUTION = ROOT / "credential-oversharing-detector"


@pytest.fixture(scope="module")
def schema_module() -> ModuleType:
    """Load schema definitions and their documentation generator without authentication."""
    path = SOLUTION / "scripts" / "create_cod_dataverse_schema.py"
    spec = importlib.util.spec_from_file_location("cod_schema_docs_test", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize("logical_name", ["fsi_approvedscopes", "fsi_actualscopes"])
def test_violation_scope_descriptions_name_only_scope_writer(
    schema_module: ModuleType, logical_name: str
) -> None:
    """Authentication violations do not populate either scope-baseline field."""
    column = next(
        column
        for column in schema_module.COLUMNS["fsi_credentialviolation"]
        if column["SchemaName"].lower() == logical_name
    )
    description = schema_module._label(column["Description"])
    assert "Compare-OAuthScopeBaseline.ps1" in description
    assert "Test-AgentAuthMethod.ps1" not in description


def test_committed_schema_docs_match_generator(schema_module: ModuleType) -> None:
    """Generated evidence instructions must remain consistent with their source."""
    actual = (SOLUTION / "docs" / "dataverse-schema.md").read_text(encoding="utf-8")
    assert actual == schema_module.generate_schema_docs()
