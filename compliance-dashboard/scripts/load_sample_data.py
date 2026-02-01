#!/usr/bin/env python3
"""
Load sample data into Dataverse for the Compliance Dashboard.

Usage:
    python load_sample_data.py --environment "https://your-org.crm.dynamics.com"
    python load_sample_data.py --controls-only
    python load_sample_data.py --assessments-only
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
import random

try:
    from msal import ConfidentialClientApplication
    import requests
except ImportError:
    print("Error: Required packages not installed.")
    print("Run: pip install msal requests")
    sys.exit(1)


def get_access_token(tenant_id: str, client_id: str, client_secret: str) -> str:
    """Acquire access token for Dataverse API."""
    authority = f"https://login.microsoftonline.com/{tenant_id}"
    scope = ["https://admin.services.crm.dynamics.com/.default"]

    app = ConfidentialClientApplication(
        client_id,
        authority=authority,
        client_credential=client_secret
    )

    result = app.acquire_token_for_client(scopes=scope)

    if "access_token" not in result:
        raise Exception(f"Failed to acquire token: {result.get('error_description', 'Unknown error')}")

    return result["access_token"]


def load_control_master(dataverse_url: str, token: str, force: bool = False) -> dict:
    """Load control master data from JSON file."""
    script_dir = Path(__file__).parent.parent
    json_path = script_dir / "sample-data" / "control-master.json"

    with open(json_path, 'r') as f:
        controls = json.load(f)

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "OData-MaxVersion": "4.0",
        "OData-Version": "4.0"
    }

    api_url = f"{dataverse_url}/api/data/v9.2/fsi_controlmasters"

    # Check existing records
    existing = requests.get(api_url, headers=headers).json()
    existing_ids = {r.get("fsi_controlid") for r in existing.get("value", [])}

    if existing_ids and not force:
        print(f"Found {len(existing_ids)} existing controls. Use --force to overwrite.")
        return {"loaded": 0, "skipped": len(existing_ids)}

    loaded = 0
    for control in controls:
        if control["fsi_controlid"] in existing_ids and not force:
            continue

        response = requests.post(api_url, headers=headers, json=control)

        if response.status_code in [201, 204]:
            loaded += 1
            print(f"  Loaded: {control['fsi_controlid']} - {control['fsi_name']}")
        else:
            print(f"  Error loading {control['fsi_controlid']}: {response.status_code}")

    return {"loaded": loaded, "total": len(controls)}


def generate_sample_assessments(controls: list, days: int = 90) -> list:
    """Generate sample assessment data for demo purposes."""
    assessments = []
    statuses = [1, 1, 1, 2, 2, 3]  # Weighted toward compliant

    for control in controls:
        # Generate assessments for each applicable zone
        zones = []
        if control.get("fsi_zone1applicable"):
            zones.append(1)
        if control.get("fsi_zone2applicable"):
            zones.append(2)
        if control.get("fsi_zone3applicable"):
            zones.append(3)

        for zone in zones:
            status = random.choice(statuses)
            score = {1: 100, 2: 50, 3: 0}.get(status, 0)

            assessment = {
                "fsi_controlid": control["fsi_controlid"],
                "fsi_zone": zone,
                "fsi_status": status,
                "fsi_score": score,
                "fsi_assessmentdate": (datetime.now() - timedelta(days=random.randint(0, 30))).isoformat(),
                "fsi_notes": f"Sample assessment for {control['fsi_controlid']} Zone {zone}"
            }
            assessments.append(assessment)

    return assessments


def generate_sample_scores(days: int = 90) -> list:
    """Generate sample daily compliance scores for trend analysis."""
    scores = []
    base_score = 75.0

    for i in range(days, 0, -1):
        date = datetime.now() - timedelta(days=i)

        # Simulate gradual improvement with some noise
        trend = i * 0.05  # Improve over time
        noise = random.uniform(-2, 2)
        overall = min(100, max(0, base_score - trend + noise))

        score = {
            "fsi_scoredate": date.strftime("%Y-%m-%d"),
            "fsi_overallscore": round(overall, 1),
            "fsi_pillar1score": round(overall + random.uniform(-5, 5), 1),
            "fsi_pillar2score": round(overall + random.uniform(-5, 5), 1),
            "fsi_pillar3score": round(overall + random.uniform(-5, 5), 1),
            "fsi_pillar4score": round(overall + random.uniform(-5, 5), 1),
            "fsi_zone1score": round(overall + random.uniform(-3, 3), 1),
            "fsi_zone2score": round(overall + random.uniform(-3, 3), 1),
            "fsi_zone3score": round(overall + random.uniform(-8, -2), 1),  # Zone 3 lower
            "fsi_compliantcount": random.randint(45, 55),
            "fsi_partialcount": random.randint(5, 12),
            "fsi_noncompliantcount": random.randint(2, 8),
            "fsi_exceptioncount": random.randint(3, 15)
        }
        scores.append(score)

    return scores


def generate_sample_exceptions() -> list:
    """Generate sample compliance exceptions."""
    severities = [1, 2, 2, 3, 3, 3, 4, 4]
    statuses = [1, 1, 2, 2, 3]

    exception_templates = [
        {"name": "MFA not enforced for Zone 3 agents", "control": "1.11"},
        {"name": "Incomplete supervision documentation", "control": "2.12"},
        {"name": "Missing retention policy configuration", "control": "1.9"},
        {"name": "DLP policy bypass detected", "control": "1.5"},
        {"name": "Segregation of duties violation", "control": "2.8"},
        {"name": "Outdated RAG knowledge source", "control": "2.16"},
        {"name": "Agent accessing unauthorized connector", "control": "1.4"},
        {"name": "Missing bias testing documentation", "control": "2.11"},
    ]

    exceptions = []
    for i, template in enumerate(exception_templates):
        severity = random.choice(severities)
        sla_days = {1: 7, 2: 14, 3: 30, 4: 90}[severity]
        days_open = random.randint(1, sla_days + 10)

        # Calculate SLA status
        if days_open > sla_days:
            sla_status = 3  # Breached
        elif days_open > sla_days * 0.8:
            sla_status = 2  # At Risk
        else:
            sla_status = 1  # On Track

        exception = {
            "fsi_name": template["name"],
            "fsi_controlid": template["control"],
            "fsi_severity": severity,
            "fsi_status": random.choice(statuses),
            "fsi_description": f"Sample exception for {template['control']}: {template['name']}",
            "fsi_targetdate": (datetime.now() + timedelta(days=sla_days - days_open)).strftime("%Y-%m-%d"),
            "fsi_daysopen": days_open,
            "fsi_slastatus": sla_status
        }
        exceptions.append(exception)

    return exceptions


def main():
    parser = argparse.ArgumentParser(description="Load sample data for Compliance Dashboard")
    parser.add_argument("--environment", help="Dataverse environment URL")
    parser.add_argument("--controls-only", action="store_true", help="Load only control master data")
    parser.add_argument("--assessments-only", action="store_true", help="Load only assessment data")
    parser.add_argument("--force", action="store_true", help="Overwrite existing data")
    parser.add_argument("--dry-run", action="store_true", help="Print data without loading")

    args = parser.parse_args()

    print("Compliance Dashboard - Sample Data Loader")
    print("=" * 50)

    # Load control master for reference
    script_dir = Path(__file__).parent.parent
    json_path = script_dir / "sample-data" / "control-master.json"

    with open(json_path, 'r') as f:
        controls = json.load(f)

    print(f"Loaded {len(controls)} control definitions")

    if args.dry_run:
        print("\n[DRY RUN MODE - No data will be loaded]")

        if not args.assessments_only:
            print(f"\nControl Master: {len(controls)} records")
            for c in controls[:5]:
                print(f"  {c['fsi_controlid']}: {c['fsi_name']}")
            print("  ...")

        if not args.controls_only:
            assessments = generate_sample_assessments(controls)
            print(f"\nAssessments: {len(assessments)} records")

            scores = generate_sample_scores()
            print(f"Daily Scores: {len(scores)} records")

            exceptions = generate_sample_exceptions()
            print(f"Exceptions: {len(exceptions)} records")

        return

    if not args.environment:
        print("\nError: --environment is required for actual loading")
        print("Use --dry-run to preview data without loading")
        sys.exit(1)

    # Get credentials from environment
    tenant_id = os.environ.get("AZURE_TENANT_ID")
    client_id = os.environ.get("AZURE_CLIENT_ID")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET")

    if not all([tenant_id, client_id, client_secret]):
        print("\nError: Missing environment variables:")
        print("  AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET")
        sys.exit(1)

    print(f"\nConnecting to: {args.environment}")
    token = get_access_token(tenant_id, client_id, client_secret)
    print("Authentication successful")

    if not args.assessments_only:
        print("\nLoading control master data...")
        result = load_control_master(args.environment, token, args.force)
        print(f"  Loaded: {result['loaded']} records")

    print("\nSample data loading complete!")


if __name__ == "__main__":
    main()
