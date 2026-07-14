"""Regression tests for Dataverse metadata publication/readiness gates in ACM."""

from __future__ import annotations

import importlib
import itertools
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

import pytest
import requests

SOLUTION_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = SOLUTION_ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))


@dataclass
class FakeResponse:
    """Minimal requests.Response stand-in."""

    status_code: int
    json_body: dict[str, Any] | None = None
    headers: dict[str, str] | None = None

    def __post_init__(self) -> None:
        self._json = self.json_body or {}
        self.headers = self.headers or {}

    def json(self) -> dict[str, Any]:
        return self._json

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise requests.HTTPError(f"HTTP {self.status_code}", response=self)

    @property
    def ok(self) -> bool:
        return self.status_code < 400


class QueueSession:
    """Queue-backed fake session."""

    def __init__(self, responses: list[FakeResponse]) -> None:
        self._responses = responses
        self.calls: list[dict[str, Any]] = []

    def mount(self, *_args: Any, **_kwargs: Any) -> None:
        return

    def get(self, url: str, **kwargs: Any) -> FakeResponse:
        return self._request("GET", url, **kwargs)

    def post(self, url: str, **kwargs: Any) -> FakeResponse:
        return self._request("POST", url, **kwargs)

    def _request(self, method: str, url: str, **kwargs: Any) -> FakeResponse:
        self.calls.append(
            {
                "method": method,
                "url": url,
                "headers": kwargs.get("headers", {}),
                "json": kwargs.get("json"),
                "params": kwargs.get("params"),
            }
        )
        if not self._responses:
            raise AssertionError(f"Unexpected request: {method} {url}")
        return self._responses.pop(0)


class AlwaysStatusSession:
    """Session that always returns the same status code."""

    def __init__(self, status_code: int) -> None:
        self._status_code = status_code
        self.calls: list[dict[str, Any]] = []

    def mount(self, *_args: Any, **_kwargs: Any) -> None:
        return

    def get(self, url: str, **kwargs: Any) -> FakeResponse:
        self.calls.append(
            {
                "method": "GET",
                "url": url,
                "headers": kwargs.get("headers", {}),
            }
        )
        return FakeResponse(status_code=self._status_code)

    def post(self, url: str, **kwargs: Any) -> FakeResponse:
        self.calls.append(
            {
                "method": "POST",
                "url": url,
                "headers": kwargs.get("headers", {}),
                "json": kwargs.get("json"),
            }
        )
        return FakeResponse(status_code=self._status_code)


class _DummyConfidentialClientApplication:
    def __init__(self, **_kwargs: Any) -> None:
        pass

    def acquire_token_for_client(self, **_kwargs: Any) -> dict[str, str]:
        return {"access_token": "fake-token"}


def _build_client(monkeypatch: pytest.MonkeyPatch, module_name: str, session: Any):
    module = importlib.import_module(module_name)
    monkeypatch.setattr(module.requests, "Session", lambda: session)
    monkeypatch.setattr(
        module.msal,
        "ConfidentialClientApplication",
        _DummyConfidentialClientApplication,
    )
    client_cls = getattr(module, "ACVClient", None) or getattr(module, "ALCAClient")
    client = client_cls(
        tenant_id="00000000-0000-0000-0000-000000000000",
        environment_url="https://contoso.crm.dynamics.com",
        client_id="11111111-1111-1111-1111-111111111111",
        client_secret="dev-only-secret",
        solution_name="AuditComplianceManager",
    )
    return client, module


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_publish_all_customizations_uses_non_solution_headers(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    session = QueueSession([FakeResponse(status_code=204)])
    client, _module = _build_client(monkeypatch, module_name, session)

    client.publish_all_customizations()

    assert len(session.calls) == 1
    call = session.calls[0]
    assert call["method"] == "POST"
    assert call["url"].endswith("/api/data/v9.2/PublishAllXml")
    assert call["json"] == {}
    assert "MSCRM.SolutionUniqueName" not in call["headers"]


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_attribute_readiness_wait_tolerates_transient_500_until_success(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    session = QueueSession(
        [
            FakeResponse(status_code=500),
            FakeResponse(status_code=500),
            FakeResponse(
                status_code=200, json_body={"value": [{"LogicalName": "fsi_runid"}]}
            ),
        ]
    )
    client, _module = _build_client(monkeypatch, module_name, session)

    metadata = client.wait_for_attribute_metadata_readiness(
        "fsi_auditvalidationhistory",
        "fsi_runid",
        timeout_seconds=30.0,
        poll_interval_seconds=0.0,
    )

    assert metadata["LogicalName"] == "fsi_runid"
    assert len(session.calls) == 3


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_entity_readiness_wait_times_out_with_last_status(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    session = AlwaysStatusSession(status_code=500)
    client, module = _build_client(monkeypatch, module_name, session)
    monotonic_counter = itertools.count()
    monkeypatch.setattr(module.time, "monotonic", lambda: float(next(monotonic_counter)))
    monkeypatch.setattr(module.time, "sleep", lambda _seconds: None)

    with pytest.raises(TimeoutError, match=r"last_status=500"):
        client.wait_for_entity_metadata_readiness(
            "fsi_auditvalidationhistory",
            timeout_seconds=2.0,
            poll_interval_seconds=0.0,
        )


class ACVSchemaRecorder:
    """Capture ACV schema-client calls for order assertions."""

    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []
        self.inventory: dict[str, set[str]] = {}
        self.created_columns: list[tuple[str, str]] = []
        # Maps entity logical name → metadata dict to return from get_entity_metadata.
        # Absent key → returns None (entity does not exist). Default: all absent.
        self.entity_data: dict[str, Any] = {}

    def get_entity_metadata(self, logical_name: str) -> Optional[dict]:
        self.calls.append(("get_entity", logical_name))
        return self.entity_data.get(logical_name)

    def create_entity(self, entity_metadata: dict) -> dict:
        self.calls.append(("create_entity", entity_metadata["SchemaName"].lower()))
        return {"LogicalName": entity_metadata["SchemaName"].lower()}

    def publish_all_customizations(self) -> None:
        self.calls.append(("publish",))

    def wait_for_entity_metadata_readiness(self, logical_name: str) -> None:
        self.calls.append(("wait_entity", logical_name))

    def list_attribute_logical_names(self, entity_logical_name: str) -> set[str]:
        self.calls.append(("list_attrs", entity_logical_name))
        return set(self.inventory.get(entity_logical_name, set()))

    def get_attribute_metadata(self, entity_logical_name: str, attribute_logical_name: str) -> None:
        raise AssertionError(
            "create_columns should inventory once and must not call get_attribute_metadata"
        )

    def create_attribute(self, entity_logical_name: str, attribute_metadata: dict) -> dict:
        logical_name = attribute_metadata["SchemaName"].lower()
        self.calls.append(
            ("create_attr", entity_logical_name, logical_name)
        )
        self.created_columns.append((entity_logical_name, logical_name))
        return attribute_metadata

    def wait_for_attribute_metadata_readiness(
        self, entity_logical_name: str, attribute_logical_name: str
    ) -> None:
        self.calls.append(("wait_attr", entity_logical_name, attribute_logical_name))


class ALCASchemaRecorder:
    """Capture ALCA schema-client calls for order assertions."""

    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []
        self.inventory: dict[str, set[str]] = {}
        self.created_columns: list[tuple[str, str]] = []
        # Maps entity logical name → metadata dict to return from get_entity_metadata.
        # Absent key → returns None (entity does not exist). Default: all absent.
        self.entity_data: dict[str, Any] = {}

    def get_entity_metadata(self, logical_name: str) -> Optional[dict]:
        self.calls.append(("get_entity", logical_name))
        return self.entity_data.get(logical_name)

    def create_entity(self, entity_metadata: dict) -> dict:
        self.calls.append(("create_entity", entity_metadata["SchemaName"].lower()))
        return {"LogicalName": entity_metadata["SchemaName"].lower()}

    def publish_all_customizations(self) -> None:
        self.calls.append(("publish",))

    def wait_for_entity_metadata_readiness(self, logical_name: str) -> None:
        self.calls.append(("wait_entity", logical_name))

    def list_attribute_logical_names(self, entity_logical_name: str) -> set[str]:
        self.calls.append(("list_attrs", entity_logical_name))
        return set(self.inventory.get(entity_logical_name, set()))

    def get_attribute_metadata(self, entity_logical_name: str, attribute_logical_name: str) -> None:
        raise AssertionError(
            "create_columns should inventory once and must not call get_attribute_metadata"
        )

    def create_attribute(self, entity_logical_name: str, attribute_metadata: dict) -> dict:
        logical_name = attribute_metadata["SchemaName"].lower()
        self.calls.append(
            ("create_attr", entity_logical_name, logical_name)
        )
        self.created_columns.append((entity_logical_name, logical_name))
        return attribute_metadata

    def wait_for_attribute_metadata_readiness(
        self, entity_logical_name: str, attribute_logical_name: str
    ) -> None:
        self.calls.append(("wait_attr", entity_logical_name, attribute_logical_name))


def test_acv_schema_publish_and_wait_order_for_tables_and_columns(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    acv_schema = importlib.import_module("create_dataverse_schema")
    client = ACVSchemaRecorder()

    acv_schema.create_tables(client, dry_run=False)
    assert client.calls == [
        ("get_entity", "fsi_auditvalidationhistory"),
        ("create_entity", "fsi_auditvalidationhistory"),
        ("publish",),
        ("wait_entity", "fsi_auditvalidationhistory"),
        ("get_entity", "fsi_environmentregistry"),
        ("create_entity", "fsi_environmentregistry"),
        ("publish",),
        ("wait_entity", "fsi_environmentregistry"),
    ]

    monkeypatch.setattr(
        acv_schema,
        "HISTORY_TABLE_COLUMNS",
        [
            {"SchemaName": "fsi_RunId"},
            {"SchemaName": "fsi_Scope"},
            {"SchemaName": "fsi_Scope"},
        ],
    )
    monkeypatch.setattr(acv_schema, "REGISTRY_TABLE_COLUMNS", [])
    client.inventory = {"fsi_auditvalidationhistory": {"fsi_runid"}}
    client.calls.clear()
    client.created_columns.clear()

    acv_schema.create_columns(client, dry_run=False)
    assert client.calls == [
        ("publish",),
        ("wait_entity", "fsi_auditvalidationhistory"),
        ("list_attrs", "fsi_auditvalidationhistory"),
        ("create_attr", "fsi_auditvalidationhistory", "fsi_scope"),
        ("publish",),
        ("wait_attr", "fsi_auditvalidationhistory", "fsi_scope"),
        ("publish",),
        ("wait_entity", "fsi_environmentregistry"),
        ("list_attrs", "fsi_environmentregistry"),
    ]
    assert client.created_columns == [("fsi_auditvalidationhistory", "fsi_scope")]


def test_alca_schema_publish_and_wait_order_for_table_and_columns(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    alca_schema = importlib.import_module("create_audit_compliance_schema")
    client = ALCASchemaRecorder()

    alca_schema.create_table(client, dry_run=False)
    assert client.calls == [
        ("get_entity", "fsi_auditenvironmentcompliance"),
        ("create_entity", "fsi_auditenvironmentcompliance"),
        ("publish",),
        ("wait_entity", "fsi_auditenvironmentcompliance"),
    ]

    monkeypatch.setattr(
        alca_schema,
        "TABLE_COLUMNS",
        [
            {"SchemaName": "fsi_EnvironmentId"},
            {"SchemaName": "fsi_AuditEnabled"},
            {"SchemaName": "fsi_AuditEnabled"},
        ],
    )
    client.inventory = {"fsi_auditenvironmentcompliance": {"fsi_environmentid"}}
    client.calls.clear()
    client.created_columns.clear()

    alca_schema.create_columns(client, dry_run=False)
    assert client.calls == [
        ("publish",),
        ("wait_entity", "fsi_auditenvironmentcompliance"),
        ("list_attrs", "fsi_auditenvironmentcompliance"),
        ("create_attr", "fsi_auditenvironmentcompliance", "fsi_auditenabled"),
        ("publish",),
        ("wait_attr", "fsi_auditenvironmentcompliance", "fsi_auditenabled"),
    ]
    assert client.created_columns == [("fsi_auditenvironmentcompliance", "fsi_auditenabled")]


def test_acv_create_columns_dry_run_missing_entity_skips_inventory(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Dry-run + missing entity: list_attribute_logical_names must not be called."""
    acv_schema = importlib.import_module("create_dataverse_schema")
    monkeypatch.setattr(acv_schema, "HISTORY_TABLE_COLUMNS", [{"SchemaName": "fsi_RunId"}])
    monkeypatch.setattr(acv_schema, "REGISTRY_TABLE_COLUMNS", [{"SchemaName": "fsi_EnvironmentId"}])

    client = ACVSchemaRecorder()
    # entity_data is empty: get_entity_metadata returns None for all entities

    acv_schema.create_columns(client, dry_run=True)

    list_calls = [t for t in client.calls if t[0] == "list_attrs"]
    assert list_calls == [], (
        "create_columns(dry_run=True) must not call list_attribute_logical_names "
        "when the entity does not exist (would block on 404 for ~180 s)"
    )
    assert ("get_entity", "fsi_auditvalidationhistory") in client.calls
    assert ("get_entity", "fsi_environmentregistry") in client.calls
    assert client.created_columns == []
    output = capsys.readouterr().out
    assert "fsi_runid: would create" in output
    assert "fsi_environmentid: would create" in output


def test_acv_create_columns_dry_run_existing_entity_inventories_and_skips(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Dry-run + existing entity: inventory is called and existing columns are skipped."""
    acv_schema = importlib.import_module("create_dataverse_schema")
    monkeypatch.setattr(
        acv_schema,
        "HISTORY_TABLE_COLUMNS",
        [{"SchemaName": "fsi_RunId"}, {"SchemaName": "fsi_Scope"}],
    )
    monkeypatch.setattr(acv_schema, "REGISTRY_TABLE_COLUMNS", [])

    client = ACVSchemaRecorder()
    client.entity_data = {"fsi_auditvalidationhistory": {"LogicalName": "fsi_auditvalidationhistory"}}
    client.inventory = {"fsi_auditvalidationhistory": {"fsi_runid"}}

    acv_schema.create_columns(client, dry_run=True)

    assert ("list_attrs", "fsi_auditvalidationhistory") in client.calls
    # registry entity absent from entity_data → no inventory call for it
    assert ("list_attrs", "fsi_environmentregistry") not in client.calls
    # dry-run: no actual creates
    assert client.created_columns == []
    output = capsys.readouterr().out
    assert "fsi_runid: already exists" in output
    assert "fsi_scope: would create" in output


def test_alca_create_columns_dry_run_missing_entity_skips_inventory(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Dry-run + missing entity: list_attribute_logical_names must not be called (ALCA)."""
    alca_schema = importlib.import_module("create_audit_compliance_schema")
    monkeypatch.setattr(
        alca_schema,
        "TABLE_COLUMNS",
        [{"SchemaName": "fsi_EnvironmentId", "@odata.type": "String"}],
    )

    client = ALCASchemaRecorder()
    # entity_data is empty: get_entity_metadata returns None

    alca_schema.create_columns(client, dry_run=True)

    list_calls = [t for t in client.calls if t[0] == "list_attrs"]
    assert list_calls == [], (
        "create_columns(dry_run=True) must not call list_attribute_logical_names "
        "when the entity does not exist (would block on 404 for ~180 s)"
    )
    assert ("get_entity", "fsi_auditenvironmentcompliance") in client.calls
    assert client.created_columns == []
    output = capsys.readouterr().out
    assert "fsi_environmentid: would create" in output


def test_alca_create_columns_dry_run_existing_entity_inventories_and_skips(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Dry-run + existing entity: inventory is called and existing columns are skipped (ALCA)."""
    alca_schema = importlib.import_module("create_audit_compliance_schema")
    monkeypatch.setattr(
        alca_schema,
        "TABLE_COLUMNS",
        [
            {"SchemaName": "fsi_EnvironmentId", "@odata.type": "String"},
            {"SchemaName": "fsi_AuditEnabled", "@odata.type": "Boolean"},
        ],
    )

    client = ALCASchemaRecorder()
    client.entity_data = {
        "fsi_auditenvironmentcompliance": {"LogicalName": "fsi_auditenvironmentcompliance"}
    }
    client.inventory = {"fsi_auditenvironmentcompliance": {"fsi_environmentid"}}

    alca_schema.create_columns(client, dry_run=True)

    assert ("list_attrs", "fsi_auditenvironmentcompliance") in client.calls
    # dry-run: no actual creates
    assert client.created_columns == []
    output = capsys.readouterr().out
    assert "fsi_environmentid: already exists" in output
    assert "fsi_auditenabled: would create" in output
