#!/usr/bin/env python3
"""Build script for FSI-AgentGov-Solutions — manifest-driven (v1.4.0+).

Walks every top-level folder, loads `manifest.yaml`, and emits the following
deterministic artifacts from a single source of truth:

* `solutions.json` (committed at repo root) — mirrors the framework
  `solutions-lock.json` schema 1:1 so `refresh_solutions_lock.py --tag v1.4.x`
  in fsi-agentgov can consume the tagged release directly.
* `README.md` solutions table inside `<!-- BEGIN:SOLUTIONS -->` /
  `<!-- END:SOLUTIONS -->` markers.
* `site-docs/solutions/index.md` — Solutions Catalog grouped by domain.
* `site-docs/solutions/<slug>/index.md` — per-solution detail page (35 of them).
* `site-docs/reference/control-mapping.md` — all 78 framework controls grouped
  by pillar; controls without solutions render "No solution yet".
* `site-docs/index.md` — hero metric counts derived from data (never hardcoded).
* Sub-doc copy from `<slug>/docs/*.md` to `site-docs/solutions/<slug>/` with
  filename normalization and intra-solution link rewriting.
* Root doc copy: `DEPLOYMENT-GUIDE.md` -> getting-started, `CHANGELOG.md` ->
  reference.

Validation runs on every invocation:

* JSON Schema (scripts/manifest.schema.json) for every manifest.
* `manifest.id` MUST equal the folder name.
* Every `controls[]` entry MUST exist in the framework `controls.json`
  (path resolved from FRAMEWORK_CONTROLS env var, defaulting to a sibling
  `fsi-agentgov` checkout).

Usage:

    python scripts/build-manifest.py            # write artifacts in place
    python scripts/build-manifest.py --check    # validate + assert no drift

Schema evolution policy
-----------------------

`solutions.json.schemaVersion` is `1.4.x` for this branch. The contract is
**additive-only** for the 1.4.x line: new optional fields MAY be introduced
in 1.4.1+ without bumping the framework lock contract. Any of the following
require a 1.5.0 bump AND a coordinated PR against fsi-agentgov:

* renaming an existing field
* removing or repurposing an existing field
* changing the JSON shape of an existing field (string -> object, etc.)
* adding a new REQUIRED field

This guarantee lets the framework pin `v1.4.0` and consume any later 1.4.x
patch release without code changes.
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import re
import shutil
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

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
README = ROOT / "README.md"
SITE_INDEX = SITE_DOCS / "index.md"
CONTROL_MAPPING = SITE_DOCS / "reference" / "control-mapping.md"
SITE_CATALOG = SOLUTIONS_OUT / "index.md"

GITHUB_BLOB = "https://github.com/judeper/FSI-AgentGov-Solutions/blob/main"
SITE_BASE = "https://judeper.github.io/FSI-AgentGov-Solutions"

SOLUTIONS_BEGIN = "<!-- BEGIN:SOLUTIONS -->"
SOLUTIONS_END = "<!-- END:SOLUTIONS -->"
HERO_BEGIN = "<!-- BEGIN:HERO_METRICS -->"
HERO_END = "<!-- END:HERO_METRICS -->"

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


# ---------------------------------------------------------------------------
# Emitters
# ---------------------------------------------------------------------------
def project_to_lock(m: dict) -> dict:
    """Project a manifest to the framework solutions-lock.json shape."""
    return {
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


def emit_solutions_json(
    manifests: dict[str, dict],
    schema_version: str = "1.4.1",
) -> str:
    """Return the canonical solutions.json content (deterministic)."""
    out = {
        "schemaVersion": schema_version,
        "generatedBy": "scripts/build-manifest.py",
        "solutions": {
            slug: project_to_lock(manifests[slug])
            for slug in sorted(manifests)
        },
    }
    # Pretty + stable: 2-space indent, sorted top keys preserved by insertion.
    return json.dumps(out, indent=2, ensure_ascii=False) + "\n"


def emit_readme_table(manifests: dict[str, dict]) -> str:
    """Generate the README solutions table block (between markers, inclusive)."""
    rows = []
    rows.append(SOLUTIONS_BEGIN)
    rows.append(f"<!-- Generated by scripts/build-manifest.py — do not edit by hand. -->")
    rows.append("")
    rows.append(f"This repository currently includes **{len(manifests)} live solution implementations**.")
    rows.append("")
    rows.append("| Solution | Description | Version | Controls |")
    rows.append("|----------|-------------|---------|----------|")
    for slug in sorted(manifests):
        m = manifests[slug]
        controls = ", ".join(m.get("controls", [])) or "—"
        rows.append(
            f"| [{m['name']}](./{slug}/) | {m['description']} | v{m['version']} | {controls} |"
        )
    rows.append("")
    rows.append(SOLUTIONS_END)
    return "\n".join(rows)


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
    by_domain: dict[str, list[str]] = defaultdict(list)
    for slug, m in manifests.items():
        by_domain[m["domain"]].append(slug)
    lines = [
        "# Solutions Catalog",
        "",
        f"{len(manifests)} live reference implementations organized by functional domain.",
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
        lines.append("| Solution | Description | Version | Controls |")
        lines.append("|----------|-------------|---------|----------|")
        for slug in slugs:
            m = manifests[slug]
            controls = ", ".join(m.get("controls", [])) or "—"
            lines.append(
                f"| [{m['name']}]({slug}/index.md) | {m['description']} | v{m['version']} | {controls} |"
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

    lines.append("## Coverage Summary")
    lines.append("")
    lines.append(f"- **Controls with implementations:** {mapped_count} of {total}")
    lines.append(f"- **Live solution folders:** {len(manifests)}")
    avg = (
        sum(len(m.get("controls", [])) for m in manifests.values()) / max(len(manifests), 1)
    )
    lines.append(f"- **Controls per solution (avg):** {avg:.1f}")
    lines.append("")
    lines.append("!!! info \"Framework Reference\"")
    lines.append("    Full control specifications are available in the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/controls/).")
    lines.append("")
    return "\n".join(lines)


def emit_hero_metrics_block(
    manifests: dict[str, dict],
    framework_pillars: dict[str, int],
) -> str:
    n_solutions = len(manifests)
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


def copy_root_docs(write_files: bool, slugs: set[str] | None = None) -> dict[Path, str]:
    pending: dict[Path, str] = {}
    mappings = [
        (ROOT / "DEPLOYMENT-GUIDE.md", SITE_DOCS / "getting-started" / "deployment-guide.md"),
        (ROOT / "CHANGELOG.md", SITE_DOCS / "reference" / "changelog.md"),
    ]
    for src, dst in mappings:
        if not src.is_file():
            continue
        content = src.read_text(encoding="utf-8")
        if slugs:
            content = _rewrite_root_doc_links(content, slugs)
        pending[dst] = content
        if write_files:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(content, encoding="utf-8")
    return pending


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

    # 2. README table block
    if README.is_file():
        original = README.read_text(encoding="utf-8")
        new_block = emit_readme_table(manifests)
        new_readme = replace_block(original, SOLUTIONS_BEGIN, SOLUTIONS_END, new_block)
        record(README, new_readme, drift)

    # 3. Site catalog
    record(SITE_CATALOG, emit_site_catalog(manifests), drift)

    # 4. Per-solution detail pages
    for slug, m in manifests.items():
        page = emit_solution_detail(slug, m, sub_docs_per_slug.get(slug, []))
        record(SOLUTIONS_OUT / slug / "index.md", page, drift)

    # 5. Sub-docs (regenerated)
    for path, content in sub_doc_pending.items():
        record(path, content, drift)

    # 6. Root doc copy
    root_doc_pending = copy_root_docs(write_files=False, slugs=set(manifests))
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
