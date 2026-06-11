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
import sys
from pathlib import Path

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
