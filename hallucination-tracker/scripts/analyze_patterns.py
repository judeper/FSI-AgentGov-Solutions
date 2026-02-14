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
from collections import Counter
from datetime import datetime, timedelta
from typing import Dict, List

try:
    from msal import ConfidentialClientApplication
    import requests
except ImportError:
    print("Error: Required packages not installed.")
    print("Run: pip install msal requests")
    sys.exit(1)


# Hallucination categories
CATEGORIES = {
    1: "factual_error",
    2: "fabricated_data",
    3: "citation_missing",
    4: "outdated_info",
    5: "confidence_overstatement"
}

SEVERITY_WEIGHTS = {
    100000003: 4,  # critical
    100000002: 3,  # high
    100000001: 2,  # medium
    100000000: 1,  # low
}


class PatternAnalyzer:
    """Analyzes hallucination patterns from feedback data."""

    def __init__(self, environment: str, tenant_id: str, client_id: str, client_secret: str):
        self.environment = environment
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.token = None

    def authenticate(self):
        """Acquire access token."""
        app = ConfidentialClientApplication(
            self.client_id,
            authority=f"https://login.microsoftonline.com/{self.tenant_id}",
            client_credential=self.client_secret
        )
        result = app.acquire_token_for_client(scopes=[f"{self.environment}/.default"])
        if "access_token" not in result:
            raise Exception(f"Authentication failed: {result.get('error_description')}")
        self.token = result["access_token"]

    def get_feedback(self, days: int = 30) -> List[Dict]:
        """Retrieve hallucination feedback from Dataverse."""
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0"
        }

        start_date = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%dT00:00:00Z")
        url = f"{self.environment}/api/data/v9.2/fsi_hallucinationreports?$filter=createdon ge {start_date}"

        try:
            results = []
            while url:
                response = requests.get(url, headers=headers)
                if response.status_code != 200:
                    break
                data = response.json()
                results.extend(data.get("value", []))
                url = data.get("@odata.nextLink")
            return results
        except Exception as e:
            print(f"Warning: Could not fetch feedback: {e}")

        return []

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
            sev = item.get("fsi_severity", "unknown")
            severity[sev] += 1
        return dict(severity)

    def calculate_agent_scores(self, feedback: List[Dict]) -> Dict:
        """Calculate accuracy scores per agent."""
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

    def generate_report(self, feedback: List[Dict]) -> str:
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

Report Date: {datetime.utcnow().isoformat()}
Analysis Period: Last 30 days

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
            report += f"  {sev}: {count} ({pct:.1f}%)\n"

        report += "\nAgent Scores:\n"
        for agent_id, score in sorted(agent_scores.items(), key=lambda x: x[1]):
            rating = "Excellent" if score >= 95 else "Good" if score >= 85 else "Needs Improvement" if score >= 70 else "Critical"
            report += f"  {agent_id[:8]}...: {score} ({rating})\n"

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

    print("========================================")
    print("  Hallucination Pattern Analyzer")
    print("========================================")

    analyzer = PatternAnalyzer(
        args.environment,
        os.environ.get("AZURE_TENANT_ID"),
        os.environ.get("AZURE_CLIENT_ID"),
        os.environ.get("AZURE_CLIENT_SECRET")
    )

    if args.dry_run:
        print("\n[DRY RUN - Using sample data]")
        # Sample data for testing
        feedback = [
            {"fsi_category": 1, "fsi_severity": 100000002, "fsi_agentid": "agent-001"},
            {"fsi_category": 1, "fsi_severity": 100000001, "fsi_agentid": "agent-001"},
            {"fsi_category": 3, "fsi_severity": 100000002, "fsi_agentid": "agent-002"},
            {"fsi_category": 2, "fsi_severity": 100000003, "fsi_agentid": "agent-001"},
            {"fsi_category": 1, "fsi_severity": 100000000, "fsi_agentid": "agent-003"},
        ]
    else:
        print("\nAuthenticating...")
        analyzer.authenticate()
        print("  Authenticated")
        print("\nFetching feedback data...")
        feedback = analyzer.get_feedback(args.days)
        print(f"  Retrieved {len(feedback)} reports")

    report = analyzer.generate_report(feedback)
    print(report)


if __name__ == "__main__":
    main()
