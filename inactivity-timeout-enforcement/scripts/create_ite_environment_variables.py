#!/usr/bin/env python3
"""
Create Dataverse environment variables for Inactivity Timeout Enforcement.

Environment variables store configurable scan settings, notification targets,
and API base URLs for inactivity timeout compliance scanning.
"""

import argparse
import os
import sys
from typing import Optional

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

ENV_VARIABLES = [
    {
        "schemaname": "fsi_ITE_NotificationRecipients",
        "displayname": "ITE - Notification Recipients",
        "description": "Semicolon-separated email list for timeout compliance alerts",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_ITE_BapApiBaseUrl",
        "displayname": "ITE - BAP Admin API Base URL",
        "description": "Business Application Platform Admin API base URL",
        "type": "String",
        "defaultvalue": "https://api.bap.microsoft.com",
    },
    {
        "schemaname": "fsi_ITE_ScanFrequencyHours",
        "displayname": "ITE - Scan Frequency (Hours)",
        "description": "Hours between scheduled inactivity timeout scans (default: 24)",
        "type": "Decimal",
        "defaultvalue": "24",
    },
    {
        "schemaname": "fsi_ITE_DataverseUrl",
        "displayname": "ITE - Dataverse URL",
        "description": "Dataverse environment URL for API calls",
        "type": "String",
        "defaultvalue": "",
    },
]


def create_environment_variables(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for inactivity timeout scanning configuration.

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

                # Create default value; roll back definition on failure
                try:
                    value_data = {
                        "value": var["defaultvalue"],
                        "environmentvariabledefinitionid@odata.bind": f"/environmentvariabledefinitions({definition_id})",
                    }
                    client.create_record("environmentvariablevalues", value_data)
                except Exception as val_err:
                    print(f"  {schemaname}: value creation failed, rolling back definition - {val_err}")
                    try:
                        client.delete_record("environmentvariabledefinitions", definition_id)
                    except Exception as cleanup_err:
                        print(f"  {schemaname}: WARNING - rollback failed, orphaned definition {definition_id} - {cleanup_err}")
                    raise

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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create environment variables for Inactivity Timeout Enforcement",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables created:
  - fsi_ITE_NotificationRecipients (semicolon-separated emails)
  - fsi_ITE_BapApiBaseUrl (https://api.bap.microsoft.com)
  - fsi_ITE_ScanFrequencyHours (24 hours)
  - fsi_ITE_DataverseUrl

Examples:
  # Interactive authentication
  python create_ite_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Managed identity authentication (automation)
  python create_ite_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --auth-mode managed-identity

  # Dry run to preview changes
  python create_ite_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ITE_TENANT_ID"),
        help="Microsoft Entra tenant ID (or ITE_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ITE_CLIENT_ID"),
        help="Application/client ID for user-assigned managed identity, workload identity, certificate, or legacy client-secret auth (or ITE_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ITE_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or ITE_ENVIRONMENT_URL env var)"
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
        "--auth-mode",
        choices=["interactive", "managed-identity", "workload-identity", "certificate", "client-secret"],
        default=os.environ.get("ITE_AUTH_MODE"),
        help="Authentication mode; prefer managed-identity, workload-identity, or certificate for automation"
    )
    parser.add_argument(
        "--access-token",
        default=os.environ.get("ITE_ACCESS_TOKEN"),
        help="Externally acquired Dataverse bearer token; takes precedence over other auth modes"
    )
    parser.add_argument(
        "--certificate-path",
        default=os.environ.get("ITE_CERTIFICATE_PATH"),
        help="PEM/PFX certificate path for certificate authentication"
    )
    parser.add_argument(
        "--certificate-password-env",
        default="ITE_CERTIFICATE_PASSWORD",
        help="Environment variable containing the certificate password"
    )

    args = parser.parse_args()

    # Validate required arguments and choose managed-identity-first auth.
    if not args.environment_url:
        parser.error("--environment-url is required")
    if not args.access_token and not args.tenant_id:
        parser.error("--tenant-id is required unless --access-token is provided")

    client_secret = os.environ.get("ITE_CLIENT_SECRET")
    auth_mode = "interactive" if args.interactive else (args.auth_mode or ("client-secret" if client_secret else "managed-identity"))
    if not args.access_token and auth_mode in {"interactive", "workload-identity", "certificate", "client-secret"} and not args.client_id:
        parser.error("--client-id is required for the selected auth mode")

    # legacy: dev-only — replace with managed identity, workload identity federation, or certificate auth in production
    if not args.access_token and auth_mode == "client-secret" and not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")

    certificate_password = os.environ.get(args.certificate_password_env) if args.certificate_password_env else None

    try:
        # Initialize client
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            access_token=args.access_token,
            interactive=args.interactive,
            dry_run=args.dry_run,
            auth_mode=auth_mode,
            certificate_path=args.certificate_path,
            certificate_password=certificate_password,
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
