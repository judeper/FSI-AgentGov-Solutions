#!/usr/bin/env python3
"""
Session Security Configurator - Dataverse Deployment Orchestrator.

Deploys all SSC Dataverse components in the correct order:
  1. Schema (option sets, tables, columns)
  2. Environment variables (zone thresholds)
  3. Connection references (Power Automate connectors)
"""

import argparse
import os
import sys
from typing import Optional

from ssc_client import SSCClient
from create_dataverse_schema import create_schema
from create_environment_variables import create_environment_variables
from create_connection_references import create_connection_references


def print_banner():
    """Print deployment banner."""
    print()
    print("=" * 70)
    print("  Session Security Configurator - Dataverse Deployment")
    print("=" * 70)
    print()
    print("This script deploys SSC components to Dataverse:")
    print()
    print("  STEP 1: Schema")
    print("    - Option sets (validation type, zone, severity)")
    print("    - SessionBaseline table (user-owned, 11 columns)")
    print("    - ValidationHistory table (org-owned, 11 columns, immutable)")
    print("    - DriftViolation table (user-owned, 13 columns)")
    print()
    print("  STEP 2: Environment Variables")
    print("    - Zone thresholds: sign-in frequency, authentication strength")
    print()
    print("  STEP 3: Connection References")
    print("    - Dataverse, Office 365, Teams connectors")
    print()
    print("=" * 70)
    print()


def print_next_steps():
    """Print post-deployment next steps."""
    print()
    print("=" * 70)
    print("  DEPLOYMENT COMPLETE - Next Steps")
    print("=" * 70)
    print()
    print("1. Configure Security Roles:")
    print("   - ValidationHistory table is IMMUTABLE (audit trail)")
    print("   - Remove Write and Delete privileges from all user roles")
    print("   - Only system/service accounts should write ValidationHistory")
    print()
    print("2. Bind Connection References:")
    print("   - In Power Automate, bind connection references to actual connections:")
    print("     * fsi_cr_dataverse_sessionvalidation → Dataverse connection")
    print("     * fsi_cr_office365_sessionvalidation → Office 365 connection")
    print("     * fsi_cr_teams_sessionvalidation → Teams connection")
    print()
    print("3. Validate Deployment:")
    print("   python ssc_client.py --test-connection \\")
    print("       --tenant-id <tenant-id> \\")
    print("       --environment-url https://org.crm.dynamics.com \\")
    print("       --interactive")
    print()
    print("4. Configure Zone Thresholds:")
    print("   - Adjust environment variables in Power Platform admin center")
    print("   - Based on your organization's security requirements")
    print()
    print("=" * 70)
    print()


def deploy(
    client: SSCClient,
    dry_run: bool = False,
    tables_only: bool = False,
    vars_only: bool = False,
    refs_only: bool = False,
    verbose: bool = False
) -> bool:
    """
    Orchestrate SSC Dataverse deployment.

    Args:
        client: SSCClient instance
        dry_run: If True, preview changes without creating
        tables_only: If True, deploy only schema (tables/columns)
        vars_only: If True, deploy only environment variables
        refs_only: If True, deploy only connection references
        verbose: If True, show detailed output

    Returns:
        bool: True if deployment succeeded, False otherwise
    """
    success = True

    try:
        # Test connection (unless dry-run)
        if not (dry_run or client.dry_run):
            print("[Testing Connection]")
            org = client.test_connection()
            print(f"  Connected to: {org.get('name', 'Unknown')}")
            print()

        # Selective deployment based on flags
        if vars_only:
            print("[Selective Deployment: Environment Variables Only]")
            print()
            results = create_environment_variables(client, dry_run=dry_run)
            if results["errors"] > 0:
                success = False

        elif refs_only:
            print("[Selective Deployment: Connection References Only]")
            print()
            results = create_connection_references(client, dry_run=dry_run)
            if results["errors"] > 0:
                success = False

        elif tables_only:
            print("[Selective Deployment: Schema/Tables Only]")
            print()
            results = create_schema(client, dry_run=dry_run)
            if results["errors"] > 0:
                success = False

        else:
            # Full deployment: schema → env vars → connection refs
            print("[Full Deployment: All Components]")
            print()

            # STEP 1: Schema
            print("STEP 1/3: Creating Schema (option sets, tables, columns)")
            print("-" * 70)
            schema_results = create_schema(client, dry_run=dry_run)
            if schema_results["errors"] > 0:
                print("\nERROR: Schema creation failed. Stopping deployment.")
                return False

            # STEP 2: Environment Variables
            print()
            print("STEP 2/3: Creating Environment Variables")
            print("-" * 70)
            vars_results = create_environment_variables(client, dry_run=dry_run)
            if vars_results["errors"] > 0:
                print("\nWARNING: Environment variable creation had errors")
                success = False

            # STEP 3: Connection References
            print()
            print("STEP 3/3: Creating Connection References")
            print("-" * 70)
            refs_results = create_connection_references(client, dry_run=dry_run)
            if refs_results["errors"] > 0:
                print("\nWARNING: Connection reference creation had errors")
                success = False

            # Summary
            print()
            print("=" * 70)
            print("  DEPLOYMENT SUMMARY")
            print("=" * 70)
            print()
            print(f"Schema:")
            print(f"  Option Sets: {schema_results.get('option_sets', {}).get('created', 0)} created, "
                  f"{schema_results.get('option_sets', {}).get('skipped', 0)} skipped")
            print(f"  Tables: {schema_results.get('tables', {}).get('created', 0)} created, "
                  f"{schema_results.get('tables', {}).get('skipped', 0)} skipped")
            print()
            print(f"Environment Variables: {vars_results['created']} created, "
                  f"{vars_results['skipped']} skipped")
            print()
            print(f"Connection References: {refs_results['created']} created, "
                  f"{refs_results['skipped']} skipped")
            print()

            total_errors = (
                schema_results.get("errors", 0) +
                vars_results.get("errors", 0) +
                refs_results.get("errors", 0)
            )
            if total_errors > 0:
                print(f"Total Errors: {total_errors}")
                success = False
            else:
                print("Status: All components deployed successfully")

        # Print next steps for successful deployments
        if success and not (dry_run or client.dry_run):
            print_next_steps()
        elif dry_run or client.dry_run:
            print()
            print("[DRY RUN COMPLETE - No changes made]")
            print()

    except Exception as e:
        print(f"\nERROR: Deployment failed: {e}", file=sys.stderr)
        if verbose:
            import traceback
            traceback.print_exc()
        success = False

    return success


def main():
    parser = argparse.ArgumentParser(
        description="Deploy Session Security Configurator components to Dataverse",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Deployment Modes:
  Full deployment (default):
    Deploys schema, environment variables, and connection references in order

  Selective deployment:
    --tables-only: Deploy only schema (option sets, tables, columns)
    --vars-only: Deploy only environment variables
    --refs-only: Deploy only connection references

  Preview mode:
    --dry-run: Show what would be created without making changes

Examples:
  # Full deployment with interactive auth
  python deploy.py \\
      --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> \\
      --interactive

  # Dry run to preview changes
  python deploy.py \\
      --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> \\
      --interactive \\
      --dry-run

  # Deploy only tables/schema
  python deploy.py \\
      --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> \\
      --interactive \\
      --tables-only

  # With Service Principal (for CI/CD)
  python deploy.py \\
      --environment-url https://org.crm.dynamics.com \\
      --tenant-id <tenant-id> \\
      --client-id <app-id> \\
      --client-secret <secret>

Environment Variables (optional):
  SSC_TENANT_ID: Microsoft Entra tenant ID
  SSC_ENVIRONMENT_URL: Dataverse environment URL
  SSC_CLIENT_ID: Service Principal application ID
  SSC_CLIENT_SECRET: Service Principal client secret
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
        help="Service Principal client secret (or SSC_CLIENT_SECRET env var). WARNING: Prefer SSC_CLIENT_SECRET env var to avoid exposing secrets in process lists and shell history"
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

    # Deployment options
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without creating resources"
    )
    parser.add_argument(
        "--tables-only",
        action="store_true",
        help="Deploy only schema (option sets, tables, columns)"
    )
    parser.add_argument(
        "--vars-only",
        action="store_true",
        help="Deploy only environment variables"
    )
    parser.add_argument(
        "--refs-only",
        action="store_true",
        help="Deploy only connection references"
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Show detailed output including errors"
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    # Validate authentication method
    if not args.client_id:
        parser.error("--client-id is required (used for app registration in both interactive and service principal modes)")

    if not args.interactive and not args.client_secret:
        if not os.environ.get("SSC_CLIENT_SECRET"):
            parser.error("Must specify either --interactive or provide --client-secret / SSC_CLIENT_SECRET for service principal authentication")

    # Validate mutual exclusivity of selective deployment flags
    selective_flags = [args.tables_only, args.vars_only, args.refs_only]
    if sum(selective_flags) > 1:
        parser.error("Only one of --tables-only, --vars-only, --refs-only can be specified")

    # Handle client secret for Service Principal auth
    client_secret = args.client_secret
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    # Print banner
    print_banner()

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

        # Execute deployment
        success = deploy(
            client,
            dry_run=args.dry_run,
            tables_only=args.tables_only,
            vars_only=args.vars_only,
            refs_only=args.refs_only,
            verbose=args.verbose
        )

        # Exit with appropriate status code
        sys.exit(0 if success else 1)

    except Exception as e:
        print(f"\nFATAL ERROR: {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
