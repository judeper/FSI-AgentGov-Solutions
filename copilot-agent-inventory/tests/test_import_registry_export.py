"""Tests for import_registry_export.py.

Adversarial matrix covered:
  SHA-256 — sha256_file produces a correct, stable digest.
  Format detection — .xlsx/.xls -> 'xlsx'; anything else -> 'csv'.
  Header normalisation — alias lookup is case-insensitive and strips
    whitespace; no-alias fallback converts to snake_case.
  load_columnmap — loads aliases, required_canonical_fields, and sheet_name
    from a JSON file; raises FileNotFoundError on a missing path; respects
    defaults when optional keys are absent.
  CSV parsing — basic happy path; alias remap correctness (non-standard
    header names mapped via JSON alias map); unmapped required column =>
    hard-fail ValueError with an explicit header-diff (never a silent skip);
    the error message names the missing field for actionable diagnosis.
  Owner attribution — missing/empty owner_upn => fsi_ownermatchconfidence=
    "Unmatched"; absent owner_upn column => "Unmatched"; owner object ID
    (fsi_ownerid / owner_id) present => "Exact"; UPN present but no object
    ID => "Heuristic"; fsi_ownersource is always "Agent Registry Export";
    fsi_ownerasofdatetime stamped from --as-of; omitted when as_of=None.
  Edge cases — empty file raises ValueError; extra columns beyond required
    are passed through without error.
  XLSX path — _rows_from_xlsx is mocked (openpyxl abstracted) so the XLSX
    code path is exercised without a live file.

Synthetic identities use Contoso/Northwind domains only — no real names.
"""

from __future__ import annotations

import csv
import hashlib
import json
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

try:
    import import_registry_export as ire

    _IMPORT_ERROR: Exception | None = None
except Exception as exc:  # pragma: no cover
    ire = None  # type: ignore[assignment]
    _IMPORT_ERROR = exc

pytestmark = pytest.mark.skipif(
    ire is None,
    reason=f"import_registry_export could not be imported: {_IMPORT_ERROR}",
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _write_csv(
    tmp_path: Path,
    rows: list[list[str]],
    filename: str = "export.csv",
    encoding: str = "utf-8-sig",
) -> Path:
    p = tmp_path / filename
    with open(str(p), "w", newline="", encoding=encoding) as fh:
        writer = csv.writer(fh)
        for row in rows:
            writer.writerow(row)
    return p


def _write_columnmap(tmp_path: Path, data: dict, filename: str = "cmap.json") -> Path:
    p = tmp_path / filename
    p.write_text(json.dumps(data), encoding="utf-8")
    return p


# Minimal alias map shared by many tests.
_MINIMAL_ALIASES = {
    "synthetic_agent_display_name": "agent_name",
    "synthetic_owner_upn": "owner_upn",
}

_MINIMAL_REQUIRED = frozenset({"agent_name", "owner_upn"})


# =============================================================================
# sha256_file
# =============================================================================

def test_sha256_file_matches_hashlib_reference(tmp_path: Path) -> None:
    content = b"Contoso synthetic fixture content for sha256 verification"
    f = tmp_path / "sample.csv"
    f.write_bytes(content)
    expected = hashlib.sha256(content).hexdigest()
    assert ire.sha256_file(str(f)) == expected


def test_sha256_file_is_stable_across_two_calls(tmp_path: Path) -> None:
    content = b"stable content"
    f = tmp_path / "stable.csv"
    f.write_bytes(content)
    assert ire.sha256_file(str(f)) == ire.sha256_file(str(f))


# =============================================================================
# _detect_format
# =============================================================================

@pytest.mark.parametrize("path,expected", [
    ("report.xlsx",  "xlsx"),
    ("report.XLSX",  "xlsx"),
    ("export.csv",   "csv"),
    ("export.CSV",   "csv"),
    ("export.txt",   "csv"),   # non-xlsx extension falls back to CSV
    ("noextension",  "csv"),   # no extension -> CSV
])
def test_detect_format(path: str, expected: str) -> None:
    assert ire._detect_format(path) == expected


@pytest.mark.parametrize("path", ["report.xls", "report.XLS"])
def test_detect_format_xls_raises_value_error(path: str) -> None:
    """.xls is a legacy binary format unsupported by openpyxl — _detect_format
    must raise ValueError so callers get an explicit error message rather than a
    silent read failure."""
    with pytest.raises(ValueError, match="Legacy .xls"):
        ire._detect_format(path)


# =============================================================================
# _normalize_header
# =============================================================================

def test_normalize_header_alias_lookup_is_case_insensitive() -> None:
    aliases = {"synthetic_owner_upn": "owner_upn"}
    assert ire._normalize_header("Synthetic_Owner_UPN", aliases) == "owner_upn"
    assert ire._normalize_header("synthetic_owner_upn", aliases) == "owner_upn"
    assert ire._normalize_header("SYNTHETIC_OWNER_UPN", aliases) == "owner_upn"


def test_normalize_header_strips_surrounding_whitespace() -> None:
    aliases = {"synthetic_owner_upn": "owner_upn"}
    assert ire._normalize_header("  synthetic_owner_upn  ", aliases) == "owner_upn"


def test_normalize_header_fallback_converts_spaces_to_underscores() -> None:
    assert ire._normalize_header("Agent Name", {}) == "agent_name"
    assert ire._normalize_header("Date Created", {}) == "date_created"


# =============================================================================
# load_columnmap
# =============================================================================

def test_load_columnmap_reads_aliases_required_and_sheet(tmp_path: Path) -> None:
    cmap = {
        "header_aliases": {"my header": "owner_upn"},
        "required_canonical_fields": ["agent_name", "owner_upn"],
        "sheet_name": "Agents",
    }
    p = _write_columnmap(tmp_path, cmap)
    aliases, required, sheet = ire.load_columnmap(p)
    assert aliases == {"my header": "owner_upn"}
    assert required == frozenset({"agent_name", "owner_upn"})
    assert sheet == "Agents"


def test_load_columnmap_file_not_found_raises(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError, match="Column-map file not found"):
        ire.load_columnmap(tmp_path / "does_not_exist.json")


def test_load_columnmap_absent_sheet_name_returns_none(tmp_path: Path) -> None:
    cmap = {"header_aliases": {}}
    p = _write_columnmap(tmp_path, cmap)
    _, _, sheet = ire.load_columnmap(p)
    assert sheet is None


def test_load_columnmap_absent_required_fields_uses_defaults(tmp_path: Path) -> None:
    cmap = {"header_aliases": {}}
    p = _write_columnmap(tmp_path, cmap)
    _, required, _ = ire.load_columnmap(p)
    assert required == ire._DEFAULT_REQUIRED_FIELDS


# =============================================================================
# import_registry_file — CSV path
# =============================================================================

def test_import_csv_basic_happy_path(tmp_path: Path) -> None:
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name", "synthetic_owner_upn"],
        ["Contoso Expense Advisor",      "advisor@contoso.com"],
    ])
    rows, warnings = ire.import_registry_file(
        str(path), _MINIMAL_ALIASES, _MINIMAL_REQUIRED, None, None
    )
    assert len(rows) == 1
    assert rows[0]["fsi_agentname"] == "Contoso Expense Advisor"
    assert rows[0]["fsi_ownerupn"] == "advisor@contoso.com"


def test_import_csv_alias_remap_correctness(tmp_path: Path) -> None:
    """Non-standard export headers are correctly mapped via the alias JSON."""
    path = _write_csv(tmp_path, [
        ["Agent Display Name",  "Owner Email"],
        ["Northwind Support Bot", "user@northwind.com"],
    ])
    aliases = {
        "agent display name": "agent_name",
        "owner email":        "owner_upn",
    }
    rows, warnings = ire.import_registry_file(
        str(path), aliases, frozenset({"agent_name", "owner_upn"}), None, None
    )
    assert len(rows) == 1
    assert rows[0]["fsi_ownerupn"] == "user@northwind.com"
    assert rows[0]["fsi_agentname"] == "Northwind Support Bot"


def test_import_csv_unmapped_required_column_raises_value_error(
    tmp_path: Path,
) -> None:
    """Missing required column after alias mapping must hard-fail with ValueError."""
    path = _write_csv(tmp_path, [
        ["agent_name"],      # owner_upn column is entirely absent
        ["Northwind Bot"],
    ])
    with pytest.raises(ValueError, match="missing required fields after header mapping"):
        ire.import_registry_file(
            str(path), {}, frozenset({"agent_name", "owner_upn"}), None, None
        )


def test_import_csv_header_diff_error_names_the_missing_field(tmp_path: Path) -> None:
    """The hard-fail ValueError must name the missing field for actionable diagnosis."""
    path = _write_csv(tmp_path, [
        ["agent_name"],
        ["Northwind Bot"],
    ])
    with pytest.raises(ValueError) as exc_info:
        ire.import_registry_file(
            str(path), {}, frozenset({"owner_upn"}), None, None
        )
    assert "owner_upn" in str(exc_info.value)


def test_import_csv_missing_owner_upn_value_sets_unmatched(tmp_path: Path) -> None:
    """A row with an empty owner_upn cell must get fsi_ownermatchconfidence='Unmatched'."""
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name", "synthetic_owner_upn"],
        ["Contoso Bot",                  ""],   # deliberately empty
    ])
    rows, warnings = ire.import_registry_file(
        str(path), _MINIMAL_ALIASES, frozenset({"agent_name"}), None, None
    )
    assert rows[0]["fsi_ownermatchconfidence"] == "Unmatched"


def test_import_csv_absent_owner_column_sets_unmatched(tmp_path: Path) -> None:
    """When the owner_upn column is not present at all, confidence is 'Unmatched'."""
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name"],
        ["Contoso Bot"],
    ])
    aliases = {"synthetic_agent_display_name": "agent_name"}
    rows, warnings = ire.import_registry_file(
        str(path), aliases, frozenset({"agent_name"}), None, None
    )
    assert rows[0]["fsi_ownermatchconfidence"] == "Unmatched"


def test_import_csv_upn_only_sets_heuristic_confidence(tmp_path: Path) -> None:
    """UPN present but NO owner object ID => 'Heuristic' (not 'Exact').
    'Exact' is reserved for rows where a stable Entra object GUID (fsi_ownerid /
    owner_id canonical field) is present in the export."""
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name", "synthetic_owner_upn"],
        ["Contoso Bot",                  "owner@contoso.com"],
    ])
    rows, warnings = ire.import_registry_file(
        str(path), _MINIMAL_ALIASES, _MINIMAL_REQUIRED, None, None
    )
    assert rows[0]["fsi_ownermatchconfidence"] == "Heuristic"


def test_import_csv_owner_id_present_sets_exact_confidence(tmp_path: Path) -> None:
    """When a stable owner object ID (Entra GUID) is present in the export,
    fsi_ownermatchconfidence must be 'Exact' — the strongest confidence level."""
    aliases_with_id = {
        "synthetic_agent_display_name": "agent_name",
        "synthetic_owner_upn": "owner_upn",
        "synthetic_owner_id": "owner_id",
    }
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name", "synthetic_owner_upn", "synthetic_owner_id"],
        ["Contoso Bot", "owner@contoso.com", "a1b2c3d4-e5f6-0000-0000-contoso00001"],
    ])
    rows, warnings = ire.import_registry_file(
        str(path),
        aliases_with_id,
        frozenset({"agent_name", "owner_upn"}),
        None,
        None,
    )
    assert rows[0]["fsi_ownermatchconfidence"] == "Exact"
    assert rows[0].get("fsi_ownerid") == "a1b2c3d4-e5f6-0000-0000-contoso00001"


def test_import_csv_owner_source_is_always_agent_registry_export(
    tmp_path: Path,
) -> None:
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name"],
        ["Northwind Bot"],
        ["Contoso Bot"],
    ])
    aliases = {"synthetic_agent_display_name": "agent_name"}
    rows, warnings = ire.import_registry_file(
        str(path), aliases, frozenset({"agent_name"}), None, None
    )
    assert len(rows) == 2
    for row in rows:
        assert row["fsi_ownersource"] == ire.OWNER_SOURCE_LABEL
        assert row["fsi_ownersource"] == "Agent Registry Export"


def test_import_csv_as_of_stamped_on_every_row(tmp_path: Path) -> None:
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name"],
        ["Bot A"],
        ["Bot B"],
    ])
    aliases = {"synthetic_agent_display_name": "agent_name"}
    as_of = "2026-07-20T18:00:00Z"
    rows, warnings = ire.import_registry_file(
        str(path), aliases, frozenset({"agent_name"}), None, as_of
    )
    assert len(rows) == 2
    assert all(r.get("fsi_ownerasofdatetime") == as_of for r in rows)


def test_import_csv_no_as_of_omits_datetime_field(tmp_path: Path) -> None:
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name"],
        ["Bot A"],
    ])
    aliases = {"synthetic_agent_display_name": "agent_name"}
    rows, warnings = ire.import_registry_file(
        str(path), aliases, frozenset({"agent_name"}), None, None
    )
    assert "fsi_ownerasofdatetime" not in rows[0]


def test_import_csv_empty_file_raises_value_error(tmp_path: Path) -> None:
    path = tmp_path / "empty.csv"
    path.write_text("", encoding="utf-8")
    with pytest.raises(ValueError, match="empty"):
        ire.import_registry_file(str(path), {}, frozenset(), None, None)


def test_import_csv_extra_columns_do_not_break_parsing(tmp_path: Path) -> None:
    """Columns beyond the required set are accepted without error."""
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name", "synthetic_owner_upn", "extra_column"],
        ["Contoso Bot",                  "owner@contoso.com",   "extra_value"],
    ])
    rows, warnings = ire.import_registry_file(
        str(path), _MINIMAL_ALIASES, _MINIMAL_REQUIRED, None, None
    )
    assert len(rows) == 1
    assert rows[0]["fsi_agentname"] == "Contoso Bot"


def test_import_csv_bom_safe_utf8_sig_encoding(tmp_path: Path) -> None:
    """M365 CSV exports typically include a UTF-8 BOM; the importer must handle it."""
    path = _write_csv(
        tmp_path,
        [
            ["synthetic_agent_display_name", "synthetic_owner_upn"],
            ["Contoso Bot",                  "bom-user@contoso.com"],
        ],
        encoding="utf-8-sig",  # explicit BOM
    )
    rows, warnings = ire.import_registry_file(
        str(path), _MINIMAL_ALIASES, _MINIMAL_REQUIRED, None, None
    )
    assert rows[0]["fsi_agentname"] == "Contoso Bot"


# =============================================================================
# import_registry_file — XLSX path (mocked _rows_from_xlsx)
# =============================================================================

def test_import_xlsx_happy_path_via_mocked_rows(tmp_path: Path) -> None:
    """XLSX code path is exercised by mocking _rows_from_xlsx — openpyxl is not
    required as a test dependency. Verifies format detection, alias mapping, and
    owner confidence tagging all work correctly for the XLSX branch."""
    xlsx_path = str(tmp_path / "export.xlsx")

    synthetic_rows: list[list] = [
        ["synthetic_agent_display_name", "synthetic_owner_upn"],
        ["Contoso Advisor Bot",          "owner@contoso.com"],
    ]
    with patch.object(ire, "_rows_from_xlsx", return_value=synthetic_rows) as mock_xl:
        rows, warnings = ire.import_registry_file(
            xlsx_path,
            _MINIMAL_ALIASES,
            _MINIMAL_REQUIRED,
            sheet_name=None,
            as_of="2026-07-20T18:00:00Z",
        )

    mock_xl.assert_called_once_with(xlsx_path, None)
    assert len(rows) == 1
    assert rows[0]["fsi_agentname"] == "Contoso Advisor Bot"
    assert rows[0]["fsi_ownerupn"] == "owner@contoso.com"
    assert rows[0]["fsi_ownermatchconfidence"] == "Heuristic"
    assert rows[0]["fsi_ownerasofdatetime"] == "2026-07-20T18:00:00Z"


def test_import_xlsx_sheet_name_passed_to_rows_from_xlsx(tmp_path: Path) -> None:
    """When a sheet_name is specified in the column-map, it must be forwarded."""
    xlsx_path = str(tmp_path / "multisheet.xlsx")
    synthetic_rows: list[list] = [
        ["synthetic_agent_display_name"],
        ["Bot on Named Sheet"],
    ]
    with patch.object(ire, "_rows_from_xlsx", return_value=synthetic_rows) as mock_xl:
        rows, warnings = ire.import_registry_file(
            xlsx_path,
            {"synthetic_agent_display_name": "agent_name"},
            frozenset({"agent_name"}),
            sheet_name="AgentInventory",
            as_of=None,
        )

    mock_xl.assert_called_once_with(xlsx_path, "AgentInventory")
    assert rows[0]["fsi_agentname"] == "Bot on Named Sheet"


# =============================================================================
# New regressions — blank rows, date validation, as-of, duplicate alias, UPN hygiene
# =============================================================================

def test_fully_blank_row_is_skipped(tmp_path: Path) -> None:
    """A row where every cell is None or whitespace must be silently skipped.
    Blank rows commonly appear in Excel exports when trailing rows are included."""
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name", "synthetic_owner_upn"],
        ["Contoso Bot",                  "owner@contoso.com"],
        ["",                             ""],     # blank data row
        ["",                             "   "],  # whitespace-only
    ])
    rows, warnings = ire.import_registry_file(
        str(path), _MINIMAL_ALIASES, _MINIMAL_REQUIRED, None, None
    )
    assert len(rows) == 1, (
        f"Expected 1 non-blank row; got {len(rows)}. Blank rows must be skipped."
    )
    assert rows[0]["fsi_agentname"] == "Contoso Bot"


def test_invalid_date_in_row_sets_createdon_null_and_emits_warning(
    tmp_path: Path,
) -> None:
    """An invalid date_created value must not crash the importer.
    The row must be included with fsi_createdon absent (null), and a per-row
    warning must be added to the returned warnings list."""
    aliases = {
        "synthetic_agent_display_name": "agent_name",
        "synthetic_owner_upn":          "owner_upn",
        "synthetic_date_created":        "date_created",
    }
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name", "synthetic_owner_upn", "synthetic_date_created"],
        ["Contoso Bot",                  "owner@contoso.com",    "not-a-date"],
    ])
    rows, warnings = ire.import_registry_file(
        str(path), aliases, frozenset({"agent_name", "owner_upn"}), None, None
    )
    assert len(rows) == 1
    assert "fsi_createdon" not in rows[0], (
        "fsi_createdon must be absent (null) when date_created is invalid"
    )
    assert len(warnings) >= 1, "At least one per-row warning expected for invalid date"
    assert any("date_created" in w or "fsi_createdon" in w for w in warnings), (
        f"Warning must reference date_created or fsi_createdon; got: {warnings}"
    )


def test_parse_iso8601_utc_rejects_invalid_as_of_string() -> None:
    """_parse_iso8601_utc must raise ValueError for non-ISO-8601 strings.
    This underpins the importer CLI's --as-of validation."""
    with pytest.raises(ValueError, match="Invalid ISO-8601"):
        ire._parse_iso8601_utc("not-a-date")

    with pytest.raises(ValueError):
        ire._parse_iso8601_utc("2026-07-20")   # date only — no time component


def test_duplicate_canonical_alias_raises_value_error(tmp_path: Path) -> None:
    """Two distinct raw headers that both alias to the same canonical field must
    raise ValueError — ambiguous mapping is a hard fail, not a silent pick-first."""
    # 'colA' and 'colB' both map to 'owner_upn' via the alias map.
    aliases = {
        "cola": "owner_upn",
        "colb": "owner_upn",
    }
    path = _write_csv(tmp_path, [
        ["colA",    "colB"],
        ["u@c.com", "v@c.com"],
    ])
    with pytest.raises(ValueError, match="[Aa]mbiguous"):
        ire.import_registry_file(
            str(path), aliases, frozenset({"owner_upn"}), None, None
        )


def test_display_name_owner_not_stored_as_upn_sets_unmatched(
    tmp_path: Path,
) -> None:
    """A display name (no '@') must NOT be stored as fsi_ownerupn.
    Without a UPN-shaped value AND without an owner_id, the row must be
    confidence='Unmatched' and fsi_ownerupn must be absent from the row dict."""
    path = _write_csv(tmp_path, [
        ["synthetic_agent_display_name", "synthetic_owner_upn"],
        ["Contoso Bot",                  "Robin Contoso"],  # display name, no '@'
    ])
    rows, warnings = ire.import_registry_file(
        str(path), _MINIMAL_ALIASES, _MINIMAL_REQUIRED, None, None
    )
    assert len(rows) == 1
    assert "fsi_ownerupn" not in rows[0], (
        "A display-name-only value must NOT be stored as fsi_ownerupn"
    )
    assert rows[0]["fsi_ownermatchconfidence"] == "Unmatched"
