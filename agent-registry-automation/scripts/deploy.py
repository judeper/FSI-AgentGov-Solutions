#!/usr/bin/env python3
"""Deploy Agent Registry Automation infrastructure to Dataverse.

Orchestrates the full deployment pipeline:
  1. Test Connection — validate Dataverse API access
  2. Dataverse Schema — tables, columns, option sets, alternate key
  3. Environment Variables — sync and workflow configuration
  4. Connection References — Power Automate connector bindings

All operations are idempotent — safe to re-run. Supports selective
deployment via --tables-only, --vars-only, --refs-only flags.
"""

import argparse
import os
import sys
import time

from ara_client import ARAClient
from create_dataverse_schema import create_schema
from create_environment_variables import create_environment_variables
from create_connection_references import create_connection_references


# =============================================================================
# Post-Deployment Guidance
# =============================================================================

POST_DEPLOYMENT_GUIDANCE = """
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
Post-Deployment Steps
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550

1. SECURITY \u2014 Configure fsi_agentcomplianceevent security role:
   - Navigate to Settings > Security > Security Roles
   - Remove Delete privileges for fsi_AgentComplianceEvent
   - This supports immutable audit records (FINRA 4511, SEC 17a-3)

2. LTR \u2014 Enable Dataverse Long-Term Retention:
   - Navigate to Power Platform admin center > Environments > Settings
   - Enable Long-Term Retention on fsi_agentcomplianceevent
   - Configure 7-year retention policy for regulatory compliance
   - This supports record-keeping requirements (FINRA 4511, SEC 17a-4)

3. ALTERNATE KEY \u2014 Verify fsi_agent_env_uniquekey status:
   - Navigate to Power Platform admin center > Tables > Agent Inventory > Keys
   - Confirm fsi_agent_env_uniquekey status is Active
   - Key activation may take a few minutes after creation

4. CONNECTIONS \u2014 Bind connection references in Power Automate:
   - fsi_cr_dataverse_agentregistry  \u2192 Select Dataverse connection
   - fsi_cr_teams_agentregistry      \u2192 Select Teams connection
   - fsi_cr_office365_agentregistry  \u2192 Select Office 365 connection
   - fsi_cr_http_agentregistry       \u2192 Select HTTP with Azure AD connection

5. VERIFY \u2014 Run dry-run to confirm deployment:
   python deploy.py --dry-run [--interactive | --client-id ...]
"""


# =============================================================================
# Deployment Pipeline
# =============================================================================


def run_deployment(
    client: ARAClient,
    dry_run: bool = False,
    tables_only: bool = False,
    vars_only: bool = False,
    refs_only: bool = False,
    verbose: bool = False,
) -> None:
    """Execute the ARA deployment pipeline.

    Runs all deployment steps in order unless selective flags are set.
    When a selective flag is provided, only that step runs.

    Args:
        client: Authenticated ARAClient instance
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
    print("Agent Registry Automation \u2014 Dataverse Deployment")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN \u2014 No changes will be made ***")

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
            "\nDeployment aborted \u2014 cannot connect to Dataverse.",
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
    """CLI entry point for ARA deployment orchestrator."""
    parser = argparse.ArgumentParser(
        description=(
            "Deploy Agent Registry Automation infrastructure to Dataverse"
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
            "    --tenant-id $ARA_TENANT_ID \\\n"
            "    --client-id $ARA_CLIENT_ID \\\n"
            "    --client-secret $ARA_CLIENT_SECRET \\\n"
            "    --environment-url $ARA_ENVIRONMENT_URL\n\n"
            "  # Deploy only environment variables\n"
            "  python deploy.py --vars-only --interactive\n\n"
            "  # Deploy only connection references\n"
            "  python deploy.py --refs-only --interactive\n\n"
            "Environment variables:\n"
            "  ARA_TENANT_ID        Microsoft Entra ID tenant ID\n"
            "  ARA_CLIENT_ID        Service principal app ID\n"
            "  ARA_CLIENT_SECRET    Service principal secret\n"
            "  ARA_ENVIRONMENT_URL  Dataverse environment URL\n"
        ),
    )

    # Authentication arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ARA_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set ARA_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ARA_CLIENT_ID"),
        help="Service principal app ID (or set ARA_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ARA_CLIENT_SECRET"),
        help="[DEPRECATED: use ARA_CLIENT_SECRET env var instead] Service principal secret",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ARA_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ARA_ENVIRONMENT_URL env var)",
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

    # Warn if --client-secret was passed via CLI (visible in process listings)
    if args.client_secret and not os.environ.get("ARA_CLIENT_SECRET"):
        print(
            "WARNING: --client-secret passes secrets via command-line arguments "
            "visible in process listings. Use ARA_CLIENT_SECRET env var instead."
        )

    # Validate required arguments
    if not args.tenant_id:
        print("ERROR: --tenant-id or ARA_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or ARA_ENVIRONMENT_URL required")
        sys.exit(1)
    if not args.interactive and (not args.client_id or not args.client_secret):
        print(
            "ERROR: --client-id and --client-secret required "
            "(or use --interactive)"
        )
        sys.exit(1)

    try:
        client = ARAClient(
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
