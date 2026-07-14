"""Regression tests for global-choice Name-to-MetadataId binding resolution."""

from __future__ import annotations

import importlib
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pytest
import requests

SOLUTION_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = SOLUTION_ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

_FAKE_UUID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
_NAME_BINDING = "/GlobalOptionSetDefinitions(Name='fsi_acv_scope')"
_GUID_BINDING = f"/GlobalOptionSetDefinitions({_FAKE_UUID})"

_OPTIONSET_RESPONSE: dict[str, Any] = {
    "MetadataId": _FAKE_UUID,
    "Name": "fsi_acv_scope",
}


def _make_picklist_attr() -> dict[str, Any]:
    """Return a fresh PicklistAttributeMetadata dict with a Name-keyed binding."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_Scope",
        "AttributeType": "Picklist",
        "AttributeTypeName": {"Value": "PicklistType"},
        "SourceTypeMask": 0,
        "GlobalOptionSet@odata.bind": _NAME_BINDING,
        "DisplayName": {"LocalizedLabels": [{"Label": "Scope", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
    }


def _make_string_attr() -> dict[str, Any]:
    """Return a fresh StringAttributeMetadata dict (no GlobalOptionSet@odata.bind)."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_RunId",
        "DisplayName": {"LocalizedLabels": [{"Label": "Run ID", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
    }


@dataclass
class FakeResponse:
    """Minimal requests.Response stand-in."""

    status_code: int = 200
    json_body: dict[str, Any] | None = None
    headers: dict[str, str] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self._json = self.json_body or {}

    def json(self) -> dict[str, Any]:
        return self._json

    @property
    def ok(self) -> bool:
        return self.status_code < 400

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise requests.HTTPError(f"HTTP {self.status_code}", response=self)


class QueueSession:
    """Queue-backed fake session recording all GET and POST calls."""

    def __init__(self, responses: list[Any]) -> None:
        self._responses = list(responses)
        self.calls: list[dict[str, Any]] = []

    def mount(self, *_args: Any, **_kwargs: Any) -> None:
        return

    def _dispatch(self, method: str, url: str, **kwargs: Any) -> Any:
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
            raise AssertionError(f"Unexpected {method} {url}")
        item = self._responses.pop(0)
        if isinstance(item, Exception):
            raise item
        return item

    def get(self, url: str, **kwargs: Any) -> FakeResponse:
        return self._dispatch("GET", url, **kwargs)

    def post(self, url: str, **kwargs: Any) -> FakeResponse:
        return self._dispatch("POST", url, **kwargs)


class _DummyConfidentialClientApplication:
    def __init__(self, **_kwargs: Any) -> None:
        pass

    def acquire_token_for_client(self, **_kwargs: Any) -> dict[str, str]:
        return {"access_token": "fake-token"}


def _build_client(
    monkeypatch: pytest.MonkeyPatch,
    module_name: str,
    session: QueueSession,
    *,
    bootstrap_ready: bool = True,
    dry_run: bool = False,
) -> tuple[Any, Any]:
    """Build an ACVClient or ALCAClient backed by *session*.

    *bootstrap_ready=True* (default) pre-marks the solution-context bootstrap
    as complete so test queues do not need to include bootstrap GET/POST responses.
    The bootstrap is independently tested in test_solution_context_bootstrap.py.
    """
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
        dry_run=dry_run,
    )
    if bootstrap_ready:
        client._solution_context_bootstrapper._ready = True
    return client, module


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_name_binding_resolves_to_metadataid_before_post(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    """Name-keyed GlobalOptionSet binding is resolved to MetadataId GUID before POST."""
    session = QueueSession(
        [
            FakeResponse(200, json_body=_OPTIONSET_RESPONSE),  # GlobalOptionSet lookup
            FakeResponse(204),  # create_attribute POST
        ]
    )
    client, _module = _build_client(monkeypatch, module_name, session)

    client.create_attribute("fsi_auditvalidationhistory", _make_picklist_attr())

    assert len(session.calls) == 2, f"Expected 2 calls, got {len(session.calls)}"

    get_call = session.calls[0]
    assert get_call["method"] == "GET"
    assert "GlobalOptionSetDefinitions(Name='fsi_acv_scope')" in get_call["url"]

    post_call = session.calls[1]
    assert post_call["method"] == "POST"
    assert post_call["url"].endswith(
        "/api/data/v9.2/EntityDefinitions(LogicalName='fsi_auditvalidationhistory')/Attributes"
    )
    sent_bind = post_call["json"]["GlobalOptionSet@odata.bind"]
    assert sent_bind == f"/GlobalOptionSetDefinitions({_FAKE_UUID})", (
        f"POST payload should carry MetadataId binding, got: {sent_bind!r}"
    )
    assert "Name=" not in sent_bind, (
        "POST payload must not retain the Name alternate-key form"
    )


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_original_input_dict_not_mutated_after_resolution(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    """The caller's attribute dict is not mutated when the Name binding is rewritten."""
    session = QueueSession(
        [
            FakeResponse(200, json_body=_OPTIONSET_RESPONSE),
            FakeResponse(204),
        ]
    )
    client, _module = _build_client(monkeypatch, module_name, session)

    attr = _make_picklist_attr()
    original_bind = attr["GlobalOptionSet@odata.bind"]
    original_keys = set(attr.keys())

    client.create_attribute("fsi_auditvalidationhistory", attr)

    assert attr["GlobalOptionSet@odata.bind"] == original_bind, (
        "create_attribute must not mutate the caller's GlobalOptionSet@odata.bind"
    )
    assert set(attr.keys()) == original_keys, (
        "create_attribute must not add or remove keys from the caller's dict"
    )


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_missing_optionset_raises_before_post(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    """RuntimeError is raised before POST when the referenced option set is not found."""
    session = QueueSession(
        [
            FakeResponse(404),  # GlobalOptionSet not found
        ]
    )
    client, _module = _build_client(monkeypatch, module_name, session)

    with pytest.raises(RuntimeError, match=r"fsi_acv_scope.*not found"):
        client.create_attribute("fsi_auditvalidationhistory", _make_picklist_attr())

    post_calls = [c for c in session.calls if c["method"] == "POST"]
    assert post_calls == [], "POST must not be issued when the option set is missing"


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_absent_metadataid_raises_before_post(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    """RuntimeError is raised before POST when MetadataId is absent from the response."""
    session = QueueSession(
        [
            # Option set found but has no MetadataId key
            FakeResponse(200, json_body={"Name": "fsi_acv_scope"}),
        ]
    )
    client, _module = _build_client(monkeypatch, module_name, session)

    with pytest.raises(RuntimeError, match=r"MetadataId"):
        client.create_attribute("fsi_auditvalidationhistory", _make_picklist_attr())

    post_calls = [c for c in session.calls if c["method"] == "POST"]
    assert post_calls == [], "POST must not be issued when MetadataId is absent"


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_invalid_metadataid_raises_before_post(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    """RuntimeError is raised before POST when MetadataId is not a valid UUID."""
    session = QueueSession(
        [
            FakeResponse(200, json_body={"MetadataId": "not-a-guid", "Name": "fsi_acv_scope"}),
        ]
    )
    client, _module = _build_client(monkeypatch, module_name, session)

    with pytest.raises(RuntimeError, match=r"MetadataId"):
        client.create_attribute("fsi_auditvalidationhistory", _make_picklist_attr())

    post_calls = [c for c in session.calls if c["method"] == "POST"]
    assert post_calls == [], "POST must not be issued when MetadataId is invalid"


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_existing_guid_binding_passes_through_without_lookup(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    """A payload already using a MetadataId GUID binding is posted with no lookup call."""
    session = QueueSession(
        [
            FakeResponse(204),  # Only the POST; no GET expected
        ]
    )
    client, _module = _build_client(monkeypatch, module_name, session)

    attr = {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_Scope",
        "AttributeType": "Picklist",
        "AttributeTypeName": {"Value": "PicklistType"},
        "SourceTypeMask": 0,
        "GlobalOptionSet@odata.bind": _GUID_BINDING,
        "RequiredLevel": {"Value": "None"},
    }
    client.create_attribute("fsi_auditvalidationhistory", attr)

    assert len(session.calls) == 1, "Only the POST should be issued for a GUID binding"
    assert session.calls[0]["method"] == "POST"
    assert session.calls[0]["json"]["GlobalOptionSet@odata.bind"] == _GUID_BINDING


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_invalid_binding_format_raises_before_post(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    """Malformed global-choice bindings fail before a Dataverse POST."""
    session = QueueSession([])
    client, _module = _build_client(monkeypatch, module_name, session)
    attr = _make_picklist_attr()
    attr["GlobalOptionSet@odata.bind"] = "/GlobalOptionSetDefinitions(not-a-guid)"

    with pytest.raises(RuntimeError, match=r"invalid MetadataId"):
        client.create_attribute("fsi_auditvalidationhistory", attr)

    assert session.calls == []


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_non_choice_attribute_passes_through_without_lookup(
    monkeypatch: pytest.MonkeyPatch, module_name: str
) -> None:
    """String attribute (no GlobalOptionSet@odata.bind) is posted without any lookup."""
    session = QueueSession(
        [
            FakeResponse(204),
        ]
    )
    client, _module = _build_client(monkeypatch, module_name, session)

    client.create_attribute("fsi_auditvalidationhistory", _make_string_attr())

    assert len(session.calls) == 1, "Only the POST should be issued for a non-choice attribute"
    assert session.calls[0]["method"] == "POST"
    assert "GlobalOptionSet@odata.bind" not in session.calls[0]["json"]


@pytest.mark.parametrize("module_name", ["acv_client", "alca_client"])
def test_dry_run_makes_no_lookup_or_post(
    monkeypatch: pytest.MonkeyPatch, module_name: str, capsys: pytest.CaptureFixture[str]
) -> None:
    """In dry-run mode create_attribute makes no network calls and returns the original dict."""
    session = QueueSession([])  # Empty queue — any call would be an assertion error
    client, _module = _build_client(monkeypatch, module_name, session, dry_run=True)

    attr = _make_picklist_attr()
    result = client.create_attribute("fsi_auditvalidationhistory", attr)

    assert session.calls == [], "dry-run must not make any GET or POST calls"
    assert result is attr, "dry-run must return the original attribute dict"
    out = capsys.readouterr().out
    assert "DRY RUN" in out
