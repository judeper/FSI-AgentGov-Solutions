#!/usr/bin/env python3
"""Lint Dataverse logical-name existence in OData query contexts.

Per CLAUDE.md, Dataverse logical-name drift is a common source of runtime
400 Bad Request failures. This linter complements scripts/lint-odata-columns.py:
that script is a spell checker for snake_case-looking `fsi_` tokens, while this
one verifies that Dataverse LogicalName/entity-set tokens in OData contexts are
declared by the solution's `create_*_dataverse_schema.py` script. It loads
schema tokens, lowercases them, and reports unknown `fsi_` references found in
`$select`, `$filter`, `$expand`, `$orderby`, `$apply`, Web API paths,
`"LogicalName"` JSON values, and PowerShell `-LogicalName` parameters. Add
baseline escape hatches to `scripts/.odata-existence-allowlist.txt` (one token
per line; `#` comments allowed) for known platform or navigation names while
the report-only baseline is triaged.

Usage:
    python scripts/lint-odata-existence.py
    python scripts/lint-odata-existence.py --strict
    python scripts/lint-odata-existence.py --solution agent-registry-automation
    python scripts/lint-odata-existence.py --cross-solution-ok
"""
from __future__ import annotations

import argparse
import ast
import logging
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

ROOT = Path(__file__).resolve().parent.parent
ALLOWLIST_PATH = ROOT / "scripts" / ".odata-existence-allowlist.txt"

LOGGER = logging.getLogger(__name__)

# Any fsi-prefixed token in an OData context, including Dataverse lookup value
# projections such as _fsi_agentid_value.
ODATA_FSI_TOKEN = re.compile(r"(?<![A-Za-z0-9])_?fsi_[a-z0-9_]+(?:_value)?\b", re.IGNORECASE)

# Existing scripts/lint-odata-columns.py owns these spell-check findings. E4
# skips them when they are not otherwise declared to avoid duplicate reports.
SNAKE_FSI_TOKEN = re.compile(r"\bfsi_[a-z][a-z0-9]*(?:_[a-z][a-z0-9]*)+\b", re.IGNORECASE)
LOOKUP_VALUE_TOKEN = re.compile(r"^_fsi_([a-z0-9]+)_value$", re.IGNORECASE)
SCHEMA_FSI_TOKEN = re.compile(r"(?<![A-Za-z0-9_])fsi_[A-Za-z0-9_]+")

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
SKIP_DIRS = {
    ".git",
    "site",
    "site-docs",
    "__pycache__",
    ".venv",
    "venv",
    "node_modules",
    "files",
    "research",
}

BUILT_IN_ALLOWLIST = {
    # Standard Dataverse system columns.
    "createdon",
    "modifiedon",
    "createdby",
    "modifiedby",
    "owninguser",
    "owningteam",
    "owningbusinessunit",
    "versionnumber",
    "statecode",
    "statuscode",
    "overriddencreatedon",
    "importsequencenumber",
    "timezoneruleversionnumber",
    "utcconversiontimezonecode",
    # Activity table columns commonly used in Dataverse queries.
    "activityid",
    "subject",
    "regardingobjectid",
    "activitytypecode",
}


@dataclass(frozen=True)
class ContextToken:
    """An OData-context token discovered in a file or text buffer."""

    line: int
    token: str


@dataclass(frozen=True)
class Finding:
    """Unknown Dataverse token found in an OData context."""

    line: int
    token: str
    suggestions: tuple[str, ...]


def discover_solutions(root: Path = ROOT) -> list[Path]:
    """Return solution directories that contain a manifest.yaml file."""
    solutions: list[Path] = []
    for child in sorted(root.iterdir()):
        if not child.is_dir() or child.name.startswith("."):
            continue
        if child.name in SKIP_DIRS:
            continue
        if (child / "manifest.yaml").is_file():
            solutions.append(child)
    return solutions


def schema_scripts(solution: Path) -> list[Path]:
    """Return Dataverse schema scripts for a solution."""
    scripts_dir = solution / "scripts"
    if not scripts_dir.is_dir():
        return []
    return sorted(scripts_dir.glob("create_*_dataverse_schema.py"))


def _resolve_string_node(node: ast.AST, constants: dict[str, str]) -> str | None:
    """Resolve simple string AST nodes, including f-strings with constants."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.JoinedStr):
        parts: list[str] = []
        for value in node.values:
            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                parts.append(value.value)
                continue
            if isinstance(value, ast.FormattedValue):
                resolved = _resolve_string_node(value.value, constants)
                if resolved is None:
                    return None
                parts.append(resolved)
                continue
            return None
        return "".join(parts)
    if isinstance(node, ast.Name):
        return constants.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _resolve_string_node(node.left, constants)
        right = _resolve_string_node(node.right, constants)
        if left is not None and right is not None:
            return left + right
    return None


def _module_string_constants(tree: ast.Module) -> dict[str, str]:
    """Return simple module-level string constants by variable name."""
    constants: dict[str, str] = {}
    for node in tree.body:
        if isinstance(node, ast.Assign):
            resolved = _resolve_string_node(node.value, constants)
            if resolved is None:
                continue
            for target in node.targets:
                if isinstance(target, ast.Name):
                    constants[target.id] = resolved
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            resolved = _resolve_string_node(node.value, constants) if node.value else None
            if resolved is not None:
                constants[node.target.id] = resolved
    return constants


def _extract_schema_tokens(value: str) -> set[str]:
    """Extract lowercased fsi-prefixed schema tokens from a string value."""
    return {match.group(0).lower() for match in SCHEMA_FSI_TOKEN.finditer(value)}


class _SchemaTokenCollector(ast.NodeVisitor):
    """Collect fsi-prefixed schema tokens from string literals and f-strings."""

    def __init__(self, constants: dict[str, str]) -> None:
        self.constants = constants
        self.tokens: set[str] = set()

    def visit_Constant(self, node: ast.Constant) -> None:  # noqa: N802 - ast API
        if isinstance(node.value, str):
            self.tokens.update(_extract_schema_tokens(node.value))

    def visit_JoinedStr(self, node: ast.JoinedStr) -> None:  # noqa: N802 - ast API
        resolved = _resolve_string_node(node, self.constants)
        if resolved is not None:
            self.tokens.update(_extract_schema_tokens(resolved))
        # Do not generic-visit: unresolved f-string chunks are often partial
        # names such as "_Title" and would produce misleading tokens.


def collect_schema_tokens_from_text(text: str, filename: str = "<schema>") -> set[str]:
    """Parse schema script text and return declared logical-name tokens."""
    try:
        tree = ast.parse(text, filename=filename)
    except SyntaxError as exc:
        LOGGER.warning("Skipping unparsable schema script %s: %s", filename, exc)
        return set()

    constants = _module_string_constants(tree)
    collector = _SchemaTokenCollector(constants)
    collector.visit(tree)
    return _with_entity_set_variants(collector.tokens)


def collect_schema_tokens(path: Path) -> set[str]:
    """Parse a schema script and return declared logical-name tokens."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        LOGGER.warning("Skipping unreadable schema script %s: %s", path, exc)
        return set()
    return collect_schema_tokens_from_text(text, filename=str(path))


def _pluralize_dataverse_name(logical_name: str) -> str:
    """Return a conservative Dataverse entity-set plural form."""
    if logical_name.endswith("y") and len(logical_name) > 1:
        return f"{logical_name[:-1]}ies"
    if logical_name.endswith(("s", "x", "z", "ch", "sh")):
        return f"{logical_name}es"
    return f"{logical_name}s"


def _with_entity_set_variants(tokens: Iterable[str]) -> set[str]:
    """Add likely entity-set names to the schema token set."""
    expanded: set[str] = set()
    for token in tokens:
        lowered = token.lower()
        expanded.add(lowered)
        if lowered.startswith("fsi_"):
            expanded.add(_pluralize_dataverse_name(lowered))
    return expanded


def load_solution_schema(solution: Path) -> set[str]:
    """Load all schema tokens declared by a solution's schema scripts."""
    tokens: set[str] = set()
    for script in schema_scripts(solution):
        tokens.update(collect_schema_tokens(script))
    return tokens


def load_allowlist(path: Path = ALLOWLIST_PATH) -> set[str]:
    """Load user-maintained allowlist tokens, if present."""
    if not path.is_file():
        return set()

    tokens: set[str] = set()
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        LOGGER.warning("Skipping unreadable allowlist %s: %s", path, exc)
        return set()

    for line in lines:
        token = line.split("#", 1)[0].strip().lower()
        if token:
            tokens.add(token)
    return tokens


def scan_text_for_odata_tokens(text: str) -> list[ContextToken]:
    """Return fsi-prefixed tokens found in supported OData contexts."""
    tokens: list[ContextToken] = []
    seen: set[tuple[int, str]] = set()

    for lineno, line in enumerate(text.splitlines(), start=1):
        # Existing lint-odata-columns.py owns explicit WRONG spelling examples.
        if "WRONG" in line and "fsi_" in line:
            continue

        snippets: list[str] = []
        snippets.extend(match.group(1) for match in ODATA_QUERY_KV.finditer(line))
        snippets.extend(match.group(1) for match in ODATA_PATH.finditer(line))
        snippets.extend(match.group(1) for match in LOGICAL_NAME_JSON.finditer(line))
        snippets.extend(match.group(1) for match in LOGICAL_NAME_PS.finditer(line))

        for snippet in snippets:
            for match in ODATA_FSI_TOKEN.finditer(snippet):
                token = match.group(0).lower()
                key = (lineno, token)
                if key in seen:
                    continue
                seen.add(key)
                tokens.append(ContextToken(line=lineno, token=token))

    return tokens


def scan_file_for_odata_tokens(path: Path) -> list[ContextToken]:
    """Return fsi-prefixed OData-context tokens from a file."""
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return []
    return scan_text_for_odata_tokens(text)


def _lookup_base(token: str) -> str | None:
    """Return the base logical name for _fsi_<name>_value lookup projections."""
    match = LOOKUP_VALUE_TOKEN.fullmatch(token)
    if not match:
        return None
    return f"fsi_{match.group(1)}"


def _compact_snake_token(token: str) -> str:
    """Compact a spell-linter-owned snake token into Dataverse logical form."""
    if not token.startswith("fsi_"):
        return token
    return "fsi_" + token[len("fsi_") :].replace("_", "")


def _is_allowed_token(
    token: str,
    local_schema: set[str],
    allowlist: set[str],
    all_schema: set[str],
    cross_solution_ok: bool,
) -> bool:
    """Return whether a token is known or intentionally out of E4 scope."""
    if token in BUILT_IN_ALLOWLIST or token in allowlist:
        return True
    if token in local_schema:
        return True

    lookup_base = _lookup_base(token)
    if lookup_base is not None:
        if lookup_base in local_schema or lookup_base in allowlist:
            return True
        return cross_solution_ok and lookup_base in all_schema

    if SNAKE_FSI_TOKEN.fullmatch(token):
        compact = _compact_snake_token(token)
        if compact in local_schema or compact in allowlist:
            return True
        if cross_solution_ok and compact in all_schema:
            return True
        # Defer snake_case spelling errors to scripts/lint-odata-columns.py.
        return True

    return cross_solution_ok and token in all_schema


def _common_prefix_length(left: str, right: str) -> int:
    """Return the length of the common prefix for two strings."""
    limit = min(len(left), len(right))
    index = 0
    while index < limit and left[index] == right[index]:
        index += 1
    return index


def matching_prefixes(token: str, available: set[str], limit: int = 3) -> tuple[str, ...]:
    """Return the best available-schema hints for an unknown token."""
    lookup_base = _lookup_base(token)
    needle = lookup_base or token
    scored = [
        (_common_prefix_length(needle, candidate), candidate)
        for candidate in available
        if candidate.startswith("fsi_")
    ]
    useful = [item for item in scored if item[0] >= len("fsi_") + 2]
    useful.sort(key=lambda item: (-item[0], item[1]))
    return tuple(candidate for _, candidate in useful[:limit])


def find_unknown_tokens(
    tokens: Sequence[ContextToken],
    local_schema: set[str],
    allowlist: set[str] | None = None,
    all_schema: set[str] | None = None,
    cross_solution_ok: bool = False,
) -> list[Finding]:
    """Return unknown-token findings for a sequence of OData-context tokens."""
    effective_allowlist = set(allowlist or set()) | BUILT_IN_ALLOWLIST
    effective_all_schema = all_schema or local_schema
    findings: list[Finding] = []
    for context_token in tokens:
        token = context_token.token.lower()
        if _is_allowed_token(
            token,
            local_schema=local_schema,
            allowlist=effective_allowlist,
            all_schema=effective_all_schema,
            cross_solution_ok=cross_solution_ok,
        ):
            continue
        findings.append(
            Finding(
                line=context_token.line,
                token=token,
                suggestions=matching_prefixes(token, local_schema),
            )
        )
    return findings


def _should_scan_file(path: Path) -> bool:
    """Return whether a path is in scope for OData existence linting."""
    if not path.is_file():
        return False
    if path.suffix.lower() not in SCAN_EXTS:
        return False
    return not any(part in SKIP_DIRS for part in path.parts)


def lint_solution(
    solution: Path,
    local_schema: set[str],
    allowlist: set[str],
    all_schema: set[str],
    cross_solution_ok: bool,
) -> tuple[int, int, dict[Path, int]]:
    """Lint one solution and return findings, scanned files, and per-file counts."""
    violations = 0
    scanned = 0
    clusters: dict[Path, int] = {}

    if not local_schema:
        LOGGER.info("Skipping %s because no Dataverse schema tokens were found", solution.name)
        return violations, scanned, clusters

    for path in solution.rglob("*"):
        if not _should_scan_file(path):
            continue
        scanned += 1
        findings = find_unknown_tokens(
            scan_file_for_odata_tokens(path),
            local_schema=local_schema,
            allowlist=allowlist,
            all_schema=all_schema,
            cross_solution_ok=cross_solution_ok,
        )
        if not findings:
            continue
        rel = path.relative_to(ROOT)
        clusters[rel] = clusters.get(rel, 0) + len(findings)
        for finding in findings:
            suggestions = ", ".join(finding.suggestions) if finding.suggestions else "none"
            print(
                f"{rel}:{finding.line}: unknown column `{finding.token}` in OData "
                f"context (solution: {solution.name}; available columns matching "
                f"prefix: {suggestions})"
            )
            violations += 1

    return violations, scanned, clusters


def _solution_schema_map(solutions: Iterable[Path]) -> dict[str, set[str]]:
    """Load schema tokens for each solution by slug."""
    return {solution.name: load_solution_schema(solution) for solution in solutions}


def main() -> int:
    """Run the OData existence linter."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--solution", help="Lint only this solution slug.")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero on any finding (default: report only).",
    )
    parser.add_argument(
        "--cross-solution-ok",
        action="store_true",
        help="Allow tokens declared by another solution's schema.",
    )
    args = parser.parse_args()

    logging.basicConfig(format="%(levelname)s: %(message)s", level=logging.INFO)

    solutions = discover_solutions()
    if args.solution:
        solutions = [solution for solution in solutions if solution.name == args.solution]
        if not solutions:
            print(f"No solution found with slug {args.solution!r}", file=sys.stderr)
            return 2

    schema_by_solution = _solution_schema_map(solutions)
    all_schema = set().union(*schema_by_solution.values()) if schema_by_solution else set()
    allowlist = load_allowlist()

    total_violations = 0
    total_scanned = 0
    total_clusters: dict[Path, int] = {}
    for solution in solutions:
        violations, scanned, clusters = lint_solution(
            solution,
            local_schema=schema_by_solution[solution.name],
            allowlist=allowlist,
            all_schema=all_schema,
            cross_solution_ok=args.cross_solution_ok,
        )
        total_violations += violations
        total_scanned += scanned
        for path, count in clusters.items():
            total_clusters[path] = total_clusters.get(path, 0) + count

    LOGGER.info(
        "odata-existence-lint: scanned %s files across %s solution(s); %s finding(s).",
        total_scanned,
        len(solutions),
        total_violations,
    )
    if total_clusters:
        top_files = sorted(total_clusters.items(), key=lambda item: (-item[1], str(item[0])))[:5]
        LOGGER.info(
            "top finding clusters: %s",
            "; ".join(f"{path} ({count})" for path, count in top_files),
        )

    if args.strict:
        return 1 if total_violations else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
