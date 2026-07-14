"""Regression tests for Dataverse global-choice column create payloads."""

from __future__ import annotations

from collections import Counter
import importlib
import sys
from pathlib import Path
from typing import Any

import pytest

SOLUTION_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = SOLUTION_ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

PICKLIST_ODATA_TYPE = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"

# Expected GlobalOptionSet@odata.bind value for each PicklistAttributeMetadata SchemaName.
# fsi_Zone appears in both ACV tables bound to the same option set.
_EXPECTED_BINDINGS: dict[str, str] = {
    "fsi_Scope": "/GlobalOptionSetDefinitions(Name='fsi_acv_scope')",
    "fsi_Zone": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
    "fsi_Severity": "/GlobalOptionSetDefinitions(Name='fsi_acv_severity')",
    "fsi_EnvironmentType": "/GlobalOptionSetDefinitions(Name='fsi_acv_environmenttype')",
    "fsi_ComplianceStatus": "/GlobalOptionSetDefinitions(Name='fsi_alca_compliancestatus')",
}

_COLUMN_LISTS: list[tuple[str, str]] = [
    ("create_dataverse_schema", "HISTORY_TABLE_COLUMNS"),
    ("create_dataverse_schema", "REGISTRY_TABLE_COLUMNS"),
    ("create_audit_compliance_schema", "TABLE_COLUMNS"),
]


def _get_columns(module_name: str, attr_name: str) -> list[dict[str, Any]]:
    module = importlib.import_module(module_name)
    return list(getattr(module, attr_name))


def _picklists(cols: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [c for c in cols if c.get("@odata.type") == PICKLIST_ODATA_TYPE]


@pytest.mark.parametrize("module_name,attr_name", _COLUMN_LISTS)
def test_all_picklist_columns_carry_full_create_contract(
    module_name: str, attr_name: str
) -> None:
    """Every PicklistAttributeMetadata column definition must include the three required
    Dataverse Web API create-contract fields alongside GlobalOptionSet@odata.bind."""
    cols = _picklists(_get_columns(module_name, attr_name))
    assert cols, (
        f"{module_name}.{attr_name} defines no Picklist columns — expected at least one"
    )

    for col in cols:
        loc = f"{module_name}.{attr_name}[{col.get('SchemaName', '<unknown>')}]"

        assert col.get("AttributeType") == "Picklist", (
            f"{loc}: missing or wrong AttributeType — Dataverse Web API requires "
            '"AttributeType": "Picklist" in PicklistAttributeMetadata create payloads'
        )
        assert col.get("AttributeTypeName") == {"Value": "PicklistType"}, (
            f'{loc}: missing or wrong AttributeTypeName — required: {{"Value": "PicklistType"}}'
        )
        assert col.get("SourceTypeMask") == 0, (
            f"{loc}: missing or wrong SourceTypeMask — required: 0 for global option-set bound column"
        )
        assert col.get("GlobalOptionSet@odata.bind"), (
            f"{loc}: missing GlobalOptionSet@odata.bind — must reference a named global option set"
        )


def test_expected_picklist_columns_are_all_covered() -> None:
    """The contract test must cover every current global-choice column."""
    actual = Counter(
        (column["SchemaName"], column["GlobalOptionSet@odata.bind"])
        for module_name, attr_name in _COLUMN_LISTS
        for column in _picklists(_get_columns(module_name, attr_name))
    )
    expected = Counter(
        {
            ("fsi_Scope", _EXPECTED_BINDINGS["fsi_Scope"]): 1,
            ("fsi_Zone", _EXPECTED_BINDINGS["fsi_Zone"]): 2,
            ("fsi_Severity", _EXPECTED_BINDINGS["fsi_Severity"]): 1,
            ("fsi_EnvironmentType", _EXPECTED_BINDINGS["fsi_EnvironmentType"]): 1,
            ("fsi_ComplianceStatus", _EXPECTED_BINDINGS["fsi_ComplianceStatus"]): 1,
        }
    )

    assert actual == expected


@pytest.mark.parametrize("module_name,attr_name", _COLUMN_LISTS)
def test_picklist_columns_use_expected_global_option_set_bindings(
    module_name: str, attr_name: str
) -> None:
    """Each PicklistAttributeMetadata column must bind to its designated global option set."""
    for col in _picklists(_get_columns(module_name, attr_name)):
        schema_name = col.get("SchemaName", "<unknown>")
        loc = f"{module_name}.{attr_name}[{schema_name}]"

        expected = _EXPECTED_BINDINGS.get(schema_name)
        assert expected is not None, (
            f"{loc}: SchemaName {schema_name!r} not present in _EXPECTED_BINDINGS — "
            "add its expected binding to keep this test current"
        )

        actual = col.get("GlobalOptionSet@odata.bind", "")
        assert actual == expected, (
            f"{loc}: GlobalOptionSet@odata.bind = {actual!r}, want {expected!r}"
        )
