#!/usr/bin/env python3
"""
FINRA Supervision Workflow - Evidence Export Script

Exports supervision queue and log data for regulatory examination
and compliance evidence with SHA-256 integrity hashing.

Usage:
    python export_supervision_evidence.py \
        --environment-url https://org.crm.dynamics.com \
        --output-path ./exports \
        --start-date 2026-01-01 \
        --end-date 2026-01-31
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone

try:
    import requests
    import msal  # noqa: F401 — validate msal is installed (used by auth.py)
except ImportError:
    print("Error: Required packages not installed.")
    print("Run: pip install -r requirements.txt")
    sys.exit(1)

# Import shared authentication module
_script_dir = os.path.dirname(os.path.abspath(__file__))
if _script_dir not in sys.path:
    sys.path.insert(0, _script_dir)
from auth import get_access_token


def fetch_records(environment_url: str, access_token: str, entity_set: str,
                  filter_query: str = None, select_columns: list = None) -> tuple:
    """Fetch records from Dataverse with pagination."""
    base_url = f"{environment_url.rstrip('/')}/api/data/v9.2/{entity_set}"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "OData-MaxVersion": "4.0",
        "OData-Version": "4.0",
        "Prefer": "odata.maxpagesize=5000"
    }

    params = []
    if filter_query:
        params.append(f"$filter={filter_query}")
    if select_columns:
        params.append(f"$select={','.join(select_columns)}")

    url = base_url
    if params:
        url += "?" + "&".join(params)

    all_records = []
    had_error = False
    while url:
        max_retries = 3
        response = None
        for attempt in range(max_retries + 1):
            try:
                response = requests.get(url, headers=headers, timeout=30)
            except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as exc:
                if attempt < max_retries:
                    retry_after = 2 ** attempt * 5
                    print(f"  Connection error: {exc}, retrying in {retry_after}s (attempt {attempt + 1}/{max_retries})...")
                    time.sleep(retry_after)
                    continue
                raise SystemExit(f"Request failed after {max_retries} retries: {exc}") from exc
            if response.status_code in (429, 503) and attempt < max_retries:
                raw_retry = response.headers.get("Retry-After")
                try:
                    retry_after = int(raw_retry) if raw_retry is not None else 2 ** attempt * 5
                except (ValueError, TypeError):
                    retry_after = 2 ** attempt * 5
                print(f"  Received {response.status_code}, retrying in {retry_after}s (attempt {attempt + 1}/{max_retries})...")
                time.sleep(retry_after)
                continue
            break

        if response.status_code != 200:
            print(f"WARNING: API error fetching records: {response.status_code}")
            print(response.text)
            print("WARNING: Export may contain partial data. Verify completeness before submitting as regulatory evidence.")
            had_error = True
            break

        data = response.json()
        records = data.get("value", [])
        all_records.extend(records)

        # Handle pagination
        url = data.get("@odata.nextLink")
        if url:
            print(f"  Fetching next page... ({len(all_records)} records so far)")

    return all_records, had_error


def calculate_sha256(filepath: str) -> str:
    """Calculate SHA-256 hash of a file."""
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def export_to_json(data: list, filepath: str) -> dict:
    """Export data to JSON file and return metadata."""
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, default=str)

    file_hash = calculate_sha256(filepath)
    file_size = os.path.getsize(filepath)

    return {
        "filename": os.path.basename(filepath),
        "record_count": len(data) if isinstance(data, list) else 1,
        "file_size_bytes": file_size,
        "sha256_hash": file_hash,
        "exported_at": datetime.now(timezone.utc).isoformat()
    }


def generate_sla_metrics(queue_records: list) -> dict:
    """Calculate SLA compliance metrics from queue records."""
    total = len(queue_records)
    if total == 0:
        return {"total": 0, "message": "No records in date range"}

    completed = [r for r in queue_records if r.get("fsi_state") in [3, 5]]  # Approved or Rejected
    pending = [r for r in queue_records if r.get("fsi_state") in [1, 2]]  # Pending or InReview
    escalated = [r for r in queue_records if r.get("fsi_state") == 4]  # Escalated

    # Calculate SLA breaches (items completed after SLA due)
    sla_breached = 0
    for record in completed:
        reviewed_date = record.get("fsi_revieweddate")
        sla_due = record.get("fsi_sladue")
        if reviewed_date and sla_due:
            reviewed_dt = datetime.fromisoformat(reviewed_date.replace("Z", "+00:00"))
            sla_dt = datetime.fromisoformat(sla_due.replace("Z", "+00:00"))
            if reviewed_dt > sla_dt:
                sla_breached += 1

    # Calculate average review time for completed items
    review_times = []
    for record in completed:
        queued_date = record.get("fsi_queueddate")
        reviewed_date = record.get("fsi_revieweddate")
        if queued_date and reviewed_date:
            # Parse ISO dates and calculate difference
            try:
                queued = datetime.fromisoformat(queued_date.replace("Z", "+00:00"))
                reviewed = datetime.fromisoformat(reviewed_date.replace("Z", "+00:00"))
                hours = (reviewed - queued).total_seconds() / 3600
                review_times.append(hours)
            except (ValueError, TypeError):
                pass

    avg_review_time = sum(review_times) / len(review_times) if review_times else 0

    return {
        "total_items": total,
        "completed": len(completed),
        "pending": len(pending),
        "escalated": len(escalated),
        "sla_breached": sla_breached,
        "sla_compliance_rate": round((len(completed) - sla_breached) / len(completed) * 100, 2) if completed else 0,
        "average_review_time_hours": round(avg_review_time, 2),
        "by_zone": {
            "zone_1": len([r for r in queue_records if r.get("fsi_zone") == 1]),
            "zone_2": len([r for r in queue_records if r.get("fsi_zone") == 2]),
            "zone_3": len([r for r in queue_records if r.get("fsi_zone") == 3]),
        },
        "by_outcome": {
            "approved": len([r for r in completed if r.get("fsi_reviewoutcome") == 1]),
            "rejected": len([r for r in completed if r.get("fsi_reviewoutcome") == 2]),
            "escalated": len([r for r in completed if r.get("fsi_reviewoutcome") == 3]),
        }
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Export FINRA Supervision Workflow evidence")
    parser.add_argument("--environment-url", required=True, help="Dataverse environment URL")
    parser.add_argument("--tenant-id", required=True, help="Microsoft Entra ID tenant ID (GUID format: 12345678-1234-1234-1234-123456789abc)")
    parser.add_argument("--client-id", help="Service principal client ID")
    parser.add_argument("--client-secret", help="Service principal client secret (prefer FSW_CLIENT_SECRET env var to avoid process list exposure)")
    parser.add_argument("--interactive", action="store_true", help="Use interactive authentication")
    parser.add_argument("--output-path", required=True, help="Output directory for exports")
    parser.add_argument("--start-date", required=True, help="Start date (YYYY-MM-DD)")
    parser.add_argument("--end-date", required=True, help="End date (YYYY-MM-DD)")

    args = parser.parse_args()

    # Fall back to environment variable for client secret
    if not args.client_secret:
        args.client_secret = os.environ.get("FSW_CLIENT_SECRET")

    # Validate tenant-id GUID format
    guid_pattern = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
    if not guid_pattern.match(args.tenant_id):
        print("Error: --tenant-id must be a valid GUID (e.g., 12345678-1234-1234-1234-123456789abc)")
        sys.exit(1)

    # Validate HTTPS
    if not args.environment_url.startswith("https://"):
        print("Error: --environment-url must start with 'https://' (e.g., https://org.crm.dynamics.com)")
        sys.exit(1)

    print("=" * 60)
    print("FINRA Supervision Workflow - Evidence Export")
    print("=" * 60)
    print(f"Environment: {args.environment_url}")
    print(f"Date Range: {args.start_date} to {args.end_date}")
    print(f"Output Path: {args.output_path}")
    print(f"Timestamp: {datetime.now(timezone.utc).isoformat()}")

    # Create output directory
    os.makedirs(args.output_path, exist_ok=True)

    # Authenticate
    print("\nAuthenticating...")
    if args.interactive:
        access_token = get_access_token(
            args.tenant_id,
            interactive=True,
            environment_url=args.environment_url
        )
    elif args.client_id and args.client_secret:
        access_token = get_access_token(
            args.tenant_id,
            client_id=args.client_id,
            client_secret=args.client_secret,
            environment_url=args.environment_url
        )
    else:
        print("Error: Specify --interactive or provide --client-id and --client-secret")
        sys.exit(1)

    print("Authentication successful")

    # Parse and validate dates
    try:
        start_dt = datetime.strptime(args.start_date, "%Y-%m-%d")
    except ValueError:
        print(f"Error: --start-date '{args.start_date}' is not in YYYY-MM-DD format")
        sys.exit(1)
    try:
        end_dt = datetime.strptime(args.end_date, "%Y-%m-%d")
    except ValueError:
        print(f"Error: --end-date '{args.end_date}' is not in YYYY-MM-DD format")
        sys.exit(1)
    if start_dt > end_dt:
        print(f"Error: --start-date ({args.start_date}) must not be after --end-date ({args.end_date})")
        sys.exit(1)

    # Build date filter
    # Use lt next-day instead of le 23:59:59Z to avoid missing sub-second items
    end_next_day = (end_dt + timedelta(days=1)).strftime("%Y-%m-%d")
    date_filter = f"fsi_queueddate ge {args.start_date}T00:00:00Z and fsi_queueddate lt {end_next_day}T00:00:00Z"

    # Determine if this is a week or quarter export
    days_diff = (end_dt - start_dt).days
    if days_diff <= 7:
        week_num = start_dt.isocalendar()[1]
        period_suffix = f"Week{week_num:02d}-{start_dt.year}"
    else:
        quarter = (start_dt.month - 1) // 3 + 1
        period_suffix = f"Q{quarter}-{start_dt.year}"

    manifest = {
        "export_info": {
            "environment": args.environment_url,
            "start_date": args.start_date,
            "end_date": args.end_date,
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "exported_by": "export_supervision_evidence.py v1.0.0",
            "status": "complete"
        },
        "files": []
    }

    has_errors = False

    # Export SupervisionQueue
    print("\nExporting SupervisionQueue...")
    queue_records, queue_error = fetch_records(
        args.environment_url,
        access_token,
        "fsi_supervisionqueues",
        filter_query=date_filter
    )
    if queue_error:
        has_errors = True
    print(f"  Found {len(queue_records)} queue records")

    queue_filepath = os.path.join(args.output_path, f"SupervisionQueue-{period_suffix}.json")
    queue_metadata = export_to_json(queue_records, queue_filepath)
    manifest["files"].append(queue_metadata)
    print(f"  Exported to: {queue_filepath}")
    print(f"  SHA-256: {queue_metadata['sha256_hash']}")

    # Export SupervisionLog
    print("\nExporting SupervisionLog...")
    log_filter = f"fsi_timestamp ge {args.start_date}T00:00:00Z and fsi_timestamp lt {end_next_day}T00:00:00Z"
    log_records, log_error = fetch_records(
        args.environment_url,
        access_token,
        "fsi_supervisionlogs",
        filter_query=log_filter
    )
    if log_error:
        has_errors = True
    print(f"  Found {len(log_records)} log records")

    log_filepath = os.path.join(args.output_path, f"SupervisionLog-{period_suffix}.json")
    log_metadata = export_to_json(log_records, log_filepath)
    manifest["files"].append(log_metadata)
    print(f"  Exported to: {log_filepath}")
    print(f"  SHA-256: {log_metadata['sha256_hash']}")

    # Generate SLA metrics
    print("\nGenerating SLA Compliance Metrics...")
    sla_metrics = generate_sla_metrics(queue_records)

    metrics_filepath = os.path.join(args.output_path, f"SLACompliance-{period_suffix}.json")
    metrics_metadata = export_to_json(sla_metrics, metrics_filepath)
    manifest["files"].append(metrics_metadata)
    print(f"  Exported to: {metrics_filepath}")

    # Print summary metrics
    print("\n  SLA Summary:")
    print(f"    Total Items: {sla_metrics.get('total_items', 0)}")
    print(f"    Completed: {sla_metrics.get('completed', 0)}")
    print(f"    SLA Compliance Rate: {sla_metrics.get('sla_compliance_rate', 0)}%")
    print(f"    Avg Review Time: {sla_metrics.get('average_review_time_hours', 0)} hours")

    # Export SupervisionConfig (for reference)
    print("\nExporting SupervisionConfig...")
    config_records, config_error = fetch_records(
        args.environment_url,
        access_token,
        "fsi_supervisionconfigs",
        filter_query="fsi_active eq true"
    )
    if config_error:
        has_errors = True
    print(f"  Found {len(config_records)} config records")

    config_filepath = os.path.join(args.output_path, f"SupervisionConfig-{period_suffix}.json")
    config_metadata = export_to_json(config_records, config_filepath)
    manifest["files"].append(config_metadata)
    print(f"  Exported to: {config_filepath}")

    # Update manifest status based on errors
    if has_errors:
        manifest["export_info"]["status"] = "partial"

    # Write manifest and compute a companion hash file for integrity verification.
    # NOTE: A self-hash embedded inside the manifest cannot match the final file's
    # SHA-256 (bootstrapping impossibility). Instead, write the manifest first, then
    # save the hash to a separate sidecar file that can be independently verified.
    manifest_filepath = os.path.join(args.output_path, f"manifest-{period_suffix}.json")
    with open(manifest_filepath, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    manifest_hash = calculate_sha256(manifest_filepath)
    hash_filepath = os.path.join(args.output_path, f"manifest-{period_suffix}.sha256")
    with open(hash_filepath, "w", encoding="utf-8") as f:
        f.write(f"{manifest_hash}  manifest-{period_suffix}.json\n")

    print(f"\nManifest written to: {manifest_filepath}")
    print(f"  Hash sidecar: {hash_filepath}")
    print(f"  Manifest SHA-256: {manifest_hash}")
    print("\n  *** SEC 17a-4 Evidence Integrity Notice ***")
    print("  The manifest records SHA-256 hashes for each exported file, and a companion")
    print("  .sha256 sidecar verifies the manifest itself. However, this alone is")
    print("  insufficient for regulatory evidence. To ensure chain")
    print("  of custody, store exports on WORM (Write Once Read Many) storage or")
    print("  generate a detached digital signature for the manifest file.")
    print("  Example: gpg --detach-sign --armor manifest-{}.json".format(period_suffix))

    print("\n" + "=" * 60)
    print("Export Complete")
    print("=" * 60)
    print(f"\nFiles exported to: {args.output_path}")
    print(f"Total files: {len(manifest['files']) + 1}")  # +1 for manifest
    print("\nFor regulatory examination, provide:")
    print(f"  1. {os.path.basename(queue_filepath)}")
    print(f"  2. {os.path.basename(log_filepath)}")
    print(f"  3. {os.path.basename(metrics_filepath)}")
    print(f"  4. {os.path.basename(manifest_filepath)} (integrity verification)")

    if has_errors:
        print("\nWARNING: Export completed with errors. Data may be incomplete.")
        print("Do not submit as regulatory evidence without verifying completeness.")
        sys.exit(1)


if __name__ == "__main__":
    main()
