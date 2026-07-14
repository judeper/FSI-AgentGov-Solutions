"""Static currency/dependency guards for audit-compliance-manager.

These checks validate static remediations from the 2026-07-14 review:
- manifest dependency correction (AOF optional, not required)
- ExchangeOnlineManagement compatibility bounds for current runtime
- runbook auth migration away from MSAL.PS/Get-MsalToken
"""

from __future__ import annotations

import re
from pathlib import Path

SOLUTION_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_ROOT = SOLUTION_ROOT / "scripts"


def _manifest_dependencies(manifest_text: str) -> list[str]:
    """Parse top-level `dependencies` entries from manifest.yaml text."""
    deps: list[str] = []
    in_dependencies = False

    for raw_line in manifest_text.splitlines():
        line = raw_line.rstrip()
        if not in_dependencies and re.match(r"^dependencies:\s*$", line):
            in_dependencies = True
            continue

        if not in_dependencies:
            continue

        # End dependencies block at next top-level key
        if re.match(r"^[A-Za-z0-9_-]+:\s*", line):
            break

        match = re.match(r"^\s*-\s*(\S+)\s*$", line)
        if match:
            deps.append(match.group(1))

    return deps


def test_manifest_removes_hard_aof_dependency() -> None:
    manifest_path = SOLUTION_ROOT / "manifest.yaml"
    text = manifest_path.read_text(encoding="utf-8")
    deps = _manifest_dependencies(text)
    assert "agent-observability-foundation" not in deps, (
        "audit-compliance-manager should not declare agent-observability-foundation "
        "as a hard manifest dependency; keep it documented as optional integration."
    )


def test_exchange_scripts_bound_maximum_version_for_current_runtime() -> None:
    required_re = re.compile(
        r"ModuleName\s*=\s*['\"]ExchangeOnlineManagement['\"][^\r\n]*MaximumVersion\s*=\s*['\"]3\.9\.2['\"]",
        re.IGNORECASE,
    )
    script_paths = [
        SCRIPTS_ROOT / "Enable-AuditLogging.ps1",
        SCRIPTS_ROOT / "Invoke-TenantAuditValidation.ps1",
        SCRIPTS_ROOT / "Start-TenantValidationRunbook.ps1",
        SCRIPTS_ROOT / "Test-AuditLoggingCompliance.ps1",
        SCRIPTS_ROOT / "Test-MailboxAudit.ps1",
        SCRIPTS_ROOT / "Test-PurviewRetention.ps1",
        SCRIPTS_ROOT / "Test-UnifiedAuditLog.ps1",
        SCRIPTS_ROOT / "private" / "Connect-AuditServices.ps1",
    ]

    missing: list[str] = []
    for path in script_paths:
        text = path.read_text(encoding="utf-8")
        if not required_re.search(text):
            missing.append(str(path.relative_to(SOLUTION_ROOT)))

    assert not missing, (
        "ExchangeOnlineManagement compatibility bound (MaximumVersion=\"3.9.2\") "
        "missing from: " + ", ".join(missing)
    )


def test_runbook_wrappers_use_connect_powerplatform_not_msal() -> None:
    runbooks = [
        SCRIPTS_ROOT / "Start-TenantValidationRunbook.ps1",
        SCRIPTS_ROOT / "Start-EnvironmentValidationRunbook.ps1",
    ]

    for path in runbooks:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(SOLUTION_ROOT)
        assert "Connect-PowerPlatform.ps1" in text, f"{rel} should load Connect-PowerPlatform helper"
        assert re.search(r"\bConnect-PowerPlatform\b", text), f"{rel} should call Connect-PowerPlatform"
        assert "MSAL.PS" not in text, f"{rel} should not reference archived MSAL.PS"
        assert "Get-MsalToken" not in text, f"{rel} should not call Get-MsalToken"
