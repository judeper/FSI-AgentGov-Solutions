"""Targeted tests for lab-validation evidence image publishing in build-manifest.py.

These cover the reusable foundation added for the copilot-agent-inventory lab
report work: binary-safe PNG publishing plus write/`--check` validation of the
`<slug>/docs/lab-validation-evidence.json` contract. The build script is loaded
by path because its filename contains a hyphen (not an importable module name),
mirroring scripts/tests/test_docs_autonomy_protection.py.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import struct
import zlib
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]

# 8-byte PNG signature.
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _png_chunk(ctype: bytes, data: bytes) -> bytes:
    return (
        len(data).to_bytes(4, "big")
        + ctype
        + data
        + (zlib.crc32(ctype + data) & 0xFFFFFFFF).to_bytes(4, "big")
    )


def make_valid_png(width: int = 1, height: int = 1, fill: int = 0) -> bytes:
    """Build a structurally valid 8-bit grayscale PNG with correct CRCs.

    Deterministic and dependency-free (stdlib zlib). Varying ``fill`` yields a
    different byte payload (and SHA-256), useful for mutation tests.
    """
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes([fill]) * width for _ in range(height))
    return (
        PNG_SIGNATURE
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", zlib.compress(raw))
        + _png_chunk(b"IEND", b"")
    )


# A structurally valid PNG. Its first byte (0x89) is not a valid UTF-8 start,
# so successful validation also proves the source is read as bytes, not text.
PNG_BYTES = make_valid_png()


def load_build_manifest():
    """Load scripts/build-manifest.py as a module (hyphenated filename)."""
    path = ROOT / "scripts" / "build-manifest.py"
    spec = importlib.util.spec_from_file_location("build_manifest_under_test", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bm = load_build_manifest()


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _write_png(base: Path, rel: str, data: bytes = PNG_BYTES) -> Path:
    dest = base / "docs" / "img" / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    return dest


def _image_entry(rel: str, sha: str, **overrides) -> dict:
    entry = {
        "path": rel,
        "sha256": sha,
        "sourceClass": "portal-screenshot",
        "capturedUtc": "2026-07-21T10:00:00Z",
        "caption": "Discovery summary",
        "alt": "Discovery summary screenshot",
    }
    entry.update(overrides)
    return entry


def _write_manifest(base: Path, images: list[dict], **top) -> dict:
    payload = {"schemaVersion": "1.0.0", "images": images}
    payload.update(top)
    (base / "docs").mkdir(parents=True, exist_ok=True)
    (base / "docs" / bm.LAB_EVIDENCE_MANIFEST_NAME).write_text(
        json.dumps(payload, indent=2), encoding="utf-8"
    )
    return payload


def _solution(tmp_path: Path, slug: str = "copilot-agent-inventory") -> Path:
    base = tmp_path / slug
    base.mkdir(parents=True, exist_ok=True)
    return base


# ---------------------------------------------------------------------------
# Valid path: validation + binary publish
# ---------------------------------------------------------------------------
def test_valid_evidence_passes_validation_and_publishes_identical_bytes(tmp_path):
    base = _solution(tmp_path)
    _write_png(base, "lab-validation/discovery.png")
    evidence = _write_manifest(
        base,
        [_image_entry("lab-validation/discovery.png", _sha256(PNG_BYTES))],
        solution="copilot-agent-inventory",
    )

    assert bm.validate_lab_evidence("copilot-agent-inventory", base, evidence) == []

    dest = tmp_path / "site" / "copilot-agent-inventory"
    published = bm.publish_lab_images(
        "copilot-agent-inventory", base, dest, dest.parent, evidence
    )

    assert len(published) == 1
    out = dest / "img" / "lab-validation" / "discovery.png"
    assert out.is_file()
    # Byte-for-byte identical; metadata-stripped bytes are not altered.
    assert out.read_bytes() == PNG_BYTES


def test_check_mode_validates_source_and_hash_reading_bytes_not_text(tmp_path):
    # The PNG signature byte is invalid UTF-8; if validation read it as text it
    # would raise. A clean pass proves the source+hash contract is byte-based.
    with pytest.raises(UnicodeDecodeError):
        PNG_BYTES.decode("utf-8")

    base = _solution(tmp_path)
    _write_png(base, "portal.png")
    evidence = _write_manifest(base, [_image_entry("portal.png", _sha256(PNG_BYTES))])

    assert bm.validate_lab_evidence("copilot-agent-inventory", base, evidence) == []


# ---------------------------------------------------------------------------
# Negative cases
# ---------------------------------------------------------------------------
def test_wrong_hash_reports_error(tmp_path):
    base = _solution(tmp_path)
    _write_png(base, "portal.png")
    evidence = _write_manifest(base, [_image_entry("portal.png", "0" * 64)])

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("sha256 mismatch" in e for e in errors)


def test_missing_image_reports_error(tmp_path):
    base = _solution(tmp_path)
    (base / "docs" / "img").mkdir(parents=True)
    evidence = _write_manifest(base, [_image_entry("missing.png", _sha256(PNG_BYTES))])

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("source image not found" in e for e in errors)


@pytest.mark.parametrize(
    "field,value",
    [
        ("notes", "Owner alex.smith@contoso.com"),
        ("caption", "Tenant 123e4567-e89b-12d3-a456-426614174000"),
        ("alt", "Environment https://contoso.crm.dynamics.com"),
        ("caption", "client_secret=example-secret"),
        ("path", "123e4567-e89b-12d3-a456-426614174000.png"),
    ],
)
def test_sensitive_manifest_text_is_rejected(tmp_path, field, value):
    base = _solution(tmp_path)
    _write_png(base, "portal.png")
    entry = _image_entry("portal.png", _sha256(PNG_BYTES))
    top = {}
    if field == "notes":
        top[field] = value
    else:
        entry[field] = value
    evidence = _write_manifest(base, [entry], **top)

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("contains a sensitive" in error for error in errors)


def test_is_reparse_point_recognizes_junction_api():
    class JunctionLike:
        @staticmethod
        def is_symlink():
            return False

        @staticmethod
        def is_junction():
            return True

    assert bm._is_reparse_point(JunctionLike()) is True


def test_symlinked_image_root_outside_solution_is_rejected(tmp_path):
    base = _solution(tmp_path)
    docs = base / "docs"
    docs.mkdir()
    outside = tmp_path / "outside-images"
    outside.mkdir()
    (outside / "portal.png").write_bytes(PNG_BYTES)
    try:
        (docs / "img").symlink_to(outside, target_is_directory=True)
    except OSError as exc:
        pytest.skip(f"directory symlinks unavailable: {exc}")
    evidence = _write_manifest(
        base, [_image_entry("portal.png", _sha256(PNG_BYTES))]
    )

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("docs/img resolves outside" in error for error in errors)
    with pytest.raises(bm.LabEvidenceError, match="image root resolves outside"):
        bm.publish_lab_images(
            "copilot-agent-inventory",
            base,
            tmp_path / "site" / "copilot-agent-inventory",
            tmp_path / "site",
            evidence,
        )


def test_generated_destination_symlink_is_rejected(tmp_path):
    base = _solution(tmp_path)
    _write_png(base, "portal.png")
    evidence = _write_manifest(
        base, [_image_entry("portal.png", _sha256(PNG_BYTES))]
    )
    trusted_dest_root = tmp_path / "site"
    trusted_dest_root.mkdir()
    outside = tmp_path / "outside-site"
    outside.mkdir()
    dest = trusted_dest_root / "copilot-agent-inventory"
    try:
        dest.symlink_to(outside, target_is_directory=True)
    except OSError as exc:
        pytest.skip(f"directory symlinks unavailable: {exc}")

    with pytest.raises(bm.LabEvidenceError, match="reparse point"):
        bm.publish_lab_images(
            "copilot-agent-inventory",
            base,
            dest,
            trusted_dest_root,
            evidence,
        )


def test_duplicate_manifest_path_reports_error(tmp_path):
    base = _solution(tmp_path)
    _write_png(base, "portal.png")
    sha = _sha256(PNG_BYTES)
    evidence = _write_manifest(
        base,
        [_image_entry("portal.png", sha), _image_entry("portal.png", sha)],
    )

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("duplicate image path" in e for e in errors)


@pytest.mark.parametrize(
    "bad_path",
    [
        "/etc/passwd.png",
        "C:/Windows/system32/x.png",
        "..\\outside.png",
        "../outside.png",
        "sub/../../escape.png",
    ],
)
def test_traversal_or_absolute_path_reports_error(tmp_path, bad_path):
    base = _solution(tmp_path)
    (base / "docs" / "img").mkdir(parents=True)
    evidence = _write_manifest(base, [_image_entry(bad_path, _sha256(PNG_BYTES))])

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert errors, f"expected a path error for {bad_path!r}"
    assert any("must be relative" in e or "'.' or '..'" in e or "forward slashes" in e
               or "resolves outside" in e for e in errors)


def test_non_png_path_reports_error(tmp_path):
    base = _solution(tmp_path)
    (base / "docs" / "img").mkdir(parents=True)
    (base / "docs" / "img" / "portal.jpg").write_bytes(PNG_BYTES)
    evidence = _write_manifest(base, [_image_entry("portal.jpg", _sha256(PNG_BYTES))])

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any(".png" in e and "must reference" in e for e in errors)


def test_non_png_bytes_renamed_png_is_rejected(tmp_path):
    # A file with a .png name but non-PNG bytes must be rejected by signature,
    # not merely accepted because the extension and hash line up.
    base = _solution(tmp_path)
    fake = b"GIF89a this is not a real png payload"
    (base / "docs" / "img").mkdir(parents=True)
    (base / "docs" / "img" / "spoof.png").write_bytes(fake)
    evidence = _write_manifest(base, [_image_entry("spoof.png", _sha256(fake))])

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("missing PNG signature" in e for e in errors)
    # Hash matched, so the failure must come from the signature check only.
    assert not any("sha256 mismatch" in e for e in errors)


def test_case_insensitive_path_collision_is_rejected(tmp_path):
    base = _solution(tmp_path)
    _write_png(base, "Alpha.png")  # only one real file on disk
    sha = _sha256(PNG_BYTES)
    evidence = _write_manifest(
        base,
        [_image_entry("Alpha.png", sha), _image_entry("alpha.png", sha)],
    )

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("collides case-insensitively" in e for e in errors)
    assert not any("unmanifested" in e for e in errors)


# ---------------------------------------------------------------------------
# Structural PNG validation (signature-prefixed malformed data must be rejected)
# ---------------------------------------------------------------------------
def _corrupt_ihdr_crc(png: bytes) -> bytes:
    # IHDR CRC occupies the 4 bytes at offset 8 (sig) + 4 (len) + 4 (type) + 13.
    crc_pos = 8 + 4 + 4 + 13
    mutable = bytearray(png)
    mutable[crc_pos] ^= 0xFF
    return bytes(mutable)


def _zero_dimension_png() -> bytes:
    ihdr = struct.pack(">IIBBBBB", 0, 1, 8, 0, 0, 0, 0)
    return PNG_SIGNATURE + _png_chunk(b"IHDR", ihdr) + _png_chunk(b"IEND", b"")


def _ihdr(
    color_type: int = 0,
    bit_depth: int = 8,
    width: int = 1,
    height: int = 1,
    interlace: int = 0,
) -> bytes:
    return _png_chunk(
        b"IHDR",
        struct.pack(
            ">IIBBBBB", width, height, bit_depth, color_type, 0, 0, interlace
        ),
    )


def _png(*chunks: bytes) -> bytes:
    return PNG_SIGNATURE + b"".join(chunks)


def _idat(
    color_type: int = 0,
    bit_depth: int = 8,
    width: int = 1,
    height: int = 1,
    filter_type: int = 0,
) -> bytes:
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    row_bytes = (width * channels * bit_depth + 7) // 8
    raw = b"".join(
        bytes([filter_type]) + (b"\x00" * row_bytes)
        for _ in range(height)
    )
    return _png_chunk(b"IDAT", zlib.compress(raw))


_IDAT = _idat()
_IEND = _png_chunk(b"IEND", b"")
_PLTE = _png_chunk(b"PLTE", b"\x00\x00\x00")


@pytest.mark.parametrize(
    "payload, expected",
    [
        (PNG_SIGNATURE, "no IHDR"),
        (PNG_SIGNATURE + b"\x00\x00\x00\x05IHDR", "truncated"),
        (PNG_BYTES[:-4], "truncated"),
        (_corrupt_ihdr_crc(PNG_BYTES), "CRC mismatch"),
        (PNG_BYTES + b"\x00", "trailing bytes"),
        (_zero_dimension_png(), "dimensions must be positive"),
        (PNG_SIGNATURE + _png_chunk(b"IEND", b""), "first chunk must be IHDR"),
        (b"not even close", "missing PNG signature"),
        # Critical-chunk tightening (blocker): non-renderable structures.
        (_png(_ihdr(), _IEND), "no IDAT"),
        (_png(_ihdr(), _ihdr(), _IDAT, _IEND), "duplicate IHDR"),
        (_png(_ihdr(), _png_chunk(b"ABCD", b""), _IDAT, _IEND), "unknown critical chunk"),
        (_png(_ihdr(), _png_chunk(b"12Ab", b""), _IDAT, _IEND), "invalid chunk type bytes"),
        (_png(_ihdr(color_type=0), _PLTE, _IDAT, _IEND), "PLTE prohibited"),
        (_png(_ihdr(color_type=2), _IDAT, _PLTE, _IEND), "PLTE must appear before IDAT"),
        (_png(_ihdr(), _IDAT, _png_chunk(b"tEXt", b"k\x00v"), _IDAT, _IEND),
         "IDAT chunks must be consecutive"),
        (_png(_ihdr(color_type=3), _IDAT, _IEND), "PLTE required for indexed"),
        (_png(_ihdr(), _png_chunk(b"IDAT", b"not-zlib"), _IEND),
         "not a valid zlib stream"),
        (_png(_ihdr(), _png_chunk(b"IDAT", zlib.compress(b"\x00")), _IEND),
         "length does not match"),
        (_png(_ihdr(), _idat(filter_type=5), _IEND), "invalid PNG scanline filter"),
        (_png(
            _ihdr(color_type=3, bit_depth=1),
            _png_chunk(b"PLTE", b"\x00\x00\x00" * 3),
            _idat(color_type=3, bit_depth=1),
            _IEND,
        ), "too many entries"),
        (_png(
            _ihdr(color_type=3, bit_depth=1),
            _PLTE,
            _png_chunk(b"IDAT", zlib.compress(b"\x00\x80")),
            _IEND,
        ), "pixel references a missing PLTE entry"),
        (_png(
            _ihdr(color_type=2),
            _png_chunk(b"PLTE", b"\x00\x00\x00" * 257),
            _idat(color_type=2),
            _IEND,
        ), "more than 256"),
    ],
)
def test_validate_png_structure_rejects_malformed(payload, expected):
    result = bm._validate_png_structure(payload)
    assert result is not None and expected in result
    # A genuine PNG passes.
    assert bm._validate_png_structure(PNG_BYTES) is None


@pytest.mark.parametrize(
    "payload",
    [
        _png(_ihdr(color_type=0), _IDAT, _IEND),  # minimal grayscale
        _png(_ihdr(color_type=3), _PLTE, _idat(color_type=3), _IEND),
        _png(_ihdr(color_type=2), _PLTE, _idat(color_type=2), _IEND),
        _png(_ihdr(color_type=0), _png_chunk(b"tEXt", b"k\x00v"), _IDAT, _IEND),  # ancillary ok
        _png(_ihdr(interlace=1), _IDAT, _IEND),  # 1x1 Adam7
    ],
)
def test_validate_png_structure_accepts_valid_variants(payload):
    assert bm._validate_png_structure(payload) is None


def test_validate_png_structure_rejects_oversized_source(monkeypatch):
    monkeypatch.setattr(bm, "MAX_LAB_PNG_BYTES", len(PNG_BYTES) - 1)
    assert "64 MiB evidence limit" in bm._validate_png_structure(PNG_BYTES)


def test_minimal_ihdr_iend_without_idat_is_rejected_by_validate(tmp_path):
    # The reported blocker: IHDR + IEND with no IDAT is not renderable and must
    # not be publishable as evidence.
    base = _solution(tmp_path)
    non_renderable = _png(_ihdr(), _IEND)
    (base / "docs" / "img").mkdir(parents=True)
    (base / "docs" / "img" / "empty.png").write_bytes(non_renderable)
    evidence = _write_manifest(base, [_image_entry("empty.png", _sha256(non_renderable))])

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("not a valid PNG" in e and "no IDAT" in e for e in errors)
    assert not any("sha256 mismatch" in e for e in errors)


def test_signature_prefixed_malformed_png_rejected_by_validate(tmp_path):
    # Bytes that carry the PNG signature but are otherwise malformed/truncated
    # must fail validation even though the extension and signature look right.
    base = _solution(tmp_path)
    malformed = PNG_BYTES[:-4]  # drop the IEND CRC -> truncated
    (base / "docs" / "img").mkdir(parents=True)
    (base / "docs" / "img" / "broken.png").write_bytes(malformed)
    evidence = _write_manifest(base, [_image_entry("broken.png", _sha256(malformed))])

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("not a valid PNG" in e for e in errors)
    assert not any("sha256 mismatch" in e for e in errors)


def test_unmanifested_png_reports_error(tmp_path):
    base = _solution(tmp_path)
    _write_png(base, "listed.png")
    _write_png(base, "rogue.png")  # present on disk, not in the manifest
    evidence = _write_manifest(base, [_image_entry("listed.png", _sha256(PNG_BYTES))])

    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("unmanifested PNG" in e and "rogue.png" in e for e in errors)


def test_schema_shape_violation_reports_error(tmp_path):
    base = _solution(tmp_path)
    _write_png(base, "portal.png")
    # Missing required 'alt' and wrong schemaVersion.
    payload = {
        "schemaVersion": "9.9.9",
        "images": [
            {
                "path": "portal.png",
                "sha256": _sha256(PNG_BYTES),
                "sourceClass": "portal-screenshot",
                "capturedUtc": "2026-07-21T10:00:00Z",
                "caption": "x",
            }
        ],
    }
    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, payload)
    assert any("schema error" in e for e in errors)


def test_captured_utc_must_be_utc(tmp_path):
    base = _solution(tmp_path)
    _write_png(base, "portal.png")
    evidence = _write_manifest(
        base,
        [_image_entry("portal.png", _sha256(PNG_BYTES), capturedUtc="2026-07-21T10:00:00+05:00")],
    )
    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("capturedUtc" in e and "UTC" in e for e in errors)


def test_solution_field_must_match_slug(tmp_path):
    base = _solution(tmp_path)
    _write_png(base, "portal.png")
    evidence = _write_manifest(
        base,
        [_image_entry("portal.png", _sha256(PNG_BYTES))],
        solution="some-other-solution",
    )
    errors = bm.validate_lab_evidence("copilot-agent-inventory", base, evidence)
    assert any("must equal folder name" in e for e in errors)


def test_invalid_json_reports_parse_error():
    errors = bm.validate_lab_evidence(
        "copilot-agent-inventory", ROOT, {"__parse_error__": "boom"}
    )
    assert errors and "invalid JSON" in errors[0]


# ---------------------------------------------------------------------------
# Publish cleanup / stale image removal
# ---------------------------------------------------------------------------
def test_publish_removes_stale_generated_images(tmp_path):
    base = _solution(tmp_path)
    _write_png(base, "current.png")
    evidence = _write_manifest(base, [_image_entry("current.png", _sha256(PNG_BYTES))])

    dest = tmp_path / "site" / "copilot-agent-inventory"
    stale = dest / "img" / "old" / "stale.png"
    stale.parent.mkdir(parents=True)
    stale.write_bytes(b"stale-bytes")

    bm.publish_lab_images(
        "copilot-agent-inventory", base, dest, dest.parent, evidence
    )

    assert not stale.exists()
    assert (dest / "img" / "current.png").is_file()
    assert list((dest / "img").rglob("*.png")) == [dest / "img" / "current.png"]


def test_removing_manifest_cleans_up_published_images(tmp_path):
    # Publish, then simulate the evidence manifest being deleted: the publisher
    # owns the generated img subtree and must remove it so no stale image lingers.
    base = _solution(tmp_path)
    _write_png(base, "discovery.png")
    evidence = _write_manifest(base, [_image_entry("discovery.png", _sha256(PNG_BYTES))])

    dest = tmp_path / "site" / "copilot-agent-inventory"
    bm.publish_lab_images(
        "copilot-agent-inventory", base, dest, dest.parent, evidence
    )
    assert (dest / "img" / "discovery.png").is_file()

    assert bm.remove_published_lab_images(dest, dest.parent) is True
    assert not (dest / "img").exists()
    # Idempotent when there is nothing to remove.
    assert bm.remove_published_lab_images(dest, dest.parent) is False


def test_publish_fails_on_source_mutation_after_validation(tmp_path):
    # TOCTOU: source validates, then changes before publish. Publish must fail
    # and must NOT leave a mismatched destination byte behind.
    base = _solution(tmp_path)
    source = _write_png(base, "discovery.png")
    evidence = _write_manifest(base, [_image_entry("discovery.png", _sha256(PNG_BYTES))])

    assert bm.validate_lab_evidence("copilot-agent-inventory", base, evidence) == []

    mutated = make_valid_png(fill=255)
    assert mutated != PNG_BYTES
    source.write_bytes(mutated)  # source changes after validation

    dest = tmp_path / "site" / "copilot-agent-inventory"
    with pytest.raises(bm.LabEvidenceError):
        bm.publish_lab_images(
            "copilot-agent-inventory", base, dest, dest.parent, evidence
        )

    # No mismatched destination was written.
    assert not (dest / "img" / "discovery.png").exists()


def test_publish_fails_when_source_becomes_structurally_invalid(tmp_path):
    base = _solution(tmp_path)
    source = _write_png(base, "discovery.png")
    evidence = _write_manifest(base, [_image_entry("discovery.png", _sha256(PNG_BYTES))])
    assert bm.validate_lab_evidence("copilot-agent-inventory", base, evidence) == []

    source.write_bytes(PNG_BYTES[:-4])  # truncate -> structurally invalid

    dest = tmp_path / "site" / "copilot-agent-inventory"
    with pytest.raises(bm.LabEvidenceError):
        bm.publish_lab_images(
            "copilot-agent-inventory", base, dest, dest.parent, evidence
        )
    assert not (dest / "img" / "discovery.png").exists()


# ---------------------------------------------------------------------------
# No-manifest solutions are unaffected
# ---------------------------------------------------------------------------
def test_no_manifest_solution_is_unaffected():
    # copilot-agent-inventory ships no committed evidence manifest yet.
    assert bm.load_lab_evidence("copilot-agent-inventory") is None


def test_load_lab_evidence_returns_none_for_missing(tmp_path, monkeypatch):
    monkeypatch.setattr(bm, "ROOT", tmp_path)
    (tmp_path / "some-solution" / "docs").mkdir(parents=True)
    assert bm.load_lab_evidence("some-solution") is None


# ---------------------------------------------------------------------------
# Regression: PNG bytes never flow through the text comparison helpers
# ---------------------------------------------------------------------------
def test_png_bytes_never_flow_through_text_helpers(tmp_path, monkeypatch):
    calls: list[str] = []

    def spy_write(path, content, drift):  # pragma: no cover - should not run
        calls.append(f"write:{path}")

    def spy_check(path, content, drift):  # pragma: no cover - should not run
        calls.append(f"check:{path}")

    monkeypatch.setattr(bm, "write_if_changed", spy_write)
    monkeypatch.setattr(bm, "check_only", spy_check)

    base = _solution(tmp_path)
    _write_png(base, "lab-validation/discovery.png")
    evidence = _write_manifest(
        base, [_image_entry("lab-validation/discovery.png", _sha256(PNG_BYTES))]
    )

    # Validation + publish is the entire image code path.
    assert bm.validate_lab_evidence("copilot-agent-inventory", base, evidence) == []
    dest = tmp_path / "site" / "copilot-agent-inventory"
    bm.publish_lab_images(
        "copilot-agent-inventory", base, dest, dest.parent, evidence
    )

    assert calls == [], f"image bytes must not pass through text helpers: {calls}"
    assert (dest / "img" / "lab-validation" / "discovery.png").read_bytes() == PNG_BYTES
