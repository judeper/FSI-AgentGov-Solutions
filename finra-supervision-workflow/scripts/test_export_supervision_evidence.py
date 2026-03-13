"""
Unit tests for FINRA Supervision Workflow Python scripts.

Covers regulatory-critical paths: SLA compliance calculations, SHA-256 integrity
hashing, date-range filtering, and export/evidence functions.

Run with: python -m pytest test_export_supervision_evidence.py -v
"""

import hashlib
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timezone

# Ensure the scripts directory is on sys.path so we can import modules.
_script_dir = os.path.dirname(os.path.abspath(__file__))
if _script_dir not in sys.path:
    sys.path.insert(0, _script_dir)

from export_supervision_evidence import calculate_sha256, export_to_json, generate_sla_metrics


class TestCalculateSha256(unittest.TestCase):
    """Tests for SHA-256 integrity hashing used in SEC 17a-4 evidence exports."""

    def test_known_hash(self):
        """SHA-256 of known content matches expected digest."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write('{"test": true}')
            f.flush()
            path = f.name
        try:
            result = calculate_sha256(path)
            expected = hashlib.sha256(b'{"test": true}').hexdigest()
            self.assertEqual(result, expected)
        finally:
            os.unlink(path)

    def test_empty_file(self):
        """SHA-256 of an empty file matches the well-known empty digest."""
        with tempfile.NamedTemporaryFile(delete=False) as f:
            path = f.name
        try:
            result = calculate_sha256(path)
            expected = hashlib.sha256(b"").hexdigest()
            self.assertEqual(result, expected)
        finally:
            os.unlink(path)

    def test_large_file(self):
        """SHA-256 works correctly for files larger than the 4096-byte read block."""
        content = b"A" * 10000
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(content)
            path = f.name
        try:
            result = calculate_sha256(path)
            expected = hashlib.sha256(content).hexdigest()
            self.assertEqual(result, expected)
        finally:
            os.unlink(path)


class TestExportToJson(unittest.TestCase):
    """Tests for JSON export with metadata generation."""

    def test_export_creates_file_with_correct_content(self):
        """Exported JSON file contains the original data."""
        data = [{"id": 1, "name": "test"}]
        with tempfile.TemporaryDirectory() as tmpdir:
            filepath = os.path.join(tmpdir, "test_export.json")
            metadata = export_to_json(data, filepath)
            with open(filepath, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            self.assertEqual(loaded, data)

    def test_export_metadata_fields(self):
        """Metadata includes required fields: filename, record_count, sha256_hash."""
        data = [{"a": 1}, {"a": 2}]
        with tempfile.TemporaryDirectory() as tmpdir:
            filepath = os.path.join(tmpdir, "meta_test.json")
            metadata = export_to_json(data, filepath)
            self.assertEqual(metadata["filename"], "meta_test.json")
            self.assertEqual(metadata["record_count"], 2)
            self.assertIn("sha256_hash", metadata)
            self.assertEqual(len(metadata["sha256_hash"]), 64)  # SHA-256 hex length
            self.assertIn("file_size_bytes", metadata)
            self.assertGreater(metadata["file_size_bytes"], 0)
            self.assertIn("exported_at", metadata)

    def test_export_hash_matches_file(self):
        """Metadata SHA-256 matches independently computed hash of the file."""
        data = [{"compliance": True}]
        with tempfile.TemporaryDirectory() as tmpdir:
            filepath = os.path.join(tmpdir, "hash_verify.json")
            metadata = export_to_json(data, filepath)
            independent_hash = calculate_sha256(filepath)
            self.assertEqual(metadata["sha256_hash"], independent_hash)


class TestGenerateSlaMetrics(unittest.TestCase):
    """Tests for SLA compliance calculations — regulatory-critical for FINRA 3120."""

    def test_empty_records(self):
        """Empty input returns zero-total message."""
        result = generate_sla_metrics([])
        self.assertEqual(result["total"], 0)
        self.assertIn("message", result)

    def test_all_completed_within_sla(self):
        """100% SLA compliance when all items reviewed before SLA due."""
        records = [
            {
                "fsi_state": 3,  # Approved
                "fsi_revieweddate": "2026-01-15T10:00:00Z",
                "fsi_sladue": "2026-01-16T10:00:00Z",
                "fsi_queueddate": "2026-01-14T10:00:00Z",
                "fsi_zone": 1,
                "fsi_reviewoutcome": 1,
            },
            {
                "fsi_state": 5,  # Rejected
                "fsi_revieweddate": "2026-01-15T12:00:00Z",
                "fsi_sladue": "2026-01-17T12:00:00Z",
                "fsi_queueddate": "2026-01-14T12:00:00Z",
                "fsi_zone": 2,
                "fsi_reviewoutcome": 2,
            },
        ]
        result = generate_sla_metrics(records)
        self.assertEqual(result["total_items"], 2)
        self.assertEqual(result["completed"], 2)
        self.assertEqual(result["sla_breached"], 0)
        self.assertEqual(result["sla_compliance_rate"], 100.0)

    def test_sla_breach_detected(self):
        """SLA breach counted when review date is after SLA due date."""
        records = [
            {
                "fsi_state": 3,
                "fsi_revieweddate": "2026-01-18T10:00:00Z",  # After SLA
                "fsi_sladue": "2026-01-16T10:00:00Z",
                "fsi_queueddate": "2026-01-14T10:00:00Z",
                "fsi_zone": 1,
                "fsi_reviewoutcome": 1,
            },
        ]
        result = generate_sla_metrics(records)
        self.assertEqual(result["sla_breached"], 1)
        self.assertEqual(result["sla_compliance_rate"], 0.0)

    def test_average_review_time(self):
        """Average review time calculated correctly from queued-to-reviewed delta."""
        records = [
            {
                "fsi_state": 3,
                "fsi_revieweddate": "2026-01-15T10:00:00Z",
                "fsi_sladue": "2026-01-20T10:00:00Z",
                "fsi_queueddate": "2026-01-15T06:00:00Z",  # 4 hours
                "fsi_zone": 1,
                "fsi_reviewoutcome": 1,
            },
            {
                "fsi_state": 3,
                "fsi_revieweddate": "2026-01-16T14:00:00Z",
                "fsi_sladue": "2026-01-20T14:00:00Z",
                "fsi_queueddate": "2026-01-16T08:00:00Z",  # 6 hours
                "fsi_zone": 2,
                "fsi_reviewoutcome": 1,
            },
        ]
        result = generate_sla_metrics(records)
        self.assertEqual(result["average_review_time_hours"], 5.0)  # (4+6)/2

    def test_pending_and_escalated_counts(self):
        """Pending and escalated items counted separately from completed."""
        records = [
            {"fsi_state": 1, "fsi_zone": 1},  # Pending
            {"fsi_state": 2, "fsi_zone": 1},  # InReview
            {"fsi_state": 4, "fsi_zone": 2},  # Escalated
            {
                "fsi_state": 3,
                "fsi_revieweddate": "2026-01-15T10:00:00Z",
                "fsi_sladue": "2026-01-16T10:00:00Z",
                "fsi_queueddate": "2026-01-14T10:00:00Z",
                "fsi_zone": 1,
                "fsi_reviewoutcome": 1,
            },
        ]
        result = generate_sla_metrics(records)
        self.assertEqual(result["total_items"], 4)
        self.assertEqual(result["pending"], 2)
        self.assertEqual(result["escalated"], 1)
        self.assertEqual(result["completed"], 1)

    def test_zone_breakdown(self):
        """Zone breakdown counts items per zone correctly."""
        records = [
            {"fsi_state": 1, "fsi_zone": 1},
            {"fsi_state": 1, "fsi_zone": 1},
            {"fsi_state": 1, "fsi_zone": 2},
            {"fsi_state": 1, "fsi_zone": 3},
        ]
        result = generate_sla_metrics(records)
        self.assertEqual(result["by_zone"]["zone_1"], 2)
        self.assertEqual(result["by_zone"]["zone_2"], 1)
        self.assertEqual(result["by_zone"]["zone_3"], 1)


class TestAuthModule(unittest.TestCase):
    """Basic import and interface tests for auth.py."""

    def test_get_access_token_importable(self):
        """The get_access_token function is importable."""
        from auth import get_access_token
        self.assertTrue(callable(get_access_token))

    def test_get_access_token_requires_credentials_for_non_interactive(self):
        """Non-interactive auth exits when client_id/client_secret missing."""
        from auth import get_access_token
        with self.assertRaises(SystemExit):
            get_access_token(
                tenant_id="fake-tenant",
                client_id=None,
                client_secret=None,
                interactive=False,
                environment_url="https://example.crm.dynamics.com",
            )


if __name__ == "__main__":
    unittest.main()
