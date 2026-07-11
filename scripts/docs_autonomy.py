"""Classify whether a change requires the documentation autonomy gate."""

from __future__ import annotations

import argparse
from pathlib import PurePosixPath


DOC_EXTENSIONS = {".json", ".md", ".mdx", ".yaml", ".yml"}
DOC_PREFIXES = (
    ".github/instructions/",
    ".github/workflows/",
    "site-docs/",
)
DOC_FILES = {
    ".github/branch-protection.json",
    "mkdocs.yml",
    "requirements-docs.txt",
    "solutions.json",
    "scripts/build-manifest.py",
    "scripts/docs_autonomy.py",
    "scripts/lint-optionset-values.py",
    "scripts/lint-version-drift.py",
    "scripts/manifest.schema.json",
    "scripts/sync-agent-md-versions.py",
    "scripts/validate-language-rules.py",
    "scripts/verify_commercial_scope.py",
}


def normalize_path(value: str) -> str:
    """Return a repository-relative POSIX path."""
    return value.strip().replace("\\", "/").removeprefix("./")


def is_docs_relevant(value: str) -> bool:
    """Return whether a changed path affects documentation validation."""
    path = normalize_path(value)
    if not path:
        return False
    if path in DOC_FILES or path.startswith(DOC_PREFIXES):
        return True
    pure_path = PurePosixPath(path)
    return pure_path.suffix.lower() in DOC_EXTENSIONS or "docs" in pure_path.parts


def classify_paths(paths: list[str]) -> list[str]:
    """Return normalized documentation-relevant paths."""
    return sorted({normalize_path(path) for path in paths if is_docs_relevant(path)})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--changed-files",
        required=True,
        help="Newline-delimited repository-relative changed paths.",
    )
    parser.add_argument(
        "--github-output",
        help="Optional GitHub Actions output file.",
    )
    args = parser.parse_args()

    with open(args.changed_files, encoding="utf-8") as handle:
        matches = classify_paths(handle.read().splitlines())

    docs = "true" if matches else "false"
    print(f"docs={docs}")
    if matches:
        print("Documentation-relevant changes:")
        for path in matches:
            print(f"  {path}")
    else:
        print("No documentation-relevant changes; required context will shim-success.")

    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as handle:
            handle.write(f"docs={docs}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
