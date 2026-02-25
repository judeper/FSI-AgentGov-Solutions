#!/usr/bin/env python3
"""Unit tests for analyze_patterns.py pure functions."""

import sys
import os
import unittest

# Add scripts directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))

from analyze_patterns import PatternAnalyzer, CATEGORIES, SEVERITIES, SEVERITY_WEIGHTS


# Sample feedback matching the dry-run data structure
SAMPLE_FEEDBACK = [
    {"fsi_category": 100000000, "fsi_severity": 100000002, "fsi_agentid": "agent-001"},
    {"fsi_category": 100000000, "fsi_severity": 100000001, "fsi_agentid": "agent-001"},
    {"fsi_category": 100000002, "fsi_severity": 100000002, "fsi_agentid": "agent-002"},
    {"fsi_category": 100000001, "fsi_severity": 100000003, "fsi_agentid": "agent-001"},
    {"fsi_category": 100000000, "fsi_severity": 100000000, "fsi_agentid": "agent-003"},
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
        self.assertEqual(result[100000002], 2)  # High
        self.assertEqual(result[100000001], 1)  # Medium
        self.assertEqual(result[100000003], 1)  # Critical
        self.assertEqual(result[100000000], 1)  # Low

    def test_empty_feedback(self):
        result = self.analyzer.analyze_severity([])
        self.assertEqual(result, {})


class TestCalculateAgentScores(unittest.TestCase):
    def setUp(self):
        self.analyzer = PatternAnalyzer("https://example.crm.dynamics.com", "t", "c", "s")

    def test_scores_range(self):
        scores = self.analyzer.calculate_agent_scores(SAMPLE_FEEDBACK)
        for score in scores.values():
            self.assertGreaterEqual(score, 0)
            self.assertLessEqual(score, 100)

    def test_agent_with_critical_scores_lower(self):
        scores = self.analyzer.calculate_agent_scores(SAMPLE_FEEDBACK)
        # agent-001 has 3 reports including a critical; agent-003 has 1 low
        self.assertLess(scores["agent-001"], scores["agent-003"])

    def test_empty_feedback(self):
        scores = self.analyzer.calculate_agent_scores([])
        self.assertEqual(scores, {})


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
        self.assertIn("unknown", result)  # None coalesces to 0, not in CATEGORIES -> "unknown"

    def test_null_severity_analyze_severity(self):
        feedback = [{"fsi_category": 100000000, "fsi_severity": None, "fsi_agentid": "a"}]
        result = self.analyzer.analyze_severity(feedback)
        self.assertIn(100000000, result)  # defaults to Low

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


if __name__ == "__main__":
    unittest.main()
