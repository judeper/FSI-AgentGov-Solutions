#!/usr/bin/env python3
"""One-time setup — create the `FSI-AgentIntake-7yr` retention label in Purview.

Run once per tenant as part of pilot deployment. The label is then applied
automatically by Flow 1 to every `fsi_intakerequest` and (in WORM variant)
every `fsi_intakedecisionlog` entry, satisfying SEC 17a-4, FINRA 4511, and
CFTC 1.31 7-year retention.

NOTE: As of v0.1.0-preview, Microsoft Graph does not yet support
**creation** of retention labels via the public API surface — only read.
This script therefore prints the **manual steps** an admin must follow in
the Microsoft Purview portal AND emits a stub JSON describing the desired
label so the deployment runbook can attach it to the change record.

Manual creation flow:
  Purview portal -> Solutions -> Records management -> File plan ->
    + Create a label

Usage:
  python setup_purview_retention_label.py --output spec.json
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
        "days": 2557,
    },
    "retentionTrigger": "dateCreated",
    "actionAfterRetentionPeriod": "none",
    "behaviorDuringRetentionPeriod": "retain",
    "isInUse": False,
    "descriptionForUsers": "Records related to AI agent intake decisions. Retained for 7 years.",
    "descriptionForAdmins": "Applied to fsi_intakerequest and fsi_intakedecisionlog rows. Required for FINRA 3110 supervision evidence and SEC 17a-4 records retention.",
    "wormVariant": {
        "displayName": "FSI-AgentIntake-7yr-WORM",
        "description": "Immutable variant for fsi_intakedecisionlog (write-once, read-many).",
        "behaviorDuringRetentionPeriod": "retainAsRecord",
    },
}

MANUAL_STEPS = """
Manual creation — Microsoft Purview portal
==========================================
1. Sign in to https://purview.microsoft.com with a Records Management admin account.
2. Navigate: Solutions -> Records management -> File plan -> + Create a label.
3. Label name: FSI-AgentIntake-7yr
4. Description for users: "Records related to AI agent intake decisions. Retained for 7 years."
5. Description for admins: see spec.json file (descriptionForAdmins).
6. Retention settings: Retain items for 7 years (2557 days), starting when items were created.
7. After the retention period: Do nothing (records management team will purge manually after legal hold review).
8. Repeat for the WORM variant 'FSI-AgentIntake-7yr-WORM' with "Mark items as a record" enabled.
9. Auto-apply policy: Scope to the Dataverse table 'fsi_intakerequest' and 'fsi_intakedecisionlog'.
10. Run scripts/autodetect_purview.py --label-name FSI-AgentIntake-7yr to verify creation.
"""


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    p = argparse.ArgumentParser(description="Emit retention-label spec + manual setup steps")
    p.add_argument("--output", type=Path, required=True, help="Where to write the JSON spec")
    args = p.parse_args()

    args.output.write_text(json.dumps(LABEL_SPEC, indent=2), encoding="utf-8")
    LOG.info("Wrote label spec to %s", args.output)
    print(MANUAL_STEPS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
