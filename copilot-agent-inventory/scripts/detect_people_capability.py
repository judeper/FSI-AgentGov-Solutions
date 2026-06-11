#!/usr/bin/env python3
"""Detect the declarative-agent **People** capability from agent manifests.

The Agent Builder toggle *"Reference org chart and profile info"* maps to the
declarative-agent manifest capability ``{ "name": "People" }`` inside
``declarativeAgent.json`` (manifest schema v1.5-v1.7). This capability is NOT a
Copilot Studio ``botcomponent`` and is NOT returned by any public API for a
*deployed* agent (verified in GATE0a). Capability-level detection therefore
requires the source manifest itself, obtained from the agent app package or from
source control. This module:

  * Parses a ``declarativeAgent.json`` (or an app-package ``.zip``, or a
    directory of packages) and extracts ``capabilities[]``.
  * Detects ``name == "People"`` as a **case-sensitive literal**, independent of
    the manifest ``version`` (the const is unchanged across v1.5-v1.7).
  * Captures the optional v1.7 ``include_related_content`` sub-setting.
  * Emits one ``fsi_caiagentfeature`` row (logical column names) per detected
    agent, using the feature type ``People (Org Chart & Profile)``, a
    provenance marker (``fsi_detectionsource``), and a confidence marker
    (``fsi_detectionconfidence = "Declared (Manifest)"``).

**Declared is not effective.** A manifest capability is *authored/available*;
the v1.7 ``user_overrides`` mechanism lets a consuming user remove a capability
at runtime, and tenant policy may gate grounding. For a governance inventory of
what an agent is *built with*, the manifest ``capabilities[].name == "People"``
signal is correct; per-user effective state is a separate, non-queryable concern.

**Agent-id linkage caveat.** A declarative-agent manifest does not contain the
Dataverse ``bot`` GUID that keys ``fsi_copilotagent``. When no ``--id-map`` is
supplied, the resolved ``fsi_agentid`` is *provisional* (the manifest/app id) and
is flagged as such so the orchestrator can reconcile it before the row joins the
canonical store or feeds Copilot Billing Governance (CBG).

Acquisition-adapter seam: ``ManifestAcquisitionAdapter`` defines the contract;
``LocalAppPackageAdapter`` and ``SourceRepoAdapter`` are implemented now, and
``FutureExportAdapter`` is a clearly-marked seam for a future scalable export
path (a sibling spike is resolving whether a supported one exists).

Usage:
  # Dry run over a local directory of app packages (logs planned work)
  python detect_people_capability.py --source local-package --path ./packages --dry-run

  # Scan a source/CI repo tree and write the detection artifact
  python detect_people_capability.py --source source-repo --path ../my-agent-repo \
      --id-map ./agent-id-map.json --environment-id <envGuid> --output people.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import zipfile
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Optional

logger = logging.getLogger("detect_people_capability")

# =============================================================================
# Detection constants (verified against R1 / GATE0a)
# =============================================================================

# Case-sensitive const from the declarative-agent manifest JSON Schema; the
# value is unchanged across schema v1.5, v1.6 and v1.7.
PEOPLE_CAPABILITY_NAME = "People"

# fsi_cai_featuretype label for the People capability (see create_cai_dataverse_schema.py).
PEOPLE_FEATURE_TYPE = "People (Org Chart & Profile)"

# fsi_cai_detectionconfidence label: manifest capabilities are declared/available.
CONFIDENCE_DECLARED = "Declared (Manifest)"

# fsi_cai_detectionsource labels - must match the option-set labels exactly.
SOURCE_LOCAL_PACKAGE = "Declarative Manifest (Local App Package)"
SOURCE_SOURCE_REPO = "Declarative Manifest (Source/CI Repo)"
SOURCE_EXPORT_FUTURE = "Declarative Manifest (Export Adapter - Future)"

# The manifest navigation path the feature was matched through (mirrors the
# botcomponent relationship-name convention used by discover_agents.py).
PEOPLE_RELATIONSHIP = "declarativeAgent.capabilities"

# A stable per-agent source-object id so re-detection upserts one People row
# (the fsi_caiagentfeature alternate key is fsi_agentid + fsi_sourceobjectid).
PEOPLE_SOURCE_OBJECT_ID = "capability:People"


def _people_source_object_id(locator: str, agent_id_provisional: bool) -> str:
    """Return the fsi_sourceobjectid for a People row, salting provisional rows.

    The fsi_caiagentfeature alternate key is (fsi_agentid, fsi_sourceobjectid).
    For a resolved (non-provisional) agent the constant ``capability:People`` is
    correct: re-detection upserts the single People row for that agent.

    For a PROVISIONAL agent the id falls back to the manifest stem, which is the
    SAME literal (``declarativeAgent``) for every Toolkit
    ``appPackage/declarativeAgent.json``. With a constant source-object id two
    distinct provisional manifests would collapse onto one alternate key and one
    upsert would silently overwrite the other. Salting the source-object id with a
    stable hash of the manifest locator keeps distinct provisional manifests on
    distinct alternate keys while remaining deterministic (idempotent re-scans).
    """
    if not agent_id_provisional:
        return PEOPLE_SOURCE_OBJECT_ID
    digest = hashlib.sha1(str(locator).encode("utf-8")).hexdigest()[:12]
    return f"{PEOPLE_SOURCE_OBJECT_ID}:{digest}"

# Conventional manifest filenames inside an app package / repo (case-insensitive).
APP_MANIFEST_NAMES = {"manifest.json"}
DECLARATIVE_AGENT_HINT = "declarativeagent"  # matches declarativeAgent*.json


# =============================================================================
# Pure detection helpers (side-effect free; unit-tested)
# =============================================================================


@dataclass
class PeopleDetection:
    """Result of testing one manifest for the People capability."""

    detected: bool
    include_related_content: Optional[bool] = None
    manifest_version: Optional[str] = None
    schema_url: Optional[str] = None
    raw_capability: Optional[dict] = None


def extract_capabilities(manifest: Any) -> list[dict]:
    """Return the manifest ``capabilities[]`` as a list of dicts (fail-open).

    Tolerates a missing array, a non-list value, or non-dict entries - platform
    drift surfaces as "no capability detected" rather than an exception.
    """
    if not isinstance(manifest, dict):
        logger.warning("Manifest is not a JSON object (fail-open): %r", type(manifest))
        return []
    capabilities = manifest.get("capabilities")
    if capabilities is None:
        return []
    if not isinstance(capabilities, list):
        logger.warning("capabilities is not a list (fail-open): %r", type(capabilities))
        return []
    return [c for c in capabilities if isinstance(c, dict)]


def parse_manifest_version(manifest: Any) -> tuple[Optional[str], Optional[str]]:
    """Best-effort (version, schema_url) extraction from a declarative manifest.

    Reads the top-level ``version`` field and/or parses the ``$schema`` URL
    (e.g. ``.../declarative-agent/v1.7/schema.json`` -> ``1.7``). Detection does
    NOT depend on either value; they are captured for provenance only.
    """
    if not isinstance(manifest, dict):
        return (None, None)
    version = manifest.get("version")
    version = str(version) if version is not None else None
    schema_url = manifest.get("$schema")
    schema_url = str(schema_url) if schema_url is not None else None
    if version is None and schema_url:
        # Pull the v<major>.<minor> token out of the schema URL path.
        for part in schema_url.replace("\\", "/").split("/"):
            token = part.lower()
            if token.startswith("v") and any(ch.isdigit() for ch in token):
                version = token[1:]
                break
    return (version, schema_url)


def detect_people_capability(manifest: Any) -> PeopleDetection:
    """Test a parsed declarative-agent manifest for the People capability.

    Matches ``capabilities[].name == "People"`` as a case-sensitive literal so a
    lowercase ``"people"`` (or any other casing) does NOT match. Returns the
    first matching capability object; the optional v1.7 ``include_related_content``
    boolean is captured but does NOT gate detection (it is a sub-setting).
    """
    version, schema_url = parse_manifest_version(manifest)
    for capability in extract_capabilities(manifest):
        if capability.get("name") == PEOPLE_CAPABILITY_NAME:
            irc = capability.get("include_related_content")
            return PeopleDetection(
                detected=True,
                include_related_content=irc if isinstance(irc, bool) else None,
                manifest_version=version,
                schema_url=schema_url,
                raw_capability=capability,
            )
    return PeopleDetection(detected=False, manifest_version=version, schema_url=schema_url)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def build_people_feature_record(
    run_id: str,
    agent_id: str,
    agent_name: Optional[str],
    environment_id: Optional[str],
    detection: PeopleDetection,
    source_label: str,
    locator: str,
    agent_id_provisional: bool,
) -> dict:
    """Build one ``fsi_caiagentfeature`` row for a detected People capability.

    Field names are Dataverse LOGICAL names. Picklist fields carry the option-set
    LABEL; the writer resolves the label to the integer value at upsert time
    (the established CAI convention - see templates/agent-record.sample.json).
    """
    detail = {
        "source": source_label,
        "locator": locator,
        "capabilityName": PEOPLE_CAPABILITY_NAME,
        "manifestVersion": detection.manifest_version,
        "schema": detection.schema_url,
        "includeRelatedContent": detection.include_related_content,
        "agentRefProvisional": agent_id_provisional,
        "detectedAt": _utc_now_iso(),
    }
    display = agent_name or agent_id
    return {
        "fsi_name": f"{PEOPLE_FEATURE_TYPE}: {display}",
        "fsi_agentid": agent_id,
        "fsi_environmentid": environment_id,
        "fsi_featuretype": PEOPLE_FEATURE_TYPE,
        "fsi_componenttype": None,
        "fsi_componentversion": "Not Applicable",
        "fsi_sourceobjectid": _people_source_object_id(locator, agent_id_provisional),
        "fsi_sourceobjectname": PEOPLE_CAPABILITY_NAME,
        "fsi_relationshipname": PEOPLE_RELATIONSHIP,
        "fsi_detectionsource": source_label,
        "fsi_detectionconfidence": CONFIDENCE_DECLARED,
        "fsi_detectiondetail": json.dumps(detail),
        "fsi_agentrefprovisional": agent_id_provisional,
        "fsi_isenabled": True,
        "fsi_lastscannedat": _utc_now_iso(),
        "fsi_runid": run_id,
    }


# =============================================================================
# Manifest loading (json file / app-package zip / directory)
# =============================================================================


@dataclass
class ManifestRecord:
    """One declarative-agent manifest located by an acquisition adapter."""

    agent_id: str
    agent_name: Optional[str]
    locator: str
    manifest: dict
    app_manifest: Optional[dict] = None
    agent_id_provisional: bool = True


def _declarative_files_from_app_manifest(app_manifest: dict) -> list[str]:
    """Return declarativeAgent.json file refs from an app manifest's copilotAgents node."""
    refs: list[str] = []
    copilot_agents = app_manifest.get("copilotAgents")
    if isinstance(copilot_agents, dict):
        for entry in copilot_agents.get("declarativeAgents", []) or []:
            if isinstance(entry, dict) and entry.get("file"):
                refs.append(str(entry["file"]))
    return refs


def _resolve_agent_identity(
    manifest: dict,
    app_manifest: Optional[dict],
    locator: str,
    id_map: Optional[dict[str, str]],
) -> tuple[str, Optional[str], bool]:
    """Resolve (agent_id, agent_name, provisional) for one manifest.

    Prefers an explicit ``--id-map`` entry keyed by app id, declarative-agent id,
    or the locator's file stem (this is how a caller binds a manifest to the
    Dataverse bot GUID). With no mapping, the agent id is the best available
    manifest identifier and is flagged provisional.
    """
    app_id = str(app_manifest.get("id")) if isinstance(app_manifest, dict) and app_manifest.get("id") else None
    da_id = str(manifest.get("id")) if manifest.get("id") else None
    stem = Path(locator.split("::")[-1]).stem
    agent_name = (
        manifest.get("name")
        or (app_manifest.get("name", {}).get("short") if isinstance(app_manifest, dict)
            and isinstance(app_manifest.get("name"), dict) else None)
        or (app_manifest.get("name") if isinstance(app_manifest, dict)
            and isinstance(app_manifest.get("name"), str) else None)
    )
    id_map = id_map or {}
    for candidate in (app_id, da_id, stem):
        if candidate and candidate in id_map:
            return (id_map[candidate], agent_name, False)
    provisional_id = da_id or app_id or stem
    return (provisional_id, agent_name, True)


def _read_json_bytes(data: bytes, locator: str) -> Optional[dict]:
    try:
        parsed = json.loads(data.decode("utf-8-sig"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        logger.warning("Could not parse JSON at %s (fail-open): %s", locator, exc)
        return None
    if not isinstance(parsed, dict):
        logger.warning("JSON at %s is not an object (fail-open)", locator)
        return None
    return parsed


def load_manifests_from_zip(
    zip_path: Path, id_map: Optional[dict[str, str]] = None,
    failures: Optional[list] = None,
) -> Iterator[ManifestRecord]:
    """Yield ManifestRecords from a Microsoft 365 app-package ``.zip``.

    Reads the app ``manifest.json`` to find the ``copilotAgents`` declarative
    agent file refs; falls back to any ``declarativeAgent*.json`` in the package
    when the app manifest is absent or does not reference one.

    A manifest that cannot be opened (``BadZipFile`` / ``OSError``) or whose
    declarative-agent JSON cannot be parsed (the ``None`` branch) is appended to
    ``failures`` (when provided) so a corrupt fleet is surfaced as Partial rather
    than read as "0 detections, all green".
    """
    try:
        with zipfile.ZipFile(zip_path) as archive:
            names = archive.namelist()
            app_manifest: Optional[dict] = None
            app_manifest_name = next(
                (n for n in names if Path(n).name.lower() in APP_MANIFEST_NAMES), None
            )
            if app_manifest_name:
                app_manifest = _read_json_bytes(
                    archive.read(app_manifest_name), f"{zip_path}::{app_manifest_name}"
                )

            da_files: list[str] = []
            if app_manifest:
                for ref in _declarative_files_from_app_manifest(app_manifest):
                    match = next((n for n in names if Path(n).name == Path(ref).name), None)
                    if match:
                        da_files.append(match)
            if not da_files:
                da_files = [
                    n for n in names
                    if DECLARATIVE_AGENT_HINT in Path(n).name.lower()
                    and n.lower().endswith(".json")
                ]
            if not da_files:
                logger.warning("No declarativeAgent.json found in package %s", zip_path)
                return

            for da_name in da_files:
                locator = f"{zip_path}::{da_name}"
                manifest = _read_json_bytes(archive.read(da_name), locator)
                if manifest is None:
                    if failures is not None:
                        failures.append(locator)
                    continue
                agent_id, agent_name, provisional = _resolve_agent_identity(
                    manifest, app_manifest, locator, id_map
                )
                yield ManifestRecord(
                    agent_id=agent_id, agent_name=agent_name, locator=locator,
                    manifest=manifest, app_manifest=app_manifest,
                    agent_id_provisional=provisional,
                )
    except (zipfile.BadZipFile, OSError) as exc:
        logger.warning("Could not open app package %s (fail-open): %s", zip_path, exc)
        if failures is not None:
            failures.append(str(zip_path))


def load_manifest_from_json_file(
    json_path: Path, id_map: Optional[dict[str, str]] = None,
    failures: Optional[list] = None,
) -> Iterator[ManifestRecord]:
    """Yield a single ManifestRecord from a loose ``declarativeAgent.json`` file.

    An unreadable file (``OSError``) or unparseable JSON (the ``None`` branch) is
    appended to ``failures`` (when provided) so a corrupt manifest is surfaced as
    Partial rather than silently skipped.
    """
    try:
        manifest = _read_json_bytes(json_path.read_bytes(), str(json_path))
    except OSError as exc:
        logger.warning("Could not read manifest %s (fail-open): %s", json_path, exc)
        if failures is not None:
            failures.append(str(json_path))
        return
    if manifest is None:
        if failures is not None:
            failures.append(str(json_path))
        return
    # An adjacent app manifest (same directory) helps resolve identity if present.
    app_manifest: Optional[dict] = None
    sibling = json_path.parent / "manifest.json"
    if sibling.is_file() and sibling != json_path:
        try:
            app_manifest = _read_json_bytes(sibling.read_bytes(), str(sibling))
        except OSError:
            app_manifest = None
    agent_id, agent_name, provisional = _resolve_agent_identity(
        manifest, app_manifest, str(json_path), id_map
    )
    yield ManifestRecord(
        agent_id=agent_id, agent_name=agent_name, locator=str(json_path),
        manifest=manifest, app_manifest=app_manifest, agent_id_provisional=provisional,
    )


def _is_declarative_agent_json(path: Path) -> bool:
    return (
        path.suffix.lower() == ".json"
        and DECLARATIVE_AGENT_HINT in path.name.lower()
    )


def load_manifests_from_dir(
    root: Path, id_map: Optional[dict[str, str]] = None,
    failures: Optional[list] = None,
) -> Iterator[ManifestRecord]:
    """Recursively yield ManifestRecords from app-package zips and loose manifests."""
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix.lower() == ".zip":
            yield from load_manifests_from_zip(path, id_map, failures)
        elif _is_declarative_agent_json(path):
            yield from load_manifest_from_json_file(path, id_map, failures)


def load_manifests_from_path(
    path: Path, id_map: Optional[dict[str, str]] = None,
    failures: Optional[list] = None,
) -> Iterator[ManifestRecord]:
    """Dispatch on a path that may be a directory, an app-package zip, or a JSON file."""
    if path.is_dir():
        yield from load_manifests_from_dir(path, id_map, failures)
    elif path.suffix.lower() == ".zip":
        yield from load_manifests_from_zip(path, id_map, failures)
    elif path.suffix.lower() == ".json":
        yield from load_manifest_from_json_file(path, id_map, failures)
    else:
        logger.warning("Unsupported manifest source path: %s", path)


# =============================================================================
# Acquisition-adapter seam
# =============================================================================


class ManifestAcquisitionAdapter(ABC):
    """Contract for sourcing declarative-agent manifests for People detection.

    The detection logic is manifest-source-agnostic: any adapter that can yield
    ManifestRecords plugs in here. Two adapters are implemented now; a future
    scalable export adapter is reserved as a clearly-marked seam.
    """

    #: fsi_cai_detectionsource label stamped onto rows from this adapter.
    provenance_label: str = SOURCE_EXPORT_FUTURE

    @abstractmethod
    def iter_records(self) -> Iterator[ManifestRecord]:
        """Yield ManifestRecords from the underlying source."""
        raise NotImplementedError


class LocalAppPackageAdapter(ManifestAcquisitionAdapter):
    """Adapter (a): a local directory of deployed app packages (and/or manifests).

    ``root`` may be a directory of ``.zip`` app packages, a single ``.zip``, or a
    loose ``declarativeAgent.json``. Suitable for packages exported/downloaded
    from Teams Admin Center or staged on disk.
    """

    provenance_label = SOURCE_LOCAL_PACKAGE

    def __init__(self, root: Path, id_map: Optional[dict[str, str]] = None) -> None:
        self.root = root
        self.id_map = id_map
        #: Locators of manifests that could not be opened/parsed during the most
        #: recent iter_records() pass (drives the run's manifests_failed counter).
        self.failures: list[str] = []

    def iter_records(self) -> Iterator[ManifestRecord]:
        self.failures = []
        yield from load_manifests_from_path(self.root, self.id_map, self.failures)


class SourceRepoAdapter(ManifestAcquisitionAdapter):
    """Adapter (b): a source/CI repo tree (Microsoft 365 Agents Toolkit layout).

    Walks the tree for ``appPackage/declarativeAgent.json`` (and any
    ``declarativeAgent*.json``) checked into source control or produced as a CI
    build artifact - the highest-fidelity source for org-built LOB agents.
    """

    provenance_label = SOURCE_SOURCE_REPO

    def __init__(self, root: Path, id_map: Optional[dict[str, str]] = None) -> None:
        self.root = root
        self.id_map = id_map
        #: Locators of manifests that could not be opened/parsed during the most
        #: recent iter_records() pass (drives the run's manifests_failed counter).
        self.failures: list[str] = []

    def iter_records(self) -> Iterator[ManifestRecord]:
        self.failures = []
        yield from load_manifests_from_dir(self.root, self.id_map, self.failures)


class FutureExportAdapter(ManifestAcquisitionAdapter):
    """SEAM (reserved): a future scalable manifest-export source.

    GATE0a found no supported public API that returns the parsed
    ``capabilities[]`` for a *deployed* agent at fleet scale. A sibling spike is
    resolving whether a scalable export (e.g., a future Microsoft Agent 365
    inventory surface) exists. This class is the integration point; do NOT block
    on it. Wire the real source in here and set ``provenance_label =
    SOURCE_EXPORT_FUTURE`` once a supported path is confirmed.
    """

    provenance_label = SOURCE_EXPORT_FUTURE

    def iter_records(self) -> Iterator[ManifestRecord]:
        raise NotImplementedError(
            "No supported scalable manifest-export adapter exists yet (GATE0a). "
            "Use LocalAppPackageAdapter or SourceRepoAdapter; a sibling spike is "
            "resolving the scalable export path."
        )


ADAPTERS: dict[str, type[ManifestAcquisitionAdapter]] = {
    "local-package": LocalAppPackageAdapter,
    "source-repo": SourceRepoAdapter,
}


# =============================================================================
# Detection over an adapter
# =============================================================================


@dataclass
class DetectionRun:
    """Aggregate outcome of a People-capability detection pass."""

    run_id: str
    features: list[dict] = field(default_factory=list)
    agents: list[dict] = field(default_factory=list)
    manifests_scanned: int = 0
    people_detected: int = 0
    provisional_ids: int = 0
    manifests_failed: int = 0

    def summary(self, source_label: str) -> dict:
        # A non-zero manifests_failed means the fleet was only partially read, so
        # the scan must NOT be reported as a clean/complete pass: a corrupt or
        # unzippable manifest is invisible to detection and would otherwise read
        # as "0 detections, all green".
        return {
            "runId": self.run_id,
            "detectionSource": source_label,
            "manifestsScanned": self.manifests_scanned,
            "peopleDetected": self.people_detected,
            "provisionalAgentIds": self.provisional_ids,
            "manifestsFailed": self.manifests_failed,
            "scanStatus": "Partial" if self.manifests_failed else "Complete",
        }


def detect_over_adapter(
    adapter: ManifestAcquisitionAdapter,
    run_id: str,
    environment_id: Optional[str] = None,
) -> DetectionRun:
    """Run People detection over every manifest an adapter yields."""
    run = DetectionRun(run_id=run_id)
    for record in adapter.iter_records():
        run.manifests_scanned += 1
        detection = detect_people_capability(record.manifest)
        if not detection.detected:
            continue
        run.people_detected += 1
        if record.agent_id_provisional:
            run.provisional_ids += 1
            logger.warning(
                "People detected for %s but agent id is PROVISIONAL (%s); supply "
                "--id-map to bind it to the Dataverse bot GUID before joining CAI/CBG.",
                record.agent_name or record.locator, record.agent_id,
            )
        feature = build_people_feature_record(
            run_id=run_id,
            agent_id=record.agent_id,
            agent_name=record.agent_name,
            environment_id=environment_id,
            detection=detection,
            source_label=adapter.provenance_label,
            locator=record.locator,
            agent_id_provisional=record.agent_id_provisional,
        )
        run.features.append(feature)
        run.agents.append({
            "agentId": record.agent_id,
            "agentName": record.agent_name,
            "agentIdProvisional": record.agent_id_provisional,
            "locator": record.locator,
            "manifestVersion": detection.manifest_version,
            "includeRelatedContent": detection.include_related_content,
        })
    # Manifests that failed to open/parse are tracked on the adapter (the
    # iter_records() seam stays argument-free); fold the count into the run so the
    # summary/artifact can surface a Partial scan.
    failures = getattr(adapter, "failures", [])
    run.manifests_failed = len(failures)
    if failures:
        logger.warning(
            "%d manifest(s) could not be read during this scan and were skipped; "
            "the scan is Partial, not a clean pass: %s",
            len(failures), ", ".join(str(f) for f in failures[:10]),
        )
    return run


def _load_id_map(path: Optional[str]) -> Optional[dict[str, str]]:
    if not path:
        return None
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Could not read --id-map {path}: {exc}")
    if not isinstance(data, dict):
        raise SystemExit("--id-map must be a JSON object mapping manifest/app id -> bot GUID")
    return {str(k): str(v) for k, v in data.items()}


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    """CLI entry point for People-capability detection."""
    parser = argparse.ArgumentParser(
        description="Detect the declarative-agent People capability from manifests",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run over a directory of app packages\n"
            "  python detect_people_capability.py --source local-package "
            "--path ./packages --dry-run\n\n"
            "  # Scan a source repo and write the detection artifact\n"
            "  python detect_people_capability.py --source source-repo "
            "--path ../agent-repo --id-map ids.json --output people.json\n"
        ),
    )
    parser.add_argument("--source", choices=sorted(ADAPTERS), default="local-package",
                        help="Manifest-acquisition adapter to use")
    parser.add_argument("--path", required=True,
                        help="Path to a directory, an app-package .zip, or a declarativeAgent.json")
    parser.add_argument("--id-map", default=None,
                        help="JSON map of app/declarative-agent id (or file stem) -> Dataverse bot GUID")
    parser.add_argument("--environment-id", default=None,
                        help="Power Platform environment GUID to stamp on emitted feature rows")
    parser.add_argument("--run-id", default=None,
                        help="Scan run correlation id (default: generated)")
    parser.add_argument("--output", default=None,
                        help="Write the detection artifact JSON to this path")
    parser.add_argument("--dry-run", action="store_true",
                        help="Log the planned adapter and source path without scanning")
    parser.add_argument("--log-level", default="INFO",
                        help="Logging level (DEBUG, INFO, WARNING, ERROR)")
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, str(args.log_level).upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    run_id = args.run_id or f"cai-people-{int(datetime.now(timezone.utc).timestamp())}"
    adapter_cls = ADAPTERS[args.source]

    if args.dry_run:
        logger.info("[DRY RUN] would scan %s via %s (provenance: %s)",
                    args.path, adapter_cls.__name__, adapter_cls.provenance_label)
        return

    id_map = _load_id_map(args.id_map)
    adapter = adapter_cls(Path(args.path), id_map=id_map)
    run = detect_over_adapter(adapter, run_id, environment_id=args.environment_id)

    artifact = {
        "schemaVersion": "0.2.0-preview",
        "summary": run.summary(adapter.provenance_label),
        "agents": run.agents,
        "features": run.features,
    }
    logger.info("People detection summary: %s", json.dumps(run.summary(adapter.provenance_label)))
    if run.provisional_ids:
        logger.warning("%d detected agent(s) have PROVISIONAL ids - reconcile via --id-map.",
                       run.provisional_ids)
    if run.manifests_failed:
        logger.warning("%d manifest(s) could not be read; scan is PARTIAL, not a clean pass.",
                       run.manifests_failed)

    if args.output:
        Path(args.output).write_text(json.dumps(artifact, indent=2), encoding="utf-8")
        logger.info("Wrote detection artifact to %s", args.output)
    else:
        print(json.dumps(artifact, indent=2))


if __name__ == "__main__":
    main()
