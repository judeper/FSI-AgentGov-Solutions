#!/usr/bin/env python3
"""Deploy Model Risk Management Automation infrastructure to Dataverse.

Orchestrates the full deployment pipeline:
  1. Test Connection -- validate Dataverse API access
  2. Dataverse Schema -- tables, columns, shared and MRM option sets
  3. Environment Variables -- MRM configuration thresholds
  4. Connection References -- Power Automate connector bindings

All operations are idempotent -- safe to re-run. Supports selective
deployment via --tables-only, --vars-only, --refs-only flags.
"""

import argparse
import os
import sys
import time

from mrm_client import MRMClient
from create_mrm_dataverse_schema import create_schema
from create_mrm_environment_variables import create_environment_variables
from create_mrm_connection_references import create_connection_references


# =============================================================================
# Post-Deployment Guidance
# =============================================================================

POST_DEPLOYMENT_GUIDANCE = """
═══════════════════════════════════════════════════════════
Post-Deployment Steps
═══════════════════════════════════════════════════════════

1. SECURITY -- Configure fsi_mrmcomplianceevent security role:
   - Navigate to Settings > Security > Security Roles
   - Remove Delete privileges for fsi_MrmComplianceEvent for all
     roles except System Administrator
   - This supports immutable audit records (OCC 2011-12, SOX 302)

2. LTR -- Enable Dataverse Long-Term Retention:
   - Enable on fsi_mrmcomplianceevent with 7-year retention policy
   - Required for SOX 302/404 and SEC 17a-4 compliance

3. ALTERNATE KEY -- Verify fsi_ModelInventoryUniqueKey status:
   - Navigate to Tables > Model Inventory > Keys
   - Confirm status is Active (may take a few minutes)

4. CONNECTIONS -- Bind connection references in Power Automate:
   - fsi_cr_dataverse_mrm    -> Select Dataverse connection
   - fsi_cr_teams_mrm        -> Select Teams connection
   - fsi_cr_approvals_mrm    -> Select Approvals connection
   - fsi_cr_http_mrm         -> Select HTTP with Microsoft Entra ID connection
   - fsi_cr_sharepoint_mrm   -> Select SharePoint connection
   - fsi_cr_wordonline_mrm   -> Select Word Online (Business) connection

5. SHAREPOINT -- Create Agent Card Library:
   - Create SharePoint site at MRMSiteUrl
   - Create "Agent Cards" document library
   - Deploy AgentCard-Template.docx to the library root

6. FEATURE FLAG -- Set IsMRMAutomationEnabled:
   - Verify all tables, connections, and SharePoint are configured
   - Set fsi_MRM_IsMRMAutomationEnabled to "true" to activate flows

7. PREREQUISITE -- Verify agent-registry-automation:
   - Confirm fsi_agentinventory table is accessible
   - Run: python deploy.py --dry-run to validate
"""


# =============================================================================
# Deployment Pipeline
# =============================================================================


def run_deployment(
    client: MRMClient,
    dry_run: bool = False,
    tables_only: bool = False,
    vars_only: bool = False,
    refs_only: bool = False,
    verbose: bool = False,
) -> None:
    """Execute the MRM deployment pipeline.

    Runs all deployment steps in order unless selective flags are set.
    When a selective flag is provided, only that step runs.

    Args:
        client: Authenticated MRMClient instance
        dry_run: Preview mode flag
        tables_only: Deploy only Dataverse schema
        vars_only: Deploy only environment variables
        refs_only: Deploy only connection references
        verbose: Enable verbose output
    """
    selective = tables_only or vars_only or refs_only
    start_time = time.time()

    print()
    print("=" * 60)
    print("Model Risk Management Automation \u2014 Dataverse Deployment")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN -- No changes will be made ***")

    if selective:
        modes = []
        if tables_only:
            modes.append("tables")
        if vars_only:
            modes.append("environment variables")
        if refs_only:
            modes.append("connection references")
        print(f"\nSelective deployment: {', '.join(modes)}")

    # Step 1: Test Connection
    print("\n" + "-" * 60)
    print("Step 1/4: Test Connection")
    print("-" * 60)

    try:
        org = client.test_connection()
        if verbose and not dry_run:
            print(f"  Organization: {org.get('name', 'Unknown')}")
        print("  Connection: OK")
    except Exception as e:
        print(f"  Connection FAILED: {e}", file=sys.stderr)
        print(
            "\nDeployment aborted -- cannot connect to Dataverse.",
            file=sys.stderr,
        )
        sys.exit(2)

    # Step 2: Dataverse Schema
    if not selective or tables_only:
        print("\n" + "-" * 60)
        print("Step 2/4: Dataverse Schema")
        print("-" * 60)
        create_schema(client, dry_run=dry_run)

    # Step 3: Environment Variables
    if not selective or vars_only:
        print("\n" + "-" * 60)
        print("Step 3/4: Environment Variables")
        print("-" * 60)
        create_environment_variables(client, dry_run=dry_run)

    # Step 4: Connection References
    if not selective or refs_only:
        print("\n" + "-" * 60)
        print("Step 4/4: Connection References")
        print("-" * 60)
        create_connection_references(client, dry_run=dry_run)

    # Completion
    elapsed = time.time() - start_time
    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE")
    else:
        print("DEPLOYMENT COMPLETE")
    print(f"  Elapsed: {elapsed:.1f}s")
    print("=" * 60)

    # Post-deployment guidance (full pipeline only, not selective)
    if not selective:
        print(POST_DEPLOYMENT_GUIDANCE)


# =============================================================================
# CLI Entry Point
# =============================================================================


def main():
    """CLI entry point for MRM deployment orchestrator."""
    parser = argparse.ArgumentParser(
        description=(
            "Deploy Model Risk Management Automation infrastructure "
            "to Dataverse"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Full deployment with interactive auth\n"
            "  python deploy.py --interactive\n\n"
            "  # Dry run (preview all changes)\n"
            "  python deploy.py --dry-run --interactive\n\n"
            "  # Deploy only tables with service principal\n"
            "  python deploy.py --tables-only \\\n"
            "    --tenant-id $MRM_TENANT_ID \\\n"
            "    --client-id $MRM_CLIENT_ID \\\n"
            "    --client-secret $MRM_CLIENT_SECRET \\\n"
            "    --environment-url $MRM_ENVIRONMENT_URL\n\n"
            "  # Deploy only environment variables\n"
            "  python deploy.py --vars-only --interactive\n\n"
            "  # Deploy only connection references\n"
            "  python deploy.py --refs-only --interactive\n\n"
            "Environment variables:\n"
            "  MRM_TENANT_ID        Microsoft Entra ID tenant ID\n"
            "  MRM_CLIENT_ID        Service principal app ID\n"
            "  MRM_CLIENT_SECRET    Service principal secret\n"
            "  MRM_ENVIRONMENT_URL  Dataverse environment URL\n"
        ),
    )

    # Authentication arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("MRM_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set MRM_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("MRM_CLIENT_ID"),
        help="Service principal app ID (or set MRM_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("MRM_CLIENT_SECRET"),
        help="Service principal secret (or set MRM_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("MRM_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set MRM_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )

    # Deployment mode arguments
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be deployed without making changes",
    )
    parser.add_argument(
        "--tables-only",
        action="store_true",
        help="Deploy only Dataverse schema (tables and columns)",
    )
    parser.add_argument(
        "--vars-only",
        action="store_true",
        help="Deploy only environment variables",
    )
    parser.add_argument(
        "--refs-only",
        action="store_true",
        help="Deploy only connection references",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose output",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id:
        print("ERROR: --tenant-id or MRM_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or MRM_ENVIRONMENT_URL required")
        sys.exit(1)
    if not args.interactive and (not args.client_id or not args.client_secret):
        print(
            "ERROR: --client-id and --client-secret required "
            "(or use --interactive)"
        )
        sys.exit(1)

    try:
        client = MRMClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        run_deployment(
            client,
            dry_run=args.dry_run,
            tables_only=args.tables_only,
            vars_only=args.vars_only,
            refs_only=args.refs_only,
            verbose=args.verbose,
        )

    except KeyboardInterrupt:
        print("\nDeployment cancelled by user.")
        sys.exit(130)
    except Exception as e:
        print(f"\nDeployment error: {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
