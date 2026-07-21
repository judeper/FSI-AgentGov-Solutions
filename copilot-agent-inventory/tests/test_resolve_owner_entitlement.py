"""Tests for resolve_owner_entitlement.py.

Adversarial matrix covered:
  _classify_user (pure classification, no subprocess):
    - hasCopilotLicense=True => "Paid Copilot"; evidence = matchedPlanIds JSON
    - Evidence for paid contains ONLY service-plan GUIDs — no UPN or PII
    - Bing_Chat_Enterprise GUID (deny trap) with no paid plan => "Copilot Chat Only"
    - BCE deny evidence contains ONLY the BCE GUID
    - BCE deny evidence has no UPN or PII
    - No paid plan + no deny GUID => "Unknown"; evidence = "[]"
    - Paid plan AND deny GUID simultaneously => paid takes precedence
    - BCE GUID comparison is case-insensitive

  resolve_entitlements (orchestration, subprocess mocked):
    - Empty UPN list => empty result list (no subprocess call)
    - Any subprocess/_invoke_ps1 failure => ALL UPNs set to Unknown (fail-open;
      never assert "blocked" for an unverifiable user)
    - UPN absent from PS1 output users[] => Unknown (fail-open)
    - Result ordering matches input UPN order regardless of PS1 output order
    - UPN strings never appear in any output field (fsi_ownerentitlementevidence)
    - Paid evidence is a valid JSON array containing the matched plan GUIDs
    - UPN lookup in PS1 output is case-insensitive

All subprocess and azure-identity calls are mocked — no live network calls.
Synthetic identities use Contoso/Northwind domains only.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

try:
    import resolve_owner_entitlement as roe

    _IMPORT_ERROR: Exception | None = None
except Exception as exc:  # pragma: no cover
    roe = None  # type: ignore[assignment]
    _IMPORT_ERROR = exc

pytestmark = pytest.mark.skipif(
    roe is None,
    reason=f"resolve_owner_entitlement could not be imported: {_IMPORT_ERROR}",
)

# Synthetic service-plan GUIDs — NOT real Microsoft GUIDs.
_PLAN_A = "11111111-aaaa-0000-0000-synth00000001"
_PLAN_B = "22222222-bbbb-0000-0000-synth00000002"

# Authoritative BCE GUID from the module constant (deny trap).
_BCE_GUID = roe._BCE_PLAN_GUID if roe else "0d0c0d31-fae7-41f2-b909-eaf4d7f26dba"

# Synthetic UPNs (Contoso/Northwind only).
_UPN_PAID      = "advisor@contoso.com"
_UPN_CHAT_ONLY = "chat-only@northwind.com"
_UPN_UNKNOWN   = "ghost@contoso.com"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _ps1_output(*users: dict) -> dict:
    """Build a synthetic PS1 output document matching the expected shape."""
    return {"users": list(users)}


def _paid_user(upn: str) -> dict:
    return {
        "upn": upn,
        "hasCopilotLicense": True,
        "matchedPlanIds": [_PLAN_A, _PLAN_B],
        "deniedPlanIdsObserved": [],
    }


def _chat_only_user(upn: str) -> dict:
    return {
        "upn": upn,
        "hasCopilotLicense": False,
        "matchedPlanIds": [],
        "deniedPlanIdsObserved": [_BCE_GUID],
    }


def _unknown_user_obj(upn: str) -> dict:
    return {
        "upn": upn,
        "hasCopilotLicense": False,
        "matchedPlanIds": [],
        "deniedPlanIdsObserved": [],
    }


# =============================================================================
# _classify_user — pure classification logic
# =============================================================================

def test_classify_user_paid_returns_paid_label() -> None:
    label, _ = roe._classify_user(_paid_user(_UPN_PAID))
    assert label == roe.ENTITLEMENT_PAID


def test_classify_user_paid_evidence_contains_matched_plan_guids() -> None:
    _, evidence = roe._classify_user(_paid_user(_UPN_PAID))
    parsed = json.loads(evidence)
    assert isinstance(parsed, list)
    assert _PLAN_A in parsed
    assert _PLAN_B in parsed


def test_classify_user_paid_evidence_has_no_upn_or_pii() -> None:
    """Evidence must contain ONLY service-plan GUIDs — no UPN, display name,
    or any other PII (privacy hard requirement from contract)."""
    user = _paid_user(_UPN_PAID)
    user["upn"] = _UPN_PAID  # PS1 output carries the UPN; must NOT appear in evidence
    _, evidence = roe._classify_user(user)
    assert _UPN_PAID not in evidence


def test_classify_user_bce_deny_trap_returns_chat_only() -> None:
    """The Bing_Chat_Enterprise GUID (0d0c0d31-...) is the deny-trap signal.
    With no paid plan, the classification must be 'Copilot Chat Only' — NOT Unknown."""
    label, _ = roe._classify_user(_chat_only_user(_UPN_CHAT_ONLY))
    assert label == roe.ENTITLEMENT_CHAT_ONLY


def test_classify_user_bce_deny_evidence_contains_bce_guid() -> None:
    _, evidence = roe._classify_user(_chat_only_user(_UPN_CHAT_ONLY))
    parsed = json.loads(evidence)
    assert _BCE_GUID in parsed


def test_classify_user_bce_deny_evidence_has_no_upn_or_pii() -> None:
    user = _chat_only_user(_UPN_CHAT_ONLY)
    _, evidence = roe._classify_user(user)
    assert _UPN_CHAT_ONLY not in evidence


def test_classify_user_no_paid_no_deny_is_unknown_with_empty_evidence() -> None:
    label, evidence = roe._classify_user(_unknown_user_obj(_UPN_UNKNOWN))
    assert label == roe.ENTITLEMENT_UNKNOWN
    assert json.loads(evidence) == []


def test_classify_user_paid_takes_precedence_over_deny_guid() -> None:
    """hasCopilotLicense=True is checked before deniedPlanIdsObserved.
    Paid must win even when the BCE deny GUID is also present."""
    user = {
        "hasCopilotLicense": True,
        "matchedPlanIds": [_PLAN_A],
        "deniedPlanIdsObserved": [_BCE_GUID],   # both signals present
    }
    label, _ = roe._classify_user(user)
    assert label == roe.ENTITLEMENT_PAID


def test_classify_user_bce_guid_comparison_is_case_insensitive() -> None:
    """BCE GUID matching must be case-insensitive to handle mixed-case PS1 output."""
    user = {
        "hasCopilotLicense": False,
        "matchedPlanIds": [],
        "deniedPlanIdsObserved": [_BCE_GUID.upper()],   # uppercase from PS1
    }
    label, _ = roe._classify_user(user)
    assert label == roe.ENTITLEMENT_CHAT_ONLY


def test_classify_user_empty_denied_list_is_not_chat_only() -> None:
    """An empty deniedPlanIdsObserved must NOT trigger the DENY trap."""
    user = {
        "hasCopilotLicense": False,
        "matchedPlanIds": [],
        "deniedPlanIdsObserved": [],
    }
    label, _ = roe._classify_user(user)
    assert label == roe.ENTITLEMENT_UNKNOWN


def test_classify_user_null_matchedplanids_is_handled() -> None:
    """PS1 may return null for matchedPlanIds; must not raise."""
    user = {
        "hasCopilotLicense": True,
        "matchedPlanIds": None,     # defensive: null from PS1
        "deniedPlanIdsObserved": [],
    }
    label, evidence = roe._classify_user(user)
    assert label == roe.ENTITLEMENT_PAID
    assert isinstance(json.loads(evidence), list)


# =============================================================================
# resolve_entitlements — orchestration with mocked _invoke_ps1
# =============================================================================

def _resolve(upns: list[str], ps1_out: dict | None = None, fail: bool = False) -> list[dict]:
    """Helper: call resolve_entitlements with _invoke_ps1 mocked.

    resolve_entitlements now returns (results, invocation_failed).  _resolve unpacks
    the tuple and returns only the results list so existing call-sites are unchanged.
    """
    if fail:
        side_effect = RuntimeError("pwsh not found in test environment")
        ctx_patch = patch.object(roe, "_invoke_ps1", side_effect=side_effect)
    else:
        ctx_patch = patch.object(roe, "_invoke_ps1", return_value=ps1_out or {})
    with ctx_patch:
        results, _ = roe.resolve_entitlements(
            upns=upns,
            ps1_path=Path("dummy_Get-CopilotEntitlement.ps1"),
            graph_token="fake-bearer-token",
            work_dir=Path("."),
            run_id="test-run-resolve-001",
        )
        return results


def test_resolve_empty_upn_list_returns_empty_without_subprocess() -> None:
    with patch.object(roe, "_invoke_ps1") as mock_ps1:
        results, invocation_failed = roe.resolve_entitlements(
            upns=[],
            ps1_path=Path("dummy.ps1"),
            graph_token="fake",
            work_dir=Path("."),
            run_id="run-empty",
        )
    assert results == []
    assert invocation_failed is False
    mock_ps1.assert_not_called()


def test_resolve_subprocess_failure_sets_all_upns_to_unknown() -> None:
    """Any _invoke_ps1 failure must set ALL UPNs to Unknown — fail-open,
    never assert 'blocked' for an unverifiable user."""
    result = _resolve([_UPN_PAID, _UPN_CHAT_ONLY], fail=True)
    assert len(result) == 2
    assert all(r["fsi_ownerentitlement"] == roe.ENTITLEMENT_UNKNOWN for r in result)
    assert all(json.loads(r["fsi_ownerentitlementevidence"]) == [] for r in result)


def test_resolve_upn_absent_from_ps1_output_is_unknown() -> None:
    """A UPN that appears in input but not in PS1 users[] must be Unknown."""
    ps1_out = _ps1_output(
        _paid_user(_UPN_PAID),
        # _UPN_UNKNOWN intentionally absent from output
    )
    result = _resolve([_UPN_PAID, _UPN_UNKNOWN], ps1_out=ps1_out)
    assert result[0]["fsi_ownerentitlement"] == roe.ENTITLEMENT_PAID
    assert result[1]["fsi_ownerentitlement"] == roe.ENTITLEMENT_UNKNOWN


def test_resolve_result_ordering_matches_input_order() -> None:
    """Results must be in the same order as the input UPN list even when the
    PS1 output returns users in a different order."""
    ps1_out = _ps1_output(
        # PS1 returns Chat-Only first, Paid second — opposite of input
        _chat_only_user(_UPN_CHAT_ONLY),
        _paid_user(_UPN_PAID),
    )
    # Input: Paid first, Chat-Only second
    result = _resolve([_UPN_PAID, _UPN_CHAT_ONLY], ps1_out=ps1_out)
    assert result[0]["fsi_ownerentitlement"] == roe.ENTITLEMENT_PAID
    assert result[1]["fsi_ownerentitlement"] == roe.ENTITLEMENT_CHAT_ONLY


def test_resolve_no_upn_in_any_output_field() -> None:
    """UPN strings must NEVER appear in any value of the output dicts.
    fsi_ownerentitlementevidence must contain only GUIDs (privacy requirement)."""
    ps1_out = _ps1_output(_paid_user(_UPN_PAID))
    result = _resolve([_UPN_PAID], ps1_out=ps1_out)
    for entry in result:
        for key, value in entry.items():
            assert _UPN_PAID not in str(value), (
                f"UPN '{_UPN_PAID}' leaked into output field '{key}': {value}"
            )


def test_resolve_paid_evidence_is_valid_json_list_of_guids() -> None:
    ps1_out = _ps1_output(_paid_user(_UPN_PAID))
    result = _resolve([_UPN_PAID], ps1_out=ps1_out)
    evidence = json.loads(result[0]["fsi_ownerentitlementevidence"])
    assert isinstance(evidence, list)
    assert _PLAN_A in evidence
    assert _PLAN_B in evidence
    assert _UPN_PAID not in evidence


def test_resolve_upn_lookup_is_case_insensitive() -> None:
    """UPN matching is case-insensitive — PS1 may return mixed case."""
    user = _paid_user(_UPN_PAID)
    user["upn"] = _UPN_PAID.upper()   # PS1 returns uppercase
    ps1_out = _ps1_output(user)
    result = _resolve([_UPN_PAID.lower()], ps1_out=ps1_out)   # input is lowercase
    assert result[0]["fsi_ownerentitlement"] == roe.ENTITLEMENT_PAID


def test_resolve_mixed_batch_paid_chat_only_unknown() -> None:
    """Full mixed batch: one paid, one chat-only, one absent => correct per-UPN labels."""
    ps1_out = _ps1_output(
        _paid_user(_UPN_PAID),
        _chat_only_user(_UPN_CHAT_ONLY),
        # _UPN_UNKNOWN intentionally absent
    )
    result = _resolve([_UPN_PAID, _UPN_CHAT_ONLY, _UPN_UNKNOWN], ps1_out=ps1_out)
    assert result[0]["fsi_ownerentitlement"] == roe.ENTITLEMENT_PAID
    assert result[1]["fsi_ownerentitlement"] == roe.ENTITLEMENT_CHAT_ONLY
    assert result[2]["fsi_ownerentitlement"] == roe.ENTITLEMENT_UNKNOWN


# =============================================================================
# _build_ps_command — call-operator regression (must use & not dot-source)
# =============================================================================

_DUMMY_PS1 = Path("C:/scripts/Get-CopilotEntitlement.ps1")
_DUMMY_IN   = Path("C:/tmp/input.json")
_DUMMY_OUT  = Path("C:/tmp/output.json")
_DUMMY_BILLING = Path("C:/tmp/billing.json")


def test_build_ps_command_uses_call_operator_not_dot_source() -> None:
    """cmd[3] must start with `& '` (call operator), NEVER with `. '` (dot-source).

    Get-CopilotEntitlement.ps1 guards its main block with
    `if ($MyInvocation.InvocationName -ne '.')`. Dot-sourcing silently skips the
    main block and produces no output file, causing every owner to resolve as
    Unknown. Regression lock for Rusty's fix."""
    cmd = roe._build_ps_command(_DUMMY_PS1, _DUMMY_IN, _DUMMY_OUT, _DUMMY_BILLING)
    command_str = cmd[3]
    assert command_str.startswith("& '"), (
        f"Command string must start with `& '` (call operator), got: {command_str!r}"
    )
    assert not command_str.startswith(". '"), (
        "Dot-source operator (`. '`) must NOT be used — it silently skips the "
        "ps1 main block and produces no output file."
    )


def test_build_ps_command_has_input_and_output_path_flags() -> None:
    """-InputPath and -OutputPath must appear in the -Command string."""
    cmd = roe._build_ps_command(_DUMMY_PS1, _DUMMY_IN, _DUMMY_OUT, _DUMMY_BILLING)
    command_str = cmd[3]
    assert "-InputPath" in command_str, "-InputPath flag missing from command string"
    assert "-OutputPath" in command_str, "-OutputPath flag missing from command string"


def test_build_ps_command_token_referenced_as_env_var_not_literal() -> None:
    """The Graph token must be `$env:CAI_GRAPH_TOKEN` in the command string —
    never a literal value in the argv list — to avoid process-list exposure."""
    cmd = roe._build_ps_command(_DUMMY_PS1, _DUMMY_IN, _DUMMY_OUT, _DUMMY_BILLING)
    command_str = cmd[3]
    assert "$env:CAI_GRAPH_TOKEN" in command_str, (
        "Token must be referenced as $env:CAI_GRAPH_TOKEN in the -Command string; "
        "a literal token on the arg list would expose it in the process list."
    )


# =============================================================================
# Integration: pwsh integration test (requires pwsh on PATH)
# =============================================================================

def test_invoke_ps1_integration_call_operator_resolves_paid_copilot(
    tmp_path: Path,
) -> None:
    """Integration test: a stub Get-CopilotEntitlement.ps1 with the REAL guard
    (`if ($MyInvocation.InvocationName -ne '.')`) must resolve to 'Paid Copilot'
    when invoked via the call operator (`&`).

    This test would FAIL against the old dot-source code: dot-sourcing skips the
    stub's main block, produces no output file, and every owner resolves as Unknown.

    Skipped when pwsh is not available on PATH.
    """
    if shutil.which("pwsh") is None:
        pytest.skip("pwsh not available on PATH — skipping pwsh integration test")

    stub_ps1 = tmp_path / "Get-CopilotEntitlement.ps1"
    stub_ps1.write_text(
        r"""
param(
    [string]$InputPath,
    [string]$OutputPath,
    [string]$GraphAccessToken,
    [string]$BillingPolicyInputPath
)

if ($MyInvocation.InvocationName -ne '.') {
    $inputData = Get-Content -Path $InputPath -Raw | ConvertFrom-Json
    $users = @()
    foreach ($upn in $inputData.upns) {
        $users += [PSCustomObject]@{
            upn                   = $upn
            hasCopilotLicense     = $true
            matchedPlanIds        = @("a809996b-0000-0000-0000-stub00000001")
            deniedPlanIdsObserved = @()
        }
    }
    $result = [PSCustomObject]@{ users = $users } | ConvertTo-Json -Depth 5
    Set-Content -Path $OutputPath -Value $result -Encoding UTF8
}
""",
        encoding="utf-8",
    )

    results, invocation_failed = roe.resolve_entitlements(
        upns=["advisor@contoso.com"],
        ps1_path=stub_ps1,
        graph_token="fake-bearer-for-integration-test",
        work_dir=tmp_path,
        run_id="integration-test-run-001",
    )

    assert not invocation_failed, (
        "resolve_entitlements reported invocation_failed=True; "
        "check that the stub PS1 correctly declares $BillingPolicyInputPath."
    )
    assert len(results) == 1, f"Expected 1 result, got {len(results)}"
    label = results[0]["fsi_ownerentitlement"]
    assert label == roe.ENTITLEMENT_PAID, (
        f"Expected '{roe.ENTITLEMENT_PAID}' from stub ps1; got '{label}'. "
        "If this is 'Unknown', the call operator (`&`) may have regressed to "
        "dot-source (`.`), which silently skips the ps1 main block."
    )


# =============================================================================
# Defect 1 regressions — billing-bypass
# =============================================================================


def test_build_ps_command_includes_billing_policy_input_path() -> None:
    """_build_ps_command must include -BillingPolicyInputPath in the -Command string.

    Regression for Defect 1 (billing-bypass): without -BillingPolicyInputPath the PS1
    else-branch calls Get-CbgResourceToken for https://api.powerplatform.com/, which
    throws on a managed-identity runner with no ambient Az context when
    -BillingApiAccessToken is not supplied. Passing the empty synthetic file
    causes the PS1 to skip the live billing API read entirely."""
    billing = Path("C:/tmp/billing-regression.json")
    cmd = roe._build_ps_command(_DUMMY_PS1, _DUMMY_IN, _DUMMY_OUT, billing)
    command_str = cmd[3]
    assert "-BillingPolicyInputPath" in command_str, (
        "-BillingPolicyInputPath must be present in the -Command string; "
        "without it the PS1 falls to the Az-context billing path and aborts."
    )
    # The path must be embedded in the string so PowerShell finds the file.
    billing_escaped = str(billing).replace("\\", "/")
    assert (
        str(billing) in command_str or billing_escaped in command_str
    ), f"billing_policy_file path not found in command_str: {command_str!r}"


def test_invoke_ps1_creates_billing_file_with_empty_policies(
    tmp_path: Path,
) -> None:
    """_invoke_ps1 must write {"billingPolicies": []} to a temp billing-policy file
    before invoking the PS1 subprocess, and delete it in the finally block.

    Regression for Defect 1 (billing-bypass): the file must contain exactly the
    empty-policies sentinel (no bearer token, no PII) so PowerShell's
    Get-CbgBillingPolicyArray reads zero policies, skipping the live billing read.
    """
    stub_ps1 = tmp_path / "stub.ps1"
    stub_ps1.write_text("exit 0", encoding="utf-8")

    captured: dict = {}

    def _spy_subprocess_run(cmd, **kw):
        # Locate the -BillingPolicyInputPath value in the -Command string.
        command_str = " ".join(str(c) for c in cmd)
        m = re.search(r"-BillingPolicyInputPath '([^']+)'", command_str)
        if m:
            bp = Path(m.group(1))
            if bp.exists():
                captured["content"] = bp.read_text(encoding="utf-8")
                captured["path"] = bp
        # Raise to simulate PS1 failure so the finally-cleanup block runs.
        raise RuntimeError("test-spy: forced subprocess failure")

    with patch.object(subprocess, "run", side_effect=_spy_subprocess_run):
        try:
            roe._invoke_ps1(
                upns=["spy-test@contoso.com"],
                ps1_path=stub_ps1,
                graph_token="fake-token",
                work_dir=tmp_path,
                run_id="billing-regression-001",
            )
        except Exception:
            pass  # expected: spy raises, _invoke_ps1 re-raises after cleanup

    assert "content" in captured, (
        "Billing-policy file was never created (or not found at the path "
        "embedded in -BillingPolicyInputPath) — _invoke_ps1 must write it "
        "before calling subprocess.run."
    )
    billing_data = json.loads(captured["content"])
    assert billing_data == {"billingPolicies": []}, (
        f'Billing file must be exactly {{"billingPolicies":[]}}; got {billing_data!r}. '
        "No bearer token or PII is permitted in this file."
    )
    # Cleanup: the billing file must be deleted even though the subprocess failed.
    assert not captured["path"].exists(), (
        "Billing-policy file was NOT deleted in the finally block; "
        "_invoke_ps1 must clean it up regardless of subprocess outcome."
    )


def test_real_ps1_smoke_billing_bypass(
    tmp_path: Path,
    caplog: "pytest.LogCaptureFixture",
) -> None:
    """Smoke test: the REAL Get-CopilotEntitlement.ps1 must reach Graph-based
    license classification WITHOUT aborting on a billing/Az-context error.

    Passing -BillingPolicyInputPath with {"billingPolicies":[]} causes the PS1 to
    skip the live Power Platform billing API read. With a dummy Graph token, Graph
    calls will fail (401) — but the failure must be Graph-auth, NOT an Az-context
    or Power Platform billing abort. A robust result is invocation_failed==False
    (PS1 wrote an output document with Unknown owners); at minimum the failure must
    not mention Az context / Get-AzAccessToken / api.powerplatform.com.

    Skipped when pwsh is not available on PATH.
    Regression for Defect 1 (billing-bypass).
    """
    if shutil.which("pwsh") is None:
        pytest.skip("pwsh not available on PATH — skipping real PS1 smoke test")

    real_ps1 = roe._DEFAULT_PS1_PATH
    if not real_ps1.exists():
        pytest.skip(f"Real PS1 not found at {real_ps1!r} — skipping smoke test")

    import logging

    with caplog.at_level(logging.ERROR, logger="resolve_owner_entitlement"):
        results, invocation_failed = roe.resolve_entitlements(
            upns=["smoke-test@contoso.com"],
            ps1_path=real_ps1,
            graph_token="dummy-graph-token-smoke-test",
            work_dir=tmp_path,
            run_id="smoke-billing-001",
        )

    # Best case: PS1 completed (billing bypass worked; Graph calls yielded Unknown).
    if not invocation_failed:
        assert len(results) == 1, (
            f"Expected 1 result from real PS1 smoke; got {len(results)}"
        )
        return

    # PS1 failed — assert the failure is NOT the billing / Az-context path.
    # Graph-auth failures (401 from the dummy token) are acceptable; billing/Az
    # failures mean the empty -BillingPolicyInputPath did not bypass the live read.
    az_billing_indicators = [
        "get-azaccesstoken",
        "connect-azaccount",
        "az.accounts",
        "api.powerplatform.com",
        "get-cbgresourcetoken",
        "billingapiaccessa",   # BillingApiAccessToken parameter reference
    ]
    error_text = caplog.text.lower()
    for indicator in az_billing_indicators:
        assert indicator not in error_text, (
            f"Real PS1 smoke test: failure contains billing/Az-context indicator "
            f"{indicator!r}, which means the empty -BillingPolicyInputPath did NOT "
            f"bypass the live billing API read (Defect 1 regression). "
            f"Full captured log: {caplog.text[:800]}"
        )
