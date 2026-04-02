#!/usr/bin/env python3
"""
Load sample data into Dataverse for the Compliance Dashboard.

Usage:
    python load_sample_data.py --environment "https://your-org.crm.dynamics.com"
    python load_sample_data.py --controls-only
    python load_sample_data.py --assessments-only
    python load_sample_data.py --dry-run
    python load_sample_data.py --export
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
    from requests.adapters import HTTPAdapter
    from urllib3.util.retry import Retry
except ImportError:
    print("Error: Required packages not installed.")
    print("Run: pip install msal requests")
    sys.exit(1)


def get_access_token(tenant_id: str, client_id: str, client_secret: str, environment_url: str = None) -> str:
    """Acquire access token for Dataverse API."""
    authority = f"https://login.microsoftonline.com/{tenant_id}"
    # Use environment-specific scope; fall back to env var or error
    base_url = environment_url or os.environ.get("DATAVERSE_URL")
    if not base_url:
        raise ValueError(
            "Dataverse environment URL required. Pass --environment or set DATAVERSE_URL."
        )
    scope = [f"{base_url.rstrip('/')}/.default"]

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

    try:
        with open(json_path, 'r') as f:
            controls = json.load(f)
    except FileNotFoundError:
        raise FileNotFoundError(f"Control master file not found: {json_path}. Ensure sample data directory exists.")
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON in control master file {json_path}: {e}")

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "OData-MaxVersion": "4.0",
        "OData-Version": "4.0"
    }

    api_url = f"{dataverse_url}/api/data/v9.2/fsi_controlmasters"

    # Configure retry adapter
    session = requests.Session()
    retry_strategy = Retry(total=3, backoff_factor=1, status_forcelist=[429, 500, 502, 503, 504])
    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("https://", adapter)

    # Check existing records (with pagination)
    existing_records = []
    next_url = api_url
    while next_url:
        response = session.get(next_url, headers=headers)
        response.raise_for_status()
        existing = response.json()
        existing_records.extend(existing.get("value", []))
        next_url = existing.get("@odata.nextLink")
    existing_ids = {r.get("fsi_controlid") for r in existing_records}

    if existing_ids and not force:
        print(f"Found {len(existing_ids)} existing controls. Use --force to overwrite.")
        return {"loaded": 0, "skipped": len(existing_ids)}

    loaded = 0
    for control in controls:
        if control["fsi_controlid"] in existing_ids and not force:
            continue

        response = session.post(api_url, headers=headers, json=control)

        if response.status_code in [201, 204]:
            loaded += 1
            print(f"  Loaded: {control['fsi_controlid']} - {control['fsi_name']}")
        else:
            print(f"  Error loading {control['fsi_controlid']}: {response.status_code}")

    return {"loaded": loaded, "total": len(controls)}


def generate_sample_assessments(controls: list, days: int = 90) -> list:
    """Generate sample assessment data for demo purposes with 90-day history."""
    random.seed(42)  # Reproducible data
    assessments = []

    # Weighted status distribution: 50% compliant, 33% partial, 17% non-compliant
    status_pool = [1, 1, 1, 2, 2, 3]

    # Generate weekly assessments over 90 days
    weeks = 13  # ~90 days / 7

    for control in controls:
        # Generate assessments for each applicable zone
        zones = []
        if control.get("fsi_zone1applicable"):
            zones.append(1)
        if control.get("fsi_zone2applicable"):
            zones.append(2)
        if control.get("fsi_zone3applicable"):
            zones.append(3)

        # Add control-specific variance (some controls consistently worse)
        control_num = int(control["fsi_controlid"].split(".")[1])
        is_problem_control = control_num % 7 == 0  # Every 7th control tends worse

        for zone in zones:
            for week in range(weeks):
                # Calculate assessment date (working backwards from now)
                days_ago = week * 7 + random.randint(0, 3)
                assessment_date = datetime.now() - timedelta(days=days_ago)

                # Gradual improvement trend (earlier weeks slightly worse)
                improvement_factor = 1.0 - (week * 0.02)  # 2% worse per week back

                # Status selection with bias
                if is_problem_control:
                    # Problem controls: shift distribution toward non-compliant
                    status_weights = [1, 1, 2, 2, 3, 3]
                else:
                    status_weights = status_pool

                status = random.choice(status_weights)

                # Apply improvement trend (earlier data more likely non-compliant)
                if week > 6 and random.random() > improvement_factor:
                    status = min(status + 1, 3)  # Degrade status for older data

                score = {1: 100, 2: 50, 3: 0}.get(status, 0)

                assessment = {
                    "fsi_controlid": control["fsi_controlid"],
                    "fsi_zone": zone,
                    "fsi_status": status,
                    "fsi_score": score,
                    "fsi_assessmentdate": assessment_date.isoformat(),
                    "fsi_notes": f"Sample assessment for {control['fsi_controlid']} Zone {zone}"
                }
                assessments.append(assessment)

    return assessments


def generate_sample_scores(days: int = 90) -> list:
    """Generate sample daily compliance scores for trend analysis."""
    random.seed(42)  # Reproducible data
    scores = []
    base_score = 75.0

    for i in range(days, 0, -1):
        date = datetime.now() - timedelta(days=i)

        # Simulate gradual improvement with some noise
        trend = i * 0.05  # Improve over time (further back = worse)
        noise = random.uniform(-2, 2)
        overall = min(100, max(0, base_score - trend + noise))

        # Pillar scores with realistic variance
        pillar1 = round(min(100, max(0, overall + random.uniform(-5, 5))), 1)
        pillar2 = round(min(100, max(0, overall + random.uniform(-5, 5))), 1)
        pillar3 = round(min(100, max(0, overall + random.uniform(-5, 5))), 1)
        pillar4 = round(min(100, max(0, overall + random.uniform(-5, 5))), 1)

        # Zone scores - Zone 3 consistently 5-10 points lower (higher risk)
        zone1 = round(min(100, max(0, overall + random.uniform(-3, 3))), 1)
        zone2 = round(min(100, max(0, overall + random.uniform(-3, 3))), 1)
        zone3 = round(min(100, max(0, overall + random.uniform(-10, -5))), 1)

        # Calculate counts based on score (62 total control-zone pairs counted)
        # Score formula: (compliant*100 + partial*50 + noncompliant*0) / total
        # Work backwards from overall score
        compliant_count = int(62 * overall / 100)
        remaining = 62 - compliant_count
        noncompliant_count = random.randint(max(1, int(remaining * 0.2)), max(2, int(remaining * 0.4)))
        partial_count = max(0, 62 - compliant_count - noncompliant_count)

        score = {
            "fsi_scoredate": date.strftime("%Y-%m-%d"),
            "fsi_overallscore": round(overall, 1),
            "fsi_pillar1score": pillar1,
            "fsi_pillar2score": pillar2,
            "fsi_pillar3score": pillar3,
            "fsi_pillar4score": pillar4,
            "fsi_zone1score": zone1,
            "fsi_zone2score": zone2,
            "fsi_zone3score": zone3,
            "fsi_compliantcount": compliant_count,
            "fsi_partialcount": partial_count,
            "fsi_noncompliantcount": noncompliant_count,
            "fsi_exceptioncount": random.randint(8, 15)
        }
        scores.append(score)

    return scores


def generate_sample_exceptions() -> list:
    """Generate sample compliance exceptions with varied SLA statuses."""
    random.seed(42)  # Reproducible data
    severities = [1, 2, 2, 3, 3, 3, 4, 4]
    statuses = [1, 1, 2, 2, 3]

    exception_templates = [
        {"name": "MFA not enforced for Zone 3 agents", "control": "1.11", "severity": 1, "root_cause": "Conditional Access policy misconfigured", "remediation": "Update CA policy to enforce phishing-resistant MFA"},
        {"name": "Incomplete supervision documentation", "control": "2.12", "severity": 2, "root_cause": "Workflow automation failure", "remediation": "Restore FINRA supervision queue and document 30-day backlog"},
        {"name": "Missing retention policy configuration", "control": "1.9", "severity": 2, "root_cause": "New environment provisioned without retention labels", "remediation": "Apply 7-year retention policy to agent conversation logs"},
        {"name": "DLP policy bypass detected", "control": "1.5", "severity": 1, "root_cause": "Custom connector not scoped by DLP rules", "remediation": "Update DLP policy to include Power Platform connectors"},
        {"name": "Segregation of duties violation", "control": "2.8", "severity": 2, "root_cause": "User holds both Maker and Approver roles", "remediation": "Remove Approver role from identified users"},
        {"name": "Outdated RAG knowledge source", "control": "2.16", "severity": 3, "root_cause": "SharePoint site content not refreshed in 90 days", "remediation": "Implement automated content validation and update cycle"},
        {"name": "Agent accessing unauthorized connector", "control": "1.4", "severity": 1, "root_cause": "Connector policy not applied to new environment", "remediation": "Block premium connectors via tenant-level DLP"},
        {"name": "Missing bias testing documentation", "control": "2.11", "severity": 3, "root_cause": "Testing framework not deployed for Zone 3 agent", "remediation": "Complete bias testing using FSI-AgentGov testing framework"},
        {"name": "Endpoint DLP not configured", "control": "1.17", "severity": 2, "root_cause": "Intune policy excluded Zone 3 devices", "remediation": "Extend Endpoint DLP policy to all Zone 3 user devices"},
        {"name": "Information barriers not enforced", "control": "1.22", "severity": 1, "root_cause": "IB policy deleted during migration", "remediation": "Recreate IB policies for Investment Banking and Research departments"},
        {"name": "Agent change not documented", "control": "2.3", "severity": 3, "root_cause": "Maker published agent without change ticket", "remediation": "Enforce change approval workflow via Managed Environment gates"},
        {"name": "External sharing policy violation", "control": "4.5", "severity": 2, "root_cause": "SharePoint site used for RAG allows external users", "remediation": "Remove external users and disable external sharing"},
        {"name": "Adversarial input logging disabled", "control": "1.21", "severity": 3, "root_cause": "Application Insights not configured for agent", "remediation": "Enable App Insights and configure custom event tracking"},
    ]

    exceptions = []

    # Generate 10-13 exceptions with target distribution (limited by template count)
    num_exceptions = min(random.randint(10, 15), len(exception_templates))
    selected_templates = random.sample(exception_templates, num_exceptions)

    for i, template in enumerate(selected_templates):
        severity = template.get("severity", random.choice(severities))
        sla_days = {1: 7, 2: 14, 3: 30, 4: 90}[severity]

        # Target distribution: 40% On Track, 35% At Risk, 25% Breached
        rand_val = random.random()
        if rand_val < 0.40:
            # On Track - less than 80% of SLA
            days_open = random.randint(1, int(sla_days * 0.7))
            sla_status = 1
        elif rand_val < 0.75:
            # At Risk - 80-100% of SLA
            days_open = random.randint(int(sla_days * 0.8), sla_days)
            sla_status = 2
        else:
            # Breached - over SLA
            days_open = random.randint(sla_days + 1, sla_days + 10)
            sla_status = 3

        exception = {
            "fsi_name": template["name"],
            "fsi_controlid": template["control"],
            "fsi_severity": severity,
            "fsi_exceptionstatus": random.choice(statuses),
            "fsi_description": f"Sample exception for {template['control']}: {template['name']}",
            "fsi_targetdate": (datetime.now() + timedelta(days=sla_days - days_open)).strftime("%Y-%m-%d"),
            "fsi_daysopen": days_open,
            "fsi_slastatus": sla_status,
            "fsi_rootcause": template["root_cause"],
            "fsi_remediationplan": template["remediation"]
        }
        exceptions.append(exception)

    return exceptions


def export_sample_data(controls: list, output_dir: Path) -> dict:
    """Export generated sample data to JSON files."""
    output_dir.mkdir(exist_ok=True)

    # Generate all sample data
    assessments = generate_sample_assessments(controls)
    scores = generate_sample_scores()
    exceptions = generate_sample_exceptions()

    # Add generation metadata
    metadata = {
        "generated_at": datetime.now().isoformat(),
        "generator": "load_sample_data.py",
        "seed": 42
    }

    # Write to JSON files with readable formatting
    assessments_file = output_dir / "sample-assessments.json"
    with open(assessments_file, 'w') as f:
        json.dump({"metadata": metadata, "assessments": assessments}, f, indent=2)

    scores_file = output_dir / "sample-scores.json"
    with open(scores_file, 'w') as f:
        json.dump({"metadata": metadata, "scores": scores}, f, indent=2)

    exceptions_file = output_dir / "sample-exceptions.json"
    with open(exceptions_file, 'w') as f:
        json.dump({"metadata": metadata, "exceptions": exceptions}, f, indent=2)

    return {
        "assessments": len(assessments),
        "scores": len(scores),
        "exceptions": len(exceptions),
        "files": [str(assessments_file), str(scores_file), str(exceptions_file)]
    }


def main():
    parser = argparse.ArgumentParser(description="Load sample data for Compliance Dashboard")
    parser.add_argument("--environment", help="Dataverse environment URL")
    parser.add_argument("--controls-only", action="store_true", help="Load only control master data")
    parser.add_argument("--assessments-only", action="store_true", help="Load only assessment data")
    parser.add_argument("--force", action="store_true", help="Overwrite existing data")
    parser.add_argument("--dry-run", action="store_true", help="Print data without loading")
    parser.add_argument("--export", action="store_true", help="Export sample data to JSON files")

    args = parser.parse_args()

    print("Compliance Dashboard - Sample Data Loader")
    print("=" * 50)

    # Load control master for reference
    script_dir = Path(__file__).parent.parent
    json_path = script_dir / "sample-data" / "control-master.json"

    with open(json_path, 'r') as f:
        controls = json.load(f)

    print(f"Loaded {len(controls)} control definitions")

    # Handle export mode
    if args.export:
        print("\n[EXPORT MODE - Generating sample data files]")
        output_dir = script_dir / "sample-data"
        result = export_sample_data(controls, output_dir)

        print(f"\nExported sample data:")
        print(f"  Assessments: {result['assessments']} records")
        print(f"  Daily Scores: {result['scores']} records")
        print(f"  Exceptions: {result['exceptions']} records")
        print(f"\nFiles created:")
        for file_path in result['files']:
            print(f"  {file_path}")
        return

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
        print("Use --dry-run to preview data without loading or --export to generate JSON files")
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
    try:
        token = get_access_token(tenant_id, client_id, client_secret, environment_url=args.environment)
        print("Authentication successful")
    except Exception as e:
        print(f"\nError: Authentication failed: {e}", file=sys.stderr)
        sys.exit(1)

    if not args.assessments_only:
        print("\nLoading control master data...")
        result = load_control_master(args.environment, token, args.force)
        print(f"  Loaded: {result['loaded']} records")

    if not args.controls_only:
        print("\nNote: Assessment, score, and exception upload to Dataverse is not yet implemented.")
        print("Use --export to generate JSON files, then import via Power Apps or Dataverse API.")
        print("Use --dry-run to preview generated data locally.")

    print("\nSample data loading complete!")


if __name__ == "__main__":
    main()
