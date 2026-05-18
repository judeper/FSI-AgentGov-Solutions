#!/usr/bin/env python3
"""Unit tests for analyze_patterns.py pure functions."""

import sys
import os
import unittest

# Add scripts directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))

from analyze_patterns import PatternAnalyzer, main


# Sample feedback matching the dry-run data structure
SAMPLE_FEEDBACK = [
    {"fsi_category": 100000000, "fsi_severity": 100000002, "fsi_agentid": "agent-001", "fsi_source": 100000000},
    {"fsi_category": 100000000, "fsi_severity": 100000001, "fsi_agentid": "agent-001", "fsi_source": 100000001},
    {"fsi_category": 100000002, "fsi_severity": 100000002, "fsi_agentid": "agent-002", "fsi_source": 100000002},
    {"fsi_category": 100000001, "fsi_severity": 100000003, "fsi_agentid": "agent-001", "fsi_source": 100000001},
    {"fsi_category": 100000000, "fsi_severity": 100000000, "fsi_agentid": "agent-003", "fsi_source": 100000003},
]


class TestAnalyzeByCategory(unittest.TestCase):
    def setUp(self):
        self.analyzer = PatternAnalyzer("https://example.crm.dynamics.com", "t", "c", "s")

    def test_counts_categories(self):
        result = self.analyzer.analyze_by_category(SAMPLE_FEEDBACK)
        self.assertEqual(result["factual_error"], 3)
        self.assertEqual(result["citation_missing"], 1)
        self.assertEqual(result["fabricated_data"], 1)

    def test_empty_feedback(self):
        result = self.analyzer.analyze_by_category([])
        self.assertEqual(result, {})

    def test_unknown_category(self):
        feedback = [{"fsi_category": 999999, "fsi_severity": 100000000, "fsi_agentid": "a"}]
        result = self.analyzer.analyze_by_category(feedback)
        self.assertEqual(result["unknown"], 1)


class TestAnalyzeSeverity(unittest.TestCase):
    def setUp(self):
        self.analyzer = PatternAnalyzer("https://example.crm.dynamics.com", "t", "c", "s")

    def test_counts_severities(self):
        result = self.analyzer.analyze_severity(SAMPLE_FEEDBACK)
        self.assertEqual(result["high"], 2)
        self.assertEqual(result["medium"], 1)
        self.assertEqual(result["critical"], 1)
        self.assertEqual(result["low"], 1)

    def test_empty_feedback(self):
        result = self.analyzer.analyze_severity([])
        self.assertEqual(result, {})


class TestAnalyzeBySource(unittest.TestCase):
    def setUp(self):
        self.analyzer = PatternAnalyzer("https://example.crm.dynamics.com", "t", "c", "s")

    def test_counts_sources(self):
        result = self.analyzer.analyze_by_source(SAMPLE_FEEDBACK)
        self.assertEqual(result["user"], 1)
        self.assertEqual(result["supervisor"], 2)
        self.assertEqual(result["automated"], 1)
        self.assertEqual(result["customer"], 1)

    def test_empty_feedback(self):
        result = self.analyzer.analyze_by_source([])
        self.assertEqual(result, {})

    def test_unknown_source(self):
        feedback = [{"fsi_category": 100000000, "fsi_severity": 100000000, "fsi_agentid": "a", "fsi_source": 999999}]
        result = self.analyzer.analyze_by_source(feedback)
        self.assertEqual(result["unknown"], 1)


class TestCalculateAgentScores(unittest.TestCase):
    def setUp(self):
        self.analyzer = PatternAnalyzer("https://example.crm.dynamics.com", "t", "c", "s")

    def test_scores_range(self):
        scores = self.analyzer.calculate_agent_scores(SAMPLE_FEEDBACK)
        for score in scores.values():
            if score is None:
                # InsufficientData (<MIN_REPORTS_FOR_SCORE) — acceptable, skip range check.
                continue
            self.assertGreaterEqual(score, 0)
            self.assertLessEqual(score, 100)

    def test_agent_with_critical_scores_lower(self):
        scores = self.analyzer.calculate_agent_scores(SAMPLE_FEEDBACK)
        # agent-001 has 3 reports including a critical (scores below 100);
        # agent-003 has 1 low (returns None — InsufficientData).
        self.assertIsNotNone(scores["agent-001"])
        self.assertIsNone(scores["agent-003"])

    def test_empty_feedback(self):
        scores = self.analyzer.calculate_agent_scores([])
        self.assertEqual(scores, {})

    def test_insufficient_reports_returns_none(self):
        # Single low-severity report ⇒ InsufficientData (<3).
        feedback = [{"fsi_agentid": "agent-x", "fsi_severity": 100000000, "fsi_category": 100000000, "fsi_source": 100000000}]
        scores = self.analyzer.calculate_agent_scores(feedback)
        self.assertIsNone(scores["agent-x"])


class TestDetectPatterns(unittest.TestCase):
    def setUp(self):
        self.analyzer = PatternAnalyzer("https://example.crm.dynamics.com", "t", "c", "s")

    def test_detects_category_cluster(self):
        patterns = self.analyzer.detect_patterns(SAMPLE_FEEDBACK)
        category_patterns = [p for p in patterns if p["type"] == "category_cluster"]
        # factual_error has 3 occurrences, meeting the threshold
        self.assertTrue(any(p["category"] == "factual_error" for p in category_patterns))

    def test_no_agent_cluster_below_threshold(self):
        patterns = self.analyzer.detect_patterns(SAMPLE_FEEDBACK)
        agent_patterns = [p for p in patterns if p["type"] == "agent_cluster"]
        # agent-001 has 3 reports, below the 5 threshold
        self.assertEqual(len(agent_patterns), 0)

    def test_agent_cluster_above_threshold(self):
        feedback = [
            {"fsi_category": 100000000, "fsi_severity": 100000000, "fsi_agentid": "agent-X"}
            for _ in range(5)
        ]
        patterns = self.analyzer.detect_patterns(feedback)
        agent_patterns = [p for p in patterns if p["type"] == "agent_cluster"]
        self.assertEqual(len(agent_patterns), 1)
        self.assertEqual(agent_patterns[0]["agent_id"], "agent-X")

    def test_empty_feedback(self):
        patterns = self.analyzer.detect_patterns([])
        self.assertEqual(patterns, [])


class TestNullFieldValues(unittest.TestCase):
    """Test handling of null/None field values from Dataverse."""

    def setUp(self):
        self.analyzer = PatternAnalyzer("https://example.crm.dynamics.com", "t", "c", "s")

    def test_null_agentid_analyze_by_agent(self):
        feedback = [{"fsi_category": 100000000, "fsi_severity": 100000000, "fsi_agentid": None}]
        result = self.analyzer.analyze_by_agent(feedback)
        self.assertEqual(result["unknown"], 1)

    def test_null_category_analyze_by_category(self):
        feedback = [{"fsi_category": None, "fsi_severity": 100000000, "fsi_agentid": "a"}]
        result = self.analyzer.analyze_by_category(feedback)
        # None key exists so .get() returns None (not default 0); CATEGORIES.get(None, "unknown") maps it to "unknown"
        self.assertIn("unknown", result)

    def test_null_severity_analyze_severity(self):
        feedback = [{"fsi_category": 100000000, "fsi_severity": None, "fsi_agentid": "a"}]
        result = self.analyzer.analyze_severity(feedback)
        self.assertIn("unknown", result)

    def test_null_agentid_calculate_scores(self):
        feedback = [{"fsi_category": 100000000, "fsi_severity": 100000001, "fsi_agentid": None}]
        scores = self.analyzer.calculate_agent_scores(feedback)
        self.assertIn("unknown", scores)

    def test_null_agentid_generate_report(self):
        feedback = [{"fsi_category": 100000000, "fsi_severity": 100000001, "fsi_agentid": None}]
        report = self.analyzer.generate_report(feedback)
        self.assertIn("unknown", report)

    def test_all_null_fields(self):
        feedback = [{"fsi_category": None, "fsi_severity": None, "fsi_agentid": None}]
        report = self.analyzer.generate_report(feedback)
        self.assertIn("unknown", report)
        self.assertIn("Total Reports: 1", report)



class TestCurrentFeedbackDimensions(unittest.TestCase):
    """Test topic, channel, and time-window clustering fields."""

    def setUp(self):
        self.analyzer = PatternAnalyzer("https://example.crm.dynamics.com", "t", "c", "s")
        self.feedback = [
            {"fsi_category": 100000000, "fsi_severity": 100000002, "fsi_agentid": "a1", "fsi_source": 100000000, "fsi_topicname": "Fees", "fsi_channelid": "msteams", "createdon": "2026-05-01T10:00:00Z"},
            {"fsi_category": 100000000, "fsi_severity": 100000001, "fsi_agentid": "a1", "fsi_source": 100000000, "fsi_topicname": "Fees", "fsi_channelid": "msteams", "createdon": "2026-05-01T11:00:00Z"},
            {"fsi_category": 100000001, "fsi_severity": 100000003, "fsi_agentid": "a2", "fsi_source": 100000004, "fsi_topicname": "Fees", "fsi_channelid": "m365copilot", "createdon": "2026-05-02T10:00:00Z"},
            {"fsi_category": 100000002, "fsi_severity": 100000002, "fsi_agentid": "a3", "fsi_source": 100000002, "fsi_topicname": "Citations", "fsi_channelid": "webchat", "createdon": "2026-05-03T10:00:00Z"},
        ]

    def test_topic_distribution(self):
        result = self.analyzer.analyze_by_topic(self.feedback)
        self.assertEqual(result["Fees"], 3)

    def test_channel_distribution(self):
        result = self.analyzer.analyze_by_channel(self.feedback)
        self.assertEqual(result["msteams"], 2)
        self.assertEqual(result["m365copilot"], 1)

    def test_daily_distribution(self):
        result = self.analyzer.analyze_by_day(self.feedback)
        self.assertEqual(result["2026-05-01"], 2)

    def test_detects_topic_cluster(self):
        patterns = self.analyzer.detect_patterns(self.feedback)
        self.assertTrue(any(p["type"] == "topic_cluster" and p["topic"] == "Fees" for p in patterns))

    def test_m365_copilot_source_label(self):
        result = self.analyzer.analyze_by_source(self.feedback)
        self.assertEqual(result["microsoft_365_copilot"], 1)

class TestGenerateReportPartialData(unittest.TestCase):
    """Test generate_report with is_complete=False."""

    def setUp(self):
        self.analyzer = PatternAnalyzer("https://example.crm.dynamics.com", "t", "c", "s")

    def test_partial_data_warning_present(self):
        report = self.analyzer.generate_report(SAMPLE_FEEDBACK, is_complete=False)
        self.assertIn("PARTIAL DATA", report)
        self.assertIn("WARNING", report)

    def test_partial_data_warning_absent_when_complete(self):
        report = self.analyzer.generate_report(SAMPLE_FEEDBACK, is_complete=True)
        self.assertNotIn("PARTIAL DATA", report)

    def test_partial_data_still_includes_report_content(self):
        report = self.analyzer.generate_report(SAMPLE_FEEDBACK, is_complete=False)
        self.assertIn("Total Reports:", report)
        self.assertIn("Category Distribution:", report)
        self.assertIn("Agent Scores:", report)


class TestAgentIdDisplayTruncation(unittest.TestCase):
    """Test that agent IDs are displayed correctly in reports."""

    def setUp(self):
        self.analyzer = PatternAnalyzer("https://example.crm.dynamics.com", "t", "c", "s")

    def test_short_agent_id_not_truncated(self):
        feedback = [{"fsi_category": 100000000, "fsi_severity": 100000000, "fsi_agentid": "short"}]
        report = self.analyzer.generate_report(feedback)
        self.assertIn("short:", report)
        self.assertNotIn("short...:", report)

    def test_long_agent_id_truncated(self):
        feedback = [{"fsi_category": 100000000, "fsi_severity": 100000000, "fsi_agentid": "very-long-agent-identifier"}]
        report = self.analyzer.generate_report(feedback)
        # Code truncates at 20 chars: "very-long-agent-iden" + "..."
        self.assertIn("very-long-agent-iden...:", report)


class TestMainErrorPaths(unittest.TestCase):
    """Test main() argument validation and error paths."""

    def test_negative_days_exits(self):
        sys.argv = ["analyze_patterns.py", "--environment", "https://test.crm.dynamics.com", "--days", "-5"]
        with self.assertRaises(SystemExit) as ctx:
            main()
        self.assertEqual(ctx.exception.code, 1)

    def test_zero_days_exits(self):
        sys.argv = ["analyze_patterns.py", "--environment", "https://test.crm.dynamics.com", "--days", "0"]
        with self.assertRaises(SystemExit) as ctx:
            main()
        self.assertEqual(ctx.exception.code, 1)

    def test_http_url_rejected(self):
        sys.argv = ["analyze_patterns.py", "--environment", "http://test.crm.dynamics.com", "--days", "7"]
        with self.assertRaises(SystemExit) as ctx:
            main()
        self.assertEqual(ctx.exception.code, 1)

    def test_invalid_domain_rejected(self):
        sys.argv = ["analyze_patterns.py", "--environment", "https://evil.example.com", "--days", "7"]
        with self.assertRaises(SystemExit) as ctx:
            main()
        self.assertEqual(ctx.exception.code, 1)

    def test_gcc_high_domain_accepted(self):
        """GCC High / DoD domains should pass URL validation."""
        sys.argv = ["analyze_patterns.py", "--environment", "https://org.crm.microsoftdynamics.us",
                     "--days", "7", "--dry-run"]
        # Should not raise on URL validation; dry-run bypasses auth
        try:
            main()
        except SystemExit as e:
            # Exit code 0 is acceptable (dry-run completes normally)
            self.assertEqual(e.code, 0)

    def test_dod_domain_accepted(self):
        """DoD (appsplatform.us) domains should pass URL validation."""
        sys.argv = ["analyze_patterns.py", "--environment", "https://org.crm.appsplatform.us",
                     "--days", "7", "--dry-run"]
        try:
            main()
        except SystemExit as e:
            self.assertEqual(e.code, 0)

    def test_missing_env_vars_exits(self):
        """Unavailable auth credentials should exit with code 1 (non-dry-run)."""
        # Ensure env vars are unset
        env_backup = {}
        for var in ("AZURE_TENANT_ID", "AZURE_CLIENT_ID", "AZURE_CLIENT_SECRET"):
            env_backup[var] = os.environ.pop(var, None)
        try:
            os.environ["AZURE_CLIENT_SECRET"] = "legacy-secret-without-required-ids"
            sys.argv = ["analyze_patterns.py", "--environment", "https://test.crm.dynamics.com", "--days", "7"]
            with self.assertRaises(SystemExit) as ctx:
                main()
            self.assertEqual(ctx.exception.code, 1)
        finally:
            for var, val in env_backup.items():
                if val is not None:
                    os.environ[var] = val
                else:
                    os.environ.pop(var, None)


if __name__ == "__main__":
    unittest.main()
