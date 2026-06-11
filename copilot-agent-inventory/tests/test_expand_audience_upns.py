"""Unit tests for the pure audience-to-UPN expansion logic.

Imports ``scripts/expand_audience_upns.py``. That module has no third-party
imports at load time (Microsoft Graph / azure-identity / requests are imported
lazily inside ``GraphMemberResolver`` only), so it imports cleanly here and the
orchestration is exercised against an injected ``FakeResolver`` — no network, no
credential, no live tenant.

Coverage focuses on the defensive behaviours that make the audience list safe to
feed Copilot Billing Governance:

  * reference normalization across heterogeneous shapes (bare GUID, dict, UPN
    string, typed user/group),
  * "Everyone in the organization" detection — the tenant is NOT enumerated,
  * nested-group flattening (trusted to Graph transitiveMembers) and overlap
    de-duplication,
  * per-group cap / truncation flagging,
  * partial vs failed vs complete resolution status derivation,
  * agents with no sharing resolving to a clean empty audience,
  * the Dataverse write-back projection carrying counts/flags only (no PII).
"""

from __future__ import annotations

import json
import logging
import sys
import time
from pathlib import Path
from types import SimpleNamespace

SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import expand_audience_upns as eau  # noqa: E402


# ---------------------------------------------------------------------------
# Test double: an in-memory resolver implementing the MemberResolver protocol.
# ---------------------------------------------------------------------------


class FakeResolver:
    """In-memory MemberResolver. transitiveMembers output is assumed already
    flattened (as real Graph transitiveMembers is), so nested groups are modeled
    by simply listing every transitive member for a group id."""

    def __init__(self, group_map=None, user_map=None,
                 truncated_groups=None, error_groups=None):
        self.group_map = group_map or {}
        self.user_map = user_map or {}
        self.truncated_groups = set(truncated_groups or ())
        self.error_groups = error_groups or {}
        self.group_calls: list[str] = []
        self.user_calls: list[str] = []

    def transitive_member_upns(self, group_id: str) -> "eau.ResolveResult":
        self.group_calls.append(group_id)
        if group_id in self.error_groups:
            return eau.ResolveResult(error=self.error_groups[group_id])
        return eau.ResolveResult(
            upns=list(self.group_map.get(group_id, [])),
            truncated=group_id in self.truncated_groups,
        )

    def user_upn(self, user_id: str):
        self.user_calls.append(user_id)
        return self.user_map.get(user_id)


SENT = eau.DEFAULT_WHOLE_TENANT_SENTINELS
CFG = eau.ExpandConfig()


# ---------------------------------------------------------------------------
# Reference normalization
# ---------------------------------------------------------------------------


def test_normalize_group_ref_bare_guid_is_group():
    ref = eau.normalize_group_ref("11111111-1111-1111-1111-111111111111", SENT)
    assert ref.kind == "group"
    assert ref.value == "11111111-1111-1111-1111-111111111111"


def test_normalize_group_ref_dict_id_variants():
    for key in ("id", "groupId", "objectId"):
        ref = eau.normalize_group_ref({key: "gid-1", "displayName": "Sales"}, SENT)
        assert ref.kind == "group"
        assert ref.value == "gid-1"
        assert ref.display == "Sales"


def test_normalize_group_ref_whole_tenant_by_display_name():
    ref = eau.normalize_group_ref({"displayName": "Everyone in the organization"}, SENT)
    assert ref.kind == "whole_tenant"


def test_normalize_group_ref_whole_tenant_by_explicit_marker():
    assert eau.normalize_group_ref({"wholeTenant": True}, SENT).kind == "whole_tenant"
    assert eau.normalize_group_ref({"type": "Everyone"}, SENT).kind == "whole_tenant"


def test_normalize_group_ref_unrecognized_is_unknown():
    assert eau.normalize_group_ref(12345, SENT).kind == "unknown"
    assert eau.normalize_group_ref({"foo": "bar"}, SENT).kind == "unknown"


def test_normalize_editor_ref_upn_string_and_dict():
    assert eau.normalize_editor_ref("alice@contoso.com", SENT).kind == "user_upn"
    r = eau.normalize_editor_ref({"upn": "bob@contoso.com"}, SENT)
    assert r.kind == "user_upn" and r.value == "bob@contoso.com"
    r2 = eau.normalize_editor_ref({"userPrincipalName": "carol@contoso.com"}, SENT)
    assert r2.kind == "user_upn" and r2.value == "carol@contoso.com"


def test_normalize_editor_ref_typed_user_id_and_group():
    u = eau.normalize_editor_ref({"id": "uid-9", "type": "User"}, SENT)
    assert u.kind == "user_id" and u.value == "uid-9"
    g = eau.normalize_editor_ref({"id": "gid-9", "type": "Group"}, SENT)
    assert g.kind == "group" and g.value == "gid-9"


def test_normalize_editor_ref_bare_guid_treated_as_group():
    # Ambiguous bare GUID in editor context -> attempt group expansion.
    r = eau.normalize_editor_ref("22222222-2222-2222-2222-222222222222", SENT)
    assert r.kind == "group"


# ---------------------------------------------------------------------------
# Whole-tenant detection
# ---------------------------------------------------------------------------


def test_detect_whole_tenant_explicit_flag():
    assert eau.detect_whole_tenant({"sharedWithEveryone": True}, SENT) is True
    assert eau.detect_whole_tenant({"wholeTenant": True}, SENT) is True


def test_detect_whole_tenant_via_group_sentinel():
    agent = {"viewerGroups": [{"displayName": "Everyone except external users"}]}
    assert eau.detect_whole_tenant(agent, SENT) is True


def test_detect_whole_tenant_false_for_named_groups():
    agent = {"viewerGroups": ["gid-1"], "editorPrincipals": ["alice@contoso.com"]}
    assert eau.detect_whole_tenant(agent, SENT) is False


# ---------------------------------------------------------------------------
# expand_agent_audience — core behaviours
# ---------------------------------------------------------------------------


def test_expand_basic_dedup_and_sorted():
    resolver = FakeResolver(group_map={
        "g1": ["alice@contoso.com", "bob@contoso.com"],
        "g2": ["bob@contoso.com", "carol@contoso.com"],  # bob overlaps
    })
    agent = {"fsi_agentid": "bot-1", "fsi_agentname": "Helpdesk",
             "viewerGroups": ["g1", "g2"]}
    out = eau.expand_agent_audience(agent, resolver, CFG)
    upns = [u["upn"] for u in out["intendedUsers"]]
    assert upns == ["alice@contoso.com", "bob@contoso.com", "carol@contoso.com"]
    assert out["audienceSize"] == 3
    assert out["resolutionStatus"] == eau.STATUS_COMPLETE
    assert out["wholeTenant"] is False
    assert out["truncated"] is False


def test_expand_nested_group_members_flattened():
    # transitiveMembers flattens nested groups; the resolver returns the full set.
    resolver = FakeResolver(group_map={
        "parent": ["a@contoso.com", "b@contoso.com", "c@contoso.com"],
    })
    agent = {"fsi_agentid": "bot-2", "viewerGroups": ["parent"]}
    out = eau.expand_agent_audience(agent, resolver, CFG)
    assert out["audienceSize"] == 3
    assert out["sourceGroups"][0]["memberCount"] == 3


def test_expand_whole_tenant_not_enumerated():
    resolver = FakeResolver(group_map={"g1": ["x@contoso.com"]})
    agent = {"fsi_agentid": "bot-3", "sharedWithEveryone": True,
             "viewerGroups": ["g1"]}
    out = eau.expand_agent_audience(agent, resolver, CFG)
    assert out["wholeTenant"] is True
    assert out["intendedUsers"] == []
    assert out["audienceSize"] == 0
    assert out["resolutionStatus"] == eau.STATUS_WHOLE_TENANT
    # Crucially: the tenant was NOT enumerated.
    assert resolver.group_calls == []


def test_expand_truncation_sets_partial():
    resolver = FakeResolver(
        group_map={"big": ["u1@contoso.com", "u2@contoso.com"]},
        truncated_groups={"big"},
    )
    agent = {"fsi_agentid": "bot-4", "viewerGroups": ["big"]}
    out = eau.expand_agent_audience(agent, resolver, CFG)
    assert out["truncated"] is True
    assert out["resolutionStatus"] == eau.STATUS_PARTIAL
    assert out["sourceGroups"][0]["truncated"] is True


def test_expand_group_error_partial_when_other_members():
    resolver = FakeResolver(
        group_map={"ok": ["good@contoso.com"]},
        error_groups={"bad": "group not found (404)"},
    )
    agent = {"fsi_agentid": "bot-5", "viewerGroups": ["ok", "bad"]}
    out = eau.expand_agent_audience(agent, resolver, CFG)
    assert out["audienceSize"] == 1
    assert out["resolutionStatus"] == eau.STATUS_PARTIAL
    assert any(e["ref"] == "bad" for e in out["resolutionErrors"])


def test_expand_all_errors_no_members_is_failed():
    resolver = FakeResolver(error_groups={"bad": "HTTP 403"})
    agent = {"fsi_agentid": "bot-6", "viewerGroups": ["bad"]}
    out = eau.expand_agent_audience(agent, resolver, CFG)
    assert out["audienceSize"] == 0
    assert out["resolutionStatus"] == eau.STATUS_FAILED


def test_expand_no_sharing_is_clean_empty():
    resolver = FakeResolver()
    agent = {"fsi_agentid": "bot-7", "viewerGroups": [], "editorPrincipals": []}
    out = eau.expand_agent_audience(agent, resolver, CFG)
    assert out["audienceSize"] == 0
    assert out["intendedUsers"] == []
    assert out["resolutionStatus"] == eau.STATUS_COMPLETE
    assert out["resolutionErrors"] == []


def test_expand_editor_mix_user_group_and_userid():
    resolver = FakeResolver(
        group_map={"eg": ["team1@contoso.com", "alice@contoso.com"]},
        user_map={"uid-1": "dan@contoso.com"},
    )
    agent = {
        "fsi_agentid": "bot-8",
        "viewerGroups": [],
        "editorPrincipals": [
            {"upn": "alice@contoso.com"},            # direct user (also in eg -> dedup)
            {"id": "eg", "type": "Group"},            # group expansion
            {"id": "uid-1", "type": "User"},          # user id -> resolve UPN
        ],
    }
    out = eau.expand_agent_audience(agent, resolver, CFG)
    upns = {u["upn"] for u in out["intendedUsers"]}
    assert upns == {"alice@contoso.com", "team1@contoso.com", "dan@contoso.com"}
    assert "uid-1" in resolver.user_calls


def test_expand_unresolvable_user_id_records_error():
    resolver = FakeResolver()  # user_map empty -> cannot resolve
    agent = {"fsi_agentid": "bot-9",
             "editorPrincipals": [{"id": "ghost", "type": "User"}]}
    out = eau.expand_agent_audience(agent, resolver, CFG)
    assert out["audienceSize"] == 0
    assert any(e["ref"] == "ghost" for e in out["resolutionErrors"])
    assert out["resolutionStatus"] == eau.STATUS_FAILED


def test_expand_unknown_ref_records_error():
    resolver = FakeResolver()
    agent = {"fsi_agentid": "bot-10", "viewerGroups": [12345]}
    out = eau.expand_agent_audience(agent, resolver, CFG)
    assert any(e["error"] == "unrecognized sharing reference"
               for e in out["resolutionErrors"])


# ---------------------------------------------------------------------------
# Dataverse write-back projection — counts/flags only, no PII
# ---------------------------------------------------------------------------


def test_build_authshare_update_logical_names_and_no_pii():
    resolver = FakeResolver(group_map={"g1": ["a@contoso.com", "b@contoso.com"]})
    out = eau.expand_agent_audience(
        {"fsi_agentid": "bot-11", "fsi_environmentid": "env-1", "viewerGroups": ["g1"]},
        resolver, CFG)
    upd = eau.build_authshare_update(out, run_id="run-xyz")
    assert set(upd.keys()) == {
        "fsi_agentid", "fsi_environmentid", "fsi_audiencewholetenant",
        "fsi_audienceupncount", "fsi_audiencetruncated",
        "fsi_audienceresolutionstatus", "fsi_audienceresolvedat", "fsi_runid",
    }
    # Logical-name convention: lowercase, no inter-word underscore after the
    # fsi_ prefix.
    for key in upd:
        assert key == key.lower()
        assert "_" not in key[len("fsi_"):]
    # No UPNs / PII leaked into the Dataverse projection.
    blob = json.dumps(upd)
    assert "@contoso.com" not in blob
    assert "intendedUsers" not in upd
    assert upd["fsi_audienceupncount"] == 2
    assert upd["fsi_audienceresolvedat"].endswith("Z")


# ---------------------------------------------------------------------------
# expand_all summary + artifact
# ---------------------------------------------------------------------------


def test_expand_all_summary_counts():
    resolver = FakeResolver(
        group_map={"g1": ["a@contoso.com"]},
        error_groups={"bad": "HTTP 500"},
    )
    agents = [
        {"fsi_agentid": "a1", "viewerGroups": ["g1"]},
        {"fsi_agentid": "a2", "sharedWithEveryone": True},
        {"fsi_agentid": "a3", "viewerGroups": ["bad"]},
    ]
    art = eau.expand_all(agents, resolver, CFG, run_id="run-1")
    assert art["summary"]["agentCount"] == 3
    assert art["summary"]["wholeTenantAgentCount"] == 1
    assert art["summary"]["agentsWithResolutionErrors"] == 1
    assert art["schemaVersion"]
    assert len(art["agents"]) == 3
    assert len(art["authShareUpdates"]) == 3


# ---------------------------------------------------------------------------
# Input loading + dry-run resolver
# ---------------------------------------------------------------------------


def test_load_agents_from_input_object_and_array(tmp_path):
    obj = tmp_path / "obj.json"
    obj.write_text(json.dumps({"agents": [{"fsi_agentid": "x"}]}), encoding="utf-8")
    assert eau.load_agents_from_input(str(obj)) == [{"fsi_agentid": "x"}]

    arr = tmp_path / "arr.json"
    arr.write_text(json.dumps([{"fsi_agentid": "y"}]), encoding="utf-8")
    assert eau.load_agents_from_input(str(arr)) == [{"fsi_agentid": "y"}]


def test_load_agents_from_input_utf8_bom(tmp_path):
    p = tmp_path / "bom.json"
    p.write_text(json.dumps({"agents": []}), encoding="utf-8-sig")
    assert eau.load_agents_from_input(str(p)) == []


def test_dry_run_resolver_resolves_nothing():
    resolver = eau.DryRunResolver()
    assert resolver.user_upn("anything") is None
    res = resolver.transitive_member_upns("g1")
    assert res.upns == [] and res.error and "dry-run" in res.error


def test_dry_run_whole_tenant_still_flagged():
    resolver = eau.DryRunResolver()
    out = eau.expand_agent_audience({"fsi_agentid": "z", "sharedWithEveryone": True},
                                    resolver, CFG)
    assert out["wholeTenant"] is True
    assert out["resolutionStatus"] == eau.STATUS_WHOLE_TENANT


# ===========================================================================
# Regression tests for GATE-1 findings (H1, M1, M2, M4)
# ===========================================================================


def _install_fake_dataverse(monkeypatch, rows):
    """Inject a fake ``dataverse_client`` module so the Dataverse-backed paths
    (load_agents_from_dataverse / _write_back_authshare) can be exercised with no
    network or credential. Returns a ``captured`` dict recording init kwargs,
    queries (entity_set/select/filter_expr/top) and update_record calls.
    """
    import types

    captured: dict = {"queries": [], "updates": [], "init_kwargs": None}

    class _FakeClient:
        def __init__(self, **kwargs):
            captured["init_kwargs"] = kwargs

        def query(self, entity_set, select=None, filter_expr=None,
                  orderby=None, top=None):
            captured["queries"].append({
                "entity_set": entity_set, "select": select,
                "filter_expr": filter_expr, "top": top,
            })
            return [dict(r) for r in rows]

        def update_record(self, entity_set, record_id, payload):
            captured["updates"].append({
                "entity_set": entity_set, "id": record_id, "payload": payload,
            })

    module = types.ModuleType("dataverse_client")
    module.DataverseClient = _FakeClient  # type: ignore[attr-defined]
    monkeypatch.setitem(sys.modules, "dataverse_client", module)
    return captured


# --- H1: org-wide-shared agent must NOT become a confident empty audience ----

def test_dataverse_org_wide_agent_is_not_confident_empty(monkeypatch):
    # An agent shared org-wide (fsi_sharedwitheveryone=True) with no group refs.
    # The pre-fix loader inferred sharing from fsi_limitsharingmode (fake values)
    # and produced sharedWithEveryone=False -> an empty audience asserted Complete
    # for a tenant-reachable agent (the exact silent-success the design forbids).
    rows = [{
        "fsi_agentid": "org-wide-bot",
        "fsi_environmentid": "env-1",
        "fsi_sharedwitheveryone": True,
    }]
    captured = _install_fake_dataverse(monkeypatch, rows)

    agents = eau.load_agents_from_dataverse("https://x.crm.dynamics.com", "t", "default")

    # The loader reads the per-agent column and never the env-wide policy.
    select = captured["queries"][0]["select"]
    assert "fsi_sharedwitheveryone" in select
    assert "fsi_limitsharingmode" not in select
    assert agents[0].get("sharedWithEveryone") is True

    out = eau.expand_agent_audience(agents[0], FakeResolver(), CFG)
    assert out["wholeTenant"] is True
    assert out["resolutionStatus"] == eau.STATUS_WHOLE_TENANT
    assert out["resolutionStatus"] != eau.STATUS_COMPLETE


def test_dataverse_unknown_signal_refless_is_partial_not_confident_empty(
    monkeypatch, caplog
):
    # A posture row with NO whole-tenant signal and NO viewer/editor refs must be
    # marked Partial (signal unknown), never a confident empty Complete audience.
    rows = [{"fsi_agentid": "unknown-bot", "fsi_environmentid": "env-1"}]
    _install_fake_dataverse(monkeypatch, rows)

    agents = eau.load_agents_from_dataverse("https://x.crm.dynamics.com", "t", "default")
    assert agents[0].get("wholeTenantSignalKnown") is False
    assert "sharedWithEveryone" not in agents[0]

    with caplog.at_level(logging.WARNING, logger=eau.logger.name):
        out = eau.expand_agent_audience(agents[0], FakeResolver(), CFG)

    assert out["resolutionStatus"] == eau.STATUS_PARTIAL
    assert out["resolutionStatus"] != eau.STATUS_COMPLETE
    assert any("no whole-tenant signal" in r.getMessage() for r in caplog.records)


def test_dataverse_explicit_not_shared_with_everyone_stays_clean_empty(monkeypatch):
    # A genuine restricted agent (fsi_sharedwitheveryone=False, no refs) is a KNOWN
    # signal: a clean empty audience (Complete) is correct here.
    rows = [{"fsi_agentid": "restricted-bot", "fsi_sharedwitheveryone": False}]
    _install_fake_dataverse(monkeypatch, rows)

    agents = eau.load_agents_from_dataverse("https://x.crm.dynamics.com", "t", "default")
    assert agents[0].get("sharedWithEveryone") is False

    out = eau.expand_agent_audience(agents[0], FakeResolver(), CFG)
    assert out["wholeTenant"] is False
    assert out["resolutionStatus"] == eau.STATUS_COMPLETE


# --- M1: Graph token must refresh as it nears expiry (no 401 on long runs) ---

class _FakeAccessToken:
    def __init__(self, token, expires_on):
        self.token = token
        self.expires_on = expires_on


class _FakeCredential:
    def __init__(self, expires_on_seq):
        self._seq = list(expires_on_seq)
        self.calls = 0

    def get_token(self, *scopes, **kwargs):
        self.calls += 1
        exp = self._seq.pop(0) if self._seq else (time.time() + 3600)
        return _FakeAccessToken(f"token-{self.calls}", exp)


def _resolver_without_init():
    # Bypass __init__ (which imports requests) so the token-refresh logic is tested
    # hermetically with an injected fake credential.
    resolver = eau.GraphMemberResolver.__new__(eau.GraphMemberResolver)
    resolver.auth_mode = "managed-identity"
    resolver._access_token = None
    return resolver


def test_graph_resolver_refreshes_token_before_expiry():
    resolver = _resolver_without_init()
    now = time.time()
    # First token expires within the refresh skew (300s); second is long-lived.
    cred = _FakeCredential([now + 30, now + 3600])
    resolver._credential_obj = cred

    assert resolver._bearer_token() == "token-1"
    assert cred.calls == 1
    # Near-expiry token must be refreshed on the next request (the 401 fix).
    assert resolver._bearer_token() == "token-2"
    assert cred.calls == 2
    # Long-lived token is reused (no needless refetch).
    assert resolver._bearer_token() == "token-2"
    assert cred.calls == 2


def test_graph_resolver_headers_use_refreshed_token():
    resolver = _resolver_without_init()
    cred = _FakeCredential([time.time() + 3600])
    resolver._credential_obj = cred
    headers = resolver._headers()
    assert headers["Authorization"] == "Bearer token-1"


# --- M2: Retry-After parsing must survive the RFC 7231 HTTP-date format ------

def test_parse_retry_after_numeric_seconds():
    assert eau._parse_retry_after("5", 1.0) == 5.0
    assert eau._parse_retry_after("0", 1.0) == 0.0


def test_parse_retry_after_http_date_returns_delta():
    from datetime import datetime, timedelta, timezone
    from email.utils import format_datetime

    future = datetime.now(timezone.utc) + timedelta(seconds=120)
    delta = eau._parse_retry_after(format_datetime(future), 1.0)
    # ~120s minus a little execution time; never the fallback.
    assert 90.0 <= delta <= 121.0


def test_parse_retry_after_garbage_and_missing_fall_back():
    assert eau._parse_retry_after("not-a-date", 7.0) == 7.0
    assert eau._parse_retry_after(None, 9.0) == 9.0
    assert eau._parse_retry_after("", 3.0) == 3.0
    # A negative number is nonsensical -> fall back rather than sleep(-n).
    assert eau._parse_retry_after("-5", 2.0) == 2.0


# --- M4: OData write-back filter must escape single quotes --------------------

def test_odata_escape_doubles_single_quotes():
    assert eau._odata_escape("o'brien") == "o''brien"
    assert eau._odata_escape("plain") == "plain"
    assert eau._odata_escape("a'b'c") == "a''b''c"


def test_write_back_escapes_agent_id_in_filter(monkeypatch):
    captured = _install_fake_dataverse(monkeypatch, [{"fsi_caiauthshareid": "row-1"}])
    args = SimpleNamespace(
        environment_url="https://x.crm.dynamics.com",
        tenant_id="t", auth_mode="default",
    )
    updates = [{"fsi_agentid": "o'brien-bot", "fsi_audienceupncount": 3}]

    eau._write_back_authshare(updates, args)

    # The single quote in the agent id is doubled per the OData spec, so the
    # $filter is well-formed (and not an injection vector).
    assert captured["queries"][0]["filter_expr"] == "fsi_agentid eq 'o''brien-bot'"
    # fsi_agentid is stripped from the update payload (it is the lookup key).
    assert captured["updates"][0]["payload"] == {"fsi_audienceupncount": 3}
