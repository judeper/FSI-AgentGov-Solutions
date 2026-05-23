"""Tests for lint-version-drift.py."""

from __future__ import annotations

import importlib.util
import shutil
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "lint-version-drift.py"
SPEC = importlib.util.spec_from_file_location("lint_version_drift", SCRIPT_PATH)
assert SPEC is not None
lint_version_drift = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(lint_version_drift)


class LintVersionDriftTests(unittest.TestCase):
    """Validate manifest-to-CHANGELOG version drift detection."""

    def setUp(self) -> None:
        self.temp_dir = Path(
            tempfile.mkdtemp(prefix="lint-version-drift-", dir=Path(__file__).resolve().parent)
        )

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir)

    def write_solution(self, version: str, changelog: str | None = None) -> Path:
        solution_dir = self.temp_dir / "sample-solution"
        solution_dir.mkdir()
        (solution_dir / "manifest.yaml").write_text(
            f"id: sample-solution\nversion: \"{version}\"\n", encoding="utf-8"
        )
        if changelog is not None:
            (solution_dir / "CHANGELOG.md").write_text(
                textwrap.dedent(changelog).lstrip(), encoding="utf-8"
            )
        return solution_dir

    def lint(self, version: str, changelog: str | None = None) -> list[str]:
        return lint_version_drift.lint_solution(self.write_solution(version, changelog))

    def test_match_case_has_no_finding(self) -> None:
        findings = self.lint("1.2.1", """
        # Changelog

        ## [1.2.1]
        - Updated.
        """)

        self.assertEqual([], findings)

    def test_mismatch_case_has_finding(self) -> None:
        findings = self.lint("1.2.1", """
        # Changelog

        ## [1.2.0]
        - Updated.
        """)

        self.assertEqual(1, len(findings))
        self.assertIn("manifest=1.2.1", findings[0])
        self.assertIn("most-recent-release=1.2.0", findings[0])
        self.assertIn("CHANGELOG.md:L3", findings[0])

    def test_preview_case_strips_leading_v_and_matches(self) -> None:
        findings = self.lint("v1.0.0-preview", """
        # Changelog

        ## [1.0.0-preview]
        - Updated.
        """)

        self.assertEqual([], findings)

    def test_unreleased_only_case_has_no_release_header_finding(self) -> None:
        findings = self.lint("1.2.1", """
        # Changelog

        ## [Unreleased]
        - Pending.
        """)

        self.assertEqual(1, len(findings))
        self.assertIn("no release header found", findings[0])

    def test_missing_changelog_case_has_finding(self) -> None:
        findings = self.lint("1.2.1")

        self.assertEqual(1, len(findings))
        self.assertIn("CHANGELOG.md missing", findings[0])

    def test_comment_line_is_not_parsed_as_header(self) -> None:
        findings = self.lint("1.0.0", """
        # Changelog

        <!-- ## [1.0.0] -->
        ## [0.9.0]
        - Updated.
        """)

        self.assertEqual(1, len(findings))
        self.assertIn("most-recent-release=0.9.0", findings[0])


if __name__ == "__main__":
    unittest.main()
