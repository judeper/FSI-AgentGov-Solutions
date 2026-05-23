#!/usr/bin/env python3
"""Lint Dataverse Picklist option-set value ranges in schema scripts.

Dataverse convention: globally-managed Picklist option sets created with the
`fsi_` publisher prefix start at integer Value `100000000` and increment by 1.
Defining a Picklist with low values (0/1/2/3 ...) is the root cause of a class
of cross-solution drift bugs — most notably `cross-solution-integration`'s
`IntegrationConfig.psm1` zone-normalization map (lines 60-68) reads `fsi_acv_*`
options as 100000000+ while several schema scripts still emit 0-based values.

This linter is intentionally narrow (Phase 1):

  1. It scans only Dataverse schema scripts (`create_*_schema.py` and
     `create_dataverse_schema.py`).
  2. For each Picklist option-set definition (dict literal with an `Options`
     list child), it emits a finding when any `Value` < `100000000`.
  3. TwoOption / Boolean attributes are skipped — Dataverse contract for
     BooleanAttributeMetadata is Value:0 (False) / Value:1 (True), so the
     `TrueOption`/`FalseOption` shape is legitimate.
  4. Three allowlists suppress known-legitimate 0-based definitions:
        a) BOOLEAN_ATTR_TYPES — auto-detected via `OptionSetType` /
           `AttributeType` ("TwoOption", "Boolean").
        b) SHARED_ACV_OPTIONSETS — `fsi_acv_zone`, `fsi_acv_severity`.
           Per `style-decisions.md` §9 these are deferred for a coordinated
           cross-solution migration. Flagging them here would only generate
           noise until the cross-solution PR lands.
        c) INTERNALLY_CONSISTENT_OPTIONSETS — solution-prefixed picklists
           where the schema AND every consumer agree on the 0/1-based
           values (audited 2026-04). Examples: `compliance-dashboard`
           pillar/category/status/zone/severity sets, `rag-source-validator`
           sourcetype/sourcestatus/validationfrequency/validationresult/
           validationtype/changetype, `dr-testing-framework`
           teststatus (deferred to v2.1.0 per its CHANGELOG, tracked in
           `.ralph-config.json`).

A user-managed allowlist at `scripts/.optionset-values-allowlist.txt` accepts
one option-set logical name per line (`#` line comments allowed) so reviewers
can mark additional findings as known-acceptable without editing this script.

Phase 2 (future): scan consumer scripts (.ps1/.psm1/.py/.kql) for option-set
value literals and detect cross-solution drift (solution A defines set X
0-based; solution B reads set X as 100000000+). Deferred because the
cross-solution coupling map requires explicit declaration.

Usage:
    python scripts/lint-optionset-values.py
    python scripts/lint-optionset-values.py --strict
    python scripts/lint-optionset-values.py --solution agent-registry-automation
"""
from __future__ import annotations

import argparse
import ast
import logging
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parent.parent
ALLOWLIST_PATH = ROOT / "scripts" / ".optionset-values-allowlist.txt"

LOGGER = logging.getLogger(__name__)

DATAVERSE_PICKLIST_FLOOR = 100_000_000

# Boolean attribute markers (case-insensitive). When an OptionSet/Attribute
# dict declares one of these as its type, the Value:0 / Value:1 pair is the
# Dataverse contract for BooleanAttributeMetadata.
BOOLEAN_ATTR_TYPES = frozenset({"twooption", "boolean"})

# Style §9 deferred: shared `fsi_acv_*` sets are inconsistent across solutions
# (some define 0-based, some 100000000-based). The fix requires a coordinated
# cross-solution migration plus tenant-side re-key — out of scope for any single
# solution PR. Tracking source: style-decisions.md §9.
SHARED_ACV_OPTIONSETS = frozenset({
    "fsi_acv_zone",
    "fsi_acv_severity",
})

# Solution-internally-consistent 0-based picklists. Each is audited to confirm
# schema AND every consumer (PowerShell $filter, Python comparisons, KQL, docs)
# agree on the low-value convention. Migrating these is a BREAKING DEPLOY that
# is intentionally deferred. Adding to this list requires an audit trail.
#
#   compliance-dashboard (8 sets, all 1-based) — schema source: scripts/
#       create_cd_dataverse_schema.py; consumer source: same solution's
#       PowerShell scripts and dataverse-schema.md doc.
#   rag-source-validator (6 sets, all 1-based) — schema source: scripts/
#       create_rsv_dataverse_schema.py; consumer source: same solution's
#       docs/dataverse-schema.md and Python validator scripts.
#   dr-testing-framework (1 set, 1/2) — deferred to v2.1.0 per CHANGELOG;
#       tracked in .ralph-config.json (`fsi_drt_teststatus uses nonstandard
#       values 1=Pass and 2=Fail`).
INTERNALLY_CONSISTENT_OPTIONSETS = frozenset({
    # compliance-dashboard
    "fsi_cd_pillar",
    "fsi_cd_category",
    "fsi_cd_status",
    "fsi_cd_zone",
    "fsi_cd_severity",
    "fsi_cd_exceptionstatus",
    "fsi_cd_slastatus",
    "fsi_cd_evidencetype",
    # rag-source-validator
    "fsi_rsv_sourcetype",
    "fsi_rsv_sourcestatus",
    "fsi_rsv_validationfrequency",
    "fsi_rsv_validationresult",
    "fsi_rsv_validationtype",
    "fsi_rsv_changetype",
    # dr-testing-framework
    "fsi_drt_teststatus",
})

SKIP_DIRS = {".git", "site", "site-docs", "__pycache__", ".venv", "venv", "node_modules"}


@dataclass(frozen=True)
class OptionSetDefinition:
    """A Picklist option-set definition discovered in a schema script."""

    line: int
    name: str
    option_set_type: str
    low_values: tuple[int, ...]


@dataclass(frozen=True)
class Finding:
    """A flagged option-set definition."""

    path: Path
    definition: OptionSetDefinition


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
    """Return Dataverse schema scripts for a solution.

    Three naming conventions exist across the catalog (mirrors lint-odata-
    existence.py): `create_<slug>_dataverse_schema.py`, `create_<slug>_schema.py`,
    and `create_dataverse_schema.py` (slugless).
    """
    scripts_dir = solution / "scripts"
    if not scripts_dir.is_dir():
        return []
    matches: set[Path] = set()
    matches.update(scripts_dir.glob("create_*_schema.py"))
    matches.update(scripts_dir.glob("create_dataverse_schema.py"))
    return sorted(matches)


def _string_constant(node: ast.AST | None) -> str | None:
    """Return the str value if node is a string ast.Constant, else None."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    return None


def _dict_lookup(node: ast.Dict, key: str) -> ast.AST | None:
    """Return the value node for a string key in a dict literal, else None."""
    for dict_key, dict_value in zip(node.keys, node.values):
        if isinstance(dict_key, ast.Constant) and dict_key.value == key:
            return dict_value
    return None


def _collect_option_values(options: ast.List) -> list[int]:
    """Return integer Value entries from an Options list literal."""
    values: list[int] = []
    for element in options.elts:
        if not isinstance(element, ast.Dict):
            continue
        value_node = _dict_lookup(element, "Value")
        if isinstance(value_node, ast.Constant) and isinstance(value_node.value, int):
            # Reject bool — Python bool is a subclass of int but a Value:True
            # would be a syntax oddity, not a numeric option value.
            if isinstance(value_node.value, bool):
                continue
            values.append(value_node.value)
    return values


class _OptionSetCollector(ast.NodeVisitor):
    """Walk a schema script AST and gather Picklist option-set definitions."""

    def __init__(self) -> None:
        self.definitions: list[OptionSetDefinition] = []

    def visit_Dict(self, node: ast.Dict) -> None:  # noqa: N802 - ast API
        self.generic_visit(node)
        options_node = _dict_lookup(node, "Options")
        if not isinstance(options_node, ast.List):
            return

        type_node = _dict_lookup(node, "OptionSetType")
        if type_node is None:
            type_node = _dict_lookup(node, "AttributeType")
        if type_node is None:
            type_node = _dict_lookup(node, "AttributeTypeName")
        type_value = _string_constant(type_node) or "Picklist"

        if type_value.lower() in BOOLEAN_ATTR_TYPES:
            return

        name = _string_constant(_dict_lookup(node, "Name"))
        if not name:
            name = _string_constant(_dict_lookup(node, "SchemaName")) or "<anonymous>"

        values = _collect_option_values(options_node)
        if not values:
            return

        low = tuple(sorted({v for v in values if v < DATAVERSE_PICKLIST_FLOOR}))
        if not low:
            return

        self.definitions.append(
            OptionSetDefinition(
                line=node.lineno,
                name=name,
                option_set_type=type_value,
                low_values=low,
            )
        )


def collect_definitions_from_text(text: str, filename: str = "<schema>") -> list[OptionSetDefinition]:
    """Parse schema script text and return Picklist defs with low Values."""
    try:
        tree = ast.parse(text, filename=filename)
    except SyntaxError as exc:
        LOGGER.warning("Skipping unparsable schema script %s: %s", filename, exc)
        return []
    collector = _OptionSetCollector()
    collector.visit(tree)
    return collector.definitions


def collect_definitions(path: Path) -> list[OptionSetDefinition]:
    """Parse a schema script and return Picklist defs with low Values."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        LOGGER.warning("Skipping unreadable schema script %s: %s", path, exc)
        return []
    return collect_definitions_from_text(text, filename=str(path))


def load_allowlist(path: Path = ALLOWLIST_PATH) -> set[str]:
    """Load user-managed allowlist (lowercase option-set logical names)."""
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


def is_allowlisted(name: str, user_allowlist: set[str]) -> bool:
    """Return whether an option-set logical name is allowlisted."""
    lowered = name.lower()
    if lowered in SHARED_ACV_OPTIONSETS:
        return True
    if lowered in INTERNALLY_CONSISTENT_OPTIONSETS:
        return True
    if lowered in user_allowlist:
        return True
    return False


def lint_script(path: Path, user_allowlist: set[str]) -> list[Finding]:
    """Return findings for one schema script after allowlist filtering."""
    findings: list[Finding] = []
    for definition in collect_definitions(path):
        if is_allowlisted(definition.name, user_allowlist):
            continue
        findings.append(Finding(path=path, definition=definition))
    return findings


def lint_solutions(solutions: Iterable[Path], user_allowlist: set[str]) -> list[Finding]:
    """Return findings across a sequence of solution directories."""
    findings: list[Finding] = []
    for solution in solutions:
        for script in schema_scripts(solution):
            findings.extend(lint_script(script, user_allowlist))
    return findings


def format_finding(finding: Finding) -> str:
    """Format a single finding for human-readable output."""
    rel = finding.path.relative_to(ROOT) if finding.path.is_absolute() else finding.path
    values = ", ".join(str(v) for v in finding.definition.low_values)
    return (
        f"{rel}:{finding.definition.line}: option-set "
        f"`{finding.definition.name}` (type={finding.definition.option_set_type}) "
        f"defines Value(s) {values} below Dataverse Picklist floor "
        f"{DATAVERSE_PICKLIST_FLOOR}. Dataverse `fsi_`-prefixed Picklist option "
        f"sets are conventionally 100000000+. Add the name to "
        f"`scripts/.optionset-values-allowlist.txt` if this 0-based definition "
        f"is intentional and internally consistent."
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--solution", help="Lint only this solution slug.")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero on any finding (default: report only).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Run the option-set value linter."""
    args = parse_args(argv)
    logging.basicConfig(format="%(levelname)s: %(message)s", level=logging.INFO)

    solutions = discover_solutions()
    if args.solution:
        solutions = [s for s in solutions if s.name == args.solution]
        if not solutions:
            print(f"No solution found with slug {args.solution!r}", file=sys.stderr)
            return 2

    user_allowlist = load_allowlist()
    findings = lint_solutions(solutions, user_allowlist)
    for finding in findings:
        print(format_finding(finding))

    LOGGER.info(
        "optionset-values-lint: scanned %s solution(s); %s finding(s).",
        len(solutions),
        len(findings),
    )

    if args.strict:
        return 1 if findings else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
