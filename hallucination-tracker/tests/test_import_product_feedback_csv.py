from __future__ import annotations

import importlib.util
import json
import shutil
import sys
from pathlib import Path

import pytest

SCRIPT_DIR = Path(__file__).resolve().parents[1] / "scripts"
IMPORTER_SPEC = importlib.util.spec_from_file_location(
    "import_product_feedback_csv",
    SCRIPT_DIR / "import_product_feedback_csv.py",
)
assert IMPORTER_SPEC is not None and IMPORTER_SPEC.loader is not None
importer = importlib.util.module_from_spec(IMPORTER_SPEC)
sys.modules[IMPORTER_SPEC.name] = importer
IMPORTER_SPEC.loader.exec_module(importer)

ANALYZER_SPEC = importlib.util.spec_from_file_location(
    "analyze_patterns",
    SCRIPT_DIR / "analyze_patterns.py",
)
assert ANALYZER_SPEC is not None and ANALYZER_SPEC.loader is not None
analyze_patterns = importlib.util.module_from_spec(ANALYZER_SPEC)
sys.modules[ANALYZER_SPEC.name] = analyze_patterns
ANALYZER_SPEC.loader.exec_module(analyze_patterns)

FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"
GENERATED_DIR = Path(__file__).resolve().parent / "_generated"


class FakeWriter:
    def __init__(self, existing: set[str] | None = None):
        self._existing = set(existing or set())
        self.created: list[dict[str, object]] = []

    def existing_reportnames(self, reportnames):
        return set(reportnames) & self._existing

    def create(self, record):
        self.created.append(record)
        self._existing.add(record["fsi_reportname"])
        return record["fsi_reportname"]


@pytest.fixture(autouse=True)
def clean_generated_dir():
    if GENERATED_DIR.exists():
        shutil.rmtree(GENERATED_DIR)
    GENERATED_DIR.mkdir(parents=True)
    yield
    shutil.rmtree(GENERATED_DIR)


def run_import(fixture_name: str, *, writer: FakeWriter | None = None):
    output_path = GENERATED_DIR / f"{Path(fixture_name).stem}.json"
    summary = importer.process_product_feedback_csv(
        FIXTURES_DIR / fixture_name,
        output_path=output_path,
        writer=writer,
    )
    return summary, output_path


def load_records(output_path: Path) -> list[dict[str, object]]:
    return json.loads(output_path.read_text(encoding="utf-8"))


def records_by_conversation(records: list[dict[str, object]]) -> dict[str, dict[str, object]]:
    return {
        str(record["fsi_conversationid"]): record
        for record in records
        if record.get("fsi_conversationid")
    }


def test_happy_path_imports_expected_records():
    writer = FakeWriter()
    summary, output_path = run_import("product-feedback-sample.csv", writer=writer)

    records = json.loads(output_path.read_text(encoding="utf-8"))

    assert summary.rows_read == 6
    assert summary.rows_normalized == 3
    assert summary.rows_written == 3
    assert summary.rows_skipped == 3
    assert len(writer.created) == 3
    assert len(records) == 3
    assert {record["fsi_source"] for record in records} == {
        importer.SOURCE_MICROSOFT_365_COPILOT
    }
    assert {record["fsi_category"] for record in records} == {
        importer.CATEGORY_CITATION_MISSING,
        importer.CATEGORY_OUTDATED_INFO,
        importer.CATEGORY_FABRICATED_DATA,
    }
    assert all(record["fsi_reportedat"].endswith("Z") for record in records)
    assert all("fsi_reportname" in record for record in records)
    assert all("fsi_topicname" in record for record in records)


def test_empty_csv_exits_cleanly_with_zero_imports():
    writer = FakeWriter()
    summary, output_path = run_import("product-feedback-empty.csv", writer=writer)

    assert summary.rows_read == 0
    assert summary.rows_normalized == 0
    assert summary.rows_written == 0
    assert summary.rows_skipped == 0
    assert writer.created == []
    assert json.loads(output_path.read_text(encoding="utf-8")) == []


def test_malformed_row_is_logged_and_skipped():
    summary, _ = run_import("product-feedback-sample.csv", writer=FakeWriter())

    assert summary.skipped_reasons["invalid_date"] == 1


def test_duplicate_rows_are_deduplicated():
    summary, output_path = run_import("product-feedback-sample.csv", writer=FakeWriter())
    records = json.loads(output_path.read_text(encoding="utf-8"))

    assert summary.skipped_reasons["duplicate_row"] == 1
    reportnames = [record["fsi_reportname"] for record in records]
    assert len(reportnames) == len(set(reportnames))


def test_clustering_fields_populated_for_every_imported_record():
    summary, output_path = run_import("product-feedback-clustering.csv", writer=FakeWriter())
    records = load_records(output_path)

    assert summary.rows_normalized == 5
    required_fields = (
        "fsi_topicname",
        "fsi_topicid",
        "fsi_channelid",
        "fsi_feedbackcomment",
        "fsi_reportedat",
    )
    for record in records:
        for field in required_fields:
            assert record.get(field), f"Expected {field} on {record['fsi_reportname']}"


def test_same_signal_rows_share_deterministic_cluster_label():
    _, output_path = run_import("product-feedback-clustering.csv", writer=FakeWriter())
    records = records_by_conversation(load_records(output_path))

    assert records["PF-101"]["fsi_topicid"] == records["PF-102"]["fsi_topicid"]
    assert records["PF-101"]["fsi_topicname"] == "Word / Research"
    assert records["PF-101"]["fsi_channelid"] == "m365copilot"


def test_different_signal_rows_get_different_cluster_labels():
    _, output_path = run_import("product-feedback-clustering.csv", writer=FakeWriter())
    records = records_by_conversation(load_records(output_path))

    assert records["PF-101"]["fsi_topicid"] != records["PF-103"]["fsi_topicid"]
    assert records["PF-103"]["fsi_topicname"] == "Word / Mail"


def test_missing_text_falls_back_to_per_record_cluster_label():
    _, output_path = run_import("product-feedback-clustering.csv", writer=FakeWriter())
    records = records_by_conversation(load_records(output_path))

    assert records["PF-104"]["fsi_feedbackcomment"] == "In-app feedback"
    assert records["PF-104"]["fsi_topicid"] != records["PF-105"]["fsi_topicid"]
    assert "record" in str(records["PF-104"]["fsi_topicid"])


def test_imported_records_are_ready_for_analyzer_grouping():
    _, output_path = run_import("product-feedback-clustering.csv", writer=FakeWriter())
    records = load_records(output_path)
    analyzer = analyze_patterns.PatternAnalyzer(
        "https://example.crm.dynamics.com",
        "tenant-id",
        "client-id",
        "client-secret",
    )

    assert analyzer.analyze_by_topic(records) == {
        "Word / Research": 2,
        "Word / Mail": 1,
        "Teams / Meetings": 2,
    }
    assert analyzer.analyze_by_channel(records) == {"m365copilot": 5}
    assert analyzer.analyze_by_day(records) == {
        "2026-05-04": 2,
        "2026-05-05": 3,
    }
