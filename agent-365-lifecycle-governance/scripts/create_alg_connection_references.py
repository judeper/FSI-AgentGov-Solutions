#!/usr/bin/env python3
"""
Create connection references for Agent 365 Lifecycle Governance.

Connection references enable Power Automate flows to access Dataverse,
Teams, Approvals, Graph API, and Power Platform for agent lifecycle management.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

CONNECTION_REFS = [
    {
        "logical_name": "fsi_cr_dataverse_lifecyclegov",
        "display_name": "Dataverse - ALG",
        "connector": "shared_commondataserviceforapps",
        "description": "Dataverse connector for lifecycle record, sponsor, review, and event tables",
    },
    {
        "logical_name": "fsi_cr_teams_lifecyclegov",
        "display_name": "Teams - ALG",
        "connector": "shared_teams",
        "description": "Teams connector for sponsor assignment and lifecycle notification cards",
    },
    {
        "logical_name": "fsi_cr_approvals_lifecyclegov",
        "display_name": "Approvals - ALG",
        "connector": "shared_approvals",
        "description": "Approvals connector for deactivation and deletion approval workflows",
    },
    {
        "logical_name": "fsi_cr_http_lifecyclegov",
        "display_name": "HTTP with Microsoft Entra ID - ALG",
        "connector": "shared_webcontents",
        "description": "HTTP with Microsoft Entra ID connector for Microsoft Graph API calls (Agent 365, Lifecycle Workflows, Access Reviews)",
    },
    {
        "logical_name": "fsi_cr_powerplatformadmin_lifecyclegov",
        "display_name": "Power Platform for Admins V2 - ALG",
        "connector": "shared_powerplatformforadmins",
        "description": "Power Platform for Admins V2 connector for agent activity data",
    },
]


def create_connection_references(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create connection references for ALG Power Automate flows.

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
        description="Create connection references for Agent 365 Lifecycle Governance",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Connection references created:
  - fsi_cr_dataverse_lifecyclegov (Dataverse connector)
  - fsi_cr_teams_lifecyclegov (Teams connector)
  - fsi_cr_approvals_lifecyclegov (Approvals connector)
  - fsi_cr_http_lifecyclegov (HTTP with Microsoft Entra ID connector)
  - fsi_cr_powerplatformadmin_lifecyclegov (Power Platform for Admins connector)

These connection references must be bound to actual connections in Power Automate
before flows can use them.

Examples:
  # Interactive authentication
  python create_alg_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Managed identity authentication (system-assigned)
  python create_alg_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --auth-mode managed-identity

  # User-assigned managed identity
  python create_alg_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --auth-mode managed-identity \\
      --client-id <managed-identity-client-id>

  # Legacy dev-only client-secret fallback (ALG_CLIENT_SECRET)
  python create_alg_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --auth-mode client-secret \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_alg_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ALG_TENANT_ID"),
        help="Microsoft Entra tenant ID (or ALG_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ALG_CLIENT_ID"),
        help="Application (client) ID for user-assigned managed identity, workload identity, certificate, interactive, or legacy client-secret auth (or ALG_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ALG_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or ALG_ENVIRONMENT_URL env var)"
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication"
    )
    parser.add_argument(
        "--auth-mode",
        choices=["interactive", "managed-identity", "workload-identity", "certificate", "client-secret"],
        default=os.environ.get("ALG_AUTH_MODE"),
        help="Authentication mode. Prefer managed-identity, workload-identity, or certificate for automation; client-secret is legacy dev-only."
    )
    parser.add_argument(
        "--certificate-path",
        default=os.environ.get("ALG_CERTIFICATE_PATH"),
        help="Certificate path for certificate auth (or ALG_CERTIFICATE_PATH env var)"
    )
    parser.add_argument(
        "--certificate-password-env",
        default="ALG_CERTIFICATE_PASSWORD",
        help="Environment variable containing certificate password"
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

    auth_mode = "interactive" if args.interactive else (args.auth_mode or ("client-secret" if os.environ.get("ALG_CLIENT_SECRET") else "managed-identity"))
    client_secret = os.environ.get("ALG_CLIENT_SECRET")
    # legacy: dev-only — replace with managed identity, workload identity federation, or certificate auth in production
    if auth_mode == "client-secret" and not client_secret:
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
            interactive=args.interactive,
            dry_run=args.dry_run,
            auth_mode=auth_mode,
            certificate_path=args.certificate_path,
            certificate_password=certificate_password,
        )

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
