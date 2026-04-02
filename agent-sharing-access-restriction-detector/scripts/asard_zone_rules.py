#!/usr/bin/env python3
"""ASARD Zone Rules Engine — zone-based sharing policy definitions.

Defines governance zone policies for the Agent Sharing Access Restriction
Detector (ASARD). Each zone specifies permitted sharing configurations,
violation severity mappings, and regulatory context references.

Zone policies enforce Controls 1.18 (Application-Level Authorization) and
2.8 (Access Control/Segregation of Duties) from the FSI Agent Governance
Framework.

Zone rules:
    Zone1: No group sharing permitted — agents restricted to specific named users
    Zone2: Named approved groups only — sharing restricted to pre-approved security groups
    Zone3: Approved groups only — governance-approved groups; no org-wide/public
    Unknown: Defaults to Zone 1 (most restrictive) per security-first principle
"""

from __future__ import annotations

import json
import sys
from typing import Any

ZONE_POLICIES: dict[str, dict[str, Any]] = {
    "Zone1": {
        "allow_group_sharing": False,
        "allow_org_wide": False,
        "allow_public": False,
        "require_approved_groups": False,
        "violation_severity": {
            "GroupSharing": "Critical",
            "OrgWideSharing": "Critical",
            "PublicSharing": "Critical",
            "UnapprovedGroup": "Critical",
        },
        "regulatory_context": (
            "Zone 1 (Personal Productivity) — No group sharing permitted; "
            "agents restricted to specific named users per "
            "FINRA Rule 4511 and GLBA Section 501(b)"
        ),
    },
    "Zone2": {
        "allow_group_sharing": True,
        "allow_org_wide": False,
        "allow_public": False,
        "require_approved_groups": True,
        "violation_severity": {
            "GroupSharing": "Informational",
            "OrgWideSharing": "High",
            "PublicSharing": "Critical",
            "UnapprovedGroup": "High",
        },
        "regulatory_context": (
            "Zone 2 (Team/Collaborative) — Named approved groups only; "
            "org-wide and public sharing prohibited per "
            "SOX Section 404 and GLBA Section 501(b)"
        ),
    },
    "Zone3": {
        "allow_group_sharing": True,
        "allow_org_wide": False,
        "allow_public": False,
        "require_approved_groups": True,
        "violation_severity": {
            "GroupSharing": "Informational",
            "OrgWideSharing": "Critical",
            "PublicSharing": "Critical",
            "UnapprovedGroup": "High",
        },
        "regulatory_context": (
            "Zone 3 (Enterprise/Regulated) — Approved groups only; "
            "org-wide and public sharing prohibited per "
            "FINRA Rule 4511, SOX Section 404, and GLBA Section 501(b)"
        ),
    },
    "Unknown": {
        "allow_group_sharing": False,
        "allow_org_wide": False,
        "allow_public": False,
        "require_approved_groups": False,
        "violation_severity": {
            "GroupSharing": "Critical",
            "OrgWideSharing": "Critical",
            "PublicSharing": "Critical",
            "UnapprovedGroup": "Critical",
        },
        "regulatory_context": (
            "Unclassified environment — Defaults to Zone 1 (most restrictive) "
            "until zone classification is completed; no group sharing permitted"
        ),
    },
}


def get_zone_policy(zone_name: str) -> dict[str, Any]:
    """Return the sharing policy for a governance zone.

    Args:
        zone_name: Zone identifier (Zone1, Zone2, Zone3, or Unknown).

    Returns:
        Policy dictionary with sharing permissions, severity mappings,
        and regulatory context.

    Raises:
        ValueError: If zone_name is not a recognized zone.
    """
    policy = ZONE_POLICIES.get(zone_name)
    if policy is None:
        raise ValueError(
            f"Unknown zone '{zone_name}'. "
            f"Valid zones: {', '.join(ZONE_POLICIES.keys())}"
        )
    return policy


def evaluate_compliance(
    agent_sharing: dict[str, Any],
    zone_name: str,
    approved_groups: list[str] | None = None,
) -> dict[str, Any]:
    """Evaluate an agent's sharing configuration against zone policy.

    Args:
        agent_sharing: Agent sharing configuration with keys:
            - sharing_type (int): 0=SpecificUsers, 1=OrgWide, 2=Public
            - shared_group_ids (list[str]): Security group IDs the agent
              is shared with
        zone_name: Governance zone (Zone1, Zone2, Zone3, Unknown).
        approved_groups: List of approved security group IDs for the zone.

    Returns:
        Compliance result dictionary with keys:
            - compliant (bool): Whether the agent is compliant
            - violation_type (str|None): Type of violation if non-compliant
            - severity (str|None): Violation severity level
            - regulatory_context (str): Zone regulatory context string
    """
    policy = get_zone_policy(zone_name)
    approved_groups = approved_groups or []

    sharing_type = agent_sharing.get("sharing_type", 0)
    shared_group_ids = agent_sharing.get("shared_group_ids", [])

    # Public sharing check
    if sharing_type == 2:
        return {
            "compliant": False,
            "violation_type": "PublicSharing",
            "severity": policy["violation_severity"]["PublicSharing"],
            "regulatory_context": policy["regulatory_context"],
        }

    # Org-wide sharing check
    if sharing_type == 1:
        if not policy["allow_org_wide"]:
            return {
                "compliant": False,
                "violation_type": "OrgWideSharing",
                "severity": policy["violation_severity"]["OrgWideSharing"],
                "regulatory_context": policy["regulatory_context"],
            }

    # Group sharing checks
    if shared_group_ids:
        if not policy["allow_group_sharing"]:
            return {
                "compliant": False,
                "violation_type": "GroupSharing",
                "severity": policy["violation_severity"]["GroupSharing"],
                "regulatory_context": policy["regulatory_context"],
            }

        if policy["require_approved_groups"]:
            unapproved = [
                gid for gid in shared_group_ids if gid not in approved_groups
            ]
            if unapproved:
                return {
                    "compliant": False,
                    "violation_type": "UnapprovedGroup",
                    "severity": policy["violation_severity"]["UnapprovedGroup"],
                    "regulatory_context": policy["regulatory_context"],
                }

    return {
        "compliant": True,
        "violation_type": None,
        "severity": None,
        "regulatory_context": policy["regulatory_context"],
    }


def main() -> None:
    """CLI entrypoint — prints zone policies as JSON."""
    output = {
        zone: {
            **policy,
            "zone": zone,
        }
        for zone, policy in ZONE_POLICIES.items()
    }
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
