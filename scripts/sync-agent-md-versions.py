#!/usr/bin/env python3
"""
Sync the per-solution version + primary-controls columns in the inventory tables
inside AGENTS.md and .github/copilot-instructions.md against solutions.json.

The descriptions in those tables are curated per file (the AGENTS.md description
is typically longer than the copilot-instructions.md description) so they are
NOT touched. Only the version cell and the primary-controls cell are rewritten.

Usage:
    python scripts/sync-agent-md-versions.py            # write changes
    python scripts/sync-agent-md-versions.py --check    # exit 1 if drift exists

The repo root is detected as the parent of this script's directory.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SOLUTIONS_JSON = REPO_ROOT / "solutions.json"
TARGETS = (
    REPO_ROOT / "AGENTS.md",
    REPO_ROOT / ".github" / "copilot-instructions.md",
)

# Inventory row format: | <id> | <version> | <controls> | <description> |
ROW_RE = re.compile(
    r"^\|\s*(?P<id>[a-z0-9][a-z0-9-]+)\s*\|\s*(?P<ver>[^|]+?)\s*\|\s*(?P<ctrl>[^|]+?)\s*\|\s*(?P<desc>[^|]+?)\s*\|\s*$"
)
# Primary-controls cell: comma-separated control IDs, optionally with whitespace.
CONTROL_TOKEN = re.compile(r"^\d+\.\d+[a-z]?$")


def load_solutions() -> dict[str, dict]:
    raw = json.loads(SOLUTIONS_JSON.read_text(encoding="utf-8"))
    sols = raw.get("solutions") or {}
    if not isinstance(sols, dict):
        sys.exit("solutions.json: 'solutions' is not an object")
    return sols


def render_version(version: str) -> str:
    """Inventory tables prefix versions with 'v' (e.g. v1.2.0). Preserve any
    existing pre-release suffix (e.g. -preview)."""
    return f"v{version}" if not version.startswith("v") else version


def sync_file(
    path: Path, solutions: dict[str, dict], check_only: bool
) -> tuple[bool, list[str]]:
    """Returns (changed, drift_lines)."""
    if not path.exists():
        return False, []

    original = path.read_text(encoding="utf-8")
    drift: list[str] = []
    new_lines: list[str] = []

    for line in original.splitlines(keepends=False):
        m = ROW_RE.match(line)
        if not m:
            new_lines.append(line)
            continue

        sol_id = m.group("id")
        sol = solutions.get(sol_id)
        if sol is None:
            # Row does not correspond to a solution (could be the header row,
            # which won't match the regex anyway). Leave untouched.
            new_lines.append(line)
            continue

        cur_ver = m.group("ver")
        cur_ctrl = m.group("ctrl")
        cur_desc = m.group("desc")

        new_ver = render_version(sol["version"])
        controls = sol.get("controls") or []
        # Authoritative ordering = manifest order.
        new_ctrl = ", ".join(controls)

        if cur_ver != new_ver or cur_ctrl != new_ctrl:
            drift.append(
                f"{path.relative_to(REPO_ROOT)}: {sol_id}  "
                f"version {cur_ver!r}->{new_ver!r}  "
                f"controls {cur_ctrl!r}->{new_ctrl!r}"
            )
        new_line = f"| {sol_id} | {new_ver} | {new_ctrl} | {cur_desc} |"
        new_lines.append(new_line)

    new_text = "\n".join(new_lines)
    # Preserve trailing newline if the original had one.
    if original.endswith("\n"):
        new_text += "\n"

    changed = new_text != original
    if changed and not check_only:
        path.write_text(new_text, encoding="utf-8")

    return changed, drift


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--check",
        action="store_true",
        help="Do not write; exit 1 if any drift detected.",
    )
    args = p.parse_args()

    solutions = load_solutions()
    total_drift: list[str] = []
    any_changed = False

    for target in TARGETS:
        changed, drift = sync_file(target, solutions, args.check)
        any_changed = any_changed or changed
        total_drift.extend(drift)

    if args.check:
        if total_drift:
            print("DRIFT detected between solutions.json and inventory tables:\n")
            for d in total_drift:
                print(f"  {d}")
            print(
                f"\nRun `python {Path(__file__).relative_to(REPO_ROOT)}` "
                "(without --check) to fix."
            )
            return 1
        print("No drift between solutions.json and inventory tables.")
        return 0

    if any_changed:
        print(f"Updated {len(total_drift)} row(s) across {len(TARGETS)} file(s).")
        for d in total_drift:
            print(f"  {d}")
    else:
        print("No drift; files unchanged.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
