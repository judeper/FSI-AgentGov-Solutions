#!/usr/bin/env python3
"""
Create Dataverse environment variables for Agent 365 Lifecycle Governance.

Environment variables store configurable lifecycle thresholds, sponsor defaults,
notification targets, and workflow IDs for agent lifecycle management.
"""

import argparse
import os
import sys
from typing import Optional

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

ENV_VARIABLES = [
    {
        "schemaname": "fsi_ALG_IsAgent365LifecycleEnabled",
        "displayname": "ALG - Agent 365 Lifecycle Enabled",
        "description": "Feature flag — gates all Entra Agent 365 API calls. Set false until GA and tenant licensing confirmed.",
        "type": "String",
        "defaultvalue": "false",
    },
    {
        "schemaname": "fsi_ALG_DefaultSponsorUPN",
        "displayname": "ALG - Default Sponsor UPN",
        "description": "Fallback sponsor UPN when agent owner cannot be resolved. Use a governance mailbox, not a personal account.",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_ALG_GovernanceTeamEmail",
        "displayname": "ALG - Governance Team Email",
        "description": "Distribution list for compliance notifications and weekly summaries",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_ALG_GovernanceCommitteeUPN",
        "displayname": "ALG - Governance Committee UPN",
        "description": "UPN or group for deactivation and deletion approval requests",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_ALG_EscalationApproverUPN",
        "displayname": "ALG - Escalation Approver UPN",
        "description": "Skip-level approver for SLA breaches in access review and deactivation flows",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_ALG_FlowAdministrators",
        "displayname": "ALG - Flow Administrators",
        "description": "Email for flow error and API failure alerts",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_ALG_SponsorMoverWorkflowId",
        "displayname": "ALG - Sponsor Mover Workflow ID",
        "description": "Entra Lifecycle Workflow ID for sponsor mover notification",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_ALG_SponsorLeaverWorkflowId",
        "displayname": "ALG - Sponsor Leaver Workflow ID",
        "description": "Entra Lifecycle Workflow ID for sponsor leaver deactivation",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_ALG_FSIAllAgentIdentitiesGroupId",
        "displayname": "ALG - All Agent Identities Group ID",
        "description": "Entra Object ID of FSI-AllAgentIdentities security group",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_ALG_FSIZone3AgentsGroupId",
        "displayname": "ALG - Zone 3 Agents Group ID",
        "description": "Entra Object ID of FSI-Zone3-Agents security group",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_ALG_DataverseEnvironmentUrl",
        "displayname": "ALG - Dataverse Environment URL",
        "description": "Target Dataverse URL for all table operations",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_ALG_InactivityThresholdZone1",
        "displayname": "ALG - Inactivity Threshold Zone 1 (Days)",
        "description": "Inactivity threshold in days for Zone 1 agents (default: 180)",
        "type": "Decimal",
        "defaultvalue": "180",
    },
    {
        "schemaname": "fsi_ALG_InactivityThresholdZone2",
        "displayname": "ALG - Inactivity Threshold Zone 2 (Days)",
        "description": "Inactivity threshold in days for Zone 2 agents (default: 90)",
        "type": "Decimal",
        "defaultvalue": "90",
    },
    {
        "schemaname": "fsi_ALG_InactivityThresholdZone3",
        "displayname": "ALG - Inactivity Threshold Zone 3 (Days)",
        "description": "Inactivity threshold in days for Zone 3 agents (default: 30)",
        "type": "Decimal",
        "defaultvalue": "30",
    },
]


def create_environment_variables(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for agent lifecycle governance thresholds and settings.

    Args:
        client: DataverseClient instance
        dry_run: If True, preview changes without creating

    Returns:
        dict: Results summary with created/skipped/errors counts
    """
    print("\n[Creating Environment Variables]")
    results = {"created": 0, "skipped": 0, "errors": 0}

    for var in ENV_VARIABLES:
        schemaname = var["schemaname"]
        try:
            # Check if variable already exists
            if not dry_run and not client.dry_run:
                existing = client.query(
                    "environmentvariabledefinitions",
                    filter_expr=f"schemaname eq '{schemaname}'",
                )
                if existing:
                    print(f"  {schemaname}: already exists, skipping")
                    results["skipped"] += 1
                    continue
            elif dry_run or client.dry_run:
                print(f"  [DRY RUN] {schemaname}: would check if exists")

            # Create variable
            if dry_run or client.dry_run:
                print(f"  [DRY RUN] {schemaname}: would create")
                print(f"    Type: {var['type']}, Default: {var['defaultvalue']}")
                results["created"] += 1
            else:
                # Map type to Dataverse type code
                type_code = 100000001 if var["type"] == "Decimal" else 100000000

                # Create definition
                definition_data = {
                    "schemaname": schemaname,
                    "displayname": var["displayname"],
                    "description": var["description"],
                    "type": type_code,
                }
                definition_id = client.create_record(
                    "environmentvariabledefinitions", definition_data
                )

                # Create default value; roll back definition on failure
                try:
                    value_data = {
                        "value": var["defaultvalue"],
                        "environmentvariabledefinitionid@odata.bind": f"/environmentvariabledefinitions({definition_id})",
                    }
                    client.create_record("environmentvariablevalues", value_data)
                except Exception as val_err:
                    print(f"  {schemaname}: value creation failed, rolling back definition - {val_err}")
                    try:
                        client.delete_record("environmentvariabledefinitions", definition_id)
                    except Exception as cleanup_err:
                        print(f"  {schemaname}: WARNING - rollback failed, orphaned definition {definition_id} - {cleanup_err}")
                    raise

                print(f"  {schemaname}: created")
                print(f"    Type: {var['type']}, Default: {var['defaultvalue']}")
                results["created"] += 1

        except Exception as e:
            print(f"  {schemaname}: ERROR - {e}")
            results["errors"] += 1

    print()
    print(f"  Summary: {results['created']} created, {results['skipped']} skipped")
    if results["errors"] > 0:
        print(f"  Errors: {results['errors']}")

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Create environment variables for Agent 365 Lifecycle Governance",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables created:
  - fsi_ALG_IsAgent365LifecycleEnabled (false)
  - fsi_ALG_DefaultSponsorUPN
  - fsi_ALG_GovernanceTeamEmail
  - fsi_ALG_GovernanceCommitteeUPN
  - fsi_ALG_EscalationApproverUPN
  - fsi_ALG_FlowAdministrators
  - fsi_ALG_SponsorMoverWorkflowId
  - fsi_ALG_SponsorLeaverWorkflowId
  - fsi_ALG_FSIAllAgentIdentitiesGroupId
  - fsi_ALG_FSIZone3AgentsGroupId
  - fsi_ALG_DataverseEnvironmentUrl
  - fsi_ALG_InactivityThresholdZone1 (180 days)
  - fsi_ALG_InactivityThresholdZone2 (90 days)
  - fsi_ALG_InactivityThresholdZone3 (30 days)

Examples:
  # Interactive authentication
  python create_alg_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_alg_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_alg_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ALG_TENANT_ID"),
        help="Microsoft Entra tenant ID (or ALG_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ALG_CLIENT_ID"),
        help="Service Principal application ID (or ALG_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ALG_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or ALG_ENVIRONMENT_URL env var)"
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without creating resources"
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    # Handle client secret for Service Principal auth
    client_secret = os.environ.get("ALG_CLIENT_SECRET")
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    try:
        # Initialize client
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run
        )

        # Create environment variables
        results = create_environment_variables(client, dry_run=args.dry_run)

        # Exit with error if any failures
        if results["errors"] > 0:
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
