#!/usr/bin/env python3
"""Create Dataverse connection references for Agent Communication Restriction Detector.

Deploys four connection references that Power Automate flows use to
interact with Dataverse, Office 365 email, Microsoft Teams, and Azure
Automation. All operations are idempotent -- safe to re-run.

Connection References:
  - fsi_cr_dataverse_commrestrictiondetector: Core data operations
  - fsi_cr_office365_commrestrictiondetector: Email alerts
  - fsi_cr_teams_commrestrictiondetector: Teams adaptive card alerts
  - fsi_cr_azureautomation_commrestrictiondetector: Runbook invocation

Version: 1.2.1

Migrated in v1.2.1 from the solution-local `acrd_client.py` to the shared
`scripts/shared/dataverse_client.py`. (council review M-1)
"""

import argparse
import os
import sys

# Import shared DataverseClient (the local acrd_client.py was retired in v1.2.1).
sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)
from dataverse_client import DataverseClient


# =============================================================================
# Connection Reference Definitions
# =============================================================================

CONNECTION_REF_DEFINITIONS = [
    {
        "logical_name": "fsi_cr_dataverse_commrestrictiondetector",
        "display_name": "Dataverse - Agent Communication Restriction Detector",
        "connector_id": "shared_commondataserviceforapps",
        "description": (
            "Dataverse connection for Agent Communication Restriction Detector. "
            "Used for violation tracking, approved route management, skill "
            "registration snapshots, and scan run audit records."
        ),
    },
    {
        "logical_name": "fsi_cr_office365_commrestrictiondetector",
        "display_name": "Office 365 - Agent Communication Restriction Detector",
        "connector_id": "shared_office365",
        "description": (
            "Office 365 connection for Agent Communication Restriction Detector. "
            "Used to send email alerts when communication restriction "
            "violations are detected."
        ),
    },
    {
        "logical_name": "fsi_cr_teams_commrestrictiondetector",
        "display_name": "Teams - Agent Communication Restriction Detector",
        "connector_id": "shared_teams",
        "description": (
            "Microsoft Teams connection for Agent Communication Restriction Detector. "
            "Used to post adaptive card alerts to the designated "
            "governance channel."
        ),
    },
    {
        "logical_name": "fsi_cr_azureautomation_commrestrictiondetector",
        "display_name": "Azure Automation - Agent Communication Restriction Detector",
        "connector_id": "shared_azureautomation",
        "description": (
            "Azure Automation connection for Agent Communication Restriction Detector. "
            "Used to invoke the validation runbook that scans agent "
            "communication configurations across Power Platform environments."
        ),
    },
]


# =============================================================================
# Deployment Functions
# =============================================================================


def create_connection_reference(
    client: DataverseClient, definition: dict, dry_run: bool = False,
) -> None:
    """Create a single connection reference in Dataverse.

    Checks for existence first -- skips if already present.

    Args:
        client: Shared DataverseClient instance
        definition: Dict with logical_name, display_name, connector_id,
                     description
        dry_run: Preview mode flag
    """
    logical_name = definition["logical_name"]
    display_name = definition["display_name"]
    connector_id = definition["connector_id"]
    description = definition["description"]

    # Idempotent check — skip if already exists.
    # Shared DataverseClient.query() returns a list directly (not a dict with
    # 'value'), and the keyword argument is `filter_expr`, not `filter`.
    existing = client.query(
        "connectionreferences",
        filter_expr=f"connectionreferencelogicalname eq '{logical_name}'",
    )
    if existing:
        print(f"  {logical_name}: already exists, skipping")
        return

    # Create connection reference record
    ref_data = {
        "connectionreferencelogicalname": logical_name,
        "connectionreferencedisplayname": display_name,
        "connectorid": f"/providers/Microsoft.PowerApps/apis/{connector_id}",
        "description": description,
    }

    client.create_record("connectionreferences", ref_data)
    print(f"  {logical_name}: created ({connector_id})")


def create_connection_references(
    client: DataverseClient, dry_run: bool = False,
) -> None:
    """Deploy all ACRD connection references to Dataverse.

    Creates four connection references for Dataverse, Office 365, Teams,
    and Azure Automation connectors. All operations are idempotent -- safe
    to re-run.

    Args:
        client: Shared DataverseClient instance
        dry_run: Preview mode flag
    """
    print("=" * 60)
    print("ACRD Connection References Deployment")
    print("  Agent Communication Restriction Detector")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    print("\n[Creating Connection References]")

    for defn in CONNECTION_REF_DEFINITIONS:
        create_connection_reference(client, defn, dry_run)

    # Summary
    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("CONNECTION REFERENCES DEPLOYMENT COMPLETE")
    print(f"  Connection references: {len(CONNECTION_REF_DEFINITIONS)}")
    print("=" * 60)


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    """CLI entry point for connection reference deployment."""
    parser = argparse.ArgumentParser(
        description=(
            "Create Dataverse connection references for "
            "Agent Communication Restriction Detector"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_connection_references.py "
            "--dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_connection_references.py \\\n"
            "    --tenant-id $ACRD_TENANT_ID \\\n"
            "    --client-id $ACRD_CLIENT_ID \\\n"
            "    --client-secret $ACRD_CLIENT_SECRET \\\n"
            "    --environment-url $ACRD_ENVIRONMENT_URL\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ACRD_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set ACRD_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ACRD_CLIENT_ID"),
        help="Application (client) ID (or set ACRD_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ACRD_CLIENT_SECRET"),
        # legacy: dev-only — replace with managed identity in production
        help=(
            "Service principal secret (or set ACRD_CLIENT_SECRET env var). "
            "Dev-only fallback; prefer managed identity in production."
        ),
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ACRD_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ACRD_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--auth-mode",
        default=os.environ.get("ACRD_AUTH_MODE"),
        choices=[
            "interactive",
            "managed-identity",
            "workload-identity",
            "certificate",
            "client-secret",
        ],
        help="Authentication mode for the shared DataverseClient.",
    )
    parser.add_argument(
        "--certificate-path",
        default=os.environ.get("ACRD_CERTIFICATE_PATH"),
        help="Path to PEM/PFX certificate for --auth-mode certificate.",
    )
    parser.add_argument(
        "--certificate-password",
        default=os.environ.get("ACRD_CERTIFICATE_PASSWORD"),
        help="Optional certificate password for --auth-mode certificate.",
    )
    parser.add_argument(
        "--access-token",
        default=os.environ.get("ACRD_ACCESS_TOKEN"),
        help="Externally-acquired Dataverse bearer token (overrides other auth).",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be created without making changes",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.environment_url:
        print("ERROR: --environment-url or ACRD_ENVIRONMENT_URL required")
        sys.exit(1)
    if (
        not args.tenant_id
        and not args.access_token
        and args.auth_mode not in ("managed-identity", "workload-identity")
    ):
        print(
            "ERROR: --tenant-id or ACRD_TENANT_ID required "
            "(not needed for managed-identity / workload-identity / --access-token)"
        )
        sys.exit(1)

    try:
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            access_token=args.access_token,
            interactive=args.interactive,
            dry_run=args.dry_run,
            auth_mode=args.auth_mode,
            certificate_path=args.certificate_path,
            certificate_password=args.certificate_password,
        )

        create_connection_references(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
