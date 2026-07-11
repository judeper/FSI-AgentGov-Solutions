"""Pin the proposed branch protection and docs-autonomy trigger contract."""

from __future__ import annotations

import importlib.util
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "docs-autonomy.yml"
PROTECTION = ROOT / ".github" / "branch-protection.json"
EXPECTED_CONTEXTS = [
    "Analyze csharp",
    "Analyze python",
    "commercial-scope",
    "dependency-review",
    "docs-autonomy",
    "gitleaks",
    "language-rules",
    "lint",
    "manifest-check",
    "powershell",
    "python",
]
REQUIRED_WORKFLOWS = {
    "Analyze csharp": ("codeql.yml", "name: Analyze ${{ matrix.language }}"),
    "Analyze python": ("codeql.yml", "name: Analyze ${{ matrix.language }}"),
    "commercial-scope": ("commercial-scope.yml", "  commercial-scope:"),
    "dependency-review": ("dependency-review.yml", "  dependency-review:"),
    "docs-autonomy": ("docs-autonomy.yml", "  docs-autonomy:"),
    "gitleaks": ("gitleaks.yml", "  gitleaks:"),
    "language-rules": ("language-rules.yml", "  language-rules:"),
    "lint": ("odata-lint.yml", "  lint:"),
    "manifest-check": ("manifest-check.yml", "  manifest-check:"),
    "powershell": ("ci-powershell.yml", "  powershell:"),
    "python": ("ci-python.yml", "  python:"),
}


def load_docs_autonomy_module():
    """Load the path classifier without requiring scripts to be a package."""
    path = ROOT / "scripts" / "docs_autonomy.py"
    spec = importlib.util.spec_from_file_location("docs_autonomy", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def pull_request_block(workflow: str) -> str:
    """Return the pull_request trigger block."""
    match = re.search(r"(?m)^  pull_request:\n((?:^    .*\n|^\s*$)*)", workflow)
    assert match, "workflow must declare a pull_request trigger"
    return match.group(1)


def test_branch_protection_is_strict_without_human_review_or_destructive_writes():
    policy = json.loads(PROTECTION.read_text(encoding="utf-8"))

    assert policy["required_status_checks"] == {
        "strict": True,
        "contexts": EXPECTED_CONTEXTS,
    }
    assert policy["enforce_admins"] is True
    assert policy["required_pull_request_reviews"] is None
    assert policy["restrictions"] is None
    assert policy["allow_force_pushes"] is False
    assert policy["allow_deletions"] is False


def test_required_docs_context_runs_on_every_pull_request_without_path_filters():
    workflow = WORKFLOW.read_text(encoding="utf-8")
    trigger = pull_request_block(workflow)

    assert "  docs-autonomy:\n" in workflow
    assert "paths:" not in trigger
    assert "paths-ignore:" not in trigger
    assert "Non-doc shim" in workflow
    assert "steps.changes.outputs.docs != 'true'" in workflow
    assert "--diff-filter=ACDMRT" in workflow


def test_every_required_context_runs_on_every_pull_request_without_path_filters():
    assert set(REQUIRED_WORKFLOWS) == set(EXPECTED_CONTEXTS)
    for context, (filename, job_marker) in REQUIRED_WORKFLOWS.items():
        workflow = (
            ROOT / ".github" / "workflows" / filename
        ).read_text(encoding="utf-8")
        trigger = pull_request_block(workflow)
        assert job_marker in workflow, f"{context} job marker changed"
        assert "paths:" not in trigger, f"{context} is path-filtered"
        assert "paths-ignore:" not in trigger, f"{context} is path-filtered"


def test_classifier_selects_docs_and_manifest_changes_but_shims_code_only_changes():
    classifier = load_docs_autonomy_module()

    assert classifier.classify_paths(
        [
            "README.md",
            "agent-intake/docs/setup.md",
            "agent-intake/manifest.yaml",
            "site-docs/removed-page.md",
            "site-docs/stylesheets/extra.css",
        ]
    ) == [
        "README.md",
        "agent-intake/docs/setup.md",
        "agent-intake/manifest.yaml",
        "site-docs/removed-page.md",
        "site-docs/stylesheets/extra.css",
    ]
    assert classifier.classify_paths(
        [
            "agent-intake/scripts/deploy.py",
            "message-center-monitor/scripts/Invoke-Monitor.ps1",
        ]
    ) == []


def test_path_filtered_optional_jobs_are_not_required():
    policy = json.loads(PROTECTION.read_text(encoding="utf-8"))
    contexts = policy["required_status_checks"]["contexts"]

    assert "dotnet build (Debug)" not in contexts
    assert "dotnet build (Release)" not in contexts
    assert "agent-intake-python" not in contexts
    assert "heartbeat" not in contexts
