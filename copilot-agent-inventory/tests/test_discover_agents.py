"""Unit tests for the pure discovery logic in copilot-agent-inventory.

Imports ``scripts/discover_agents.py`` (guarded by a skip when its single
third-party runtime dependency, ``requests``, is unavailable so CI skips rather
than errors) and exercises the side-effect-free helpers that the discovery
pipeline relies on:

  * ``_canonical_agent_id`` — both discovery layers must key ``fsi_agentid`` on
    the SAME bot-GUID id space. An Azure Resource Graph record yields the GUID
    from its ``name`` field; a Dataverse ``bot`` row yields ``botid`` and must
    never fall back to the friendly display ``name`` (finding H-3).
  * ``classify_component`` / ``COMPONENTTYPE_MAP`` — the botcomponent
    componenttype enum, including the distinct ``4`` (Dialog) vs ``8`` (Dialog
    Schema) codes (finding M-4) and the V1/V2 pairs, with fail-open behaviour
    for unparseable or drifted codes.
  * ``reconcile_sources`` — the same GUID present in both layers reconciles to
    ``in_both``; ids present in only one layer surface as drift.

The script guards its CLI entry point behind ``if __name__ == "__main__":`` and
performs no network or file I/O at import time, so importing it for unit testing
is safe.
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

try:
    import discover_agents as da

    _IMPORT_ERROR: Exception | None = None
except Exception as exc:  # pragma: no cover - only when a runtime dep is absent
    da = None  # type: ignore[assignment]
    _IMPORT_ERROR = exc

pytestmark = pytest.mark.skipif(
    da is None,
    reason=(
        "discover_agents could not be imported (missing runtime dependency such "
        f"as 'requests'): {_IMPORT_ERROR}"
    ),
)


# ---------------------------------------------------------------------------
# _canonical_agent_id — shared bot-GUID id space (finding H-3)
# ---------------------------------------------------------------------------

def test_canonical_id_dataverse_uses_botid_not_display_name() -> None:
    row = {
        "botid": "11111111-1111-1111-1111-111111111111",
        "name": "Friendly Display Name",
    }
    result = da._canonical_agent_id(row, da.DISCOVERY_SOURCE_DATAVERSE)
    assert result == "11111111-1111-1111-1111-111111111111"
    assert result != row["name"]


def test_canonical_id_dataverse_missing_botid_is_empty_string() -> None:
    row = {"name": "Only A Display Name"}
    assert da._canonical_agent_id(row, da.DISCOVERY_SOURCE_DATAVERSE) == ""


def test_canonical_id_arg_uses_resource_name_as_guid() -> None:
    row = {"name": "22222222-2222-2222-2222-222222222222"}
    assert da._canonical_agent_id(row, da.DISCOVERY_SOURCE_ARG) == (
        "22222222-2222-2222-2222-222222222222"
    )


def test_canonical_id_arg_falls_back_to_explicit_bot_id_field() -> None:
    # With no ARG resource name, fall back to an explicit bot-id field — never a
    # display name.
    row = {"botId": "33333333-3333-3333-3333-333333333333"}
    assert da._canonical_agent_id(row, da.DISCOVERY_SOURCE_ARG) == (
        "33333333-3333-3333-3333-333333333333"
    )


def test_canonical_id_empty_record_is_empty_string() -> None:
    assert da._canonical_agent_id({}, da.DISCOVERY_SOURCE_ARG) == ""


# ---------------------------------------------------------------------------
# classify_component / COMPONENTTYPE_MAP (finding M-4 — 4 vs 8 are distinct)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "code,expected",
    [
        (0, ("Topic", "V1")),
        (9, ("Topic", "V2")),
        (1, ("Skill", "V1")),
        (13, ("Skill", "V2")),
        (4, ("Dialog", "V1")),
        (8, ("Dialog Schema", "V1")),
    ],
)
def test_classify_component_known_codes(code: int, expected: tuple[str, str]) -> None:
    assert da.classify_component(code) == expected


def test_classify_component_dialog_vs_dialog_schema_are_distinct() -> None:
    # Code 4 (Dialog) and code 8 (Dialog Schema) must not collapse together.
    assert da.classify_component(4) == ("Dialog", "V1")
    assert da.classify_component(8) == ("Dialog Schema", "V1")
    assert da.classify_component(4) != da.classify_component(8)


def test_classify_component_accepts_string_digit() -> None:
    assert da.classify_component("4") == ("Dialog", "V1")


@pytest.mark.parametrize("bad", [None, "not-a-number", 20, 99, -1])
def test_classify_component_unrecognized_is_fail_open(bad: object) -> None:
    assert da.classify_component(bad) == ("Other / Unrecognized", "Not Applicable")


# ---------------------------------------------------------------------------
# reconcile_sources — drift detection across the two discovery layers
# ---------------------------------------------------------------------------

def test_reconcile_sources_classifies_overlap_and_drift() -> None:
    shared = "aaaaaaaa-0000-0000-0000-000000000001"
    arg_only = "bbbbbbbb-0000-0000-0000-000000000002"
    dataverse_only = "cccccccc-0000-0000-0000-000000000003"
    arg_agents = [{"fsi_agentid": shared}, {"fsi_agentid": arg_only}]
    scanned_agents = [{"fsi_agentid": shared}, {"fsi_agentid": dataverse_only}]

    result = da.reconcile_sources(arg_agents, scanned_agents)

    assert result["in_both"] == [shared]
    assert result["in_arg_only"] == [arg_only]
    assert result["in_dataverse_only"] == [dataverse_only]


def test_reconcile_sources_same_guid_across_layers_is_in_both() -> None:
    guid = "dddddddd-0000-0000-0000-000000000004"
    result = da.reconcile_sources([{"fsi_agentid": guid}], [{"fsi_agentid": guid}])
    assert result["in_both"] == [guid]
    assert result["in_arg_only"] == []
    assert result["in_dataverse_only"] == []


def test_reconcile_sources_ignores_records_without_id() -> None:
    result = da.reconcile_sources([{"fsi_agentid": ""}, {"other": "x"}], [])
    assert result == {"in_arg_only": [], "in_dataverse_only": [], "in_both": []}


def test_reconcile_sources_returns_sorted_lists() -> None:
    arg_agents = [{"fsi_agentid": "z"}, {"fsi_agentid": "a"}, {"fsi_agentid": "m"}]
    result = da.reconcile_sources(arg_agents, [])
    assert result["in_arg_only"] == ["a", "m", "z"]


def test_reconcile_sources_disjoint_id_spaces_warns(
    caplog: pytest.LogCaptureFixture,
) -> None:
    # Both layers return agents yet share zero ids: the id-space smoke check (H-3)
    # must warn loudly rather than silently reporting a 100% false drift. in_both
    # stays empty because the populations genuinely do not intersect.
    arg_agents = [{"fsi_agentid": "11111111-0000-0000-0000-000000000001"}]
    scanned_agents = [{"fsi_agentid": "22222222-0000-0000-0000-000000000002"}]

    with caplog.at_level(logging.WARNING, logger=da.logger.name):
        result = da.reconcile_sources(arg_agents, scanned_agents)

    assert result["in_both"] == []
    assert any(
        "id-space check FAILED" in record.getMessage() for record in caplog.records
    ), "expected the H-3 id-space-split warning to be emitted"


# ---------------------------------------------------------------------------
# derive_shared_with_everyone / _authshare_record (finding H1 - population side)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "policy,expected",
    [
        (0, True), (3, True),        # Any / Any (multi-tenant) -> org-wide reach
        ("0", True), ("3", True),    # string codes parse too
        (1, False), (2, False),      # more restrictive / security groups
        ("2", False),
    ],
)
def test_derive_shared_with_everyone_known_policies(
    policy: object, expected: bool
) -> None:
    assert da.derive_shared_with_everyone({"accesscontrolpolicy": policy}) is expected


@pytest.mark.parametrize(
    "bot",
    [
        {},                                # signal absent
        {"accesscontrolpolicy": None},     # explicit null
        {"accesscontrolpolicy": "weird"},  # unparseable
        {"accesscontrolpolicy": 99},       # unknown / drifted code
        {"accesscontrolpolicy": True},     # a bool is not a policy code
    ],
)
def test_derive_shared_with_everyone_unknown_is_none(bot: dict) -> None:
    # An unknown signal must be None (NOT coerced to False) so the audience expander
    # marks the agent Partial rather than emitting a confident empty audience.
    assert da.derive_shared_with_everyone(bot) is None


def test_authshare_record_stamps_shared_with_everyone_for_org_wide() -> None:
    ctx = da.ScanContext(run_id="run-1", dry_run=True)
    rec = da._authshare_record(ctx, {"botid": "bot-1", "accesscontrolpolicy": 0})
    assert rec["fsi_agentid"] == "bot-1"
    assert rec["fsi_sharedwitheveryone"] is True


def test_authshare_record_omits_column_when_signal_unknown() -> None:
    ctx = da.ScanContext(run_id="run-1", dry_run=True)
    rec = da._authshare_record(ctx, {"botid": "bot-2"})
    # The column is left OFF the record so the Dataverse value stays unset and the
    # expander treats whole-tenant reach as unknown (Partial), not a confident empty.
    assert "fsi_sharedwitheveryone" not in rec
    assert rec["fsi_agentid"] == "bot-2"


# ---------------------------------------------------------------------------
# _validate_as_of — strict UTC enforcement (DEFECT 2 regression)
#
# Rusty changed _validate_as_of to REJECT naive (timezone-less) datetimes.
# Previously they were silently accepted and could shift by the runner's local
# TZ, producing non-deterministic timestamps.  The regressions below pin the
# three input classes that the fix must handle correctly.
# ---------------------------------------------------------------------------

def test_validate_as_of_rejects_naive_datetime() -> None:
    """A naive datetime (no 'Z', no offset) must raise ValueError.

    Pre-fix behaviour: silently accepted and shifted by runner-local TZ.
    Post-fix behaviour: ValueError — UTC is required.
    """
    with pytest.raises(ValueError):
        da._validate_as_of("2026-07-20T18:00:00")


def test_validate_as_of_accepts_z_suffix_and_returns_canonical_form() -> None:
    """'Z' suffix is valid UTC and must round-trip to the canonical YYYY-MM-DDTHH:MM:SSZ form."""
    result = da._validate_as_of("2026-07-20T18:00:00Z")
    assert result == "2026-07-20T18:00:00Z"


def test_validate_as_of_normalizes_explicit_offset_to_utc() -> None:
    """An explicit non-zero offset must be converted to UTC deterministically.

    '2026-07-20T23:00:00+05:00' is 18:00 UTC regardless of the runner's local TZ.
    Pre-fix: naive input could produce a different timestamp on a UTC-offset host.
    Post-fix: explicit offsets are always normalised; the result is runner-independent.
    """
    result = da._validate_as_of("2026-07-20T23:00:00+05:00")
    assert result == "2026-07-20T18:00:00Z"


def test_validate_as_of_parity_with_parse_iso8601_utc() -> None:
    """_validate_as_of and import_registry_export._parse_iso8601_utc must agree.

    Both functions enforce strict UTC and produce the same canonical output for
    the same valid inputs.  Divergence here would mean an --as-of value that
    one pipeline leg accepts is rejected (or normalised differently) by the other.
    """
    try:
        import import_registry_export as ire
    except Exception:  # pragma: no cover — dep absent in some CI configurations
        pytest.skip("import_registry_export not importable — skipping parity check")

    for value in ("2026-07-20T18:00:00Z", "2026-07-20T23:00:00+05:00"):
        assert da._validate_as_of(value) == ire._parse_iso8601_utc(value), (
            f"_validate_as_of and _parse_iso8601_utc disagree on {value!r}"
        )

    # Both must reject the same naive input.
    with pytest.raises(ValueError):
        da._validate_as_of("2026-07-20T18:00:00")
    with pytest.raises(ValueError):
        ire._parse_iso8601_utc("2026-07-20T18:00:00")
