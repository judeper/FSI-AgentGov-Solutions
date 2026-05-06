#!/usr/bin/env python3
"""One-time setup guidance for the `FSI-AgentIntake-7yr` retention label.

Run once per tenant as part of pilot deployment. The label is then stamped on
`fsi_intakedecisionlog` evidence rows and tracked by `fsi_intakeretentionrecord`,
supporting SEC 17a-4, FINRA 4511, and CFTC 1.31 retention expectations.

Microsoft Graph can create retention labels only on the beta endpoint
(`/security/labels/retentionLabels`) and, per Microsoft Learn, create currently
supports delegated `RecordsManagement.ReadWrite.All` but not application
permissions. For production deployments, use the Microsoft Purview portal or
Security & Compliance PowerShell (`New-ComplianceTag`) unless your change-control
process explicitly permits beta Graph APIs.

Usage:
  python setup_purview_retention_label.py --output spec.json
  python setup_purview_retention_label.py
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

LOG = logging.getLogger("agent-intake.purview-label")

LABEL_SPEC = {
    "displayName": "FSI-AgentIntake-7yr",
    "description": "Retention label for FSI agent-intake records (SEC 17a-4, FINRA 4511, CFTC 1.31).",
    "retentionDuration": {
        "@odata.type": "microsoft.graph.security.retentionDurationInDays",
        "days": 2555,
    },
    "retentionTrigger": "dateCreated",
    "actionAfterRetentionPeriod": "none",
    "behaviorDuringRetentionPeriod": "retain",
    "isInUse": False,
    "descriptionForUsers": "Records related to AI agent intake decisions. Retained for 7 years.",
    "descriptionForAdmins": "Applied to fsi_intakedecisionlog evidence rows and tracked in fsi_intakeretentionrecord. Supports FINRA 3110 supervision evidence and SEC 17a-4 records retention.",
    "wormVariant": {
        "displayName": "FSI-AgentIntake-7yr-WORM",
        "description": "Immutable variant for fsi_intakedecisionlog (write-once, read-many).",
        "behaviorDuringRetentionPeriod": "retainAsRecord",
        "defaultRecordBehavior": "startLocked",
    },
}

GRAPH_BETA_CREATE_SAMPLE = {
    "method": "POST",
    "url": "https://graph.microsoft.com/beta/security/labels/retentionLabels",
    "permission": "Delegated RecordsManagement.ReadWrite.All (application permissions not supported by the beta create API)",
    "payload": LABEL_SPEC,
}

MANUAL_STEPS = """
Manual creation — Microsoft Purview portal
==========================================
1. Sign in to https://purview.microsoft.com with a Records Management admin account.
2. Navigate: Solutions -> Records management -> File plan -> + Create a label.
3. Label name: FSI-AgentIntake-7yr
4. Description for users: "Records related to AI agent intake decisions. Retained for 7 years."
5. Description for admins: see the emitted JSON spec.
6. Retention settings: retain items for 7 years (2,555 days), starting when items were created.
7. After the retention period: do nothing until records management completes legal-hold review.
8. Repeat for the WORM variant 'FSI-AgentIntake-7yr-WORM' with "Mark items as a record" enabled.
9. Configure the Dataverse/Power Automate evidence-stamping step to record the label name on fsi_intakedecisionlog and fsi_intakeretentionrecord.
10. Run: python scripts/autodetect_purview.py --label-name FSI-AgentIntake-7yr --token-source cli

Production PowerShell alternative
=================================
Connect-IPPSSession
New-ComplianceTag -Name "FSI-AgentIntake-7yr" -RetentionAction Keep -RetentionDuration 2555 -RetentionType CreationAgeInDays -Comment "FSI agent-intake decision records"
New-ComplianceTag -Name "FSI-AgentIntake-7yr-WORM" -RetentionAction Keep -RetentionDuration 2555 -RetentionType CreationAgeInDays -IsRecordLabel $true -Comment "Immutable FSI agent-intake decision records"

Graph beta reference (preview/admin validation only)
===================================================
POST https://graph.microsoft.com/beta/security/labels/retentionLabels
Permission: delegated RecordsManagement.ReadWrite.All; application permissions not supported for create.
"""


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Emit retention-label spec + setup steps")
    parser.add_argument("--output", type=Path, help="Where to write the JSON spec")
    parser.add_argument("--include-graph-beta", action="store_true", help="Include the beta Graph create sample in the emitted spec")
    args = parser.parse_args()

    spec = {"label": LABEL_SPEC}
    if args.include_graph_beta:
        spec["graphBetaCreateSample"] = GRAPH_BETA_CREATE_SAMPLE
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(spec, indent=2), encoding="utf-8")
        LOG.info("Wrote label spec to %s", args.output)
    else:
        print(json.dumps(spec, indent=2))
    print(MANUAL_STEPS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
