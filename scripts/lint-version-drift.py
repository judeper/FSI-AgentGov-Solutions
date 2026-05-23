"""Lint solution manifest versions against CHANGELOG release headers."""

from __future__ import annotations

import argparse
import logging
import re
import sys
from pathlib import Path
from typing import Any

import yaml

LOGGER = logging.getLogger(__name__)
VERSION_HEADING_RE = re.compile(r"^\s*##\s+\[(?P<version>v?\d+\.\d+\.\d+(?:-preview)?)\]")


def normalize_version(value: Any) -> str:
    """Return a comparable version string with one leading v/V removed."""
    version = str(value).strip()
    if version.lower().startswith("v"):
        return version[1:]
    return version


def load_manifest_version(manifest_path: Path) -> str | None:
    """Load and normalize manifest.yaml.version."""
    with manifest_path.open("r", encoding="utf-8") as handle:
        manifest = yaml.safe_load(handle) or {}
    version = manifest.get("version") if isinstance(manifest, dict) else None
    if version is None:
        return None
    return normalize_version(version)


def find_changelog_release(changelog_path: Path) -> tuple[str, int] | None:
    """Find the first non-Unreleased version heading in a CHANGELOG."""
    with changelog_path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if line.lstrip().startswith("<!--"):
                continue
            match = VERSION_HEADING_RE.match(line)
            if match:
                return normalize_version(match.group("version")), line_number
    return None


def lint_solution(solution_dir: Path) -> list[str]:
    """Return version drift findings for one solution directory."""
    slug = solution_dir.name
    manifest_path = solution_dir / "manifest.yaml"
    if not manifest_path.exists():
        return []

    manifest_version = load_manifest_version(manifest_path)
    if manifest_version is None:
        return [f"{slug}: manifest.yaml version missing"]

    changelog_path = solution_dir / "CHANGELOG.md"
    if not changelog_path.exists():
        return [f"{slug}: CHANGELOG.md missing (manifest={manifest_version})"]

    release = find_changelog_release(changelog_path)
    if release is None:
        return [
            f"{slug}: manifest={manifest_version} but "
            "CHANGELOG most-recent-release=<none: no release header found>"
        ]

    changelog_version, line_number = release
    if manifest_version != changelog_version:
        return [
            f"{slug}: manifest={manifest_version} but "
            f"CHANGELOG most-recent-release={changelog_version}  "
            f"(CHANGELOG.md:L{line_number})"
        ]

    return []


def iter_solution_dirs(root: Path, solution: str | None = None) -> list[Path]:
    """Return solution directories that contain manifest.yaml files."""
    if solution:
        candidate = root / solution
        return [candidate] if (candidate / "manifest.yaml").exists() else []

    return sorted(
        path
        for path in root.iterdir()
        if path.is_dir() and not path.name.startswith(".") and (path / "manifest.yaml").exists()
    )


def lint_repository(root: Path, solution: str | None = None) -> list[str]:
    """Return version drift findings for all matching solution directories."""
    findings: list[str] = []
    for solution_dir in iter_solution_dirs(root, solution):
        findings.extend(lint_solution(solution_dir))
    return findings


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Lint manifest.yaml.version values against CHANGELOG release headers."
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 when version drift findings are present.",
    )
    parser.add_argument(
        "--solution",
        help="Limit linting to a single solution slug.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Run the version drift linter."""
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s", stream=sys.stdout)

    findings = lint_repository(Path.cwd(), args.solution)
    for finding in findings:
        LOGGER.info("%s", finding)

    if args.strict and findings:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
