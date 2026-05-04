#!/usr/bin/env python3
"""Deploy File Upload Security Configurator infrastructure to Dataverse.

Orchestrates the complete deployment sequence:
  1. Test Dataverse connectivity
  2. Create schema (tables, columns, option sets)
  3. Create environment variables
  4. Create connection references

Supports selective deployment with --skip-* flags and --dry-run for validation.

Usage:
  python deploy.py --tenant-id <tid> --url <url> [--dry-run]
  python deploy.py --interactive --url <url>
  python deploy.py --skip-schema --url <url>
"""

import argparse
import os
import sys
import time

from fus_client import FUSClient
from create_dataverse_schema import deploy_schema
from create_environment_variables import deploy_environment_variables
from create_connection_references import deploy_connection_references


def deploy(client: FUSClient, skip_schema=False, skip_vars=False, skip_refs=False):
    """Run all deployment steps."""
    banner = """
╔══════════════════════════════════════════════════════════════╗
║  File Upload Security Configurator — Dataverse Deployment   ║
╚══════════════════════════════════════════════════════════════╝
"""
    print(banner)

    if client.dry_run:
        print("  ⚠  DRY RUN MODE — no changes will be made\n")

    # ── Step 1: Test Connectivity ─────────────────────────────────
    print("Step 1/4: Testing Dataverse connectivity...")
    try:
        org = client.test_connection()
        org_name = org.get("Name", org.get("name", "Unknown"))
        print(f"  Connected to: {org_name}")
        print(f"  URL: {client.environment_url}")
    except Exception as e:
        print(f"  FAILED: {e}", file=sys.stderr)
        sys.exit(1)

    start = time.time()

    # ── Step 2: Dataverse Schema ──────────────────────────────────
    if skip_schema:
        print("\nStep 2/4: Schema — SKIPPED")
    else:
        print("\nStep 2/4: Creating Dataverse schema...")
        deploy_schema(client)

    # ── Step 3: Environment Variables ────────────────────────────
    if skip_vars:
        print("\nStep 3/4: Environment variables — SKIPPED")
    else:
        print("\nStep 3/4: Creating environment variables...")
        deploy_environment_variables(client)

    # ── Step 4: Connection References ────────────────────────────
    if skip_refs:
        print("\nStep 4/4: Connection references — SKIPPED")
    else:
        print("\nStep 4/4: Creating connection references...")
        deploy_connection_references(client)

    elapsed = time.time() - start

    # ── Summary ──────────────────────────────────────────────────
    summary = f"""
╔══════════════════════════════════════════════════════════════╗
║  Deployment Complete                                         ║
╠══════════════════════════════════════════════════════════════╣
║  Duration: {elapsed:6.1f}s                                         ║
║  Schema:   {'SKIPPED' if skip_schema else 'DEPLOYED':10s}                                    ║
║  Env Vars: {'SKIPPED' if skip_vars   else 'DEPLOYED':10s}                                    ║
║  Conn Ref: {'SKIPPED' if skip_refs   else 'DEPLOYED':10s}                                    ║
╚══════════════════════════════════════════════════════════════╝

Next Steps:
  1. Set environment variable values in Power Platform admin center
  2. Configure connection reference credentials
  3. Import the Power Automate validation flow
  4. Run Invoke-FileUploadBaselineCapture.ps1 to capture initial baselines
  5. Verify with: Test-FileUploadCompliance.ps1 -TenantId <tid>
"""
    print(summary)


# ── CLI Entry Point ──────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Deploy File Upload Security Configurator to Dataverse"
    )
    parser.add_argument("--tenant-id", default=os.environ.get("FUS_TENANT_ID"))
    parser.add_argument("--client-id", default=os.environ.get("FUS_CLIENT_ID"))
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("FUS_CLIENT_SECRET"),
        help="Legacy dev-only fallback; use managed identity in production",
    )
    parser.add_argument(
        "--managed-identity-client-id",
        default=os.environ.get("FUS_MANAGED_IDENTITY_CLIENT_ID"),
        help="Optional user-assigned managed identity client ID",
    )
    parser.add_argument("--url", default=os.environ.get("FUS_DATAVERSE_URL"),
                        help="Dataverse environment URL")
    parser.add_argument("--interactive", action="store_true",
                        help="Use interactive browser auth")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be deployed without making changes")
    parser.add_argument("--skip-schema", action="store_true",
                        help="Skip Dataverse schema creation")
    parser.add_argument("--skip-vars", action="store_true",
                        help="Skip environment variable creation")
    parser.add_argument("--skip-refs", action="store_true",
                        help="Skip connection reference creation")
    args = parser.parse_args()

    if not args.url:
        parser.error("url required (set FUS_DATAVERSE_URL env var or use --url)")
    if args.interactive and (not args.tenant_id or not args.client_id):
        parser.error("interactive auth requires tenant-id and client-id")
    if args.client_secret and (not args.tenant_id or not args.client_id):
        parser.error("legacy client secret auth requires tenant-id and client-id")

    client = FUSClient(
        tenant_id=args.tenant_id or "",
        environment_url=args.url,
        client_id=args.client_id,
        client_secret=args.client_secret,
        interactive=args.interactive,
        dry_run=args.dry_run,
        managed_identity_client_id=args.managed_identity_client_id,
    )

    deploy(
        client,
        skip_schema=args.skip_schema,
        skip_vars=args.skip_vars,
        skip_refs=args.skip_refs,
    )


if __name__ == "__main__":
    main()
