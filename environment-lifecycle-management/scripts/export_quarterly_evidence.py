#!/usr/bin/env python3
"""
Export quarterly evidence for Environment Lifecycle Management.

Exports EnvironmentRequest and ProvisioningLog tables with SHA-256 integrity hashing.
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from elm_client import ELMClient


def calculate_sha256(content: str) -> str:
    """Calculate SHA-256 hash of content."""
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def get_quarter(date: datetime) -> str:
    """Get quarter string for date (e.g., 'Q1')."""
    return f"Q{(date.month - 1) // 3 + 1}"


def export_table(
    client: ELMClient,
    entity_name: str,
    entity_set: str,
    start_date: str,
    end_date: str,
    date_field: str,
    verbose: bool = False,
) -> tuple[list[dict], int]:
    """
    Export table records using FetchXML.

    Args:
        client: ELM client instance
        entity_name: Entity logical name (e.g., "fsi_environmentrequest")
        entity_set: Entity set name (e.g., "fsi_environmentrequests")
        start_date: ISO date string (YYYY-MM-DD)
        end_date: ISO date string (YYYY-MM-DD)
        date_field: Field to filter by date
        verbose: Show detailed output

    Returns:
        Tuple of (records, count)
    """
    # FetchXML for date range query
    fetchxml = f"""
    <fetch>
      <entity name="{entity_name}">
        <all-attributes />
        <filter type="and">
          <condition attribute="{date_field}" operator="ge" value="{start_date}T00:00:00Z" />
          <condition attribute="{date_field}" operator="le" value="{end_date}T23:59:59Z" />
        </filter>
        <order attribute="{date_field}" />
      </entity>
    </fetch>
    """

    if verbose:
        print(f"  Querying {entity_name} from {start_date} to {end_date}...")

    records = client.query_fetchxml(entity_set, fetchxml)

    if verbose:
        print(f"  Retrieved {len(records)} records")

    return records, len(records)


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Export quarterly evidence for ELM",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Export Q1 2026
  python export_quarterly_evidence.py \\
    --environment-url https://org.crm.dynamics.com \\
    --output-path ./exports \\
    --start-date 2026-01-01 \\
    --end-date 2026-03-31

  # With verbose output
  python export_quarterly_evidence.py \\
    --environment-url https://org.crm.dynamics.com \\
    --output-path ./exports \\
    --start-date 2026-01-01 \\
    --end-date 2026-03-31 \\
    --verbose
        """,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ELM_TENANT_ID"),
        help="Entra ID tenant ID (or set ELM_TENANT_ID)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ELM_CLIENT_ID"),
        help="Application (client) ID (or set ELM_CLIENT_ID)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ELM_CLIENT_SECRET"),
        help="Client secret (or set ELM_CLIENT_SECRET)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ELM_ENVIRONMENT_URL"),
        required=True,
        help="Dataverse environment URL",
    )
    parser.add_argument(
        "--output-path",
        required=True,
        help="Directory for output files",
    )
    parser.add_argument(
        "--start-date",
        required=True,
        help="Start date (YYYY-MM-DD)",
    )
    parser.add_argument(
        "--end-date",
        required=True,
        help="End date (YYYY-MM-DD)",
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
    try:
        start_date = datetime.strptime(args.start_date, "%Y-%m-%d")
        end_date = datetime.strptime(args.end_date, "%Y-%m-%d")
    except ValueError as e:
        parser.error(f"Invalid date format: {e}")

    # Determine quarter for filenames
    quarter = get_quarter(start_date)
    year = start_date.year

    print("ELM Quarterly Evidence Export")
    print("=" * 30)
    print(f"Date range: {args.start_date} to {args.end_date}")
    print(f"Quarter: {year}-{quarter}")
    print()

    try:
        # Initialize client
        client = ELMClient(
            tenant_id=args.tenant_id,
            client_id=args.client_id,
            client_secret=client_secret,
            environment_url=args.environment_url,
        )

        # Create output directory
        output_path = Path(args.output_path)
        output_path.mkdir(parents=True, exist_ok=True)

        manifest = {
            "exportDate": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "exportedBy": "export_quarterly_evidence.py",
            "environmentUrl": args.environment_url,
            "dateRange": {
                "start": args.start_date,
                "end": args.end_date,
            },
            "files": [],
        }

        # Export EnvironmentRequest
        print("Exporting EnvironmentRequest...")
        requests_data, requests_count = export_table(
            client,
            entity_name="fsi_environmentrequest",
            entity_set="fsi_environmentrequests",
            start_date=args.start_date,
            end_date=args.end_date,
            date_field="fsi_requestedon",
            verbose=args.verbose,
        )

        requests_filename = f"EnvironmentRequest-{year}-{quarter}.json"
        requests_content = json.dumps(requests_data, indent=2, default=str)
        requests_hash = calculate_sha256(requests_content)

        (output_path / requests_filename).write_text(requests_content)
        print(f"  Exported {requests_count} records to {requests_filename}")
        print(f"  SHA-256: {requests_hash[:16]}...")

        if requests_count == 0:
            print("  WARNING: No EnvironmentRequest records found in date range")

        manifest["files"].append({
            "name": requests_filename,
            "table": "fsi_environmentrequest",
            "recordCount": requests_count,
            "sha256": requests_hash,
            "isEmpty": requests_count == 0,
        })

        # Export ProvisioningLog
        print()
        print("Exporting ProvisioningLog...")
        logs_data, logs_count = export_table(
            client,
            entity_name="fsi_provisioninglog",
            entity_set="fsi_provisioninglogs",
            start_date=args.start_date,
            end_date=args.end_date,
            date_field="fsi_timestamp",
            verbose=args.verbose,
        )

        logs_filename = f"ProvisioningLog-{year}-{quarter}.json"
        logs_content = json.dumps(logs_data, indent=2, default=str)
        logs_hash = calculate_sha256(logs_content)

        (output_path / logs_filename).write_text(logs_content)
        print(f"  Exported {logs_count} records to {logs_filename}")
        print(f"  SHA-256: {logs_hash[:16]}...")

        if logs_count == 0:
            print("  WARNING: No ProvisioningLog records found in date range")

        manifest["files"].append({
            "name": logs_filename,
            "table": "fsi_provisioninglog",
            "recordCount": logs_count,
            "sha256": logs_hash,
            "isEmpty": logs_count == 0,
        })

        # Write manifest
        print()
        print("Writing manifest...")
        manifest_content = json.dumps(manifest, indent=2)
        manifest_hash = calculate_sha256(manifest_content)
        manifest["manifestHash"] = manifest_hash

        manifest_path = output_path / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2))
        print(f"  Manifest: {manifest_path}")

        # Summary
        print()
        print("Export Complete")
        print("=" * 15)
        print(f"Output directory: {output_path}")
        print(f"Total records: {requests_count + logs_count}")
        print()
        print("Files created:")
        for f in manifest["files"]:
            print(f"  - {f['name']} ({f['recordCount']} records)")
        print(f"  - manifest.json")

        # Warn if both exports are empty
        if requests_count == 0 and logs_count == 0:
            print()
            print("NOTICE: Both exports contain 0 records.")
            print("  This may indicate:")
            print("  - No activity in the specified date range")
            print("  - Incorrect date range parameters")
            print("  - ELM tables not yet populated")

        print()
        print("Integrity verification:")
        print("  To verify exports, compare SHA-256 hashes in manifest.json")
        print("  with recalculated hashes of the exported files.")

        sys.exit(0)

    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
