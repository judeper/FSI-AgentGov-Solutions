#!/usr/bin/env python3
"""Deploy HITL Workflow Governance infrastructure to Dataverse.

Orchestrates the full deployment pipeline:
  1. Test Connection -- validate Dataverse API access
  2. Dataverse Schema -- tables, columns, shared and HWG option sets
  3. Environment Variables -- scan configuration thresholds
  4. Connection References -- Power Automate connector bindings

All operations are idempotent -- safe to re-run. Supports selective
deployment via --schema-only, --env-vars-only, --conn-refs-only flags.
"""

import argparse
import os
import sys
import time

from hwg_client import HWGClient
from create_hwg_dataverse_schema import create_schema
from create_hwg_environment_variables import create_environment_variables
from create_hwg_connection_references import create_connection_references


# =============================================================================
# Post-Deployment Guidance
# =============================================================================

POST_DEPLOYMENT_GUIDANCE = """
═══════════════════════════════════════════════════════════
Post-Deployment Steps
═══════════════════════════════════════════════════════════

1. SECURITY -- Configure fsi_HitlScanRun security role:
   - Navigate to Settings > Security > Security Roles
   - Remove Write and Delete privileges for fsi_HitlScanRun
   - This supports immutable audit records (FINRA Rule 4511(a), SEC Rule 17a-3)

2. CONNECTIONS -- Bind connection references in Power Automate:
   - fsi_cr_dataverse_hitlworkflowgovernance          -> Select Dataverse connection
   - fsi_cr_humanintheloop_hitlworkflowgovernance      -> Select Human in the Loop connection

3. EXCEPTIONS -- Populate fsi_HitlCheckpointException table:
   - Add approved exceptions for agents not requiring HITL checkpoints
   - Set fsi_IsActive to true for active exceptions
   - Set fsi_ExpiresAt for time-limited exceptions

4. VERIFY -- Run dry-run to confirm deployment:
   python deploy.py --dry-run [--interactive | --client-id ...]
"""


# =============================================================================
# Deployment Pipeline
# =============================================================================


def run_deployment(
    client: HWGClient,
    dry_run: bool = False,
    schema_only: bool = False,
    env_vars_only: bool = False,
    conn_refs_only: bool = False,
    verbose: bool = False,
) -> None:
    """Execute the HWG deployment pipeline.

    Runs all deployment steps in order unless selective flags are set.
    When a selective flag is provided, only that step runs.

    Args:
        client: Authenticated HWGClient instance
        dry_run: Preview mode flag
        schema_only: Deploy only Dataverse schema
        env_vars_only: Deploy only environment variables
        conn_refs_only: Deploy only connection references
        verbose: Enable verbose output
    """
    selective = schema_only or env_vars_only or conn_refs_only
    start_time = time.time()

    print()
    print("=" * 60)
    print("HITL Workflow Governance -- Dataverse Deployment")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN -- No changes will be made ***")

    if selective:
        modes = []
        if schema_only:
            modes.append("schema")
        if env_vars_only:
            modes.append("environment variables")
        if conn_refs_only:
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
    if not selective or schema_only:
        print("\n" + "-" * 60)
        print("Step 2/4: Dataverse Schema")
        print("-" * 60)
        create_schema(client, dry_run=dry_run)

    # Step 3: Environment Variables
    if not selective or env_vars_only:
        print("\n" + "-" * 60)
        print("Step 3/4: Environment Variables")
        print("-" * 60)
        create_environment_variables(client, dry_run=dry_run)

    # Step 4: Connection References
    if not selective or conn_refs_only:
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


def main() -> None:
    """CLI entry point for HWG deployment orchestrator."""
    parser = argparse.ArgumentParser(
        description=(
            "Deploy HITL Workflow Governance infrastructure to Dataverse"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Full deployment with interactive auth\n"
            "  python deploy.py --interactive\n\n"
            "  # Dry run (preview all changes)\n"
            "  python deploy.py --dry-run --interactive\n\n"
            "  # Deploy only schema with service principal\n"
            "  python deploy.py --schema-only \\\n"
            "    --tenant-id $HWG_TENANT_ID \\\n"
            "    --client-id $HWG_CLIENT_ID \\\n"
            "    --client-secret $HWG_CLIENT_SECRET \\\n"
            "    --environment-url $HWG_ENVIRONMENT_URL\n\n"
            "  # Deploy only environment variables\n"
            "  python deploy.py --env-vars-only --interactive\n\n"
            "  # Deploy only connection references\n"
            "  python deploy.py --conn-refs-only --interactive\n\n"
            "Environment variables:\n"
            "  HWG_TENANT_ID        Microsoft Entra ID tenant ID\n"
            "  HWG_CLIENT_ID        Service principal app ID\n"
            "  HWG_CLIENT_SECRET    Service principal secret\n"
            "  HWG_ENVIRONMENT_URL  Dataverse environment URL\n"
        ),
    )

    # Authentication arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("HWG_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set HWG_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("HWG_CLIENT_ID"),
        help="Service principal app ID (or set HWG_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("HWG_CLIENT_SECRET"),
        help="Service principal secret (or set HWG_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("HWG_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set HWG_ENVIRONMENT_URL env var)",
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
        "--schema-only",
        action="store_true",
        help="Deploy only Dataverse schema (tables and columns)",
    )
    parser.add_argument(
        "--env-vars-only",
        action="store_true",
        help="Deploy only environment variables",
    )
    parser.add_argument(
        "--conn-refs-only",
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
        print("ERROR: --tenant-id or HWG_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or HWG_ENVIRONMENT_URL required")
        sys.exit(1)
    if not args.interactive and (not args.client_id or not args.client_secret):
        print(
            "ERROR: --client-id and --client-secret required "
            "(or use --interactive)"
        )
        sys.exit(1)

    try:
        client = HWGClient(
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
            schema_only=args.schema_only,
            env_vars_only=args.env_vars_only,
            conn_refs_only=args.conn_refs_only,
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
