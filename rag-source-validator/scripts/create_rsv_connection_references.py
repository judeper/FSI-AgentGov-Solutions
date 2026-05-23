#!/usr/bin/env python3
"""
Create connection references for RAG Source Validator.

Connection references enable Power Automate flows to access Dataverse,
SharePoint, and Teams for knowledge source validation and alerting.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

CONNECTION_REFS = [
    {
        "logical_name": "fsi_cr_dataverse_ragsourcevalidator",
        "display_name": "Dataverse - RSV",
        "connector": "shared_commondataserviceforapps",
        "description": "Dataverse connector for validation persistence — knowledge sources, results, and change records",
    },
    {
        "logical_name": "fsi_cr_sharepoint_ragsourcevalidator",
        "display_name": "SharePoint - RSV",
        "connector": "shared_sharepointonline",
        "description": "SharePoint connector for source content access — document libraries, lists, and pages",
    },
    {
        "logical_name": "fsi_cr_teams_ragsourcevalidator",
        "display_name": "Teams - RSV",
        "connector": "shared_teams",
        "description": "Teams connector for validation failure alert notifications",
    },
]


def create_connection_references(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create connection references for RSV Power Automate flows.

    Args:
        client: DataverseClient instance
        dry_run: If True, preview changes without creating

    Returns:
        dict: Results summary with created/skipped/errors counts
    """
    print("\n[Creating Connection References]")
    results = {"created": 0, "skipped": 0, "errors": 0}

    for conn_ref in CONNECTION_REFS:
        logical_name = conn_ref["logical_name"]
        try:
            # Check if connection reference already exists
            if not dry_run and not client.dry_run:
                existing = client.query(
                    "connectionreferences",
                    filter_expr=f"connectionreferencelogicalname eq '{logical_name}'"
                )
                if existing:
                    print(f"  {logical_name}: already exists, skipping")
                    results["skipped"] += 1
                    continue
            elif dry_run or client.dry_run:
                print(f"  [DRY RUN] {logical_name}: would check if exists")

            # Create connection reference
            if dry_run or client.dry_run:
                print(f"  [DRY RUN] {logical_name}: would create")
                print(f"    Display name: {conn_ref['display_name']}")
                print(f"    Connector: {conn_ref['connector']}")
                results["created"] += 1
            else:
                data = {
                    "connectionreferencelogicalname": logical_name,
                    "connectionreferencedisplayname": conn_ref["display_name"],
                    "connectorid": f"/providers/Microsoft.PowerApps/apis/{conn_ref['connector']}",
                    "description": conn_ref.get("description", ""),
                }
                client.create_record("connectionreferences", data)

                print(f"  {logical_name}: created")
                print(f"    Display name: {conn_ref['display_name']}")
                print(f"    Connector: {conn_ref['connector']}")
                results["created"] += 1

        except Exception as e:
            print(f"  {logical_name}: ERROR - {e}")
            results["errors"] += 1

    print()
    print(f"  Summary: {results['created']} created, {results['skipped']} skipped")
    if results["errors"] > 0:
        print(f"  Errors: {results['errors']}")

    return results


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create connection references for RAG Source Validator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Connection references created:
  - fsi_cr_dataverse_ragsourcevalidator (Dataverse connector)
  - fsi_cr_sharepoint_ragsourcevalidator (SharePoint connector)
  - fsi_cr_teams_ragsourcevalidator (Teams connector)

These connection references must be bound to actual connections in Power Automate
before flows can use them.

Examples:
  # Interactive authentication
  python create_rsv_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_rsv_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_rsv_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("RSV_TENANT_ID"),
        help="Microsoft Entra tenant ID (or RSV_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("RSV_CLIENT_ID"),
        help="Application/client ID for user-assigned managed identity, workload identity, certificate, or legacy client-secret auth (or RSV_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("RSV_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or RSV_ENVIRONMENT_URL env var)"
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication"
    )
    parser.add_argument(
        "--auth-mode",
        choices=["interactive", "managed-identity", "workload-identity", "certificate", "client-secret"],
        default=os.environ.get("RSV_AUTH_MODE"),
        help="Authentication mode; prefer managed-identity, workload-identity, or certificate for automation"
    )
    parser.add_argument(
        "--access-token",
        default=os.environ.get("RSV_ACCESS_TOKEN"),
        help="Externally acquired Dataverse bearer token; takes precedence over other auth modes"
    )
    parser.add_argument(
        "--certificate-path",
        default=os.environ.get("RSV_CERTIFICATE_PATH"),
        help="PEM/PFX certificate path for certificate authentication"
    )
    parser.add_argument(
        "--certificate-password-env",
        default="RSV_CERTIFICATE_PASSWORD",
        help="Environment variable name containing the certificate password"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without creating resources"
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.environment_url:
        parser.error("--environment-url is required (or set RSV_ENVIRONMENT_URL)")
    if not args.access_token and not args.tenant_id:
        parser.error("--tenant-id is required unless --access-token is provided (or set RSV_TENANT_ID)")

    # Handle client secret for Service Principal auth
    client_secret = os.environ.get("RSV_CLIENT_SECRET")
    auth_mode = "interactive" if args.interactive else (
        args.auth_mode or ("client-secret" if client_secret else "managed-identity")
    )
    if not args.access_token and auth_mode in {"interactive", "workload-identity", "certificate", "client-secret"} and not args.client_id:
        parser.error("--client-id is required for the selected auth mode (or set RSV_CLIENT_ID env var)")

    # legacy: dev-only -- replace with managed identity, workload identity federation, or certificate auth in production
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
            auth_mode=auth_mode,
            certificate_path=args.certificate_path,
            certificate_password=certificate_password,
        )
        client.dry_run = args.dry_run

        # Create connection references
        results = create_connection_references(client, dry_run=args.dry_run)

        # Exit with error if any failures
        if results["errors"] > 0:
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
