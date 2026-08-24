"""Regression checks for severe Python CodeQL findings."""

from __future__ import annotations

import ast
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def _tree(relative_path: str) -> ast.Module:
    source = (REPO_ROOT / relative_path).read_text(encoding="utf-8")
    return ast.parse(source)


def test_service_principal_logs_do_not_format_secret_metadata() -> None:
    tree = _tree(
        "environment-lifecycle-management/scripts/register_service_principal.py"
    )
    sensitive_names = {"secret", "secret_name", "credentials", "cred", "password"}

    for call in (
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "print"
    ):
        for joined in (
            node for node in ast.walk(call) if isinstance(node, ast.JoinedStr)
        ):
            formatted_names = {
                child.id
                for child in ast.walk(joined)
                if isinstance(child, ast.Name)
            }
            assert formatted_names.isdisjoint(sensitive_names)


def test_telemetry_responses_are_initialized_before_query() -> None:
    for relative_path in (
        "agent-observability-foundation/scripts/verify_telemetry.py",
        "copilot-studio-analytics/scripts/validate_telemetry.py",
    ):
        source = (REPO_ROOT / relative_path).read_text(encoding="utf-8")
        assert "response = None\n    try:" in source
        assert "if response is None:" in source


def test_codeql_uninitialized_and_unused_patterns_are_absent() -> None:
    evidence_source = (
        REPO_ROOT
        / "environment-lifecycle-management/scripts/export_quarterly_evidence.py"
    ).read_text(encoding="utf-8")
    deploy_source = (
        REPO_ROOT / "finra-supervision-workflow/scripts/deploy.py"
    ).read_text(encoding="utf-8")
    drift_source = (
        REPO_ROOT / "hitl-workflow-governance/tests/test_connector_drift.py"
    ).read_text(encoding="utf-8")

    assert 'parser.error(f"Invalid date format: {e}")\n        return' in evidence_source
    assert "deploy_all" not in deploy_source
    assert "for m in zero_indexed_pattern.finditer(line):" not in drift_source
    assert "if zero_indexed_pattern.search(line):" in drift_source
