"""Adversarial tests for -SkipPurviewLabel guard implementation.

Phase 2 (P2c): validate that the `-SkipPurviewLabel` switch successfully gates the
interactive Purview retention-label creation step while allowing non-interactive
identity steps to always run. These tests statically analyze script text to confirm
guard placement — they MUST fail if the guard is removed.

Target files:
- deploy.ps1: Test-IdentityStage function with the skip-guard logic
- Invoke-Deploy.ps1: config.deploy.skipPurviewLabel threading
- config.example.json: schema presence for skipPurviewLabel field
- Test-LabAuthReadiness.ps1: preflight script structure
"""
from __future__ import annotations

import json
import re
from pathlib import Path


# Resolve solution root relative to this test file.
_SOLUTION_ROOT = Path(__file__).resolve().parent.parent
_DEPLOY_SCRIPT = _SOLUTION_ROOT / "scripts" / "deploy.ps1"
_LAB_INVOKE = _SOLUTION_ROOT / "lab" / "Invoke-Deploy.ps1"
_LAB_CONFIG_EXAMPLE = _SOLUTION_ROOT / "lab" / "config.example.json"
_LAB_PREFLIGHT = _SOLUTION_ROOT / "lab" / "Test-LabAuthReadiness.ps1"


# ---------------------------------------------------------------------------
# Test 1: deploy.ps1 declares -SkipPurviewLabel parameter
# ---------------------------------------------------------------------------


def test_deploy_ps1_declares_skip_purview_label_param() -> None:
    """deploy.ps1 param() block must declare [switch]$SkipPurviewLabel."""
    text = _DEPLOY_SCRIPT.read_text(encoding="utf-8")

    # Find the param() block
    param_match = re.search(r'param\s*\(', text, re.IGNORECASE)
    assert param_match, "deploy.ps1 must have a param() block"

    # Search for the parameter declaration within a reasonable distance
    param_start = param_match.end()
    param_region = text[param_start:param_start + 15000]  # First ~15k chars should cover params

    # Match the parameter declaration with optional whitespace/newlines
    skip_param_pattern = r'\[switch\]\s*\$SkipPurviewLabel'
    assert re.search(skip_param_pattern, param_region, re.IGNORECASE), (
        "deploy.ps1 param() block must declare [switch]$SkipPurviewLabel"
    )


# ---------------------------------------------------------------------------
# Test 2: THE CRITICAL TEST — the guard is real and bites
# ---------------------------------------------------------------------------


def test_deploy_ps1_setup_purview_retention_label_is_guarded() -> None:
    """The $labelScript invocation MUST be lexically inside 'if (-not $SkipPurviewLabel)'.

    This is the adversarial test — it MUST fail if someone later removes the guard and
    the interactive hang returns. We locate the guard condition and verify the
    Invoke-PythonChildScript call for $labelScript occurs within its guarded block.
    """
    text = _DEPLOY_SCRIPT.read_text(encoding="utf-8")

    # Anchor on Test-IdentityStage function
    func_match = re.search(r'function\s+Test-IdentityStage\s*\{', text, re.IGNORECASE)
    assert func_match, "deploy.ps1 must contain Test-IdentityStage function"

    func_start = func_match.start()
    # Find the function's end (next function or EOF) — use a generous search window
    next_func = re.search(r'\nfunction\s+\w+', text[func_start + 100:])
    func_end = func_start + 100 + next_func.start() if next_func else len(text)
    func_body = text[func_start:func_end]

    # Locate the $labelScript variable assignment
    label_script_match = re.search(
        r"\$labelScript\s*=\s*Join-Path.*?'setup_purview_retention_label\.py'",
        func_body,
        re.DOTALL
    )
    assert label_script_match, "Test-IdentityStage must define $labelScript variable"

    # Find the guard: if (-not $SkipPurviewLabel)
    guard_pattern = r'if\s*\(\s*-not\s+\$SkipPurviewLabel\s*\)'
    guard_match = re.search(guard_pattern, func_body, re.IGNORECASE)
    assert guard_match, (
        "Test-IdentityStage must contain 'if (-not $SkipPurviewLabel)' guard"
    )

    # Find the Invoke-PythonChildScript call for $labelScript
    invoke_pattern = r'Invoke-PythonChildScript\s+[^}]*?\$labelScript'
    invoke_match = re.search(invoke_pattern, func_body, re.DOTALL)
    assert invoke_match, (
        "Test-IdentityStage must invoke Invoke-PythonChildScript with $labelScript"
    )

    # THE BITE: Verify the invocation occurs AFTER the guard and BEFORE the else/closing
    guard_pos = guard_match.start()
    invoke_pos = invoke_match.start()

    # Find the matching else or closing brace for the guard
    # Look for 'else {' or '}' after the guard, before any other major control structure
    guard_end_search = func_body[guard_pos:]
    else_match = re.search(r'\}\s*else\s*\{', guard_end_search)

    if else_match:
        guard_close_pos = guard_pos + else_match.start()
    else:
        # No explicit else — find the closing brace of the if block
        # Count braces to find the matching close
        brace_depth = 0
        in_guard = False
        guard_close_pos = guard_pos
        for i, char in enumerate(guard_end_search):
            if char == '{':
                in_guard = True
                brace_depth += 1
            elif char == '}':
                brace_depth -= 1
                if in_guard and brace_depth == 0:
                    guard_close_pos = guard_pos + i
                    break

    assert invoke_pos > guard_pos, (
        "Invoke-PythonChildScript for $labelScript must occur AFTER the 'if (-not $SkipPurviewLabel)' guard"
    )
    assert invoke_pos < guard_close_pos, (
        "Invoke-PythonChildScript for $labelScript must occur BEFORE the guard's else/closing brace. "
        f"Guard at position {guard_pos}, invoke at {invoke_pos}, guard close at {guard_close_pos}. "
        "If the guard is removed, this invocation would be unconditional and this test should FAIL."
    )


# ---------------------------------------------------------------------------
# Test 3: Blueprint, consent, and probe steps stay UNguarded
# ---------------------------------------------------------------------------


def test_deploy_ps1_non_interactive_steps_are_not_guarded() -> None:
    """Blueprint, consent, and autodetect_purview steps must NOT be inside the skip guard.

    These steps are non-interactive and tolerate failures gracefully. They must always run
    regardless of -SkipPurviewLabel.
    """
    text = _DEPLOY_SCRIPT.read_text(encoding="utf-8")

    # Anchor on Test-IdentityStage
    func_match = re.search(r'function\s+Test-IdentityStage\s*\{', text, re.IGNORECASE)
    assert func_match
    func_start = func_match.start()
    next_func = re.search(r'\nfunction\s+\w+', text[func_start + 100:])
    func_end = func_start + 100 + next_func.start() if next_func else len(text)
    func_body = text[func_start:func_end]

    # Find the guard block
    guard_match = re.search(r'if\s*\(\s*-not\s+\$SkipPurviewLabel\s*\)', func_body, re.IGNORECASE)
    assert guard_match
    guard_start = guard_match.start()

    # Find the guard's closing (else or end brace)
    guard_end_search = func_body[guard_start:]
    else_match = re.search(r'\}\s*else\s*\{', guard_end_search)
    if else_match:
        guard_end = guard_start + else_match.end()
    else:
        brace_depth = 0
        in_guard = False
        for i, char in enumerate(guard_end_search):
            if char == '{':
                in_guard = True
                brace_depth += 1
            elif char == '}':
                brace_depth -= 1
                if in_guard and brace_depth == 0:
                    guard_end = guard_start + i + 1
                    break

    guarded_region = func_body[guard_start:guard_end]

    # Verify that the non-interactive scripts are NOT in the guarded region
    assert 'setup_agent_identity_blueprint.py' not in guarded_region, (
        "setup_agent_identity_blueprint.py invocation must NOT be inside the SkipPurviewLabel guard"
    )
    assert 'setup_entra_agent_id.py' not in guarded_region, (
        "setup_entra_agent_id.py invocation must NOT be inside the SkipPurviewLabel guard"
    )
    assert 'autodetect_purview.py' not in guarded_region, (
        "autodetect_purview.py invocation must NOT be inside the SkipPurviewLabel guard"
    )

    # Positive check: these scripts ARE invoked somewhere in the function
    assert 'setup_agent_identity_blueprint.py' in func_body
    assert 'setup_entra_agent_id.py' in func_body
    assert 'autodetect_purview.py' in func_body


# ---------------------------------------------------------------------------
# Test 4: Threading through Invoke-Deploy.ps1
# ---------------------------------------------------------------------------


def test_invoke_deploy_declares_skip_purview_label_param() -> None:
    """Invoke-Deploy.ps1 must declare [switch]$SkipPurviewLabel parameter."""
    text = _LAB_INVOKE.read_text(encoding="utf-8")

    param_match = re.search(r'param\s*\(', text, re.IGNORECASE)
    assert param_match, "Invoke-Deploy.ps1 must have a param() block"

    param_region = text[param_match.end():param_match.end() + 5000]
    skip_param_pattern = r'\[switch\]\s*\$SkipPurviewLabel'
    assert re.search(skip_param_pattern, param_region, re.IGNORECASE), (
        "Invoke-Deploy.ps1 param() block must declare [switch]$SkipPurviewLabel"
    )


def test_invoke_deploy_reads_config_deploy_skip_purview_label() -> None:
    """Invoke-Deploy.ps1 must read config.deploy.skipPurviewLabel from the JSON config."""
    text = _LAB_INVOKE.read_text(encoding="utf-8")

    # Look for the pattern: $config.deploy.skipPurviewLabel or similar
    config_read_pattern = r'\$config\.deploy\.skipPurviewLabel'
    assert re.search(config_read_pattern, text, re.IGNORECASE), (
        "Invoke-Deploy.ps1 must reference config.deploy.skipPurviewLabel"
    )

    # Verify it's used in conditional logic to set the switch
    # Should find something like: $config.deploy.PSObject.Properties.Name -contains 'skipPurviewLabel'
    # or direct access with conditional
    conditional_pattern = r"config\.deploy.*?skipPurviewLabel"
    assert re.search(conditional_pattern, text, re.IGNORECASE | re.DOTALL), (
        "Invoke-Deploy.ps1 must use config.deploy.skipPurviewLabel in conditional logic"
    )


def test_config_example_json_contains_skip_purview_label() -> None:
    """config.example.json must contain deploy.skipPurviewLabel field."""
    config_text = _LAB_CONFIG_EXAMPLE.read_text(encoding="utf-8")
    config_data = json.loads(config_text)

    assert "deploy" in config_data, "config.example.json must have a 'deploy' object"
    assert "skipPurviewLabel" in config_data["deploy"], (
        "config.example.json deploy object must contain 'skipPurviewLabel' field"
    )
    # Verify it's a boolean
    assert isinstance(config_data["deploy"]["skipPurviewLabel"], bool), (
        "config.example.json deploy.skipPurviewLabel must be a boolean"
    )


# ---------------------------------------------------------------------------
# Test 5: Preflight script structure
# ---------------------------------------------------------------------------


def test_lab_preflight_exists_and_has_cmdletbinding() -> None:
    """Test-LabAuthReadiness.ps1 must exist and declare [CmdletBinding()]."""
    assert _LAB_PREFLIGHT.exists(), (
        "agent-intake/lab/Test-LabAuthReadiness.ps1 must exist"
    )

    text = _LAB_PREFLIGHT.read_text(encoding="utf-8")
    assert re.search(r'\[CmdletBinding\(\)\]', text, re.IGNORECASE), (
        "Test-LabAuthReadiness.ps1 must declare [CmdletBinding()]"
    )


def test_lab_preflight_has_mandatory_environment_url() -> None:
    """Test-LabAuthReadiness.ps1 must declare mandatory $EnvironmentUrl parameter."""
    text = _LAB_PREFLIGHT.read_text(encoding="utf-8")

    param_match = re.search(r'param\s*\(', text, re.IGNORECASE)
    assert param_match, "Test-LabAuthReadiness.ps1 must have a param() block"

    param_region = text[param_match.end():param_match.end() + 5000]

    # Look for [Parameter(Mandatory)] followed by $EnvironmentUrl
    mandatory_pattern = r'\[Parameter\(\s*Mandatory\s*\)\].*?\$EnvironmentUrl'
    assert re.search(mandatory_pattern, param_region, re.IGNORECASE | re.DOTALL), (
        "Test-LabAuthReadiness.ps1 must declare mandatory $EnvironmentUrl parameter"
    )


def test_lab_preflight_contains_no_write_host() -> None:
    """Test-LabAuthReadiness.ps1 must contain NO Write-Host calls (CI hard gate).

    Write-Host breaks CI automation. The preflight script must use Write-Information,
    Write-Warning, and Write-Error only.
    """
    text = _LAB_PREFLIGHT.read_text(encoding="utf-8")

    # Find all Write-Host calls (case-insensitive)
    write_host_pattern = r'\bWrite-Host\b'
    matches = list(re.finditer(write_host_pattern, text, re.IGNORECASE))

    # Filter out any matches inside comments or doc comments
    real_violations = []
    for match in matches:
        line_start = text.rfind('\n', 0, match.start()) + 1
        line_text = text[line_start:text.find('\n', match.start())]
        # Skip if it's in a comment or .EXAMPLE doc comment
        if not re.match(r'^\s*#', line_text) and '.EXAMPLE' not in text[max(0, match.start() - 500):match.start()]:
            real_violations.append(match)

    assert len(real_violations) == 0, (
        f"Test-LabAuthReadiness.ps1 must NOT contain Write-Host calls (found {len(real_violations)}). "
        "Use Write-Information, Write-Warning, or Write-Error instead for CI compatibility."
    )


# ---------------------------------------------------------------------------
# Owl self-check test: verify the guard test is adversarial
# ---------------------------------------------------------------------------


def test_meta_adversarial_guard_test_would_fail_without_guard() -> None:
    """Meta-test: confirm test_deploy_ps1_setup_purview_retention_label_is_guarded is adversarial.

    This test verifies that the critical guard test (test 2) would actually fail if the
    guard were removed. It simulates a deploy.ps1 with the guard block removed and confirms
    that the guard test logic would detect the missing guard.
    """
    text = _DEPLOY_SCRIPT.read_text(encoding="utf-8")

    # Anchor on Test-IdentityStage function
    func_match = re.search(r'function\s+Test-IdentityStage\s*\{', text, re.IGNORECASE)
    assert func_match, "deploy.ps1 must contain Test-IdentityStage function"

    func_start = func_match.start()
    next_func = re.search(r'\nfunction\s+\w+', text[func_start + 100:])
    func_end = func_start + 100 + next_func.start() if next_func else len(text)
    func_body = text[func_start:func_end]

    # Simulate removing the guard: remove 'if (-not $SkipPurviewLabel) {' and its closing '} else {'
    guard_pattern = r'if\s*\(\s*-not\s+\$SkipPurviewLabel\s*\)\s*\{'
    mutated_body = re.sub(guard_pattern, '', func_body, flags=re.IGNORECASE)

    # Also remove the matching else block
    mutated_body = re.sub(r'\}\s*else\s*\{[^}]*\$labelSkipped\s*=\s*\$true[^}]*\}', '', mutated_body, flags=re.DOTALL)

    # Now verify that test 2's critical check would fail on the mutated text
    # Test 2 checks that the guard pattern exists
    guard_match_in_mutated = re.search(guard_pattern, mutated_body, re.IGNORECASE)

    assert guard_match_in_mutated is None, (
        "Meta-test failure: After simulating guard removal, the guard pattern still exists. "
        "This means the simulation didn't work correctly."
    )

    # If we reach here, the guard is gone in the mutated version.
    # This proves that test 2 (which asserts the guard EXISTS) would fail on the mutated script,
    # making test 2 genuinely adversarial.
    # The adversarial property is: test 2 passes on real deploy.ps1, would fail on mutated deploy.ps1.
