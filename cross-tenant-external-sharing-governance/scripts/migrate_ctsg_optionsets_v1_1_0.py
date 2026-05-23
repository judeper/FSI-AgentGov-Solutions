#!/usr/bin/env python3
"""
CTSG v1.1.0 [BREAKING DEPLOY] — Option Set Value Re-Keying Script.

Re-keys all fsi_ctsg_* picklist column values on existing rows from 0-based
(legacy v1.0.x) to 100000000-based (Dataverse default, v1.1.0). The shared
fsi_acv_zone option set is intentionally NOT migrated by this script — it
remains 0-based for cross-solution compatibility (see
create_ctsg_dataverse_schema.py SHARED_OPTIONSETS comment).

Run order (per release notes):
    1. python create_ctsg_dataverse_schema.py     # publish new metadata
    2. python migrate_ctsg_optionsets_v1_1_0.py   # re-key existing rows
    3. Re-publish flows that reference the picklist integers

USAGE
-----
Dry-run (no changes — prints planned PATCH bodies):

    python migrate_ctsg_optionsets_v1_1_0.py \\
        --tenant-id <tenant-guid> \\
        --environment-url https://<org>.crm.dynamics.com \\
        --interactive --client-id <app-id> \\
        --dry-run

Live run (managed-identity-first):

    python migrate_ctsg_optionsets_v1_1_0.py \\
        --environment-url https://<org>.crm.dynamics.com \\
        --auth-mode managed-identity --client-id <user-assigned-mi-client-id>

ROLLBACK
--------
A symmetrical rollback (re-key 100000000-based → 0-based) is intentionally NOT
provided. If a roll-back is required, restore from a pre-migration Dataverse
backup taken at step 0 of the deployment guide.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "shared"))

from dataverse_client import DataverseClient  # noqa: E402


# Entity set name → list of picklist columns bound to fsi_ctsg_* option sets.
# Source of truth: create_ctsg_dataverse_schema.py CTSG_OPTIONSETS + table column lists.
# fsi_acv_zone (SHARED) and any agent_zone references are deliberately excluded.
ENTITY_PICKLISTS: dict[str, list[str]] = {
    "fsi_approvedexternaltenants": [
        "fsi_relationshiptype",
        "fsi_approvalstatus",
        "fsi_risktier",
        "fsi_ppisolationdirection",
    ],
    "fsi_externalsharefindings": [
        "fsi_findingtype",
        "fsi_findingstatus",
        "fsi_severity",
        "fsi_governancelayer",
        "fsi_remediationstatus",
        "fsi_guestdetectionmethod",
    ],
    "fsi_tenantisolationrecords": [
        "fsi_compliancestatus",
    ],
    "fsi_entractarecords": [
        "fsi_compliancestatus",
    ],
    "fsi_crosstenantcomplianceevents": [
        "fsi_eventtype",
        "fsi_complianceimpact",
    ],
}

# Per Dataverse convention, the row primary key column = "<entity-logical-name>id".
PRIMARY_KEY: dict[str, str] = {
    "fsi_approvedexternaltenants": "fsi_approvedexternaltenantid",
    "fsi_externalsharefindings": "fsi_externalsharefindingid",
    "fsi_tenantisolationrecords": "fsi_tenantisolationrecordid",
    "fsi_entractarecords": "fsi_entractarecordid",
    "fsi_crosstenantcomplianceevents": "fsi_crosstenantcomplianceeventid",
}

OFFSET = 100_000_000


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Re-key CTSG picklist values from 0-based to 100000000-based (v1.1.0 BREAKING DEPLOY).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--tenant-id", default=os.environ.get("AZURE_TENANT_ID"),
                   help="Microsoft Entra ID tenant GUID. Falls back to $AZURE_TENANT_ID.")
    p.add_argument("--environment-url", required=True,
                   help="Dataverse environment URL (e.g., https://org.crm.dynamics.com).")
    p.add_argument("--client-id", default=os.environ.get("AZURE_CLIENT_ID"),
                   help="App / managed-identity client ID. Falls back to $AZURE_CLIENT_ID.")
    p.add_argument("--client-secret", default=os.environ.get("AZURE_CLIENT_SECRET"),
                   help="Client secret (legacy: dev-only). Prefer managed identity.")
    p.add_argument("--auth-mode",
                   choices=["interactive", "managed-identity", "workload-identity",
                            "certificate", "client-secret"],
                   help="Explicit auth mode override.")
    p.add_argument("--interactive", action="store_true",
                   help="Use interactive browser auth (developer machines only).")
    p.add_argument("--dry-run", action="store_true",
                   help="Log planned PATCH calls without sending them.")
    p.add_argument("--verbose", "-v", action="store_true",
                   help="Enable DEBUG logging.")
    return p.parse_args()


def migrate_entity(
    client: DataverseClient,
    entity_set: str,
    columns: list[str],
    log: logging.Logger,
) -> tuple[int, int]:
    """Re-key all picklist columns on rows of ``entity_set``.

    Returns (rows_inspected, patches_applied).
    """
    pk = PRIMARY_KEY[entity_set]
    inspected = 0
    patches = 0

    # Fetch the entire entity set once; we evaluate every picklist column per row
    # in memory. The volume across CTSG tables is governance-scale (~10⁴ rows
    # at most for the busiest table), so a single read pass per entity set is
    # cheaper than one filtered query per column.
    select_cols = [pk, *columns]
    log.info("Reading entity set %s (columns: %s)", entity_set, ", ".join(select_cols))
    rows = client.query(entity_set, select=select_cols)
    log.info("  %d row(s) returned from %s", len(rows), entity_set)

    for row in rows:
        inspected += 1
        row_id = row.get(pk)
        if not row_id:
            log.warning("  Row missing primary key %s; skipping: %s", pk, row)
            continue

        patch_body: dict[str, int] = {}
        for col in columns:
            value = row.get(col)
            if value is None:
                continue
            if not isinstance(value, int):
                log.warning(
                    "  %s(%s).%s is not an int (got %r); skipping column",
                    entity_set, row_id, col, value,
                )
                continue
            if value >= OFFSET:
                log.debug(
                    "  %s(%s).%s already migrated (value=%s); skipping",
                    entity_set, row_id, col, value,
                )
                continue
            patch_body[col] = value + OFFSET

        if not patch_body:
            continue

        log.info("  PATCH %s(%s) -> %s", entity_set, row_id, patch_body)
        client.update_record(entity_set, row_id, patch_body)
        patches += 1

    return inspected, patches


def main() -> int:
    args = parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    log = logging.getLogger("migrate_ctsg_optionsets_v1_1_0")

    if args.dry_run:
        log.warning("DRY RUN: no PATCH requests will be sent.")

    auth_mode = args.auth_mode
    if not auth_mode:
        if args.interactive:
            auth_mode = "interactive"
        elif args.client_secret:
            auth_mode = "client-secret"
        else:
            auth_mode = "managed-identity"

    client = DataverseClient(
        tenant_id=args.tenant_id,
        environment_url=args.environment_url,
        client_id=args.client_id,
        client_secret=args.client_secret,
        interactive=(auth_mode == "interactive"),
        auth_mode=auth_mode,
        dry_run=args.dry_run,
    )

    org = client.test_connection()
    log.info("Connected to Dataverse organization: %s", org.get("name", "<unknown>"))

    totals: dict[str, tuple[int, int]] = {}
    for entity_set, columns in ENTITY_PICKLISTS.items():
        try:
            inspected, patches = migrate_entity(client, entity_set, columns, log)
        except Exception:
            log.exception("Migration failed for %s; aborting before further entities.", entity_set)
            return 2
        totals[entity_set] = (inspected, patches)

    log.info("---- Migration summary ----")
    total_patches = 0
    for entity_set, (inspected, patches) in totals.items():
        log.info("  %-40s rows=%d patches=%d", entity_set, inspected, patches)
        total_patches += patches

    if args.dry_run:
        log.warning("DRY RUN complete. %d row(s) would have been patched.", total_patches)
    else:
        log.info("Migration complete. %d row(s) patched.", total_patches)

    return 0


if __name__ == "__main__":
    sys.exit(main())
