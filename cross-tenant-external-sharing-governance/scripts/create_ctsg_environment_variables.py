#!/usr/bin/env python3
"""
Create Dataverse environment variables for Cross-Tenant External Sharing Governance.

Environment variables store feature flags, notification targets, CTA baseline
policies, and administrative URLs for cross-tenant governance flows.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

ENV_VARIABLES = [
    {
        "schemaname": "fsi_CTSG_IsCrossTenantGovernanceEnabled",
        "displayname": "CTSG - Is Cross-Tenant Governance Enabled",
        "description": "Master feature flag. Set 'false' during deployment and allow-list population. Set 'true' to activate all flows.",
        "type": "String",
        "defaultvalue": "false",
    },
    {
        "schemaname": "fsi_CTSG_GovernanceTeamEmail",
        "displayname": "CTSG - Governance Team Email",
        "description": "Distribution list for governance notifications and daily scan summaries",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_CTSG_GovernanceCommitteeUPN",
        "displayname": "CTSG - Governance Committee UPN",
        "description": "Approver UPN for remediation decisions and tenant onboarding approval",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_CTSG_SecurityTeamUPN",
        "displayname": "CTSG - Security Team UPN",
        "description": "Security team UPN for security attestation in Flow 4 onboarding",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_CTSG_FlowAdministrators",
        "displayname": "CTSG - Flow Administrators",
        "description": "Email for flow error, API failure, and schema validation alerts",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_CTSG_DataverseEnvironmentUrl",
        "displayname": "CTSG - Dataverse Environment URL",
        "description": "Target Dataverse environment URL for API calls",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_CTSG_PPACTenantIsolationUrl",
        "displayname": "CTSG - PPAC Tenant Isolation URL",
        "description": "Power Platform Admin Center URL for manual tenant isolation configuration",
        "type": "String",
        "defaultvalue": "https://admin.powerplatform.microsoft.com/tenantsettings",
    },
    {
        "schemaname": "fsi_CTSG_EntraAdminCenterCTAUrl",
        "displayname": "CTSG - Entra Admin Center CTA URL",
        "description": "Entra Admin Center URL for cross-tenant access settings",
        "type": "String",
        "defaultvalue": "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/CompanyRelationshipsMenuBlade/~/Settings",
    },
    {
        "schemaname": "fsi_CTSG_CTABaselineInboundB2BBlocked",
        "displayname": "CTSG - CTA Baseline Inbound B2B Blocked",
        "description": "Whether default inbound B2B collaboration should be blocked per FSI baseline (default: true)",
        "type": "String",
        "defaultvalue": "true",
    },
    {
        "schemaname": "fsi_CTSG_CTABaselineOutboundB2BBlocked",
        "displayname": "CTSG - CTA Baseline Outbound B2B Blocked",
        "description": "Whether default outbound B2B should be blocked. Default false; set true for Zone 3. Document rationale in DELIVERY-CHECKLIST.md",
        "type": "String",
        "defaultvalue": "false",
    },
    {
        "schemaname": "fsi_CTSG_CTABaselineDirectConnectBlocked",
        "displayname": "CTSG - CTA Baseline Direct Connect Blocked",
        "description": "Whether default B2B direct connect should be blocked per FSI baseline (default: true)",
        "type": "String",
        "defaultvalue": "true",
    },
    {
        "schemaname": "fsi_CTSG_FrameworkVersion",
        "displayname": "CTSG - Framework Version",
        "description": "FSI-AgentGov framework version tag",
        "type": "String",
        "defaultvalue": "FSI-AgentGov-v1.1",
    },
]


def create_environment_variables(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for cross-tenant governance configuration.

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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create environment variables for Cross-Tenant External Sharing Governance",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables created:
  - fsi_CTSG_IsCrossTenantGovernanceEnabled (false)
  - fsi_CTSG_GovernanceTeamEmail
  - fsi_CTSG_GovernanceCommitteeUPN
  - fsi_CTSG_SecurityTeamUPN
  - fsi_CTSG_FlowAdministrators
  - fsi_CTSG_DataverseEnvironmentUrl
  - fsi_CTSG_PPACTenantIsolationUrl
  - fsi_CTSG_EntraAdminCenterCTAUrl
  - fsi_CTSG_CTABaselineInboundB2BBlocked (true)
  - fsi_CTSG_CTABaselineOutboundB2BBlocked (false)
  - fsi_CTSG_CTABaselineDirectConnectBlocked (true)
  - fsi_CTSG_FrameworkVersion (FSI-AgentGov-v1.1)

Examples:
  # Interactive authentication
  python create_ctsg_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_ctsg_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_ctsg_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("CTSG_TENANT_ID"),
        help="Microsoft Entra tenant ID (or CTSG_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CTSG_CLIENT_ID"),
        help="Service Principal application ID (or CTSG_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("CTSG_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or CTSG_ENVIRONMENT_URL env var)"
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
    client_secret = os.environ.get("CTSG_CLIENT_SECRET")
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
