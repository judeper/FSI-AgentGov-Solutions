"""Pytest coverage for agent-intake classification routing."""

from __future__ import annotations

import copy
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from seed_classification_rules import build_self_test_cases, classify, load_policy


@pytest.fixture(scope="module")
def policy() -> dict:
    """Load the default classification policy once for the module."""
    return load_policy()


def _effective_policy(case: dict, base_policy: dict) -> dict:
    """Resolve a case-specific policy without mutating the shared fixture."""
    if case.get("policy_path"):
        return load_policy(case["policy_path"])
    policy_value = copy.deepcopy(case.get("policy", base_policy))
    transform = case.get("policy_transform")
    if transform:
        policy_value = transform(policy_value)
    return policy_value


@pytest.mark.parametrize("case", build_self_test_cases(), ids=lambda case: case["name"])
def test_classification_matrix(case: dict, policy: dict) -> None:
    """Cover every routing path, deny gate, and policy fallback in the matrix."""
    case_policy = _effective_policy(case, policy)

    if case.get("expect_error"):
        with pytest.raises(ValueError, match=rf"^{re.escape(case['expect_error'])}$"):
            classify(case["request"], case_policy)
        return

    result = classify(case["request"], case_policy)
    for key, expected_value in case["expected"].items():
        assert result[key] == expected_value, f"{case['name']} -> {key}"


def test_self_test_matrix_size() -> None:
    """Keep the regression matrix at or above the requested coverage floor."""
    assert len(build_self_test_cases()) >= 30


def test_classify_preserves_existing_keys(policy: dict) -> None:
    """Backwards-compatible keys remain available for downstream callers."""
    request = {
        "fsi_t1initiatesfinancialtxn": "No",
        "fsi_t2customerfacing": "No",
        "fsi_t3autonomousunmonitored": "No",
        "fsi_t4handlesnpi": "No",
        "fsi_t5handlesmnpi": "No",
        "fsi_t6crossborderdata": "No",
        "fsi_intendedaudience": "Just me",
        "fsi_makerupn": "maker@contoso.com",
        "fsi_sponsorupn": "sponsor@contoso.com",
        "fsi_makercountry": "US",
        "fsi_dataresidencycountry": "US",
    }

    result = classify(request, policy)

    assert result["decisionPath"] == "Express"
    assert result["tier"] == 3
    assert result["risktier"] == "Tier 3 (Low)"
    assert result["zone"] == 3
    assert result["retentionLabel"] == "FSI-AgentIntake-7yr"
    assert isinstance(result["routing"], dict)
    assert result["managedEnvironment"] == "recommended"
    assert result["dlpConnectorGroup"] == "nonBusinessDataOnly"
