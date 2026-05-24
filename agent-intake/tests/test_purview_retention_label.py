"""Unit tests for setup_purview_retention_label.py pure-logic functions.

Covers label spec construction and spec output with/without Graph beta sample.
Live Purview validation (Connect-IPPSSession, New-ComplianceTag) requires human
intervention per issue #123.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from setup_purview_retention_label import (
    DEFAULT_LABEL_NAME,
    DEFAULT_RETENTION_DAYS,
    DEFAULT_WORM_LABEL_NAME,
    build_label_spec,
    build_spec,
)

# ---------------------------------------------------------------------------
# build_label_spec
# ---------------------------------------------------------------------------


def test_build_label_spec_defaults() -> None:
    """Default spec matches the documented FSI-AgentIntake-7yr shape."""
    spec = build_label_spec(DEFAULT_LABEL_NAME, DEFAULT_WORM_LABEL_NAME, DEFAULT_RETENTION_DAYS)
    assert spec["displayName"] == "FSI-AgentIntake-7yr"
    assert spec["retentionDuration"]["days"] == 2555
    assert spec["retentionTrigger"] == "dateCreated"
    assert spec["behaviorDuringRetentionPeriod"] == "retain"
    assert spec["actionAfterRetentionPeriod"] == "none"
    assert spec["isInUse"] is False


def test_build_label_spec_worm_variant() -> None:
    """WORM variant has record behavior and locked default."""
    spec = build_label_spec(DEFAULT_LABEL_NAME, DEFAULT_WORM_LABEL_NAME, DEFAULT_RETENTION_DAYS)
    worm = spec["wormVariant"]
    assert worm["displayName"] == "FSI-AgentIntake-7yr-WORM"
    assert worm["behaviorDuringRetentionPeriod"] == "retainAsRecord"
    assert worm["defaultRecordBehavior"] == "startLocked"


def test_build_label_spec_custom_values() -> None:
    """Custom names and retention days propagate correctly."""
    spec = build_label_spec("CustomLabel", "CustomLabel-WORM", 365)
    assert spec["displayName"] == "CustomLabel"
    assert spec["retentionDuration"]["days"] == 365
    assert spec["wormVariant"]["displayName"] == "CustomLabel-WORM"


def test_build_label_spec_regulatory_references() -> None:
    """Description references SEC 17a-4, FINRA 4511, CFTC 1.31."""
    spec = build_label_spec(DEFAULT_LABEL_NAME, DEFAULT_WORM_LABEL_NAME, DEFAULT_RETENTION_DAYS)
    assert "SEC 17a-4" in spec["description"]
    assert "FINRA 4511" in spec["description"]
    assert "CFTC 1.31" in spec["description"]


def test_build_label_spec_admin_description_references_dataverse() -> None:
    """Admin description references the Dataverse tables used for evidence."""
    spec = build_label_spec(DEFAULT_LABEL_NAME, DEFAULT_WORM_LABEL_NAME, DEFAULT_RETENTION_DAYS)
    assert "fsi_intakedecisionlog" in spec["descriptionForAdmins"]
    assert "fsi_intakeretentionrecord" in spec["descriptionForAdmins"]


# ---------------------------------------------------------------------------
# build_spec
# ---------------------------------------------------------------------------


def test_build_spec_without_graph_beta() -> None:
    """Spec without Graph beta sample has label but no graphBetaCreateSample."""
    spec = build_spec(
        label_name=DEFAULT_LABEL_NAME,
        worm_label_name=DEFAULT_WORM_LABEL_NAME,
        retention_days=DEFAULT_RETENTION_DAYS,
        include_graph_beta=False,
    )
    assert "label" in spec
    assert "graphBetaCreateSample" not in spec


def test_build_spec_with_graph_beta() -> None:
    """Spec with Graph beta includes the sample URL and permission note."""
    spec = build_spec(
        label_name=DEFAULT_LABEL_NAME,
        worm_label_name=DEFAULT_WORM_LABEL_NAME,
        retention_days=DEFAULT_RETENTION_DAYS,
        include_graph_beta=True,
    )
    assert "graphBetaCreateSample" in spec
    sample = spec["graphBetaCreateSample"]
    assert sample["method"] == "POST"
    assert "beta" in sample["url"]
    assert "retentionLabels" in sample["url"]
    assert "RecordsManagement.ReadWrite.All" in sample["permission"]


def test_build_spec_is_json_serializable() -> None:
    """The full spec round-trips through JSON without error."""
    spec = build_spec(
        label_name=DEFAULT_LABEL_NAME,
        worm_label_name=DEFAULT_WORM_LABEL_NAME,
        retention_days=DEFAULT_RETENTION_DAYS,
        include_graph_beta=True,
    )
    serialized = json.dumps(spec, indent=2)
    deserialized = json.loads(serialized)
    assert deserialized["label"]["displayName"] == DEFAULT_LABEL_NAME
