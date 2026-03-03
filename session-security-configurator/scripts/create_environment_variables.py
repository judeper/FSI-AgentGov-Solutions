#!/usr/bin/env python3
"""
Create Dataverse environment variables for Session Security Configurator.

Environment variables store configurable zone thresholds for sign-in frequency
and authentication strength requirements.
"""

import argparse
import os
import sys
from typing import Optional

from ssc_client import SSCClient

ENV_VARIABLES = [
    {
        "schemaname": "fsi_SSC_Zone1SignInFrequencyMinutes",
        "displayname": "SSC - Zone 1 Sign-In Frequency (Minutes)",
        "description": "Maximum sign-in frequency for Zone 1 Personal Productivity (default: 480 = 8 hours)",
        "type": "Decimal",
        "defaultvalue": "480",
    },
    {
        "schemaname": "fsi_SSC_Zone2SignInFrequencyMinutes",
        "displayname": "SSC - Zone 2 Sign-In Frequency (Minutes)",
        "description": "Maximum sign-in frequency for Zone 2 Team Collaboration (default: 240 = 4 hours)",
        "type": "Decimal",
        "defaultvalue": "240",
    },
    {
        "schemaname": "fsi_SSC_Zone3SignInFrequencyMinutes",
        "displayname": "SSC - Zone 3 Sign-In Frequency (Minutes)",
        "description": "Maximum sign-in frequency for Zone 3 Enterprise Managed (default: 60 = 1 hour)",
        "type": "Decimal",
        "defaultvalue": "60",
    },
    {
        "schemaname": "fsi_SSC_Zone1AuthStrength",
        "displayname": "SSC - Zone 1 Authentication Strength",
        "description": "Required authentication strength for Zone 1 (standard, passwordless, phishing-resistant)",
        "type": "String",
        "defaultvalue": "standard",
    },
    {
        "schemaname": "fsi_SSC_Zone2AuthStrength",
        "displayname": "SSC - Zone 2 Authentication Strength",
        "description": "Required authentication strength for Zone 2 (must match Microsoft Graph DisplayName, e.g. 'Passwordless MFA')",
        "type": "String",
        "defaultvalue": "Passwordless MFA",
    },
    {
        "schemaname": "fsi_SSC_Zone3AuthStrength",
        "displayname": "SSC - Zone 3 Authentication Strength",
        "description": "Required authentication strength for Zone 3 (must match Microsoft Graph DisplayName, e.g. 'Phishing-resistant MFA')",
        "type": "String",
        "defaultvalue": "Phishing-resistant MFA",
    },
]


def create_environment_variables(client: SSCClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for zone-specific session security thresholds.

    Args:
        client: SSCClient instance
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
                    print(f"  {schemaname}: already exists, skipping")
                    results["skipped"] += 1
                    continue
            elif dry_run or client.dry_run:
                print(f"  [DRY RUN] {schemaname}: would check if exists")

            # Create variable
            if dry_run or client.dry_run:
                print(f"  [DRY RUN] {schemaname}: would create")
                print(f"    Type: {var['type']}, Default: {var['defaultvalue']}")
                results["created"] += 1
            else:
                # Map type to Dataverse type code
                type_code = 100000001 if var["type"] == "Decimal" else 100000000

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

                # Create default value
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

    print()
    print(f"  Summary: {results['created']} created, {results['skipped']} skipped")
    if results["errors"] > 0:
        print(f"  Errors: {results['errors']}")

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Create environment variables for Session Security Configurator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables created:
  - fsi_SSC_Zone1SignInFrequencyMinutes (480 minutes = 8 hours)
  - fsi_SSC_Zone2SignInFrequencyMinutes (240 minutes = 4 hours)
  - fsi_SSC_Zone3SignInFrequencyMinutes (60 minutes = 1 hour)
  - fsi_SSC_Zone1AuthStrength (standard)
  - fsi_SSC_Zone2AuthStrength (Passwordless MFA)
  - fsi_SSC_Zone3AuthStrength (Phishing-resistant MFA)

Examples:
  # Interactive authentication
  python create_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id> \\
      --client-secret <secret>

  # Dry run to preview changes
  python create_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("SSC_TENANT_ID"),
        help="Microsoft Entra tenant ID (or SSC_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("SSC_CLIENT_ID"),
        help="Service Principal application ID (or SSC_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("SSC_CLIENT_SECRET"),
        help="Service Principal client secret (or SSC_CLIENT_SECRET env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("SSC_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or SSC_ENVIRONMENT_URL env var)"
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

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    # Handle client secret for Service Principal auth
    client_secret = args.client_secret
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    try:
        # Initialize client
        client = SSCClient(
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

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
