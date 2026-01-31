#!/usr/bin/env python3
"""
Create field security profiles for Environment Lifecycle Management.

Creates ELM Approver Fields profile to restrict approvers to only
modifying approval-related fields.
"""

import argparse
import os
import sys
from typing import Optional

from elm_client import ELMClient

# Field permissions for ELM Approver Fields profile
# Can Read = 4, Can Update = 2, Can Create = 1
# Permissions are combined: Read+Update = 6, Read only = 4
APPROVER_FIELD_PERMISSIONS = {
    # Approval fields - approvers can read and update
    "fsi_state": {"canread": 4, "cancreate": 0, "canupdate": 2},
    "fsi_approver": {"canread": 4, "cancreate": 0, "canupdate": 2},
    "fsi_approvedon": {"canread": 4, "cancreate": 0, "canupdate": 2},
    "fsi_approvalcomments": {"canread": 4, "cancreate": 0, "canupdate": 2},
    # All other fields - read only
    "fsi_requestnumber": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_environmentname": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_environmenttype": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_region": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_businessjustification": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_zone": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_zonerationale": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_zoneautoflags": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_datasensitivity": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_expectedusers": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_securitygroupid": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_requester": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_requestedon": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_environmentid": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_environmenturl": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_provisioningstarted": {"canread": 4, "cancreate": 0, "canupdate": 0},
    "fsi_provisioningcompleted": {"canread": 4, "cancreate": 0, "canupdate": 0},
}


def validate_fields_exist(
    client: ELMClient,
    entity_logical_name: str,
    field_names: list[str],
) -> tuple[list[str], list[str]]:
    """
    Validate that all specified fields exist on the entity.

    Args:
        client: Authenticated ELMClient
        entity_logical_name: Entity logical name
        field_names: List of field names to check

    Returns:
        Tuple of (existing_fields, missing_fields)
    """
    existing = []
    missing = []
    for field_name in field_names:
        attr = client.get_attribute_metadata(entity_logical_name, field_name)
        if attr:
            existing.append(field_name)
        else:
            missing.append(field_name)
    return existing, missing


def create_field_security(client: ELMClient, dry_run: bool = False) -> bool:
    """
    Create field security profiles for ELM.

    Args:
        client: Authenticated ELMClient
        dry_run: If True, show what would be created without making changes

    Returns:
        True if successful, False if validation fails
    """
    print("\n" + "=" * 60)
    print("ELM Field Security Deployment")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Validate entity exists first
    print("\n[Validating Schema]")
    er_metadata = client.get_entity_metadata("fsi_environmentrequest")
    if not er_metadata:
        print("  ERROR: EnvironmentRequest table not found.")
        print("  Run create_dataverse_schema.py first.")
        return False
    print("  EnvironmentRequest table: found ✓")

    # Upfront field validation
    print()
    print("  Validating fields...")
    existing_fields, missing_fields = validate_fields_exist(
        client,
        "fsi_environmentrequest",
        list(APPROVER_FIELD_PERMISSIONS.keys()),
    )

    if missing_fields:
        print(f"  ERROR: {len(missing_fields)} required field(s) not found:")
        for field in missing_fields:
            print(f"    - {field}")
        print()
        print("  Run create_dataverse_schema.py to create missing fields.")
        return False

    print(f"  All {len(existing_fields)} fields validated ✓")

    profile_name = "ELM Approver Fields"

    # Check if profile already exists
    print("\n[Checking Existing Profiles]")
    existing = client.get_field_security_profiles(f"name eq '{profile_name}'")

    if existing:
        profile_id = existing[0]["fieldsecurityprofileid"]
        print(f"  {profile_name}: already exists ({profile_id})")
        print("  Skipping profile creation, will add missing field permissions")
    elif dry_run:
        print(f"  {profile_name}: would create")
        profile_id = None
    else:
        # Create the profile
        print(f"\n[Creating Field Security Profile]")
        profile_data = {
            "name": profile_name,
            "description": "Restricts ELM Approvers to only modify approval-related fields",
        }
        profile_id = client.create_field_security_profile(profile_data)
        print(f"  {profile_name}: created ({profile_id})")

    # Create field permissions
    print(f"\n[Creating Field Permissions]")

    for field_name, permissions in APPROVER_FIELD_PERMISSIONS.items():
        can_update = permissions["canupdate"] > 0

        if dry_run:
            update_label = "read+update" if can_update else "read-only"
            print(f"  {field_name}: would set {update_label}")
        elif profile_id:
            try:
                permission_data = {
                    "attributelogicalname": field_name,
                    "canread": permissions["canread"],
                    "cancreate": permissions["cancreate"],
                    "canupdate": permissions["canupdate"],
                    "entityname": "fsi_environmentrequest",
                    "fieldsecurityprofileid@odata.bind": f"/fieldsecurityprofiles({profile_id})",
                }
                client.create_field_permission(permission_data)
                update_label = "read+update" if can_update else "read-only"
                print(f"  {field_name}: {update_label}")
            except Exception as e:
                # May fail if permission already exists
                if "duplicate" in str(e).lower() or "already" in str(e).lower():
                    print(f"  {field_name}: already configured")
                else:
                    print(f"  {field_name}: ERROR - {e}")

    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("FIELD SECURITY DEPLOYMENT COMPLETE")
    print("=" * 60)

    print("\n[Important Notes]")
    print("  - Associate the ELM Approver Fields profile with ELM Approver security role")
    print("  - Test with an approver user to verify field restrictions work")
    print("  - Approvers should only be able to modify: State, Approver, Approved On, Approval Comments")

    return True


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create field security profiles for ELM",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ELM_TENANT_ID"),
        help="Entra ID tenant ID",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ELM_CLIENT_ID"),
        help="Application (client) ID",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ELM_CLIENT_SECRET"),
        help="Client secret",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ELM_ENVIRONMENT_URL"),
        help="Dataverse environment URL",
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
    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    # Get client secret if needed
    client_secret = args.client_secret
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    try:
        client = ELMClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
        )

        success = create_field_security(client, dry_run=args.dry_run)
        if not success:
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
