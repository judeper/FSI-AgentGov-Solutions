"""Unit tests for setup_agent_identity_blueprint.py pure-logic functions.

Covers payload construction, scope configuration, permissions matching, and
scope normalization. Live Graph API validation requires human intervention
per issue #123.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from setup_agent_identity_blueprint import (
    MICROSOFT_GRAPH_APP_ID,
    build_blueprint_payload,
    normalize_allowed_scopes,
    permissions_match,
    scope_configuration,
)

# ---------------------------------------------------------------------------
# normalize_allowed_scopes
# ---------------------------------------------------------------------------


def test_normalize_allowed_scopes_none_returns_defaults() -> None:
    result = normalize_allowed_scopes(None)
    assert result == ["User.Read"]


def test_normalize_allowed_scopes_empty_string() -> None:
    result = normalize_allowed_scopes("")
    assert result == []


def test_normalize_allowed_scopes_single() -> None:
    result = normalize_allowed_scopes("Mail.Read")
    assert result == ["Mail.Read"]


def test_normalize_allowed_scopes_multiple() -> None:
    result = normalize_allowed_scopes("User.Read,Mail.Read,Files.Read")
    assert result == ["User.Read", "Mail.Read", "Files.Read"]


def test_normalize_allowed_scopes_deduplicates() -> None:
    result = normalize_allowed_scopes("User.Read,User.Read,Mail.Read")
    assert result == ["User.Read", "Mail.Read"]


def test_normalize_allowed_scopes_strips_whitespace() -> None:
    result = normalize_allowed_scopes(" User.Read , Mail.Read ")
    assert result == ["User.Read", "Mail.Read"]


# ---------------------------------------------------------------------------
# build_blueprint_payload
# ---------------------------------------------------------------------------


def test_build_blueprint_payload_structure() -> None:
    payload = build_blueprint_payload(
        display_name="TestBlueprint",
        description="Test description",
        sponsor_id="sponsor-guid",
    )
    assert payload["displayName"] == "TestBlueprint"
    assert payload["description"] == "Test description"
    assert payload["signInAudience"] == "AzureADMyOrg"
    assert "fsi-agent-intake" in payload["tags"]
    assert "identity-records-automation" in payload["tags"]
    assert any("sponsor-guid" in binding for binding in payload["sponsors@odata.bind"])


def test_build_blueprint_payload_sponsor_binding_format() -> None:
    """Sponsor binding must be a Graph v1.0 user URI."""
    payload = build_blueprint_payload(
        display_name="X",
        description="Y",
        sponsor_id="abc-123",
    )
    bindings = payload["sponsors@odata.bind"]
    assert len(bindings) == 1
    assert bindings[0] == "https://graph.microsoft.com/v1.0/users/abc-123"


# ---------------------------------------------------------------------------
# scope_configuration
# ---------------------------------------------------------------------------


def test_scope_configuration_no_scopes() -> None:
    """Empty scopes produce noScopes / noRoles."""
    config = scope_configuration([])
    assert config["resourceAppId"] == MICROSOFT_GRAPH_APP_ID
    assert config["inheritableScopes"]["@odata.type"] == "#microsoft.graph.noScopes"
    assert config["inheritableScopes"]["kind"] == "none"
    assert config["inheritableRoles"]["@odata.type"] == "#microsoft.graph.noRoles"


def test_scope_configuration_all_scopes() -> None:
    """Wildcard produces allAllowedScopes."""
    config = scope_configuration(["all"])
    assert config["inheritableScopes"]["@odata.type"] == "#microsoft.graph.allAllowedScopes"
    assert config["inheritableScopes"]["kind"] == "allAllowed"


def test_scope_configuration_all_star() -> None:
    """Star wildcard also produces allAllowedScopes."""
    config = scope_configuration(["*"])
    assert config["inheritableScopes"]["@odata.type"] == "#microsoft.graph.allAllowedScopes"


def test_scope_configuration_enumerated() -> None:
    """Specific scopes produce enumeratedScopes with the requested list."""
    config = scope_configuration(["User.Read", "Mail.Read"])
    assert config["inheritableScopes"]["@odata.type"] == "#microsoft.graph.enumeratedScopes"
    assert config["inheritableScopes"]["kind"] == "enumerated"
    assert config["inheritableScopes"]["scopes"] == ["User.Read", "Mail.Read"]


def test_scope_configuration_roles_always_none() -> None:
    """inheritableRoles is always noRoles regardless of scopes."""
    for scopes in [[], ["all"], ["User.Read"]]:
        config = scope_configuration(scopes)
        assert config["inheritableRoles"]["kind"] == "none"


# ---------------------------------------------------------------------------
# permissions_match
# ---------------------------------------------------------------------------


def test_permissions_match_identical() -> None:
    desired = scope_configuration(["User.Read", "Mail.Read"])
    existing = scope_configuration(["User.Read", "Mail.Read"])
    assert permissions_match(existing, desired) is True


def test_permissions_match_different_order() -> None:
    """Scope order should not matter."""
    desired = scope_configuration(["Mail.Read", "User.Read"])
    existing = scope_configuration(["User.Read", "Mail.Read"])
    assert permissions_match(existing, desired) is True


def test_permissions_mismatch_different_scopes() -> None:
    desired = scope_configuration(["User.Read"])
    existing = scope_configuration(["User.Read", "Mail.Read"])
    assert permissions_match(existing, desired) is False


def test_permissions_mismatch_different_type() -> None:
    desired = scope_configuration(["all"])
    existing = scope_configuration(["User.Read"])
    assert permissions_match(existing, desired) is False


def test_permissions_mismatch_different_app_id() -> None:
    desired = scope_configuration(["User.Read"])
    existing = {**scope_configuration(["User.Read"]), "resourceAppId": "different-app-id"}
    assert permissions_match(existing, desired) is False
