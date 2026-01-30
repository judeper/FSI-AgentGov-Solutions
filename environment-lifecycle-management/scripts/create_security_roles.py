#!/usr/bin/env python3
"""
Create security roles for Environment Lifecycle Management.

Creates ELM Requester, ELM Approver, ELM Admin, and ELM Auditor roles
with appropriate privilege assignments.
"""

import argparse
import os
import sys
from typing import Optional

from elm_client import ELMClient

# Privilege depth constants
DEPTH_USER = 1       # Own records only
DEPTH_BU = 2         # Business unit records
DEPTH_PARENT_BU = 4  # Parent:Child business units
DEPTH_ORG = 8        # Organization-wide

# Role definitions with privilege matrices
ROLES = {
    "ELM Requester": {
        "description": "Submit and track own environment requests",
        "privileges": {
            "fsi_environmentrequest": {
                "Create": DEPTH_USER,
                "Read": DEPTH_USER,
                "Write": DEPTH_USER,
                "Append": DEPTH_USER,
                "AppendTo": DEPTH_USER,
            },
            "fsi_provisioninglog": {
                "Read": DEPTH_USER,
            },
        },
    },
    "ELM Approver": {
        "description": "Approve environment requests within business unit",
        "privileges": {
            "fsi_environmentrequest": {
                "Read": DEPTH_BU,
                "Write": DEPTH_BU,  # Field-level security restricts to approval fields
            },
            "fsi_provisioninglog": {
                "Read": DEPTH_BU,
            },
        },
    },
    "ELM Admin": {
        "description": "Full access for automation and administration",
        "privileges": {
            "fsi_environmentrequest": {
                "Create": DEPTH_ORG,
                "Read": DEPTH_ORG,
                "Write": DEPTH_ORG,
                "Append": DEPTH_ORG,
                "AppendTo": DEPTH_ORG,
            },
            "fsi_provisioninglog": {
                "Create": DEPTH_ORG,
                "Read": DEPTH_ORG,
                # NOTE: No Write or Delete - enforces immutability
            },
        },
    },
    "ELM Auditor": {
        "description": "Read-only access for compliance and audit",
        "privileges": {
            "fsi_environmentrequest": {
                "Read": DEPTH_ORG,
            },
            "fsi_provisioninglog": {
                "Read": DEPTH_ORG,
            },
        },
    },
}

# Mapping from our privilege names to Dataverse privilege prefixes
PRIVILEGE_PREFIX_MAP = {
    "Create": "prvCreate",
    "Read": "prvRead",
    "Write": "prvWrite",
    "Delete": "prvDelete",
    "Append": "prvAppend",
    "AppendTo": "prvAppendTo",
    "Assign": "prvAssign",
    "Share": "prvShare",
}


def get_privilege_name(operation: str, entity_logical_name: str) -> str:
    """
    Get the Dataverse privilege name for an operation on an entity.

    Args:
        operation: Operation name (Create, Read, Write, etc.)
        entity_logical_name: Entity logical name

    Returns:
        Full privilege name (e.g., prvCreatefsi_environmentrequest)
    """
    prefix = PRIVILEGE_PREFIX_MAP.get(operation)
    if not prefix:
        raise ValueError(f"Unknown operation: {operation}")
    return f"{prefix}{entity_logical_name}"


def create_roles(client: ELMClient, dry_run: bool = False) -> None:
    """Create ELM security roles with privilege assignments."""
    print("\n" + "=" * 60)
    print("ELM Security Roles Deployment")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Get root business unit (required for role creation)
    print("\n[Getting Root Business Unit]")
    root_bu = client.get_root_business_unit()
    bu_id = root_bu["businessunitid"]
    print(f"  Root BU: {root_bu.get('name', 'Unknown')} ({bu_id})")

    # Get all privileges upfront for mapping
    print("\n[Loading Privilege Definitions]")
    all_privileges = client.get_privileges()
    privilege_map = {p["name"]: p["privilegeid"] for p in all_privileges}
    print(f"  Loaded {len(privilege_map)} privileges")

    # Create each role
    print("\n[Creating Security Roles]")
    for role_name, role_def in ROLES.items():
        print(f"\n  {role_name}:")

        # Check if role already exists
        existing_roles = client.get_roles(filter_expr=f"name eq '{role_name}'")
        if existing_roles:
            role_id = existing_roles[0]["roleid"]
            print(f"    Role exists: {role_id}")
        elif dry_run:
            print(f"    Would create role: {role_def['description']}")
            role_id = None
        else:
            # Create the role
            role_data = {
                "name": role_name,
                "description": role_def["description"],
                "businessunitid@odata.bind": f"/businessunits({bu_id})",
            }
            role_id = client.create_role(role_data)
            print(f"    Created role: {role_id}")

        # Assign privileges
        print(f"    Privileges:")
        for entity, operations in role_def["privileges"].items():
            for operation, depth in operations.items():
                priv_name = get_privilege_name(operation, entity)
                priv_id = privilege_map.get(priv_name)

                depth_name = {
                    DEPTH_USER: "User",
                    DEPTH_BU: "BU",
                    DEPTH_PARENT_BU: "Parent:Child",
                    DEPTH_ORG: "Org",
                }.get(depth, str(depth))

                if not priv_id:
                    print(f"      {priv_name}: NOT FOUND (entity may not exist)")
                    continue

                if dry_run:
                    print(f"      {priv_name}: would assign ({depth_name})")
                elif role_id:
                    try:
                        client.add_role_privilege(role_id, priv_id, depth)
                        print(f"      {priv_name}: assigned ({depth_name})")
                    except Exception as e:
                        print(f"      {priv_name}: ERROR - {e}")

    # Verify immutability for ELM Admin
    print("\n[Verifying ELM Admin Immutability]")
    admin_roles = client.get_roles(filter_expr="name eq 'ELM Admin'")
    if admin_roles and not dry_run:
        admin_role_id = admin_roles[0]["roleid"]

        # Check for forbidden privileges
        forbidden = [
            ("prvWritefsi_provisioninglog", "Write"),
            ("prvDeletefsi_provisioninglog", "Delete"),
        ]

        admin_privs = client.get_role_privileges(admin_role_id)
        admin_priv_names = {p.get("name", "") for p in admin_privs}

        all_good = True
        for priv_name, operation in forbidden:
            if priv_name in admin_priv_names:
                print(f"  WARNING: ELM Admin has {operation} on ProvisioningLog!")
                all_good = False
            else:
                print(f"  {operation} on ProvisioningLog: Not granted ✓")

        if all_good:
            print("  Immutability verification: PASSED")
        else:
            print("  Immutability verification: FAILED")
            print("  Remove Write/Delete privileges from ELM Admin role!")
    elif dry_run:
        print("  Would verify no Write/Delete on ProvisioningLog for ELM Admin")
    else:
        print("  ELM Admin role not found, skipping verification")

    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("SECURITY ROLES DEPLOYMENT COMPLETE")
    print("=" * 60)


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create security roles for ELM",
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

        create_roles(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
