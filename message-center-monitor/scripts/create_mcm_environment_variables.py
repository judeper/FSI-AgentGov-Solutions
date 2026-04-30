#!/usr/bin/env python3
"""
Create Dataverse environment variables for Message Center Monitor.

Environment variables store configurable polling intervals, notification targets,
and connection settings for M365 Message Center monitoring.
"""

import argparse
import logging
import os
import sys

import requests

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

logger = logging.getLogger(__name__)

# Dataverse environment variable type option-set values
TYPE_CODES = {
    "String": 100000000,
    "Number": 100000001,
    "Boolean": 100000002,
    "JSON": 100000003,
    "DataSource": 100000004,
    "Secret": 100000005,
}

ENV_VARIABLES = [
    {
        "schemaname": "fsi_MCM_PollingIntervalDays",
        "displayname": "MCM - Polling Interval (Days)",
        "description": "Days between Message Center polling cycles (default: 1)",
        "type": "Number",
        "defaultvalue": "1",
    },
    {
        "schemaname": "fsi_MCM_NotifySeverities",
        "displayname": "MCM - Notify Severities",
        "description": "Comma-separated severity levels that trigger notifications (default: high,critical)",
        "type": "String",
        "defaultvalue": "high,critical",
    },
    {
        "schemaname": "fsi_MCM_TeamsTeamId",
        "displayname": "MCM - Teams Team ID",
        "description": "Teams team ID for posting Message Center notifications",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_MCM_TeamsChannelId",
        "displayname": "MCM - Teams Channel ID",
        "description": "Teams channel ID for posting Message Center notifications",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_MCM_DataverseUrl",
        "displayname": "MCM - Dataverse URL",
        "description": "Dataverse environment URL for API calls",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_MCM_KeyVaultSecretName",
        "displayname": "MCM - Key Vault Secret Name",
        "description": "Key Vault secret name for Graph API client secret (default: MessageCenterClientSecret)",
        "type": "String",
        "defaultvalue": "MessageCenterClientSecret",
    },
]


def create_environment_variables(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for Message Center monitoring and notification.

    Args:
        client: DataverseClient instance
        dry_run: If True, preview changes without creating

    Returns:
        dict: Results summary with created/skipped/errors counts
    """
    print("\n[Creating Environment Variables]")
    results = {"created": 0, "skipped": 0, "errors": 0}

    for var in ENV_VARIABLES:
        schemaname = var["schemaname"]
        try:
            # Check if variable already exists
            if not dry_run and not client.dry_run:
                existing = client.query(
                    "environmentvariabledefinitions",
                    filter_expr=f"schemaname eq '{schemaname}'",
                )
                if existing:
                    logger.info(f"  {schemaname}: already exists, skipping")
                    results["skipped"] += 1
                    continue
            elif dry_run or client.dry_run:
                logger.info(f"  [DRY RUN] {schemaname}: would check if exists [dry-run: existence not verified]")

            # Create variable
            if dry_run or client.dry_run:
                logger.info(f"  [DRY RUN] {schemaname}: would create  [dry-run: existence not verified]")
                logger.info(f"    Type: {var['type']}, Default: {var['defaultvalue']}")
                results["created"] += 1
            else:
                # Map type to Dataverse type code (raises KeyError on unknown)
                type_code = TYPE_CODES[var["type"]]

                # Create definition
                definition_data = {
                    "schemaname": schemaname,
                    "displayname": var["displayname"],
                    "description": var["description"],
                    "type": type_code,
                }
                definition_id = client.create_record(
                    "environmentvariabledefinitions", definition_data
                )

                # Create default value; roll back definition on failure
                try:
                    value_data = {
                        "value": var["defaultvalue"],
                        "environmentvariabledefinitionid@odata.bind": f"/environmentvariabledefinitions({definition_id})",
                    }
                    client.create_record("environmentvariablevalues", value_data)
                except Exception as val_err:
                    logger.error(f"  {schemaname}: value creation failed, rolling back definition - {val_err}")
                    try:
                        client.delete_record("environmentvariabledefinitions", definition_id)
                    except Exception as cleanup_err:
                        logger.warning(f"  {schemaname}: WARNING - rollback failed, orphaned definition {definition_id} - {cleanup_err}")
                    raise

                logger.info(f"  {schemaname}: created")
                logger.info(f"    Type: {var['type']}, Default: {var['defaultvalue']}")
                results["created"] += 1

        except Exception as e:
            logger.error(f"  {schemaname}: ERROR - {e}")
            results["errors"] += 1

    logger.info("")
    logger.info(f"  Summary: {results['created']} created, {results['skipped']} skipped")
    if results["errors"] > 0:
        logger.error(f"  Errors: {results['errors']}")

    return results


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create environment variables for Message Center Monitor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables created:
  - fsi_MCM_PollingIntervalDays (1 day)
  - fsi_MCM_NotifySeverities (high,critical)
  - fsi_MCM_TeamsTeamId
  - fsi_MCM_TeamsChannelId
  - fsi_MCM_DataverseUrl
  - fsi_MCM_KeyVaultSecretName (MessageCenterClientSecret)

Examples:
  # Interactive authentication
  python create_mcm_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_mcm_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_mcm_environment_variables.py \\
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

        # Create environment variables
        results = create_environment_variables(client, dry_run=args.dry_run)

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
