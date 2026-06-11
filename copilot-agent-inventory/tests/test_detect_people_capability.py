"""Unit tests for People-capability detection in copilot-agent-inventory.

Exercises the side-effect-free detection logic and the manifest-acquisition
adapters in ``scripts/detect_people_capability.py``:

  * ``detect_people_capability`` matches ``capabilities[].name == "People"`` as a
    CASE-SENSITIVE literal, independent of the manifest ``version`` (the const is
    unchanged across schema v1.5-v1.7), and captures the optional v1.7
    ``include_related_content`` sub-setting without letting it gate detection.
  * ``extract_capabilities`` / ``parse_manifest_version`` fail open on missing or
    malformed manifests (platform drift surfaces as "not detected", not an error).
  * ``build_people_feature_record`` emits Dataverse LOGICAL column names, the new
    ``People (Org Chart & Profile)`` feature type, and a ``Declared (Manifest)``
    confidence marker.
  * ``LocalAppPackageAdapter`` / ``SourceRepoAdapter`` read loose manifests and
    app-package zips; ``--id-map`` binds a manifest to a bot GUID (else the id is
    flagged provisional); ``FutureExportAdapter`` is an unimplemented seam.
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import detect_people_capability as dp  # noqa: E402


# ---------------------------------------------------------------------------
# detect_people_capability — the core signal
# ---------------------------------------------------------------------------

def test_detects_people_v17_with_include_related_content() -> None:
    manifest = {
        "$schema": "https://developer.microsoft.com/json-schemas/copilot/"
                   "declarative-agent/v1.7/schema.json",
        "version": "1.7",
        "capabilities": [
            {"name": "WebSearch"},
            {"name": "People", "include_related_content": True},
        ],
    }
    result = dp.detect_people_capability(manifest)
    assert result.detected is True
    assert result.include_related_content is True
    assert result.manifest_version == "1.7"
    assert result.raw_capability == {"name": "People", "include_related_content": True}


def test_detects_people_v15_without_include_related_content() -> None:
    manifest = {
        "$schema": "https://developer.microsoft.com/json-schemas/copilot/"
                   "declarative-agent/v1.5/schema.json",
        "capabilities": [{"name": "People"}],
    }
    result = dp.detect_people_capability(manifest)
    assert result.detected is True
    # Absent sub-setting must be None, never a fabricated default.
    assert result.include_related_content is None
    assert result.manifest_version == "1.5"


def test_people_match_is_case_sensitive() -> None:
    # The schema const is exactly "People"; any other casing must NOT match.
    for name in ("people", "PEOPLE", "PeoplE", "people "):
        manifest = {"capabilities": [{"name": name}]}
        assert dp.detect_people_capability(manifest).detected is False, name


def test_no_capabilities_array_is_not_detected() -> None:
    assert dp.detect_people_capability({}).detected is False
    assert dp.detect_people_capability({"capabilities": []}).detected is False


@pytest.mark.parametrize("bad_manifest", [
    None,
    "not-a-dict",
    {"capabilities": "WebSearch"},      # capabilities not a list
    {"capabilities": [None, 7, "x"]},   # entries not dicts
    {"capabilities": [{"noname": 1}]},  # capability missing name
])
def test_malformed_manifests_fail_open(bad_manifest: object) -> None:
    assert dp.detect_people_capability(bad_manifest).detected is False


def test_include_related_content_non_bool_is_ignored() -> None:
    manifest = {"capabilities": [{"name": "People", "include_related_content": "yes"}]}
    result = dp.detect_people_capability(manifest)
    assert result.detected is True
    assert result.include_related_content is None


def test_extract_capabilities_filters_non_dicts() -> None:
    caps = dp.extract_capabilities({"capabilities": [{"name": "People"}, None, 5, "x"]})
    assert caps == [{"name": "People"}]


def test_parse_manifest_version_from_schema_url_when_no_version_field() -> None:
    manifest = {"$schema": ".../declarative-agent/v1.6/schema.json"}
    version, schema_url = dp.parse_manifest_version(manifest)
    assert version == "1.6"
    assert schema_url.endswith("v1.6/schema.json")


# ---------------------------------------------------------------------------
# build_people_feature_record — Dataverse logical-name row
# ---------------------------------------------------------------------------

def test_feature_record_uses_logical_names_and_declared_confidence() -> None:
    detection = dp.PeopleDetection(
        detected=True, include_related_content=True, manifest_version="1.7",
        schema_url="schema-url", raw_capability={"name": "People"},
    )
    record = dp.build_people_feature_record(
        run_id="run-1", agent_id="bot-guid", agent_name="CoS Agent",
        environment_id="env-guid", detection=detection,
        source_label=dp.SOURCE_SOURCE_REPO, locator="appPackage/declarativeAgent.json",
        agent_id_provisional=False,
    )
    assert record["fsi_featuretype"] == "People (Org Chart & Profile)"
    assert record["fsi_detectionconfidence"] == "Declared (Manifest)"
    assert record["fsi_detectionsource"] == dp.SOURCE_SOURCE_REPO
    assert record["fsi_sourceobjectid"] == dp.PEOPLE_SOURCE_OBJECT_ID
    assert record["fsi_agentid"] == "bot-guid"
    # Every emitted key is a Dataverse logical name (fsi_ prefix, no inter-word _).
    for key in record:
        assert key.startswith("fsi_"), key
        assert "_" not in key[len("fsi_"):], key
    detail = json.loads(record["fsi_detectiondetail"])
    assert detail["includeRelatedContent"] is True
    assert detail["manifestVersion"] == "1.7"
    assert detail["agentRefProvisional"] is False


# ---------------------------------------------------------------------------
# Manifest loading: loose JSON, directory, app-package zip
# ---------------------------------------------------------------------------

def _write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload), encoding="utf-8")


def test_local_package_adapter_reads_loose_manifest(tmp_path: Path) -> None:
    da = tmp_path / "declarativeAgent.json"
    _write_json(da, {"version": "1.7", "name": "Loose Agent",
                     "capabilities": [{"name": "People"}]})
    adapter = dp.LocalAppPackageAdapter(tmp_path)
    run = dp.detect_over_adapter(adapter, "run-x")
    assert run.manifests_scanned == 1
    assert run.people_detected == 1
    assert run.features[0]["fsi_detectionsource"] == dp.SOURCE_LOCAL_PACKAGE
    # No id-map supplied -> id is provisional and surfaced in the count.
    assert run.provisional_ids == 1


def test_zip_app_package_detects_via_copilot_agents_node(tmp_path: Path) -> None:
    zip_path = tmp_path / "agent.zip"
    app_manifest = {
        "id": "11111111-1111-1111-1111-111111111111",
        "name": {"short": "Packaged Agent"},
        "copilotAgents": {"declarativeAgents": [{"id": "da1", "file": "declarativeAgent.json"}]},
    }
    da_manifest = {"version": "1.7", "capabilities": [{"name": "People"},
                                                      {"name": "WebSearch"}]}
    with zipfile.ZipFile(zip_path, "w") as archive:
        archive.writestr("manifest.json", json.dumps(app_manifest))
        archive.writestr("declarativeAgent.json", json.dumps(da_manifest))
        archive.writestr("color.png", b"not-json")
    records = list(dp.load_manifests_from_zip(zip_path))
    assert len(records) == 1
    assert records[0].agent_name == "Packaged Agent"
    assert dp.detect_people_capability(records[0].manifest).detected is True


def test_zip_without_app_manifest_falls_back_to_filename(tmp_path: Path) -> None:
    zip_path = tmp_path / "loose.zip"
    with zipfile.ZipFile(zip_path, "w") as archive:
        archive.writestr("declarativeAgent.json",
                         json.dumps({"capabilities": [{"name": "People"}]}))
    records = list(dp.load_manifests_from_zip(zip_path))
    assert len(records) == 1
    assert dp.detect_people_capability(records[0].manifest).detected is True


def test_id_map_resolves_provisional_to_bot_guid(tmp_path: Path) -> None:
    da = tmp_path / "declarativeAgent.json"
    _write_json(da, {"id": "da-77", "capabilities": [{"name": "People"}]})
    id_map = {"da-77": "99999999-9999-9999-9999-999999999999"}
    records = list(dp.load_manifest_from_json_file(da, id_map))
    assert records[0].agent_id == "99999999-9999-9999-9999-999999999999"
    assert records[0].agent_id_provisional is False


def test_source_repo_adapter_walks_tree(tmp_path: Path) -> None:
    pkg = tmp_path / "myagent" / "appPackage"
    pkg.mkdir(parents=True)
    _write_json(pkg / "declarativeAgent.json", {"capabilities": [{"name": "People"}]})
    # A non-manifest JSON file must be ignored (only declarativeAgent*.json counts).
    other = tmp_path / "other"
    other.mkdir(parents=True)
    _write_json(other / "notes.json", {"capabilities": [{"name": "People"}]})
    adapter = dp.SourceRepoAdapter(tmp_path)
    run = dp.detect_over_adapter(adapter, "run-r")
    assert run.manifests_scanned == 1
    assert run.people_detected == 1
    assert run.features[0]["fsi_detectionsource"] == dp.SOURCE_SOURCE_REPO


def test_future_export_adapter_is_unimplemented_seam() -> None:
    with pytest.raises(NotImplementedError):
        list(dp.FutureExportAdapter().iter_records())


def test_detect_over_adapter_ignores_agents_without_people(tmp_path: Path) -> None:
    _write_json(tmp_path / "a.declarativeAgent.json",
                {"capabilities": [{"name": "WebSearch"}]})
    _write_json(tmp_path / "b.declarativeAgent.json",
                {"capabilities": [{"name": "People"}]})
    run = dp.detect_over_adapter(dp.LocalAppPackageAdapter(tmp_path), "run-z")
    assert run.manifests_scanned == 2
    assert run.people_detected == 1
