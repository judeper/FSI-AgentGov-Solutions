"""Tests for the Package Management API layer (Layer 4) in discover_agents.py.

Adversarial matrix covered:
  Package API — $filter build for 'Microsoft 365 Copilot Agent Builder' ONLY
    (length-1 PACKAGE_API_PLATFORMS; 'Copilot Studio' is intentionally excluded
    because ARG and Dataverse layers already cover it); @odata.nextLink paging
    accumulates all items;
    TRUNCATION/paging-error => paging_was_truncated=True (GATE-1 INCOMPLETE,
    never a silent empty); HTTP non-200 => truncated; ThrottlingExhaustedError
    => truncated; non-list value shape => truncated; clean empty value list is
    NOT truncated; duplicate package ids pass through unfiltered.

  Reconciliation — package appId matches existing bot-GUID row => ENRICH
    in-place (fsi_discoverysource = "Reconciled (multi-source)"), no duplicate,
    fsi_agentid stays as bot GUID; manifestId fallback match; no match => new
    P_... row with fsi_ownermatchconfidence="Unmatched" and
    fsi_discoverysource="Package Management API"; empty packages list is a no-op;
    appId takes priority over manifestId; Agent Builder row completeness upgrades
    to Complete after enrichment sets fsi_packageid.

  Helpers — _package_status_label option-set mapping (None/Some/All/unknown/
    case variants); _package_fields field projection; map_package_record
    standalone row shape and completeness.

  Behavioral — dry-run: fetch_package_catalog returns ([], False) with no
    HTTP calls; backward compat: --enable-package-api OFF leaves three-layer
    summary byte-for-byte unchanged; --enable-package-api ON adds
    packageNewRowCount/packageScanTruncated; P_... rows excluded from
    reconcile_sources drift detection.

All HTTP calls and token acquisition are mocked — no live network calls.
Synthetic data uses Contoso/Northwind identities; package ids follow the
P_19ae1zz1-... convention from Microsoft docs examples.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from unittest.mock import MagicMock, patch

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
# Fixtures / shared helpers
# ---------------------------------------------------------------------------

def _ctx(
    dry_run: bool = True,
    agent365_mode: str = "absent",
    enable_package_api: bool | None = None,
) -> "da.ScanContext":
    if enable_package_api is not None:
        agent365_mode = "present" if enable_package_api else "absent"
    return da.ScanContext(
        run_id="test-run-pkg-001",
        dry_run=dry_run,
        agent365_requested_mode=agent365_mode,
        agent365_resolution_source="Test",
    )


def _mock_response(json_data: object, status_code: int = 200) -> MagicMock:
    resp = MagicMock()
    resp.status_code = status_code
    resp.json.return_value = json_data
    return resp


# Synthetic Agent Builder package (P_ id from Microsoft docs example convention).
_AB_PKG: dict = {
    "id": "P_19ae1zz1-0000-0000-0000-contoso00001",
    "displayName": "Contoso Expense Advisor",
    "type": "custom",
    "platform": "Microsoft 365 Copilot Agent Builder",
    "appId": "a1b2c3d4-e5f6-0000-0000-contoso00001",
    "manifestId": "m1111111-0000-0000-0000-contoso00001",
    "manifestVersion": "1.0.0",
    "publisher": "Contoso Ltd.",
    "supportedHosts": ["TeamsPersonalApp", "OutlookAddIn"],
    "availableTo": "all",
    "deployedTo": "some",
    "isBlocked": False,
    "lastModifiedDateTime": "2026-07-01T00:00:00Z",
}

# Synthetic Copilot Studio package.
_CS_PKG: dict = {
    "id": "P_19ae1zz1-0000-0000-0000-northwind001",
    "displayName": "Northwind Support Bot",
    "type": "custom",
    "platform": "Copilot Studio",
    "appId": "b2c3d4e5-f6a7-0000-0000-northwind001",
    "manifestId": "m2222222-0000-0000-0000-northwind001",
    "manifestVersion": "1.0.0",
    "publisher": "Northwind Traders",
    "supportedHosts": ["TeamsPersonalApp"],
    "availableTo": "some",
    "deployedTo": "none",
    "isBlocked": False,
    "lastModifiedDateTime": "2026-07-02T00:00:00Z",
}


# =============================================================================
# _package_status_label
# =============================================================================

@pytest.mark.parametrize("raw,expected", [
    ("none",    "None"),
    ("some",    "Some"),
    ("all",     "All"),
    ("NONE",    "None"),     # case-insensitive
    ("SOME",    "Some"),
    ("ALL",     "All"),
    (None,      "None"),     # missing/null -> sentinel "None"
    ("",        "None"),     # empty string -> sentinel "None"
    ("partial", "None"),     # unrecognized value -> sentinel "None"
])
def test_package_status_label_known_and_unknown_values(
    raw: object, expected: str
) -> None:
    assert da._package_status_label(raw) == expected


# =============================================================================
# _package_fields
# =============================================================================

def test_package_fields_maps_all_documented_fields() -> None:
    ctx = _ctx()
    fields = da._package_fields(ctx, _AB_PKG)

    assert fields["fsi_packageid"] == _AB_PKG["id"]
    assert fields["fsi_publisher"] == "Contoso Ltd."
    assert fields["fsi_manifestid"] == _AB_PKG["manifestId"]
    assert fields["fsi_manifestversion"] == "1.0.0"
    assert fields["fsi_availableto"] == "All"
    assert fields["fsi_deployedto"] == "Some"
    assert fields["fsi_discoverysource"] == da.DISCOVERY_SOURCE_PACKAGE_API
    assert fields["fsi_runid"] == ctx.run_id
    # supportedHosts must be a JSON-serialised list (memo column)
    hosts = json.loads(fields["fsi_supportedhosts"])
    assert isinstance(hosts, list)
    assert "TeamsPersonalApp" in hosts


def test_package_fields_null_hosts_serialises_to_empty_list() -> None:
    ctx = _ctx()
    pkg = dict(_AB_PKG)
    pkg["supportedHosts"] = None
    fields = da._package_fields(ctx, pkg)
    assert json.loads(fields["fsi_supportedhosts"]) == []


def test_package_fields_non_list_hosts_serialises_to_empty_list() -> None:
    """Platform drift: API returns hosts as a string instead of a list."""
    ctx = _ctx()
    pkg = dict(_AB_PKG)
    pkg["supportedHosts"] = "TeamsPersonalApp"  # unexpected scalar
    fields = da._package_fields(ctx, pkg)
    assert json.loads(fields["fsi_supportedhosts"]) == []


# =============================================================================
# map_package_record
# =============================================================================

def test_map_package_record_fsi_agentid_is_package_id_with_p_prefix() -> None:
    ctx = _ctx()
    row = da.map_package_record(ctx, _AB_PKG)
    assert row["fsi_agentid"] == _AB_PKG["id"]
    assert row["fsi_agentid"].startswith(da.PACKAGE_ID_PREFIX)


def test_map_package_record_confidence_is_unmatched() -> None:
    """The Package API does not return a creator — owner attribution is impossible."""
    ctx = _ctx()
    row = da.map_package_record(ctx, _AB_PKG)
    assert row["fsi_ownermatchconfidence"] == "Unmatched"


def test_map_package_record_agent_builder_with_package_id_is_complete() -> None:
    """_package_fields sets fsi_packageid before classify_scan_completeness runs,
    so the standalone row is Complete (not Incomplete Scan)."""
    ctx = _ctx()
    row = da.map_package_record(ctx, _AB_PKG)
    assert row.get("fsi_packageid") == _AB_PKG["id"]
    assert row["fsi_scancompleteness"] == "Complete"


def test_map_package_record_copilot_studio_pkg_is_complete() -> None:
    ctx = _ctx()
    row = da.map_package_record(ctx, _CS_PKG)
    assert row["fsi_scancompleteness"] == "Complete"


# =============================================================================
# fetch_package_catalog
# =============================================================================

def test_fetch_package_catalog_dry_run_returns_empty_no_http_calls() -> None:
    ctx = _ctx(dry_run=True)
    session = MagicMock()

    with patch.object(da, "_request_with_backoff") as mock_req, \
         patch.object(da, "_get_token", return_value="fake-token"):
        packages, truncated = da.fetch_package_catalog(ctx, session)

    assert packages == []
    assert truncated is False
    mock_req.assert_not_called()


def test_package_api_platforms_is_agent_builder_only() -> None:
    """Regression: PACKAGE_API_PLATFORMS must have exactly one entry —
    'Microsoft 365 Copilot Agent Builder'. 'Copilot Studio' must NOT be present:
    ARG and Dataverse layers already cover it, and a package join would produce
    duplicates."""
    assert len(da.PACKAGE_API_PLATFORMS) == 1
    assert da.CREATED_IN_AGENT_BUILDER in da.PACKAGE_API_PLATFORMS
    assert da.CREATED_IN_COPILOT_STUDIO not in da.PACKAGE_API_PLATFORMS


def test_fetch_package_catalog_builds_filter_for_agent_builder_platform_only() -> None:
    """fetch_package_catalog must issue EXACTLY ONE request (Agent Builder only).
    'Copilot Studio' must NOT appear as a platform query — ARG and Dataverse
    layers already cover it.
    Endpoint must be the documented GA v1.0 path (GRAPH_API_BASE + PACKAGE_API_PATH)."""
    ctx = _ctx(dry_run=False)
    session = MagicMock()
    called_urls: list[str] = []

    def _side_effect(sess, method, url, **kwargs):
        called_urls.append(url)
        return _mock_response({"value": []})

    with patch.object(da, "_request_with_backoff", side_effect=_side_effect), \
         patch.object(da, "_get_token", return_value="fake-token"):
        packages, truncated = da.fetch_package_catalog(ctx, session)

    assert truncated is False
    # Exactly one request per the single-entry PACKAGE_API_PLATFORMS
    assert len(called_urls) == 1
    # Agent Builder must be the queried platform
    assert da.CREATED_IN_AGENT_BUILDER in called_urls[0]
    # Copilot Studio must NEVER be queried
    assert da.CREATED_IN_COPILOT_STUDIO not in called_urls[0], (
        "Copilot Studio must not be queried from the Package API; "
        "ARG and Dataverse layers already cover it."
    )
    # URL must target the documented GA v1.0 endpoint
    assert da.GRAPH_API_BASE in called_urls[0]
    assert da.PACKAGE_API_PATH in called_urls[0]
    assert "$filter=platform eq" in called_urls[0]


def test_fetch_package_catalog_follows_nextlink_paging() -> None:
    """@odata.nextLink must be followed; items from all pages are accumulated."""
    ctx = _ctx(dry_run=False)
    session = MagicMock()

    next_url = (
        "https://graph.microsoft.com/v1.0/copilot/admin/catalog/packages"
        "?$skiptoken=page-two"
    )
    page2_pkg = dict(_AB_PKG)
    page2_pkg["id"] = "P_19ae1zz1-0000-0000-0000-contoso00002"

    def _side_effect(sess, method, url, **kwargs):
        if url == next_url:
            # Second page — no further nextLink
            return _mock_response({"value": [page2_pkg]})
        if da.CREATED_IN_AGENT_BUILDER in url:
            # First Agent Builder page — has a nextLink
            return _mock_response({
                "value": [_AB_PKG],
                "@odata.nextLink": next_url,
            })
        # Fallback for unexpected URLs (should not occur with single-platform list)
        return _mock_response({"value": []})

    with patch.object(da, "_request_with_backoff", side_effect=_side_effect), \
         patch.object(da, "_get_token", return_value="fake-token"):
        packages, truncated = da.fetch_package_catalog(ctx, session)

    assert truncated is False
    # Both pages of Agent Builder results are present
    assert len(packages) == 2
    pkg_ids = {p["id"] for p in packages}
    assert _AB_PKG["id"] in pkg_ids
    assert page2_pkg["id"] in pkg_ids


def test_fetch_package_catalog_http_error_marks_truncated() -> None:
    """Non-200 HTTP status during paging must set paging_was_truncated=True (GATE-1).
    A truncated pull is never silently treated as end-of-data. With only Agent Builder
    in PACKAGE_API_PLATFORMS, a failure returns an empty package list."""
    ctx = _ctx(dry_run=False)
    session = MagicMock()

    def _side_effect(sess, method, url, **kwargs):
        if da.CREATED_IN_AGENT_BUILDER in url:
            return _mock_response({}, status_code=503)
        return _mock_response({"value": []})

    with patch.object(da, "_request_with_backoff", side_effect=_side_effect), \
         patch.object(da, "_get_token", return_value="fake-token"):
        packages, truncated = da.fetch_package_catalog(ctx, session)

    assert truncated is True
    # Only Agent Builder is queried; it returned 503 so packages list is empty
    assert packages == []


def test_fetch_package_catalog_throttle_exhausted_marks_truncated() -> None:
    """ThrottlingExhaustedError on Agent Builder must surface as INCOMPLETE (GATE-1).
    With only Agent Builder in PACKAGE_API_PLATFORMS, the package list is empty."""
    ctx = _ctx(dry_run=False)
    session = MagicMock()

    def _side_effect(sess, method, url, **kwargs):
        if da.CREATED_IN_AGENT_BUILDER in url:
            raise da.ThrottlingExhaustedError("429 exhausted on Agent Builder")
        return _mock_response({"value": []})

    with patch.object(da, "_request_with_backoff", side_effect=_side_effect), \
         patch.object(da, "_get_token", return_value="fake-token"):
        packages, truncated = da.fetch_package_catalog(ctx, session)

    assert truncated is True
    # Only Agent Builder is queried; throttle exhausted means packages is empty
    assert packages == []


def test_fetch_package_catalog_empty_value_list_is_not_truncated() -> None:
    """An empty value list is a legitimate clean empty response — NOT truncation."""
    ctx = _ctx(dry_run=False)
    session = MagicMock()

    def _side_effect(sess, method, url, **kwargs):
        return _mock_response({"value": []})

    with patch.object(da, "_request_with_backoff", side_effect=_side_effect), \
         patch.object(da, "_get_token", return_value="fake-token"):
        packages, truncated = da.fetch_package_catalog(ctx, session)

    assert packages == []
    assert truncated is False


def test_fetch_package_catalog_nonlist_value_shape_marks_truncated() -> None:
    """If the API returns 'value' as a non-list (platform drift), treat as INCOMPLETE."""
    ctx = _ctx(dry_run=False)
    session = MagicMock()

    def _side_effect(sess, method, url, **kwargs):
        if da.CREATED_IN_AGENT_BUILDER in url:
            return _mock_response({"value": "unexpected_string_not_a_list"})
        return _mock_response({"value": []})

    with patch.object(da, "_request_with_backoff", side_effect=_side_effect), \
         patch.object(da, "_get_token", return_value="fake-token"):
        packages, truncated = da.fetch_package_catalog(ctx, session)

    assert truncated is True


def test_fetch_package_catalog_duplicate_package_ids_pass_through() -> None:
    """Duplicate ids returned by the API are collected unfiltered — dedup is not
    this layer's responsibility. The reconciler handles duplicates at join time."""
    ctx = _ctx(dry_run=False)
    session = MagicMock()

    next_url = (
        "https://graph.microsoft.com/v1.0/copilot/admin/catalog/packages"
        "?$skiptoken=dup-page-2"
    )

    def _side_effect(sess, method, url, **kwargs):
        if url == next_url:
            # Second page deliberately repeats the same package id
            return _mock_response({"value": [_AB_PKG]})
        if da.CREATED_IN_AGENT_BUILDER in url:
            return _mock_response({
                "value": [_AB_PKG],
                "@odata.nextLink": next_url,
            })
        return _mock_response({"value": []})

    with patch.object(da, "_request_with_backoff", side_effect=_side_effect), \
         patch.object(da, "_get_token", return_value="fake-token"):
        packages, truncated = da.fetch_package_catalog(ctx, session)

    assert truncated is False
    dup_count = sum(1 for p in packages if p["id"] == _AB_PKG["id"])
    assert dup_count == 2, (
        "Both copies of the duplicate package must pass through; "
        "deduplication is the reconciler's job, not the fetcher's."
    )


# =============================================================================
# reconcile_package_catalog
# =============================================================================

def test_reconcile_enrich_on_appid_match_no_new_row_created() -> None:
    """Package with appId matching fsi_entraappid ENRICHES the existing row.
    fsi_agentid stays as the bot GUID — the P_... id space is NOT written to it.
    fsi_discoverysource is updated to 'Reconciled (multi-source)', NOT
    'Package Management API', so provenance of the original ARG/Dataverse source
    is preserved alongside the package enrichment."""
    ctx = _ctx()
    existing_agent = {
        "fsi_agentid": "aaaaaaaa-0000-0000-0000-000000000001",
        "fsi_agentname": "Contoso Expense Advisor",
        "fsi_entraappid": _AB_PKG["appId"],
        "fsi_discoverysource": da.DISCOVERY_SOURCE_ARG,
    }

    _, new_rows = da.reconcile_package_catalog(ctx, [_AB_PKG], [existing_agent])

    # No standalone P_ row created
    assert new_rows == []
    # Existing row enriched with package fields
    assert existing_agent["fsi_packageid"] == _AB_PKG["id"]
    # ENRICHED row must have "Reconciled (multi-source)" — NOT "Package Management API"
    assert existing_agent["fsi_discoverysource"] == da.DISCOVERY_SOURCE_RECONCILED
    # CRITICAL: fsi_agentid must remain the bot GUID
    assert existing_agent["fsi_agentid"] == "aaaaaaaa-0000-0000-0000-000000000001"
    assert not existing_agent["fsi_agentid"].startswith(da.PACKAGE_ID_PREFIX)


def test_reconcile_enrich_on_manifestid_fallback_no_new_row_created() -> None:
    """When appId is absent, manifestId is the fallback join key."""
    ctx = _ctx()
    pkg_no_appid = dict(_AB_PKG)
    pkg_no_appid["appId"] = None  # No appId — must fall through to manifestId

    existing_agent = {
        "fsi_agentid": "bbbbbbbb-0000-0000-0000-000000000002",
        "fsi_manifestid": _AB_PKG["manifestId"],
        "fsi_entraappid": None,
        "fsi_discoverysource": da.DISCOVERY_SOURCE_DATAVERSE,
    }

    _, new_rows = da.reconcile_package_catalog(ctx, [pkg_no_appid], [existing_agent])

    assert new_rows == []
    assert existing_agent["fsi_packageid"] == _AB_PKG["id"]


def test_reconcile_no_match_creates_p_row_with_unmatched_confidence() -> None:
    """No appId/manifestId match -> new standalone row with P_... fsi_agentid
    and fsi_ownermatchconfidence='Unmatched' (Package API has no owner field)."""
    ctx = _ctx()
    existing_agent = {
        "fsi_agentid": "cccccccc-0000-0000-0000-000000000003",
        "fsi_entraappid": "totally-different-app-id",
        "fsi_manifestid": "totally-different-manifest-id",
    }

    _, new_rows = da.reconcile_package_catalog(ctx, [_AB_PKG], [existing_agent])

    assert len(new_rows) == 1
    row = new_rows[0]
    assert row["fsi_agentid"] == _AB_PKG["id"]
    assert row["fsi_agentid"].startswith(da.PACKAGE_ID_PREFIX)
    assert row["fsi_ownermatchconfidence"] == "Unmatched"


def test_reconcile_empty_packages_list_is_noop() -> None:
    ctx = _ctx()
    existing_agents = [
        {"fsi_agentid": "dddddddd-0000-0000-0000-000000000004"}
    ]
    enriched, new_rows = da.reconcile_package_catalog(ctx, [], existing_agents)
    assert new_rows == []
    assert len(enriched) == 1


def test_reconcile_appid_match_takes_priority_over_manifestid() -> None:
    """When both appId and manifestId could each match a DIFFERENT existing agent,
    appId match wins (join order: appId first)."""
    ctx = _ctx()
    agent_by_appid = {
        "fsi_agentid": "eeeeeeee-0000-0000-0000-000000000005",
        "fsi_entraappid": _AB_PKG["appId"],
        "fsi_manifestid": "",
    }
    agent_by_manifestid = {
        "fsi_agentid": "ffffffff-0000-0000-0000-000000000006",
        "fsi_entraappid": "",
        "fsi_manifestid": _AB_PKG["manifestId"],
    }

    _, new_rows = da.reconcile_package_catalog(
        ctx, [_AB_PKG], [agent_by_appid, agent_by_manifestid]
    )

    # appId match takes priority — no new rows
    assert new_rows == []
    # The appId-matched agent is enriched
    assert agent_by_appid.get("fsi_packageid") == _AB_PKG["id"]
    # manifestId-matched agent is NOT enriched (appId already consumed the package)
    assert "fsi_packageid" not in agent_by_manifestid


def test_reconcile_agent_builder_completeness_upgrades_after_enrichment() -> None:
    """An Agent Builder row that started as 'Incomplete Scan' must be upgraded
    to 'Complete' after enrichment sets fsi_packageid."""
    ctx = _ctx()
    existing_agent = {
        "fsi_agentid": "gggggggg-0000-0000-0000-000000000007",
        "fsi_createdin": da.CREATED_IN_AGENT_BUILDER,
        "fsi_entraappid": _AB_PKG["appId"],
        "fsi_scancompleteness": "Incomplete Scan",  # pre-enrichment state
    }

    da.reconcile_package_catalog(ctx, [_AB_PKG], [existing_agent])

    assert existing_agent.get("fsi_packageid") == _AB_PKG["id"]
    assert existing_agent["fsi_scancompleteness"] == "Complete"


def test_reconcile_enriched_row_source_is_reconciled_not_package_api() -> None:
    """Regression: an existing ARG/Dataverse row enriched by reconcile_package_catalog
    must have fsi_discoverysource = DISCOVERY_SOURCE_RECONCILED, NOT
    DISCOVERY_SOURCE_PACKAGE_API. Overwriting with 'Package Management API' would
    destroy the original source provenance."""
    ctx = _ctx()
    for original_source in (
        da.DISCOVERY_SOURCE_ARG,
        da.DISCOVERY_SOURCE_DATAVERSE,
    ):
        agent = {
            "fsi_agentid": "hhhhhhhh-0000-0000-0000-000000000008",
            "fsi_entraappid": _AB_PKG["appId"],
            "fsi_discoverysource": original_source,
        }
        da.reconcile_package_catalog(ctx, [_AB_PKG], [agent])
        assert agent["fsi_discoverysource"] == da.DISCOVERY_SOURCE_RECONCILED, (
            f"Expected RECONCILED, got {agent['fsi_discoverysource']!r} "
            f"(original source was {original_source!r})"
        )


def test_reconcile_no_match_row_has_package_api_discovery_source() -> None:
    """A package that finds no appId/manifestId match in existing agents creates a
    new standalone P_... row.  That row's fsi_discoverysource must be
    'Package Management API' (not 'Reconciled'), because it has no ARG/Dataverse
    counterpart — it is purely a package-layer finding."""
    ctx = _ctx()
    existing_agent = {
        "fsi_agentid": "iiiiiiii-0000-0000-0000-000000000009",
        "fsi_entraappid": "totally-different-app-id-99",
        "fsi_manifestid": "totally-different-manifest-id-99",
    }

    _, new_rows = da.reconcile_package_catalog(ctx, [_AB_PKG], [existing_agent])

    assert len(new_rows) == 1
    assert new_rows[0]["fsi_discoverysource"] == da.DISCOVERY_SOURCE_PACKAGE_API


# =============================================================================
# Cross-id-space / backward-compat / dry-run behavioral tests
# =============================================================================

def test_reconcile_sources_excludes_p_prefix_rows_from_drift_detection() -> None:
    """Package-sourced P_... rows must NOT participate in ARG/Dataverse drift
    detection — mixing id spaces produces false 100% drift (H-3 guard applies
    inter-layer too, per Rusty's Decision 2)."""
    p_row = {"fsi_agentid": "P_19ae1zz1-0000-0000-0000-contoso00099"}
    bot_row = {"fsi_agentid": "aaaaaaaa-0000-0000-0000-000000000001"}

    # Mix P_ rows into arg_agents (simulates a caller accidentally passing both)
    result = da.reconcile_sources([p_row, bot_row], [bot_row])

    all_ids_in_report = (
        result["in_arg_only"] + result["in_dataverse_only"] + result["in_both"]
    )
    # P_ id must be absent from every drift bucket
    assert not any(i.startswith(da.PACKAGE_ID_PREFIX) for i in all_ids_in_report), (
        "P_... id leaked into ARG/Dataverse drift report — cross-id-space guard failed"
    )
    # Bot-GUID row correctly classified as in_both
    assert bot_row["fsi_agentid"] in result["in_both"]


def test_scan_all_dry_run_flag_off_has_no_package_summary_keys() -> None:
    """Without --enable-package-api, the three-layer summary must be byte-for-byte
    unchanged: packageNewRowCount and packageScanTruncated must NOT appear."""
    ctx = _ctx(dry_run=True, enable_package_api=False)
    result = da.scan_all(ctx)
    summary = result["summary"]

    assert "packageNewRowCount" not in summary, (
        "Backward compat broken: packageNewRowCount appeared without the feature flag"
    )
    assert "packageScanTruncated" not in summary, (
        "Backward compat broken: packageScanTruncated appeared without the feature flag"
    )


def test_enable_package_api_off_makes_no_package_catalog_calls() -> None:
    """Sanity: when enable_package_api is False (the default), fetch_package_catalog
    must never be called. The three-layer discovery path is byte-for-byte unchanged."""
    ctx = _ctx(dry_run=True, enable_package_api=False)

    with patch.object(da, "fetch_package_catalog_details") as mock_fetch:
        da.scan_all(ctx)

    mock_fetch.assert_not_called(), (
        "fetch_package_catalog was called without --enable-package-api; "
        "the three-layer default must remain unchanged."
    )


def test_scan_all_dry_run_flag_on_adds_package_summary_keys() -> None:
    """With --enable-package-api, summary must include package-layer keys.
    In dry_run the fetcher returns ([], False), so counts are zero/False."""
    ctx = _ctx(dry_run=True, enable_package_api=True)
    result = da.scan_all(ctx)
    summary = result["summary"]

    assert "packageNewRowCount" in summary
    assert "packageScanTruncated" in summary
    assert summary["packageNewRowCount"] == 0
    assert summary["packageScanTruncated"] is False


def test_scan_all_dry_run_flag_on_final_agents_has_no_p_rows() -> None:
    """With flag on and dry_run, fetch_package_catalog returns no packages,
    so no P_... rows should appear in the final agents list."""
    ctx = _ctx(dry_run=True, enable_package_api=True)
    result = da.scan_all(ctx)
    p_rows = [
        a for a in result["agents"]
        if str(a.get("fsi_agentid", "")).startswith(da.PACKAGE_ID_PREFIX)
    ]
    assert p_rows == []


# =============================================================================
# Regression: transport / parse errors from Package API do not crash scan_all
# =============================================================================

@pytest.mark.parametrize("label,outcome,error_code", [
    ("TransportFailure", da.PackageApiOutcome.TRANSPORT_FAILURE, "TransportFailure"),
    ("ParseFailure", da.PackageApiOutcome.PARSE_FAILURE, "ParseFailure"),
])
def test_scan_all_package_api_transport_error_marks_incomplete_does_not_raise(
    label: str,
    outcome: "da.PackageApiOutcome",
    error_code: str,
) -> None:
    """Failed package outcomes remain fail-visible and keep deprecated mirrors."""
    ctx = _ctx(dry_run=True, enable_package_api=True)
    failed_fetch = da.PackageApiFetchResult(
        outcome=outcome,
        attempted=True,
        packages=[],
        paging_truncated=True,
        error_code=error_code,
        reason="simulated",
    )

    with patch.object(da, "fetch_package_catalog_details", return_value=failed_fetch):
        result = da.scan_all(ctx)

    summary = result["summary"]
    assert summary.get("packageScanTruncated") is True, (
        f"packageScanTruncated must be True after {label}; got: {summary}"
    )
    assert summary.get("packageNewRowCount") == 0, (
        f"packageNewRowCount must be 0 after {label} guard; got: {summary}"
    )
    assert summary["agent365"]["layerStatus"] == da.LAYER_STATUS_FAILED


# =============================================================================
# New Yen columns — _package_fields must emit all five new columns
# =============================================================================

_AB_PKG_FULL: dict = {
    **_AB_PKG,
    "version":      "2.1.0",
    "assetId":      "asset-contoso-full-00001",
    "elementTypes": ["DeclarativeAgent"],
}

_AB_PKG_CEA: dict = {
    **_AB_PKG,
    "elementTypes": ["CustomEngineAgent"],
}

_AB_PKG_LITE: dict = {
    **_AB_PKG,
    "elementTypes": [],
}


def test_package_fields_includes_fsi_packagetype() -> None:
    ctx = _ctx()
    fields = da._package_fields(ctx, _AB_PKG_FULL)
    assert "fsi_packagetype" in fields
    assert fields["fsi_packagetype"] == _AB_PKG_FULL["type"]


def test_package_fields_includes_fsi_elementtypes_as_json_list() -> None:
    ctx = _ctx()
    fields = da._package_fields(ctx, _AB_PKG_FULL)
    assert "fsi_elementtypes" in fields
    parsed = json.loads(fields["fsi_elementtypes"])
    assert isinstance(parsed, list)
    assert "DeclarativeAgent" in parsed


def test_package_fields_includes_fsi_isblocked() -> None:
    ctx = _ctx()
    fields = da._package_fields(ctx, _AB_PKG_FULL)
    assert "fsi_isblocked" in fields
    assert fields["fsi_isblocked"] == _AB_PKG_FULL.get("isBlocked")


def test_package_fields_includes_fsi_packageversion() -> None:
    ctx = _ctx()
    fields = da._package_fields(ctx, _AB_PKG_FULL)
    assert "fsi_packageversion" in fields
    assert fields["fsi_packageversion"] == "2.1.0"


def test_package_fields_includes_fsi_assetid() -> None:
    ctx = _ctx()
    fields = da._package_fields(ctx, _AB_PKG_FULL)
    assert "fsi_assetid" in fields
    assert fields["fsi_assetid"] == "asset-contoso-full-00001"


def test_package_fields_includes_fsi_modifiedon() -> None:
    ctx = _ctx()
    fields = da._package_fields(ctx, _AB_PKG_FULL)
    assert "fsi_modifiedon" in fields
    assert fields["fsi_modifiedon"] == _AB_PKG_FULL.get("lastModifiedDateTime")


def test_package_fields_agenttype_declarative_agent() -> None:
    """elementTypes containing 'DeclarativeAgent' → fsi_agenttype='Declarative Agent'."""
    ctx = _ctx()
    fields = da._package_fields(ctx, _AB_PKG_FULL)
    assert fields["fsi_agenttype"] == "Declarative Agent"


def test_package_fields_agenttype_custom_engine_agent() -> None:
    """elementTypes containing 'CustomEngineAgent' → fsi_agenttype='Custom Engine Agent'."""
    ctx = _ctx()
    fields = da._package_fields(ctx, _AB_PKG_CEA)
    assert fields["fsi_agenttype"] == "Custom Engine Agent"


def test_package_fields_agenttype_lite_agent_builder_fallback() -> None:
    """Empty elementTypes → fsi_agenttype='Lite / Agent Builder'."""
    ctx = _ctx()
    fields = da._package_fields(ctx, _AB_PKG_LITE)
    assert fields["fsi_agenttype"] == "Lite / Agent Builder"


def test_map_package_record_carries_all_new_yen_columns() -> None:
    """A standalone map_package_record row must include all five new Yen columns
    plus fsi_modifiedon and fsi_agenttype so BI consumers never parse rawjson."""
    ctx = _ctx()
    row = da.map_package_record(ctx, _AB_PKG_FULL)
    for col in (
        "fsi_packagetype",
        "fsi_elementtypes",
        "fsi_isblocked",
        "fsi_packageversion",
        "fsi_assetid",
        "fsi_modifiedon",
        "fsi_agenttype",
    ):
        assert col in row, f"Missing column '{col}' in map_package_record output"


# =============================================================================
# PARTIAL semantics — reconcile_package_catalog(truncated=True)
# =============================================================================

def test_reconcile_truncated_enriched_row_has_partial_completeness() -> None:
    """When truncated=True, an existing row that gets package-enriched must have
    fsi_scancompleteness='Partial' with the canonical truncation reason."""
    ctx = _ctx()
    existing_agent = {
        "fsi_agentid": "aaaaaaaa-0000-0000-0000-partial00001",
        "fsi_entraappid": _AB_PKG["appId"],
        "fsi_scancompleteness": "Complete",
        "fsi_discoverysource": da.DISCOVERY_SOURCE_ARG,
    }

    da.reconcile_package_catalog(ctx, [_AB_PKG], [existing_agent], truncated=True)

    assert existing_agent["fsi_scancompleteness"] == "Incomplete Scan", (
        "Package-enriched row must be 'Incomplete Scan' when truncated=True"
    )
    assert da._PACKAGE_TRUNCATION_REASON in existing_agent.get(
        "fsi_scancompletenessreason", ""
    ), "Truncation reason must be set on the enriched row"


def test_reconcile_truncated_new_row_has_partial_completeness() -> None:
    """When truncated=True, a new standalone package-only row must also be 'Partial'."""
    ctx = _ctx()
    unrelated_agent = {
        "fsi_agentid": "bbbbbbbb-0000-0000-0000-partial00002",
        "fsi_entraappid": "no-match-app-id",
        "fsi_manifestid": "no-match-manifest-id",
    }

    _, new_rows = da.reconcile_package_catalog(
        ctx, [_AB_PKG], [unrelated_agent], truncated=True
    )

    assert len(new_rows) == 1
    assert new_rows[0]["fsi_scancompleteness"] == "Incomplete Scan", (
        "New standalone package row must be 'Incomplete Scan' when truncated=True"
    )
    assert da._PACKAGE_TRUNCATION_REASON in new_rows[0].get(
        "fsi_scancompletenessreason", ""
    )


def test_reconcile_truncated_does_not_affect_arg_dataverse_only_rows() -> None:
    """When truncated=True, rows that are NOT touched by package reconciliation
    (no appId/manifestId match AND not a new package row) must be untouched."""
    ctx = _ctx()
    arg_only_agent = {
        "fsi_agentid":        "cccccccc-0000-0000-0000-partial00003",
        "fsi_entraappid":     "different-app-id-never-matches",
        "fsi_manifestid":     "different-manifest-never-matches",
        "fsi_scancompleteness": "Complete",
        "fsi_discoverysource":  da.DISCOVERY_SOURCE_ARG,
    }

    # Empty package list → no package touches arg_only_agent.
    da.reconcile_package_catalog(ctx, [], [arg_only_agent], truncated=True)

    assert arg_only_agent["fsi_scancompleteness"] == "Complete", (
        "ARG/Dataverse-only rows must not be modified when truncated=True "
        "if they are not touched by package reconciliation"
    )


# =============================================================================
# Defect 3 regressions — "Incomplete Scan" label for truncated rows
# =============================================================================


def test_regression_defect3_truncated_enriched_row_is_incomplete_scan_not_partial() -> None:
    """Regression: an existing row ENRICHED during a truncated package scan must have
    fsi_scancompleteness == 'Incomplete Scan' — NOT 'Partial'.

    Locks the string constant so any future rename to 'Partial' or another label
    fails this test immediately."""
    ctx = _ctx()
    existing_agent = {
        "fsi_agentid": "aaaa0001-defect3-0000-0000-000000000001",
        "fsi_entraappid": _AB_PKG["appId"],
        "fsi_discoverysource": da.DISCOVERY_SOURCE_ARG,
    }

    da.reconcile_package_catalog(ctx, [_AB_PKG], [existing_agent], truncated=True)

    assert existing_agent["fsi_scancompleteness"] == "Incomplete Scan", (
        f"Expected 'Incomplete Scan'; got {existing_agent['fsi_scancompleteness']!r}. "
        "Defect 3: the completeness label for truncated package rows must be "
        "'Incomplete Scan', not 'Partial' or any other string."
    )
    assert existing_agent["fsi_scancompleteness"] != "Partial", (
        "Defect 3 regression: 'Partial' must NOT be used for truncated package rows."
    )


def test_regression_defect3_truncated_new_row_is_incomplete_scan_not_partial() -> None:
    """Regression: a new STANDALONE package-only row from a truncated scan must have
    fsi_scancompleteness == 'Incomplete Scan' — NOT 'Partial'."""
    ctx = _ctx()
    unrelated_agent = {
        "fsi_agentid": "bbbb0002-defect3-0000-0000-000000000002",
        "fsi_entraappid": "no-match-regression-app-id",
        "fsi_manifestid": "no-match-regression-manifest-id",
    }

    _, new_rows = da.reconcile_package_catalog(
        ctx, [_AB_PKG], [unrelated_agent], truncated=True
    )

    assert len(new_rows) == 1
    assert new_rows[0]["fsi_scancompleteness"] == "Incomplete Scan", (
        f"Expected 'Incomplete Scan' on standalone package row; "
        f"got {new_rows[0]['fsi_scancompleteness']!r}. "
        "Defect 3 regression: must be 'Incomplete Scan', not 'Partial'."
    )


def test_regression_defect3_custom_engine_agent_type_from_element_types() -> None:
    """Regression: elementTypes containing 'CustomEngineAgent' must derive
    fsi_agenttype == 'Custom Engine Agent' via _package_fields.

    Locks the exact string so any misspelling or enum rename fails immediately."""
    ctx = _ctx()
    cea_pkg = dict(_AB_PKG)
    cea_pkg["elementTypes"] = ["CustomEngineAgent"]

    fields = da._package_fields(ctx, cea_pkg)

    assert fields["fsi_agenttype"] == "Custom Engine Agent", (
        f"Expected 'Custom Engine Agent'; got {fields['fsi_agenttype']!r}. "
        "Defect 3 regression: CustomEngineAgent elementType must map to "
        "'Custom Engine Agent' (with spaces and title-case), not any other string."
    )


# =============================================================================
# Defect 4 regression — sample JSON contract test
# =============================================================================


def test_regression_defect4_sample_json_shape_matches_scan_all_output() -> None:
    """Contract test: package-inventory.sample.json must match the shape that
    scan_all() emits.

    Top-level keys (ignoring $comment) must be exactly {summary, agents, features,
    authShares} — no top-level runId, no fsi_copilotagent key.

    summary must contain the documented sub-blocks: runId, reconciliation,
    registryCorrelation, entitlementResolution.

    agents must be a list.

    The expected key sets are derived from a REAL (mocked-discovery) scan_all call so
    the test fails if EITHER the sample OR scan_all drifts from the contract.

    Regression for Defect 4.
    """
    from contextlib import ExitStack
    from unittest.mock import patch as _patch

    # --- Derive expected shape from a real (mocked) scan_all output. ----------
    ctx_full = da.ScanContext(
        run_id="contract-test-001",
        dry_run=True,
        agent365_requested_mode="present",
        agent365_resolution_source="Test",
        registry_export_path="fake-export.xlsx",
        columnmap_path="fake-map.json",
        as_of="2026-07-20T18:00:00Z",
        resolve_entitlement=True,
        entitlement_ps1_path="fake-ps1.ps1",
    )

    with ExitStack() as stack:
        import import_registry_export as ire
        stack.enter_context(
            _patch.object(da, "enumerate_environments", return_value=[])
        )
        stack.enter_context(
            _patch.object(da, "probe_arg_resource_type", return_value=False)
        )
        stack.enter_context(
            _patch.object(ire, "load_columnmap", return_value=({}, frozenset(), None))
        )
        stack.enter_context(
            _patch.object(ire, "import_registry_file", return_value=([], []))
        )
        real_output = da.scan_all(ctx_full)

    expected_toplevel_keys = frozenset(real_output.keys())
    expected_summary_keys = frozenset(real_output["summary"].keys())

    # --- Load the sample JSON and extract its shape. --------------------------
    sample_path = (
        Path(__file__).resolve().parents[1]
        / "templates"
        / "package-inventory.sample.json"
    )
    assert sample_path.exists(), f"Sample file not found: {sample_path}"
    sample = json.loads(sample_path.read_text(encoding="utf-8"))

    # Strip the $comment key (documentation only — not part of the data contract).
    sample_toplevel = frozenset(k for k in sample if not k.startswith("$"))

    # --- Shape assertions. ----------------------------------------------------
    assert sample_toplevel == expected_toplevel_keys, (
        f"Top-level keys mismatch.\n"
        f"  sample: {sorted(sample_toplevel)}\n"
        f"  scan_all: {sorted(expected_toplevel_keys)}\n"
        "Defect 4: sample or scan_all has drifted from the documented shape."
    )

    # summary sub-block keys — sample must be a SUPERSET of what scan_all emits
    # (the sample is a full run with all flags; scan_all base keys are always present).
    sample_summary_keys = frozenset(sample["summary"].keys())
    deferred_sample_keys = {"agent365", "coverageScope"}
    for key in expected_summary_keys:
        if key in deferred_sample_keys:
            continue
        assert key in sample_summary_keys, (
            f"summary key '{key}' present in scan_all output but missing from sample. "
            "Defect 4: update package-inventory.sample.json."
        )

    # Required keys from the documented contract.
    for required in ("runId", "reconciliation", "registryCorrelation",
                     "entitlementResolution"):
        assert required in sample_summary_keys, (
            f"summary must contain '{required}'; not found in sample. "
            "Defect 4 regression."
        )

    assert isinstance(sample["agents"], list), (
        "sample['agents'] must be a list — Defect 4 regression."
    )

    # Forbidden top-level keys.
    assert "runId" not in sample_toplevel, (
        "Top-level 'runId' must NOT exist; runId belongs inside summary. "
        "Defect 4 regression."
    )
    assert "fsi_copilotagent" not in sample_toplevel, (
        "Top-level 'fsi_copilotagent' key must NOT exist; Defect 4 regression."
    )


# ---------------------------------------------------------------------------
# DEFECT 1 regression — package-only rows must carry fsi_packageid
#
# Yen added fsi_PackageKey = (fsi_packageid) so that a scheduled package-only
# run can upsert via that key without accumulating duplicate rows.  The sample
# must contain at least one package-only row, and every such row must supply a
# non-empty fsi_packageid — otherwise the upsert key resolves to nothing and
# every re-run inserts a fresh duplicate.
# ---------------------------------------------------------------------------

_SAMPLE_PATH = (
    Path(__file__).resolve().parents[1] / "templates" / "package-inventory.sample.json"
)
_PACKAGE_ONLY_DISCOVERY_SOURCE = "Package Management API"


def _load_package_sample() -> dict:
    return json.loads(_SAMPLE_PATH.read_text(encoding="utf-8"))


def test_package_sample_contains_at_least_one_package_only_row() -> None:
    """The sample must have >= 1 package-only agent to exercise the fsi_PackageKey path."""
    agents = _load_package_sample()["agents"]
    pkg_only = [a for a in agents if a.get("fsi_discoverysource") == _PACKAGE_ONLY_DISCOVERY_SOURCE]
    assert len(pkg_only) >= 1, (
        f"package-inventory.sample.json has no agent with "
        f"fsi_discoverysource == {_PACKAGE_ONLY_DISCOVERY_SOURCE!r}; "
        "the fsi_PackageKey regression cannot be exercised"
    )


def test_package_only_rows_have_non_empty_packageid() -> None:
    """Every package-only row must supply a non-empty fsi_packageid.

    A package-only row without fsi_packageid cannot be matched by fsi_PackageKey,
    so each scheduler run would insert a fresh duplicate — the exact defect Yen
    fixed by adding the second alternate key.
    """
    agents = _load_package_sample()["agents"]
    pkg_only = [a for a in agents if a.get("fsi_discoverysource") == _PACKAGE_ONLY_DISCOVERY_SOURCE]
    for agent in pkg_only:
        pkg_id = agent.get("fsi_packageid")
        assert pkg_id and str(pkg_id).strip(), (
            f"package-only agent {agent.get('fsi_agentname')!r} has a missing or "
            "empty fsi_packageid — upsert via fsi_PackageKey would create duplicates"
        )


# ---------------------------------------------------------------------------
# Upsert-key PRECEDENCE contract tests (Linus transition-duplicate fix)
#
# Precedence (checked in order):
#   1. fsi_agentid AND fsi_environmentid both non-empty  ->  "fsi_AgentEnvKey"
#   2. fsi_packageid non-empty                           ->  "fsi_PackageKey"
#   3. else                                              ->  None (unpersistable)
#
# Regression trigger: an API-enriched existing row has BOTH fsi_environmentid
# and fsi_packageid.  It MUST route to fsi_AgentEnvKey (Branch 1, checked first)
# so it updates the pre-existing row rather than inserting a duplicate.
# ---------------------------------------------------------------------------

_ENRICHED_DISCOVERY_SOURCE = "Reconciled (multi-source)"


def _expected_upsert_key(row: dict) -> "str | None":
    """Local reference implementation of the upsert-key precedence.

    Returns:
        "fsi_AgentEnvKey"  if fsi_agentid AND fsi_environmentid are both non-empty.
        "fsi_PackageKey"   elif fsi_packageid is non-empty.
        None               otherwise (row is unpersistable — no idempotency key).
    """
    agent_id = row.get("fsi_agentid") or ""
    env_id = row.get("fsi_environmentid") or ""
    pkg_id = row.get("fsi_packageid") or ""

    if agent_id.strip() and env_id.strip():
        return "fsi_AgentEnvKey"
    if pkg_id.strip():
        return "fsi_PackageKey"
    return None


def test_upsert_key_helper_synthetic_none_case() -> None:
    """Synthetic row with neither (agentid + environmentid) nor packageid → None."""
    row: dict = {"fsi_agentid": "", "fsi_environmentid": "", "fsi_packageid": ""}
    assert _expected_upsert_key(row) is None


def test_upsert_key_helper_synthetic_none_case_missing_fields() -> None:
    """Row with no relevant keys at all is also unpersistable."""
    assert _expected_upsert_key({}) is None


def test_upsert_key_enriched_rows_route_to_agent_env_key() -> None:
    """Every enriched sample row (fsi_discoverysource == 'Reconciled (multi-source)')
    must have non-empty fsi_agentid AND fsi_environmentid and route to
    fsi_AgentEnvKey — NOT fsi_PackageKey.

    This is the transition-duplicate regression: if an enriched row lacks
    fsi_environmentid or if the precedence check preferred fsi_packageid, the
    upsert would insert a duplicate instead of updating the pre-existing row.
    """
    agents = _load_package_sample()["agents"]
    enriched = [a for a in agents if a.get("fsi_discoverysource") == _ENRICHED_DISCOVERY_SOURCE]

    assert len(enriched) >= 1, (
        "Sample must contain at least one enriched row (Reconciled (multi-source)) "
        "to exercise the transition-duplicate regression guard"
    )

    for row in enriched:
        name = row.get("fsi_agentname", "<unknown>")

        # Prerequisite: enriched rows must carry both keys
        assert row.get("fsi_agentid") and str(row["fsi_agentid"]).strip(), (
            f"Enriched row {name!r} is missing fsi_agentid — "
            "cannot route to fsi_AgentEnvKey"
        )
        assert row.get("fsi_environmentid") and str(row["fsi_environmentid"]).strip(), (
            f"Enriched row {name!r} is missing fsi_environmentid — "
            "transition-duplicate bug: would fall through to fsi_PackageKey"
        )

        key = _expected_upsert_key(row)
        assert key == "fsi_AgentEnvKey", (
            f"Enriched row {name!r} routed to {key!r} instead of 'fsi_AgentEnvKey'. "
            "Transition-duplicate regression: a row with both fsi_agentid and "
            "fsi_environmentid must always prefer fsi_AgentEnvKey (Branch 1)."
        )


def test_upsert_key_package_only_rows_route_to_package_key() -> None:
    """Package-only rows (fsi_discoverysource == 'Package Management API',
    no fsi_environmentid) must route to fsi_PackageKey (Branch 2).
    """
    agents = _load_package_sample()["agents"]
    pkg_only = [a for a in agents if a.get("fsi_discoverysource") == _PACKAGE_ONLY_DISCOVERY_SOURCE]

    assert len(pkg_only) >= 1, (
        "Sample must contain at least one package-only row to exercise fsi_PackageKey"
    )

    for row in pkg_only:
        name = row.get("fsi_agentname", "<unknown>")
        env_id = row.get("fsi_environmentid") or ""
        assert not env_id.strip(), (
            f"Package-only row {name!r} unexpectedly has fsi_environmentid={env_id!r}; "
            "if it has an environment id it should be reconciled, not package-only"
        )
        key = _expected_upsert_key(row)
        assert key == "fsi_PackageKey", (
            f"Package-only row {name!r} routed to {key!r} instead of 'fsi_PackageKey'."
        )


def test_upsert_key_both_keys_present_prefers_agent_env_key() -> None:
    """The sample must contain at least one row with BOTH a non-empty fsi_packageid
    AND a non-empty fsi_environmentid.  Such a row MUST route to fsi_AgentEnvKey
    (Branch 1) — proving that the presence of fsi_packageid alone does not
    divert an enriched row to fsi_PackageKey (Branch 2).

    This is the core of the transition-duplicate fix: Branch 1 is checked first.
    """
    agents = _load_package_sample()["agents"]
    both_keys_rows = [
        a for a in agents
        if (a.get("fsi_packageid") or "").strip()
        and (a.get("fsi_environmentid") or "").strip()
    ]

    assert len(both_keys_rows) >= 1, (
        "Sample must contain at least one row with both fsi_packageid and "
        "fsi_environmentid non-empty to prove Branch 1 takes precedence over Branch 2"
    )

    for row in both_keys_rows:
        name = row.get("fsi_agentname", "<unknown>")
        key = _expected_upsert_key(row)
        assert key == "fsi_AgentEnvKey", (
            f"Row {name!r} has both fsi_packageid and fsi_environmentid but routed "
            f"to {key!r} instead of 'fsi_AgentEnvKey'. "
            "Branch 1 (agentid + environmentid) must take precedence over Branch 2 "
            "(packageid alone) — this is exactly the transition-duplicate fix."
        )


# =============================================================================
# Agent 365 v0.4 — license probe + mode resolution
# =============================================================================


@pytest.mark.parametrize(
    "label,sku_part,sku_capability,plans",
    [
        ("Microsoft Agent 365", "Microsoft Agent 365", "Enabled", []),
        ("Agent 365 Frontier", "Agent 365 Frontier", "Enabled", []),
        (
            "Frontier display name",
            "Microsoft 365 Frontier for AI Teammates",
            "Enabled",
            [],
        ),
        (
            "E7 plan",
            "UNRELATED_SKU",
            "Enabled",
            [{"servicePlanName": "Microsoft 365 E7", "provisioningStatus": "Success"}],
        ),
    ],
)
def test_probe_agent365_detects_documented_name_aliases(
    label: str,
    sku_part: str,
    sku_capability: str,
    plans: list[dict],
) -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    session = MagicMock()
    payload = {
        "value": [
            {
                "skuPartNumber": sku_part,
                "capabilityStatus": sku_capability,
                "consumedUnits": 1,
                "prepaidUnits": {"enabled": 10},
                "servicePlans": plans,
            }
        ]
    }
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=_mock_response(payload)
    ):
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.DETECTED, label


def test_probe_agent365_selects_all_fields_required_for_usability_decision() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    session = MagicMock()
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=_mock_response({"value": []})
    ) as mock_req:
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.NOT_DETECTED
    called_url = mock_req.call_args.args[2]
    select_value = parse_qs(urlsplit(called_url).query).get("$select", [""])[0]
    selected_fields = {field.strip() for field in select_value.split(",") if field.strip()}
    assert {
        "skuPartNumber",
        "capabilityStatus",
        "prepaidUnits",
        "consumedUnits",
        "servicePlans",
    }.issubset(selected_fields)


def test_probe_agent365_alias_requires_enabled_or_consumed_seats() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    session = MagicMock()
    payload = {
        "value": [
            {
                "skuPartNumber": "Microsoft Agent 365",
                "capabilityStatus": "Enabled",
                "consumedUnits": 0,
                "prepaidUnits": {"enabled": 0},
                "servicePlans": [],
            }
        ]
    }
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=_mock_response(payload)
    ):
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.NOT_DETECTED


def test_probe_agent365_ignores_disabled_service_plan_aliases() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    session = MagicMock()
    payload = {
        "value": [
            {
                "skuPartNumber": "UNRELATED_SKU",
                "capabilityStatus": "Enabled",
                "consumedUnits": 2,
                "prepaidUnits": {"enabled": 2},
                "servicePlans": [
                    {
                        "servicePlanName": "Microsoft 365 E7",
                        "provisioningStatus": "Disabled",
                    }
                ],
            }
        ]
    }
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=_mock_response(payload)
    ):
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.NOT_DETECTED


def test_probe_agent365_requires_enabled_sku_capability_status() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    session = MagicMock()
    payload = {
        "value": [
            {
                "skuPartNumber": "Microsoft Agent 365",
                "capabilityStatus": "Suspended",
                "consumedUnits": 4,
                "prepaidUnits": {"enabled": 10},
                "servicePlans": [],
            }
        ]
    }
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=_mock_response(payload)
    ):
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.NOT_DETECTED


def test_probe_agent365_heuristic_does_not_assume_undocumented_sku_tokens() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    session = MagicMock()
    payload = {
        "value": [
            {
                "skuPartNumber": "MICROSOFT_AGENT_365_GA",
                "capabilityStatus": "Enabled",
                "consumedUnits": 5,
                "prepaidUnits": {"enabled": 5},
                "servicePlans": [],
            }
        ]
    }
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=_mock_response(payload)
    ):
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.NOT_DETECTED


def test_probe_agent365_operator_override_alias_detects_custom_sku() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    ctx.agent365_alias_overrides = ("CONTOSO_AGENT_365_CUSTOM",)
    session = MagicMock()
    payload = {
        "value": [
            {
                "skuPartNumber": "contoso-agent-365-custom",
                "capabilityStatus": "Enabled",
                "consumedUnits": 3,
                "prepaidUnits": {"enabled": 3},
                "servicePlans": [],
            }
        ]
    }
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=_mock_response(payload)
    ):
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.DETECTED


def test_probe_agent365_operator_override_can_enable_undocumented_tokens() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    ctx.agent365_alias_overrides = ("MICROSOFT_AGENT_365_GA",)
    session = MagicMock()
    payload = {
        "value": [
            {
                "skuPartNumber": "MICROSOFT_AGENT_365_GA",
                "capabilityStatus": "Enabled",
                "consumedUnits": 2,
                "prepaidUnits": {"enabled": 2},
                "servicePlans": [],
            }
        ]
    }
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=_mock_response(payload)
    ):
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.DETECTED


def test_probe_agent365_malformed_response_is_inconclusive() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    session = MagicMock()
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=_mock_response({"unexpected": True})
    ):
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.INCONCLUSIVE
    assert result.error_code == "MalformedResponse"


@pytest.mark.parametrize("body", [["not-an-object"], 7, None])
def test_probe_agent365_non_object_json_body_is_inconclusive_malformed(body: object) -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    session = MagicMock()
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=_mock_response(body)
    ):
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.INCONCLUSIVE
    assert result.error_code == "MalformedResponse"


def test_probe_agent365_transport_failure_is_inconclusive() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    session = MagicMock()
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da,
        "_request_with_backoff",
        side_effect=da.requests.exceptions.ConnectionError("boom"),
    ):
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.INCONCLUSIVE


def test_probe_agent365_forbidden_reason_uses_correct_permission_guidance() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    session = MagicMock()
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da,
        "_request_with_backoff",
        return_value=_mock_response(
            {"error": {"code": "Authorization_RequestDenied"}},
            status_code=403,
        ),
    ):
        result = da.probe_agent365_license(ctx, session)
    assert result.outcome == da.Agent365ProbeOutcome.INCONCLUSIVE
    assert "LicenseAssignment.Read.All" in result.reason
    assert "Organization.Read.All" in result.reason
    assert "required" not in result.reason


@pytest.mark.parametrize(
    "status,expected_outcome",
    [
        (401, da.PackageApiOutcome.HTTP_401),
        (403, da.PackageApiOutcome.HTTP_403),
        (404, da.PackageApiOutcome.HTTP_404_UNSUPPORTED),
        (429, da.PackageApiOutcome.HTTP_429),
        (503, da.PackageApiOutcome.HTTP_5XX),
    ],
)
def test_fetch_package_catalog_details_maps_http_outcomes(
    status: int,
    expected_outcome: "da.PackageApiOutcome",
) -> None:
    ctx = _ctx(dry_run=False, agent365_mode="present")
    session = MagicMock()
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da,
        "_request_with_backoff",
        return_value=_mock_response({"error": {"code": "TestCode"}}, status_code=status),
    ):
        details = da.fetch_package_catalog_details(ctx, session)
    assert details.outcome == expected_outcome
    assert details.paging_truncated is True


def test_fetch_package_catalog_details_parse_failure_outcome() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="present")
    session = MagicMock()
    bad_resp = MagicMock()
    bad_resp.status_code = 200
    bad_resp.json.side_effect = ValueError("not json")
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=bad_resp
    ):
        details = da.fetch_package_catalog_details(ctx, session)
    assert details.outcome == da.PackageApiOutcome.PARSE_FAILURE


@pytest.mark.parametrize("body", [["not-an-object"], 42, None])
def test_fetch_package_catalog_details_non_object_first_page_is_parse_failure(
    body: object,
) -> None:
    ctx = _ctx(dry_run=False, agent365_mode="present")
    session = MagicMock()
    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", return_value=_mock_response(body)
    ):
        details = da.fetch_package_catalog_details(ctx, session)
    assert details.outcome == da.PackageApiOutcome.PARSE_FAILURE
    assert details.error_code == "MalformedResponse"
    assert details.paging_truncated is True


@pytest.mark.parametrize("next_page_body", [["not-an-object"], 9, None])
def test_fetch_package_catalog_details_non_object_next_page_is_parse_failure(
    next_page_body: object,
) -> None:
    ctx = _ctx(dry_run=False, agent365_mode="present")
    session = MagicMock()
    next_url = (
        "https://graph.microsoft.com/v1.0/copilot/admin/catalog/packages"
        "?$skiptoken=next-page"
    )

    def _side_effect(_sess, _method, url, **_kwargs):
        if url == next_url:
            return _mock_response(next_page_body)
        return _mock_response({"value": [_AB_PKG], "@odata.nextLink": next_url})

    with patch.object(da, "_get_token", return_value="fake-token"), patch.object(
        da, "_request_with_backoff", side_effect=_side_effect
    ):
        details = da.fetch_package_catalog_details(ctx, session)
    assert details.outcome == da.PackageApiOutcome.PARSE_FAILURE
    assert details.error_code == "MalformedResponse"
    assert details.paging_truncated is True
    assert len(details.packages) == 1


def test_scan_all_absent_mode_defers_package_layer_and_keeps_complete_status() -> None:
    ctx = _ctx(dry_run=True, agent365_mode="absent")
    with patch.object(da, "fetch_package_catalog_details") as mock_fetch, patch.object(
        da, "probe_agent365_license"
    ) as mock_probe:
        result = da.scan_all(ctx)
    mock_fetch.assert_not_called()
    mock_probe.assert_not_called()
    agent365 = result["summary"]["agent365"]
    assert agent365["resolvedState"] == "Absent"
    assert agent365["layerStatus"] == da.LAYER_STATUS_DEFERRED
    assert result["summary"]["status"] == "Complete"


def test_scan_all_auto_not_detected_skips_package_api_and_is_not_absence() -> None:
    ctx = _ctx(dry_run=True, agent365_mode="auto")
    probe = da.Agent365LicenseProbeResult(
        outcome=da.Agent365ProbeOutcome.NOT_DETECTED,
        attempted=True,
        reason="none",
    )
    with patch.object(da, "probe_agent365_license", return_value=probe), patch.object(
        da, "fetch_package_catalog_details"
    ) as mock_fetch:
        result = da.scan_all(ctx)
    mock_fetch.assert_not_called()
    agent365 = result["summary"]["agent365"]
    assert agent365["resolvedState"] == "NotDetected"
    assert agent365["layerStatus"] == da.LAYER_STATUS_DEFERRED
    assert result["summary"]["status"] == "Complete"


def test_scan_all_present_mode_package_failure_remains_present_and_fails() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="present")
    failed_fetch = da.PackageApiFetchResult(
        outcome=da.PackageApiOutcome.HTTP_403,
        attempted=True,
        paging_truncated=True,
        http_status=403,
        error_code="Authorization_RequestDenied",
        reason="forbidden",
    )
    with patch.object(da, "probe_arg_resource_type", return_value=False), patch.object(
        da, "enumerate_environments", return_value=[]
    ), patch.object(da, "fetch_package_catalog_details", return_value=failed_fetch):
        result = da.scan_all(ctx)
    agent365 = result["summary"]["agent365"]
    assert agent365["resolvedState"] == "Present"
    assert agent365["layerStatus"] == da.LAYER_STATUS_FAILED
    assert result["summary"]["status"] == "Failed"
    assert agent365["resolvedState"] not in {"Absent", "NotDetected", "Deferred"}


def test_scan_all_auto_inconclusive_attempts_package_api_and_degrades_status() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    probe = da.Agent365LicenseProbeResult(
        outcome=da.Agent365ProbeOutcome.INCONCLUSIVE,
        attempted=True,
        reason="probe failed",
        error_code="Http503",
        http_status=503,
    )
    ok_fetch = da.PackageApiFetchResult(
        outcome=da.PackageApiOutcome.SUCCESS_EMPTY,
        attempted=True,
        packages=[],
        paging_truncated=False,
    )
    with patch.object(da, "probe_arg_resource_type", return_value=False), patch.object(
        da, "enumerate_environments", return_value=[]
    ), patch.object(da, "probe_agent365_license", return_value=probe), patch.object(
        da, "fetch_package_catalog_details", return_value=ok_fetch
    ) as mock_fetch:
        result = da.scan_all(ctx)
    assert mock_fetch.called
    assert result["summary"]["agent365"]["resolvedState"] == "Inconclusive"
    assert result["summary"]["status"] == "Incomplete"


def test_scan_all_coverage_scope_surfaces_subscribed_skus_permission_guidance() -> None:
    ctx = _ctx(dry_run=False, agent365_mode="auto")
    probe = da.Agent365LicenseProbeResult(
        outcome=da.Agent365ProbeOutcome.INCONCLUSIVE,
        attempted=True,
        http_status=403,
        error_code="Authorization_RequestDenied",
        reason="forbidden",
    )
    ok_fetch = da.PackageApiFetchResult(
        outcome=da.PackageApiOutcome.SUCCESS_EMPTY,
        attempted=True,
        packages=[],
        paging_truncated=False,
    )
    with patch.object(da, "probe_arg_resource_type", return_value=False), patch.object(
        da, "enumerate_environments", return_value=[]
    ), patch.object(da, "probe_agent365_license", return_value=probe), patch.object(
        da, "fetch_package_catalog_details", return_value=ok_fetch
    ):
        result = da.scan_all(ctx)
    limitations = result["summary"]["coverageScope"]["limitations"]
    assert any("LicenseAssignment.Read.All" in item for item in limitations)
    assert any("Organization.Read.All" in item for item in limitations)


def test_scan_all_summary_emits_agent365_and_coverage_scope_contract() -> None:
    ctx = _ctx(dry_run=True, agent365_mode="present")
    result = da.scan_all(ctx)
    summary = result["summary"]
    assert "agent365" in summary
    assert "coverageScope" in summary
    agent365 = summary["agent365"]
    for key in (
        "requestedMode",
        "resolvedState",
        "resolutionSource",
        "detectionConfidence",
        "licenseProbeAttempted",
        "packageApiAttempted",
        "layerStatus",
        "httpStatus",
        "errorCode",
        "errorSubcode",
        "reason",
        "packagesObserved",
        "packageNewRowCount",
        "pagingTruncated",
    ):
        assert key in agent365
    scope = summary["coverageScope"]
    assert scope["layers"]["packageApi"] == da.LAYER_STATUS_DRY_RUN
    assert "Deferred/NotDetected is not an authoritative Agent Builder catalog." in scope["warning"]
