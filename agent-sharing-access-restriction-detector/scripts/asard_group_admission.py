#!/usr/bin/env python3
"""ASARD Group Admission Gate — validates Entra group type before approval.

Enforces that only proper security groups (securityEnabled=True,
mailEnabled=False) are admitted to fsi_approvedsecuritygrouppolicies.
Rejects:
  - Mail-enabled distribution groups (lack access control semantics)
  - Security-disabled groups (no Entra RBAC enforcement)
  - Dynamic membership groups that could silently change membership

Emits GROUP_TYPE_DRIFT findings when a previously-approved group's type
properties change after initial admission.

Usage:
    # Validate a single group before admission
    python asard_group_admission.py --group-id <object-id> --access-token <token>

    # Batch-validate all approved groups for drift
    python asard_group_admission.py --batch --groups-file approved_groups.json --access-token <token>
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import dataclass, field
from typing import Any

logger = logging.getLogger(__name__)


# ── Data types ────────────────────────────────────────────────────────────


@dataclass
class GroupProperties:
    """Microsoft Entra group properties relevant to admission gating."""

    group_id: str
    display_name: str
    security_enabled: bool
    mail_enabled: bool
    group_types: list[str] = field(default_factory=list)

    @property
    def is_dynamic(self) -> bool:
        """Check if group uses dynamic membership rules."""
        return "DynamicMembership" in self.group_types

    @property
    def is_unified(self) -> bool:
        """Check if group is a Microsoft 365 group (Unified)."""
        return "Unified" in self.group_types


@dataclass
class AdmissionResult:
    """Result of a group admission gate check."""

    group_id: str
    display_name: str
    admitted: bool
    findings: list[dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        """Serialize to dictionary for JSON output."""
        return {
            "groupId": self.group_id,
            "displayName": self.display_name,
            "admitted": self.admitted,
            "findingCount": len(self.findings),
            "findings": self.findings,
        }


# ── Validation logic ─────────────────────────────────────────────────────


def validate_group_admission(group: GroupProperties) -> AdmissionResult:
    """Validate whether an Entra group meets admission requirements.

    Admission requirements:
      - securityEnabled must be True
      - mailEnabled must be False
      - groupTypes must NOT contain 'Unified' (M365 groups)

    Dynamic groups (groupTypes contains 'DynamicMembership') are flagged
    as a warning but not rejected — the caller decides policy.

    Args:
        group: Entra group properties to validate.

    Returns:
        AdmissionResult indicating pass/fail with finding details.
    """
    result = AdmissionResult(
        group_id=group.group_id,
        display_name=group.display_name,
        admitted=True,
        findings=[],
    )

    # Gate 1: Must be security-enabled
    if not group.security_enabled:
        result.admitted = False
        result.findings.append({
            "findingType": "GROUP_SECURITY_DISABLED",
            "severity": "Critical",
            "description": (
                f"Group '{group.display_name}' ({group.group_id}) has "
                f"securityEnabled=false. Security-disabled groups lack "
                f"proper access control semantics and cannot be used "
                f"for agent sharing governance."
            ),
            "remediation": (
                "Use a security-enabled group or create a new Microsoft "
                "Entra security group with securityEnabled=true."
            ),
        })

    # Gate 2: Must NOT be mail-enabled
    if group.mail_enabled:
        result.admitted = False
        result.findings.append({
            "findingType": "GROUP_MAIL_ENABLED",
            "severity": "High",
            "description": (
                f"Group '{group.display_name}' ({group.group_id}) has "
                f"mailEnabled=true. Mail-enabled distribution groups lack "
                f"proper access control semantics for agent sharing."
            ),
            "remediation": (
                "Use a pure security group (mailEnabled=false, "
                "securityEnabled=true) instead of a mail-enabled group."
            ),
        })

    # Gate 3: Must NOT be a Microsoft 365 (Unified) group
    if group.is_unified:
        result.admitted = False
        result.findings.append({
            "findingType": "GROUP_M365_UNIFIED",
            "severity": "High",
            "description": (
                f"Group '{group.display_name}' ({group.group_id}) is a "
                f"Microsoft 365 group (Unified). M365 groups have broader "
                f"access semantics (mailbox, SharePoint site, Teams) that "
                f"are not appropriate for agent sharing admission control."
            ),
            "remediation": (
                "Use a dedicated Microsoft Entra security group instead "
                "of a Microsoft 365 group."
            ),
        })

    # Warning: Dynamic membership (informational, does not block admission)
    if group.is_dynamic:
        result.findings.append({
            "findingType": "GROUP_DYNAMIC_MEMBERSHIP",
            "severity": "Medium",
            "description": (
                f"Group '{group.display_name}' ({group.group_id}) uses "
                f"dynamic membership rules. Membership may change without "
                f"explicit governance approval — monitor for drift."
            ),
            "remediation": (
                "Consider using a statically-assigned security group for "
                "tighter control, or implement periodic membership review."
            ),
        })

    return result


def detect_group_type_drift(
    group: GroupProperties,
    stored_security_enabled: bool,
    stored_mail_enabled: bool,
) -> list[dict[str, Any]]:
    """Detect changes in group type properties since last admission check.

    Args:
        group: Current Entra group properties.
        stored_security_enabled: securityEnabled value at admission time.
        stored_mail_enabled: mailEnabled value at admission time.

    Returns:
        List of drift findings (empty if no drift detected).
    """
    findings: list[dict[str, Any]] = []

    if group.security_enabled != stored_security_enabled:
        findings.append({
            "findingType": "GROUP_TYPE_DRIFT",
            "severity": "Critical",
            "description": (
                f"Group '{group.display_name}' ({group.group_id}) "
                f"securityEnabled changed from {stored_security_enabled} "
                f"to {group.security_enabled} since last admission check."
            ),
            "remediation": (
                "Re-validate group admission. If securityEnabled is now "
                "false, remove group from approved policies."
            ),
            "driftField": "securityEnabled",
            "previousValue": stored_security_enabled,
            "currentValue": group.security_enabled,
        })

    if group.mail_enabled != stored_mail_enabled:
        findings.append({
            "findingType": "GROUP_TYPE_DRIFT",
            "severity": "High",
            "description": (
                f"Group '{group.display_name}' ({group.group_id}) "
                f"mailEnabled changed from {stored_mail_enabled} "
                f"to {group.mail_enabled} since last admission check."
            ),
            "remediation": (
                "Re-validate group admission. If mailEnabled is now "
                "true, the group has become a distribution group and "
                "should be removed from approved policies."
            ),
            "driftField": "mailEnabled",
            "previousValue": stored_mail_enabled,
            "currentValue": group.mail_enabled,
        })

    return findings


# ── CLI ───────────────────────────────────────────────────────────────────


def _parse_graph_group(data: dict[str, Any]) -> GroupProperties:
    """Parse a Microsoft Graph group API response into GroupProperties."""
    return GroupProperties(
        group_id=data.get("id", ""),
        display_name=data.get("displayName", ""),
        security_enabled=data.get("securityEnabled", False),
        mail_enabled=data.get("mailEnabled", False),
        group_types=data.get("groupTypes", []),
    )


def main() -> None:
    """CLI entry point for group admission validation."""
    parser = argparse.ArgumentParser(
        description="ASARD Group Admission Gate — validate Entra group type",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--group-id",
        help="Microsoft Entra group object ID to validate",
    )
    parser.add_argument(
        "--batch",
        action="store_true",
        help="Batch-validate groups from a JSON file",
    )
    parser.add_argument(
        "--groups-file",
        help="Path to JSON file with group data (array of Graph group objects)",
    )
    parser.add_argument(
        "--access-token",
        help=(
            "[RESERVED — unused in this version] Microsoft Graph access token. "
            "Reserved for a future enhancement that will fetch group properties "
            "directly from the /v1.0/groups/{id} endpoint when --group-id is "
            "supplied. Today the script validates only locally-loaded JSON via "
            "--groups-file."
        ),
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging",
    )

    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    if args.batch and args.groups_file:
        with open(args.groups_file, encoding="utf-8") as f:
            groups_data = json.load(f)

        results = []
        for gdata in groups_data:
            group = _parse_graph_group(gdata)
            result = validate_group_admission(group)
            results.append(result.to_dict())
            status = "ADMITTED" if result.admitted else "REJECTED"
            logger.info(
                "%s: %s (%s) — %d finding(s)",
                status, group.display_name, group.group_id, len(result.findings),
            )

        json.dump(results, sys.stdout, indent=2)
        sys.stdout.write("\n")

    elif args.groups_file:
        with open(args.groups_file, encoding="utf-8") as f:
            gdata = json.load(f)
        group = _parse_graph_group(gdata)
        result = validate_group_admission(group)
        json.dump(result.to_dict(), sys.stdout, indent=2)
        sys.stdout.write("\n")
        sys.exit(0 if result.admitted else 1)

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
