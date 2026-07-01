#!/usr/bin/env python3
"""
Shared library for the Agent Cost Reporting solution.

Holds the verified API constants (hosts, endpoints, api-versions), provenance and
integrity helpers (SHA-256, deterministic fact ids, UTC timestamps), and the raw-extract
writer used by every collector. Keeping these in one place lets collectors stay thin and
keeps the cost-fact provenance model consistent across surfaces.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Iterable, Optional

logger = logging.getLogger(__name__)

# Deterministic namespace for fact_id generation (UUIDv5). Do not change once data is in use.
FACT_ID_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_DNS, "agent-cost-reporting.fsi-agentgov")

# ---------------------------------------------------------------------------
# Verified API constants (see docs/api-surface-matrix.md for sources + dates).
# Values flagged PREVIEW/BETA must stay behind feature flags in their collectors.
# ---------------------------------------------------------------------------

AZURE_RM_HOST = "https://management.azure.com"
AZURE_RM_SCOPE = "https://management.azure.com/.default"
COST_MANAGEMENT_API_VERSION = "2025-03-01"  # verify current GA at build time

GRAPH_V1_HOST = "https://graph.microsoft.com/v1.0"
GRAPH_BETA_HOST = "https://graph.microsoft.com/beta"
GRAPH_SCOPE = "https://graph.microsoft.com/.default"

POWERPLATFORM_HOST = "https://api.powerplatform.com"
POWERPLATFORM_SCOPE = "https://api.powerplatform.com/.default"
POWERPLATFORM_API_VERSION = "2024-10-01"
# Power Platform API GUID used when registering the app (see programmability-authentication-v2).
POWERPLATFORM_API_APP_GUID = "8578e004-a5c6-46e7-913e-12f58912df43"

# Canonical surface identifiers (mirror the cost_fact.schema.json enums).
SURFACE_AZURE_COST = "azure_cost_management"
SURFACE_GRAPH_REPORTS = "graph_reports"
SURFACE_GRAPH_LICENSES = "graph_licenses"
SURFACE_POWERPLATFORM = "powerplatform_api"
SURFACE_PURVIEW_AUDIT = "purview_audit_beta"
SURFACE_MANUAL_CSV = "manual_csv"


def utc_now_iso() -> str:
    """Return the current UTC time as an ISO-8601 string with a trailing Z."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_bytes(data: bytes) -> str:
    """Return the hex SHA-256 of a byte string."""
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: str) -> str:
    """Return the hex SHA-256 of a file, read in chunks."""
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stable_record_id(native_id: Optional[str], native_row: Any) -> str:
    """Return native_id if present, else a stable hash of the serialized native row."""
    if native_id:
        return str(native_id)
    payload = json.dumps(native_row, sort_keys=True, default=str).encode("utf-8")
    return f"sha256:{sha256_bytes(payload)}"


def fact_id(source_surface: str, source_record_id: str, period_start_utc: str, fact_type: str) -> str:
    """Deterministic UUIDv5 fact id so reruns over identical inputs are byte-stable."""
    name = "|".join([source_surface, source_record_id, period_start_utc, fact_type])
    return str(uuid.uuid5(FACT_ID_NAMESPACE, name))


@dataclass
class CollectorResult:
    """Outcome of a single collector run, recorded in the report manifest."""

    surface: str
    status: str  # succeeded | partial | skipped | surface_unavailable | failed
    rows: int = 0
    data_freshness_utc: Optional[str] = None
    preview: bool = False
    note: Optional[str] = None
    extract_path: Optional[str] = None
    started_utc: str = field(default_factory=utc_now_iso)
    completed_utc: Optional[str] = None

    def finish(self, status: Optional[str] = None) -> "CollectorResult":
        """Stamp completion time and optionally override status."""
        if status:
            self.status = status
        self.completed_utc = utc_now_iso()
        return self


def write_raw_extract(out_dir: str, surface: str, snapshot_id: str, records: Iterable[Any]) -> str:
    """Write a collector's raw records to a JSONL extract and return the path.

    Raw extracts are retained as part of the evidence package so the normalized dataset
    can always be traced back to the exact source rows.
    """
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"raw_{surface}_{snapshot_id}.jsonl")
    count = 0
    with open(path, "w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, default=str, sort_keys=True))
            handle.write("\n")
            count += 1
    logger.info("Wrote %d raw record(s) for surface '%s' to %s", count, surface, path)
    return path


def new_snapshot_id() -> str:
    """Generate a point-in-time snapshot id for one report run."""
    return f"{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}-{uuid.uuid4().hex[:8]}"
