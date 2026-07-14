"""Regression tests for ACM Boolean column create payloads."""

from __future__ import annotations

import importlib
import sys
from pathlib import Path
from typing import Any

import pytest

SOLUTION_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = SOLUTION_ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

BOOLEAN_ODATA_TYPE = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
BOOLEAN_OPTIONSET_ODATA_TYPE = "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"

_BOOLEAN_SOURCES: list[tuple[str, str, dict[str, bool]]] = [
    (
        "create_dataverse_schema",
        "REGISTRY_TABLE_COLUMNS",
        {"fsi_OverrideInclude": False},
    ),
    (
        "create_audit_compliance_schema",
        "TABLE_COLUMNS",
        {"fsi_AuditEnabled": False, "fsi_DataverseAuditEnabled": False},
    ),
]

_COLUMN_LISTS: list[tuple[str, str]] = [
    (module_name, attr_name)
    for module_name, attr_name, _expected_defaults in _BOOLEAN_SOURCES
]

_ALL_EXPECTED_SCHEMA_NAMES = [
    "fsi_OverrideInclude",
    "fsi_AuditEnabled",
    "fsi_DataverseAuditEnabled",
]


def _get_columns(module_name: str, attr_name: str) -> list[dict[str, Any]]:
    module = importlib.import_module(module_name)
    return list(getattr(module, attr_name))


def _booleans(cols: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [c for c in cols if c.get("@odata.type") == BOOLEAN_ODATA_TYPE]


def test_exactly_three_acm_boolean_schema_names_are_covered() -> None:
    """The contract test covers exactly the current ACM Boolean columns."""
    found = [
        col["SchemaName"]
        for module_name, attr_name, _expected_defaults in _BOOLEAN_SOURCES
        for col in _booleans(_get_columns(module_name, attr_name))
    ]
    assert sorted(found) == sorted(_ALL_EXPECTED_SCHEMA_NAMES), (
        f"Expected Boolean SchemaNames {sorted(_ALL_EXPECTED_SCHEMA_NAMES)!r}, "
        f"found {sorted(found)!r} - update _ALL_EXPECTED_SCHEMA_NAMES if a column "
        "was intentionally added or removed"
    )


@pytest.mark.parametrize("module_name,attr_name", _COLUMN_LISTS)
def test_boolean_columns_carry_attributetype_and_attributetypename(
    module_name: str, attr_name: str
) -> None:
    """Boolean columns include their Dataverse type discriminators."""
    cols = _booleans(_get_columns(module_name, attr_name))
    assert cols, (
        f"{module_name}.{attr_name} defines no Boolean columns"
    )
    for col in cols:
        loc = f"{module_name}.{attr_name}[{col.get('SchemaName', '<unknown>')}]"
        assert col.get("AttributeType") == "Boolean", (
            f'{loc}: missing or wrong AttributeType - required: "Boolean"'
        )
        assert col.get("AttributeTypeName") == {"Value": "BooleanType"}, (
            f'{loc}: missing or wrong AttributeTypeName - required: '
            '{"Value": "BooleanType"}'
        )


@pytest.mark.parametrize("module_name,attr_name", _COLUMN_LISTS)
def test_boolean_columns_carry_full_optionset_contract(
    module_name: str, attr_name: str
) -> None:
    """Boolean columns include the required two-option metadata."""
    cols = _booleans(_get_columns(module_name, attr_name))
    for col in cols:
        loc = f"{module_name}.{attr_name}[{col.get('SchemaName', '<unknown>')}]"

        option_set = col.get("OptionSet")
        assert option_set is not None, (
            f"{loc}: missing OptionSet"
        )
        assert option_set.get("@odata.type") == BOOLEAN_OPTIONSET_ODATA_TYPE, (
            f"{loc}: OptionSet['@odata.type'] must be {BOOLEAN_OPTIONSET_ODATA_TYPE!r}"
        )
        assert option_set.get("OptionSetType") == "Boolean", (
            f'{loc}: OptionSet["OptionSetType"] must be "Boolean"'
        )

        true_opt = option_set.get("TrueOption", {})
        assert true_opt.get("Value") == 1, (
            f"{loc}: TrueOption Value must be 1, got {true_opt.get('Value')!r}"
        )
        true_labels = (
            true_opt.get("Label", {}).get("LocalizedLabels", [])
        )
        assert true_labels and true_labels[0].get("Label"), (
            f"{loc}: TrueOption must carry a non-empty LocalizedLabel"
        )

        false_opt = option_set.get("FalseOption", {})
        assert false_opt.get("Value") == 0, (
            f"{loc}: FalseOption Value must be 0, got {false_opt.get('Value')!r}"
        )
        false_labels = (
            false_opt.get("Label", {}).get("LocalizedLabels", [])
        )
        assert false_labels and false_labels[0].get("Label"), (
            f"{loc}: FalseOption must carry a non-empty LocalizedLabel"
        )


def test_each_boolean_column_owns_a_distinct_optionset_object() -> None:
    """Boolean columns do not share mutable OptionSet dictionaries."""
    all_optionsets: list[tuple[str, object]] = []
    for module_name, attr_name, _expected_defaults in _BOOLEAN_SOURCES:
        for col in _booleans(_get_columns(module_name, attr_name)):
            schema_name = col.get("SchemaName", "<unknown>")
            option_set = col.get("OptionSet")
            assert option_set is not None, (
                f"{module_name}.{attr_name}[{schema_name}]: OptionSet is missing"
            )
            for prev_name, prev_optionset in all_optionsets:
                assert option_set is not prev_optionset, (
                    f"{module_name}.{attr_name}[{schema_name}] shares an OptionSet "
                    f"with {prev_name} - use _boolean_optionset() to return a fresh "
                    "dict per column"
                )
            all_optionsets.append(
                (f"{module_name}.{attr_name}[{schema_name}]", option_set)
            )


@pytest.mark.parametrize(
    "module_name,attr_name,expected_defaults",
    _BOOLEAN_SOURCES,
)
def test_boolean_columns_preserve_existing_default_values(
    module_name: str,
    attr_name: str,
    expected_defaults: dict[str, bool],
) -> None:
    """DefaultValue on each Boolean column must match its pre-fix value."""
    cols = _booleans(_get_columns(module_name, attr_name))
    for col in cols:
        schema_name = col.get("SchemaName", "<unknown>")
        loc = f"{module_name}.{attr_name}[{schema_name}]"
        if schema_name in expected_defaults:
            assert col.get("DefaultValue") == expected_defaults[schema_name], (
                f"{loc}: DefaultValue should be {expected_defaults[schema_name]!r}"
            )
