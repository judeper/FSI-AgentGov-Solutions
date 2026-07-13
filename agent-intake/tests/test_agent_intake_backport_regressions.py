"""Regression checks for the v1.0.1-preview lab-validated back-port."""

from __future__ import annotations

from pathlib import Path


_SOLUTION_ROOT = Path(__file__).resolve().parent.parent
_LAB_PREFLIGHT = _SOLUTION_ROOT / "lab" / "Test-LabAuthReadiness.ps1"
_FLOW_STATE = _SOLUTION_ROOT / "scripts" / "Get-IntakeFlowState.ps1"
_SUBMISSION = _SOLUTION_ROOT / "scripts" / "New-IntakeSubmission.ps1"
_BINDING = _SOLUTION_ROOT / "scripts" / "Test-IntakeConnectionBinding.ps1"
_SOLUTION_SHELL = _SOLUTION_ROOT / "scripts" / "provision_solution_shell.ps1"


def test_lab_preflight_uses_acquired_bearer_headers() -> None:
    """Preflight must use in-memory Dataverse/Graph tokens when calling az rest."""

    text = _LAB_PREFLIGHT.read_text(encoding="utf-8")
    assert 'Authorization=Bearer $($dvToken.accessToken)' in text
    assert 'Authorization=Bearer $($graphToken.accessToken)' in text


def test_lab_preflight_uses_real_pac_exit_code() -> None:
    """Fresh-shell PAC probe must classify the native command result, not job completion."""

    text = _LAB_PREFLIGHT.read_text(encoding="utf-8")
    assert "< NUL" not in text
    assert "$job.State -eq 'Completed' ? 0 : 1" not in text
    assert "$pacExitCode = [int]$probe.ExitCode" in text
    raw = _LAB_PREFLIGHT.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf#Requires")
    assert not raw.startswith(b"\xef\xbb\xbf\xef\xbb\xbf")


def test_backported_helpers_use_dataverse_bearer_headers() -> None:
    """Back-ported helper scripts must use bearer auth from token helpers."""

    expected = 'Authorization      = "Bearer $(Get-DataverseAccessToken)"'
    for script_path in (_FLOW_STATE, _SUBMISSION, _BINDING):
        text = script_path.read_text(encoding="utf-8")
        assert expected in text, f"{script_path.name} must use Get-DataverseAccessToken() in Authorization header"


def test_solution_shell_uses_connectionreference_component_type_name() -> None:
    """Solution-shell must add connection references by pac type name and verify membership."""

    text = _SOLUTION_SHELL.read_text(encoding="utf-8")
    assert "-ComponentType 'connectionreference'" in text
    assert "function Assert-ConnectionReferenceInSolution" in text
    assert "Assert-ConnectionReferenceInSolution -Token $resolvedToken -LogicalNames $expectedConnectionReferenceNames" in text


def test_backported_scripts_use_sanitized_placeholders() -> None:
    """No private-lab tenant markers should appear in newly back-ported helper scripts/docs."""

    tracked_text = "\n".join(
        [
            _LAB_PREFLIGHT.read_text(encoding="utf-8"),
            _FLOW_STATE.read_text(encoding="utf-8"),
            _SUBMISSION.read_text(encoding="utf-8"),
            _BINDING.read_text(encoding="utf-8"),
        ]
    )
    for marker in (
        "https://contoso-dev.crm.dynamics.com",
        "https://<org-id>.crm.dynamics.com",
    ):
        assert marker not in tracked_text
