"""Validate repository content against the FSI language rules."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path, PurePosixPath


COMPLIANCE_PATTERNS = re.compile(
    r"ensures compliance|guarantees compliance|guarantee compliance|"
    r"will prevent|eliminates risk"
)
LEGACY_PRODUCT_NAME = re.compile(r"\bAzure" + r" AD\b")
COMPLIANCE_SUFFIXES = {".md"}
PRODUCT_SUFFIXES = {".json", ".kql", ".md", ".ps1", ".psm1", ".py", ".yaml", ".yml"}
EXCLUDED_DIRS = {".git", ".github", "research", "site", "site-docs"}
EXCLUDED_PRODUCT_DIRS = EXCLUDED_DIRS | {"files"}
EXCLUDED_NAMES = {
    "AGENTS.md",
    "CHANGELOG.md",
    "CLAUDE.md",
    "SECURITY.md",
    "THREAT-MODEL.md",
}
LEGACY_NAME_EXCEPTION = "agent-365-lifecycle-governance/.ralph-config.json"


def tracked_files(root: Path) -> list[Path]:
    """Return tracked repository files."""
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        check=True,
        capture_output=True,
    )
    names = result.stdout.decode("utf-8", "replace").split("\0")
    return [root / name for name in names if name]


def is_excluded(relative: PurePosixPath, product_rule: bool = False) -> bool:
    """Return whether a path is exempt from a language rule."""
    excluded_dirs = EXCLUDED_PRODUCT_DIRS if product_rule else EXCLUDED_DIRS
    return relative.name in EXCLUDED_NAMES or any(
        part in excluded_dirs for part in relative.parts
    )


def scan(root: Path) -> list[str]:
    """Return formatted language-rule violations."""
    violations: list[str] = []
    for path in tracked_files(root):
        if not path.is_file():
            continue
        relative = PurePosixPath(path.relative_to(root).as_posix())
        suffix = path.suffix.lower()
        if suffix not in COMPLIANCE_SUFFIXES | PRODUCT_SUFFIXES:
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeDecodeError):
            continue

        if suffix in COMPLIANCE_SUFFIXES and not is_excluded(relative):
            for line_number, line in enumerate(lines, start=1):
                if COMPLIANCE_PATTERNS.search(line):
                    violations.append(
                        f"{relative}:{line_number}: prohibited compliance phrase: "
                        f"{line.strip()[:160]}"
                    )

        if (
            suffix in PRODUCT_SUFFIXES
            and relative.as_posix() != LEGACY_NAME_EXCEPTION
            and not is_excluded(relative, product_rule=True)
        ):
            for line_number, line in enumerate(lines, start=1):
                if LEGACY_PRODUCT_NAME.search(line):
                    violations.append(
                        f"{relative}:{line_number}: use 'Microsoft Entra ID': "
                        f"{line.strip()[:160]}"
                    )
    return violations


def main() -> int:
    root = Path.cwd().resolve()
    violations = scan(root)
    if violations:
        print("Language rule violations found:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print("OK: repository content satisfies the FSI language rules.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
