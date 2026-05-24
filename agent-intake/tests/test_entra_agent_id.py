"""Unit tests for setup_entra_agent_id.py pure-logic functions.

Covers reviewer-attestation parsing, payload construction, approval-path
normalization, and evidence rendering — all exercisable without a live tenant.
Live API validation (HTTP 201 from Graph) requires human intervention per
issue #123.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from setup_entra_agent_id import (
    build_reviewer_evidence,
    normalize_approval_path,
    parse_iso8601_utc,
    parse_reviewer_attestations,
    planned_payload,
)

# ---------------------------------------------------------------------------
# normalize_approval_path
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("raw,expected", [
    ("Express", "Express"),
    ("express", "Express"),
    ("EXPRESS", "Express"),
    ("Standard", "Standard"),
    ("standard", "Standard"),
    ("Full", "Full"),
    ("full", "Full"),
])
def test_normalize_approval_path_valid(raw: str, expected: str) -> None:
    assert normalize_approval_path(raw) == expected


def test_normalize_approval_path_invalid() -> None:
    with pytest.raises(StopIteration):
        normalize_approval_path("Unknown")


# ---------------------------------------------------------------------------
# parse_iso8601_utc
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("raw,expected", [
    ("2026-05-16T12:34:56Z", "2026-05-16T12:34:56Z"),
    ("2026-05-16T12:34:56+00:00", "2026-05-16T12:34:56Z"),
    ("2026-05-16T08:34:56-04:00", "2026-05-16T12:34:56Z"),
])
def test_parse_iso8601_utc_valid(raw: str, expected: str) -> None:
    assert parse_iso8601_utc(raw) == expected


def test_parse_iso8601_utc_no_timezone() -> None:
    with pytest.raises(ValueError, match="must include a timezone"):
        parse_iso8601_utc("2026-05-16T12:34:56")


def test_parse_iso8601_utc_invalid_format() -> None:
    with pytest.raises(ValueError, match="Invalid decidedOnUtc"):
        parse_iso8601_utc("not-a-timestamp")


# ---------------------------------------------------------------------------
# parse_reviewer_attestations
# ---------------------------------------------------------------------------

VALID_SPONSOR_ATTESTATION = {
    "role": "Sponsor",
    "upn": "alice@contoso.com",
    "decidedOnUtc": "2026-05-16T12:34:56Z",
    "decisionPackHash": "a" * 64,
}

VALID_INFOSEC_ATTESTATION = {
    "role": "InfoSec",
    "upn": "bob@contoso.com",
    "decidedOnUtc": "2026-05-16T13:00:00Z",
    "decisionPackHash": "b" * 64,
}


def test_express_path_no_attestations() -> None:
    """Express path allows empty reviewer evidence."""
    result = parse_reviewer_attestations(
        None,
        approval_path="Express",
        sponsor_upn="alice@contoso.com",
    )
    assert result == []


def test_standard_requires_attestations() -> None:
    """Standard path must have reviewer evidence."""
    with pytest.raises(ValueError, match="required for Standard"):
        parse_reviewer_attestations(
            None,
            approval_path="Standard",
            sponsor_upn="alice@contoso.com",
        )


def test_full_requires_attestations() -> None:
    with pytest.raises(ValueError, match="required for Standard and Full"):
        parse_reviewer_attestations(
            None,
            approval_path="Full",
            sponsor_upn="alice@contoso.com",
        )


def test_valid_standard_attestations() -> None:
    """Standard path with sponsor + one non-sponsor reviewer."""
    items = [VALID_SPONSOR_ATTESTATION, VALID_INFOSEC_ATTESTATION]
    result = parse_reviewer_attestations(
        json.dumps(items),
        approval_path="Standard",
        sponsor_upn="alice@contoso.com",
    )
    assert len(result) == 2
    assert result[0]["role"] == "Sponsor"
    assert result[1]["role"] == "InfoSec"


def test_full_needs_three_non_sponsor() -> None:
    """Full path needs at least three non-sponsor attestations."""
    items = [VALID_SPONSOR_ATTESTATION, VALID_INFOSEC_ATTESTATION]
    with pytest.raises(ValueError, match="at least three non-Sponsor"):
        parse_reviewer_attestations(
            json.dumps(items),
            approval_path="Full",
            sponsor_upn="alice@contoso.com",
        )


def test_valid_full_attestations() -> None:
    """Full path with sponsor + three non-sponsor reviewers."""
    non_sponsor_roles = ["InfoSec", "Privacy", "Compliance"]
    items = [VALID_SPONSOR_ATTESTATION]
    for i, role in enumerate(non_sponsor_roles):
        items.append({
            "role": role,
            "upn": f"reviewer{i}@contoso.com",
            "decidedOnUtc": "2026-05-16T12:00:00Z",
            "decisionPackHash": f"{chr(ord('c') + i)}" * 64,
        })
    result = parse_reviewer_attestations(
        json.dumps(items),
        approval_path="Full",
        sponsor_upn="alice@contoso.com",
    )
    assert len(result) == 4
    non_sponsor = [r for r in result if r["role"] != "Sponsor"]
    assert len(non_sponsor) == 3


def test_sponsor_upn_mismatch_rejected() -> None:
    """Sponsor UPN must match the one passed via CLI."""
    items = [VALID_SPONSOR_ATTESTATION]
    with pytest.raises(ValueError, match="same UPN passed via --sponsor-upn"):
        parse_reviewer_attestations(
            json.dumps(items),
            approval_path="Express",
            sponsor_upn="someone-else@contoso.com",
        )


def test_invalid_json_rejected() -> None:
    with pytest.raises(ValueError, match="must be valid JSON"):
        parse_reviewer_attestations(
            "not-json",
            approval_path="Standard",
            sponsor_upn="alice@contoso.com",
        )


def test_empty_array_rejected() -> None:
    with pytest.raises(ValueError, match="non-empty JSON array"):
        parse_reviewer_attestations(
            "[]",
            approval_path="Standard",
            sponsor_upn="alice@contoso.com",
        )


def test_missing_fields_rejected() -> None:
    items = [{"role": "Sponsor"}]
    with pytest.raises(ValueError, match="missing required fields"):
        parse_reviewer_attestations(
            json.dumps(items),
            approval_path="Express",
            sponsor_upn="alice@contoso.com",
        )


def test_invalid_role_rejected() -> None:
    item = {**VALID_SPONSOR_ATTESTATION, "role": "CEO"}
    with pytest.raises(ValueError, match="unsupported role"):
        parse_reviewer_attestations(
            json.dumps([item]),
            approval_path="Express",
            sponsor_upn="alice@contoso.com",
        )


def test_invalid_upn_rejected() -> None:
    item = {**VALID_SPONSOR_ATTESTATION, "upn": "no-at-sign"}
    with pytest.raises(ValueError, match="invalid UPN"):
        parse_reviewer_attestations(
            json.dumps([item]),
            approval_path="Express",
            sponsor_upn="alice@contoso.com",
        )


def test_invalid_hash_rejected() -> None:
    item = {**VALID_SPONSOR_ATTESTATION, "decisionPackHash": "too-short"}
    with pytest.raises(ValueError, match="invalid decisionPackHash"):
        parse_reviewer_attestations(
            json.dumps([item]),
            approval_path="Express",
            sponsor_upn="alice@contoso.com",
        )


def test_must_include_sponsor_attestation() -> None:
    """Evidence must include at least one Sponsor entry."""
    items = [VALID_INFOSEC_ATTESTATION]
    with pytest.raises(ValueError, match="at least one Sponsor"):
        parse_reviewer_attestations(
            json.dumps(items),
            approval_path="Standard",
            sponsor_upn="bob@contoso.com",
        )


# ---------------------------------------------------------------------------
# build_reviewer_evidence
# ---------------------------------------------------------------------------

def test_build_reviewer_evidence_compact() -> None:
    """Short evidence fits in the compact notes format."""
    attestations = [
        {
            "role": "Sponsor",
            "upn": "alice@contoso.com",
            "decidedOnUtc": "2026-05-16T12:34:56Z",
            "decisionPackHash": "a" * 64,
        },
    ]
    note_text, extension = build_reviewer_evidence(attestations, approval_path="Express")
    assert note_text.startswith("fsi-agent-intake-reviewers:")
    assert extension["approvalPath"] == "Express"
    assert len(extension["reviewerAttestations"]) == 1


def test_build_reviewer_evidence_hash_fallback() -> None:
    """When compact payload exceeds 900 chars, hash fallback is used."""
    attestations = []
    for i in range(10):
        attestations.append({
            "role": "InfoSec",
            "upn": f"very-long-reviewer-name-{i}-extra-padding@contoso.onmicrosoft.com",
            "decidedOnUtc": "2026-05-16T12:34:56Z",
            "decisionPackHash": f"{i:0>64}",
        })
    note_text, extension = build_reviewer_evidence(attestations, approval_path="Full")
    assert "payloadSha256" in note_text
    assert extension["approvalPath"] == "Full"


# ---------------------------------------------------------------------------
# planned_payload
# ---------------------------------------------------------------------------

def test_planned_payload_express_no_attestations() -> None:
    """Express path with no reviewer attestations."""
    payload = planned_payload(
        display_name="Test Agent",
        sponsor_id="sponsor-guid-123",
        blueprint_id="blueprint-guid-456",
        intake_request_id="intake-guid-789",
        approval_path="Express",
        reviewer_attestations=None,
    )
    assert payload["displayName"] == "Test Agent"
    assert payload["agentIdentityBlueprintId"] == "blueprint-guid-456"
    assert "sponsors@odata.bind" in payload
    assert any("sponsor-guid-123" in binding for binding in payload["sponsors@odata.bind"])
    assert "intake-request:intake-guid-789" in payload["tags"]
    assert "approval-path:express" in payload["tags"]
    assert "notes" not in payload
    assert "fsiReviewerAttestations" not in payload


def test_planned_payload_with_attestations() -> None:
    """Payload with reviewer attestations includes notes and extension."""
    attestations = [
        {
            "role": "Sponsor",
            "upn": "alice@contoso.com",
            "decidedOnUtc": "2026-05-16T12:34:56Z",
            "decisionPackHash": "a" * 64,
        },
    ]
    payload = planned_payload(
        display_name="Test Agent",
        sponsor_id="sponsor-guid-123",
        blueprint_id="blueprint-guid-456",
        intake_request_id="intake-guid-789",
        approval_path="Standard",
        reviewer_attestations=attestations,
    )
    assert "notes" in payload
    assert "fsiReviewerAttestations" in payload
    assert payload["fsiReviewerAttestations"]["approvalPath"] == "Standard"


def test_planned_payload_tags_contain_fsi_agent_intake() -> None:
    payload = planned_payload(
        display_name="X",
        sponsor_id="s",
        blueprint_id="b",
        intake_request_id="i",
        approval_path="Express",
    )
    assert "fsi-agent-intake" in payload["tags"]
