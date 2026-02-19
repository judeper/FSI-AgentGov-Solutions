#!/usr/bin/env python3
"""
Hallucination Pattern Analyzer

Analyzes collected feedback to identify hallucination patterns and trends.

Usage:
    python analyze_patterns.py --environment "https://your-org.crm.dynamics.com"
"""

import argparse
import json
import os
import sys
import time
from collections import Counter
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Tuple

try:
    from msal import ConfidentialClientApplication
    import requests
except ImportError:
    print("Error: Required packages not installed.")
    print("Run: pip install msal requests")
    sys.exit(1)


# Hallucination categories (Dataverse option set values)
CATEGORIES = {
    100000000: "factual_error",
    100000001: "fabricated_data",
    100000002: "citation_missing",
    100000003: "outdated_info",
    100000004: "confidence_overstatement"
}

SEVERITIES = {
    100000000: "Low",
    100000001: "Medium",
    100000002: "High",
    100000003: "Critical",
}

SEVERITY_WEIGHTS = {
    100000003: 4,  # critical
    100000002: 3,  # high
    100000001: 2,  # medium
    100000000: 1,  # low
}


class PatternAnalyzer:
    """Analyzes hallucination patterns from feedback data."""

    # Buffer in seconds before actual token expiry to trigger re-auth
    _TOKEN_EXPIRY_BUFFER = 60

    def __init__(self, environment: str, tenant_id: str, client_id: str, client_secret: str):
        self.environment = environment.rstrip("/")
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.token = None
        self._token_expiry: float = 0

    def authenticate(self):
        """Acquire access token and track expiry."""
        app = ConfidentialClientApplication(
            self.client_id,
            authority=f"https://login.microsoftonline.com/{self.tenant_id}",
            client_credential=self.client_secret
        )
        result = app.acquire_token_for_client(scopes=[f"{self.environment}/.default"])
        if "access_token" not in result:
            raise Exception(f"Authentication failed: {result.get('error_description')}")
        self.token = result["access_token"]
        expires_in = result.get("expires_in", 3600)
        self._token_expiry = time.monotonic() + int(expires_in)

    def _ensure_valid_token(self):
        """Re-authenticate if the token is near expiry."""
        if time.monotonic() >= self._token_expiry - self._TOKEN_EXPIRY_BUFFER:
            self.authenticate()

    def get_feedback(self, days: int = 30) -> Tuple[List[Dict], bool]:
        """Retrieve hallucination feedback from Dataverse.

        Returns:
            Tuple of (results list, is_complete flag). is_complete is False
            when pagination failed and data may be truncated.
        """
        max_retries = 3

        start_date = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT00:00:00Z")
        url = f"{self.environment}/api/data/v9.2/fsi_hallucinationreports?$filter=createdon ge {start_date}"

        try:
            results = []
            is_complete = True
            while url:
                self._ensure_valid_token()
                headers = {
                    "Authorization": f"Bearer {self.token}",
                    "Content-Type": "application/json",
                    "OData-MaxVersion": "4.0",
                    "OData-Version": "4.0"
                }

                response = None
                for attempt in range(max_retries):
                    response = requests.get(url, headers=headers)
                    if response.status_code == 429 or response.status_code >= 500:
                        raw_retry = response.headers.get("Retry-After")
                        try:
                            retry_after = int(raw_retry) if raw_retry else 2 ** attempt
                        except ValueError:
                            retry_after = 2 ** attempt
                        print(f"  Retrying after {retry_after}s (HTTP {response.status_code}, attempt {attempt + 1}/{max_retries})")
                        time.sleep(retry_after)
                    else:
                        break

                if response.status_code != 200:
                    print(f"Error: API returned {response.status_code}: {response.text[:200]}")
                    is_complete = False
                    break
                data = response.json()
                results.extend(data.get("value", []))
                url = data.get("@odata.nextLink")
            return results, is_complete
        except (requests.RequestException, json.JSONDecodeError) as e:
            sys.exit(f"Error: Failed to retrieve feedback data: {type(e).__name__}: {e}")
        except Exception as e:
            sys.exit(f"Error: Authentication failed during pagination: {e}")

    def analyze_by_category(self, feedback: List[Dict]) -> Dict:
        """Analyze feedback distribution by category."""
        categories = Counter()
        for item in feedback:
            cat = item.get("fsi_category", 0)
            categories[CATEGORIES.get(cat, "unknown")] += 1
        return dict(categories)

    def analyze_by_agent(self, feedback: List[Dict]) -> Dict:
        """Analyze feedback distribution by agent."""
        agents = Counter()
        for item in feedback:
            agent_id = item.get("fsi_agentid", "unknown")
            agents[agent_id] += 1
        return dict(agents)

    def analyze_severity(self, feedback: List[Dict]) -> Dict:
        """Analyze severity distribution."""
        severity = Counter()
        for item in feedback:
            sev = item.get("fsi_severity", 100000000)
            severity[sev] += 1
        return dict(severity)

    def calculate_agent_scores(self, feedback: List[Dict]) -> Dict:
        """Calculate accuracy scores per agent.

        Note: Scores are based solely on hallucination report count and severity.
        Without total interaction volume data (not currently available from
        Dataverse), scores are not normalized by usage — a high-volume agent
        with few issues may score the same as a low-volume agent with the same
        number of issues. TODO: Normalize by total agent interactions once
        interaction telemetry is available.
        """
        agent_data = {}

        for item in feedback:
            agent_id = item.get("fsi_agentid", "unknown")
            severity = item.get("fsi_severity", 100000000)

            if agent_id not in agent_data:
                agent_data[agent_id] = {"total": 0, "weighted_issues": 0}

            agent_data[agent_id]["total"] += 1
            agent_data[agent_id]["weighted_issues"] += SEVERITY_WEIGHTS.get(severity, 1)

        # Calculate scores (100 - penalty)
        scores = {}
        for agent_id, data in agent_data.items():
            penalty = min(data["weighted_issues"] * 2, 100)  # Cap at 100
            scores[agent_id] = max(0, 100 - penalty)

        return scores

    def detect_patterns(self, feedback: List[Dict]) -> List[Dict]:
        """Detect recurring patterns in feedback."""
        patterns = []

        # Group by category and count
        category_counts = self.analyze_by_category(feedback)
        for category, count in category_counts.items():
            if count >= 3:  # Threshold for pattern
                patterns.append({
                    "type": "category_cluster",
                    "category": category,
                    "count": count,
                    "recommendation": f"Investigate {category} issues"
                })

        # Group by agent
        agent_counts = self.analyze_by_agent(feedback)
        for agent_id, count in agent_counts.items():
            if count >= 5:  # Threshold for agent-specific pattern
                patterns.append({
                    "type": "agent_cluster",
                    "agent_id": agent_id,
                    "count": count,
                    "recommendation": f"Review agent {agent_id} configuration"
                })

        return patterns

    def generate_report(self, feedback: List[Dict], days: int = 30, is_complete: bool = True) -> str:
        """Generate analysis report."""
        category_analysis = self.analyze_by_category(feedback)
        severity_analysis = self.analyze_severity(feedback)
        agent_scores = self.calculate_agent_scores(feedback)
        patterns = self.detect_patterns(feedback)

        total = len(feedback)
        critical = sum(1 for f in feedback if f.get("fsi_severity") == 100000003)

        report = f"""
========================================
  Hallucination Pattern Analysis Report
========================================
"""
        if not is_complete:
            report += f"""
⚠ DATA INCOMPLETE — pagination failed after {total} records.
  Percentages and patterns below may not reflect the full dataset.
"""

        report += f"""
Report Date: {datetime.now(timezone.utc).isoformat()}
Analysis Period: Last {days} days

Summary:
  Total Reports: {total}
  Critical Issues: {critical}

Category Distribution:
"""
        for cat, count in sorted(category_analysis.items(), key=lambda x: -x[1]):
            pct = (count / total * 100) if total > 0 else 0
            report += f"  {cat}: {count} ({pct:.1f}%)\n"

        report += "\nSeverity Distribution:\n"
        for sev, count in sorted(severity_analysis.items(), key=lambda x: -SEVERITY_WEIGHTS.get(x[0], 0)):
            pct = (count / total * 100) if total > 0 else 0
            report += f"  {SEVERITIES.get(sev, f'unknown({sev})')}: {count} ({pct:.1f}%)\n"

        report += "\nAgent Scores:\n"
        for agent_id, score in sorted(agent_scores.items(), key=lambda x: x[1]):
            rating = "Excellent" if score >= 95 else "Good" if score >= 85 else "Needs Improvement" if score >= 70 else "Critical"
            report += f"  {agent_id[:8]}{'...' if len(agent_id) > 8 else ''}: {score} ({rating})\n"

        if patterns:
            report += "\nDetected Patterns:\n"
            for pattern in patterns:
                report += f"  - {pattern['type']}: {pattern['recommendation']}\n"

        return report


def main():
    parser = argparse.ArgumentParser(description="Hallucination Pattern Analyzer")
    parser.add_argument("--environment", required=True, help="Dataverse environment URL")
    parser.add_argument("--days", type=int, default=30, help="Analysis period in days")
    parser.add_argument("--verbose", "-v", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="Use sample data")

    args = parser.parse_args()

    if args.days < 1:
        sys.exit("Error: --days must be a positive integer")

    if not args.environment.startswith("https://"):
        sys.exit("Error: --environment must be a valid HTTPS URL (e.g., https://your-org.crm.dynamics.com)")

    print("========================================")
    print("  Hallucination Pattern Analyzer")
    print("========================================")

    if not args.dry_run:
        tenant_id = os.environ.get("AZURE_TENANT_ID")
        client_id = os.environ.get("AZURE_CLIENT_ID")
        client_secret = os.environ.get("AZURE_CLIENT_SECRET")
        if not all([tenant_id, client_id, client_secret]):
            sys.exit("Error: AZURE_TENANT_ID, AZURE_CLIENT_ID, and AZURE_CLIENT_SECRET environment variables are required")
    else:
        tenant_id = None
        client_id = None
        client_secret = None

    analyzer = PatternAnalyzer(
        args.environment,
        tenant_id,
        client_id,
        client_secret
    )

    if args.dry_run:
        print("\n[DRY RUN - Using sample data]")
        # Sample data for testing
        feedback = [
            {"fsi_category": 100000000, "fsi_severity": 100000002, "fsi_agentid": "agent-001"},
            {"fsi_category": 100000000, "fsi_severity": 100000001, "fsi_agentid": "agent-001"},
            {"fsi_category": 100000002, "fsi_severity": 100000002, "fsi_agentid": "agent-002"},
            {"fsi_category": 100000001, "fsi_severity": 100000003, "fsi_agentid": "agent-001"},
            {"fsi_category": 100000000, "fsi_severity": 100000000, "fsi_agentid": "agent-003"},
        ]
        is_complete = True
    else:
        print("\nAuthenticating...")
        try:
            analyzer.authenticate()
        except Exception as e:
            sys.exit(f"Error: Authentication failed: {e}")
        print("  Authenticated")
        print("\nFetching feedback data...")
        feedback, is_complete = analyzer.get_feedback(args.days)
        print(f"  Retrieved {len(feedback)} reports")

    report = analyzer.generate_report(feedback, args.days, is_complete)
    print(report)


if __name__ == "__main__":
    main()
