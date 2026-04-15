#!/usr/bin/env python3
"""Create Dataverse connection references for Model Risk Management Automation.

Deploys six connection references that Power Automate flows use to
interact with Dataverse, Microsoft Teams, Power Automate Approvals,
HTTP with Azure AD, SharePoint, and Word Online. All operations are
idempotent -- safe to re-run.

Connection References:
  - fsi_cr_dataverse_mrm: Model inventory CRUD, risk ratings, validation
    cycles, findings, monitoring records, and compliance event logging
  - fsi_cr_teams_mrm: Risk scoring notifications, validation assignment
    alerts, SLA breach alerts, and revalidation approval requests
  - fsi_cr_approvals_mrm: Validator assignment approval, revalidation
    confirmation, and Tier 1 examiner alert choices
  - fsi_cr_http_mrm: Power Platform Bots API, Microsoft Graph API calls
    for user profile resolution and Entra Agent Registry
  - fsi_cr_sharepoint_mrm: Agent Card document upload, folder creation,
    and metadata updates in the Agent Card Library
  - fsi_cr_wordonline_mrm: Agent Card document generation from template;
    falls back to JSON if Word connector is unavailable
"""

import argparse
import os
import sys

from mrm_client import MRMClient


# =============================================================================
# Connection Reference Definitions
# =============================================================================

CONNECTION_REF_DEFINITIONS = [
    {
        "logical_name": "fsi_cr_dataverse_mrm",
        "display_name": "Dataverse - Model Risk Management",
        "connector_id": "shared_commondataserviceforapps",
        "description": (
            "Dataverse connection for MRM. Used for model inventory CRUD, "
            "risk rating records, validation cycles, findings, monitoring "
            "records, and compliance event logging."
        ),
    },
    {
        "logical_name": "fsi_cr_teams_mrm",
        "display_name": "Teams - Model Risk Management",
        "connector_id": "shared_teams",
        "description": (
            "Microsoft Teams connection for MRM. Used for risk scoring "
            "notification cards, validation assignment alerts, SLA breach "
            "alerts, and revalidation approval requests."
        ),
    },
    {
        "logical_name": "fsi_cr_approvals_mrm",
        "display_name": "Approvals - Model Risk Management",
        "connector_id": "shared_approvals",
        "description": (
            "Power Automate Approvals connection for MRM. Used for "
            "validator assignment approval, revalidation confirmation, "
            "and Tier 1 examiner alert choices."
        ),
    },
    {
        "logical_name": "fsi_cr_http_mrm",
        "display_name": "HTTP with Azure AD - Model Risk Management",
        "connector_id": "shared_webcontents",
        "description": (
            "HTTP with Azure AD connection for MRM. Used for Power "
            "Platform Bots API, Microsoft Graph API calls for user "
            "profile resolution and Entra Agent Registry."
        ),
    },
    {
        "logical_name": "fsi_cr_sharepoint_mrm",
        "display_name": "SharePoint - Model Risk Management",
        "connector_id": "shared_sharepointonline",
        "description": (
            "SharePoint connection for MRM. Used for Agent Card document "
            "upload, folder creation, and metadata updates in the Agent "
            "Card Library."
        ),
    },
    {
        "logical_name": "fsi_cr_wordonline_mrm",
        "display_name": "Word Online - Model Risk Management",
        "connector_id": "shared_wordonlinebusiness",
        "description": (
            "Word Online (Business) connection for MRM. Used for Agent "
            "Card document generation from template. Falls back to JSON "
            "if Word connector is unavailable."
        ),
    },
]


# =============================================================================
# Deployment Functions
# =============================================================================


def create_connection_reference(
    client: MRMClient, definition: dict, dry_run: bool = False,
) -> None:
    """Create a single connection reference in Dataverse.

    Checks for existence first -- skips if already present.

    Args:
        client: MRMClient instance
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
    client: MRMClient, dry_run: bool = False,
) -> None:
    """Deploy all MRM connection references to Dataverse.

    Creates six connection references for Dataverse, Teams, Approvals,
    HTTP with Azure AD, SharePoint, and Word Online connectors. All
    operations are idempotent -- safe to re-run.

    Args:
        client: MRMClient instance
        dry_run: Preview mode flag
    """
    print("=" * 60)
    print("MRM Connection References Deployment")
    print("  Model Risk Management Automation")
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
            "Model Risk Management Automation"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_mrm_connection_references.py "
            "--dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_mrm_connection_references.py \\\n"
            "    --tenant-id $MRM_TENANT_ID \\\n"
            "    --client-id $MRM_CLIENT_ID \\\n"
            "    --client-secret $MRM_CLIENT_SECRET \\\n"
            "    --environment-url $MRM_ENVIRONMENT_URL\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("MRM_TENANT_ID"),
        help="Azure AD tenant ID (or set MRM_TENANT_ID env var)",
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
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be created without making changes",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id:
        print("ERROR: --tenant-id or MRM_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or MRM_ENVIRONMENT_URL required")
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

        create_connection_references(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
