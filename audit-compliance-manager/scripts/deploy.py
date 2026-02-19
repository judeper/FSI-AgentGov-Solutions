#!/usr/bin/env python3
"""
ACV Deployment Orchestrator.

Creates all Dataverse components for Audit Configuration Validator:
- Global option sets (choices)
- Tables (AuditValidationHistory, EnvironmentRegistry)
- Columns on each table
- Environment variables (zone thresholds, operational parameters)
- Connection references (Dataverse, Office 365)

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

    # With Service Principal (for CI/CD — set ACV_CLIENT_SECRET env var)
    ACV_CLIENT_SECRET=<secret> python deploy.py --environment-url https://org.crm.dynamics.com \\
        --tenant-id <tenant-id> --client-id <app-id>
"""

import argparse
import os
import sys
from typing import Optional

from acv_client import ACVClient
from create_dataverse_schema import create_schema
from create_environment_variables import create_environment_variables
from create_connection_references import create_connection_references


def print_banner():
    """Print deployment banner."""
    print()
    print("=" * 70)
    print("  Audit Configuration Validator - Dataverse Deployment")
    print("=" * 70)
    print()
    print("  This script deploys ACV components to Dataverse:")
    print("    - Option sets (severity, scope, zone, env status, env type)")
    print("    - AuditValidationHistory table (org-owned, 12 columns, immutable)")
    print("    - EnvironmentRegistry table (org-owned, 9 columns)")
    print("    - Environment variables (zone thresholds, operational params)")
    print("    - Connection references (Dataverse, Office 365)")
    print()


def deploy(
    client: ACVClient,
    dry_run: bool = False,
    tables_only: bool = False,
    vars_only: bool = False,
    refs_only: bool = False,
    verbose: bool = False,
) -> bool:
    """
    Deploy all ACV components to Dataverse.

    Args:
        client: Authenticated ACVClient
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
        # Test connection first (unless dry run mode with client dry_run enabled)
        if not (dry_run or client.dry_run):
            print("[Testing Connection]")
            org = client.test_connection()
            print(f"  Connected to: {org.get('name', 'Unknown')}")
            print()

        if vars_only:
            # Only deploy environment variables
            create_environment_variables(client, dry_run=dry_run)

        elif refs_only:
            # Only deploy connection references
            create_connection_references(client, dry_run=dry_run)

        elif tables_only:
            # Only deploy schema (option sets, tables, columns)
            create_schema(client, dry_run=dry_run)

        else:
            # Full deployment
            # Step 1: Schema (option sets, tables, columns)
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

        # Final summary
        print("\n" + "=" * 70)
        if dry_run or client.dry_run:
            print("  DRY RUN COMPLETE")
            print("  Review output above to see what would be created.")
            print("  Run without --dry-run to apply changes.")
        else:
            print("  DEPLOYMENT COMPLETE")
            print()
            print("  Next Steps:")
            print("    1. Create Power Automate flows (manual)")
            print("       - Daily scheduled tenant validation")
            print("       - Daily scheduled environment validation")
            print("       - Grace period alerting")
            print()
            print("    2. Configure alerting (manual)")
            print("       - Teams notifications for failures")
            print("       - Email alerts for grace period expirations")
            print()
            print("    3. Validate deployment:")
            print("       python acv_client.py --environment-url ... --test-connection")
            print()
            print("  IMPORTANT: Security Configuration Required")
            print("    - AuditValidationHistory is organization-owned for immutability")
            print("    - Security roles must remove Write/Delete privileges")
            print("    - Only allow Create (append-only) for automation accounts")
            print("    - See docs/deployment-guide.md for security configuration details")
        print("=" * 70)
        print()

    except Exception as e:
        print(f"\nERROR: {e}", file=sys.stderr)
        success = False

    return success


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Deploy ACV components to Dataverse",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Full deployment with interactive auth (recommended for first run)
  python deploy.py --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> --interactive

  # Dry run to preview changes
  python deploy.py --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> --interactive --dry-run

  # With Service Principal (for CI/CD — set ACV_CLIENT_SECRET env var)
  ACV_CLIENT_SECRET=<secret> python deploy.py --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> --client-id <app-id>
        """,
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ACV_TENANT_ID"),
        required=not os.environ.get("ACV_TENANT_ID"),
        help="Entra ID tenant ID (or set ACV_TENANT_ID env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ACV_ENVIRONMENT_URL"),
        required=not os.environ.get("ACV_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ACV_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ACV_CLIENT_ID"),
        help="Application (client) ID for Service Principal auth",
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

    # Validate mutually exclusive flags
    exclusive_flags = [args.tables_only, args.vars_only, args.refs_only]
    if sum(exclusive_flags) > 1:
        parser.error("Cannot use multiple selective deployment flags together")

    # Get client secret from env var or prompt (never via CLI arg to avoid shell history exposure)
    client_secret = os.environ.get("ACV_CLIENT_SECRET")
    if not args.interactive and args.client_id and not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")

    print_banner()

    if args.dry_run:
        print("*** DRY RUN MODE - No changes will be made ***")
        print()

    try:
        # Initialize client
        client = ACVClient(
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
