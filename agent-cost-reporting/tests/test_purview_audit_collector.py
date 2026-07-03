#!/usr/bin/env python3
"""Offline unit tests for the Purview audit beta collector (records-fetch + mapping).

No network access: @odata.nextLink pagination is exercised via an injected get_json
callable, and CopilotInteraction field mapping is checked against mocked auditLogRecord
payloads (dict and JSON-string auditData, case-insensitive keys, missing fields).

Run with: python -m pytest tests/test_purview_audit_collector.py
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys

SOLUTION_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(SOLUTION_ROOT, "scripts")
sys.path.insert(0, os.path.join(SCRIPTS, "shared"))


def _load():
    path = os.path.join(SCRIPTS, "collectors", "collect_purview_audit_queries_beta.py")
    spec = importlib.util.spec_from_file_location("collect_purview_audit_queries_beta", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MOD = _load()


def _sequential_pager(pages):
    """Return (get_json, calls) that yields the given pages in order, ignoring the url."""
    calls = {"n": 0}

    def get_json(url, headers):
        page = pages[calls["n"]]
        calls["n"] += 1
        return page

    return get_json, calls


def test_fetch_records_single_page():
    get_json, calls = _sequential_pager([{"value": [{"id": "r1"}, {"id": "r2"}]}])
    records = MOD.fetch_query_records("q1", "tok", get_json=get_json)
    assert [r["id"] for r in records] == ["r1", "r2"]
    assert calls["n"] == 1  # no nextLink -> exactly one request


def test_fetch_records_multi_page():
    pages = [
        {"value": [{"id": "r1"}], "@odata.nextLink": "https://graph/next1"},
        {"value": [{"id": "r2"}], "@odata.nextLink": "https://graph/next2"},
        {"value": [{"id": "r3"}]},  # final page, no nextLink
    ]
    get_json, calls = _sequential_pager(pages)
    records = MOD.fetch_query_records("q1", "tok", get_json=get_json)
    assert [r["id"] for r in records] == ["r1", "r2", "r3"]
    assert calls["n"] == 3


def test_fetch_records_empty():
    get_json, _ = _sequential_pager([{"value": []}])
    assert MOD.fetch_query_records("q1", "tok", get_json=get_json) == []


def test_fetch_records_missing_value_key():
    get_json, _ = _sequential_pager([{}])  # neither value nor nextLink present
    assert MOD.fetch_query_records("q1", "tok", get_json=get_json) == []


def test_fetch_records_repeated_nextlink_guard():
    # A server that echoes an identical nextLink must terminate, not loop forever.
    # The base URL is fetched once, the echoed link once, then the repeat is detected
    # and paging stops -- so exactly two pages are consumed and the call returns.
    page = {"value": [{"id": "r1"}], "@odata.nextLink": "https://graph/same"}
    records = MOD.fetch_query_records("q1", "tok", get_json=lambda url, headers: page)
    assert [r["id"] for r in records] == ["r1", "r1"]


def test_map_copilot_interaction_dict_auditdata():
    record = {
        "id": "40706737",
        "createdDateTime": "2026-06-16T17:12:00Z",
        "operation": "CopilotInteraction",
        "auditLogRecordType": "copilotInteraction",
        "organizationId": "org-1",
        "service": "Copilot",
        "userId": "user@contoso.com",
        "userPrincipalName": "user@contoso.com",
        "userType": "regular",
        "clientIp": "10.0.0.1",
        "auditData": {
            "AppHost": "BizChat",
            "AgentId": "agent-123",
            "Contexts": [{"Id": "doc1"}],
            "ThreadId": "thread-1",
            "MessageIds": ["m1", "m2"],
            "AccessedResources": [{"Name": "file.docx"}],
            "AISystemPlugin": [{"Name": "plugin"}],
        },
    }
    mapped = MOD.map_copilot_interaction(record)
    assert mapped["source_surface"] == MOD.lib.SURFACE_PURVIEW_AUDIT
    assert mapped["record_id"] == "40706737"
    assert mapped["operation"] == "CopilotInteraction"
    assert mapped["app_host"] == "BizChat"
    assert mapped["agent_id"] == "agent-123"
    assert mapped["thread_id"] == "thread-1"
    assert mapped["message_ids"] == ["m1", "m2"]
    assert mapped["user_principal_name"] == "user@contoso.com"


def test_map_copilot_interaction_json_string_auditdata_and_casing():
    # Some workloads deliver auditData as a JSON string, and casing may differ.
    record = {
        "id": "abc",
        "createdDateTime": "2026-06-16T00:00:00Z",
        "operation": "CopilotInteraction",
        "auditData": json.dumps({"apphost": "Word", "threadID": "t9", "messageIDs": ["x"]}),
    }
    mapped = MOD.map_copilot_interaction(record)
    assert mapped["app_host"] == "Word"
    assert mapped["thread_id"] == "t9"
    assert mapped["message_ids"] == ["x"]


def test_map_copilot_interaction_missing_auditdata():
    mapped = MOD.map_copilot_interaction({"id": "no-data", "operation": "CopilotInteraction"})
    assert mapped["record_id"] == "no-data"
    assert mapped["app_host"] is None
    assert mapped["agent_id"] is None


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("purview audit collector tests passed")
