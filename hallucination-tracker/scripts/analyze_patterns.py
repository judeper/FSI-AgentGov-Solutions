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
from typing import Dict, List, Optional, Tuple
from urllib.parse import urlparse

try:
    import requests
except ImportError:
    print("Error: Required package not installed: requests")
    print("Run: pip install -r scripts/requirements.txt")
    sys.exit(1)

try:
    from azure.identity import (
        AzureCliCredential,
        AzurePowerShellCredential,
        ChainedTokenCredential,
        ManagedIdentityCredential,
        WorkloadIdentityCredential,
    )
except ImportError:  # Optional unless using managed identity / workload identity auth.
    AzureCliCredential = None
    AzurePowerShellCredential = None
    ChainedTokenCredential = None
    ManagedIdentityCredential = None
    WorkloadIdentityCredential = None

try:
    from msal import ConfidentialClientApplication
except ImportError:  # Optional legacy fallback only.
    ConfidentialClientApplication = None


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
    100000004: "microsoft_365_copilot",
}

SEVERITY_LABEL_ORDER = {"critical": 4, "high": 3, "medium": 2, "low": 1, "unknown": 0}

FEEDBACK_SELECT_FIELDS = [
    "fsi_category",
    "fsi_severity",
    "fsi_agentid",
    "fsi_source",
    "fsi_topicname",
    "fsi_topicid",
    "fsi_channelid",
    "fsi_feedbackcomment",
    "fsi_groundednessdetected",
    "fsi_reportedat",
    "createdon",
]

LEGACY_SELECT_FIELDS = ["fsi_category", "fsi_severity", "fsi_agentid", "fsi_source"]


class PatternAnalyzer:
    """Analyzes hallucination patterns from feedback data."""

    def __init__(self, environment: str, tenant_id: str, client_id: str, client_secret: str):
        self.environment = environment.rstrip("/")
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.token = None

    def authenticate(self):
        """Acquire a Dataverse access token using managed-identity-first auth."""
        scope = f"{self.environment}/.default"
        credential_errors: list[str] = []

        if ChainedTokenCredential is not None:
            credentials = []
            if ManagedIdentityCredential:
                managed_identity_client_id = os.environ.get("AZURE_MANAGED_IDENTITY_CLIENT_ID")
                credentials.append(ManagedIdentityCredential(client_id=managed_identity_client_id))

            federated_token_file = os.environ.get("AZURE_FEDERATED_TOKEN_FILE")
            if federated_token_file and self.tenant_id and self.client_id and WorkloadIdentityCredential:
                credentials.append(
                    WorkloadIdentityCredential(
                        tenant_id=self.tenant_id,
                        client_id=self.client_id,
                        token_file_path=federated_token_file,
                    )
                )

            if AzureCliCredential:
                credentials.append(AzureCliCredential())
            if AzurePowerShellCredential:
                credentials.append(AzurePowerShellCredential())

            try:
                token = ChainedTokenCredential(*credentials).get_token(scope)
                self.token = token.token
                return
            except Exception as exc:
                credential_errors.append(str(exc))

        if self.client_secret:
            # legacy: dev-only - replace with managed identity in production
            if ConfidentialClientApplication is None:
                raise RuntimeError(
                    "msal is required for legacy client-secret authentication. "
                    "Install dependencies with: pip install -r scripts/requirements.txt"
                )
            if not self.tenant_id or not self.client_id:
                raise RuntimeError(
                    "AZURE_TENANT_ID and AZURE_CLIENT_ID are required with legacy AZURE_CLIENT_SECRET auth."
                )
            print(
                "Warning: using client-secret authentication (legacy dev-only - replace with managed identity in production).",
                file=sys.stderr,
            )
            app = ConfidentialClientApplication(
                self.client_id,
                authority=f"https://login.microsoftonline.com/{self.tenant_id}",
                client_credential=self.client_secret,
            )
            result = app.acquire_token_for_client(scopes=[scope])
            if "access_token" not in result:
                raise RuntimeError(f"Authentication failed: {result.get('error_description')}")
            self.token = result["access_token"]
            return

        guidance = (
            "Authentication failed. Configure a managed identity, workload identity federation, "
            "Azure CLI/PowerShell sign-in for workstation runs, or legacy dev-only "
            "AZURE_CLIENT_SECRET credentials."
        )
        if credential_errors:
            guidance += f" Last credential error: {credential_errors[-1]}"
        raise RuntimeError(guidance)

    def _feedback_url(self, days: int, select_fields: List[str]) -> str:
        """Build the Dataverse hallucination report query URL."""
        start_date = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT00:00:00Z")
        select = ",".join(select_fields)
        return f"{self.environment}/api/data/v9.2/fsi_hallucinationreports?$select={select}&$filter=createdon ge {start_date}"

    def _fetch_feedback_pages(self, url: str, headers: Dict[str, str]) -> Tuple[List[Dict], bool, Optional[int], str]:
        """Fetch Dataverse pages for a prepared query URL."""
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
                    return results, False, response.status_code, response.text[:500]
                data = response.json()
                results.extend(data.get("value", []))
                url = data.get("@odata.nextLink")
                retry_count = 0
            else:
                is_complete = True
            return results, is_complete, None, ""
        except requests.RequestException as e:
            return results, is_complete, None, str(e)

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
            "OData-Version": "4.0",
        }

        for select_fields in (FEEDBACK_SELECT_FIELDS, LEGACY_SELECT_FIELDS):
            url = self._feedback_url(days, select_fields)
            results, is_complete, status_code, error_text = self._fetch_feedback_pages(url, headers)
            if status_code is None and (is_complete or results):
                return results, is_complete
            if select_fields is FEEDBACK_SELECT_FIELDS and status_code == 400:
                print(
                    "Warning: enriched feedback columns are unavailable; falling back to legacy v1.1.0 columns. "
                    "Redeploy the v1.2.0 Dataverse schema to enable topic/channel/time clustering."
                )
                continue
            if error_text:
                print(f"Warning: API returned status {status_code}: {error_text[:200]}")
            return results, is_complete

        return [], False

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
        """Calculate per-agent risk scores using weighted severity penalty.

        IMPORTANT: This is NOT an accuracy metric - the denominator is the
        agent's *hallucination report count*, not the agent's total response
        count. The score expresses the *severity profile of reported issues*
        for an agent, not the actual hallucination rate. To compute true
        accuracy or hallucination-rate, callers must join against the agent's
        total response volume (out of scope for this aggregation).

        Calibration (with a single report):
            1 Low      → 75 ("Needs Improvement")
            1 Medium   → 50 ("Critical")
            1 High     → 25 ("Critical")
            1 Critical → 0  ("Critical")

        Because a single low-volume report can dominate the score, agents
        with fewer than MIN_REPORTS_FOR_SCORE reports are returned as
        ``None`` so callers can render them as "InsufficientData".

        Returns:
            Dict mapping agent_id to either an integer 0-100 or ``None``
            when the agent has too few reports to score reliably.
        """
        MIN_REPORTS_FOR_SCORE = 3

        agent_data = {}
        for item in feedback:
            agent_id = item.get("fsi_agentid") or "unknown"
            severity = item.get("fsi_severity")
            if agent_id not in agent_data:
                agent_data[agent_id] = {"total": 0, "weighted_issues": 0}
            agent_data[agent_id]["total"] += 1
            agent_data[agent_id]["weighted_issues"] += SEVERITY_WEIGHTS.get(severity, 1)

        scores = {}
        for agent_id, data in agent_data.items():
            total = data["total"]
            if total < MIN_REPORTS_FOR_SCORE:
                scores[agent_id] = None
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

    def analyze_by_topic(self, feedback: List[Dict]) -> Dict:
        """Analyze feedback distribution by topic where the source provides topic metadata."""
        topics = Counter()
        for item in feedback:
            topic = item.get("fsi_topicname") or item.get("fsi_topicid")
            if topic:
                topics[str(topic)] += 1
        return dict(topics)

    def analyze_by_channel(self, feedback: List[Dict]) -> Dict:
        """Analyze feedback distribution by channel where channel metadata is available."""
        channels = Counter()
        for item in feedback:
            channel = item.get("fsi_channelid")
            if channel:
                channels[str(channel)] += 1
        return dict(channels)

    def analyze_by_day(self, feedback: List[Dict]) -> Dict:
        """Analyze feedback distribution by reported/created UTC day."""
        days = Counter()
        for item in feedback:
            timestamp = item.get("fsi_reportedat") or item.get("createdon")
            if not timestamp:
                continue
            day = str(timestamp)[:10]
            if len(day) == 10:
                days[day] += 1
        return dict(days)

    def detect_patterns(self, feedback: List[Dict]) -> List[Dict]:
        """Detect recurring category, agent, topic, and time-window patterns in feedback."""
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

        # Group by topic when source data includes topic metadata.
        topic_counts = self.analyze_by_topic(feedback)
        for topic, count in topic_counts.items():
            if count >= 3:
                patterns.append({
                    "type": "topic_cluster",
                    "topic": topic,
                    "count": count,
                    "recommendation": f"Review topic {topic} knowledge sources, instructions, and citations"
                })

        # Detect simple daily spikes for operational triage.
        daily_counts = self.analyze_by_day(feedback)
        if len(daily_counts) >= 2:
            average = sum(daily_counts.values()) / len(daily_counts)
            spike_threshold = max(3, average * 2)
            for day, count in daily_counts.items():
                if count >= spike_threshold:
                    patterns.append({
                        "type": "time_spike",
                        "date": day,
                        "count": count,
                        "recommendation": f"Review releases, content updates, or incidents around {day}"
                    })

        return patterns

    def generate_report(self, feedback: List[Dict], days: int = 30, is_complete: bool = True) -> str:
        """Generate analysis report."""
        category_analysis = self.analyze_by_category(feedback)
        severity_analysis = self.analyze_severity(feedback)
        source_analysis = self.analyze_by_source(feedback)
        topic_analysis = self.analyze_by_topic(feedback)
        channel_analysis = self.analyze_by_channel(feedback)
        daily_analysis = self.analyze_by_day(feedback)
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

        if topic_analysis:
            report += "\nTopic Distribution:\n"
            for topic, count in sorted(topic_analysis.items(), key=lambda x: -x[1]):
                pct = (count / total * 100) if total > 0 else 0
                display = f"{topic[:40]}..." if len(topic) > 40 else topic
                report += f"  {display}: {count} ({pct:.1f}%)\n"

        if channel_analysis:
            report += "\nChannel Distribution:\n"
            for channel, count in sorted(channel_analysis.items(), key=lambda x: -x[1]):
                pct = (count / total * 100) if total > 0 else 0
                report += f"  {channel}: {count} ({pct:.1f}%)\n"

        if daily_analysis:
            report += "\nDaily Feedback Volume:\n"
            for day, count in sorted(daily_analysis.items()):
                report += f"  {day}: {count}\n"

        report += "\nAgent Scores:\n"
        for agent_id, score in sorted(agent_scores.items(), key=lambda x: (x[1] is None, x[1] if x[1] is not None else 0)):
            display = f"{agent_id[:20]}..." if len(agent_id) > 20 else agent_id
            if score is None:
                report += f"  {display}: InsufficientData (<3 reports)\n"
                continue
            rating = "Excellent" if score >= 95 else "Good" if score >= 85 else "Needs Improvement" if score >= 70 else "Critical"
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

    # Defense-in-depth: restrict to known Dataverse domains using regex
    # Accepts: *.crm[N].dynamics.com (any region number), sovereign clouds, GCC
    import re
    dataverse_pattern = re.compile(
        r'^[a-z0-9\-]+\.(crm\d*\.dynamics\.com|crm\.microsoftdynamics\.us|crm\.appsplatform\.us|crm\.dynamics\.cn|crm\.dynamics\.de)$',
        re.IGNORECASE,
    )
    if not dataverse_pattern.match(parsed.netloc):
        print(f"Error: --environment host must be a Dataverse domain (*.crm[N].dynamics.com, *.microsoftdynamics.us, *.appsplatform.us, *.dynamics.cn, *.dynamics.de)")
        print(f"  Got: {parsed.netloc}")
        sys.exit(1)

    if not args.dry_run and os.environ.get("AZURE_CLIENT_SECRET"):
        # legacy: dev-only - replace with managed identity in production
        missing = [v for v in ("AZURE_TENANT_ID", "AZURE_CLIENT_ID") if not os.environ.get(v)]
        if missing:
            print(f"Error: Missing required environment variables for legacy client-secret auth: {', '.join(missing)}")
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
            {"fsi_category": 100000000, "fsi_severity": 100000002, "fsi_agentid": "agent-001", "fsi_source": 100000000, "fsi_topicname": "Account fees", "fsi_channelid": "msteams", "createdon": "2026-05-01T10:00:00Z"},
            {"fsi_category": 100000000, "fsi_severity": 100000001, "fsi_agentid": "agent-001", "fsi_source": 100000001, "fsi_topicname": "Account fees", "fsi_channelid": "msteams", "createdon": "2026-05-01T11:00:00Z"},
            {"fsi_category": 100000002, "fsi_severity": 100000002, "fsi_agentid": "agent-002", "fsi_source": 100000002, "fsi_topicname": "Citations", "fsi_channelid": "webchat", "createdon": "2026-05-02T10:00:00Z"},
            {"fsi_category": 100000001, "fsi_severity": 100000003, "fsi_agentid": "agent-001", "fsi_source": 100000001, "fsi_topicname": "Account fees", "fsi_channelid": "msteams", "createdon": "2026-05-02T11:00:00Z"},
            {"fsi_category": 100000000, "fsi_severity": 100000000, "fsi_agentid": "agent-003", "fsi_source": 100000003, "fsi_topicname": "General", "fsi_channelid": "webchat", "createdon": "2026-05-03T10:00:00Z"},
        ]
        is_complete = True
    else:
        status_print("\nAuthenticating...")
        try:
            analyzer.authenticate()
        except RuntimeError as exc:
            print(f"Error: {exc}")
            sys.exit(1)
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
            "topic_distribution": analyzer.analyze_by_topic(feedback),
            "channel_distribution": analyzer.analyze_by_channel(feedback),
            "daily_distribution": analyzer.analyze_by_day(feedback),
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
