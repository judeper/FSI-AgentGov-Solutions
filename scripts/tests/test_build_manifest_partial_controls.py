"""Regression tests for partial control-coverage declarations in build-manifest.py.

`<slug>/controls-covered.json` is a generated artifact consumed by the framework
`solutions-lock.json` contract, and `manifest.yaml.controls_partial` is the only
supported way to declare partial coverage. Six solutions previously carried
hand-edited `coverage: "partial"` values (plus a non-schema `coverageScope`
block) in that generated file while their manifests declared nothing, so any
regeneration silently upgraded 12 control claims to `coverage: "full"` --
manufacturing stronger compliance claims than the evidence supports.

These tests pin both halves of the fix: the manifest field must round-trip into
the generated export, and a `controls_partial` entry that is absent from
`controls[]` must fail validation instead of being silently dropped.

The build script is loaded by path because its filename contains a hyphen (not
an importable module name), mirroring test_build_manifest_lab_images.py.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]

# Solutions whose control coverage is PARTIAL, with the evidence anchor that
# documents why. Each entry maps slug -> controls that must stay partial.
PARTIAL_COVERAGE_SOLUTIONS: dict[str, set[str]] = {
    "action-confirmation-auditor": {"2.12", "1.10"},
    "agent-access-monitor": {"3.8"},
    "agent-sharing-access-restriction-detector": {"1.18", "2.8"},
    "content-moderation-monitor": {"1.27", "1.8"},
    "file-upload-security": {"1.14", "1.8", "1.4"},
    "generative-ai-config-auditor": {"2.24"},
}


def load_build_manifest():
    path = ROOT / "scripts" / "build-manifest.py"
    spec = importlib.util.spec_from_file_location("build_manifest_partial_test", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bm = load_build_manifest()


def _manifest(slug: str) -> dict:
    return yaml.safe_load((ROOT / slug / "manifest.yaml").read_text(encoding="utf-8"))


def test_partial_controls_round_trip_into_generated_export() -> None:
    """Regenerating controls-covered.json must preserve every partial claim."""
    for slug, expected_partial in PARTIAL_COVERAGE_SOLUTIONS.items():
        m = _manifest(slug)
        exported = json.loads(bm.emit_controls_covered_json(slug, m))
        actual_partial = {
            c["id"] for c in exported["controls"] if c["coverage"] == "partial"
        }
        assert actual_partial == expected_partial, (
            f"{slug}: expected partial coverage for {sorted(expected_partial)}, "
            f"got {sorted(actual_partial)}. A partial claim silently upgraded to "
            f"'full' overstates compliance evidence."
        )


def test_partial_controls_are_declared_in_manifest_not_generated_file() -> None:
    """The manifest is the source of truth; the export must not be hand-edited."""
    for slug, expected_partial in PARTIAL_COVERAGE_SOLUTIONS.items():
        m = _manifest(slug)
        declared = set(m.get("controls_partial") or [])
        assert declared == expected_partial, (
            f"{slug}/manifest.yaml: controls_partial must declare "
            f"{sorted(expected_partial)}, got {sorted(declared)}."
        )


def test_controls_partial_must_be_subset_of_controls() -> None:
    """An id absent from controls[] would be dropped silently -- fail instead."""
    framework_controls = {"1.1": 0, "2.2": 0}
    good = {
        "id": "sample-solution",
        "name": "Sample",
        "controls": ["1.1", "2.2"],
        "controls_partial": ["2.2"],
        "url": f"{bm.SITE_BASE}/solutions/sample-solution/",
    }
    assert not [
        e
        for e in bm.validate_manifests({"sample-solution": good}, framework_controls)
        if "controls_partial" in e
    ]

    bad = dict(good, controls_partial=["9.9"])
    errors = [
        e
        for e in bm.validate_manifests({"sample-solution": bad}, framework_controls)
        if "controls_partial" in e
    ]
    assert errors, "controls_partial entry outside controls[] must raise an error"
    assert "silently dropped" in errors[0]


def test_generated_export_matches_controls_covered_schema() -> None:
    """coverageScope/notes are not permitted -- the schema forbids extra keys."""
    schema = json.loads(
        (ROOT / "scripts" / "controls-covered.schema.json").read_text(encoding="utf-8")
    )
    from jsonschema import Draft202012Validator

    validator = Draft202012Validator(schema)
    for slug in PARTIAL_COVERAGE_SOLUTIONS:
        committed = json.loads(
            (ROOT / slug / "controls-covered.json").read_text(encoding="utf-8")
        )
        errors = sorted(validator.iter_errors(committed), key=lambda e: list(e.path))
        assert not errors, f"{slug}/controls-covered.json: {[e.message for e in errors]}"
