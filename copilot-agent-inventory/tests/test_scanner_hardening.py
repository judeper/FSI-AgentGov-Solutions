"""Pre-live hardening tests for the discovery scanner.

These tests pin the fixes that stop authorization/API failures from looking like
a clean, empty tenant:

  * Environment enumeration (Layer 2) must FAIL EXPLICITLY on 401/403/5xx or a
    malformed body — never return a success-shaped empty list. A genuine HTTP 200
    with ``value: []`` remains a representable empty result.
  * Per-environment scan failures are retained as structured coverage-gap records
    (environment id, stage, HTTP status, sanitized reason) and degrade the overall
    scan status to Incomplete/Failed — never indistinguishable from a zero-agent
    environment.
  * The ARG layer (Layer 1) distinguishes unavailable / failed / observed-zero;
    a failed query is never treated as an observed zero.
  * The CLI surfaces a Failed scan through a non-zero exit code, and
    ``--resolve-entitlement`` without ``--registry-export`` fails argument
    validation (no owner source exists).

All network/token work is mocked; no HTTP call or credential acquisition occurs.
Synthetic identities use Contoso/Northwind domains only.
"""

from __future__ import annotations

import sys
from pathlib import Path
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
# Helpers
# ---------------------------------------------------------------------------

def _resp(status_code: int, json_data: dict | None = None,
          json_raises: bool = False) -> MagicMock:
    resp = MagicMock()
    resp.status_code = status_code
    if json_raises:
        resp.json.side_effect = ValueError("simulated non-JSON body")
    else:
        resp.json.return_value = json_data if json_data is not None else {}
    return resp


def _ctx(**kwargs) -> "da.ScanContext":
    kwargs.setdefault("dry_run", False)
    return da.ScanContext(run_id="cai-harden-001", **kwargs)


# =============================================================================
# enumerate_environments — explicit failure vs genuine empty
# =============================================================================

@pytest.mark.parametrize("status", [401, 403, 500])
def test_enumerate_environments_non_200_raises_with_status(status: int) -> None:
    """A 401/403/5xx environment-list response must raise (never return [])."""
    ctx = _ctx()
    with patch.object(da, "_get_token", return_value="fake-token"), \
         patch.object(da, "_request_with_backoff", return_value=_resp(status, {})):
        with pytest.raises(da.EnvironmentEnumerationError) as excinfo:
            da.enumerate_environments(ctx, MagicMock())
    assert excinfo.value.http_status == status


def test_enumerate_environments_empty_success_returns_empty_list() -> None:
    """A genuine HTTP 200 with ``value: []`` is a representable empty result."""
    ctx = _ctx()
    with patch.object(da, "_get_token", return_value="fake-token"), \
         patch.object(da, "_request_with_backoff",
                      return_value=_resp(200, {"value": []})):
        result = da.enumerate_environments(ctx, MagicMock())
    assert result == []


def test_enumerate_environments_missing_value_array_raises() -> None:
    """A 200 body with no ``value`` array is malformed, not a genuine empty."""
    ctx = _ctx()
    with patch.object(da, "_get_token", return_value="fake-token"), \
         patch.object(da, "_request_with_backoff",
                      return_value=_resp(200, {"unexpected": True})):
        with pytest.raises(da.EnvironmentEnumerationError):
            da.enumerate_environments(ctx, MagicMock())


def test_enumerate_environments_non_json_body_raises() -> None:
    """A 200 with a non-JSON body must raise, not silently read zero."""
    ctx = _ctx()
    with patch.object(da, "_get_token", return_value="fake-token"), \
         patch.object(da, "_request_with_backoff",
                      return_value=_resp(200, json_raises=True)):
        with pytest.raises(da.EnvironmentEnumerationError):
            da.enumerate_environments(ctx, MagicMock())


# =============================================================================
# scan_all — enumeration failure vs genuine empty (top-level status)
# =============================================================================

def test_scan_all_enumeration_failure_is_failed_not_empty_tenant() -> None:
    """Enumeration failure → summary.status Failed + environmentEnumeration Failed
    carrying the HTTP status — distinct from a clean empty tenant."""
    ctx = _ctx()
    with patch.object(da, "probe_arg_resource_type", return_value=False), \
         patch.object(
             da, "enumerate_environments",
             side_effect=da.EnvironmentEnumerationError("403", http_status=403)):
        result = da.scan_all(ctx)

    summary = result["summary"]
    assert summary["status"] == "Failed"
    assert summary["environmentEnumeration"]["status"] == "Failed"
    assert summary["environmentEnumeration"]["httpStatus"] == 403
    assert summary["scannedAgentCount"] == 0


def test_scan_all_genuine_empty_is_complete_and_distinct_from_failure() -> None:
    """A genuinely empty tenant (enumeration returns []) is Complete/Success —
    never the same shape as an enumeration failure."""
    ctx = _ctx()
    with patch.object(da, "probe_arg_resource_type", return_value=False), \
         patch.object(da, "enumerate_environments", return_value=[]):
        result = da.scan_all(ctx)

    summary = result["summary"]
    assert summary["status"] == "Complete"
    assert summary["environmentEnumeration"]["status"] == "Success"
    assert summary["environmentEnumeration"]["environmentCount"] == 0
    assert summary["environmentFailures"] == []


# =============================================================================
# _scan_one_environment — structured per-environment failures
# =============================================================================

def test_scan_one_environment_bots_403_recorded_as_failed_not_zero() -> None:
    """A per-environment bot read 403 must produce status Failed with a structured
    coverage-gap record — never an empty (zero-agent) success."""
    ctx = _ctx()
    env = {"name": "contoso-env-01", "url": "https://contoso01.crm.dynamics.com"}
    with patch.object(
        da, "scan_environment_bots",
        side_effect=da.EnvironmentScanError("403", http_status=403, stage="bots"),
    ):
        result = da._scan_one_environment(ctx, MagicMock(), env)

    assert result["status"] == "Failed"
    assert result["agents"] == []
    assert len(result["failures"]) == 1
    failure = result["failures"][0]
    assert failure["environmentId"] == "contoso-env-01"
    assert failure["stage"] == "bots"
    assert failure["httpStatus"] == 403


def test_scan_one_environment_generic_exception_recorded_as_failed() -> None:
    """An unexpected per-environment exception is retained as a failure (stage
    'environment'), not swallowed into a silent zero-agent result."""
    ctx = _ctx()
    env = {"name": "contoso-env-02"}
    with patch.object(
        da, "scan_environment_bots",
        side_effect=RuntimeError("unexpected boom"),
    ):
        result = da._scan_one_environment(ctx, MagicMock(), env)

    assert result["status"] == "Failed"
    assert len(result["failures"]) == 1
    assert result["failures"][0]["stage"] == "environment"
    assert result["failures"][0]["environmentId"] == "contoso-env-02"


def test_scan_one_environment_feature_failure_is_incomplete_and_flags_agent() -> None:
    """Bots read OK but a per-bot feature read 403: the agent row is kept and
    flagged Incomplete Scan, the environment is Incomplete, and the feature-scan
    failure is retained with the offending bot id."""
    ctx = _ctx()
    env = {"name": "contoso-env-03", "url": "https://contoso03.crm.dynamics.com"}
    bot = {"botid": "bot-guid-0003", "name": "Northwind Support Bot",
           "accesscontrolpolicy": 2}
    with patch.object(da, "scan_environment_bots", return_value=([bot], None)), \
         patch.object(
             da, "scan_bot_features",
             side_effect=da.EnvironmentScanError(
                 "bc 403", http_status=403, stage="botcomponents")):
        result = da._scan_one_environment(ctx, MagicMock(), env)

    assert result["status"] == "Incomplete"
    assert len(result["agents"]) == 1
    assert result["agents"][0]["fsi_scancompleteness"] == "Incomplete Scan"
    assert len(result["failures"]) == 1
    assert result["failures"][0]["stage"] == "botcomponents"
    assert result["failures"][0]["botId"] == "bot-guid-0003"
    # The auth-share posture row is still captured despite the feature-scan gap.
    assert len(result["authShares"]) == 1


def test_scan_one_environment_mid_loop_exception_recorded_not_aborting() -> None:
    """An unexpected error while iterating bots is retained as a coverage gap
    (status Failed), never propagated to abort the whole tenant scan."""
    ctx = _ctx()
    env = {"name": "contoso-env-06", "url": "https://contoso06.crm.dynamics.com"}
    bot = {"botid": "bot-guid-0006", "name": "Boom Bot", "accesscontrolpolicy": 2}
    with patch.object(da, "scan_environment_bots", return_value=([bot], None)), \
         patch.object(da, "map_agent_record",
                      side_effect=RuntimeError("unexpected mapping error")):
        result = da._scan_one_environment(ctx, MagicMock(), env)

    assert result["status"] == "Failed"
    assert len(result["failures"]) == 1
    assert result["failures"][0]["stage"] == "environment"


def test_scan_one_environment_success_is_complete_no_failures() -> None:
    """A clean environment scan yields status Complete and no failures."""
    ctx = _ctx()
    env = {"name": "contoso-env-04", "url": "https://contoso04.crm.dynamics.com"}
    bot = {"botid": "bot-guid-0004", "name": "Clean Bot", "accesscontrolpolicy": 2}
    with patch.object(da, "scan_environment_bots", return_value=([bot], None)), \
         patch.object(da, "scan_bot_features", return_value=[]):
        result = da._scan_one_environment(ctx, MagicMock(), env)

    assert result["status"] == "Complete"
    assert result["failures"] == []
    assert len(result["agents"]) == 1


# =============================================================================
# scan_all — per-environment failure aggregation into overall status
# =============================================================================

def test_scan_all_all_environments_failed_is_failed() -> None:
    """If every scanned environment failed, the overall scan status is Failed."""
    ctx = _ctx()
    failed_outcome = {
        "agents": [], "features": [], "authShares": [],
        "failures": [da._env_failure("contoso-env-05", "bots", 403, "403")],
        "status": "Failed",
    }
    with patch.object(da, "probe_arg_resource_type", return_value=False), \
         patch.object(da, "enumerate_environments",
                      return_value=[{"name": "contoso-env-05"}]), \
         patch.object(da, "_scan_one_environment", return_value=failed_outcome):
        result = da.scan_all(ctx)

    summary = result["summary"]
    assert summary["status"] == "Failed"
    assert len(summary["environmentFailures"]) == 1
    assert summary["environmentFailures"][0]["environmentId"] == "contoso-env-05"


def test_scan_all_some_environments_failed_is_incomplete() -> None:
    """When some (not all) environments fail, the overall scan is Incomplete and
    the failing environment surfaces in environmentFailures."""
    ctx = _ctx()

    def fake_scan(_ctx, _session, env):
        if env["name"] == "bad":
            return {
                "agents": [], "features": [], "authShares": [],
                "failures": [da._env_failure("bad", "bots", 403, "403")],
                "status": "Failed",
            }
        return {"agents": [], "features": [], "authShares": [],
                "failures": [], "status": "Complete"}

    with patch.object(da, "probe_arg_resource_type", return_value=False), \
         patch.object(da, "enumerate_environments",
                      return_value=[{"name": "good"}, {"name": "bad"}]), \
         patch.object(da, "_scan_one_environment", side_effect=fake_scan):
        result = da.scan_all(ctx)

    summary = result["summary"]
    assert summary["status"] == "Incomplete"
    assert any(f["environmentId"] == "bad" for f in summary["environmentFailures"])


# =============================================================================
# scan_all — ARG layer: unavailable / failed / observed-zero are distinct
# =============================================================================

def test_scan_all_arg_available_zero_is_distinct_from_failed() -> None:
    """ARG probe succeeds and returns zero agents → argLayer Available with
    agentCount 0 (a genuine observed zero, NOT a failure)."""
    ctx = _ctx(use_arg=True)
    with patch.object(da, "probe_arg_resource_type", return_value=True), \
         patch.object(da, "query_arg_inventory", return_value=[]), \
         patch.object(da, "enumerate_environments", return_value=[]):
        result = da.scan_all(ctx)

    arg = result["summary"]["argLayer"]
    assert arg["status"] == "Available"
    assert arg["agentCount"] == 0
    assert result["summary"]["status"] == "Complete"


def test_scan_all_arg_query_failure_is_failed_not_observed_zero() -> None:
    """A failed ARG query is recorded as argLayer Failed (with HTTP status) and
    degrades the overall scan to Incomplete — never treated as observed zero."""
    ctx = _ctx(use_arg=True)
    with patch.object(da, "probe_arg_resource_type", return_value=True), \
         patch.object(da, "query_arg_inventory",
                      side_effect=da.ArgQueryError("500", http_status=500)), \
         patch.object(da, "enumerate_environments", return_value=[]):
        result = da.scan_all(ctx)

    arg = result["summary"]["argLayer"]
    assert arg["status"] == "Failed"
    assert arg["httpStatus"] == 500
    assert arg["agentCount"] == 0
    assert result["summary"]["status"] == "Incomplete"


def test_scan_all_arg_throttled_is_failed() -> None:
    """ARG throttled to exhaustion → argLayer Failed (fallback to Layer 2)."""
    ctx = _ctx(use_arg=True)
    with patch.object(da, "probe_arg_resource_type", return_value=True), \
         patch.object(da, "query_arg_inventory",
                      side_effect=da.ThrottlingExhaustedError("throttled")), \
         patch.object(da, "enumerate_environments", return_value=[]):
        result = da.scan_all(ctx)

    assert result["summary"]["argLayer"]["status"] == "Failed"


def test_scan_all_arg_unavailable_is_normal_fallback_and_complete() -> None:
    """ARG probe False (type not resolvable) → argLayer Unavailable, Layer 2 is
    the load-bearing default, overall status Complete."""
    ctx = _ctx(use_arg=True)
    with patch.object(da, "probe_arg_resource_type", return_value=False), \
         patch.object(da, "enumerate_environments", return_value=[]):
        result = da.scan_all(ctx)

    assert result["summary"]["argLayer"]["status"] == "Unavailable"
    assert result["summary"]["status"] == "Complete"


def test_scan_all_arg_disabled_when_no_arg() -> None:
    """--no-arg (use_arg False) → argLayer Disabled."""
    ctx = _ctx(use_arg=False)
    with patch.object(da, "enumerate_environments", return_value=[]):
        result = da.scan_all(ctx)

    assert result["summary"]["argLayer"]["status"] == "Disabled"


# =============================================================================
# CLI — exit code + argument validation
# =============================================================================

def test_main_exits_nonzero_when_scan_status_failed(monkeypatch: pytest.MonkeyPatch) -> None:
    """A Failed scan status must surface as a non-zero process exit."""
    monkeypatch.setattr(sys, "argv", ["discover_agents.py", "--dry-run"])
    failed_result = {
        "summary": {"status": "Failed", "environmentEnumeration": {},
                    "environmentFailures": []},
        "agents": [], "features": [], "authShares": [],
    }
    with patch.object(da, "scan_all", return_value=failed_result):
        with pytest.raises(SystemExit) as excinfo:
            da.main()
    assert excinfo.value.code == 1


def test_main_complete_status_does_not_exit(monkeypatch: pytest.MonkeyPatch) -> None:
    """A Complete scan status returns normally (no SystemExit)."""
    monkeypatch.setattr(sys, "argv", ["discover_agents.py", "--dry-run"])
    ok_result = {
        "summary": {"status": "Complete", "environmentEnumeration": {},
                    "environmentFailures": []},
        "agents": [], "features": [], "authShares": [],
    }
    with patch.object(da, "scan_all", return_value=ok_result):
        da.main()  # must not raise


def test_main_resolve_entitlement_without_registry_export_errors(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """--resolve-entitlement without --registry-export must fail argument
    validation (argparse error → SystemExit code 2), never run silently."""
    monkeypatch.setattr(
        sys, "argv",
        ["discover_agents.py", "--dry-run", "--resolve-entitlement"],
    )
    with pytest.raises(SystemExit) as excinfo:
        da.main()
    assert excinfo.value.code == 2


def test_main_resolve_entitlement_with_registry_export_is_allowed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """--resolve-entitlement WITH --registry-export passes argument validation."""
    monkeypatch.setattr(
        sys, "argv",
        ["discover_agents.py", "--dry-run", "--resolve-entitlement",
         "--registry-export", "fake-export.xlsx"],
    )
    ok_result = {
        "summary": {"status": "Complete", "environmentEnumeration": {},
                    "environmentFailures": []},
        "agents": [], "features": [], "authShares": [],
    }
    with patch.object(da, "scan_all", return_value=ok_result):
        da.main()  # must not raise (validation passes)


# =============================================================================
# Agent 365 v0.4 — CLI precedence, sanitization, dry-run I/O, run IDs
# =============================================================================


def test_main_defaults_to_agent365_absent(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict = {}

    def _fake_scan(ctx):
        captured["ctx"] = ctx
        return {"summary": {"status": "Complete", "environmentFailures": []},
                "agents": [], "features": [], "authShares": []}

    monkeypatch.delenv("CAI_AGENT365", raising=False)
    monkeypatch.setattr(sys, "argv", ["discover_agents.py", "--dry-run"])
    with patch.object(da, "scan_all", side_effect=_fake_scan):
        da.main()
    ctx = captured["ctx"]
    assert ctx.agent365_requested_mode == "absent"
    assert ctx.agent365_resolution_source == "Default"


def test_main_env_mode_used_when_cli_absent(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict = {}

    def _fake_scan(ctx):
        captured["ctx"] = ctx
        return {"summary": {"status": "Complete", "environmentFailures": []},
                "agents": [], "features": [], "authShares": []}

    monkeypatch.setenv("CAI_AGENT365", "auto")
    monkeypatch.setattr(sys, "argv", ["discover_agents.py", "--dry-run"])
    with patch.object(da, "scan_all", side_effect=_fake_scan):
        da.main()
    assert captured["ctx"].agent365_requested_mode == "auto"
    assert captured["ctx"].agent365_resolution_source == "Environment"


def test_main_deprecated_alias_maps_to_present_and_warns(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    captured: dict = {}

    def _fake_scan(ctx):
        captured["ctx"] = ctx
        return {"summary": {"status": "Complete", "environmentFailures": []},
                "agents": [], "features": [], "authShares": []}

    monkeypatch.delenv("CAI_AGENT365", raising=False)
    monkeypatch.setattr(
        sys,
        "argv",
        ["discover_agents.py", "--dry-run", "--enable-package-api"],
    )
    with patch.object(da, "scan_all", side_effect=_fake_scan), caplog.at_level("WARNING"):
        da.main()
    assert captured["ctx"].agent365_requested_mode == "present"
    assert captured["ctx"].agent365_resolution_source == "DeprecatedAlias"
    assert any("DEPRECATED: --enable-package-api" in rec.getMessage() for rec in caplog.records)


def test_main_cli_mode_has_highest_precedence_when_inputs_agree(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured: dict = {}

    def _fake_scan(ctx):
        captured["ctx"] = ctx
        return {"summary": {"status": "Complete", "environmentFailures": []},
                "agents": [], "features": [], "authShares": []}

    monkeypatch.setenv("CAI_AGENT365", "present")
    monkeypatch.setattr(
        sys,
        "argv",
        ["discover_agents.py", "--dry-run", "--agent365", "present", "--enable-package-api"],
    )
    with patch.object(da, "scan_all", side_effect=_fake_scan):
        da.main()
    assert captured["ctx"].agent365_requested_mode == "present"
    assert captured["ctx"].agent365_resolution_source == "CLI"


def test_main_conflicting_cli_and_alias_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        sys,
        "argv",
        ["discover_agents.py", "--dry-run", "--agent365", "auto", "--enable-package-api"],
    )
    with pytest.raises(SystemExit) as excinfo:
        da.main()
    assert excinfo.value.code == 2


def test_main_invalid_agent365_env_value_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CAI_AGENT365", "maybe")
    monkeypatch.setattr(sys, "argv", ["discover_agents.py", "--dry-run"])
    with pytest.raises(SystemExit) as excinfo:
        da.main()
    assert excinfo.value.code == 2


def test_main_reads_agent365_alias_overrides_from_named_env(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured: dict = {}

    def _fake_scan(ctx):
        captured["ctx"] = ctx
        return {"summary": {"status": "Complete", "environmentFailures": []},
                "agents": [], "features": [], "authShares": []}

    monkeypatch.setenv("CAI_AGENT365_LICENSE_ALIASES", "contoso-agent-365-custom, Foo Plan")
    monkeypatch.delenv("CAI_AGENT365_SKU_ALIASES", raising=False)
    monkeypatch.setattr(sys, "argv", ["discover_agents.py", "--dry-run"])
    with patch.object(da, "scan_all", side_effect=_fake_scan):
        da.main()
    assert captured["ctx"].agent365_alias_overrides == (
        "CONTOSO_AGENT_365_CUSTOM",
        "FOO_PLAN",
    )


def test_main_legacy_agent365_alias_env_still_works_with_warning(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    captured: dict = {}

    def _fake_scan(ctx):
        captured["ctx"] = ctx
        return {"summary": {"status": "Complete", "environmentFailures": []},
                "agents": [], "features": [], "authShares": []}

    monkeypatch.delenv("CAI_AGENT365_LICENSE_ALIASES", raising=False)
    monkeypatch.setenv("CAI_AGENT365_SKU_ALIASES", "legacy-value")
    monkeypatch.setattr(sys, "argv", ["discover_agents.py", "--dry-run"])
    with patch.object(da, "scan_all", side_effect=_fake_scan), caplog.at_level("WARNING"):
        da.main()
    assert captured["ctx"].agent365_alias_overrides == ("LEGACY_VALUE",)
    assert any("DEPRECATED: CAI_AGENT365_SKU_ALIASES" in rec.getMessage() for rec in caplog.records)


def test_generate_run_id_has_contract_length_and_sortable_prefix() -> None:
    now = da.datetime(2026, 7, 22, 17, 0, 0, tzinfo=da.timezone.utc)
    run_id = da._generate_run_id(now)
    assert run_id.startswith("cai-20260722T170000Z-")
    assert len(run_id) == 35


def test_generate_run_id_is_collision_resistant() -> None:
    now = da.datetime(2026, 7, 22, 17, 0, 0, tzinfo=da.timezone.utc)
    run_ids = {da._generate_run_id(now) for _ in range(80)}
    assert len(run_ids) == 80


def test_generate_run_id_prefix_remains_sortable_across_seconds() -> None:
    earlier = da._generate_run_id(da.datetime(2026, 7, 22, 16, 59, 59, tzinfo=da.timezone.utc))
    later = da._generate_run_id(da.datetime(2026, 7, 22, 17, 0, 0, tzinfo=da.timezone.utc))
    assert earlier < later


def test_sanitize_reason_redacts_bearer_upn_and_url() -> None:
    text = (
        "Bearer abc.def.ghi user alice@contoso.com "
        "https://contoso.crm.dynamics.com/api/data"
    )
    cleaned = da._sanitize_reason(text)
    assert "abc.def.ghi" not in cleaned
    assert "alice@contoso.com" not in cleaned
    assert "contoso.crm.dynamics.com" not in cleaned
    assert "<redacted-upn>" in cleaned
    assert "<redacted-url>" in cleaned


def test_scan_all_dry_run_auto_performs_no_token_or_network_io() -> None:
    ctx = da.ScanContext(
        run_id="dryrun-auto-001",
        dry_run=True,
        agent365_requested_mode="auto",
        agent365_resolution_source="Test",
    )
    with patch.object(da, "_get_token") as mock_token, patch.object(
        da, "_request_with_backoff"
    ) as mock_request:
        result = da.scan_all(ctx)
    mock_token.assert_not_called()
    mock_request.assert_not_called()
    assert result["summary"]["status"] == "Dry Run"
    assert result["summary"]["agent365"]["detectionConfidence"] == "Inconclusive"
    assert result["summary"]["agent365"]["layerStatus"] == da.LAYER_STATUS_DRY_RUN
