#!/usr/bin/env python3
"""
ELM Deployment Orchestrator.

Creates all Dataverse components for Environment Lifecycle Management:
- Global option sets (choices)
- Tables (EnvironmentRequest, ProvisioningLog)
- Columns on each table
- Security roles with privilege assignments
- Business rules for conditional requirements
- Model-driven app views
- Field security profiles

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

    # Deploy only security roles
    python deploy.py --environment-url https://org.crm.dynamics.com \\
        --tenant-id <tenant-id> --interactive --roles-only

    # With Service Principal (for CI/CD)
    python deploy.py --environment-url https://org.crm.dynamics.com \\
        --tenant-id <tenant-id> --client-id <app-id> --client-secret <secret>
"""

import argparse
import os
import sys
from typing import Optional

from elm_client import ELMClient
from create_dataverse_schema import create_schema
from create_security_roles import create_roles
from create_business_rules import create_business_rules
from create_views import create_views
from create_field_security import create_field_security


def print_banner():
    """Print deployment banner."""
    print()
    print("=" * 70)
    print("  Environment Lifecycle Management - Dataverse Deployment")
    print("=" * 70)
    print()
    print("  This script deploys ELM components to Dataverse:")
    print("    - Option sets (choices) for state, zone, region, etc.")
    print("    - EnvironmentRequest table (user-owned, 22 columns)")
    print("    - ProvisioningLog table (org-owned, 11 columns, immutable)")
    print("    - Security roles (Requester, Approver, Admin, Auditor)")
    print("    - Business rules (conditional required fields)")
    print("    - Model-driven app views")
    print("    - Field security profiles")
    print()


def deploy(
    client: ELMClient,
    dry_run: bool = False,
    tables_only: bool = False,
    roles_only: bool = False,
    verbose: bool = False,
) -> bool:
    """
    Deploy all ELM components to Dataverse.

    Args:
        client: Authenticated ELMClient
        dry_run: If True, show what would be created without making changes
        tables_only: If True, only deploy tables and schema
        roles_only: If True, only deploy security roles
        verbose: If True, show additional output

    Returns:
        True if deployment succeeded, False otherwise
    """
    success = True

    try:
        # Test connection first
        print("[Testing Connection]")
        org = client.test_connection()
        print(f"  Connected to: {org.get('name', 'Unknown')}")
        print()

        if roles_only:
            # Only deploy security roles
            create_roles(client, dry_run=dry_run)

        elif tables_only:
            # Only deploy schema (option sets, tables, columns)
            create_schema(client, dry_run=dry_run)

        else:
            # Full deployment
            # Phase 1: Schema (option sets, tables, columns)
            print("\n" + "=" * 70)
            print("  PHASE 1: Dataverse Schema")
            print("=" * 70)
            create_schema(client, dry_run=dry_run)

            # Phase 2: Security Roles
            print("\n" + "=" * 70)
            print("  PHASE 2: Security Roles")
            print("=" * 70)
            create_roles(client, dry_run=dry_run)

            # Phase 3: Business Rules
            print("\n" + "=" * 70)
            print("  PHASE 3: Business Rules")
            print("=" * 70)
            create_business_rules(client, dry_run=dry_run)

            # Phase 4: Views
            print("\n" + "=" * 70)
            print("  PHASE 4: Model-Driven App Views")
            print("=" * 70)
            create_views(client, dry_run=dry_run)

            # Phase 5: Field Security
            print("\n" + "=" * 70)
            print("  PHASE 5: Field Security Profiles")
            print("=" * 70)
            create_field_security(client, dry_run=dry_run)

        # Final summary
        print("\n" + "=" * 70)
        if dry_run:
            print("  DRY RUN COMPLETE")
            print("  Review output above to see what would be created.")
            print("  Run without --dry-run to apply changes.")
        else:
            print("  DEPLOYMENT COMPLETE")
            print()
            print("  Next Steps:")
            print("    1. Register Service Principal in PPAC (manual)")
            print("       python register_service_principal.py --help")
            print()
            print("    2. Create Environment Groups in PPAC (manual)")
            print("       - FSI-Zone1-PersonalProductivity")
            print("       - FSI-Zone2-TeamCollaboration")
            print("       - FSI-Zone3-EnterpriseManagedEnvironment")
            print()
            print("    3. Create Copilot Studio agent (manual)")
            print("       See docs/copilot-agent-setup.md")
            print()
            print("    4. Create Power Automate flows (manual)")
            print("       See docs/flow-configuration.md")
            print()
            print("    5. Validate deployment:")
            print("       python verify_role_privileges.py --environment-url ...")
            print("       python validate_immutability.py --environment-url ...")
        print("=" * 70)
        print()

    except Exception as e:
        print(f"\nERROR: {e}", file=sys.stderr)
        success = False

    return success


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Deploy ELM components to Dataverse",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Full deployment with interactive auth (recommended for first run)
  python deploy.py --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> --interactive

  # Dry run to preview changes
  python deploy.py --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> --interactive --dry-run

  # With Service Principal (for CI/CD)
  python deploy.py --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> --client-id <app-id> --client-secret <secret>
        """,
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ELM_TENANT_ID"),
        required=not os.environ.get("ELM_TENANT_ID"),
        help="Entra ID tenant ID (or set ELM_TENANT_ID env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ELM_ENVIRONMENT_URL"),
        required=not os.environ.get("ELM_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ELM_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ELM_CLIENT_ID"),
        help="Application (client) ID for Service Principal auth",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ELM_CLIENT_SECRET"),
        help="Client secret for Service Principal auth",
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
        help="Only deploy tables and schema (skip roles, rules, views)",
    )
    parser.add_argument(
        "--roles-only",
        action="store_true",
        help="Only deploy security roles (skip tables, rules, views)",
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

    if args.tables_only and args.roles_only:
        parser.error("Cannot use both --tables-only and --roles-only")

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
        client = ELMClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
        )

        # Run deployment
        success = deploy(
            client,
            dry_run=args.dry_run,
            tables_only=args.tables_only,
            roles_only=args.roles_only,
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
