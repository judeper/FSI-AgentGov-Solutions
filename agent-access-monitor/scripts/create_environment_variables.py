#!/usr/bin/env python3
"""
Create Dataverse environment variables for Agent Access Governance Monitor.

Environment variables store configurable operational parameters such as
scan frequency, grace periods, and alerting configuration.
"""

import argparse
import os
import sys

from aam_client import AAMClient

# ============================================================================
# Environment Variable Definitions
# ============================================================================

ENV_VAR_DEFINITIONS = [
    {
        "schemaname": "fsi_AAM_GracePeriodHours",
        "displayname": "AAM - Grace Period (Hours)",
        "description": "Hours to exclude newly provisioned environments from compliance checks",
        "type": "Decimal",
        "defaultvalue": "48",
    },
    {
        "schemaname": "fsi_AAM_ScanFrequencyHours",
        "displayname": "AAM - Scan Frequency (Hours)",
        "description": "Interval in hours between automated access compliance scans",
        "type": "Decimal",
        "defaultvalue": "24",
    },
    {
        "schemaname": "fsi_AAM_IncludeSandbox",
        "displayname": "AAM - Include Sandbox Environments",
        "description": "Whether to include sandbox environments in access scans (true/false)",
        "type": "String",
        "defaultvalue": "false",
    },
    {
        "schemaname": "fsi_AAM_BaselineMaxAgeDays",
        "displayname": "AAM - Maximum Baseline Age (Days)",
        "description": "Alert threshold in days for stale access baselines requiring refresh",
        "type": "Decimal",
        "defaultvalue": "30",
    },
    {
        "schemaname": "fsi_AAM_TeamsGroupId",
        "displayname": "AAM - Teams Alert Group ID",
        "description": "Microsoft Teams group GUID for sending compliance alert notifications",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_AAM_TeamsChannelId",
        "displayname": "AAM - Teams Alert Channel ID",
        "description": "Microsoft Teams channel GUID for sending compliance alert notifications",
        "type": "String",
        "defaultvalue": "",
    },
]


def create_environment_variables(client: AAMClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for operational parameters.

    Args:
        client: Authenticated AAMClient
        dry_run: If True, preview without creating

    Returns:
        Results dict with created/skipped counts
    """
    print("\n[Creating Environment Variables]")

    results = {"created": 0, "skipped": 0, "errors": 0}

    for var in ENV_VAR_DEFINITIONS:
        schemaname = var["schemaname"]

        # Check if environment variable already exists
        try:
            if not dry_run and not client.dry_run:
                # Query existing environment variable definitions
                existing = client.query(
                    "environmentvariabledefinitions",
                    filter_expr=f"schemaname eq '{schemaname}'",
                )
                if existing:
                    print(f"  {schemaname}: already exists, skipping")
                    results["skipped"] += 1
                    continue
            elif dry_run or client.dry_run:
                print(f"  [DRY RUN] {schemaname}: would check if exists")

            if dry_run or client.dry_run:
                print(f"  [DRY RUN] {schemaname}: would create")
                print(f"    Type: {var['type']}, Default: {var['defaultvalue']!r}")
                results["created"] += 1
            else:
                # Map type string to Dataverse type code
                # Decimal = 100000001, String = 100000000
                type_code = 100000001 if var["type"] == "Decimal" else 100000000

                # Create environment variable definition
                definition_data = {
                    "schemaname": schemaname,
                    "displayname": var["displayname"],
                    "description": var["description"],
                    "type": type_code,
                }

                definition_id = client.create_record(
                    "environmentvariabledefinitions", definition_data
                )

                # Create environment variable value (current value)
                value_data = {
                    "value": var["defaultvalue"],
                    "environmentvariabledefinitionid@odata.bind": (
                        f"/environmentvariabledefinitions({definition_id})"
                    ),
                }

                client.create_record("environmentvariablevalues", value_data)

                print(f"  {schemaname}: created")
                print(f"    Type: {var['type']}, Default: {var['defaultvalue']!r}")
                results["created"] += 1

        except Exception as e:
            print(f"  {schemaname}: ERROR - {e}")
            results["errors"] += 1

    # Summary
    print()
    print(f"  Summary: {results['created']} created, {results['skipped']} skipped")
    if results["errors"] > 0:
        print(f"  Errors: {results['errors']}")

    return results


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create environment variables for Agent Access Governance Monitor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("AAM_TENANT_ID"),
        help="Entra ID tenant ID (or set AAM_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("AAM_CLIENT_ID"),
        help="Application (client) ID (or set AAM_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("AAM_CLIENT_SECRET"),
        help="Client secret (INSECURE: visible in process listings; prefer AAM_CLIENT_SECRET env var or interactive prompt)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("AAM_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set AAM_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be created without making changes",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    # Get client secret if needed
    client_secret = args.client_secret
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass

            client_secret = getpass.getpass("Client secret: ")

    try:
        client = AAMClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        results = create_environment_variables(client, dry_run=args.dry_run)

        if results["errors"] > 0:
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
