"""Regression tests for collection-filtered attribute metadata lookups in ACM clients."""

from __future__ import annotations

import importlib
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

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

    def __post_init__(self) -> None:
        self._json = self.json_body or {}

    def json(self) -> dict[str, Any]:
        return self._json

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise requests.HTTPError(f"HTTP {self.status_code}", response=self)


class QueueSession:
    """Queue-backed fake session that records request details."""

    def __init__(self, responses: list[FakeResponse]) -> None:
        self._responses = responses
        self.calls: list[dict[str, Any]] = []

    def mount(self, *_args: Any, **_kwargs: Any) -> None:
        return

    def get(self, url: str, **kwargs: Any) -> FakeResponse:
        self.calls.append(
            {
                "method": "GET",
                "url": url,
                "headers": kwargs.get("headers", {}),
                "params": kwargs.get("params"),
            }
        )
        if not self._responses:
            raise AssertionError(f"Unexpected request: GET {url}")
        return self._responses.pop(0)


class _DummyConfidentialClientApplication:
    def __init__(self, **_kwargs: Any) -> None:
        pass

    def acquire_token_for_client(self, **_kwargs: Any) -> dict[str, str]:
        return {"access_token": "fake-token"}


def _build_client(monkeypatch: pytest.MonkeyPatch, module_name: str, session: QueueSession):
    module = importlib.import_module(module_name)
    monkeypatch.setattr(module.requests, "Session", lambda: session)
    monkeypatch.setattr(
        module.msal,
        "ConfidentialClientApplication",
        _DummyConfidentialClientApplication,
    )
    client_cls = getattr(module, "ACVClient", None) or getattr(module, "ALCAClient")
    return client_cls(
        tenant_id="00000000-0000-0000-0000-000000000000",
        environment_url="https://contoso.crm.dynamics.com",
        client_id="11111111-1111-1111-1111-111111111111",
        client_secret="dev-only-secret",
        solution_name="AuditComplianceManager",
    )


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_attribute_lookup_returns_existing_match(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    session = QueueSession(
        [
            FakeResponse(
                status_code=200,
                json_body={"value": [{"LogicalName": "fsi_scope", "MetadataId": "abc"}]},
            )
        ]
    )
    client = _build_client(monkeypatch, module_name, session)

    metadata = client.get_attribute_metadata("fsi_auditvalidationhistory", "fsi_scope")

    assert metadata == {"LogicalName": "fsi_scope", "MetadataId": "abc"}
    assert len(session.calls) == 1
    request = session.calls[0]
    assert request["url"].endswith(
        "/api/data/v9.2/EntityDefinitions(LogicalName='fsi_auditvalidationhistory')/Attributes"
    )
    assert request["params"] == {
        "$select": "LogicalName,MetadataId",
        "$filter": "LogicalName eq 'fsi_scope'",
    }
    assert request["headers"]["OData-Version"] == "4.0"


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_attribute_lookup_returns_none_for_empty_collection(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    session = QueueSession([FakeResponse(status_code=200, json_body={"value": []})])
    client = _build_client(monkeypatch, module_name, session)

    metadata = client.get_attribute_metadata("fsi_auditvalidationhistory", "fsi_scope")

    assert metadata is None
    assert len(session.calls) == 1


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_attribute_lookup_escapes_single_quote_in_odata_filter(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    session = QueueSession([FakeResponse(status_code=200, json_body={"value": []})])
    client = _build_client(monkeypatch, module_name, session)

    client.get_attribute_metadata("fsi_auditvalidationhistory", "fsi_o'hare")

    assert session.calls[0]["params"]["$filter"] == "LogicalName eq 'fsi_o''hare'"


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_attribute_inventory_lists_existing_names_with_single_get(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    session = QueueSession(
        [
            FakeResponse(
                status_code=200,
                json_body={"value": [{"LogicalName": "fsi_runid"}, {"LogicalName": "fsi_scope"}]},
            )
        ]
    )
    client = _build_client(monkeypatch, module_name, session)

    names = client.list_attribute_logical_names("fsi_auditvalidationhistory")

    assert names == {"fsi_runid", "fsi_scope"}
    assert len(session.calls) == 1
    request = session.calls[0]
    assert request["url"].endswith(
        "/api/data/v9.2/EntityDefinitions(LogicalName='fsi_auditvalidationhistory')/Attributes"
    )
    assert request["params"] == {"$select": "LogicalName"}


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_attribute_inventory_follows_nextlink_pagination(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    session = QueueSession(
        [
            FakeResponse(
                status_code=200,
                json_body={
                    "value": [{"LogicalName": "fsi_runid"}],
                    "@odata.nextLink": "https://contoso.crm.dynamics.com/api/data/v9.2/next-page",
                },
            ),
            FakeResponse(
                status_code=200,
                json_body={"value": [{"LogicalName": "fsi_scope"}]},
            ),
        ]
    )
    client = _build_client(monkeypatch, module_name, session)

    names = client.list_attribute_logical_names("fsi_auditvalidationhistory")

    assert names == {"fsi_runid", "fsi_scope"}
    assert len(session.calls) == 2
    assert session.calls[0]["params"] == {"$select": "LogicalName"}
    assert session.calls[1]["url"] == "https://contoso.crm.dynamics.com/api/data/v9.2/next-page"
    assert session.calls[1]["params"] is None


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_attribute_readiness_wait_never_uses_alternate_key_endpoint(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    session = QueueSession(
        [
            FakeResponse(status_code=500),
            FakeResponse(status_code=200, json_body={"value": []}),
            FakeResponse(
                status_code=200,
                json_body={"value": [{"LogicalName": "fsi_scope", "MetadataId": "abc"}]},
            ),
        ]
    )
    client = _build_client(monkeypatch, module_name, session)

    metadata = client.wait_for_attribute_metadata_readiness(
        "fsi_auditvalidationhistory",
        "fsi_scope",
        timeout_seconds=10.0,
        poll_interval_seconds=0.0,
    )

    assert metadata["LogicalName"] == "fsi_scope"
    assert len(session.calls) == 3
    assert all("Attributes(LogicalName='" not in call["url"] for call in session.calls)
