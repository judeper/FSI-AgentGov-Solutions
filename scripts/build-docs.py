#!/usr/bin/env python3
"""Build script for FSI-AgentGov-Solutions documentation site.

Runs before `mkdocs build` to:
  A. Auto-generate solution index.md files from READMEs
  B. Copy sub-docs with filename normalization
  C. Copy root docs (DEPLOYMENT-GUIDE.md, CHANGELOG.md)
  D. Validate all nav-referenced files exist
"""

import logging
import re
import shutil
import sys
from pathlib import Path

import yaml

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parent.parent
SITE_DOCS = ROOT / "site-docs"
SOLUTIONS_OUT = SITE_DOCS / "solutions"
CONFIG_PATH = ROOT / "scripts" / "solution-config.yml"
MKDOCS_PATH = ROOT / "mkdocs.yml"

# Changelog files to exclude from sub-doc copies
CHANGELOG_PATTERNS = {"acv-changelog.md", "alca-changelog.md"}

# GitHub blob base URL for rewriting relative links
GITHUB_BLOB = "https://github.com/judeper/FSI-AgentGov-Solutions/blob/main"


def load_config() -> dict:
    """Load solution-config.yml."""
    with open(CONFIG_PATH, encoding="utf-8") as f:
        return yaml.safe_load(f)


def normalize_filename(name: str) -> str:
    """Normalize a filename: lowercase, underscores to hyphens."""
    stem = Path(name).stem
    suffix = Path(name).suffix
    normalized = stem.lower().replace("_", "-")
    return normalized + suffix.lower()


def extract_sections(readme_text: str) -> dict[str, str]:
    """Extract sections from a README by ## headings.

    Returns a dict mapping lowercase heading text to section content.
    The 'preamble' key holds everything before the first ## heading.
    """
    sections = {}
    current_heading = "preamble"
    current_lines = []

    for line in readme_text.splitlines():
        if line.startswith("## "):
            # Save previous section
            sections[current_heading] = "\n".join(current_lines).strip()
            current_heading = line[3:].strip().lower()
            current_lines = []
        else:
            current_lines.append(line)

    # Save last section
    sections[current_heading] = "\n".join(current_lines).strip()
    return sections


def build_solution_index(
    solution_name: str, config: dict, domains: dict
) -> str:
    """Generate index.md content for a solution from its README."""
    readme_path = ROOT / solution_name / "README.md"
    if not readme_path.exists():
        log.warning("No README.md for %s", solution_name)
        return f"# {config['display_name']}\n\n*Documentation pending.*\n"

    readme_text = readme_path.read_text(encoding="utf-8")
    sections = extract_sections(readme_text)

    sol_config = config
    domain_label = domains.get(sol_config.get("domain", ""), "")
    controls = ", ".join(sol_config.get("controls", []))
    version = sol_config.get("version", "")

    # Build page
    lines = []

    # Title from README H1 or display_name
    h1_match = re.match(r"^#\s+(.+)", readme_text)
    title = h1_match.group(1) if h1_match else sol_config["display_name"]
    lines.append(f"# {title}")
    lines.append("")

    # Metadata badges
    badge_parts = []
    if version:
        badge_parts.append(f"**Version:** {version}")
    if domain_label:
        badge_parts.append(f"**Domain:** {domain_label}")
    if controls:
        badge_parts.append(f"**Controls:** {controls}")
    if badge_parts:
        lines.append(" | ".join(badge_parts))
        lines.append("")

    # Preamble (description before first ##)
    preamble = sections.get("preamble", "")
    if preamble:
        # Remove H1 line from preamble
        preamble_lines = preamble.splitlines()
        preamble_lines = [
            l for l in preamble_lines if not l.startswith("# ")
        ]
        preamble_text = "\n".join(preamble_lines).strip()
        if preamble_text:
            lines.append(preamble_text)
            lines.append("")

    # Standard sections to include
    section_order = [
        "overview",
        "features",
        "architecture",
        "quick start",
        "scope components",
        "zone requirements",
        "detection logic",
        "solution components",
        "configuration placeholders",
        "deployment",
        "prerequisites",
        "related controls",
        "regulatory alignment",
        "known limitations",
    ]

    for section_key in section_order:
        if section_key in sections and sections[section_key]:
            heading = section_key.title()
            lines.append(f"## {heading}")
            lines.append("")
            lines.append(sections[section_key])
            lines.append("")

    # Build filename map for link rewriting in README content
    docs_dir = ROOT / solution_name / "docs"
    filename_map = {}
    if docs_dir.exists():
        for f in docs_dir.iterdir():
            if f.suffix.lower() == ".md" and f.name.lower() not in CHANGELOG_PATTERNS:
                filename_map[f.name] = normalize_filename(f.name)

    # Rewrite links in all section content
    content_so_far = "\n".join(lines)
    content_so_far = rewrite_relative_links(
        content_so_far, solution_name, filename_map
    )
    lines = content_so_far.splitlines()

    # Documentation sub-pages table
    if docs_dir.exists():
        md_files = sorted(
            f
            for f in docs_dir.iterdir()
            if f.suffix.lower() == ".md"
            and f.name.lower() not in CHANGELOG_PATTERNS
        )
        if md_files:
            lines.append("## Documentation")
            lines.append("")
            lines.append("| Document | Description |")
            lines.append("|----------|-------------|")
            for md_file in md_files:
                norm_name = normalize_filename(md_file.name)
                display = (
                    norm_name.replace(".md", "")
                    .replace("-", " ")
                    .title()
                )
                lines.append(f"| [{display}]({norm_name}) | |")
            lines.append("")

    # GitHub source link
    lines.append("---")
    lines.append("")
    lines.append(
        f"[View source on GitHub]({GITHUB_BLOB}/{solution_name}/)"
        " { .md-button }"
    )
    lines.append("")

    # Final pass: rewrite any remaining relative .md links that won't exist
    # in site-docs to GitHub blob URLs
    result = "\n".join(lines)
    available_docs = set(filename_map.values())

    def fixup_unresolvable(match):
        prefix = match.group(1)
        path = match.group(2)
        suffix = match.group(3)
        # Skip external links and anchors
        if path.startswith(("http://", "https://", "#", "mailto:")):
            return match.group(0)
        # Only process .md links
        clean = path.split("#")[0]
        if not clean.endswith(".md"):
            return match.group(0)
        # Check if the target exists in our available docs
        basename = Path(clean).name
        if basename in available_docs:
            return match.group(0)
        # Convert to GitHub blob URL
        # Determine the best repo path
        if clean.startswith("docs/"):
            repo_path = f"{solution_name}/{clean}"
        elif "/" in clean:
            repo_path = f"{solution_name}/{clean}"
        else:
            repo_path = f"{solution_name}/docs/{clean}"
        anchor = ""
        if "#" in path:
            anchor = "#" + path.split("#", 1)[1]
        new_url = f"{GITHUB_BLOB}/{repo_path}{anchor}"
        log.info(
            "  Unresolvable link fixup [%s]: %s -> %s",
            solution_name,
            path,
            new_url,
        )
        return f"{prefix}{new_url}{suffix}"

    result = re.sub(r"(\[[^\]]*\]\()([^)]+)(\))", fixup_unresolvable, result)
    return result


def rewrite_relative_links(
    content: str, solution_name: str, filename_map: dict[str, str] | None = None,
) -> str:
    """Rewrite links in sub-docs:

    1. ../ links → GitHub blob URLs
    2. Intra-solution cross-references → normalized filenames
    3. docs/ prefix links → direct filename references

    Logs every rewrite for CI auditability.
    """
    if filename_map is None:
        filename_map = {}

    def replace_link(match):
        prefix = match.group(1)
        path = match.group(2)
        suffix = match.group(3)

        # 1. Parent directory links → GitHub blob URLs
        if path.startswith("../"):
            resolved = path.replace("../", "")
            new_url = f"{GITHUB_BLOB}/{resolved}"
            log.info(
                "  Link rewrite [%s]: %s -> %s", solution_name, path, new_url
            )
            return f"{prefix}{new_url}{suffix}"

        # Skip external links and anchors
        if path.startswith(("http://", "https://", "#", "mailto:")):
            return match.group(0)

        # 2. Strip docs/ prefix (links like docs/schema.md → schema.md)
        clean_path = path
        if clean_path.startswith("./"):
            clean_path = clean_path[2:]
        if clean_path.startswith("docs/"):
            clean_path = clean_path[5:]

        # 3. Normalize the filename part (preserve anchor)
        anchor = ""
        if "#" in clean_path:
            clean_path, anchor = clean_path.split("#", 1)
            anchor = "#" + anchor

        # Check if this filename needs normalization
        basename = Path(clean_path).name
        if basename in filename_map:
            new_name = filename_map[basename]
            new_path = new_name + anchor
            if new_path != path:
                log.info(
                    "  Cross-ref rewrite [%s]: %s -> %s",
                    solution_name,
                    path,
                    new_path,
                )
            return f"{prefix}{new_path}{suffix}"

        # Try normalizing directly
        norm = normalize_filename(basename)
        if norm != basename and clean_path.endswith(".md"):
            new_path = norm + anchor
            if new_path != path:
                log.info(
                    "  Cross-ref normalize [%s]: %s -> %s",
                    solution_name,
                    path,
                    new_path,
                )
            return f"{prefix}{new_path}{suffix}"

        # If docs/ prefix was stripped, update even if name didn't change
        if path != clean_path + anchor:
            new_path = clean_path + anchor
            log.info(
                "  Path rewrite [%s]: %s -> %s",
                solution_name,
                path,
                new_path,
            )
            return f"{prefix}{new_path}{suffix}"

        return match.group(0)

    # Match markdown links: [text](url)
    return re.sub(
        r"(\[[^\]]*\]\()([^)]+)(\))", replace_link, content
    )


def rewrite_root_doc_links(content: str, source_name: str) -> str:
    """Rewrite links in root docs (DEPLOYMENT-GUIDE, CHANGELOG) for site context."""
    def replace_link(match):
        prefix = match.group(1)
        path = match.group(2)
        suffix = match.group(3)
        # Rewrite relative solution links to site paths
        if path.startswith("./") or (
            not path.startswith("http") and "/" in path
        ):
            clean = path.lstrip("./")
            # Check if it's a solution link
            parts = clean.split("/")
            if len(parts) >= 1:
                new_url = f"{GITHUB_BLOB}/{clean}"
                log.info(
                    "  Root doc link rewrite [%s]: %s -> %s",
                    source_name,
                    path,
                    new_url,
                )
                return f"{prefix}{new_url}{suffix}"
        return match.group(0)

    return re.sub(r"(\[[^\]]*\]\()([^)]+)(\))", replace_link, content)


def copy_sub_docs(solution_name: str) -> int:
    """Copy and normalize docs from {solution}/docs/ to site-docs output.

    Returns number of files copied.
    """
    docs_dir = ROOT / solution_name / "docs"
    if not docs_dir.exists():
        return 0

    out_dir = SOLUTIONS_OUT / solution_name
    out_dir.mkdir(parents=True, exist_ok=True)

    # Build filename map: original name → normalized name
    filename_map = {}
    md_files = []
    for md_file in docs_dir.iterdir():
        if md_file.suffix.lower() != ".md":
            continue
        if md_file.name.lower() in CHANGELOG_PATTERNS:
            log.info("  Skipping changelog: %s/%s", solution_name, md_file.name)
            continue
        md_files.append(md_file)
        filename_map[md_file.name] = normalize_filename(md_file.name)

    copied = 0
    for md_file in md_files:
        norm_name = filename_map[md_file.name]
        content = md_file.read_text(encoding="utf-8")
        content = rewrite_relative_links(content, solution_name, filename_map)

        out_path = out_dir / norm_name
        out_path.write_text(content, encoding="utf-8")
        if norm_name != md_file.name:
            log.info(
                "  Normalized: %s/%s -> %s",
                solution_name,
                md_file.name,
                norm_name,
            )
        copied += 1

    return copied


def copy_root_docs() -> None:
    """Copy DEPLOYMENT-GUIDE.md and CHANGELOG.md into site-docs."""
    mappings = [
        (
            ROOT / "DEPLOYMENT-GUIDE.md",
            SITE_DOCS / "getting-started" / "deployment-guide.md",
        ),
        (ROOT / "CHANGELOG.md", SITE_DOCS / "reference" / "changelog.md"),
    ]

    for src, dst in mappings:
        if src.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            content = src.read_text(encoding="utf-8")
            content = rewrite_root_doc_links(content, src.name)
            dst.write_text(content, encoding="utf-8")
            log.info("Copied root doc: %s -> %s", src.name, dst.relative_to(ROOT))
        else:
            log.warning("Root doc not found: %s", src)


def collect_nav_files(nav_item, collected=None) -> list[str]:
    """Recursively collect all file paths from mkdocs nav structure."""
    if collected is None:
        collected = []

    if isinstance(nav_item, str):
        collected.append(nav_item)
    elif isinstance(nav_item, dict):
        for value in nav_item.values():
            collect_nav_files(value, collected)
    elif isinstance(nav_item, list):
        for item in nav_item:
            collect_nav_files(item, collected)

    return collected


def validate(config: dict) -> bool:
    """Validate build output: file counts and nav references."""
    ok = True

    # Check all 28 solution index.md files exist
    solution_indexes = list(SOLUTIONS_OUT.glob("*/index.md"))
    if len(solution_indexes) != 28:
        log.error(
            "Expected 28 solution index.md files, found %d",
            len(solution_indexes),
        )
        ok = False
    else:
        log.info("OK: 28 solution index.md files generated")

    # Check all nav-referenced files exist
    # Custom loader that ignores !!python/name tags (used by mkdocs for superfences)
    loader = yaml.SafeLoader
    loader.add_multi_constructor(
        "tag:yaml.org,2002:python/",
        lambda loader, suffix, node: None,
    )
    with open(MKDOCS_PATH, encoding="utf-8") as f:
        mkdocs_config = yaml.load(f, Loader=loader)  # noqa: S506

    nav = mkdocs_config.get("nav", [])
    nav_files = collect_nav_files(nav)

    missing = []
    for nav_file in nav_files:
        full_path = SITE_DOCS / nav_file
        if not full_path.exists():
            missing.append(nav_file)

    if missing:
        log.error("Missing nav-referenced files (%d):", len(missing))
        for m in missing:
            log.error("  - %s", m)
        ok = False
    else:
        log.info("OK: All %d nav-referenced files exist", len(nav_files))

    return ok


def main() -> int:
    """Run the full build pipeline."""
    log.info("Loading solution config...")
    config = load_config()
    solutions = config["solutions"]
    domains = config["domains"]

    log.info("Generating %d solution index pages...", len(solutions))
    for solution_name, sol_config in solutions.items():
        out_dir = SOLUTIONS_OUT / solution_name
        out_dir.mkdir(parents=True, exist_ok=True)

        index_content = build_solution_index(solution_name, sol_config, domains)
        index_path = out_dir / "index.md"
        index_path.write_text(index_content, encoding="utf-8")

    log.info("Copying sub-docs with normalization...")
    total_copied = 0
    for solution_name in solutions:
        copied = copy_sub_docs(solution_name)
        if copied:
            log.info("  %s: %d files", solution_name, copied)
        total_copied += copied
    log.info("Total sub-docs copied: %d", total_copied)

    log.info("Copying root docs...")
    copy_root_docs()

    log.info("Validating build output...")
    if not validate(config):
        log.error("Build validation failed!")
        return 1

    log.info("Build complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
