#!/usr/bin/env python3
"""Create Dataverse connection references for Agent Registry Automation.

Deploys four connection references that Power Automate flows use to
interact with Dataverse, Microsoft Teams, Office 365, and HTTP with
Azure AD endpoints. All operations are idempotent — safe to re-run.

Connection References:
  - fsi_cr_dataverse_agentregistry: Core data operations
  - fsi_cr_teams_agentregistry: Approval cards and alert notifications
  - fsi_cr_office365_agentregistry: Business day calculation for SLA
  - fsi_cr_http_agentregistry: Power Platform Bots API and Graph API calls
"""

import argparse
import os
import sys

from ara_client import ARAClient


# =============================================================================
# Connection Reference Definitions
# =============================================================================

CONNECTION_REF_DEFINITIONS = [
    {
        "logical_name": "fsi_cr_dataverse_agentregistry",
        "display_name": "Dataverse - Agent Registry Automation",
        "connector_id": "shared_commondataserviceforapps",
        "description": (
            "Dataverse connection for Agent Registry Automation. "
            "Used for agent inventory CRUD, registration requests, "
            "and compliance event logging."
        ),
    },
    {
        "logical_name": "fsi_cr_teams_agentregistry",
        "display_name": "Teams - Agent Registry Automation",
        "connector_id": "shared_teams",
        "description": (
            "Microsoft Teams connection for Agent Registry Automation. "
            "Used for approval adaptive cards, unregistered agent alerts, "
            "and escalation notifications."
        ),
    },
    {
        "logical_name": "fsi_cr_office365_agentregistry",
        "display_name": "Office 365 - Agent Registry Automation",
        "connector_id": "shared_office365",
        "description": (
            "Office 365 connection for Agent Registry Automation. "
            "Used for business day calculation in SLA deadline computation."
        ),
    },
    {
        "logical_name": "fsi_cr_http_agentregistry",
        "display_name": "HTTP with Azure AD - Agent Registry Automation",
        "connector_id": "shared_webcontents",
        "description": (
            "HTTP with Azure AD connection for Agent Registry Automation. "
            "Used for Power Platform Bots API calls and Microsoft Graph "
            "Agent Registry API calls."
        ),
    },
]


# =============================================================================
# Deployment Functions
# =============================================================================


def create_connection_reference(
    client: ARAClient, definition: dict, dry_run: bool = False,
) -> None:
    """Create a single connection reference in Dataverse.

    Checks for existence first — skips if already present.

    Args:
        client: ARAClient instance
        definition: Dict with logical_name, display_name, connector_id,
                     description
        dry_run: Preview mode flag
    """
    logical_name = definition["logical_name"]
    display_name = definition["display_name"]
    connector_id = definition["connector_id"]
    description = definition["description"]

    # Idempotent check — skip if already exists
    existing = client.query(
        "connectionreferences",
        filter=f"connectionreferencelogicalname eq '{logical_name}'",
    )
    if existing["value"]:
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
    client: ARAClient, dry_run: bool = False,
) -> None:
    """Deploy all ARA connection references to Dataverse.

    Creates four connection references for Dataverse, Teams, Office 365,
    and HTTP with Azure AD connectors. All operations are idempotent —
    safe to re-run.

    Args:
        client: ARAClient instance
        dry_run: Preview mode flag
    """
    print("=" * 60)
    print("ARA Connection References Deployment")
    print("  Agent Registry Automation")
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


def main():
    """CLI entry point for connection reference deployment."""
    parser = argparse.ArgumentParser(
        description=(
            "Create Dataverse connection references for "
            "Agent Registry Automation"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_connection_references.py "
            "--dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_connection_references.py \\\n"
            "    --tenant-id $ARA_TENANT_ID \\\n"
            "    --client-id $ARA_CLIENT_ID \\\n"
            "    --client-secret $ARA_CLIENT_SECRET \\\n"
            "    --environment-url $ARA_ENVIRONMENT_URL\n"
        ),
    )

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
        help="Service principal secret (or set ARA_CLIENT_SECRET env var)",
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
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be created without making changes",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id:
        print("ERROR: --tenant-id or ARA_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or ARA_ENVIRONMENT_URL required")
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

        create_connection_references(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
