#!/usr/bin/env python3
"""
CTSG Deployment Orchestrator.

Creates all Dataverse components for Cross-Tenant External Sharing Governance:
- Tables (ApprovedExternalTenant, ExternalShareFinding, TenantIsolationRecord,
  EntraCTARecord, CrossTenantComplianceEvent)
- Columns on each table
- Environment variables (feature flags, CTA baselines, notification targets)
- Connection references (Dataverse, Teams, Approvals, Graph, Power Platform Admin)

Usage:
    # Full deployment with interactive auth
    python deploy.py --environment-url https://org.crm.dynamics.com \\
        --tenant-id <tenant-id> --interactive

    # Dry run to preview changes
    python deploy.py --environment-url https://org.crm.dynamics.com \\
        --tenant-id <tenant-id> --interactive --dry-run

    # Deploy only tables/schema
    python deploy.py --environment-url https://org.crm.dynamics.com \\
        --tenant-id <tenant-id> --interactive --tables-only

    # With Service Principal (for CI/CD — set CTSG_CLIENT_SECRET env var)
    python deploy.py --environment-url https://org.crm.dynamics.com \\
        --tenant-id <tenant-id> --client-id <app-id>
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

from create_ctsg_dataverse_schema import create_schema
from create_ctsg_environment_variables import create_environment_variables
from create_ctsg_connection_references import create_connection_references


def print_banner():
    """Print deployment banner."""
    print()
    print("=" * 70)
    print("  Cross-Tenant External Sharing Governance - Dataverse Deployment")
    print("=" * 70)
    print()
    print("  This script deploys CTSG components to Dataverse:")
    print("    - Tables (ApprovedExternalTenant, ExternalShareFinding,")
    print("      TenantIsolationRecord, EntraCTARecord,")
    print("      CrossTenantComplianceEvent)")
    print("    - Environment variables (feature flags, CTA baselines,")
    print("      notification targets)")
    print("    - Connection references (Dataverse, Teams, Approvals,")
    print("      Graph, Power Platform Admin)")
    print()


def deploy(
    client: DataverseClient,
    dry_run: bool = False,
    tables_only: bool = False,
    vars_only: bool = False,
    refs_only: bool = False,
    verbose: bool = False,
) -> bool:
    """
    Deploy all CTSG components to Dataverse.

    Args:
        client: Authenticated DataverseClient
        dry_run: If True, show what would be created without making changes
        tables_only: If True, only deploy tables and schema
        vars_only: If True, only deploy environment variables
        refs_only: If True, only deploy connection references
        verbose: If True, show additional output

    Returns:
        True if deployment succeeded, False otherwise
    """
    success = True

    try:
        # Test connection first (unless dry run)
        if not (dry_run or client.dry_run):
            print("[Testing Connection]")
            org = client.test_connection()
            print(f"  Connected to: {org.get('name', 'Unknown')}")
            print()

        if vars_only:
            create_environment_variables(client, dry_run=dry_run)

        elif refs_only:
            create_connection_references(client, dry_run=dry_run)

        elif tables_only:
            create_schema(client, dry_run=dry_run)

        else:
            # Full deployment pipeline
            # Step 1: Schema (tables, columns)
            print("\n" + "=" * 70)
            print("  STEP 1: Dataverse Schema")
            print("=" * 70)
            create_schema(client, dry_run=dry_run)

            # Step 2: Environment Variables
            print("\n" + "=" * 70)
            print("  STEP 2: Environment Variables")
            print("=" * 70)
            create_environment_variables(client, dry_run=dry_run)

            # Step 3: Connection References
            print("\n" + "=" * 70)
            print("  STEP 3: Connection References")
            print("=" * 70)
            create_connection_references(client, dry_run=dry_run)

        # Post-deployment summary
        _print_post_deployment(dry_run or client.dry_run)

    except Exception as e:
        print(f"\nERROR: {e}", file=sys.stderr)
        success = False

    return success


def _print_post_deployment(is_dry_run: bool):
    """Print post-deployment summary and guidance."""
    print()
    print("\u2550" * 60)
    print("  Cross-Tenant External Sharing Governance \u2014 ", end="")

    if is_dry_run:
        print("Dry Run Complete")
        print("\u2550" * 60)
        print()
        print("  Review output above to see what would be created.")
        print("  Run without --dry-run to apply changes.")
    else:
        print("Deployment Complete")
        print("\u2550" * 60)
        print()
        print("  \u2713 Dataverse Schema: tables and columns deployed")
        print("  \u2713 Environment Variables: 12 variables (fsi_CTSG_*)")
        print("  \u2713 Connection References: 7 references (fsi_cr_*_ctsg*)")
        print()
        print("  POST-DEPLOYMENT STEPS:")
        print("  1. Set fsi_CTSG_GovernanceTeamEmail, fsi_CTSG_GovernanceCommitteeUPN,")
        print("     fsi_CTSG_SecurityTeamUPN, and fsi_CTSG_FlowAdministrators")
        print("  2. Bind connection references in Power Automate:")
        print("     - Open make.powerapps.com \u2192 Solutions \u2192 CTSG")
        print("     - Select each connection reference and click \"Set connection\"")
        print("  3. Populate the AllowedTenant table before enabling governance")
        print("  4. Set fsi_CTSG_IsCrossTenantGovernanceEnabled to 'true'")

    print("\u2550" * 60)
    print()


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Deploy CTSG components to Dataverse",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Full deployment with interactive auth (recommended for first run)
  python deploy.py --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> --interactive

  # Dry run to preview changes
  python deploy.py --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> --interactive --dry-run

  # Deploy only environment variables
  python deploy.py --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> --interactive --vars-only

  # With Service Principal (for CI/CD — set CTSG_CLIENT_SECRET env var)
  python deploy.py --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> --client-id <app-id>
        """,
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("CTSG_TENANT_ID"),
        required=not os.environ.get("CTSG_TENANT_ID"),
        help="Entra ID tenant ID (or set CTSG_TENANT_ID env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("CTSG_ENVIRONMENT_URL"),
        required=not os.environ.get("CTSG_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set CTSG_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CTSG_CLIENT_ID"),
        help="Application (client) ID for Service Principal auth",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("CTSG_CLIENT_SECRET"),
        help="Client secret for Service Principal auth (or set CTSG_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication (recommended for manual runs)",
    )

    # Deployment options
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be created without making changes",
    )
    parser.add_argument(
        "--tables-only",
        action="store_true",
        help="Only deploy tables and schema (skip env vars, connection refs)",
    )
    parser.add_argument(
        "--vars-only",
        action="store_true",
        help="Only deploy environment variables (skip tables, connection refs)",
    )
    parser.add_argument(
        "--refs-only",
        action="store_true",
        help="Only deploy connection references (skip tables, env vars)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Show additional output",
    )

    args = parser.parse_args()

    # Validate auth mode
    if not args.interactive and not args.client_id:
        parser.error(
            "Either --interactive or --client-id is required.\n"
            "Use --interactive for manual runs or provide Service Principal credentials."
        )

    # Validate mutually exclusive selective flags
    exclusive_flags = [args.tables_only, args.vars_only, args.refs_only]
    if sum(exclusive_flags) > 1:
        parser.error("Cannot use multiple selective deployment flags together")

    # Get client secret if needed for SP auth
    client_secret = args.client_secret
    if not args.interactive and args.client_id and not client_secret:
        import getpass

        client_secret = getpass.getpass("Client secret: ")

    print_banner()

    if args.dry_run:
        print("*** DRY RUN MODE - No changes will be made ***")
        print()

    try:
        # Initialize client
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        # Run deployment
        success = deploy(
            client,
            dry_run=args.dry_run,
            tables_only=args.tables_only,
            vars_only=args.vars_only,
            refs_only=args.refs_only,
            verbose=args.verbose,
        )

        sys.exit(0 if success else 1)

    except KeyboardInterrupt:
        print("\n\nDeployment cancelled by user.")
        sys.exit(130)
    except Exception as e:
        print(f"\nFatal error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
