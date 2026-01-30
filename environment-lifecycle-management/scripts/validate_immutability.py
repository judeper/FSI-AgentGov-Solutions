#!/usr/bin/env python3
"""
Validate ProvisioningLog immutability.

Checks audit log for unauthorized modification attempts and verifies
data integrity of provisioning log entries.
"""

import argparse
import os
import sys
from datetime import datetime, timedelta, timezone

from elm_client import ELMClient


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Validate ProvisioningLog immutability",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Check last 7 days (default)
  python validate_immutability.py \\
    --environment-url https://org.crm.dynamics.com

  # Check specific date range
  python validate_immutability.py \\
    --environment-url https://org.crm.dynamics.com \\
    --start-date 2026-01-01 \\
    --end-date 2026-01-31
        """,
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
        "--start-date",
        help="Start date (YYYY-MM-DD), default: 7 days ago",
    )
    parser.add_argument(
        "--end-date",
        help="End date (YYYY-MM-DD), default: today",
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

    # Parse dates
    if args.end_date:
        end_date = datetime.strptime(args.end_date, "%Y-%m-%d")
    else:
        end_date = datetime.now(timezone.utc)

    if args.start_date:
        start_date = datetime.strptime(args.start_date, "%Y-%m-%d")
    else:
        start_date = end_date - timedelta(days=7)

    print("ProvisioningLog Immutability Validation")
    print("=" * 39)
    print()
    print(f"Date range: {start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}")

    try:
        client = ELMClient(
            tenant_id=args.tenant_id,
            client_id=args.client_id,
            client_secret=client_secret,
            environment_url=args.environment_url,
        )

        # Count total records in range
        logs = client.query(
            "fsi_provisioninglogs",
            select=["fsi_provisioninglogid"],
            filter_expr=(
                f"fsi_timestamp ge {start_date.isoformat()}Z and "
                f"fsi_timestamp le {end_date.isoformat()}Z"
            ),
        )
        record_count = len(logs)
        print(f"Records checked: {record_count}")
        print()

        # Check audit log for modification attempts
        print("Audit Log Analysis:")

        # Query for Update operations (2)
        update_attempts = client.query_audit(
            "fsi_provisioninglog",
            operations=[2],  # Update
            start_date=start_date.isoformat() + "Z",
            end_date=end_date.isoformat() + "Z",
        )

        # Query for Delete operations (3)
        delete_attempts = client.query_audit(
            "fsi_provisioninglog",
            operations=[3],  # Delete
            start_date=start_date.isoformat() + "Z",
            end_date=end_date.isoformat() + "Z",
        )

        violations_found = False

        if update_attempts:
            violations_found = True
            print(f"  Update attempts: {len(update_attempts)} ✗")
            if args.verbose:
                for attempt in update_attempts[:10]:  # Show first 10
                    print(
                        f"    - {attempt.get('createdon')} by "
                        f"{attempt.get('_userid_value', 'Unknown')} "
                        f"(record: {attempt.get('_objectid_value', 'Unknown')[:8]}...)"
                    )
                if len(update_attempts) > 10:
                    print(f"    ... and {len(update_attempts) - 10} more")
        else:
            print("  Update attempts: 0 ✓")

        if delete_attempts:
            violations_found = True
            print(f"  Delete attempts: {len(delete_attempts)} ✗")
            if args.verbose:
                for attempt in delete_attempts[:10]:
                    print(
                        f"    - {attempt.get('createdon')} by "
                        f"{attempt.get('_userid_value', 'Unknown')} "
                        f"(record: {attempt.get('_objectid_value', 'Unknown')[:8]}...)"
                    )
                if len(delete_attempts) > 10:
                    print(f"    ... and {len(delete_attempts) - 10} more")
        else:
            print("  Delete attempts: 0 ✓")

        print()

        # Data integrity checks
        print("Data Integrity:")

        # Check for records with missing required fields
        missing_fields_query = (
            f"fsi_timestamp ge {start_date.isoformat()}Z and "
            f"fsi_timestamp le {end_date.isoformat()}Z and "
            "(fsi_action eq null or fsi_actor eq null or fsi_success eq null)"
        )

        incomplete_records = client.query(
            "fsi_provisioninglogs",
            select=["fsi_provisioninglogid", "fsi_action", "fsi_actor", "fsi_success"],
            filter_expr=missing_fields_query,
        )

        if incomplete_records:
            print(f"  Records with missing fields: {len(incomplete_records)} ✗")
            if args.verbose:
                for rec in incomplete_records[:5]:
                    print(f"    - {rec.get('fsi_provisioninglogid', 'Unknown')[:8]}...")
        else:
            print("  Records with missing fields: 0 ✓")

        # Check for orphaned records (no parent request)
        orphan_query = (
            f"fsi_timestamp ge {start_date.isoformat()}Z and "
            f"fsi_timestamp le {end_date.isoformat()}Z and "
            "_fsi_environmentrequest_value eq null"
        )

        orphaned_records = client.query(
            "fsi_provisioninglogs",
            select=["fsi_provisioninglogid"],
            filter_expr=orphan_query,
        )

        if orphaned_records:
            print(f"  Orphaned records: {len(orphaned_records)} ✗")
        else:
            print("  Orphaned records: 0 ✓")

        print()

        # Summary
        integrity_issues = len(incomplete_records) + len(orphaned_records)

        if violations_found:
            print("ALERT: Immutability violations detected!")
            print()
            if update_attempts:
                print(f"Update attempts: {len(update_attempts)}")
                for attempt in update_attempts[:5]:
                    print(
                        f"  - {attempt.get('createdon')} by "
                        f"{attempt.get('_userid_value', 'Unknown')}"
                    )
            if delete_attempts:
                print(f"Delete attempts: {len(delete_attempts)}")
                for attempt in delete_attempts[:5]:
                    print(
                        f"  - {attempt.get('createdon')} by "
                        f"{attempt.get('_userid_value', 'Unknown')}"
                    )
            print()
            print("Result: FAILED - Investigate immediately")
            print()
            print("Recommended actions:")
            print("  1. Review security role assignments")
            print("  2. Check for System Administrator overrides")
            print("  3. Document incident per security policy")
            print("  4. Contact security team if unauthorized")
            sys.exit(3)

        elif integrity_issues > 0:
            print("WARNING: Data integrity issues found")
            print()
            print(f"Result: PARTIAL - {integrity_issues} integrity issue(s)")
            print()
            print("Recommended actions:")
            print("  1. Review records with missing fields")
            print("  2. Investigate orphaned log entries")
            print("  3. Fix data issues if possible")
            sys.exit(3)

        else:
            print("Result: PASSED - No immutability violations detected")
            print()
            print("Summary:")
            print(f"  - Records validated: {record_count}")
            print("  - Update attempts: 0")
            print("  - Delete attempts: 0")
            print("  - Data integrity: OK")
            sys.exit(0)

    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
