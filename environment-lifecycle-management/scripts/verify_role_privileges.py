#!/usr/bin/env python3
"""
Verify ELM security role privileges.

Audits security roles to ensure correct configuration, especially
verifying ProvisioningLog immutability (no Write/Delete privileges).
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from typing import Optional

from elm_client import ELMClient


# Expected role configurations
EXPECTED_ROLES = {
    "ELM Requester": {
        "fsi_environmentrequest": {
            "Create": "User",
            "Read": "User",
            "Write": "User",
            "Delete": None,
            "Append": "User",
            "AppendTo": "User",
        },
        "fsi_provisioninglog": {
            "Create": None,
            "Read": "User",
            "Write": None,
            "Delete": None,
            "Append": None,
            "AppendTo": None,
        },
    },
    "ELM Approver": {
        "fsi_environmentrequest": {
            "Create": None,
            "Read": "Business Unit",
            "Write": "Business Unit",
            "Delete": None,
            "Append": None,
            "AppendTo": None,
        },
        "fsi_provisioninglog": {
            "Create": None,
            "Read": "Business Unit",
            "Write": None,
            "Delete": None,
            "Append": None,
            "AppendTo": None,
        },
    },
    "ELM Admin": {
        "fsi_environmentrequest": {
            "Create": "Organization",
            "Read": "Organization",
            "Write": "Organization",
            "Delete": None,
            "Append": "Organization",
            "AppendTo": "Organization",
        },
        "fsi_provisioninglog": {
            "Create": "Organization",
            "Read": "Organization",
            "Write": None,  # CRITICAL: Must be None for immutability
            "Delete": None,  # CRITICAL: Must be None for immutability
            "Append": None,
            "AppendTo": None,
        },
    },
    "ELM Auditor": {
        "fsi_environmentrequest": {
            "Create": None,
            "Read": "Organization",
            "Write": None,
            "Delete": None,
            "Append": None,
            "AppendTo": None,
        },
        "fsi_provisioninglog": {
            "Create": None,
            "Read": "Organization",
            "Write": None,
            "Delete": None,
            "Append": None,
            "AppendTo": None,
        },
    },
}

# Depth mapping
DEPTH_MAP = {
    1: "User",
    2: "Business Unit",
    4: "Parent: Child Business Units",
    8: "Organization",
}


def get_role_privileges(client: ELMClient, role_name: str) -> Optional[dict]:
    """
    Get privileges for a security role.

    Args:
        client: ELM client
        role_name: Security role name

    Returns:
        Dictionary of entity -> privilege -> depth, or None if role not found
    """
    # Query for role
    roles = client.query(
        "roles",
        select=["roleid", "name"],
        filter_expr=f"name eq '{role_name}'",
    )

    if not roles:
        return None

    role_id = roles[0]["roleid"]

    # Use FetchXML to query role privileges with expanded privilege details
    # This avoids N+1 queries by fetching everything in one request
    fetchxml = f"""
    <fetch>
      <entity name="roleprivileges">
        <attribute name="privilegeid" />
        <attribute name="privilegedepthmask" />
        <filter type="and">
          <condition attribute="roleid" operator="eq" value="{role_id}" />
        </filter>
        <link-entity name="privilege" from="privilegeid" to="privilegeid" alias="priv">
          <attribute name="name" />
          <attribute name="accessright" />
        </link-entity>
      </entity>
    </fetch>
    """

    privileges = client.query_fetchxml("roleprivilegescollection", fetchxml)

    # Build privilege map
    priv_map = {}
    for priv in privileges:
        depth = priv.get("privilegedepthmask", 0)
        # Linked entity attributes come with alias prefix
        priv_name = priv.get("priv.name", priv.get("priv_x002e_name", ""))

        # Parse privilege name (e.g., "prvCreatefsi_environmentrequest")
        if priv_name.startswith("prv"):
            # Extract action and entity
            for action in ["Create", "Read", "Write", "Delete", "Append", "AppendTo"]:
                if priv_name.startswith(f"prv{action}"):
                    entity = priv_name[len(f"prv{action}"):]
                    if entity not in priv_map:
                        priv_map[entity] = {}
                    priv_map[entity][action] = DEPTH_MAP.get(depth, f"Unknown({depth})")
                    break

    return priv_map


def verify_role(
    role_name: str,
    actual: Optional[dict],
    expected: dict,
    verbose: bool = False,
) -> tuple[bool, list[str]]:
    """
    Verify role matches expected configuration.

    Args:
        role_name: Role name
        actual: Actual privileges
        expected: Expected privileges
        verbose: Show detailed output

    Returns:
        Tuple of (passed, list of issues)
    """
    issues = []

    if actual is None:
        return False, [f"Role '{role_name}' not found"]

    for entity, privs in expected.items():
        actual_entity = actual.get(entity, {})

        for priv_type, expected_depth in privs.items():
            actual_depth = actual_entity.get(priv_type)

            if expected_depth is None:
                # Privilege should NOT be granted
                if actual_depth is not None:
                    issues.append(
                        f"{entity}: {priv_type} should NOT be granted "
                        f"(found: {actual_depth})"
                    )
            else:
                # Privilege should be granted at specific depth
                if actual_depth is None:
                    issues.append(
                        f"{entity}: {priv_type} should be {expected_depth} "
                        f"(not granted)"
                    )
                elif actual_depth != expected_depth:
                    issues.append(
                        f"{entity}: {priv_type} should be {expected_depth} "
                        f"(found: {actual_depth})"
                    )

    return len(issues) == 0, issues


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Verify ELM security role privileges",
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
        required=True,
        help="Dataverse environment URL",
    )
    parser.add_argument(
        "--role-name",
        help="Check specific role only",
    )
    parser.add_argument(
        "--output-path",
        help="Export results to JSON file",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Show detailed output",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not all([args.tenant_id, args.client_id, args.environment_url]):
        parser.error("Missing required arguments or environment variables")

    # Prompt for secret if not provided
    client_secret = args.client_secret
    if not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")

    print("ELM Role Privilege Audit")
    print("=" * 24)
    print()

    try:
        client = ELMClient(
            tenant_id=args.tenant_id,
            client_id=args.client_id,
            client_secret=client_secret,
            environment_url=args.environment_url,
        )

        results = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "environment": args.environment_url,
            "roles": {},
        }

        all_passed = True
        roles_to_check = [args.role_name] if args.role_name else EXPECTED_ROLES.keys()

        for role_name in roles_to_check:
            print(f"Checking {role_name}...")

            expected = EXPECTED_ROLES.get(role_name, {})
            actual = get_role_privileges(client, role_name)
            passed, issues = verify_role(role_name, actual, expected, args.verbose)

            results["roles"][role_name] = {
                "passed": passed,
                "issues": issues,
                "actual": actual,
            }

            if passed:
                # Show summary of granted privileges
                for entity in expected:
                    granted = []
                    for priv, depth in expected[entity].items():
                        if depth:
                            granted.append(f"{priv}({depth[:3]})")
                    if granted:
                        print(f"  {entity}: {' '.join(granted)} ✓")

                # Special verification for ELM Admin
                if role_name == "ELM Admin":
                    print("  [VERIFY] No Write privilege on fsi_provisioninglog ✓")
                    print("  [VERIFY] No Delete privilege on fsi_provisioninglog ✓")
            else:
                all_passed = False
                for issue in issues:
                    print(f"  ✗ {issue}")

            print()

        # Summary
        print("=" * 24)
        if all_passed:
            print("Summary: All roles configured correctly ✓")
            print()
            print("Immutability verification: PASSED")
            print("  - ELM Admin has no Write on fsi_provisioninglog")
            print("  - ELM Admin has no Delete on fsi_provisioninglog")
        else:
            print("Summary: Configuration issues found ✗")
            print()
            print("Recommended actions:")
            print("  1. Review security role definitions")
            print("  2. Remove unauthorized privileges")
            print("  3. Re-run verification")

        # Export to JSON if requested
        if args.output_path:
            with open(args.output_path, "w") as f:
                json.dump(results, f, indent=2)
            print(f"\nResults exported to: {args.output_path}")

        sys.exit(0 if all_passed else 3)

    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
