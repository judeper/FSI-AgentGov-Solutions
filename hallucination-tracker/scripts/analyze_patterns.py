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
from urllib.parse import urlparse

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

SEVERITY_WEIGHTS = {
    100000003: 4,  # critical
    100000002: 3,  # high
    100000001: 2,  # medium
    100000000: 1,  # low
}

SEVERITY_LABELS = {
    100000003: "critical",
    100000002: "high",
    100000001: "medium",
    100000000: "low",
}

SOURCES = {
    100000000: "user",
    100000001: "supervisor",
    100000002: "automated",
    100000003: "customer",
}

SEVERITY_LABEL_ORDER = {"critical": 4, "high": 3, "medium": 2, "low": 1, "unknown": 0}


class PatternAnalyzer:
    """Analyzes hallucination patterns from feedback data."""

    def __init__(self, environment: str, tenant_id: str, client_id: str, client_secret: str):
        self.environment = environment.rstrip("/")
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

    def get_feedback(self, days: int = 30) -> Tuple[List[Dict], bool]:
        """Retrieve hallucination feedback from Dataverse.

        Returns:
            A tuple of (records, is_complete) where is_complete indicates
            whether all pages were successfully retrieved.
        """
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0"
        }

        start_date = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT00:00:00Z")
        url = f"{self.environment}/api/data/v9.2/fsi_hallucinationreports?$select=fsi_category,fsi_severity,fsi_agentid,fsi_source&$filter=createdon ge {start_date}"

        results = []
        is_complete = False
        max_retries = 5
        retry_count = 0
        try:
            while url:
                response = requests.get(url, headers=headers, timeout=30)
                if response.status_code == 429:
                    retry_count += 1
                    if retry_count >= max_retries:
                        print("Error: Max retries exceeded for rate limiting.")
                        break
                    raw = response.headers.get("Retry-After", "60")
                    try:
                        retry_after = int(raw)
                    except ValueError:
                        retry_after = 60
                    print(f"Warning: Rate limited. Retrying after {retry_after}s (attempt {retry_count}/{max_retries})...")
                    time.sleep(retry_after)
                    continue
                if response.status_code != 200:
                    print(f"Warning: API returned status {response.status_code}: {response.text[:200]}")
                    break
                data = response.json()
                results.extend(data.get("value", []))
                url = data.get("@odata.nextLink")
                retry_count = 0
            else:
                is_complete = True
            return results, is_complete
        except requests.RequestException as e:
            print(f"Warning: Could not fetch feedback: {e}")

        return results, is_complete

    def analyze_by_category(self, feedback: List[Dict]) -> Dict:
        """Analyze feedback distribution by category."""
        categories = Counter()
        for item in feedback:
            cat = item.get("fsi_category") or 0
            categories[CATEGORIES.get(cat, "unknown")] += 1
        return dict(categories)

    def analyze_by_agent(self, feedback: List[Dict]) -> Dict:
        """Analyze feedback distribution by agent."""
        agents = Counter()
        for item in feedback:
            agent_id = item.get("fsi_agentid") or "unknown"
            agents[agent_id] += 1
        return dict(agents)

    def analyze_severity(self, feedback: List[Dict]) -> Dict:
        """Analyze severity distribution."""
        severity = Counter()
        for item in feedback:
            sev = item.get("fsi_severity")
            severity[SEVERITY_LABELS.get(sev, "unknown")] += 1
        return dict(severity)

    def calculate_agent_scores(self, feedback: List[Dict]) -> Dict:
        """Calculate accuracy scores per agent using weighted penalty rate.

        Score = 100 - min((weighted_issues / total_reports) * 25, 100).
        The average severity weight (1-4) is scaled by 25 to produce a
        penalty range of 25-100, giving meaningful score differentiation.
        """
        agent_data = {}

        for item in feedback:
            agent_id = item.get("fsi_agentid") or "unknown"
            severity = item.get("fsi_severity")

            if agent_id not in agent_data:
                agent_data[agent_id] = {"total": 0, "weighted_issues": 0}

            agent_data[agent_id]["total"] += 1
            agent_data[agent_id]["weighted_issues"] += SEVERITY_WEIGHTS.get(severity, 1)

        # Calculate scores as rate-based penalty (normalized by report count)
        scores = {}
        for agent_id, data in agent_data.items():
            total = data["total"]
            if total == 0:
                scores[agent_id] = 100
            else:
                penalty = min((data["weighted_issues"] / total) * 25, 100)
                scores[agent_id] = max(0, round(100 - penalty))

        return scores

    def analyze_by_source(self, feedback: List[Dict]) -> Dict:
        """Analyze feedback distribution by source type."""
        sources = Counter()
        for item in feedback:
            src = item.get("fsi_source")
            sources[SOURCES.get(src, "unknown")] += 1
        return dict(sources)

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
        source_analysis = self.analyze_by_source(feedback)
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
            report += """
*** WARNING: PARTIAL DATA ***
Not all pages were retrieved. Counts, percentages,
and agent scores below may be understated.
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

        report += "\nSource Distribution:\n"
        for src, count in sorted(source_analysis.items(), key=lambda x: -x[1]):
            pct = (count / total * 100) if total > 0 else 0
            report += f"  {src}: {count} ({pct:.1f}%)\n"

        report += "\nSeverity Distribution:\n"
        for sev, count in sorted(severity_analysis.items(), key=lambda x: -SEVERITY_LABEL_ORDER.get(x[0], 0)):
            pct = (count / total * 100) if total > 0 else 0
            report += f"  {sev}: {count} ({pct:.1f}%)\n"

        report += "\nAgent Scores:\n"
        for agent_id, score in sorted(agent_scores.items(), key=lambda x: x[1]):
            rating = "Excellent" if score >= 95 else "Good" if score >= 85 else "Needs Improvement" if score >= 70 else "Critical"
            display = f"{agent_id[:20]}..." if len(agent_id) > 20 else agent_id
            report += f"  {display}: {score} ({rating})\n"

        if patterns:
            report += "\nDetected Patterns:\n"
            for pattern in patterns:
                report += f"  - {pattern['type']}: {pattern['recommendation']}\n"

        return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Hallucination Pattern Analyzer")
    parser.add_argument("--environment", required=True, help="Dataverse environment URL")
    parser.add_argument("--days", type=int, default=30, help="Analysis period in days")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show detailed output")
    parser.add_argument("--format", choices=["text", "json"], default="text", help="Output format (default: text)")
    parser.add_argument("--dry-run", action="store_true", help="Use sample data")

    args = parser.parse_args()

    if args.days < 1:
        print("Error: --days must be a positive integer")
        sys.exit(1)

    # Validate environment URL format
    parsed = urlparse(args.environment)
    if parsed.scheme not in ("https",) or not parsed.netloc:
        print("Error: --environment must be an HTTPS URL (e.g., https://your-org.crm.dynamics.com)")
        sys.exit(1)

    # Defense-in-depth: restrict to known Dataverse domains
    allowed_suffixes = (".crm.dynamics.com", ".crm2.dynamics.com", ".crm3.dynamics.com",
                        ".crm4.dynamics.com", ".crm5.dynamics.com", ".crm6.dynamics.com",
                        ".crm7.dynamics.com", ".crm8.dynamics.com", ".crm9.dynamics.com",
                        ".crm11.dynamics.com", ".crm12.dynamics.com", ".crm14.dynamics.com",
                        ".crm15.dynamics.com", ".crm17.dynamics.com", ".crm19.dynamics.com",
                        ".crm20.dynamics.com", ".crm21.dynamics.com",
                        ".crm.microsoftdynamics.us", ".crm.appsplatform.us")
    if not any(parsed.netloc.endswith(suffix) for suffix in allowed_suffixes):
        print(f"Error: --environment host must be a Dataverse domain (*.crm[N].dynamics.com or *.microsoftdynamics.us or *.appsplatform.us)")
        print(f"  Got: {parsed.netloc}")
        sys.exit(1)

    if not args.dry_run:
        missing = [v for v in ("AZURE_TENANT_ID", "AZURE_CLIENT_ID", "AZURE_CLIENT_SECRET")
                   if not os.environ.get(v)]
        if missing:
            print(f"Error: Missing required environment variables: {', '.join(missing)}")
            sys.exit(1)

    is_json = args.format == "json"
    def status_print(*a, **kw):
        if is_json:
            kw["file"] = sys.stderr
        print(*a, **kw)

    status_print("========================================")
    status_print("  Hallucination Pattern Analyzer")
    status_print("========================================")

    analyzer = PatternAnalyzer(
        args.environment,
        os.environ.get("AZURE_TENANT_ID"),
        os.environ.get("AZURE_CLIENT_ID"),
        os.environ.get("AZURE_CLIENT_SECRET")
    )

    if args.dry_run:
        status_print("\n[DRY RUN - Using sample data]")
        # Sample data for testing
        feedback = [
            {"fsi_category": 100000000, "fsi_severity": 100000002, "fsi_agentid": "agent-001", "fsi_source": 100000000},
            {"fsi_category": 100000000, "fsi_severity": 100000001, "fsi_agentid": "agent-001", "fsi_source": 100000001},
            {"fsi_category": 100000002, "fsi_severity": 100000002, "fsi_agentid": "agent-002", "fsi_source": 100000002},
            {"fsi_category": 100000001, "fsi_severity": 100000003, "fsi_agentid": "agent-001", "fsi_source": 100000001},
            {"fsi_category": 100000000, "fsi_severity": 100000000, "fsi_agentid": "agent-003", "fsi_source": 100000003},
        ]
        is_complete = True
    else:
        status_print("\nAuthenticating...")
        analyzer.authenticate()
        status_print("  Authenticated")
        status_print("\nFetching feedback data...")
        feedback, is_complete = analyzer.get_feedback(args.days)
        status_print(f"  Retrieved {len(feedback)} reports")

    if args.format == "json":
        output = {
            "report_date": datetime.now(timezone.utc).isoformat(),
            "analysis_period_days": args.days,
            "is_complete": is_complete,
            "total_reports": len(feedback),
            "critical_issues": sum(1 for f in feedback if f.get("fsi_severity") == 100000003),
            "category_distribution": analyzer.analyze_by_category(feedback),
            "severity_distribution": analyzer.analyze_severity(feedback),
            "agent_scores": analyzer.calculate_agent_scores(feedback),
            "source_distribution": analyzer.analyze_by_source(feedback),
            "patterns": analyzer.detect_patterns(feedback),
        }
        print(json.dumps(output, indent=2))
    else:
        report = analyzer.generate_report(feedback, days=args.days, is_complete=is_complete)
        print(report)

    if args.verbose:
        status_print("\nVerbose Details:")
        for item in feedback:
            cat = CATEGORIES.get(item.get("fsi_category", 0), "unknown")
            sev = SEVERITY_LABELS.get(item.get("fsi_severity"), "unknown")
            src = SOURCES.get(item.get("fsi_source"), "unknown")
            agent = item.get("fsi_agentid", "unknown")
            status_print(f"  Agent: {agent}, Category: {cat}, Severity: {sev}, Source: {src}")

    if not is_complete:
        sys.exit(2)


if __name__ == "__main__":
    main()
