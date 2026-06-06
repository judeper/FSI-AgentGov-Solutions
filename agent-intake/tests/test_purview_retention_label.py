"""Unit tests for setup_purview_retention_label.py pure-logic functions.

Covers label spec construction and spec output with/without Graph beta sample.
Live Purview validation (Connect-IPPSSession, New-ComplianceTag) requires human
intervention per issue #123.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import setup_purview_retention_label  # noqa: E402  (path injected above)
from setup_purview_retention_label import (
    DEFAULT_LABEL_NAME,
    DEFAULT_RETENTION_DAYS,
    DEFAULT_WORM_LABEL_NAME,
    build_compliance_tag_commands,
    build_label_spec,
    build_spec,
)

_PS_SCRIPT = (
    Path(__file__).resolve().parent.parent / "scripts" / "setup_purview_retention_label.ps1"
)

# ---------------------------------------------------------------------------
# build_label_spec
# ---------------------------------------------------------------------------


def test_build_label_spec_defaults() -> None:
    """Default spec matches the documented FSI-AgentIntake-7yr shape."""
    spec = build_label_spec(DEFAULT_LABEL_NAME, DEFAULT_WORM_LABEL_NAME, DEFAULT_RETENTION_DAYS)
    assert spec["displayName"] == "FSI-AgentIntake-7yr"
    assert spec["retentionDuration"]["days"] == 2555
    assert spec["retentionTrigger"] == "dateCreated"
    assert spec["behaviorDuringRetentionPeriod"] == "retain"
    assert spec["actionAfterRetentionPeriod"] == "none"
    assert spec["isInUse"] is False


def test_build_label_spec_worm_variant() -> None:
    """WORM variant has record behavior and locked default."""
    spec = build_label_spec(DEFAULT_LABEL_NAME, DEFAULT_WORM_LABEL_NAME, DEFAULT_RETENTION_DAYS)
    worm = spec["wormVariant"]
    assert worm["displayName"] == "FSI-AgentIntake-7yr-WORM"
    assert worm["behaviorDuringRetentionPeriod"] == "retainAsRecord"
    assert worm["defaultRecordBehavior"] == "startLocked"


def test_build_label_spec_custom_values() -> None:
    """Custom names and retention days propagate correctly."""
    spec = build_label_spec("CustomLabel", "CustomLabel-WORM", 365)
    assert spec["displayName"] == "CustomLabel"
    assert spec["retentionDuration"]["days"] == 365
    assert spec["wormVariant"]["displayName"] == "CustomLabel-WORM"


def test_build_label_spec_regulatory_references() -> None:
    """Description references SEC 17a-4, FINRA 4511, CFTC 1.31."""
    spec = build_label_spec(DEFAULT_LABEL_NAME, DEFAULT_WORM_LABEL_NAME, DEFAULT_RETENTION_DAYS)
    assert "SEC 17a-4" in spec["description"]
    assert "FINRA 4511" in spec["description"]
    assert "CFTC 1.31" in spec["description"]


def test_build_label_spec_admin_description_references_dataverse() -> None:
    """Admin description references the Dataverse tables used for evidence."""
    spec = build_label_spec(DEFAULT_LABEL_NAME, DEFAULT_WORM_LABEL_NAME, DEFAULT_RETENTION_DAYS)
    assert "fsi_intakedecisionlog" in spec["descriptionForAdmins"]
    assert "fsi_intakeretentionrecord" in spec["descriptionForAdmins"]


# ---------------------------------------------------------------------------
# build_spec
# ---------------------------------------------------------------------------


def test_build_spec_without_graph_beta() -> None:
    """Spec without Graph beta sample has label but no graphBetaCreateSample."""
    spec = build_spec(
        label_name=DEFAULT_LABEL_NAME,
        worm_label_name=DEFAULT_WORM_LABEL_NAME,
        retention_days=DEFAULT_RETENTION_DAYS,
        include_graph_beta=False,
    )
    assert "label" in spec
    assert "graphBetaCreateSample" not in spec


def test_build_spec_with_graph_beta() -> None:
    """Spec with Graph beta includes the sample URL and permission note."""
    spec = build_spec(
        label_name=DEFAULT_LABEL_NAME,
        worm_label_name=DEFAULT_WORM_LABEL_NAME,
        retention_days=DEFAULT_RETENTION_DAYS,
        include_graph_beta=True,
    )
    assert "graphBetaCreateSample" in spec
    sample = spec["graphBetaCreateSample"]
    assert sample["method"] == "POST"
    assert "beta" in sample["url"]
    assert "retentionLabels" in sample["url"]
    assert "RecordsManagement.ReadWrite.All" in sample["permission"]


def test_build_spec_is_json_serializable() -> None:
    """The full spec round-trips through JSON without error."""
    spec = build_spec(
        label_name=DEFAULT_LABEL_NAME,
        worm_label_name=DEFAULT_WORM_LABEL_NAME,
        retention_days=DEFAULT_RETENTION_DAYS,
        include_graph_beta=True,
    )
    serialized = json.dumps(spec, indent=2)
    deserialized = json.loads(serialized)
    assert deserialized["label"]["displayName"] == DEFAULT_LABEL_NAME


# ---------------------------------------------------------------------------
# Production-path request-shape lock: New-ComplianceTag (issue #123)
#
# Ground truth re-verified by Rusty 2026-06-06 against Microsoft Learn:
#   Production create = New-ComplianceTag -RetentionAction Keep
#                       -RetentionType CreationAgeInDays   (WORM adds -IsRecordLabel $true)
#   Ref: https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag
#   Graph create is GA at v1.0 and also present at beta:
#     POST https://graph.microsoft.com/v1.0/security/labels/retentionLabels
#   Delegated RecordsManagement.ReadWrite.All; application permissions NOT supported.
#   Ref: https://learn.microsoft.com/graph/api/security-labelsroot-post-retentionlabel?view=graph-rest-1.0
# ---------------------------------------------------------------------------


def test_compliance_tag_commands_lock_production_switches() -> None:
    """The offline preview must mirror the exact New-ComplianceTag switches."""
    standard, worm = build_compliance_tag_commands(
        DEFAULT_LABEL_NAME, DEFAULT_WORM_LABEL_NAME, DEFAULT_RETENTION_DAYS
    )
    for command in (standard, worm):
        assert command.startswith("New-ComplianceTag")
        assert "-RetentionAction Keep" in command
        assert "-RetentionType CreationAgeInDays" in command
        assert f"-RetentionDuration {DEFAULT_RETENTION_DAYS}" in command
    # Standard label is NOT a record; only the WORM variant marks items as records.
    assert "-IsRecordLabel $true" not in standard
    assert "-IsRecordLabel $true" in worm
    assert DEFAULT_LABEL_NAME in standard
    assert DEFAULT_WORM_LABEL_NAME in worm


def test_graph_create_ga_v1_url_documented() -> None:
    """Manual guidance advertises the GA v1.0 create endpoint (not only beta)."""
    assert (
        "https://graph.microsoft.com/v1.0/security/labels/retentionLabels"
        in setup_purview_retention_label.MANUAL_STEPS
    )
    # Application permissions are explicitly unsupported — keep the caveat visible.
    assert "Application permissions are" in setup_purview_retention_label.MANUAL_STEPS
    assert "not supported" in setup_purview_retention_label.MANUAL_STEPS


def test_graph_beta_sample_scope_and_app_caveat() -> None:
    """Beta sample keeps delegated scope + 'not documented for application' caveat."""
    spec = build_spec(
        label_name=DEFAULT_LABEL_NAME,
        worm_label_name=DEFAULT_WORM_LABEL_NAME,
        retention_days=DEFAULT_RETENTION_DAYS,
        include_graph_beta=True,
    )
    sample = spec["graphBetaCreateSample"]
    assert sample["method"] == "POST"
    assert sample["url"] == "https://graph.microsoft.com/beta/security/labels/retentionLabels"
    assert "RecordsManagement.ReadWrite.All" in sample["permission"]
    assert "application permissions" in sample["permission"].lower()


# ---------------------------------------------------------------------------
# Dry-run offline-safety locks (issue #123)
#
# Rusty's key safety fix: --dry-run / -DryRun must NOT open any tenant
# connection. The Python wrapper's only outbound action is subprocess.run (which
# shells to pwsh -> Connect-IPPSSession). The PS wrapper's -DryRun block must
# reach `exit 0` BEFORE the first Connect-IPPSSession.
# ---------------------------------------------------------------------------


def _run_purview_main(monkeypatch: pytest.MonkeyPatch, argv: list[str]) -> int:
    monkeypatch.setattr(sys, "argv", ["setup_purview_retention_label.py", *argv])
    return setup_purview_retention_label.main()


def test_python_dry_run_never_shells_out(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    """--dry-run must return before run_powershell_wrapper, even with wrapper on.

    subprocess.run is the only egress in this module; monkeypatch it to raise so
    any shell-out (-> Connect-IPPSSession) fails the test loudly.
    """
    def _no_subprocess(*_args: object, **_kwargs: object) -> object:
        raise AssertionError(
            "subprocess.run invoked — dry-run must not shell out to pwsh/IPPSSession"
        )

    monkeypatch.setattr(setup_purview_retention_label.subprocess, "run", _no_subprocess)
    rc = _run_purview_main(monkeypatch, ["--dry-run", "--use-powershell-wrapper"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "[DRY RUN]" in out
    assert "offline preview" in out


def test_python_wrapper_subprocess_sentinel_is_wired(monkeypatch: pytest.MonkeyPatch) -> None:
    """Positive control: WITHOUT --dry-run the wrapper DOES shell out.

    Guards against the dry-run test passing vacuously — proves subprocess.run is
    actually on the live wrapper path so its absence under --dry-run is meaningful.
    """
    def _sentinel(*_args: object, **_kwargs: object) -> object:
        raise AssertionError("subprocess.run invoked")

    monkeypatch.setattr(setup_purview_retention_label.subprocess, "run", _sentinel)
    with pytest.raises(AssertionError, match="subprocess.run invoked"):
        _run_purview_main(monkeypatch, ["--use-powershell-wrapper"])


def test_ps_dry_run_block_exits_before_any_connect() -> None:
    """Static guard for Rusty's fix: -DryRun reaches `exit 0` before any connect.

    Offline/deterministic — reads the script text. Proves the -DryRun branch
    cannot fall through to Connect-IPPSSession / Connect-ExchangeOnline, which is
    exactly the live-tenant connection the previous version opened before
    skipping the write.
    """
    text = _PS_SCRIPT.read_text(encoding="utf-8")
    # Anchor on the top-level offline-preview block (not the per-label guard inside
    # Add-RetentionLabelResult) and on the EXECUTABLE connect call (not the
    # .PARAMETER doc-comment mention of Connect-IPPSSession).
    guard_idx = text.index("# Offline preview: emit the exact New-ComplianceTag")
    dry_run_exit_idx = text.index("exit 0", guard_idx)
    connect_idx = text.index("Connect-IPPSSession -UserPrincipalName")
    assert dry_run_exit_idx < connect_idx, (
        "DryRun offline block must `exit 0` before Connect-IPPSSession"
    )
    # No tenant-connecting cmdlet may appear between the guard and its exit.
    between = text[guard_idx:dry_run_exit_idx]
    assert "Connect-IPPSSession" not in between
    assert "Connect-ExchangeOnline" not in between
    assert "Install-Module" not in between


@pytest.mark.skipif(shutil.which("pwsh") is None, reason="pwsh not available")
def test_ps_dry_run_execution_is_offline() -> None:
    """Execution proof (when pwsh present): -DryRun emits [DRY RUN] and never connects.

    The -DryRun branch runs only pure string builders + Write-Host before exit 0,
    so this stays offline (no module install, no tenant connection).
    """
    completed = subprocess.run(
        ["pwsh", "-NoLogo", "-NoProfile", "-File", str(_PS_SCRIPT), "-DryRun"],
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    combined = completed.stdout + completed.stderr
    assert "[DRY RUN]" in combined
    assert "-RetentionType CreationAgeInDays" in combined
    # Must not have attempted the live Security & Compliance connection.
    assert "Connecting to Security & Compliance" not in combined
