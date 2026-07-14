"""Regression checks for Dataverse CreateEntity primary-name metadata."""

from __future__ import annotations

import importlib.util
from copy import deepcopy
from pathlib import Path


SCRIPTS_ROOT = Path(__file__).resolve().parents[1] / "scripts"
DATAVERSE_ENTITY_TYPE = "Microsoft.Dynamics.CRM.EntityMetadata"
LIVE_PRIMARY_ATTRIBUTE_ERROR_CODE = "0x80040203"
LIVE_PRIMARY_ATTRIBUTE_ERROR_MESSAGE = (
    "Required field 'PrimaryAttribute' is missing for RequestName='CreateEntity'."
)


def _load_module(file_name: str):
    path = SCRIPTS_ROOT / file_name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _iter_entity_factories() -> list[tuple[str, str, dict]]:
    entities: list[tuple[str, str, dict]] = []
    for file_name in ("create_dataverse_schema.py", "create_audit_compliance_schema.py"):
        module = _load_module(file_name)
        for factory_name in dir(module):
            if not (factory_name.startswith("get_") and factory_name.endswith("_entity")):
                continue

            factory = getattr(module, factory_name)
            if not callable(factory):
                continue

            payload = factory()
            if (
                isinstance(payload, dict)
                and payload.get("@odata.type") == DATAVERSE_ENTITY_TYPE
                and "PrimaryNameAttribute" in payload
                and "Attributes" in payload
            ):
                entities.append((file_name, factory_name, payload))
    return entities


def _create_entity_contract_response(entity_payload: dict) -> dict:
    primary_attributes = [
        attribute
        for attribute in entity_payload.get("Attributes", [])
        if attribute.get("IsPrimaryName") is True
    ]
    if len(primary_attributes) != 1:
        return {
            "error": {
                "code": LIVE_PRIMARY_ATTRIBUTE_ERROR_CODE,
                "message": LIVE_PRIMARY_ATTRIBUTE_ERROR_MESSAGE,
            }
        }
    return {"status_code": 204}


def test_create_entity_payload_marks_exactly_one_primary_name() -> None:
    """Every ACM CreateEntity payload marks one IsPrimaryName column."""

    entities = _iter_entity_factories()
    assert entities, "No ACM entity factory payloads were discovered for validation."

    for file_name, factory_name, entity in entities:
        primary_attributes = [
            attribute
            for attribute in entity["Attributes"]
            if attribute.get("IsPrimaryName") is True
        ]
        assert len(primary_attributes) == 1, (
            f"{file_name}:{factory_name} must define exactly one IsPrimaryName attribute."
        )
        assert primary_attributes[0]["SchemaName"].lower() == entity["PrimaryNameAttribute"], (
            f"{file_name}:{factory_name} PrimaryNameAttribute must match the IsPrimaryName "
            "SchemaName logical name."
        )


def test_live_0x80040203_primary_attribute_regression_contract() -> None:
    """Document the live CreateEntity failure shape and assert ACM payloads avoid it."""

    entities = _iter_entity_factories()
    assert entities, "No ACM entity factory payloads were discovered for contract validation."

    for file_name, factory_name, entity in entities:
        mutated_payload = deepcopy(entity)
        for attribute in mutated_payload["Attributes"]:
            attribute.pop("IsPrimaryName", None)

        failure = _create_entity_contract_response(mutated_payload)
        assert failure == {
            "error": {
                "code": LIVE_PRIMARY_ATTRIBUTE_ERROR_CODE,
                "message": LIVE_PRIMARY_ATTRIBUTE_ERROR_MESSAGE,
            }
        }, f"{file_name}:{factory_name} should reproduce the observed 0x80040203 failure shape."

        success = _create_entity_contract_response(entity)
        assert success == {"status_code": 204}, (
            f"{file_name}:{factory_name} should satisfy the PrimaryAttribute contract."
        )
