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
