#!/usr/bin/env python3
"""Lint Dataverse logical-name references in OData query contexts only.

Per CLAUDE.md, the #1 source of runtime bugs is mis-spelled Dataverse logical
column names: code or docs writes `fsi_agent_id` (snake_case with underscores
between alpha segments) when the actual logical name is `fsi_agentid`
(SchemaName lowercased — Dataverse NEVER inserts underscores between words in
column or entity logical names).

This linter is intentionally narrow to keep signal high. It only flags tokens
that match `fsi_<alpha>_<alpha>...` AND appear inside one of these contexts:

  1. OData query parameters:  $select=...  $filter=...  $expand=...
                              $orderby=... $apply=...   $top=...
  2. OData entity-set URL paths:  /api/data/v9.X/fsi_<token>
  3. Explicit `"LogicalName"` JSON values, e.g.
        "LogicalName": "fsi_agent_id"
  4. PowerShell `-LogicalName` parameters, e.g.
        Get-CrmRecord -LogicalName fsi_agent_id

It deliberately does NOT flag:
  * Connection reference unique names (`fsi_cr_dataverse_xxx`) — Power
    Platform connection references legitimately use snake_case.
  * Environment variable schema names.
  * Free-form prose in markdown that mentions `fsi_*` outside an OData
    fragment (e.g., a sentence describing schema design).

Usage:
    python scripts/lint-odata-columns.py
    python scripts/lint-odata-columns.py --solution agent-registry-automation
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SNAKE_FSI_TOKEN = re.compile(r"\bfsi_[a-z][a-z0-9]*(?:_[a-z][a-z0-9]*)+\b")

# OData query parameters: capture the key=value pair so we can scan the value.
ODATA_QUERY_KV = re.compile(
    r"\$(?:select|filter|expand|orderby|apply|top|count|skip)=([^&'\"\s\)\]]+)",
    re.IGNORECASE,
)

# Web API entity-set path: /api/data/v9.x/<set>(...
ODATA_PATH = re.compile(
    r"/api/data/v9\.[0-9]+/(fsi_[a-z0-9_]+)",
    re.IGNORECASE,
)

# JSON LogicalName key value.
LOGICAL_NAME_JSON = re.compile(
    r'"LogicalName"\s*:\s*"(fsi_[a-z0-9_]+)"',
    re.IGNORECASE,
)

# PowerShell -LogicalName parameter.
LOGICAL_NAME_PS = re.compile(
    r"-LogicalName\s+['\"]?(fsi_[a-z0-9_]+)['\"]?",
    re.IGNORECASE,
)

SCAN_EXTS = {".ps1", ".psm1", ".md", ".py", ".kql"}
SKIP_DIRS = {".git", "site", "site-docs", "__pycache__", ".venv", "venv"}


def discover_solutions() -> list[Path]:
    solutions = []
    for child in sorted(ROOT.iterdir()):
        if not child.is_dir() or child.name.startswith("."):
            continue
        if child.name in SKIP_DIRS:
            continue
        if (child / "manifest.yaml").is_file():
            solutions.append(child)
    return solutions


def scan_file(path: Path) -> list[tuple[int, str, str]]:
    """Return (line, token, context-label) tuples for snake_case violations."""
    findings: list[tuple[int, str, str]] = []
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return findings

    for lineno, line in enumerate(text.splitlines(), start=1):
        # Skip lines that explicitly demonstrate the WRONG spelling (CLAUDE.md
        # rule documentation).
        if "WRONG" in line and "fsi_" in line:
            continue

        contexts: list[tuple[str, str]] = []  # (snippet, label)

        for m in ODATA_QUERY_KV.finditer(line):
            contexts.append((m.group(1), f"$query"))
        for m in ODATA_PATH.finditer(line):
            contexts.append((m.group(1), "Web API path"))
        for m in LOGICAL_NAME_JSON.finditer(line):
            contexts.append((m.group(1), "LogicalName JSON"))
        for m in LOGICAL_NAME_PS.finditer(line):
            contexts.append((m.group(1), "-LogicalName param"))

        for snippet, label in contexts:
            for token in SNAKE_FSI_TOKEN.findall(snippet):
                findings.append((lineno, token, label))

    return findings


def lint_solution(solution: Path) -> tuple[int, int]:
    violations = 0
    scanned = 0
    for path in solution.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in SCAN_EXTS:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        scanned += 1
        for lineno, token, label in scan_file(path):
            rel = path.relative_to(ROOT)
            print(
                f"::error file={rel},line={lineno}::"
                f"Dataverse logical-name '{token}' has underscores between alpha "
                f"segments (context: {label}). Logical names never insert "
                f"underscores between words. Verify against "
                f"create_*_dataverse_schema.py SchemaName.",
                file=sys.stderr,
            )
            violations += 1
    return violations, scanned


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--solution", help="Lint only this solution slug.")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero on any violation (default: report only).",
    )
    args = parser.parse_args()

    solutions = discover_solutions()
    if args.solution:
        solutions = [s for s in solutions if s.name == args.solution]
        if not solutions:
            print(f"No solution found with slug {args.solution!r}", file=sys.stderr)
            return 2

    total_violations = 0
    total_scanned = 0
    for sol in solutions:
        v, s = lint_solution(sol)
        total_violations += v
        total_scanned += s

    print(
        f"odata-lint: scanned {total_scanned} files across {len(solutions)} "
        f"solution(s); {total_violations} OData-context violation(s).",
        file=sys.stderr,
    )
    if args.strict:
        return 1 if total_violations else 0
    # Soft-gate: report-only until baseline is fixed. Flip to --strict in CI
    # once the 5 known violations (see CHANGELOG critique-remediation entry)
    # are resolved.
    return 0


if __name__ == "__main__":
    sys.exit(main())
