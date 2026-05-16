#!/usr/bin/env python3
"""Provision or emit the FSI agent-intake retention-label configuration.

On Windows, this wrapper defaults to the Security & Compliance PowerShell path
(`setup_purview_retention_label.ps1`) because Connect-IPPSSession +
New-ComplianceTag is the supported automation path for unattended tenant setup.
Use `--no-use-powershell-wrapper` to emit only the JSON spec and delegated
Graph beta sample / manual guidance.

Usage:
  python setup_purview_retention_label.py --output spec.json
  python setup_purview_retention_label.py --use-powershell-wrapper --admin-upn admin@contoso.com
  python setup_purview_retention_label.py --no-use-powershell-wrapper --include-graph-beta
"""
from __future__ import annotations

import argparse
import json
import logging
import subprocess
import sys
from pathlib import Path
from typing import Any

LOG = logging.getLogger("agent-intake.purview-label")

DEFAULT_LABEL_NAME = "FSI-AgentIntake-7yr"
DEFAULT_WORM_LABEL_NAME = "FSI-AgentIntake-7yr-WORM"
DEFAULT_RETENTION_DAYS = 2555

MANUAL_STEPS = """
Primary automation path
=======================
On Windows, this wrapper defaults to `pwsh .\\scripts\\setup_purview_retention_label.ps1`.
That PowerShell path uses Connect-IPPSSession and New-ComplianceTag to create the
labels idempotently.

Manual fallback - Microsoft Purview portal
==========================================
1. Sign in to https://purview.microsoft.com with a records-management admin account.
2. Navigate to Solutions -> Records Management -> File plan.
3. Create a label named FSI-AgentIntake-7yr.
4. Configure retention to keep items for 2,555 days from the creation date.
5. Create a second label named FSI-AgentIntake-7yr-WORM with the same duration and turn on "Mark items as records".
6. Record the exact label names used by the intake decision-log flow.
7. See docs/identity-records-automation.md for the full Stage 2 sequence.

Graph beta reference (preview / delegated only)
===============================================
POST https://graph.microsoft.com/beta/security/labels/retentionLabels
Permission: delegated RecordsManagement.ReadWrite.All; application permissions are not documented for create.
"""


def build_label_spec(label_name: str, worm_label_name: str, retention_days: int) -> dict[str, Any]:
    """Return the base retention-label specification."""
    return {
        "displayName": label_name,
        "description": "Retention label for FSI agent-intake records (SEC 17a-4, FINRA 4511, CFTC 1.31).",
        "retentionDuration": {
            "@odata.type": "microsoft.graph.security.retentionDurationInDays",
            "days": retention_days,
        },
        "retentionTrigger": "dateCreated",
        "actionAfterRetentionPeriod": "none",
        "behaviorDuringRetentionPeriod": "retain",
        "isInUse": False,
        "descriptionForUsers": "Records related to AI agent intake decisions. Retained for 7 years.",
        "descriptionForAdmins": (
            "Applied to fsi_intakedecisionlog evidence rows and tracked in fsi_intakeretentionrecord. "
            "Supports FINRA 3110 supervision evidence and SEC 17a-4 records retention."
        ),
        "wormVariant": {
            "displayName": worm_label_name,
            "description": "Immutable variant for fsi_intakedecisionlog (write-once, read-many).",
            "behaviorDuringRetentionPeriod": "retainAsRecord",
            "defaultRecordBehavior": "startLocked",
        },
    }


def build_spec(
    *,
    label_name: str,
    worm_label_name: str,
    retention_days: int,
    include_graph_beta: bool,
) -> dict[str, Any]:
    """Build the emitted JSON spec."""
    label_spec = build_label_spec(label_name, worm_label_name, retention_days)
    spec: dict[str, Any] = {"label": label_spec}
    if include_graph_beta:
        spec["graphBetaCreateSample"] = {
            "method": "POST",
            "url": "https://graph.microsoft.com/beta/security/labels/retentionLabels",
            "permission": "Delegated RecordsManagement.ReadWrite.All (application permissions not documented for the beta create API)",
            "payload": label_spec,
        }
    return spec


def write_spec(path: Path, spec: dict[str, Any]) -> None:
    """Persist the emitted spec."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(spec, indent=2), encoding="utf-8")
    LOG.info("Wrote label spec to %s", path)


def run_powershell_wrapper(args: argparse.Namespace) -> int:
    """Invoke the PowerShell wrapper with pass-through arguments."""
    wrapper_path = Path(__file__).with_name("setup_purview_retention_label.ps1")
    if not wrapper_path.exists():
        raise FileNotFoundError(f"PowerShell wrapper not found: {wrapper_path}")

    command = [
        "pwsh",
        "-NoLogo",
        "-NoProfile",
        "-File",
        str(wrapper_path),
        "-LabelName",
        args.label_name,
        "-WormLabelName",
        args.worm_label_name,
        "-RetentionDays",
        str(args.retention_days),
    ]
    if args.admin_upn:
        command.extend(["-AdminUpn", args.admin_upn])
    if args.dry_run:
        command.append("-DryRun")

    LOG.info("Path taken: Security & Compliance PowerShell wrapper")
    completed = subprocess.run(command, check=False)
    return completed.returncode


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Create the agent-intake retention labels or emit the supporting JSON spec")
    parser.add_argument("--output", type=Path, help="Where to write the JSON spec")
    parser.add_argument("--include-graph-beta", action="store_true", help="Include the beta Graph create sample in the emitted spec")
    parser.add_argument("--label-name", default=DEFAULT_LABEL_NAME, help="Retention label name")
    parser.add_argument("--worm-label-name", default=DEFAULT_WORM_LABEL_NAME, help="WORM retention label name")
    parser.add_argument("--retention-days", type=int, default=DEFAULT_RETENTION_DAYS, help="Retention duration in days")
    parser.add_argument("--admin-upn", help="Admin UPN passed through to the PowerShell wrapper")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Passed through to the PowerShell wrapper; when the wrapper is disabled, only emits the planned spec",
    )
    parser.add_argument(
        "--use-powershell-wrapper",
        action=argparse.BooleanOptionalAction,
        default=sys.platform.startswith("win"),
        help="On Windows, defaults to true and shells out to setup_purview_retention_label.ps1",
    )
    args = parser.parse_args()

    spec = build_spec(
        label_name=args.label_name,
        worm_label_name=args.worm_label_name,
        retention_days=args.retention_days,
        include_graph_beta=args.include_graph_beta,
    )

    if args.output:
        write_spec(args.output, spec)

    if args.use_powershell_wrapper:
        print("Path taken: Security & Compliance PowerShell wrapper.")
        return run_powershell_wrapper(args)

    print("Path taken: JSON spec + delegated Graph beta sample/manual guidance.")
    if not args.output:
        print(json.dumps(spec, indent=2))
    print(MANUAL_STEPS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
