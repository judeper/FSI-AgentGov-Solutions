"""Pin the framework reference contract.

Every workflow that checks out the framework repository must pin the same
release tag, and that tag must equal the framework version solution READMEs
declare they were validated against. A mismatch between the two is a
coverage-honesty defect: CI would validate manifests against one framework
version while the published documentation claims another (issue #325, F10).
"""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"

# Workflows that check out judeper/FSI-AgentGov and must carry the pin.
PINNED_WORKFLOWS = (
    "docs-autonomy.yml",
    "manifest-check.yml",
    "publish_docs.yml",
)

PIN_RE = re.compile(r"\$\{\{\s*vars\.FRAMEWORK_REF\s*\|\|\s*'([^']+)'\s*\}\}")
VALIDATED_RE = re.compile(
    r"^>\s*\*\*Validated against framework version:\*\*\s*(\S+)\s*$",
    re.MULTILINE,
)


def workflow_pins() -> dict[str, str]:
    """Return {workflow_filename: pinned_framework_tag}."""
    pins: dict[str, str] = {}
    for name in PINNED_WORKFLOWS:
        path = WORKFLOWS / name
        assert path.is_file(), f"{name} must exist"
        match = PIN_RE.search(path.read_text(encoding="utf-8"))
        assert match, f"{name} must pin the framework via vars.FRAMEWORK_REF"
        pins[name] = match.group(1)
    return pins


def readme_validated_versions() -> dict[str, str]:
    """Return {solution_slug: declared_framework_version} for solution READMEs."""
    declared: dict[str, str] = {}
    for manifest in sorted(ROOT.glob("*/manifest.yaml")):
        readme = manifest.parent / "README.md"
        if not readme.is_file():
            continue
        match = VALIDATED_RE.search(readme.read_text(encoding="utf-8"))
        if match:
            declared[manifest.parent.name] = match.group(1)
    return declared


def test_framework_pin_is_a_release_tag_not_main():
    """The pin must be an explicit release tag so builds stay reproducible."""
    for name, tag in workflow_pins().items():
        assert tag != "main", f"{name} must not pin the framework to 'main'"
        assert re.fullmatch(r"v\d+\.\d+\.\d+", tag), (
            f"{name} pins {tag!r}; expected a vMAJOR.MINOR.PATCH release tag"
        )


def test_all_workflows_pin_the_same_framework_tag():
    """A split pin would let two workflows validate against different controls."""
    pins = workflow_pins()
    assert len(set(pins.values())) == 1, f"workflows disagree on the pin: {pins}"


def test_solution_readmes_agree_on_one_validated_version():
    """Mixed validated-against claims make the pin unresolvable."""
    declared = readme_validated_versions()
    assert declared, "expected at least one solution README validated-against claim"
    assert len(set(declared.values())) == 1, (
        f"solution READMEs declare conflicting framework versions: "
        f"{sorted(set(declared.values()))}"
    )


def test_pin_matches_readme_validated_version():
    """The CI pin and the published validation claim must be the same tag."""
    pinned = next(iter(set(workflow_pins().values())))
    claimed = next(iter(set(readme_validated_versions().values())))
    assert pinned == claimed, (
        f"FRAMEWORK_REF pins {pinned} but solution READMEs claim validation "
        f"against {claimed}. Either bump the pin or correct the claim — "
        f"they must agree (issue #325, F10)."
    )
