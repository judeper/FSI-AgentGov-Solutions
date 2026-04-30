#!/usr/bin/env python3
"""
Create connection references for Message Center Monitor.

Connection references enable Power Automate flows to access Dataverse, Teams,
Key Vault, and the Graph API for Message Center post monitoring and notifications.
"""

import argparse
import logging
import os
import sys

import requests

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

logger = logging.getLogger(__name__)

CONNECTION_REFS = [
    {
        "logical_name": "fsi_cr_dataverse_messagecenter",
        "display_name": "Dataverse - MCM",
        "connector": "shared_commondataserviceforapps",
        "description": "Dataverse connector for message persistence and assessment tracking",
    },
    {
        "logical_name": "fsi_cr_teams_messagecenter",
        "display_name": "Teams - MCM",
        "connector": "shared_teams",
        "description": "Teams connector for Message Center alert notifications",
    },
    {
        "logical_name": "fsi_cr_keyvault_messagecenter",
        "display_name": "Key Vault - MCM",
        "connector": "shared_keyvault",
        "description": "Key Vault connector for Graph API secret retrieval",
    },
    {
        "logical_name": "fsi_cr_http_messagecenter",
        "display_name": "HTTP - MCM",
        "connector": "shared_httppremium",
        "description": "HTTP connector for Microsoft Graph API calls to Message Center",
    },
]


def create_connection_references(client: DataverseClient, dry_run: bool = False, update: bool = False) -> dict:
    """
    Create connection references for MCM Power Automate flows.

    Args:
        client: DataverseClient instance
        dry_run: If True, preview changes without creating
        update: If True, PATCH existing connection references with current connectorid/display name
                instead of skipping them

    Returns:
        dict: Results summary with created/skipped/updated/errors counts
    """
    logger.info("[Creating Connection References]")
    results = {"created": 0, "skipped": 0, "updated": 0, "errors": 0}

    for conn_ref in CONNECTION_REFS:
        logical_name = conn_ref["logical_name"]
        connector_id = f"/providers/Microsoft.PowerApps/apis/{conn_ref['connector']}"
        try:
            # Check if connection reference already exists
            existing_record = None
            if not dry_run and not client.dry_run:
                existing = client.query(
                    "connectionreferences",
                    filter_expr=f"connectionreferencelogicalname eq '{logical_name}'"
                )
                if existing:
                    existing_record = existing[0]
            elif dry_run or client.dry_run:
                logger.info(f"  [DRY RUN] {logical_name}: would check if exists")

            # Handle existing record
            if existing_record is not None:
                if update:
                    if dry_run or client.dry_run:
                        logger.info(f"  [DRY RUN] {logical_name}: would update (connectorid + display name)")
                        results["updated"] += 1
                    else:
                        record_id = existing_record.get("connectionreferenceid")
                        patch_data = {
                            "connectionreferencedisplayname": conn_ref["display_name"],
                            "connectorid": connector_id,
                        }
                        client.update_record("connectionreferences", record_id, patch_data)
                        logger.info(f"  {logical_name}: updated")
                        logger.info(f"    Display name: {conn_ref['display_name']}")
                        logger.info(f"    Connector: {conn_ref['connector']}")
                        results["updated"] += 1
                else:
                    logger.info(f"  {logical_name}: already exists, skipping (use --update to overwrite)")
                    results["skipped"] += 1
                continue

            # Create connection reference
            if dry_run or client.dry_run:
                logger.info(f"  [DRY RUN] {logical_name}: would create")
                logger.info(f"    Display name: {conn_ref['display_name']}")
                logger.info(f"    Connector: {conn_ref['connector']}")
                results["created"] += 1
            else:
                data = {
                    "connectionreferencelogicalname": logical_name,
                    "connectionreferencedisplayname": conn_ref["display_name"],
                    "connectorid": connector_id,
                    "description": conn_ref.get("description", ""),
                }
                client.create_record("connectionreferences", data)

                logger.info(f"  {logical_name}: created")
                logger.info(f"    Display name: {conn_ref['display_name']}")
                logger.info(f"    Connector: {conn_ref['connector']}")
                results["created"] += 1

        except Exception as e:
            logger.error(f"  {logical_name}: ERROR - {e}")
            results["errors"] += 1

    logger.info("")
    logger.info(
        f"  Summary: {results['created']} created, {results['updated']} updated, "
        f"{results['skipped']} skipped"
    )
    if results["errors"] > 0:
        logger.error(f"  Errors: {results['errors']}")

    return results


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create connection references for Message Center Monitor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Connection references created:
  - fsi_cr_dataverse_messagecenter (Dataverse connector)
  - fsi_cr_teams_messagecenter (Teams connector)
  - fsi_cr_keyvault_messagecenter (Key Vault connector)
  - fsi_cr_http_messagecenter (HTTP Premium connector)

These connection references must be bound to actual connections in Power Automate
before flows can use them.

Examples:
  # Interactive authentication
  python create_mcm_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_mcm_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_mcm_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("MCM_TENANT_ID"),
        help="Microsoft Entra tenant ID (or MCM_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("MCM_CLIENT_ID"),
        help="Service Principal application ID (or MCM_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("MCM_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or MCM_ENVIRONMENT_URL env var)"
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without creating resources"
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="PATCH existing connection references with current connectorid and display name "
             "instead of skipping them"
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging verbosity (default: INFO)"
    )

    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s [%(levelname)s] %(message)s",
    )

    # Validate required arguments
    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    # Handle client secret for Service Principal auth (skip prompt in dry-run)
    client_secret = os.environ.get("MCM_CLIENT_SECRET")
    if not args.interactive and not client_secret and not args.dry_run:
        if args.client_id:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    try:
        # Initialize client
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run
        )

        # Create connection references
        results = create_connection_references(client, dry_run=args.dry_run, update=args.update)

        # Exit with error if any failures
        if results["errors"] > 0:
            sys.exit(1)

    except requests.HTTPError as e:
        logger.error(f"HTTP Error: {e}")
        sys.exit(2)
    except RuntimeError as e:
        logger.error(f"Authentication Error: {e}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Error: {e}")
        sys.exit(4)


if __name__ == "__main__":
    main()
