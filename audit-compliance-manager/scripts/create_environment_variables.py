#!/usr/bin/env python3
"""
Create Dataverse environment variables for Audit Configuration Validator.

Environment variables store configurable zone thresholds and operational parameters.
"""

import argparse
import os
import sys
from typing import Optional

from acv_client import ACVClient

# ============================================================================
# Environment Variable Definitions
# ============================================================================

ENV_VARIABLES = [
    {
        "schemaname": "fsi_ACV_Zone1RetentionDays",
        "displayname": "ACV - Zone 1 Retention Days",
        "description": "Minimum audit retention days for Zone 1 (Personal Productivity)",
        "type": "Decimal",
        "defaultvalue": "180",
    },
    {
        "schemaname": "fsi_ACV_Zone2RetentionDays",
        "displayname": "ACV - Zone 2 Retention Days",
        "description": "Minimum audit retention days for Zone 2 (Team Collaboration)",
        "type": "Decimal",
        "defaultvalue": "365",
    },
    {
        "schemaname": "fsi_ACV_Zone3RetentionDays",
        "displayname": "ACV - Zone 3 Retention Days",
        "description": "Minimum audit retention days for Zone 3 (Enterprise Managed)",
        "type": "Decimal",
        "defaultvalue": "730",
    },
    {
        "schemaname": "fsi_ACV_GracePeriodHours",
        "displayname": "ACV - Grace Period Hours",
        "description": "Hours to wait after audit enablement before alerting",
        "type": "Decimal",
        "defaultvalue": "24",
    },
    {
        "schemaname": "fsi_ACV_CanaryWaitMinutes",
        "displayname": "ACV - Canary Wait Minutes",
        "description": "Minutes to wait for canary event propagation",
        "type": "Decimal",
        "defaultvalue": "5",
    },
]


def create_environment_variables(client: ACVClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for zone thresholds and operational parameters.

    Args:
        client: Authenticated ACVClient
        dry_run: If True, preview without creating

    Returns:
        Results dict with created/skipped counts
    """
    print("\n[Creating Environment Variables]")

    results = {"created": 0, "skipped": 0, "errors": 0}

    for var in ENV_VARIABLES:
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
                print(f"    Type: {var['type']}, Default: {var['defaultvalue']}")
                results["created"] += 1
            else:
                # Create environment variable definition
                definition_data = {
                    "schemaname": schemaname,
                    "displayname": var["displayname"],
                    "description": var["description"],
                    "type": 100000001 if var["type"] == "Decimal" else 100000000,  # Decimal=100000001, String=100000000
                }

                definition_id = client.create_record(
                    "environmentvariabledefinitions", definition_data
                )

                # Create environment variable value (current value)
                value_data = {
                    "value": var["defaultvalue"],
                    "environmentvariabledefinitionid@odata.bind": f"/environmentvariabledefinitions({definition_id})",
                }

                client.create_record("environmentvariablevalues", value_data)

                print(f"  {schemaname}: created")
                print(f"    Type: {var['type']}, Default: {var['defaultvalue']}")
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


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create environment variables for ACV",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ACV_TENANT_ID"),
        help="Entra ID tenant ID",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ACV_CLIENT_ID"),
        help="Application (client) ID",
    )
    # Client secret read from ACV_CLIENT_SECRET env var (not CLI arg to avoid shell history exposure)
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ACV_ENVIRONMENT_URL"),
        help="Dataverse environment URL",
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

    # Validate auth mode
    if not args.interactive and not args.client_id:
        parser.error(
            "Either --interactive or --client-id is required.\n"
            "Use --interactive for manual runs or provide Service Principal credentials."
        )
    if args.interactive and not args.client_id:
        parser.error(
            "--client-id is required for interactive authentication.\n"
            "Register an app in Entra ID and provide --client-id."
        )

    # Get client secret from env var or prompt (never via CLI arg to avoid shell history exposure)
    client_secret = os.environ.get("ACV_CLIENT_SECRET")
    if not args.interactive and args.client_id and not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")

    try:
        client = ACVClient(
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
