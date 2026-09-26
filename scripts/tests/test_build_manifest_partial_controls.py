"""Regression tests for authored control-coverage fields in build-manifest.py.

`<slug>/controls-covered.json` is a mixed-contract artifact:

* generated identity/inventory fields come from `manifest.yaml`
* authored coverage rationale (`coverageScope`, per-control `notes`, and an
  already-declared `coverage: "partial"`) must survive full regeneration

The build script is loaded by path because its filename contains a hyphen (not
an importable module name), mirroring test_build_manifest_lab_images.py.
"""

from __future__ import annotations

import importlib.util
import json
import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]

AFFECTED_SOLUTIONS = (
    "action-confirmation-auditor",
    "agent-access-monitor",
    "agent-sharing-access-restriction-detector",
    "content-moderation-monitor",
    "copilot-agent-inventory",
    "file-upload-security",
    "generative-ai-config-auditor",
)

RICH_AUTHORED_SOLUTIONS: dict[str, set[str]] = {
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


def _artifact(slug: str) -> dict:
    return json.loads((ROOT / slug / "controls-covered.json").read_text(encoding="utf-8"))


def _control_by_id(payload: dict) -> dict[str, dict]:
    return {control["id"]: control for control in payload["controls"]}


def _minimal_run_outputs(tmp_path: Path, artifact: str) -> dict[Path, str]:
    return {
        tmp_path / "solutions.json": "solutions\n",
        tmp_path / "sample" / "controls-covered.json": artifact,
        tmp_path / "site-docs" / "solutions" / "index.md": "catalog\n",
        tmp_path / "site-docs" / "solutions" / "sample" / "index.md": "detail\n",
        tmp_path / "site-docs" / "reference" / "control-mapping.md": "mapping\n",
    }


def _patch_minimal_run(monkeypatch, tmp_path: Path, artifact: str) -> dict[Path, str]:
    manifest = {
        "id": "sample",
        "name": "Sample",
        "description": "Sample solution",
        "version": "1.0.0",
        "status": "live",
        "domain": "agent-config",
        "tier": "1",
        "controls": ["1.1"],
        "url": f"{bm.SITE_BASE}/solutions/sample/",
        "prerequisites": {"admin": "Admin access"},
        "verification": "Verify sample output.",
        "zones": ["enterprise"],
    }
    expected = _minimal_run_outputs(tmp_path, artifact)

    monkeypatch.setattr(bm, "ROOT", tmp_path)
    monkeypatch.setattr(bm, "SOLUTIONS_JSON", tmp_path / "solutions.json")
    monkeypatch.setattr(bm, "README", tmp_path / "README.md")
    monkeypatch.setattr(bm, "SITE_DOCS", tmp_path / "site-docs")
    monkeypatch.setattr(bm, "SOLUTIONS_OUT", tmp_path / "site-docs" / "solutions")
    monkeypatch.setattr(
        bm,
        "SITE_CATALOG",
        tmp_path / "site-docs" / "solutions" / "index.md",
    )
    monkeypatch.setattr(
        bm,
        "CONTROL_MAPPING",
        tmp_path / "site-docs" / "reference" / "control-mapping.md",
    )
    monkeypatch.setattr(bm, "SITE_INDEX", tmp_path / "site-docs" / "index.md")
    monkeypatch.setattr(bm, "DEPLOYMENT_GUIDE", tmp_path / "DEPLOYMENT-GUIDE.md")
    monkeypatch.setattr(bm, "load_framework_controls", lambda: {"1.1": 1})
    monkeypatch.setattr(bm, "load_framework_control_titles", lambda: {"1.1": "One"})
    monkeypatch.setattr(bm, "load_manifests", lambda: {"sample": manifest})
    monkeypatch.setattr(bm, "validate_solution_readme_headers", lambda manifests: [])
    monkeypatch.setattr(bm, "load_lab_evidence", lambda slug: None)
    monkeypatch.setattr(bm, "copy_sub_docs", lambda slug, write_files=False: ([], {}))
    monkeypatch.setattr(bm, "sync_solution_readme_controls", lambda slug, m, titles: None)
    monkeypatch.setattr(
        bm,
        "copy_root_docs",
        lambda write_files=False, slugs=None, overrides=None: {},
    )
    monkeypatch.setattr(bm, "emit_solutions_json", lambda manifests: "solutions\n")
    monkeypatch.setattr(bm, "emit_controls_covered_json", lambda slug, m: artifact)
    monkeypatch.setattr(bm, "emit_site_catalog", lambda manifests: "catalog\n")
    monkeypatch.setattr(
        bm,
        "emit_solution_detail",
        lambda slug, m, sub_docs: "detail\n",
    )
    monkeypatch.setattr(
        bm,
        "emit_control_mapping",
        lambda manifests, pillars, titles: "mapping\n",
    )
    return expected


def _patch_tracked_outputs(monkeypatch, tmp_path: Path, paths: list[Path]) -> None:
    monkeypatch.setattr(
        bm,
        "load_tracked_relative_paths",
        lambda: {path.relative_to(tmp_path).as_posix() for path in paths},
    )


def test_full_build_preserves_authored_fields_for_all_affected_solutions() -> None:
    """A full regeneration must retain each solution's authored coverage fields."""
    for slug in AFFECTED_SOLUTIONS:
        committed = _artifact(slug)
        generated = json.loads(bm.emit_controls_covered_json(slug, _manifest(slug)))

        assert generated["solutionVersion"] == _manifest(slug)["version"]
        assert generated["controls"] == committed["controls"]

        if slug not in RICH_AUTHORED_SOLUTIONS:
            assert "coverageScope" not in generated
            assert all("notes" not in c for c in generated["controls"])
            continue

        expected_partial = RICH_AUTHORED_SOLUTIONS[slug]
        committed_controls = _control_by_id(committed)
        generated_controls = _control_by_id(generated)

        assert generated["coverageScope"] == committed["coverageScope"]
        for control_id in expected_partial:
            assert generated_controls[control_id]["coverage"] == "partial"
            assert generated_controls[control_id]["notes"] == committed_controls[
                control_id
            ]["notes"]


def test_existing_partial_and_notes_survive_even_without_manifest_controls_partial(
    tmp_path,
    monkeypatch,
) -> None:
    """A hand-authored partial claim must not be upgraded to full on regeneration."""
    slug = "sample-solution"
    base = tmp_path / slug
    base.mkdir()
    (base / "controls-covered.json").write_text(
        json.dumps(
            {
                "schemaVersion": "1.0.0",
                "generatedBy": "scripts/build-manifest.py",
                "solutionId": slug,
                "solutionName": "Old name",
                "solutionVersion": "0.1.0",
                "status": "preview",
                "coverageScope": {
                    "summary": "Only live tenant path was validated.",
                    "reference": "LAB-VALIDATION.md#scope",
                    "gaps": ["Synthetic fixtures do not prove Graph pagination."],
                },
                "controls": [
                    {
                        "id": "1.1",
                        "coverage": "partial",
                        "notes": "Live evidence covers the happy path only.",
                    }
                ],
                "controlCount": 1,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(bm, "ROOT", tmp_path)

    generated = json.loads(
        bm.emit_controls_covered_json(
            slug,
            {
                "id": slug,
                "name": "Sample Solution",
                "version": "1.0.0",
                "status": "live",
                "controls": ["1.1"],
            },
        )
    )

    assert generated["solutionName"] == "Sample Solution"
    assert generated["solutionVersion"] == "1.0.0"
    assert generated["status"] == "live"
    assert generated["coverageScope"]["reference"] == "LAB-VALIDATION.md#scope"
    assert generated["controls"] == [
        {
            "id": "1.1",
            "coverage": "partial",
            "notes": "Live evidence covers the happy path only.",
        }
    ]


def test_controls_covered_schema_allows_authored_scope_and_notes() -> None:
    """The schema must document the mixed generated/authored artifact contract."""
    schema = json.loads(
        (ROOT / "scripts" / "controls-covered.schema.json").read_text(encoding="utf-8")
    )
    from jsonschema import Draft202012Validator

    validator = Draft202012Validator(schema)
    for slug in RICH_AUTHORED_SOLUTIONS:
        errors = sorted(
            validator.iter_errors(_artifact(slug)),
            key=lambda e: list(e.path),
        )
        assert not errors, f"{slug}/controls-covered.json: {[e.message for e in errors]}"


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


def test_check_mode_fails_on_deliberately_stale_committed_artifact(
    tmp_path,
    monkeypatch,
) -> None:
    expected = _patch_minimal_run(monkeypatch, tmp_path, "fresh\n")
    for path, content in expected.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("stale\n" if path.name == "controls-covered.json" else content)

    assert bm.run(check=True) == 1


def test_tracked_only_check_passes_when_gitignored_site_docs_are_absent(
    tmp_path,
    monkeypatch,
) -> None:
    expected = _patch_minimal_run(monkeypatch, tmp_path, "fresh\n")
    tracked_outputs = [
        tmp_path / "solutions.json",
        tmp_path / "sample" / "controls-covered.json",
    ]
    _patch_tracked_outputs(monkeypatch, tmp_path, tracked_outputs)
    for path in tracked_outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected[path], encoding="utf-8")

    assert bm.run(check=True, tracked_only=True) == 0


def test_tracked_only_check_fails_on_stale_committed_artifact(
    tmp_path,
    monkeypatch,
) -> None:
    expected = _patch_minimal_run(monkeypatch, tmp_path, "fresh\n")
    tracked_outputs = [
        tmp_path / "solutions.json",
        tmp_path / "sample" / "controls-covered.json",
    ]
    _patch_tracked_outputs(monkeypatch, tmp_path, tracked_outputs)
    for path in tracked_outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        content = "stale\n" if path.name == "controls-covered.json" else expected[path]
        path.write_text(content, encoding="utf-8")

    assert bm.run(check=True, tracked_only=True) == 1


def test_check_mode_passes_on_clean_committed_artifacts(tmp_path, monkeypatch) -> None:
    expected = _patch_minimal_run(monkeypatch, tmp_path, "fresh\n")
    for path, content in expected.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    assert bm.run(check=True) == 0


def test_manifest_check_workflow_gates_committed_tree_before_regenerating() -> None:
    workflow = (ROOT / ".github" / "workflows" / "manifest-check.yml").read_text(
        encoding="utf-8"
    )
    check_pos = workflow.index(
        "python scripts/build-manifest.py --check --tracked-only"
    )
    generate_pos = re.search(
        r"(?m)^\s*run:\s+python scripts/build-manifest\.py\s*$", workflow
    )
    assert generate_pos is not None
    assert check_pos < generate_pos.start()
