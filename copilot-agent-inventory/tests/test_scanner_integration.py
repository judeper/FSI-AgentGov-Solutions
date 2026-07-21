"""Integration tests for the combined scanner: registry correlation, entitlement
resolution, and backward-compatibility assertions.

Discovery layers (ARG + Dataverse) are replaced with synthetic in-memory fixtures
via patch.object so no HTTP calls, subprocess invocations, or file I/O occur.
Synthetic identities use Contoso/Northwind domains only.

Coverage matrix:
  _validate_as_of       — rejects invalid datetime strings.
  _normalize_agent_name — collapses whitespace and lowercases.
  _apply_registry_owner — sets owner fields without touching fsi_discoverysource.
  scan_all backward-compat — no new summary keys when registry flags absent.
  Registry correlation (via scan_all):
      stable agent-id join (strongest key)
      last-resort exact normalized-name join (single candidate)
      ambiguous duplicate name → skipped + counted, NOT enriched
      unmatched registry row → counted, NO orphan agent created
      only Agent Builder / package rows enriched; Copilot Studio rows untouched
      registryCorrelation summary block shape + field values
  Entitlement resolution (via scan_all):
      deterministic zip join-back by UPN order
      no UPN in any evidence field
      owners without a UPN (@) are not classified
      resolver failure → all-Unknown + status "Failed"
  Integrated combined output — both summary blocks present + agents enriched.
"""

from __future__ import annotations

import json
import sys
from contextlib import ExitStack
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

# ---------------------------------------------------------------------------
# Module-level guards — skip entire file if any required module is absent
# ---------------------------------------------------------------------------

try:
    import discover_agents as da
    _DA_ERR: Exception | None = None
except Exception as exc:  # pragma: no cover
    da = None  # type: ignore[assignment]
    _DA_ERR = exc

try:
    import import_registry_export as ire
    _IRE_ERR: Exception | None = None
except Exception as exc:  # pragma: no cover
    ire = None  # type: ignore[assignment]
    _IRE_ERR = exc

try:
    import resolve_owner_entitlement as roe
    _ROE_ERR: Exception | None = None
except Exception as exc:  # pragma: no cover
    roe = None  # type: ignore[assignment]
    _ROE_ERR = exc

pytestmark = pytest.mark.skipif(
    da is None or ire is None or roe is None,
    reason=(
        "Required modules unavailable "
        f"(da={_DA_ERR!r}, ire={_IRE_ERR!r}, roe={_ROE_ERR!r})"
    ),
)


# ---------------------------------------------------------------------------
# Synthetic fixtures
# ---------------------------------------------------------------------------

_RUN_ID = "test-integ-scan-001"
_AS_OF  = "2026-07-20T18:00:00Z"

# A single fake environment so enumerate_environments returns a non-empty
# list so the ThreadPoolExecutor submits exactly one _scan_one_environment call.
_FAKE_ENV = {"id": "env-contoso-001"}

# Stable IDs for synthetic agents.
_AB_ID   = "aaaaaaaa-0000-0000-0000-agbuilder0001"
_AB_NAME = "Contoso Expense Advisor"
_CS_ID   = "bbbbbbbb-0000-0000-0000-copilotstud1"
_AB_ID_2 = "cccccccc-0000-0000-0000-agbuilder0002"

# Synthetic service-plan GUID for entitlement evidence — NOT a real Microsoft GUID.
_PLAN_GUID = "11111111-aaaa-0000-0000-synth00000001"

# Default owner UPN used in registry rows.
_OWNER_UPN = "advisor@contoso.com"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _ab_agent(**overrides: Any) -> dict:
    """Return an Agent Builder agent fixture (registry-enrichment candidate)."""
    base: dict = {
        "fsi_agentid":       _AB_ID,
        "fsi_agentname":     _AB_NAME,
        "fsi_createdin":     da.CREATED_IN_AGENT_BUILDER,
        "fsi_discoverysource": da.DISCOVERY_SOURCE_DATAVERSE,
        "fsi_packageid":     "",
    }
    base.update(overrides)
    return base


def _cs_agent(**overrides: Any) -> dict:
    """Return a Copilot Studio agent fixture (NOT a registry-enrichment candidate)."""
    base: dict = {
        "fsi_agentid":       _CS_ID,
        "fsi_agentname":     "Northwind Support Bot",
        "fsi_createdin":     da.CREATED_IN_COPILOT_STUDIO,
        "fsi_discoverysource": da.DISCOVERY_SOURCE_ARG,
    }
    base.update(overrides)
    return base


def _reg_row(
    agent_id: str = _AB_ID,
    agent_name: str = _AB_NAME,
    upn: str = _OWNER_UPN,
    confidence: str = "Heuristic",
) -> dict:
    """Build a synthetic registry row (output of import_registry_file)."""
    row = {
        "fsi_agentid":             agent_id,
        "fsi_agentname":           agent_name,
        "fsi_ownersource":         ire.OWNER_SOURCE_LABEL,
        "fsi_ownermatchconfidence": confidence,
    }
    if upn and "@" in upn:
        row["fsi_ownerupn"] = upn
    return row


def _ent_result_paid() -> dict:
    return {
        "fsi_ownerentitlement":         roe.ENTITLEMENT_PAID,
        "fsi_ownerentitlementevidence": json.dumps([_PLAN_GUID]),
    }


def _ent_result_unknown() -> dict:
    return {
        "fsi_ownerentitlement":         roe.ENTITLEMENT_UNKNOWN,
        "fsi_ownerentitlementevidence": "[]",
    }


def _make_ctx(**kwargs: Any) -> "da.ScanContext":
    # Allow callers to override dry_run (e.g. _ENT_CTX sets dry_run=False so
    # scan_all's Step 6 exercises the live entitlement path with mocked resolvers).
    dry_run = kwargs.pop("dry_run", True)
    return da.ScanContext(run_id=_RUN_ID, dry_run=dry_run, **kwargs)


# Convenience kwarg bundles for registry / entitlement contexts.
_REG_CTX: dict = dict(
    registry_export_path="fake-export.xlsx",
    columnmap_path="fake-map.json",
    as_of=_AS_OF,
)
_ENT_CTX: dict = dict(
    **_REG_CTX,
    dry_run=False,          # Step 6 must run with the live (mocked) resolver path.
    resolve_entitlement=True,
    entitlement_ps1_path="fake-Get-CopilotEntitlement.ps1",
)


def _run_scan(
    agents: list[dict],
    reg_rows: list[dict] | None = None,
    reg_warnings: list[str] | None = None,
    ent_results: list[dict] | None = None,
    **ctx_kwargs: Any,
) -> dict:
    """Run scan_all with mocked discovery layers and optional reg/ent injection.

    Discovery is replaced with a single fake environment that returns ``agents``
    (shallow-copied so in-place enrichment doesn't mutate the caller's fixture).
    """
    ctx = _make_ctx(**ctx_kwargs)
    # Shallow-copy each agent dict so the enriched state is isolated to one test.
    scan_outcome = {
        "agents":     [dict(a) for a in agents],
        "features":   [],
        "authShares": [],
    }

    with ExitStack() as stack:
        # Prevent the ARG capability probe from making real HTTP calls regardless
        # of ctx.dry_run — it is always a no-op in unit tests.
        stack.enter_context(
            patch.object(da, "probe_arg_resource_type", return_value=False)
        )
        stack.enter_context(
            patch.object(da, "enumerate_environments", return_value=[_FAKE_ENV])
        )
        stack.enter_context(
            patch.object(da, "_scan_one_environment", return_value=scan_outcome)
        )

        if ctx.registry_export_path:
            # Stub load_columnmap (returns empty aliases — no mapping needed for
            # tests since reg_rows are already in Dataverse logical-name form).
            stack.enter_context(
                patch.object(ire, "load_columnmap", return_value=({}, frozenset(), None))
            )
            stack.enter_context(
                patch.object(
                    ire, "import_registry_file",
                    return_value=(list(reg_rows or []), list(reg_warnings or [])),
                )
            )

        if ctx.resolve_entitlement and ctx.registry_export_path:
            stack.enter_context(
                patch.object(da, "_get_token", return_value="fake-bearer-token")
            )
            # resolve_entitlements now returns (results, invocation_failed).
            stack.enter_context(
                patch.object(
                    roe, "resolve_entitlements",
                    return_value=(list(ent_results or []), False),
                )
            )

        return da.scan_all(ctx)


def _find_agent(result: dict, agent_id: str) -> dict:
    """Look up an agent in scan_all's result by fsi_agentid (fails the test if absent)."""
    matches = [a for a in result["agents"] if a.get("fsi_agentid") == agent_id]
    assert matches, f"Agent '{agent_id}' not found in result['agents']"
    return matches[0]


# =============================================================================
# _validate_as_of — pure unit tests
# =============================================================================

def test_validate_as_of_rejects_invalid_datetime() -> None:
    """_validate_as_of must raise ValueError for non-ISO-8601 strings."""
    with pytest.raises(ValueError):
        da._validate_as_of("not-a-date")


def test_validate_as_of_accepts_canonical_utc() -> None:
    """A valid UTC string must be returned in canonical YYYY-MM-DDTHH:MM:SSZ form."""
    result = da._validate_as_of("2026-07-20T18:00:00Z")
    assert result == "2026-07-20T18:00:00Z"


# =============================================================================
# _normalize_agent_name — pure unit tests
# =============================================================================

def test_normalize_agent_name_lowercases_and_collapses_spaces() -> None:
    assert da._normalize_agent_name("Contoso  Expense  Advisor") == (
        "contoso expense advisor"
    )


def test_normalize_agent_name_strips_leading_trailing_whitespace() -> None:
    assert da._normalize_agent_name("  Contoso Bot  ") == "contoso bot"


def test_normalize_agent_name_empty_string_returns_empty() -> None:
    assert da._normalize_agent_name("") == ""


# =============================================================================
# _apply_registry_owner — pure unit tests
# =============================================================================

def test_apply_registry_owner_sets_owner_fields() -> None:
    """_apply_registry_owner must copy fsi_ownerupn, fsi_ownerid, fsi_createdon,
    fsi_ownersource, and fsi_ownermatchconfidence from the registry row."""
    agent = {"fsi_agentid": _AB_ID, "fsi_discoverysource": da.DISCOVERY_SOURCE_DATAVERSE}
    reg = {
        "fsi_ownerupn":             _OWNER_UPN,
        "fsi_ownerid":              "guid-owner-0001",
        "fsi_createdon":            "2026-01-01T00:00:00Z",
        "fsi_ownermatchconfidence": "Exact",
    }
    da._apply_registry_owner(agent, reg, _AS_OF)

    assert agent["fsi_ownerupn"] == _OWNER_UPN
    assert agent["fsi_ownerid"] == "guid-owner-0001"
    assert agent["fsi_createdon"] == "2026-01-01T00:00:00Z"
    assert agent["fsi_ownersource"] == "Agent Registry Export"
    assert agent["fsi_ownermatchconfidence"] == "Exact"
    assert agent["fsi_ownerasofdatetime"] == _AS_OF


def test_apply_registry_owner_preserves_fsi_discoverysource() -> None:
    """fsi_discoverysource must NOT be overwritten — API provenance is preserved."""
    original_source = da.DISCOVERY_SOURCE_ARG
    agent = {"fsi_agentid": _AB_ID, "fsi_discoverysource": original_source}
    reg = {"fsi_ownermatchconfidence": "Unmatched"}
    da._apply_registry_owner(agent, reg, None)
    assert agent["fsi_discoverysource"] == original_source, (
        "fsi_discoverysource must not be overwritten by registry correlation"
    )


def test_apply_registry_owner_skips_upn_when_absent_from_reg_row() -> None:
    """If the registry row has no fsi_ownerupn key, the agent must not gain one."""
    agent = {"fsi_agentid": _AB_ID}
    reg = {"fsi_ownermatchconfidence": "Unmatched"}   # no fsi_ownerupn
    da._apply_registry_owner(agent, reg, None)
    assert "fsi_ownerupn" not in agent


# =============================================================================
# Backward-compat — no new summary keys when registry / entitlement flags absent
# =============================================================================

def test_backward_compat_no_registry_flags_no_new_summary_keys() -> None:
    """scan_all without --registry-export must not emit registryCorrelation or
    entitlementResolution — backward compat is byte-for-byte unchanged."""
    ctx = _make_ctx()   # no registry_export_path, no resolve_entitlement
    result = da.scan_all(ctx)
    assert "registryCorrelation" not in result["summary"], (
        "registryCorrelation appeared without --registry-export flag"
    )
    assert "entitlementResolution" not in result["summary"], (
        "entitlementResolution appeared without --resolve-entitlement flag"
    )


def test_scan_all_no_flags_does_not_fail_without_openpyxl(monkeypatch: Any) -> None:
    """scan_all without registry flags must not fail even when openpyxl is absent.
    The import is guarded by lazy loading inside _rows_from_xlsx."""
    import sys
    monkeypatch.setitem(sys.modules, "openpyxl", None)  # simulate unavailable
    ctx = _make_ctx()
    result = da.scan_all(ctx)   # must not raise ImportError
    assert "agents" in result


# =============================================================================
# Registry correlation — via scan_all with mocked discovery + registry data
# =============================================================================

def test_registry_stable_agent_id_join_enriches_ab_row() -> None:
    """Stable fsi_agentid join (highest priority) must enrich the Agent Builder row."""
    agent = _ab_agent()
    reg = [_reg_row(agent_id=_AB_ID, upn=_OWNER_UPN)]

    result = _run_scan([agent], reg_rows=reg, **_REG_CTX)

    ab = _find_agent(result, _AB_ID)
    assert ab.get("fsi_ownerupn") == _OWNER_UPN
    assert ab.get("fsi_ownersource") == "Agent Registry Export"
    assert ab.get("fsi_ownerasofdatetime") == _AS_OF


def test_registry_stable_id_join_preserves_discoverysource() -> None:
    """The stable-id join must not overwrite fsi_discoverysource."""
    agent = _ab_agent(fsi_discoverysource=da.DISCOVERY_SOURCE_ARG)
    reg = [_reg_row(agent_id=_AB_ID)]

    result = _run_scan([agent], reg_rows=reg, **_REG_CTX)

    ab = _find_agent(result, _AB_ID)
    assert ab.get("fsi_discoverysource") == da.DISCOVERY_SOURCE_ARG, (
        "fsi_discoverysource must not be overwritten by registry correlation"
    )


def test_registry_name_join_single_candidate_enriches() -> None:
    """Last-resort exact-normalised-name join must fire when EXACTLY ONE candidate
    matches the normalised name and no stable id join succeeded."""
    agent = _ab_agent(fsi_agentid=_AB_ID)
    # Registry row has NO agent_id — falls through to name join.
    reg_row_name_only = {
        "fsi_agentid":              "",          # no stable id
        "fsi_agentname":            _AB_NAME,    # matches by name
        "fsi_ownerupn":             _OWNER_UPN,
        "fsi_ownersource":          ire.OWNER_SOURCE_LABEL,
        "fsi_ownermatchconfidence": "Heuristic",
    }

    result = _run_scan([agent], reg_rows=[reg_row_name_only], **_REG_CTX)

    ab = _find_agent(result, _AB_ID)
    assert ab.get("fsi_ownerupn") == _OWNER_UPN, (
        "Last-resort name join must enrich when exactly one candidate matches"
    )


def test_registry_ambiguous_name_skipped_and_counted() -> None:
    """When two Agent Builder rows share the same normalized name, the registry
    row must be SKIPPED (ambiguous — never guess), and ambiguousNameSkipped must
    be incremented."""
    agent1 = _ab_agent(fsi_agentid=_AB_ID,   fsi_agentname=_AB_NAME)
    agent2 = _ab_agent(fsi_agentid=_AB_ID_2, fsi_agentname=_AB_NAME)  # same name!

    # Registry row: no stable id, will try name join → finds TWO candidates.
    reg_row_ambiguous = {
        "fsi_agentid":              "",
        "fsi_agentname":            _AB_NAME,
        "fsi_ownerupn":             _OWNER_UPN,
        "fsi_ownersource":          ire.OWNER_SOURCE_LABEL,
        "fsi_ownermatchconfidence": "Heuristic",
    }

    result = _run_scan([agent1, agent2], reg_rows=[reg_row_ambiguous], **_REG_CTX)

    # Neither agent must have been enriched.
    ab1 = _find_agent(result, _AB_ID)
    ab2 = _find_agent(result, _AB_ID_2)
    assert "fsi_ownerupn" not in ab1, "Ambiguous name join must NOT enrich first candidate"
    assert "fsi_ownerupn" not in ab2, "Ambiguous name join must NOT enrich second candidate"

    corr = result["summary"]["registryCorrelation"]
    assert corr["ambiguousNameSkipped"] >= 1, (
        f"ambiguousNameSkipped must be >= 1; got {corr['ambiguousNameSkipped']}"
    )
    assert corr["matched"] == 0, "Ambiguous row must NOT count as matched"


def test_registry_unmatched_row_no_orphan_agent_created() -> None:
    """A registry row that cannot be joined to any agent must be counted in
    unmatchedRegistryRows and must NOT create an orphan fsi_copilotagent row."""
    agent = _ab_agent()
    # Registry row references a completely unknown agent id.
    reg_row_unmatched = _reg_row(
        agent_id="ffffffff-0000-0000-0000-unknown00001",
        agent_name="Unknown Bot Nobody Knows",
    )

    result = _run_scan([agent], reg_rows=[reg_row_unmatched], **_REG_CTX)

    # Only the one synthetic agent should appear — no orphan row.
    assert len(result["agents"]) == 1, (
        f"Unmatched registry row must not create an orphan agent; "
        f"got {len(result['agents'])} agents"
    )
    corr = result["summary"]["registryCorrelation"]
    assert corr["unmatchedRegistryRows"] >= 1


def test_registry_only_enriches_ab_and_package_rows_not_cs_rows() -> None:
    """Registry correlation must target ONLY Agent Builder / package rows.
    A Copilot Studio row must not be enriched even if its agent-id matches."""
    cs = _cs_agent(fsi_agentid=_CS_ID)
    # Registry row that matches the CS agent's id — must still be skipped.
    reg = [_reg_row(agent_id=_CS_ID, agent_name="Northwind Support Bot")]

    result = _run_scan([cs], reg_rows=reg, **_REG_CTX)

    cs_row = _find_agent(result, _CS_ID)
    assert "fsi_ownerupn" not in cs_row, (
        "Copilot Studio row must NOT be enriched by registry correlation"
    )
    # The registry row was not matched — counted as unmatched.
    corr = result["summary"]["registryCorrelation"]
    assert corr["matched"] == 0
    assert corr["unmatchedRegistryRows"] >= 1


def test_registry_correlation_summary_block_all_keys_present() -> None:
    """registryCorrelation summary block must have exactly the documented keys."""
    agent = _ab_agent()
    reg = [_reg_row()]

    result = _run_scan([agent], reg_rows=reg, **_REG_CTX)

    corr = result["summary"]["registryCorrelation"]
    for key in (
        "registryRowCount",
        "matched",
        "unmatchedRegistryRows",
        "ambiguousNameSkipped",
        "invalidDateWarnings",
        "status",
    ):
        assert key in corr, f"registryCorrelation missing key '{key}'"


def test_registry_correlation_summary_status_complete_on_no_warnings() -> None:
    """status must be 'Complete' when import_registry_file returns no warnings."""
    agent = _ab_agent()
    reg = [_reg_row()]

    result = _run_scan([agent], reg_rows=reg, reg_warnings=[], **_REG_CTX)

    assert result["summary"]["registryCorrelation"]["status"] == "Complete"


def test_registry_correlation_summary_status_incomplete_with_warnings() -> None:
    """status must be 'Incomplete' when import_registry_file returns warnings
    (e.g., invalid date_created values in the export)."""
    agent = _ab_agent()
    reg = [_reg_row()]
    warnings = ["Row 2: date_created value 'not-a-date' invalid — fsi_createdon null"]

    result = _run_scan([agent], reg_rows=reg, reg_warnings=warnings, **_REG_CTX)

    assert result["summary"]["registryCorrelation"]["status"] == "Incomplete"
    assert result["summary"]["registryCorrelation"]["invalidDateWarnings"] == 1


# =============================================================================
# Entitlement resolution — via scan_all
# =============================================================================

def test_entitlement_deterministic_join_back_by_upn() -> None:
    """resolve_entitlements result must be applied to the right agent by UPN."""
    agent = _ab_agent()
    reg   = [_reg_row(upn=_OWNER_UPN)]   # gives the agent a UPN

    result = _run_scan(
        [agent],
        reg_rows=reg,
        ent_results=[_ent_result_paid()],
        **_ENT_CTX,
    )

    ab = _find_agent(result, _AB_ID)
    assert ab.get("fsi_ownerentitlement") == roe.ENTITLEMENT_PAID
    assert ab.get("fsi_ownerentitlementevidence") is not None


def test_entitlement_no_upn_in_evidence_fields() -> None:
    """UPN strings must never appear in fsi_ownerentitlementevidence (privacy guard)."""
    agent = _ab_agent()
    reg   = [_reg_row(upn=_OWNER_UPN)]

    result = _run_scan(
        [agent],
        reg_rows=reg,
        ent_results=[_ent_result_paid()],
        **_ENT_CTX,
    )

    ab = _find_agent(result, _AB_ID)
    evidence = ab.get("fsi_ownerentitlementevidence", "")
    assert _OWNER_UPN not in evidence, (
        f"UPN '{_OWNER_UPN}' leaked into fsi_ownerentitlementevidence: {evidence}"
    )


def test_entitlement_owners_without_upn_not_classified() -> None:
    """An agent without a UPN-shaped fsi_ownerupn must not receive entitlement
    classification — the eligible-UPN list must exclude non-UPN owners."""
    # Agent has no fsi_ownerupn at all (Unmatched from registry).
    agent = _ab_agent()
    reg_unmatched = {
        "fsi_agentid":              _AB_ID,
        "fsi_agentname":            _AB_NAME,
        "fsi_ownersource":          ire.OWNER_SOURCE_LABEL,
        "fsi_ownermatchconfidence": "Unmatched",
        # fsi_ownerupn intentionally absent
    }

    result = _run_scan(
        [agent],
        reg_rows=[reg_unmatched],
        ent_results=[],   # no UPNs eligible — resolver must not be called with any
        **_ENT_CTX,
    )

    ab = _find_agent(result, _AB_ID)
    assert "fsi_ownerentitlement" not in ab, (
        "Agent without a UPN must not receive entitlement classification"
    )
    ent = result["summary"]["entitlementResolution"]
    assert ent["ownersConsidered"] == 0


def test_entitlement_unknown_when_no_upn_match() -> None:
    """If resolve_entitlements returns Unknown for a UPN, the agent must have
    fsi_ownerentitlement='Unknown' and fsi_ownerentitlementevidence='[]'."""
    agent = _ab_agent()
    reg   = [_reg_row(upn=_OWNER_UPN)]

    result = _run_scan(
        [agent],
        reg_rows=reg,
        ent_results=[_ent_result_unknown()],
        **_ENT_CTX,
    )

    ab = _find_agent(result, _AB_ID)
    assert ab.get("fsi_ownerentitlement") == roe.ENTITLEMENT_UNKNOWN
    assert json.loads(ab.get("fsi_ownerentitlementevidence", "null")) == []


def test_entitlement_failed_sets_all_unknown_and_failed_status() -> None:
    """When resolve_entitlements raises an exception, all eligible UPN owners must
    be set to Unknown and status must be 'Failed' — fail-open, never 'blocked'."""
    agent = _ab_agent()
    reg   = [_reg_row(upn=_OWNER_UPN)]
    ctx   = _make_ctx(**_ENT_CTX)
    scan_outcome = {"agents": [dict(agent)], "features": [], "authShares": []}

    with ExitStack() as stack:
        stack.enter_context(
            patch.object(da, "probe_arg_resource_type", return_value=False)
        )
        stack.enter_context(
            patch.object(da, "enumerate_environments", return_value=[_FAKE_ENV])
        )
        stack.enter_context(
            patch.object(da, "_scan_one_environment", return_value=scan_outcome)
        )
        stack.enter_context(
            patch.object(ire, "load_columnmap", return_value=({}, frozenset(), None))
        )
        stack.enter_context(
            patch.object(
                ire, "import_registry_file",
                return_value=([_reg_row(upn=_OWNER_UPN)], []),
            )
        )
        stack.enter_context(patch.object(da, "_get_token", return_value="fake-token"))
        # Simulate resolver crash.
        stack.enter_context(
            patch.object(
                roe, "resolve_entitlements",
                side_effect=RuntimeError("pwsh not available in test env"),
            )
        )
        result = da.scan_all(ctx)

    ent = result["summary"]["entitlementResolution"]
    assert ent["status"] == "Failed", (
        f"status must be 'Failed' on resolver crash; got {ent['status']!r}"
    )
    ab = _find_agent(result, _AB_ID)
    assert ab.get("fsi_ownerentitlement") == roe.ENTITLEMENT_UNKNOWN, (
        "Agent with UPN must be set to Unknown on resolver failure (fail-open)"
    )


def test_entitlement_summary_block_all_keys_present() -> None:
    """entitlementResolution summary must contain all documented keys."""
    agent = _ab_agent()
    reg   = [_reg_row(upn=_OWNER_UPN)]

    result = _run_scan(
        [agent],
        reg_rows=reg,
        ent_results=[_ent_result_paid()],
        **_ENT_CTX,
    )

    ent = result["summary"]["entitlementResolution"]
    for key in ("ownersConsidered", "paidCount", "chatOnlyCount", "unknownCount", "status"):
        assert key in ent, f"entitlementResolution missing key '{key}'"


# =============================================================================
# Integrated combined output — both summary blocks + enriched agents[]
# =============================================================================

def test_integrated_combined_output_both_summary_blocks_present() -> None:
    """scan_all with --registry-export AND --resolve-entitlement must emit agents[]
    enriched with owner + entitlement fields AND both summary blocks in summary."""
    agent = _ab_agent()
    reg   = [_reg_row(upn=_OWNER_UPN)]

    result = _run_scan(
        [agent],
        reg_rows=reg,
        ent_results=[_ent_result_paid()],
        **_ENT_CTX,
    )

    # Both optional summary blocks must be present.
    assert "registryCorrelation" in result["summary"], (
        "registryCorrelation block missing from combined output"
    )
    assert "entitlementResolution" in result["summary"], (
        "entitlementResolution block missing from combined output"
    )

    # The Agent Builder row must be enriched with owner + entitlement.
    ab = _find_agent(result, _AB_ID)
    assert ab.get("fsi_ownerupn") == _OWNER_UPN, "Agent must have owner UPN after combined scan"
    assert ab.get("fsi_ownerentitlement") == roe.ENTITLEMENT_PAID, (
        "Agent must have entitlement label after combined scan"
    )

    # agents[] key must exist and be a list.
    assert isinstance(result["agents"], list)


def test_integrated_summary_counts_are_consistent() -> None:
    """registryCorrelation.matched must equal the number of enriched agents."""
    agent = _ab_agent()
    reg   = [_reg_row(upn=_OWNER_UPN)]

    result = _run_scan(
        [agent],
        reg_rows=reg,
        ent_results=[_ent_result_paid()],
        **_ENT_CTX,
    )

    corr = result["summary"]["registryCorrelation"]
    assert corr["matched"] == 1
    assert corr["registryRowCount"] == 1
    assert corr["unmatchedRegistryRows"] == 0

    ent = result["summary"]["entitlementResolution"]
    assert ent["ownersConsidered"] == 1
    assert ent["paidCount"] == 1
    assert ent["unknownCount"] == 0


# =============================================================================
# Defect 1 (truthfulness) regression
# =============================================================================


def test_regression_defect1_invocation_failed_true_sets_status_failed() -> None:
    """Regression: when resolve_entitlements returns (results, invocation_failed=True),
    summary['entitlementResolution']['status'] must be 'Failed' — NOT 'Complete'.

    Distinguishes "ran; owners genuinely Unknown" from "resolver crashed".
    The pre-fix code ignored invocation_failed and always wrote 'Complete'.
    """
    agent = _ab_agent()
    reg   = [_reg_row(upn=_OWNER_UPN)]

    # Mock returns all-Unknown results WITH invocation_failed=True.
    ent_failed: list[dict] = [
        {"fsi_ownerentitlement": roe.ENTITLEMENT_UNKNOWN,
         "fsi_ownerentitlementevidence": "[]"}
    ]

    ctx = _make_ctx(**_ENT_CTX)
    scan_outcome = {"agents": [dict(agent)], "features": [], "authShares": []}

    with ExitStack() as stack:
        stack.enter_context(
            patch.object(da, "probe_arg_resource_type", return_value=False)
        )
        stack.enter_context(
            patch.object(da, "enumerate_environments", return_value=[_FAKE_ENV])
        )
        stack.enter_context(
            patch.object(da, "_scan_one_environment", return_value=scan_outcome)
        )
        stack.enter_context(
            patch.object(ire, "load_columnmap", return_value=({}, frozenset(), None))
        )
        stack.enter_context(
            patch.object(
                ire, "import_registry_file",
                return_value=([_reg_row(upn=_OWNER_UPN)], []),
            )
        )
        stack.enter_context(patch.object(da, "_get_token", return_value="fake-token"))
        # invocation_failed=True: PS1 ran but exited non-zero.
        stack.enter_context(
            patch.object(
                roe, "resolve_entitlements",
                return_value=(ent_failed, True),
            )
        )
        result = da.scan_all(ctx)

    ent = result["summary"]["entitlementResolution"]
    assert ent["status"] == "Failed", (
        f"status must be 'Failed' when invocation_failed=True; got {ent['status']!r}. "
        "Defect 1 (truthfulness) regression: 'Complete' must not be written when the "
        "resolver subprocess failed, even if all results are Unknown."
    )
    # Owners must still be set to Unknown (fail-open).
    ab = _find_agent(result, _AB_ID)
    assert ab.get("fsi_ownerentitlement") == roe.ENTITLEMENT_UNKNOWN, (
        "Agent must receive Unknown entitlement even on invocation_failed (fail-open)"
    )


# =============================================================================
# Defect 5 (dry-run) regression
# =============================================================================


def test_regression_defect5_dry_run_skips_token_acquisition_and_resolver() -> None:
    """Regression: scan_all with dry_run=True must NOT call _get_token or
    resolve_entitlements even when resolve_entitlement=True and
    registry_export_path is set.

    summary['entitlementResolution']['status'] must be 'Skipped (dry-run)'.

    Pre-fix behavior: Step 6 always called the resolver regardless of dry_run,
    exposing the managed-identity token path in non-live test runs and making
    dry-run unsafe for use without Az context.
    """
    ctx = _make_ctx(
        dry_run=True,   # explicit True — must override any _ENT_CTX default
        registry_export_path="fake-export.xlsx",
        columnmap_path="fake-map.json",
        as_of=_AS_OF,
        resolve_entitlement=True,
        entitlement_ps1_path="fake-Get-CopilotEntitlement.ps1",
    )
    agent = _ab_agent()
    scan_outcome = {"agents": [dict(agent)], "features": [], "authShares": []}

    with ExitStack() as stack:
        stack.enter_context(
            patch.object(da, "probe_arg_resource_type", return_value=False)
        )
        stack.enter_context(
            patch.object(da, "enumerate_environments", return_value=[_FAKE_ENV])
        )
        stack.enter_context(
            patch.object(da, "_scan_one_environment", return_value=scan_outcome)
        )
        stack.enter_context(
            patch.object(ire, "load_columnmap", return_value=({}, frozenset(), None))
        )
        stack.enter_context(
            patch.object(ire, "import_registry_file", return_value=([], []))
        )
        mock_token = stack.enter_context(
            patch.object(da, "_get_token")
        )
        mock_resolver = stack.enter_context(
            patch.object(roe, "resolve_entitlements")
        )
        result = da.scan_all(ctx)

    mock_token.assert_not_called(), (
        "_get_token must NOT be called in dry-run mode (Defect 5 regression)"
    )
    mock_resolver.assert_not_called(), (
        "resolve_entitlements must NOT be called in dry-run mode (Defect 5 regression)"
    )

    ent = result["summary"]["entitlementResolution"]
    assert ent["status"] == "Skipped (dry-run)", (
        f"status must be 'Skipped (dry-run)' with dry_run=True; got {ent['status']!r}. "
        "Defect 5 regression."
    )
