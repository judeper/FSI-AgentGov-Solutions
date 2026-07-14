"""Runtime contracts for ACM Dataverse solution-context bootstrap behavior."""

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

SOLUTION_FILTER = "uniquename eq 'AuditComplianceManager'"
PUBLISHER_FILTER = "customizationprefix eq 'fsi' or uniquename eq 'FSIPublisher'"


@dataclass
class FakeResponse:
    """Minimal requests.Response stand-in."""

    status_code: int = 200
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


class FakeSession:
    """Queue-driven fake requests.Session."""

    def __init__(self, expected_calls: list[dict[str, Any]]) -> None:
        self.expected_calls = expected_calls
        self.calls: list[dict[str, Any]] = []

    def mount(self, *_args: Any, **_kwargs: Any) -> None:
        return

    def get(self, url: str, **kwargs: Any) -> FakeResponse:
        return self._request("GET", url, **kwargs)

    def post(self, url: str, **kwargs: Any) -> FakeResponse:
        return self._request("POST", url, **kwargs)

    def _request(self, method: str, url: str, **kwargs: Any) -> FakeResponse:
        call = {
            "method": method,
            "url": url,
            "headers": kwargs.get("headers", {}),
            "params": kwargs.get("params"),
            "json": kwargs.get("json"),
        }
        self.calls.append(call)

        if not self.expected_calls:
            raise AssertionError(f"Unexpected request: {method} {url}")

        expected = self.expected_calls.pop(0)
        assert expected["method"] == method
        assert url.endswith(expected["url_suffix"])
        if "params" in expected:
            assert call["params"] == expected["params"]

        response = expected["response"]
        if callable(response):
            return response(call, self)
        return response


class _DummyConfidentialClientApplication:
    def __init__(self, **_kwargs: Any) -> None:
        pass

    def acquire_token_for_client(self, **_kwargs: Any) -> dict[str, str]:
        return {"access_token": "fake-token"}


def _build_client(monkeypatch: pytest.MonkeyPatch, module_name: str, session: FakeSession):
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
def test_existing_solution_noop_then_solution_header_on_write(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    session = FakeSession(
        expected_calls=[
            {
                "method": "GET",
                "url_suffix": "/api/data/v9.2/solutions",
                "params": {
                    "$select": "solutionid,uniquename,friendlyname,version",
                    "$filter": SOLUTION_FILTER,
                },
                "response": FakeResponse(
                    json_body={
                        "value": [
                            {
                                "solutionid": "22222222-2222-2222-2222-222222222222",
                                "uniquename": "AuditComplianceManager",
                            }
                        ]
                    }
                ),
            },
            {
                "method": "POST",
                "url_suffix": "/api/data/v9.2/GlobalOptionSetDefinitions",
                "response": FakeResponse(status_code=204),
            },
        ]
    )
    client = _build_client(monkeypatch, module_name, session)
    client.create_global_optionset({"Name": "fsi_test_choice", "Options": []})

    assert len(session.calls) == 2
    assert "MSCRM.SolutionUniqueName" not in session.calls[0]["headers"]
    assert (
        session.calls[1]["headers"].get("MSCRM.SolutionUniqueName")
        == "AuditComplianceManager"
    )


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_missing_solution_bootstraps_publisher_then_solution_with_expected_payload(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    session = FakeSession(
        expected_calls=[
            {
                "method": "GET",
                "url_suffix": "/api/data/v9.2/solutions",
                "params": {
                    "$select": "solutionid,uniquename,friendlyname,version",
                    "$filter": SOLUTION_FILTER,
                },
                "response": FakeResponse(json_body={"value": []}),
            },
            {
                "method": "GET",
                "url_suffix": "/api/data/v9.2/publishers",
                "params": {
                    "$select": "publisherid,uniquename,friendlyname,customizationprefix,customizationoptionvalueprefix",
                    "$filter": PUBLISHER_FILTER,
                },
                "response": FakeResponse(json_body={"value": []}),
            },
            {
                "method": "POST",
                "url_suffix": "/api/data/v9.2/publishers",
                "response": FakeResponse(
                    status_code=204,
                    headers={
                        "OData-EntityId": "https://contoso.crm.dynamics.com/api/data/v9.2/"
                        "publishers(11111111-1111-1111-1111-111111111111)"
                    },
                ),
            },
            {
                "method": "POST",
                "url_suffix": "/api/data/v9.2/solutions",
                "response": FakeResponse(status_code=204),
            },
            {
                "method": "POST",
                "url_suffix": "/api/data/v9.2/GlobalOptionSetDefinitions",
                "response": FakeResponse(status_code=204),
            },
        ]
    )
    client = _build_client(monkeypatch, module_name, session)
    client.create_global_optionset({"Name": "fsi_test_choice", "Options": []})

    publisher_payload = session.calls[2]["json"]
    assert publisher_payload["friendlyname"] == "FSIPublisher"
    assert publisher_payload["uniquename"] == "FSIPublisher"
    assert publisher_payload["customizationprefix"] == "fsi"
    assert publisher_payload["customizationoptionvalueprefix"] == 10000

    solution_payload = session.calls[3]["json"]
    assert solution_payload["friendlyname"] == "Audit Compliance Manager"
    assert solution_payload["uniquename"] == "AuditComplianceManager"
    assert solution_payload["version"] == "1.0.6.0"
    assert (
        solution_payload["publisherid@odata.bind"]
        == "/publishers(11111111-1111-1111-1111-111111111111)"
    )

    for index in (0, 1, 2, 3):
        assert "MSCRM.SolutionUniqueName" not in session.calls[index]["headers"]
    assert (
        session.calls[4]["headers"].get("MSCRM.SolutionUniqueName")
        == "AuditComplianceManager"
    )


def test_acv_create_record_bootstraps_solution_for_env_var_and_connection_paths(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    session = FakeSession(
        expected_calls=[
            {
                "method": "GET",
                "url_suffix": "/api/data/v9.2/solutions",
                "params": {
                    "$select": "solutionid,uniquename,friendlyname,version",
                    "$filter": SOLUTION_FILTER,
                },
                "response": FakeResponse(json_body={"value": []}),
            },
            {
                "method": "GET",
                "url_suffix": "/api/data/v9.2/publishers",
                "params": {
                    "$select": "publisherid,uniquename,friendlyname,customizationprefix,customizationoptionvalueprefix",
                    "$filter": PUBLISHER_FILTER,
                },
                "response": FakeResponse(
                    json_body={
                        "value": [
                            {
                                "publisherid": "33333333-3333-3333-3333-333333333333",
                                "uniquename": "FSIPublisher",
                                "customizationprefix": "fsi",
                            }
                        ]
                    }
                ),
            },
            {
                "method": "POST",
                "url_suffix": "/api/data/v9.2/solutions",
                "response": FakeResponse(status_code=204),
            },
            {
                "method": "POST",
                "url_suffix": "/api/data/v9.2/environmentvariabledefinitions",
                "response": FakeResponse(
                    status_code=204,
                    headers={
                        "OData-EntityId": "https://contoso.crm.dynamics.com/api/data/v9.2/"
                        "environmentvariabledefinitions(44444444-4444-4444-4444-444444444444)"
                    },
                ),
            },
        ]
    )
    client = _build_client(monkeypatch, "acv_client", session)
    record_id = client.create_record(
        "environmentvariabledefinitions",
        {"schemaname": "fsi_ACV_Test"},
    )

    assert record_id == "44444444-4444-4444-4444-444444444444"
    assert "MSCRM.SolutionUniqueName" not in session.calls[2]["headers"]
    assert (
        session.calls[3]["headers"].get("MSCRM.SolutionUniqueName")
        == "AuditComplianceManager"
    )


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_live_404_regression_contract_bootstraps_before_optionset_post(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    def _optionset_contract_response(_call: dict[str, Any], state: FakeSession) -> FakeResponse:
        solution_bootstrapped = any(
            c["method"] == "POST" and c["url"].endswith("/api/data/v9.2/solutions")
            for c in state.calls[:-1]
        )
        if not solution_bootstrapped:
            return FakeResponse(status_code=404, json_body={"error": {"message": "Solution not found"}})
        return FakeResponse(status_code=204)

    session = FakeSession(
        expected_calls=[
            {
                "method": "GET",
                "url_suffix": "/api/data/v9.2/solutions",
                "params": {
                    "$select": "solutionid,uniquename,friendlyname,version",
                    "$filter": SOLUTION_FILTER,
                },
                "response": FakeResponse(json_body={"value": []}),
            },
            {
                "method": "GET",
                "url_suffix": "/api/data/v9.2/publishers",
                "params": {
                    "$select": "publisherid,uniquename,friendlyname,customizationprefix,customizationoptionvalueprefix",
                    "$filter": PUBLISHER_FILTER,
                },
                "response": FakeResponse(json_body={"value": []}),
            },
            {
                "method": "POST",
                "url_suffix": "/api/data/v9.2/publishers",
                "response": FakeResponse(
                    status_code=204,
                    headers={
                        "OData-EntityId": "https://contoso.crm.dynamics.com/api/data/v9.2/"
                        "publishers(55555555-5555-5555-5555-555555555555)"
                    },
                ),
            },
            {
                "method": "POST",
                "url_suffix": "/api/data/v9.2/solutions",
                "response": FakeResponse(status_code=204),
            },
            {
                "method": "POST",
                "url_suffix": "/api/data/v9.2/GlobalOptionSetDefinitions",
                "response": _optionset_contract_response,
            },
        ]
    )
    client = _build_client(monkeypatch, module_name, session)
    client.create_global_optionset({"Name": "fsi_contract_choice", "Options": []})

    call_urls = [call["url"] for call in session.calls]
    assert call_urls.index("https://contoso.crm.dynamics.com/api/data/v9.2/solutions") < call_urls.index(
        "https://contoso.crm.dynamics.com/api/data/v9.2/GlobalOptionSetDefinitions"
    )
