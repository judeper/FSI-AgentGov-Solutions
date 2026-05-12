#!/usr/bin/env python3
"""MIME type parser validation tests.

Tests cover the file-signature taxonomy used by the MIME Type Restrictions
solution (Control 1.25). These tests validate the magic-byte parsing logic
that the Dataverse plugin (ValidateMimeTypePlugin.cs) and the mime-config.json
configuration both rely on.

Framework: pytest
"""

import struct
from typing import Optional

import pytest


# ---------------------------------------------------------------------------
# Minimal parser implementation (mirrors plugin logic for testability)
# ---------------------------------------------------------------------------


def parse_magic_bytes(hex_string: str) -> bytes:
    """Parse a space-separated hex string into bytes.

    Mirrors ValidateMimeTypePlugin.ParseHexString.
    """
    if not hex_string or not hex_string.strip():
        return b""
    parts = hex_string.strip().split()
    return bytes(int(part, 16) for part in parts)


def starts_with_bytes(data: bytes, signature: bytes) -> bool:
    """Check if data starts with the given signature bytes."""
    if len(data) < len(signature):
        return False
    return data[: len(signature)] == signature


def validate_mime_signature(
    file_bytes: bytes,
    declared_mime: str,
    allowed_types: list[dict],
) -> tuple[bool, str]:
    """Validate file bytes against declared MIME type's magic signature.

    Returns:
        (is_valid, reason)
    """
    if len(file_bytes) == 0:
        return False, "Empty file"

    entry = None
    for t in allowed_types:
        if t["mimeType"].lower() == declared_mime.lower():
            entry = t
            break

    if entry is None:
        return False, f"MIME type '{declared_mime}' not in allowlist"

    magic = entry.get("magicBytes")
    if magic is None:
        return True, "No magic bytes defined (text-based type)"

    # Handle array of signatures (e.g., TIFF has two)
    if isinstance(magic, list):
        signatures = [parse_magic_bytes(m) for m in magic]
    else:
        signatures = [parse_magic_bytes(magic)]

    signatures = [s for s in signatures if s]
    if not signatures:
        return True, "No parseable signatures"

    for sig in signatures:
        if starts_with_bytes(file_bytes, sig):
            # Special case: WebP needs offset-8 WEBP check
            if declared_mime == "image/webp":
                return validate_webp(file_bytes)
            return True, "Signature match"

    return False, "Magic bytes mismatch"


def validate_webp(file_bytes: bytes) -> tuple[bool, str]:
    """Validate WebP file: RIFF header at offset 0, WEBP at offset 8.

    WebP magic: bytes 0-3 = 'RIFF', bytes 4-7 = file size (LE),
    bytes 8-11 = 'WEBP'.
    """
    if len(file_bytes) < 12:
        return False, "File too short for WebP (need ≥12 bytes)"

    if file_bytes[0:4] != b"RIFF":
        return False, "Missing RIFF header"

    if file_bytes[8:12] != b"WEBP":
        return False, f"RIFF file but not WebP (offset-8 signature: {file_bytes[8:12]!r})"

    return True, "Valid WebP signature"


def detect_animated_gif(file_bytes: bytes) -> bool:
    """Detect animated GIF by checking for NETSCAPE2.0 application extension.

    Animated GIFs contain a Netscape Application Extension block with the
    marker bytes 0x21 0xFF followed by 0x0B and 'NETSCAPE2.0'.
    """
    if len(file_bytes) < 16:
        return False

    # Search for the NETSCAPE2.0 marker
    marker = b"NETSCAPE2.0"
    return marker in file_bytes


def detect_tiff(file_bytes: bytes) -> Optional[str]:
    """Detect TIFF byte order and validate magic number.

    Returns:
        'little-endian', 'big-endian', or None if not TIFF.
    """
    if len(file_bytes) < 4:
        return None

    # Little-endian: II (0x49 0x49) + magic 42 (0x2A 0x00)
    if file_bytes[0:2] == b"II" and file_bytes[2:4] == b"\x2a\x00":
        return "little-endian"

    # Big-endian: MM (0x4D 0x4D) + magic 42 (0x00 0x2A)
    if file_bytes[0:2] == b"MM" and file_bytes[2:4] == b"\x00\x2a":
        return "big-endian"

    return None


# ---------------------------------------------------------------------------
# Allowlist fixture (mirrors mime-config.json Zone 3)
# ---------------------------------------------------------------------------

ZONE3_ALLOWED_TYPES = [
    {
        "mimeType": "application/pdf",
        "extensions": [".pdf"],
        "magicBytes": "25 50 44 46",
        "description": "Portable Document Format",
    },
    {
        "mimeType": "image/png",
        "extensions": [".png"],
        "magicBytes": "89 50 4E 47",
        "description": "Portable Network Graphics",
    },
    {
        "mimeType": "image/jpeg",
        "extensions": [".jpg", ".jpeg"],
        "magicBytes": "FF D8 FF",
        "description": "JPEG image",
    },
    {
        "mimeType": "image/gif",
        "extensions": [".gif"],
        "magicBytes": "47 49 46 38",
        "description": "Graphics Interchange Format",
    },
    {
        "mimeType": "image/webp",
        "extensions": [".webp"],
        "magicBytes": "52 49 46 46",
        "description": "WebP image (RIFF container with WEBP signature at offset 8)",
    },
    {
        "mimeType": "text/plain",
        "extensions": [".txt"],
        "magicBytes": None,
        "description": "Plain text",
    },
    {
        "mimeType": "text/csv",
        "extensions": [".csv"],
        "magicBytes": None,
        "description": "Comma-separated values",
    },
]


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def webp_valid_bytes() -> bytes:
    """Valid minimal WebP file header."""
    # RIFF + 4-byte file size (LE) + WEBP + VP8 chunk header
    return b"RIFF" + struct.pack("<I", 100) + b"WEBP" + b"VP8 "


@pytest.fixture
def wav_riff_bytes() -> bytes:
    """WAV file that starts with RIFF but has WAVE at offset 8."""
    return b"RIFF" + struct.pack("<I", 100) + b"WAVE" + b"fmt "


@pytest.fixture
def avi_riff_bytes() -> bytes:
    """AVI file that starts with RIFF but has AVI at offset 8."""
    return b"RIFF" + struct.pack("<I", 100) + b"AVI " + b"LIST"


@pytest.fixture
def gif87a_bytes() -> bytes:
    """GIF87a header."""
    return b"GIF87a" + b"\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00"


@pytest.fixture
def gif89a_bytes() -> bytes:
    """GIF89a header (non-animated)."""
    return b"GIF89a" + b"\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00"


@pytest.fixture
def gif89a_animated_bytes() -> bytes:
    """GIF89a header with NETSCAPE2.0 application extension (animated)."""
    header = b"GIF89a" + b"\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00"
    # Application extension block: 0x21 0xFF 0x0B + "NETSCAPE2.0"
    netscape_ext = b"\x21\xff\x0b" + b"NETSCAPE2.0" + b"\x03\x01\x00\x00\x00"
    return header + netscape_ext


@pytest.fixture
def tiff_little_endian_bytes() -> bytes:
    """TIFF little-endian (II) header."""
    return b"II\x2a\x00" + b"\x08\x00\x00\x00" + b"\x00" * 50


@pytest.fixture
def tiff_big_endian_bytes() -> bytes:
    """TIFF big-endian (MM) header."""
    return b"MM\x00\x2a" + b"\x00\x00\x00\x08" + b"\x00" * 50


@pytest.fixture
def pdf_bytes() -> bytes:
    """Minimal PDF header."""
    return b"%PDF-1.4\n1 0 obj\n<<\n>>\nendobj\n"


@pytest.fixture
def png_bytes() -> bytes:
    """Minimal PNG header."""
    return b"\x89PNG\r\n\x1a\n" + b"\x00" * 50


@pytest.fixture
def jpeg_bytes() -> bytes:
    """Minimal JPEG header."""
    return b"\xff\xd8\xff\xe0" + b"\x00" * 50


# ---------------------------------------------------------------------------
# WebP RIFF offset-8 validation (H6)
# ---------------------------------------------------------------------------


class TestWebPValidation:
    """WebP RIFF offset-8 signature validation."""

    def test_valid_webp_signature(self, webp_valid_bytes: bytes) -> None:
        """Valid WebP file should pass validation."""
        is_valid, reason = validate_webp(webp_valid_bytes)
        assert is_valid, f"Expected valid WebP, got: {reason}"

    def test_wav_riff_not_webp(self, wav_riff_bytes: bytes) -> None:
        """WAV file (RIFF/WAVE) should NOT match as WebP."""
        is_valid, reason = validate_webp(wav_riff_bytes)
        assert not is_valid
        assert "not WebP" in reason

    def test_avi_riff_not_webp(self, avi_riff_bytes: bytes) -> None:
        """AVI file (RIFF/AVI) should NOT match as WebP."""
        is_valid, reason = validate_webp(avi_riff_bytes)
        assert not is_valid
        assert "not WebP" in reason

    def test_webp_in_allowlist_validation(self, webp_valid_bytes: bytes) -> None:
        """WebP declared as image/webp should pass full allowlist validation."""
        is_valid, reason = validate_mime_signature(
            webp_valid_bytes, "image/webp", ZONE3_ALLOWED_TYPES
        )
        assert is_valid, f"Expected valid, got: {reason}"

    def test_wav_declared_as_webp_fails(self, wav_riff_bytes: bytes) -> None:
        """WAV file declared as image/webp should fail validation."""
        is_valid, reason = validate_mime_signature(
            wav_riff_bytes, "image/webp", ZONE3_ALLOWED_TYPES
        )
        assert not is_valid

    def test_webp_too_short(self) -> None:
        """File shorter than 12 bytes cannot be valid WebP."""
        short = b"RIFF" + b"\x00\x00\x00\x00"  # 8 bytes, missing WEBP
        is_valid, reason = validate_webp(short)
        assert not is_valid
        assert "too short" in reason

    def test_non_riff_not_webp(self) -> None:
        """Arbitrary data should not validate as WebP."""
        is_valid, reason = validate_webp(b"\x00" * 20)
        assert not is_valid


# ---------------------------------------------------------------------------
# TIFF detection (H7/H8)
# ---------------------------------------------------------------------------


class TestTIFFDetection:
    """TIFF magic number detection for both byte orders."""

    def test_tiff_little_endian(self, tiff_little_endian_bytes: bytes) -> None:
        """II\\x2a\\x00 should be detected as little-endian TIFF."""
        result = detect_tiff(tiff_little_endian_bytes)
        assert result == "little-endian"

    def test_tiff_big_endian(self, tiff_big_endian_bytes: bytes) -> None:
        """MM\\x00\\x2a should be detected as big-endian TIFF."""
        result = detect_tiff(tiff_big_endian_bytes)
        assert result == "big-endian"

    def test_non_tiff_returns_none(self, pdf_bytes: bytes) -> None:
        """Non-TIFF data should return None."""
        assert detect_tiff(pdf_bytes) is None

    def test_partial_tiff_header(self) -> None:
        """II without magic number 42 should not match."""
        assert detect_tiff(b"II\x00\x00") is None

    def test_tiff_too_short(self) -> None:
        """Files shorter than 4 bytes cannot be TIFF."""
        assert detect_tiff(b"II") is None
        assert detect_tiff(b"MM\x00") is None
        assert detect_tiff(b"") is None


# ---------------------------------------------------------------------------
# GIF detection (H7/H8)
# ---------------------------------------------------------------------------


class TestGIFDetection:
    """GIF magic number detection including animated GIF."""

    def test_gif87a_magic(self, gif87a_bytes: bytes) -> None:
        """GIF87a signature should match GIF header check."""
        assert starts_with_bytes(gif87a_bytes, b"GIF87a")
        assert starts_with_bytes(gif87a_bytes, parse_magic_bytes("47 49 46 38"))

    def test_gif89a_magic(self, gif89a_bytes: bytes) -> None:
        """GIF89a signature should match GIF header check."""
        assert starts_with_bytes(gif89a_bytes, b"GIF89a")
        assert starts_with_bytes(gif89a_bytes, parse_magic_bytes("47 49 46 38"))

    def test_non_animated_gif(self, gif89a_bytes: bytes) -> None:
        """GIF89a without NETSCAPE2.0 is not animated."""
        assert not detect_animated_gif(gif89a_bytes)

    def test_animated_gif_detection(self, gif89a_animated_bytes: bytes) -> None:
        """GIF89a with NETSCAPE2.0 extension should be detected as animated."""
        assert detect_animated_gif(gif89a_animated_bytes)

    def test_gif87a_not_animated(self, gif87a_bytes: bytes) -> None:
        """GIF87a does not support animation (no NETSCAPE extension)."""
        assert not detect_animated_gif(gif87a_bytes)

    def test_gif_allowlist_validation(self, gif89a_bytes: bytes) -> None:
        """GIF declared as image/gif should pass allowlist validation."""
        is_valid, _ = validate_mime_signature(
            gif89a_bytes, "image/gif", ZONE3_ALLOWED_TYPES
        )
        assert is_valid


# ---------------------------------------------------------------------------
# Edge cases (H8)
# ---------------------------------------------------------------------------


class TestEdgeCases:
    """Edge case handling for the parser."""

    def test_empty_file(self) -> None:
        """Empty file should fail validation for any typed MIME."""
        is_valid, reason = validate_mime_signature(
            b"", "image/png", ZONE3_ALLOWED_TYPES
        )
        assert not is_valid
        assert "Empty file" in reason

    def test_file_shorter_than_12_bytes(self) -> None:
        """File < 12 bytes should fail WebP validation."""
        short = b"RIFF\x00\x00"
        is_valid, reason = validate_mime_signature(
            short, "image/webp", ZONE3_ALLOWED_TYPES
        )
        assert not is_valid

    def test_all_zero_file(self) -> None:
        """All-zero file should not match any typed signature."""
        zeros = b"\x00" * 100
        # Should fail PNG check (expects 0x89 0x50 ...)
        is_valid, _ = validate_mime_signature(zeros, "image/png", ZONE3_ALLOWED_TYPES)
        assert not is_valid

        # Should fail JPEG check
        is_valid, _ = validate_mime_signature(zeros, "image/jpeg", ZONE3_ALLOWED_TYPES)
        assert not is_valid

        # Should fail PDF check
        is_valid, _ = validate_mime_signature(zeros, "application/pdf", ZONE3_ALLOWED_TYPES)
        assert not is_valid

    def test_valid_header_truncated_body(self, png_bytes: bytes) -> None:
        """File with valid header but truncated body should still pass magic check."""
        # Magic bytes only care about the header prefix
        truncated = png_bytes[:8]
        is_valid, _ = validate_mime_signature(
            truncated, "image/png", ZONE3_ALLOWED_TYPES
        )
        assert is_valid  # Parser only checks header, not body integrity

    def test_text_type_no_magic_required(self) -> None:
        """Text types (magicBytes=null) should pass without magic check."""
        text_content = b"Hello, world!\nThis is a test.\n"
        is_valid, reason = validate_mime_signature(
            text_content, "text/plain", ZONE3_ALLOWED_TYPES
        )
        assert is_valid
        assert "No magic bytes" in reason

    def test_unknown_mime_rejected(self) -> None:
        """Unlisted MIME type should be rejected."""
        is_valid, reason = validate_mime_signature(
            b"\x00" * 50, "application/octet-stream", ZONE3_ALLOWED_TYPES
        )
        assert not is_valid
        assert "not in allowlist" in reason


# ---------------------------------------------------------------------------
# parse_magic_bytes utility tests
# ---------------------------------------------------------------------------


class TestParseMagicBytes:
    """Tests for the hex string parser."""

    def test_standard_hex(self) -> None:
        assert parse_magic_bytes("25 50 44 46") == b"%PDF"

    def test_empty_string(self) -> None:
        assert parse_magic_bytes("") == b""

    def test_none_input(self) -> None:
        assert parse_magic_bytes(None) == b""  # type: ignore[arg-type]

    def test_single_byte(self) -> None:
        assert parse_magic_bytes("FF") == b"\xff"

    def test_lowercase_hex(self) -> None:
        assert parse_magic_bytes("ff d8 ff") == b"\xff\xd8\xff"


# ---------------------------------------------------------------------------
# Cross-type mismatch tests
# ---------------------------------------------------------------------------


class TestCrossTypeMismatch:
    """Ensure signature checks reject cross-type mismatches."""

    def test_pdf_declared_as_png(self, pdf_bytes: bytes) -> None:
        """PDF data declared as image/png should fail."""
        is_valid, _ = validate_mime_signature(pdf_bytes, "image/png", ZONE3_ALLOWED_TYPES)
        assert not is_valid

    def test_png_declared_as_pdf(self, png_bytes: bytes) -> None:
        """PNG data declared as application/pdf should fail."""
        is_valid, _ = validate_mime_signature(png_bytes, "application/pdf", ZONE3_ALLOWED_TYPES)
        assert not is_valid

    def test_jpeg_declared_as_gif(self, jpeg_bytes: bytes) -> None:
        """JPEG data declared as image/gif should fail."""
        is_valid, _ = validate_mime_signature(jpeg_bytes, "image/gif", ZONE3_ALLOWED_TYPES)
        assert not is_valid
