#!/usr/bin/env python3
"""
Print Power Platform maker-portal instructions for ELM business rules.

Why this script no longer calls the Dataverse Web API
-----------------------------------------------------
Earlier versions of this script tried to create business rules (workflow
``category=2``) by POSTing legacy ``RuleDefinitions`` XAML to
``/workflows`` in an already-Activated state. Both decisions are
incompatible with the current Dataverse Web API:

* The supported XAML for category=2 business rules in modern Dataverse is
  Windows Workflow Foundation (``<Activity ...
  xmlns="http://schemas.microsoft.com/netfx/2009/xaml/activities">``),
  not the legacy ``<RuleDefinitions xmlns=".../crm/2009/WebServices">``
  used here previously.
* New ``workflow`` rows must be POSTed with ``statecode=0`` (Draft) and
  then PATCHed to Activated. Posting Activated directly is rejected by
  the platform.

Programmatically generating valid business-rule WF XAML is brittle and
hard to maintain. Microsoft's recommended path is to author business
rules in the maker portal, where the platform produces the correct XAML
on save. Once authored, the rules can be packaged into a managed
solution for ALM transport.

Run this script to print the rule definitions; then follow the
instructions in ``docs/business-rules.md`` to author each rule manually.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import dataclass, field
from typing import Iterable

LOGGER = logging.getLogger("elm.business_rules")

# Option-set values match `create_dataverse_schema.py` after the
# 2026-04 schema canonicalisation (custom range 100000001+).
ZONE_2 = 100000002
ZONE_3 = 100000003
STATE_REJECTED = 100000005


@dataclass(frozen=True)
class BusinessRule:
    name: str
    description: str
    entity: str
    trigger: str
    actions: tuple[str, ...] = field(default_factory=tuple)


RULES: tuple[BusinessRule, ...] = (
    BusinessRule(
        name="ELM Zone Rationale Required",
        description=(
            "Make 'Zone Rationale' (fsi_zonerationale) required when 'Zone' "
            "(fsi_zone) is Zone2 or Zone3."
        ),
        entity="fsi_environmentrequest",
        trigger=f"fsi_zone IN ({ZONE_2}, {ZONE_3})",
        actions=(
            "Set Business Required: fsi_zonerationale = Business Required",
            "Otherwise: fsi_zonerationale = Not Required",
        ),
    ),
    BusinessRule(
        name="ELM Security Group Required",
        description=(
            "Make 'Security Group ID' (fsi_securitygroupid) required when "
            "'Zone' (fsi_zone) is Zone2 or Zone3."
        ),
        entity="fsi_environmentrequest",
        trigger=f"fsi_zone IN ({ZONE_2}, {ZONE_3})",
        actions=(
            "Set Business Required: fsi_securitygroupid = Business Required",
            "Otherwise: fsi_securitygroupid = Not Required",
        ),
    ),
    BusinessRule(
        name="ELM Approval Comments Required",
        description=(
            "Make 'Approval Comments' (fsi_approvalcomments) required when "
            "'State' (fsi_state) is Rejected."
        ),
        entity="fsi_environmentrequest",
        trigger=f"fsi_state EQUALS {STATE_REJECTED}  (Rejected)",
        actions=(
            "Set Business Required: fsi_approvalcomments = Business Required",
            "Otherwise: fsi_approvalcomments = Not Required",
        ),
    ),
)


def _format_human(rules: Iterable[BusinessRule]) -> str:
    lines = []
    for r in rules:
        lines.append("=" * 70)
        lines.append(f"Rule: {r.name}")
        lines.append(f"Entity: {r.entity}")
        lines.append(f"Description: {r.description}")
        lines.append(f"Condition: {r.trigger}")
        lines.append("Actions:")
        for action in r.actions:
            lines.append(f"  - {action}")
    lines.append("=" * 70)
    lines.append("")
    lines.append("Authoring steps (per rule):")
    lines.append("  1. Open https://make.powerapps.com")
    lines.append("  2. Solutions > <your ELM solution> > New > Automation > Business rule")
    lines.append("  3. Choose the entity, set the Scope to 'Entity'.")
    lines.append("  4. Add the Condition and Actions exactly as shown above.")
    lines.append("  5. Save > Activate.")
    lines.append("")
    lines.append(
        "Notes:"
    )
    lines.append(
        "  - Save and activate each rule before testing."
    )
    lines.append(
        "  - Keep the rule scope at 'Entity' so server-side validation runs."
    )
    return "\n".join(lines)


def _format_json(rules: Iterable[BusinessRule]) -> str:
    payload = [
        {
            "name": r.name,
            "description": r.description,
            "entity": r.entity,
            "condition": r.trigger,
            "actions": list(r.actions),
        }
        for r in rules
    ]
    return json.dumps(payload, indent=2)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Print ELM business-rule definitions for manual authoring.",
    )
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format (default: text)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    if args.format == "json":
        print(_format_json(RULES))
    else:
        print(_format_human(RULES))

    LOGGER.info("Printed %d business rule definitions.", len(RULES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
