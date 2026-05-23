"""Smoke tests for the agent-intake validator scripts."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

VALIDATORS_DIR = Path(__file__).resolve().parent
REPO_ROOT = VALIDATORS_DIR.parents[2]



def run_validator(name: str) -> None:
    """Execute one validator script and require a zero exit code."""
    result = subprocess.run(
        [sys.executable, str(VALIDATORS_DIR / name)],
        capture_output=True,
        cwd=REPO_ROOT,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"{name} failed with exit code {result.returncode}:\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )



def test_question_catalogs() -> None:
    """Smoke-run the question catalog validator."""
    run_validator("validate_question_catalogs.py")



def test_adaptive_cards() -> None:
    """Smoke-run the Adaptive Card validator."""
    run_validator("validate_adaptive_cards.py")



def test_manifest() -> None:
    """Smoke-run the manifest validator."""
    run_validator("validate_manifest.py")



def test_policy_yaml() -> None:
    """Smoke-run the policy YAML validator."""
    run_validator("validate_policy_yaml.py")
