#!/usr/bin/env python3
"""Build script for FSI-AgentGov-Solutions — manifest-driven (v1.4.0+).

Walks every top-level folder, loads `manifest.yaml`, and emits the following
deterministic artifacts from a single source of truth:

* `solutions.json` (committed at repo root) — mirrors the framework
  `solutions-lock.json` contract and publishes canonical machine-readable
  inventory counts (`counts.total`, `counts.live`, `counts.preview`) plus
  per-solution control coverage (`solutions.<solution-id>.controls`) so
  downstream consumers never have to parse generated prose.
* `<slug>/controls-covered.json` — per-solution control-coverage export
  listing each framework control ID with its coverage level (`full` or
  `partial`). Schema: `scripts/controls-covered.schema.json`. Consumed by
  the framework `solutions-lock.json` as the canonical per-solution contract
  (issue #163 / finding U-050).
* `README.md` solutions table inside `<!-- BEGIN:SOLUTIONS -->` /
  `<!-- END:SOLUTIONS -->` markers.
* `site-docs/solutions/index.md` — Solutions Catalog grouped by domain.
* `site-docs/solutions/<slug>/index.md` — per-solution detail pages.
* `site-docs/reference/control-mapping.md` — all 78 framework controls grouped
  by pillar; controls without solutions render "No solution yet".
* `site-docs/index.md` — hero metric counts derived from data (never hardcoded).
* Sub-doc copy from `<slug>/docs/*.md` to `site-docs/solutions/<slug>/` with
  filename normalization and intra-solution link rewriting.
* Root doc copy: `DEPLOYMENT-GUIDE.md` -> getting-started, `CHANGELOG.md` ->
  reference.
* Optional lab-validation evidence images: when `<slug>/docs/lab-validation-evidence.json`
  is present (schema: scripts/lab-validation-evidence.schema.json), the allow-listed,
  SHA-256-pinned PNGs under `<slug>/docs/img` are validated and — in write mode —
  copied byte-for-byte to `site-docs/solutions/<slug>/img`. See the "Lab-validation
  evidence images" section below for the full contract.

Validation runs on every invocation:

* JSON Schema (scripts/manifest.schema.json) for every manifest.
* `manifest.id` MUST equal the folder name.
* Every `controls[]` entry MUST exist in the framework `controls.json`
  (path resolved from FRAMEWORK_CONTROLS env var, defaulting to a sibling
  `fsi-agentgov` checkout).
* Every top-level solution `README.md` MUST expose a parseable metadata header
  near the H1 that matches the manifest-driven version/status contract:
  `Version`, `Status`, `Validated against framework version`, and an optional
  `Upstream Microsoft dependency` line when `manifest.yaml.upstreamDependency`
  is present.
* Optional `<slug>/docs/lab-validation-evidence.json` — shape, unique relative
  POSIX `.png` paths (no case-insensitive collisions) confined under
  `<slug>/docs/img`, structural PNG validity (signature, chunk framing, single
  IHDR, at least one contiguous IDAT, PLTE/color-type rules, per-chunk CRC,
  terminal IEND), SHA-256 match, and no unmanifested PNG. Enforced in both
  write and `--check` modes.

Usage:

    python scripts/build-manifest.py            # write artifacts in place
    python scripts/build-manifest.py --check    # validate + assert no drift

Canonical inventory contract
----------------------------

Downstream consumers MUST treat `solutions.json` as the authoritative export.
Use the top-level `counts` object for `total` / `live` / `preview` inventory
statistics. Treat each solution's `manifest.yaml.controls` array as the
canonical control-coverage declaration and sync it from
`solutions.json.solutions.<solution-id>.controls`. Generated Markdown summaries
(`README.md`, manifest-managed solution README blocks, `site-docs/solutions/index.md`,
etc.) are human-readable projections only and MUST NOT be parsed for counts or
control mappings.

Schema evolution policy
-----------------------

`solutions.json.schemaVersion` is `1.5.0` for this branch. The contract was
**additive-only** for the 1.4.x line: new optional fields could be introduced
in 1.4.1+ without bumping the framework lock contract. 1.5.0 is the first
breaking change since 1.4.0 — it makes `zones` a REQUIRED field on every
solution entry. Any of the following require a 1.6.0 bump AND a coordinated
PR against fsi-agentgov:

* renaming an existing field
* removing or repurposing an existing field
* changing the JSON shape of an existing field (string -> object, etc.)
* adding a new REQUIRED field

The framework consumer (`fsi-agentgov/scripts/validate_solutions_lock.py`)
was widened to accept both 1.4.x and 1.5.x in the companion PR before this
change shipped.

1.5.0 changelog (BREAKING):
* `zones` is now REQUIRED on every solution entry. The catalog already had
  `zones` populated and confirmed (commit `ce82f83`); the schema change is a
  tightening, not a data change.

1.5.x contract notes:
* Top-level `counts` exposes the authoritative `total` / `live` / `preview`
  inventory summary for downstream sync.
* `solutions.<solution-id>.controls` is the authoritative per-solution control
  list mirrored from `manifest.yaml.controls`.

1.4.2 changelog (additive only — historical):
* Optional `zones` field — array of {personal, team, enterprise}.
* Optional `dataClassification` field — public|internal|confidential|restricted.
* Optional `dataResidency` and `retention` free-form notes.

Framework version pinning
-------------------------

`build-manifest.py` reads `controls.json` from the path given by the
`FRAMEWORK_CONTROLS` env var (preferred) or a sibling `FSI-AgentGov` checkout.
CI workflows pin the framework checkout to a release tag via the
`FRAMEWORK_REF` repository variable (default `v1.4.0`). Local development
should also point at a tagged checkout — never `main` — so build artifacts
are reproducible.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import re
import shutil
import sys
import zlib
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path, PurePosixPath, PureWindowsPath

import yaml

try:
    from jsonschema import Draft202012Validator
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "jsonschema not installed. Run: pip install jsonschema pyyaml"
    ) from exc

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent
SITE_DOCS = ROOT / "site-docs"
SOLUTIONS_OUT = SITE_DOCS / "solutions"
SCHEMA_PATH = ROOT / "scripts" / "manifest.schema.json"
SOLUTIONS_JSON = ROOT / "solutions.json"
CONTROLS_COVERED_SCHEMA = ROOT / "scripts" / "controls-covered.schema.json"
LAB_EVIDENCE_SCHEMA_PATH = ROOT / "scripts" / "lab-validation-evidence.schema.json"
LAB_EVIDENCE_MANIFEST_NAME = "lab-validation-evidence.json"
LAB_IMG_DIRNAME = "img"
MAX_LAB_PNG_BYTES = 64 * 1024 * 1024
MAX_LAB_PNG_DECODED_BYTES = 256 * 1024 * 1024
# PNG 8-byte file signature (magic number). Extension checks alone are spoofable,
# so evidence sources must start with these bytes to be published.
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
LAB_EVIDENCE_SENSITIVE_PATTERNS = (
    ("UPN/email", re.compile(r"(?i)\b[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}\b")),
    ("tenant domain", re.compile(r"(?i)\b[a-z0-9\-]+\.onmicrosoft\.com\b")),
    (
        "GUID",
        re.compile(
            r"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-"
            r"[89ab][0-9a-f]{3}-[0-9a-f]{12}\b"
        ),
    ),
    ("URL", re.compile(r"(?i)\bhttps?://[^\s\"'<>]+")),
    (
        "bearer token",
        re.compile(r"(?i)\bauthorization\s*[:=]\s*bearer\s+\S+"),
    ),
    (
        "JWT",
        re.compile(r"(?i)\beyJ[a-z0-9_-]{5,}\.[a-z0-9_-]{5,}\.[a-z0-9_-]{5,}\b"),
    ),
    (
        "secret parameter",
        re.compile(r"(?i)\b(sig|code|token|access_token|client_secret)=([^&\s]+)"),
    ),
)
README = ROOT / "README.md"
SITE_INDEX = SITE_DOCS / "index.md"
CONTROL_MAPPING = SITE_DOCS / "reference" / "control-mapping.md"
SITE_CATALOG = SOLUTIONS_OUT / "index.md"

GITHUB_BLOB = "https://github.com/judeper/FSI-AgentGov-Solutions/blob/main"
SITE_BASE = "https://judeper.github.io/FSI-AgentGov-Solutions"
CONTROL_MAPPING_PAGE = f"{SITE_BASE}/reference/control-mapping/"

SOLUTIONS_BEGIN = "<!-- BEGIN:SOLUTIONS -->"
SOLUTIONS_END = "<!-- END:SOLUTIONS -->"
IMPLEMENTED_CONTROLS_BEGIN = "<!-- BEGIN:IMPLEMENTED_CONTROLS -->"
IMPLEMENTED_CONTROLS_END = "<!-- END:IMPLEMENTED_CONTROLS -->"
HERO_BEGIN = "<!-- BEGIN:HERO_METRICS -->"
HERO_END = "<!-- END:HERO_METRICS -->"
DEPLOY_LAYERS_BEGIN = "<!-- BEGIN:DEPLOY_LAYERS -->"
DEPLOY_LAYERS_END = "<!-- END:DEPLOY_LAYERS -->"
ZONE_ROADMAP_BEGIN = "<!-- BEGIN:ZONE_ROADMAP -->"
ZONE_ROADMAP_END = "<!-- END:ZONE_ROADMAP -->"

DEPLOYMENT_GUIDE = ROOT / "DEPLOYMENT-GUIDE.md"

README_HEADER_FIELD_LABELS = {
    "version": "Version",
    "status": "Status",
    "validated against framework version": "Validated against framework version",
    "upstream microsoft dependency": "Upstream Microsoft dependency",
}
README_STATUS_SECTION_RE = re.compile(
    r"^## Status\s*$\n(?:\n|\r\n)(?P<body>\|.*(?:\n|\r\n))+?(?=^## |\Z)",
    re.MULTILINE,
)
README_STATUS_ROW_RE = re.compile(
    r"^\|\s*(?P<prop>[^|]+?)\s*\|\s*(?P<value>[^|]+?)\s*\|$",
    re.MULTILINE,
)
README_VERSION_TOKEN_RE = re.compile(r"v?(\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?)")
README_CAPE_VERSION_RE = re.compile(
    r"^#\s*(v\d+\.\d+\.\d+)\s+CAPE alignment metadata$", re.MULTILINE
)
UPSTREAM_DEPENDENCY_STATUS_LABELS = {
    "preview": "Preview",
    "ga": "GA",
    "mixed": "Mixed",
}

CHANGELOG_PATTERNS = {"acv-changelog.md", "alca-changelog.md"}

DOMAIN_LABELS = {
    "access-identity": "Access & Identity",
    "content-data": "Content & Data Protection",
    "compliance-audit": "Compliance & Audit",
    "monitoring-analytics": "Monitoring & Analytics",
    "agent-config": "Agent Configuration",
    "lifecycle-ops": "Lifecycle & Operations",
}

PILLAR_NAMES = {
    1: "Pillar 1 — Security",
    2: "Pillar 2 — Management",
    3: "Pillar 3 — Reporting",
    4: "Pillar 4 — Governance",
}

DOMAIN_DESCRIPTIONS = {
    "access-identity": "Solutions for controlling who can access, share, and publish AI agents.",
    "content-data": "Solutions for securing agent content, file handling, and knowledge sources.",
    "compliance-audit": "Solutions for audit management, compliance reporting, and regulatory workflows.",
    "monitoring-analytics": "Solutions for observability, analytics, event correlation, and drift detection.",
    "agent-config": "Solutions for validating agent runtime configuration, session controls, and connector scope.",
    "lifecycle-ops": "Solutions for environment provisioning, agent lifecycle, and operational testing.",
}

# Folders to skip when scanning the repo root for solutions.
SKIP_FOLDERS = {
    ".claude", ".codex", ".github", ".git", "scripts", "site-docs", "site",
    "overrides", "__pycache__",
}

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger("build-manifest")


# ---------------------------------------------------------------------------
# Loading & validation
# ---------------------------------------------------------------------------
def load_schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def discover_solution_folders() -> list[str]:
    folders = []
    for entry in sorted(ROOT.iterdir()):
        if not entry.is_dir():
            continue
        if entry.name in SKIP_FOLDERS or entry.name.startswith("."):
            continue
        if (entry / "manifest.yaml").is_file():
            folders.append(entry.name)
    return folders


def load_manifests() -> dict[str, dict]:
    manifests: dict[str, dict] = {}
    for slug in discover_solution_folders():
        path = ROOT / slug / "manifest.yaml"
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
        except yaml.YAMLError as exc:
            raise SystemExit(f"FATAL: invalid YAML in {path}: {exc}")
        if not isinstance(data, dict):
            raise SystemExit(f"FATAL: {path} did not parse to a mapping")
        manifests[slug] = data
    return manifests


def load_framework_controls() -> dict[str, str]:
    """Return {control_id: pillar_int} from the framework controls.json."""
    env = os.environ.get("FRAMEWORK_CONTROLS")
    candidates: list[Path] = []
    if env:
        candidates.append(Path(env))
    candidates.extend([
        ROOT.parent / "fsi-agentgov" / "assessment" / "manifest" / "controls.json",
        ROOT.parent / "FSI-AgentGov" / "assessment" / "manifest" / "controls.json",
    ])
    for c in candidates:
        if c.is_file():
            log.info("Using framework controls: %s", c)
            data = json.loads(c.read_text(encoding="utf-8"))
            return {ctrl["id"]: int(ctrl["pillar"]) for ctrl in data}
    raise SystemExit(
        "FATAL: framework controls.json not found. Set FRAMEWORK_CONTROLS or "
        "place a sibling fsi-agentgov checkout next to this repo."
    )


def load_framework_control_titles() -> dict[str, str]:
    """Return {control_id: short_title} for control-mapping rendering."""
    env = os.environ.get("FRAMEWORK_CONTROLS")
    for c in (
        Path(env) if env else None,
        ROOT.parent / "fsi-agentgov" / "assessment" / "manifest" / "controls.json",
        ROOT.parent / "FSI-AgentGov" / "assessment" / "manifest" / "controls.json",
    ):
        if c and c.is_file():
            data = json.loads(c.read_text(encoding="utf-8"))
            out = {}
            for ctrl in data:
                # Prefer the short `name` over the prefixed `title`
                out[ctrl["id"]] = ctrl.get("name") or ctrl.get("title", "")
            return out
    return {}


def validate_manifests(
    manifests: dict[str, dict],
    framework_controls: dict[str, int],
) -> list[str]:
    errors: list[str] = []
    schema = load_schema()
    validator = Draft202012Validator(schema)

    for slug, m in manifests.items():
        # Schema validation
        for err in sorted(validator.iter_errors(m), key=lambda e: e.path):
            errors.append(
                f"{slug}/manifest.yaml: schema error at "
                f"{'/'.join(map(str, err.absolute_path)) or '(root)'}: {err.message}"
            )
        # id == folder
        if m.get("id") != slug:
            errors.append(
                f"{slug}/manifest.yaml: id={m.get('id')!r} must equal folder name"
            )
        # url echoes folder
        expected_url = f"{SITE_BASE}/solutions/{slug}/"
        if m.get("url") != expected_url:
            errors.append(
                f"{slug}/manifest.yaml: url must be {expected_url}, got {m.get('url')!r}"
            )
        # controls[] in framework
        for ctrl in m.get("controls", []):
            if ctrl not in framework_controls:
                errors.append(
                    f"{slug}/manifest.yaml: control {ctrl!r} not in framework controls.json"
                )
        # dependencies refer to known slugs
        for dep in m.get("dependencies", []):
            if dep not in manifests:
                errors.append(
                    f"{slug}/manifest.yaml: dependency {dep!r} is not a known solution"
                )

    return errors


def extract_cape_framework_version(readme_text: str) -> str | None:
    """Return the CAPE-alignment framework version embedded in README frontmatter."""
    match = README_CAPE_VERSION_RE.search(readme_text[:500])
    return match.group(1) if match else None


def render_readme_status(status: str) -> str:
    """Render the manifest enum for human-facing README headers."""
    return status.capitalize()


def render_upstream_dependency(dependency: dict[str, str]) -> str:
    """Render the optional upstream Microsoft dependency header value."""
    status = UPSTREAM_DEPENDENCY_STATUS_LABELS[dependency["status"]]
    note = dependency["note"].strip()
    return f"{status} — {note}" if note else status


def build_expected_readme_header(readme_text: str, manifest: dict) -> dict[str, str]:
    """Return the expected README header fields for one solution."""
    header = {
        "version": f"v{manifest['version']}",
        "status": render_readme_status(manifest.get("status", "live")),
    }
    framework_version = extract_cape_framework_version(readme_text)
    if framework_version:
        header["validated against framework version"] = framework_version
    dependency = manifest.get("upstreamDependency")
    if dependency:
        header["upstream microsoft dependency"] = render_upstream_dependency(dependency)
    return header


def parse_readme_header_fields(readme_text: str) -> dict[str, str]:
    """Parse the top-of-file README metadata header into a normalized mapping."""
    top = "\n".join(readme_text.splitlines()[:80])
    fields: dict[str, str] = {}
    for key, label in README_HEADER_FIELD_LABELS.items():
        match = re.search(rf"\*\*{re.escape(label)}:\*\*\s*(?P<value>[^\n]+)", top)
        if match:
            fields[key] = match.group("value").strip()

    if "version" not in fields or "status" not in fields:
        section = README_STATUS_SECTION_RE.search(top)
        if section:
            for row in README_STATUS_ROW_RE.finditer(section.group("body")):
                prop = row.group("prop").strip().lower()
                value = row.group("value").strip()
                if prop == "version" and "version" not in fields:
                    fields["version"] = value
                elif prop == "status" and "status" not in fields:
                    fields["status"] = value
    return fields


def parse_version_claim(value: str | None) -> str | None:
    """Extract a semver token from a README metadata value."""
    if not value:
        return None
    match = README_VERSION_TOKEN_RE.search(value)
    return match.group(1) if match else None


def normalize_status_claim(value: str | None) -> str | None:
    """Map legacy README labels to the manifest status enum."""
    if not value:
        return None
    lowered = value.lower()
    patterns = (
        (r"\b(public\s+)?preview\b", "preview"),
        (r"\bscaffold\b", "preview"),
        (r"\bin development\b", "preview"),
        (r"\blive\b", "live"),
        (r"\bproduction ready\b", "live"),
        (r"\bcompleted\b", "live"),
        (r"\bvalidated\b", "live"),
        (r"\bactive\b", "live"),
        (r"\breleased\b", "live"),
        (r"\bcomplete\b", "live"),
        (r"\bga\b", "live"),
    )
    for pattern, normalized in patterns:
        if re.search(pattern, lowered):
            return normalized
    return None


def validate_solution_readme_headers(manifests: dict[str, dict]) -> list[str]:
    """Validate that each solution README header agrees with manifest metadata."""
    errors: list[str] = []
    for slug, manifest in manifests.items():
        path = ROOT / slug / "README.md"
        if not path.is_file():
            errors.append(f"{slug}/README.md: missing top-level solution README")
            continue

        readme_text = path.read_text(encoding="utf-8")
        header_fields = parse_readme_header_fields(readme_text)
        expected_header = build_expected_readme_header(readme_text, manifest)

        claimed_version = parse_version_claim(
            header_fields.get("version") or header_fields.get("status")
        )
        if claimed_version is None:
            errors.append(f"{slug}/README.md: missing parseable Version header")
        elif claimed_version != manifest["version"]:
            errors.append(
                f"{slug}/README.md: Version header claims v{claimed_version}, "
                f"expected v{manifest['version']} from manifest.yaml"
            )

        claimed_status = normalize_status_claim(header_fields.get("status"))
        expected_status = manifest.get("status", "live")
        if claimed_status is None:
            errors.append(f"{slug}/README.md: missing parseable Status header")
        elif claimed_status != expected_status:
            errors.append(
                f"{slug}/README.md: Status header claims {header_fields.get('status')!r}, "
                f"expected {render_readme_status(expected_status)!r}"
            )

        for key in (
            "validated against framework version",
            "upstream microsoft dependency",
        ):
            expected_value = expected_header.get(key)
            claimed_value = header_fields.get(key)
            if expected_value and claimed_value != expected_value:
                errors.append(
                    f"{slug}/README.md: {README_HEADER_FIELD_LABELS[key]!r} should be "
                    f"{expected_value!r}, got {claimed_value!r}"
                )
            if not expected_value and claimed_value:
                errors.append(
                    f"{slug}/README.md: unexpected {README_HEADER_FIELD_LABELS[key]!r} "
                    f"header {claimed_value!r}; declare it in manifest.yaml first"
                )
    return errors


# ---------------------------------------------------------------------------
# Emitters
# ---------------------------------------------------------------------------
def project_to_lock(m: dict) -> dict:
    """Project a manifest to the framework solutions-lock.json shape."""
    out = {
        "id": m["id"],
        "name": m["name"],
        "version": m["version"],
        "domain": m["domain"],
        "tier": m["tier"],
        "status": m.get("status", "live"),
        "description": m["description"],
        "url": m["url"],
        "controls": list(m.get("controls", [])),
        "dependencies": list(m.get("dependencies", [])),
        "prerequisites": dict(m["prerequisites"]),
        "verification": m["verification"],
    }
    # zones is required as of schema 1.5.0; project always.
    out["zones"] = list(m["zones"])
    # Additive 1.4.2 fields. Only project when present so absent manifests
    # remain valid for staged backfill.
    if "dataClassification" in m:
        out["dataClassification"] = m["dataClassification"]
    if "dataResidency" in m:
        out["dataResidency"] = m["dataResidency"]
    if "retention" in m:
        out["retention"] = m["retention"]
    return out


def compute_inventory_counts(manifests: dict[str, dict]) -> dict[str, int]:
    """Return canonical inventory counts for the aggregated export."""
    return {
        "total": len(manifests),
        "live": sum(
            1 for m in manifests.values() if m.get("status", "live") == "live"
        ),
        "preview": sum(
            1 for m in manifests.values() if m.get("status", "live") == "preview"
        ),
    }


def format_inventory_summary(counts: dict[str, int], noun: str) -> str:
    """Render a short human-readable summary from canonical inventory counts."""
    return (
        f"{counts['total']} {noun} "
        f"({counts['live']} live, {counts['preview']} preview)"
    )


def emit_solutions_json(
    manifests: dict[str, dict],
    schema_version: str = "1.5.0",
) -> str:
    """Return the canonical solutions.json content (deterministic)."""
    counts = compute_inventory_counts(manifests)
    out = {
        "schemaVersion": schema_version,
        "generatedBy": "scripts/build-manifest.py",
        "counts": counts,
        "solutions": {
            slug: project_to_lock(manifests[slug])
            for slug in sorted(manifests)
        },
    }
    # Pretty + stable: 2-space indent, sorted top keys preserved by insertion.
    return json.dumps(out, indent=2, ensure_ascii=False) + "\n"


def emit_controls_covered_json(slug: str, m: dict) -> str:
    """Return the per-solution controls-covered.json content.

    Controls listed in the optional ``controls_partial`` manifest field are
    exported with ``"coverage": "partial"`` (the solution contributes to the
    control but does not provide primary/full implementation).  All other
    controls default to ``"coverage": "full"``.
    """
    partial_controls: set[str] = set(m.get("controls_partial", []))
    controls = [
        {"id": ctrl, "coverage": "partial" if ctrl in partial_controls else "full"}
        for ctrl in m.get("controls", [])
    ]
    out = {
        "schemaVersion": "1.0.0",
        "generatedBy": "scripts/build-manifest.py",
        "solutionId": m["id"],
        "solutionName": m["name"],
        "solutionVersion": m["version"],
        "status": m.get("status", "live"),
        "controls": controls,
        "controlCount": len(controls),
    }
    return json.dumps(out, indent=2, ensure_ascii=False) + "\n"


def emit_readme_table(manifests: dict[str, dict]) -> str:
    """Generate the README solutions table block (between markers, inclusive)."""
    counts = compute_inventory_counts(manifests)
    rows = []
    rows.append(SOLUTIONS_BEGIN)
    rows.append("<!-- Generated by scripts/build-manifest.py — do not edit by hand. -->")
    rows.append("")
    rows.append(
        "This repository currently includes "
        f"**{format_inventory_summary(counts, 'solution implementations')}**."
    )
    rows.append("")
    rows.append(
        "Downstream consumers should treat `solutions.json` (top-level `counts` "
        "plus each `solutions.<solution-id>.controls` list mirrored from "
        "`manifest.yaml.controls`) as the authoritative machine-readable export; "
        "this README block and its Controls column are generated summaries only."
    )
    rows.append("")
    rows.append("| Solution | Description | Version | Status | Zones | Controls |")
    rows.append("|----------|-------------|---------|--------|-------|----------|")
    for slug in sorted(manifests):
        m = manifests[slug]
        controls = ", ".join(m.get("controls", [])) or "—"
        zones = ", ".join(m.get("zones", [])) or "—"
        status = m.get("status", "live")
        rows.append(
            f"| [{m['name']}](./{slug}/) | {m['description']} | v{m['version']} | {status} | {zones} | {controls} |"
        )
    rows.append("")
    rows.append(SOLUTIONS_END)
    return "\n".join(rows)


def emit_solution_readme_controls_block(
    m: dict,
    framework_titles: dict[str, str],
) -> str:
    """Generate a manifest-managed README block for canonical implemented controls."""
    controls = m.get("controls", [])
    lines = [
        IMPLEMENTED_CONTROLS_BEGIN,
        "<!-- Generated by scripts/build-manifest.py from manifest.yaml.controls — do not edit by hand. -->",
        "",
        "## Implemented Controls",
        "",
        "Canonical control coverage for this solution is declared in "
        "`manifest.yaml.controls` and exported in `solutions.json` as "
        "`solutions.<solution-id>.controls`. Downstream consumers should sync "
        "from that machine-readable list rather than parsing hand-maintained "
        "README prose.",
        "",
    ]
    if controls:
        lines.append("| Control | Description |")
        lines.append("|---------|-------------|")
        for control_id in controls:
            link = f"{CONTROL_MAPPING_PAGE}#control-{control_id.replace('.', '-')}"
            title = framework_titles.get(control_id, "See control mapping")
            lines.append(f"| [{control_id}]({link}) | {title} |")
    else:
        lines.append("_No framework controls mapped._")
    lines.append("")
    lines.append(IMPLEMENTED_CONTROLS_END)
    return "\n".join(lines)


def sync_solution_readme_controls(
    slug: str,
    m: dict,
    framework_titles: dict[str, str],
) -> tuple[Path, str] | None:
    """Return an updated README when a solution opts into manifest-managed controls."""
    path = ROOT / slug / "README.md"
    if not path.is_file():
        return None
    original = path.read_text(encoding="utf-8")
    if (
        IMPLEMENTED_CONTROLS_BEGIN not in original
        or IMPLEMENTED_CONTROLS_END not in original
    ):
        return None
    new_block = emit_solution_readme_controls_block(m, framework_titles)
    return path, replace_block(
        original,
        IMPLEMENTED_CONTROLS_BEGIN,
        IMPLEMENTED_CONTROLS_END,
        new_block,
    )


def replace_block(text: str, begin: str, end: str, new_block: str) -> str:
    pattern = re.compile(
        rf"{re.escape(begin)}.*?{re.escape(end)}", re.DOTALL
    )
    if pattern.search(text):
        return pattern.sub(new_block, text)
    # Append at end if markers missing.
    sep = "" if text.endswith("\n") else "\n"
    return f"{text}{sep}\n{new_block}\n"


def emit_site_catalog(manifests: dict[str, dict]) -> str:
    counts = compute_inventory_counts(manifests)
    by_domain: dict[str, list[str]] = defaultdict(list)
    for slug, m in manifests.items():
        by_domain[m["domain"]].append(slug)
    lines = [
        "# Solutions Catalog",
        "",
        f"{format_inventory_summary(counts, 'reference implementations')} organized by functional domain.",
        "",
        "<!-- Generated by scripts/build-manifest.py — do not edit by hand. -->",
        "",
        "---",
        "",
    ]
    for domain in DOMAIN_LABELS:
        slugs = sorted(by_domain.get(domain, []), key=lambda s: manifests[s]["name"].lower())
        if not slugs:
            continue
        lines.append(f"## {DOMAIN_LABELS[domain]}")
        lines.append("")
        lines.append(DOMAIN_DESCRIPTIONS[domain])
        lines.append("")
        lines.append("| Solution | Description | Version | Status | Zones | Controls |")
        lines.append("|----------|-------------|---------|--------|-------|----------|")
        for slug in slugs:
            m = manifests[slug]
            controls = ", ".join(m.get("controls", [])) or "—"
            zones = ", ".join(m.get("zones", [])) or "—"
            status = m.get("status", "live")
            lines.append(
                f"| [{m['name']}]({slug}/index.md) | {m['description']} | v{m['version']} | {status} | {zones} | {controls} |"
            )
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def emit_solution_detail(slug: str, m: dict, sub_docs: list[str]) -> str:
    """Render the per-solution detail page from manifest + sub-doc list."""
    domain_label = DOMAIN_LABELS.get(m["domain"], m["domain"])
    controls = m.get("controls", [])
    deps = m.get("dependencies", [])

    lines = [f"# {m['name']}", ""]

    # Metadata badges
    badges = [
        f"**Version:** v{m['version']}",
        f"**Status:** {m['status']}",
        f"**Domain:** {domain_label}",
        f"**Tier:** {m['tier']}",
    ]
    if m.get("zones"):
        badges.append(f"**Zones:** {', '.join(m['zones'])}")
    if m.get("dataClassification"):
        badges.append(f"**Data classification:** {m['dataClassification']}")
    lines.append(" | ".join(badges))
    lines.append("")
    lines.append(m["description"])
    lines.append("")

    # Controls
    lines.append("## Mapped Controls")
    lines.append("")
    if controls:
        lines.append(", ".join(
            f"[{c}](../../reference/control-mapping.md#control-{c.replace('.', '-')})"
            for c in controls
        ))
    else:
        lines.append("_No framework controls mapped._")
    lines.append("")

    # Prerequisites
    lines.append("## Prerequisites")
    lines.append("")
    lines.append("| Role | Requirement |")
    lines.append("|------|-------------|")
    for role, req in m["prerequisites"].items():
        lines.append(f"| `{role}` | {req} |")
    lines.append("")

    # Dependencies
    if deps:
        lines.append("## Dependencies")
        lines.append("")
        for dep in deps:
            lines.append(f"- [`{dep}`](../{dep}/index.md)")
        lines.append("")

    # Verification
    lines.append("## Verification")
    lines.append("")
    lines.append(m["verification"])
    lines.append("")

    # Documentation sub-pages
    if sub_docs:
        lines.append("## Documentation")
        lines.append("")
        lines.append("| Document |")
        lines.append("|----------|")
        for fname in sub_docs:
            display = fname[:-3].replace("-", " ").title()
            lines.append(f"| [{display}]({fname}) |")
        lines.append("")

    # GitHub link
    lines.append("---")
    lines.append("")
    lines.append(
        f"[View source on GitHub]({GITHUB_BLOB}/{slug}/) {{ .md-button }}"
    )
    lines.append("")
    return "\n".join(lines)


def emit_control_mapping(
    manifests: dict[str, dict],
    framework_pillars: dict[str, int],
    framework_titles: dict[str, str],
) -> str:
    # control_id -> [(name, slug)]
    by_control: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for slug, m in manifests.items():
        for c in m.get("controls", []):
            by_control[c].append((m["name"], slug))

    mapped_count = sum(1 for cid in framework_pillars if by_control.get(cid))
    total = len(framework_pillars)

    def control_sort_key(cid: str) -> tuple[int, int]:
        major, _, minor = cid.partition(".")
        return (int(major), int(minor))

    lines = [
        "# Control Mapping",
        "",
        f"Complete mapping of the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/) controls to implementing solutions. **{mapped_count} of {total}** controls have at least one solution; remaining controls show *No solution yet*.",
        "",
        "<!-- Generated by scripts/build-manifest.py — do not edit by hand. -->",
        "",
    ]

    # Group by pillar
    by_pillar: dict[int, list[str]] = defaultdict(list)
    for cid, pillar in framework_pillars.items():
        by_pillar[pillar].append(cid)

    for pillar in sorted(by_pillar):
        lines.append(f"## {PILLAR_NAMES.get(pillar, f'Pillar {pillar}')}")
        lines.append("")
        lines.append("| Control | Description | Solutions |")
        lines.append("|---------|-------------|-----------|")
        for cid in sorted(by_pillar[pillar], key=control_sort_key):
            anchor_id = f"control-{cid.replace('.', '-')}"
            sols = by_control.get(cid, [])
            if sols:
                cell = ", ".join(
                    f"[{name}](../solutions/{slug}/index.md)"
                    for name, slug in sorted(sols, key=lambda x: x[0].lower())
                )
            else:
                cell = "_No solution yet_"
            title = framework_titles.get(cid, "")
            lines.append(
                f'| <span id="{anchor_id}"></span>{cid} | {title} | {cell} |'
            )
        lines.append("")

    counts = compute_inventory_counts(manifests)
    lines.append("## Coverage Summary")
    lines.append("")
    lines.append(f"- **Controls with implementations:** {mapped_count} of {total}")
    lines.append(
        f"- **Solution inventory:** {format_inventory_summary(counts, 'solutions')}"
    )
    avg = (
        sum(len(m.get("controls", [])) for m in manifests.values()) / max(counts["total"], 1)
    )
    lines.append(f"- **Controls per solution (avg):** {avg:.1f}")
    lines.append("")
    lines.append("!!! info \"Framework Reference\"")
    lines.append("    Full control specifications are available in the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/controls/).")
    lines.append("")
    return "\n".join(lines)


# Short-form codes for the dependency-tree references in DEPLOYMENT-GUIDE.
_SLUG_SHORT = {
    "agent-observability-foundation": "AOF",
    "cross-solution-integration": "CSI",
    "compliance-dashboard": "CD",
    "audit-compliance-manager": "ACM",
    "copilot-studio-analytics": "CSA",
    "deny-event-correlation-report": "DECR",
    "scope-drift-monitor": "SDM",
    "agent-registry-automation": "ARA",
    "unrestricted-agent-sharing-detector": "UASD",
    "cross-tenant-external-sharing-governance": "CTESG",
    "environment-lifecycle-management": "ELM",
}


def _layer_for(m: dict) -> str:
    """Bucket a manifest into the deployment-guide layer model.

    Layer 1: Tier 1 foundational solutions.
    Layer 2: Tier 2 solutions wired into Compliance Dashboard via CSI.
    Layer 3: All other solutions (Tier 3 and standalone).
    """
    if m["tier"] == "1":
        return "1"
    # Tier 2 solutions that show up as CSI dependents in current docs.
    csi_dashboard = {
        "audit-compliance-manager",
        "session-security-configurator",
        "agent-access-monitor",
        "content-moderation-monitor",
        "file-upload-security",
        "conditional-access-automation",
    }
    if m["id"] in csi_dashboard:
        return "2"
    return "3"


def emit_deploy_layers_block(manifests: dict[str, dict]) -> str:
    """Render the Layer 1/2/3 deployment tables for DEPLOYMENT-GUIDE.md."""
    by_layer: dict[str, list[dict]] = defaultdict(list)
    for slug in sorted(manifests):
        by_layer[_layer_for(manifests[slug])].append(manifests[slug])

    lines = [
        DEPLOY_LAYERS_BEGIN,
        "<!-- Generated by scripts/build-manifest.py — do not edit by hand. -->",
        "",
        "### Layer 1: Foundational Infrastructure",
        "",
        "These solutions provide shared infrastructure that other solutions depend on:",
        "",
        "| Solution | Role | Version |",
        "|----------|------|---------|",
    ]
    for m in by_layer["1"]:
        lines.append(f"| [{m['name']}](./{m['id']}/) | {m['description']} | v{m['version']} |")
    lines.append("")
    lines.append("### Layer 2: Tier 2 Governance Solutions")
    lines.append("")
    lines.append(
        "These solutions operate independently but can be wired into the "
        "Compliance Dashboard via [Cross-Solution Integration](./cross-solution-integration/):"
    )
    lines.append("")
    lines.append("| Solution | Version | Controls |")
    lines.append("|----------|---------|----------|")
    for m in by_layer["2"]:
        controls = ", ".join(m.get("controls", [])) or "—"
        lines.append(f"| [{m['name']}](./{m['id']}/) | v{m['version']} | {controls} |")
    lines.append("")
    lines.append("### Layer 3: Tier 3 / Standalone Solutions")
    lines.append("")
    lines.append(
        "All other solutions operate independently and can be deployed in any "
        "order based on customer needs."
    )
    lines.append("")
    lines.append("| Solution | Tier | Version | Zones |")
    lines.append("|----------|------|---------|-------|")
    for m in by_layer["3"]:
        zones = ", ".join(m.get("zones", [])) or "—"
        lines.append(
            f"| [{m['name']}](./{m['id']}/) | {m['tier']} | v{m['version']} | {zones} |"
        )
    lines.append("")
    lines.append(DEPLOY_LAYERS_END)
    return "\n".join(lines)


def emit_zone_roadmap_block(manifests: dict[str, dict]) -> str:
    """Render the Personal/Team/Enterprise zone applicability matrix."""
    lines = [
        ZONE_ROADMAP_BEGIN,
        "<!-- Generated by scripts/build-manifest.py — do not edit by hand. -->",
        "",
    ]
    by_tier: dict[str, list[dict]] = defaultdict(list)
    for slug in sorted(manifests, key=lambda s: manifests[s]["name"].lower()):
        m = manifests[slug]
        by_tier[m["tier"]].append(m)

    tier_labels = {
        "1": "Tier 1 (Foundational)",
        "2": "Tier 2 (Governance)",
        "3": "Tier 3 (Enterprise)",
    }
    for tier in sorted(by_tier):
        lines.append(f"### {tier_labels.get(tier, f'Tier {tier}')}")
        lines.append("")
        lines.append("| Solution | Personal | Team | Enterprise | Data class |")
        lines.append("|----------|----------|------|------------|------------|")
        for m in by_tier[tier]:
            zones = set(m.get("zones", []))
            p = "✅" if "personal" in zones else "—"
            t = "✅" if "team" in zones else "—"
            e = "✅" if "enterprise" in zones else "—"
            dc = m.get("dataClassification", "—")
            lines.append(
                f"| [{m['name']}](./{m['id']}/) | {p} | {t} | {e} | {dc} |"
            )
        lines.append("")
    lines.append(ZONE_ROADMAP_END)
    return "\n".join(lines)


def emit_hero_metrics_block(
    manifests: dict[str, dict],
    framework_pillars: dict[str, int],
) -> str:
    counts = compute_inventory_counts(manifests)
    n_solutions = counts["total"]
    n_controls = len(framework_pillars)
    n_domains = len({m["domain"] for m in manifests.values()})
    n_tiers = len({m["tier"] for m in manifests.values()})
    block = f"""{HERO_BEGIN}
<!-- Generated by scripts/build-manifest.py — do not edit by hand. -->
<div class="metrics-strip">
  <div class="metric">
    <span class="metric-number">{n_solutions}</span>
    <span class="metric-label">Solutions</span>
  </div>
  <div class="metric">
    <span class="metric-number">{n_controls}</span>
    <span class="metric-label">Framework Controls</span>
  </div>
  <div class="metric">
    <span class="metric-number">{n_domains}</span>
    <span class="metric-label">Solution Domains</span>
  </div>
  <div class="metric">
    <span class="metric-number">{n_tiers}</span>
    <span class="metric-label">Deployment Tiers</span>
  </div>
</div>
{HERO_END}"""
    return block


# ---------------------------------------------------------------------------
# Sub-doc copy (carried forward from the legacy build-docs.py)
# ---------------------------------------------------------------------------
def normalize_filename(name: str) -> str:
    stem = Path(name).stem
    suffix = Path(name).suffix
    return stem.lower().replace("_", "-") + suffix.lower()


def rewrite_sub_doc_links(
    content: str,
    slug: str,
    filename_map: dict[str, str],
) -> str:
    def _replace(match: re.Match) -> str:
        prefix, path, suffix = match.group(1), match.group(2), match.group(3)
        # Skip externals & anchors
        if path.startswith(("http://", "https://", "#", "mailto:")):
            return match.group(0)
        # Parent links -> GitHub
        if path.startswith("../"):
            resolved = path.lstrip("./")
            return f"{prefix}{GITHUB_BLOB}/{resolved}{suffix}"
        clean = path
        if clean.startswith("./"):
            clean = clean[2:]
        if clean.startswith("docs/"):
            clean = clean[5:]
        anchor = ""
        if "#" in clean:
            clean, anchor = clean.split("#", 1)
            anchor = "#" + anchor
        basename = Path(clean).name
        if basename in filename_map:
            return f"{prefix}{filename_map[basename]}{anchor}{suffix}"
        if clean.endswith(".md"):
            return f"{prefix}{normalize_filename(basename)}{anchor}{suffix}"
        return match.group(0)

    return re.sub(r"(\[[^\]]*\]\()([^)]+)(\))", _replace, content)


def copy_sub_docs(slug: str, write_files: bool) -> tuple[list[str], dict[Path, str]]:
    """Return (sorted normalized filenames, {path: content}) for sub-docs."""
    src = ROOT / slug / "docs"
    if not src.is_dir():
        return [], {}
    out_dir = SOLUTIONS_OUT / slug
    filename_map: dict[str, str] = {}
    md_files: list[Path] = []
    for f in src.iterdir():
        if f.suffix.lower() != ".md":
            continue
        if f.name.lower() in CHANGELOG_PATTERNS:
            continue
        md_files.append(f)
        filename_map[f.name] = normalize_filename(f.name)

    pending: dict[Path, str] = {}
    for f in md_files:
        norm = filename_map[f.name]
        content = f.read_text(encoding="utf-8")
        content = rewrite_sub_doc_links(content, slug, filename_map)
        pending[out_dir / norm] = content

    if write_files:
        out_dir.mkdir(parents=True, exist_ok=True)
        for path, content in pending.items():
            path.write_text(content, encoding="utf-8")

    return sorted(filename_map.values()), pending


def _rewrite_root_doc_links(content: str, slugs: set[str]) -> str:
    """Rewrite ./<slug>/ and ./<slug>/foo links in DEPLOYMENT-GUIDE / CHANGELOG
    so the rendered site resolves them. Solution-folder links go to internal
    site detail pages; CHANGELOG.md → GitHub blob (we don't render per-solution
    changelogs in the site)."""
    pattern = re.compile(r"(\[[^\]]*\]\()([^)]+)(\))")

    def replace(match: re.Match) -> str:
        prefix, path, suffix = match.group(1), match.group(2), match.group(3)
        if path.startswith(("http://", "https://", "#", "mailto:")):
            return match.group(0)
        clean = path.lstrip("./")
        head = clean.split("/", 1)[0]
        if head not in slugs:
            return match.group(0)
        rest = clean[len(head):].lstrip("/")
        # Solution root link → site detail page
        if rest in ("", "README.md"):
            return f"{prefix}../solutions/{head}/index.md{suffix}"
        # Anything deeper (CHANGELOG.md, docs/foo.md, scripts/...) → GitHub blob
        return f"{prefix}{GITHUB_BLOB}/{head}/{rest}{suffix}"

    return pattern.sub(replace, content)


def copy_root_docs(
    write_files: bool,
    slugs: set[str] | None = None,
    overrides: dict[Path, str] | None = None,
) -> dict[Path, str]:
    pending: dict[Path, str] = {}
    overrides = overrides or {}
    mappings = [
        (ROOT / "DEPLOYMENT-GUIDE.md", SITE_DOCS / "getting-started" / "deployment-guide.md"),
        (ROOT / "CHANGELOG.md", SITE_DOCS / "reference" / "changelog.md"),
    ]
    for src, dst in mappings:
        if src in overrides:
            content = overrides[src]
        elif src.is_file():
            content = src.read_text(encoding="utf-8")
        else:
            continue
        if slugs:
            content = _rewrite_root_doc_links(content, slugs)
        pending[dst] = content
        if write_files:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(content, encoding="utf-8")
    return pending


# ---------------------------------------------------------------------------
# Lab-validation evidence images (binary publish, outside the text pipeline)
# ---------------------------------------------------------------------------
#
# Contract (schema: scripts/lab-validation-evidence.schema.json)
# --------------------------------------------------------------
# A solution MAY ship an OPTIONAL evidence manifest at
# ``<slug>/docs/lab-validation-evidence.json``. When present it allow-lists the
# sanitized PNG screenshots that later lab-validation report work references, so
# that ONLY those images are published into the generated (git-ignored) site at
# ``site-docs/solutions/<slug>/img/<path>``. Shape (v1.0.0):
#
#   {
#     "schemaVersion": "1.0.0",
#     "solution": "<slug>",            # optional; must equal the folder when set
#     "images": [
#       {
#         "path": "lab-validation/x.png",   # relative, POSIX, under docs/img, .png
#         "sha256": "<64 lowercase hex>",   # SHA-256 of the source bytes
#         "sourceClass": "portal-screenshot",
#         "capturedUtc": "2026-07-21T10:00:00Z",
#         "caption": "…",
#         "alt": "…"
#       }
#     ]
#   }
#
# Validation runs in BOTH write and ``--check`` modes and fails the build with
# actionable errors on: bad JSON shape, duplicate paths, case-insensitive path
# collisions (Windows/Linux portability), absolute/traversal/non-POSIX paths,
# sources outside ``<slug>/docs/img``, non-``.png`` sources, structurally invalid
# PNGs (signature, four-letter chunk types, framing, single IHDR, >=1 contiguous
# IDAT, PLTE placement/color-type rules, per-chunk CRC-32, no unknown critical
# chunks, terminal IEND, no truncation/trailing bytes), missing/non-regular
# sources, SHA-256 mismatches, and any unmanifested PNG under ``<slug>/docs/img``. In WRITE mode the publisher
# owns the generated ``site-docs/solutions/<slug>/img`` subtree: it re-reads each
# source ONCE, re-validates structure + SHA-256 on those exact bytes (closing the
# TOCTOU window), writes the validated bytes, and removes the subtree for slugs
# whose manifest was deleted. Publishing is deliberately kept out of the text
# ``record()`` pipeline so PNG bytes never flow through the UTF-8 helpers.


def load_lab_evidence_schema() -> dict:
    return json.loads(LAB_EVIDENCE_SCHEMA_PATH.read_text(encoding="utf-8"))


def load_lab_evidence(slug: str) -> dict | None:
    """Return the parsed evidence manifest for ``slug`` or ``None`` when absent.

    A JSON parse failure is surfaced as a manifest with a sentinel error marker
    so ``validate_lab_evidence`` can report it rather than raising.
    """
    path = ROOT / slug / "docs" / LAB_EVIDENCE_MANIFEST_NAME
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        return {"__parse_error__": str(exc)}


class LabEvidenceError(RuntimeError):
    """Raised when evidence images fail revalidation during publishing."""


def _png_scanline_layout(
    width: int,
    height: int,
    bit_depth: int,
    color_type: int,
    interlace_method: int,
) -> tuple[list[tuple[int, int, int]], int]:
    """Return (row-count, row-bytes, pixel-width) groups and decoded length."""
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    bits_per_pixel = channels * bit_depth
    passes = (
        ((0, 0, 1, 1),)
        if interlace_method == 0
        else (
            (0, 0, 8, 8),
            (4, 0, 8, 8),
            (0, 4, 4, 8),
            (2, 0, 4, 4),
            (0, 2, 2, 4),
            (1, 0, 2, 2),
            (0, 1, 1, 2),
        )
    )
    scanlines: list[tuple[int, int, int]] = []
    expected_size = 0
    for x_start, y_start, x_step, y_step in passes:
        pass_width = (
            (width - x_start + x_step - 1) // x_step
            if width > x_start
            else 0
        )
        pass_height = (
            (height - y_start + y_step - 1) // y_step
            if height > y_start
            else 0
        )
        if pass_width == 0 or pass_height == 0:
            continue
        row_bytes = (pass_width * bits_per_pixel + 7) // 8
        scanlines.append((pass_height, row_bytes, pass_width))
        expected_size += pass_height * (1 + row_bytes)
    return scanlines, expected_size


def _read_lab_png_bytes(path: Path) -> bytes:
    """Read one PNG through a stable handle without exceeding the source limit."""
    with path.open("rb") as handle:
        initial = os.fstat(handle.fileno())
        if initial.st_size > MAX_LAB_PNG_BYTES:
            raise LabEvidenceError("source exceeds the 64 MiB evidence limit")
        data = handle.read(MAX_LAB_PNG_BYTES + 1)
        final = os.fstat(handle.fileno())
    if len(data) > MAX_LAB_PNG_BYTES or final.st_size > MAX_LAB_PNG_BYTES:
        raise LabEvidenceError("source exceeds the 64 MiB evidence limit")
    return data


def _is_reparse_point(path: Path) -> bool:
    is_junction = getattr(path, "is_junction", None)
    return path.is_symlink() or bool(is_junction and is_junction())


def _confined_destination(candidate: Path, trusted_root: Path) -> Path:
    """Resolve a generated destination without following reparse points."""
    root_absolute = trusted_root.absolute()
    candidate_absolute = candidate.absolute()
    try:
        relative = candidate_absolute.relative_to(root_absolute)
    except ValueError as exc:
        raise LabEvidenceError(
            f"destination {candidate} is outside trusted root {trusted_root}"
        ) from exc

    current = root_absolute
    if current.exists() and _is_reparse_point(current):
        raise LabEvidenceError(f"trusted destination root is a reparse point: {current}")
    for part in relative.parts:
        current = current / part
        if current.exists() and _is_reparse_point(current):
            raise LabEvidenceError(f"destination path is a reparse point: {current}")

    root_resolved = trusted_root.resolve()
    candidate_resolved = candidate.resolve()
    if not _path_is_within(candidate_resolved, root_resolved):
        raise LabEvidenceError(
            f"destination {candidate} resolves outside trusted root {trusted_root}"
        )
    return candidate_resolved


def _validate_png_structure(data: bytes) -> str | None:
    """Return an error string when ``data`` is not a structurally valid PNG.

    Dependency-free (stdlib ``zlib`` only). Verifies the 8-byte signature and,
    for every chunk, four-ASCII-letter type bytes, framing without truncation,
    and a per-chunk CRC-32. Enforces critical-chunk rules so non-renderable
    files cannot pass as evidence: a single leading 13-byte IHDR (positive
    dimensions, valid compression/filter/interlace methods, valid bit-depth /
    color-type pairing); at least one IDAT with all IDATs consecutive; PLTE (if
    present) exactly once, before IDAT, required for indexed color type 3 and
    prohibited for grayscale types 0/4, with a length that is a positive
    multiple of 3; a terminal zero-length IEND; rejection of unknown critical
    chunks; and no truncation or trailing bytes. Ancillary chunks are permitted.
    """
    if len(data) > MAX_LAB_PNG_BYTES:
        return "PNG source exceeds the 64 MiB evidence limit"
    if not data.startswith(PNG_SIGNATURE):
        return "missing PNG signature"

    valid_bit_depths = {
        0: {1, 2, 4, 8, 16},
        2: {8, 16},
        3: {1, 2, 4, 8},
        4: {8, 16},
        6: {8, 16},
    }

    offset = len(PNG_SIGNATURE)
    total = len(data)
    first_chunk = True
    seen_ihdr = False
    seen_plte = False
    seen_idat = False
    idat_ended = False
    saw_iend = False
    width: int | None = None
    height: int | None = None
    bit_depth: int | None = None
    color_type: int | None = None
    interlace_method: int | None = None
    scanlines: list[tuple[int, int, int]] = []
    expected_size: int | None = None
    decompressor = zlib.decompressobj()
    decoded = bytearray()
    palette_entries: int | None = None

    while offset < total:
        if offset + 8 > total:
            return "truncated chunk header"
        length = int.from_bytes(data[offset:offset + 4], "big")
        ctype = data[offset + 4:offset + 8]
        body_start = offset + 8
        body_end = body_start + length
        if body_end + 4 > total:
            return "truncated chunk data or CRC"

        body = memoryview(data)[body_start:body_end]
        declared_crc = int.from_bytes(data[body_end:body_end + 4], "big")
        actual_crc = zlib.crc32(ctype)
        actual_crc = zlib.crc32(body, actual_crc) & 0xFFFFFFFF
        if actual_crc != declared_crc:
            return f"CRC mismatch in {ctype.decode('latin-1', 'replace')} chunk"

        # Chunk type must be four ASCII letters (A-Z / a-z).
        if not all(65 <= b <= 90 or 97 <= b <= 122 for b in ctype):
            return "invalid chunk type bytes"
        is_critical = (ctype[0] & 0x20) == 0

        if first_chunk:
            if ctype != b"IHDR":
                return "first chunk must be IHDR"
            first_chunk = False

        if ctype == b"IHDR":
            if seen_ihdr:
                return "duplicate IHDR chunk"
            seen_ihdr = True
            if length != 13:
                return "IHDR length must be 13"
            width = int.from_bytes(body[0:4], "big")
            height = int.from_bytes(body[4:8], "big")
            if width == 0 or height == 0:
                return "IHDR dimensions must be positive"
            bit_depth = body[8]
            color_type = body[9]
            if body[10] != 0:
                return "IHDR compression method must be 0"
            if body[11] != 0:
                return "IHDR filter method must be 0"
            interlace_method = body[12]
            if interlace_method not in (0, 1):
                return "IHDR interlace method must be 0 or 1"
            if color_type not in valid_bit_depths:
                return "IHDR color type is invalid"
            if bit_depth not in valid_bit_depths[color_type]:
                return "IHDR bit depth is invalid for the color type"
            scanlines, expected_size = _png_scanline_layout(
                width, height, bit_depth, color_type, interlace_method
            )
            if expected_size > MAX_LAB_PNG_DECODED_BYTES:
                return "decoded PNG data exceeds the 256 MiB evidence limit"
        elif ctype == b"PLTE":
            if seen_plte:
                return "duplicate PLTE chunk"
            if seen_idat:
                return "PLTE must appear before IDAT"
            if color_type in (0, 4):
                return "PLTE prohibited for grayscale color type"
            if length == 0 or length % 3 != 0:
                return "PLTE length must be a positive multiple of 3"
            palette_entries = length // 3
            if palette_entries > 256:
                return "PLTE cannot contain more than 256 entries"
            if color_type == 3 and bit_depth is not None:
                if palette_entries > (1 << bit_depth):
                    return "PLTE has too many entries for the indexed bit depth"
            seen_plte = True
        elif ctype == b"IDAT":
            if idat_ended:
                return "IDAT chunks must be consecutive"
            seen_idat = True
            assert expected_size is not None
            try:
                remaining = expected_size + 1 - len(decoded)
                decoded.extend(decompressor.decompress(body, max(remaining, 1)))
            except zlib.error:
                return "IDAT data is not a valid zlib stream"
            if decompressor.unconsumed_tail:
                return "decoded PNG data exceeds the IHDR dimensions"
            if decompressor.unused_data:
                return "IDAT zlib stream has trailing data"
        elif ctype == b"IEND":
            if length != 0:
                return "IEND length must be 0"
            saw_iend = True
        elif is_critical:
            return f"unknown critical chunk {ctype.decode('latin-1', 'replace')}"

        # Any non-IDAT chunk after the IDAT run ends the (required-contiguous) run.
        if seen_idat and ctype != b"IDAT":
            idat_ended = True

        offset = body_end + 4
        if ctype == b"IEND":
            break

    if not seen_ihdr:
        return "no IHDR chunk found"
    if not saw_iend:
        return "missing terminal IEND chunk"
    if not seen_idat:
        return "no IDAT chunk found"
    if color_type == 3 and not seen_plte:
        return "PLTE required for indexed color type"
    if offset != total:
        return "trailing bytes after IEND"

    assert width is not None
    assert height is not None
    assert bit_depth is not None
    assert color_type is not None
    assert interlace_method is not None

    assert expected_size is not None
    try:
        decoded.extend(decompressor.flush())
    except zlib.error:
        return "IDAT data is not a valid zlib stream"

    if not decompressor.eof:
        return "IDAT zlib stream is incomplete"
    if decompressor.unused_data:
        return "IDAT zlib stream has trailing data"
    if len(decoded) != expected_size:
        return (
            "decoded PNG data length does not match the IHDR dimensions "
            f"(expected {expected_size}, got {len(decoded)})"
        )

    row_offset = 0
    if color_type != 3:
        for pass_height, row_bytes, _ in scanlines:
            for _ in range(pass_height):
                filter_type = decoded[row_offset]
                if filter_type > 4:
                    return f"invalid PNG scanline filter type {filter_type}"
                row_offset += 1 + row_bytes
        return None

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    filter_bpp = max(1, (channels * bit_depth + 7) // 8)
    for pass_height, row_bytes, pass_width in scanlines:
        previous = bytearray(row_bytes)
        for _ in range(pass_height):
            filter_type = decoded[row_offset]
            if filter_type > 4:
                return f"invalid PNG scanline filter type {filter_type}"
            filtered = decoded[row_offset + 1:row_offset + 1 + row_bytes]
            reconstructed = bytearray(row_bytes)
            for index, value in enumerate(filtered):
                left = reconstructed[index - filter_bpp] if index >= filter_bpp else 0
                up = previous[index]
                upper_left = previous[index - filter_bpp] if index >= filter_bpp else 0
                if filter_type == 0:
                    predictor = 0
                elif filter_type == 1:
                    predictor = left
                elif filter_type == 2:
                    predictor = up
                elif filter_type == 3:
                    predictor = (left + up) // 2
                else:
                    estimate = left + up - upper_left
                    left_distance = abs(estimate - left)
                    up_distance = abs(estimate - up)
                    upper_left_distance = abs(estimate - upper_left)
                    if left_distance <= up_distance and left_distance <= upper_left_distance:
                        predictor = left
                    elif up_distance <= upper_left_distance:
                        predictor = up
                    else:
                        predictor = upper_left
                reconstructed[index] = (value + predictor) & 0xFF

            assert palette_entries is not None
            if bit_depth == 8:
                if any(
                    sample >= palette_entries
                    for sample in reconstructed[:pass_width]
                ):
                    return "indexed PNG pixel references a missing PLTE entry"
            else:
                samples_per_byte = 8 // bit_depth
                mask = (1 << bit_depth) - 1
                sample_count = 0
                for byte in reconstructed:
                    for sample_index in range(samples_per_byte):
                        shift = 8 - bit_depth * (sample_index + 1)
                        sample = (byte >> shift) & mask
                        if sample >= palette_entries:
                            return (
                                "indexed PNG pixel references a missing PLTE entry"
                            )
                        sample_count += 1
                        if sample_count == pass_width:
                            break
                    if sample_count == pass_width:
                        break

            previous = reconstructed
            row_offset += 1 + row_bytes
    return None


def _path_is_within(candidate: Path, root: Path) -> bool:
    try:
        candidate.relative_to(root)
        return True
    except ValueError:
        return False


def _lab_image_path_error(rel: str) -> str | None:
    """Return an error string when ``rel`` is not a safe relative POSIX PNG path."""
    if not isinstance(rel, str) or not rel:
        return "path must be a non-empty string"
    if "\\" in rel:
        return f"path {rel!r} must use forward slashes, not backslashes"
    if len(rel) >= 2 and rel[1] == ":":
        return f"path {rel!r} must be relative (no drive letter)"
    posix = PurePosixPath(rel)
    if posix.is_absolute() or PureWindowsPath(rel).is_absolute():
        return f"path {rel!r} must be relative (no leading '/')"
    for part in posix.parts:
        if part in ("", ".", ".."):
            return f"path {rel!r} must not contain '.' or '..' segments"
    if posix.suffix != ".png":
        return f"path {rel!r} must reference a lowercase '.png' file"
    return None


def _lab_captured_utc_error(value: object) -> str | None:
    if not isinstance(value, str) or not value:
        return "must be a non-empty ISO-8601 UTC timestamp"
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return f"{value!r} is not a valid ISO-8601 timestamp"
    if parsed.tzinfo is None or parsed.utcoffset() != timedelta(0):
        return f"{value!r} must be in UTC (end with 'Z' or '+00:00')"
    return None


def _lab_sensitive_text_error(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    for label, pattern in LAB_EVIDENCE_SENSITIVE_PATTERNS:
        if pattern.search(value):
            return f"contains a sensitive {label}; redact it before committing"
    return None


def validate_lab_evidence(slug: str, solution_dir: Path, evidence: dict) -> list[str]:
    """Validate a solution's evidence manifest. Returns actionable error strings.

    Runs identically in write and ``--check`` modes: it only reads the source
    PNG bytes (for hashing) and never reads generated/destination artifacts.
    """
    prefix = f"{slug}/docs/{LAB_EVIDENCE_MANIFEST_NAME}"
    errors: list[str] = []

    if "__parse_error__" in evidence:
        return [f"{prefix}: invalid JSON: {evidence['__parse_error__']}"]

    validator = Draft202012Validator(load_lab_evidence_schema())
    schema_errors = sorted(validator.iter_errors(evidence), key=lambda e: list(e.path))
    for err in schema_errors:
        loc = "/".join(map(str, err.absolute_path)) or "(root)"
        errors.append(f"{prefix}: schema error at {loc}: {err.message}")
    if schema_errors:
        # Shape is invalid; deeper filesystem/hash checks would be misleading.
        return errors

    solution_field = evidence.get("solution")
    if solution_field is not None and solution_field != slug:
        errors.append(
            f"{prefix}: solution {solution_field!r} must equal folder name {slug!r}"
        )
    notes_error = _lab_sensitive_text_error(evidence.get("notes"))
    if notes_error:
        errors.append(f"{prefix}: notes {notes_error}")

    docs_root = (solution_dir / "docs").resolve()
    img_dir = solution_dir / "docs" / LAB_IMG_DIRNAME
    img_root = img_dir.resolve()
    img_root_is_trusted = _path_is_within(img_root, docs_root)
    if not img_root_is_trusted:
        errors.append(
            f"{prefix}: {slug}/docs/{LAB_IMG_DIRNAME} resolves outside "
            f"the solution docs directory"
        )
    seen: dict[str, int] = {}
    seen_ci: dict[str, tuple[int, str]] = {}
    listed_sources: set[Path] = set()

    for idx, image in enumerate(evidence.get("images", [])):
        loc = f"{prefix}: images[{idx}]"
        rel = image.get("path", "")
        for field_name in ("path", "caption", "alt"):
            text_error = _lab_sensitive_text_error(image.get(field_name))
            if text_error:
                errors.append(f"{loc}: {field_name} {text_error}")
        path_error = _lab_image_path_error(rel)
        if path_error:
            errors.append(f"{loc}: {path_error}")
            continue

        if rel in seen:
            errors.append(
                f"{loc}: duplicate image path {rel!r} (already declared at images[{seen[rel]}])"
            )
            continue
        lowered = rel.lower()
        if lowered in seen_ci:
            prior_idx, prior_rel = seen_ci[lowered]
            errors.append(
                f"{loc}: path {rel!r} collides case-insensitively with "
                f"{prior_rel!r} at images[{prior_idx}]; rename for "
                f"Windows/Linux portability"
            )
            continue
        seen[rel] = idx
        seen_ci[lowered] = (idx, rel)

        source = img_dir / PurePosixPath(rel)
        resolved_source = source.resolve()
        if (
            not img_root_is_trusted
            or not _path_is_within(resolved_source, img_root)
            or not _path_is_within(resolved_source, docs_root)
        ):
            errors.append(
                f"{loc}: path {rel!r} resolves outside {slug}/docs/{LAB_IMG_DIRNAME}"
            )
            continue

        captured_error = _lab_captured_utc_error(image.get("capturedUtc"))
        if captured_error:
            errors.append(f"{loc}: capturedUtc {captured_error}")

        if not source.exists():
            errors.append(f"{loc}: source image not found: {slug}/docs/{LAB_IMG_DIRNAME}/{rel}")
            continue
        if not source.is_file():
            errors.append(
                f"{loc}: source is not a regular file: {slug}/docs/{LAB_IMG_DIRNAME}/{rel}"
            )
            continue

        # Manifest-listed source (tracked so it is not double-flagged below).
        listed_sources.add(resolved_source)

        try:
            data = _read_lab_png_bytes(source)
        except (OSError, LabEvidenceError) as exc:
            errors.append(f"{loc}: cannot read source {slug}/docs/{LAB_IMG_DIRNAME}/{rel}: {exc}")
            continue

        structure_error = _validate_png_structure(data)
        if structure_error:
            errors.append(
                f"{loc}: source is not a valid PNG ({structure_error}): "
                f"{slug}/docs/{LAB_IMG_DIRNAME}/{rel}"
            )
            continue

        actual = hashlib.sha256(data).hexdigest()
        declared = image.get("sha256", "")
        if actual != declared:
            errors.append(
                f"{loc}: sha256 mismatch for {rel} "
                f"(manifest {declared!r}, actual {actual!r})"
            )

    # No unmanifested PNG may sit under <slug>/docs/img.
    if img_dir.is_dir():
        for found in sorted(img_dir.rglob("*")):
            if not found.is_file() or found.suffix.lower() != ".png":
                continue
            if found.resolve() not in listed_sources:
                rel = found.resolve().relative_to(img_root).as_posix()
                errors.append(
                    f"{prefix}: unmanifested PNG under {slug}/docs/{LAB_IMG_DIRNAME}: {rel} "
                    f"(add it to the manifest or remove it)"
                )

    return errors


def publish_lab_images(
    slug: str,
    solution_dir: Path,
    dest_solution_dir: Path,
    trusted_dest_root: Path,
    evidence: dict,
) -> list[Path]:
    """WRITE-MODE ONLY: publish allow-listed PNG bytes into the generated site.

    The generated ``site-docs/solutions/<slug>/img`` subtree is owned solely by
    this evidence publisher. Removes any stale generated ``img`` content for the
    slug first, then for each manifest-listed PNG reads the source bytes ONCE,
    re-validates PNG structure and the declared SHA-256 against those exact
    bytes, and writes those exact bytes to the destination. Reading once and
    writing the validated buffer closes the validate-then-copy TOCTOU window: a
    source mutated after the earlier validation pass fails here (raising
    ``LabEvidenceError``) BEFORE any mismatched destination byte is written.
    Deliberately isolated from ``write_if_changed`` / ``check_only`` so image
    bytes never pass through the UTF-8 text comparison pipeline.
    """
    src_img_dir = solution_dir / "docs" / LAB_IMG_DIRNAME
    docs_root = (solution_dir / "docs").resolve()
    src_img_root = src_img_dir.resolve()
    if not _path_is_within(src_img_root, docs_root):
        raise LabEvidenceError(
            f"{slug}/docs/{LAB_IMG_DIRNAME}: image root resolves outside "
            "the solution docs directory"
        )
    resolved_dest_solution = _confined_destination(
        dest_solution_dir, trusted_dest_root
    )
    dest_img_dir = resolved_dest_solution / LAB_IMG_DIRNAME
    _confined_destination(dest_img_dir, trusted_dest_root)
    if dest_img_dir.exists():
        shutil.rmtree(dest_img_dir)

    published: list[Path] = []
    for image in evidence.get("images", []):
        rel = PurePosixPath(image["path"])
        source = src_img_dir / rel
        resolved_source = source.resolve()
        if (
            not _path_is_within(resolved_source, src_img_root)
            or not _path_is_within(resolved_source, docs_root)
        ):
            raise LabEvidenceError(
                f"{slug}/docs/{LAB_IMG_DIRNAME}/{rel}: source resolves outside "
                "the solution docs directory"
            )
        data = _read_lab_png_bytes(source)

        structure_error = _validate_png_structure(data)
        if structure_error:
            raise LabEvidenceError(
                f"{slug}/docs/{LAB_IMG_DIRNAME}/{rel}: source changed after "
                f"validation and is no longer a valid PNG ({structure_error})"
            )
        actual = hashlib.sha256(data).hexdigest()
        declared = image.get("sha256", "")
        if actual != declared:
            raise LabEvidenceError(
                f"{slug}/docs/{LAB_IMG_DIRNAME}/{rel}: source changed after "
                f"validation; SHA-256 mismatch (manifest {declared!r}, actual {actual!r})"
            )

        dest = dest_img_dir / rel
        _confined_destination(dest.parent, trusted_dest_root)
        if dest.exists() and _is_reparse_point(dest):
            raise LabEvidenceError(f"destination path is a reparse point: {dest}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        published.append(dest)
    return published


def remove_published_lab_images(
    dest_solution_dir: Path, trusted_dest_root: Path
) -> bool:
    """Remove the generated evidence ``img`` subtree for a slug (publisher-owned).

    Used in write mode to clean up after a solution's evidence manifest is
    deleted, so a removed manifest never leaves stale published images behind.
    Returns True when a subtree was removed.
    """
    resolved_dest_solution = _confined_destination(
        dest_solution_dir, trusted_dest_root
    )
    dest_img_dir = resolved_dest_solution / LAB_IMG_DIRNAME
    _confined_destination(dest_img_dir, trusted_dest_root)
    if dest_img_dir.exists():
        shutil.rmtree(dest_img_dir)
        return True
    return False


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------
def write_if_changed(path: Path, content: str, drift: list[str]) -> None:
    """Write file; record into drift list if content differs from existing."""
    existing = path.read_text(encoding="utf-8") if path.is_file() else None
    if existing != content:
        drift.append(str(path.relative_to(ROOT)))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def check_only(path: Path, content: str, drift: list[str]) -> None:
    existing = path.read_text(encoding="utf-8") if path.is_file() else None
    if existing != content:
        drift.append(str(path.relative_to(ROOT)))


def run(check: bool) -> int:
    log.info("Loading framework controls...")
    framework_pillars = load_framework_controls()
    framework_titles = load_framework_control_titles()
    log.info("  framework controls: %d", len(framework_pillars))

    log.info("Loading solution manifests...")
    manifests = load_manifests()
    log.info("  manifests loaded: %d", len(manifests))

    errors = validate_manifests(manifests, framework_pillars)
    errors.extend(validate_solution_readme_headers(manifests))

    # Validate optional lab-validation evidence image manifests (both modes).
    lab_evidence: dict[str, dict] = {}
    for slug in manifests:
        evidence = load_lab_evidence(slug)
        if evidence is None:
            continue
        evidence_errors = validate_lab_evidence(slug, ROOT / slug, evidence)
        errors.extend(evidence_errors)
        if not evidence_errors:
            lab_evidence[slug] = evidence

    if errors:
        for e in errors:
            log.error(e)
        return 1

    drift: list[str] = []
    record = check_only if check else (lambda p, c, d: write_if_changed(p, c, d))

    # Pre-scan sub-docs (need filenames for detail pages)
    sub_docs_per_slug: dict[str, list[str]] = {}
    sub_doc_pending: dict[Path, str] = {}
    for slug in manifests:
        names, pending = copy_sub_docs(slug, write_files=False)
        sub_docs_per_slug[slug] = names
        sub_doc_pending.update(pending)

    # 1. solutions.json
    sj = emit_solutions_json(manifests)
    record(SOLUTIONS_JSON, sj, drift)

    # 1b. Per-solution controls-covered.json
    for slug, m in manifests.items():
        cc = emit_controls_covered_json(slug, m)
        record(ROOT / slug / "controls-covered.json", cc, drift)

    # 2. README table block
    if README.is_file():
        original = README.read_text(encoding="utf-8")
        new_block = emit_readme_table(manifests)
        new_readme = replace_block(original, SOLUTIONS_BEGIN, SOLUTIONS_END, new_block)
        record(README, new_readme, drift)

    # 2b. Solution README control blocks (opt-in via markers)
    for slug, m in manifests.items():
        pending = sync_solution_readme_controls(slug, m, framework_titles)
        if pending is None:
            continue
        path, content = pending
        record(path, content, drift)

    # 3. Site catalog
    record(SITE_CATALOG, emit_site_catalog(manifests), drift)

    # 4. Per-solution detail pages
    for slug, m in manifests.items():
        page = emit_solution_detail(slug, m, sub_docs_per_slug.get(slug, []))
        record(SOLUTIONS_OUT / slug / "index.md", page, drift)

    # 5. Sub-docs (regenerated)
    for path, content in sub_doc_pending.items():
        record(path, content, drift)

    # 5b. DEPLOYMENT-GUIDE: regenerate deploy-layers and zone-roadmap blocks
    #     before copying to site-docs so the copy reflects the updated content.
    deployment_overrides: dict[Path, str] = {}
    if DEPLOYMENT_GUIDE.is_file():
        original = DEPLOYMENT_GUIDE.read_text(encoding="utf-8")
        updated = original
        layers_block = emit_deploy_layers_block(manifests)
        updated = replace_block(updated, DEPLOY_LAYERS_BEGIN, DEPLOY_LAYERS_END, layers_block)
        roadmap_block = emit_zone_roadmap_block(manifests)
        updated = replace_block(updated, ZONE_ROADMAP_BEGIN, ZONE_ROADMAP_END, roadmap_block)
        record(DEPLOYMENT_GUIDE, updated, drift)
        deployment_overrides[DEPLOYMENT_GUIDE] = updated

    # 6. Root doc copy
    root_doc_pending = copy_root_docs(
        write_files=False,
        slugs=set(manifests),
        overrides=deployment_overrides,
    )
    for path, content in root_doc_pending.items():
        record(path, content, drift)

    # 7. Control mapping
    cm = emit_control_mapping(manifests, framework_pillars, framework_titles)
    record(CONTROL_MAPPING, cm, drift)

    # 8. Hero metrics block in site index
    if SITE_INDEX.is_file():
        original = SITE_INDEX.read_text(encoding="utf-8")
        new_block = emit_hero_metrics_block(manifests, framework_pillars)
        new_index = replace_block(original, HERO_BEGIN, HERO_END, new_block)
        record(SITE_INDEX, new_index, drift)

    # In write mode, ensure stale per-solution detail dirs (for slugs no longer
    # present) are removed. We DO NOT touch site-docs/solutions/index.md.
    if not check:
        valid_slugs = set(manifests)
        if SOLUTIONS_OUT.is_dir():
            for child in SOLUTIONS_OUT.iterdir():
                if child.is_dir() and child.name not in valid_slugs:
                    log.info("Removing stale solution dir: %s", child)
                    shutil.rmtree(child)

        # Lab-validation evidence images. The generated
        # site-docs/solutions/<slug>/img subtree is owned exclusively by the
        # evidence publisher: publish allow-listed PNGs for slugs that ship a
        # manifest, and remove any stale generated img subtree for slugs without
        # one (e.g. after a manifest is deleted). Binary-safe; not part of the
        # text drift contract (the destination lives under git-ignored site-docs).
        for slug in manifests:
            dest_dir = SOLUTIONS_OUT / slug
            if slug in lab_evidence:
                try:
                    published = publish_lab_images(
                        slug,
                        ROOT / slug,
                        dest_dir,
                        SOLUTIONS_OUT,
                        lab_evidence[slug],
                    )
                except LabEvidenceError as exc:
                    log.error("%s", exc)
                    return 1
                if published:
                    log.info(
                        "Published %d lab evidence image(s) for %s",
                        len(published),
                        slug,
                    )
            elif remove_published_lab_images(dest_dir, SOLUTIONS_OUT):
                log.info("Removed stale evidence img subtree (no manifest) for %s", slug)

    if check:
        if drift:
            log.error("Drift detected in %d generated artifact(s):", len(drift))
            for d in drift:
                log.error("  - %s", d)
            log.error(
                "Run `python scripts/build-manifest.py` and commit the changes."
            )
            return 1
        log.info("OK: all generated artifacts match manifests.")
        return 0

    log.info("Build complete: wrote %d generated artifacts.", len(drift))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate manifests + assert no drift in generated artifacts.",
    )
    args = parser.parse_args()
    return run(check=args.check)


if __name__ == "__main__":
    sys.exit(main())
