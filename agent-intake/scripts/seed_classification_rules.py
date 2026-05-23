#!/usr/bin/env python3
"""Classification rules for agent-intake v1.0.0-preview.

Computes path, tier, zone, retention class, and reviewer routing from the six
trigger answers and the maker-facing audience field.

The Power Automate router flow (`docs/flow-configuration.md`, Flow 1) calls
this logic via a child flow OR mirrors it inline. This script is the canonical
reference and can be invoked standalone for unit testing or batch
reclassification of historical requests.

Usage:
  python seed_classification_rules.py --request-json input.json
  python seed_classification_rules.py --self-test
"""
from __future__ import annotations

import argparse
import copy
import json
import logging
import sys
from pathlib import Path
from typing import Any, Callable

import yaml

LOG = logging.getLogger("agent-intake.classify")

_SCRIPT_DIR = Path(__file__).resolve().parent
_DEFAULT_POLICY = _SCRIPT_DIR.parent / "templates" / "policy-lookup-tables.yaml"

TRIGGER_FIELDS = (
    "fsi_t1initiatesfinancialtxn",
    "fsi_t2customerfacing",
    "fsi_t3autonomousunmonitored",
    "fsi_t4handlesnpi",
    "fsi_t5handlesmnpi",
    "fsi_t6crossborderdata",
)
AUDIENCE_FIELDS = (
    "fsi_intendedaudience",
    "fsi_intendedaudiencelabel",
    "fsi_intendedaudienceLabel",
)
REQUIRED_REQUEST_FIELDS = TRIGGER_FIELDS + (
    "fsi_makerupn",
    "fsi_sponsorupn",
    "fsi_makercountry",
)
RISK_TIER_LABELS = {
    1: "Tier 1 (High)",
    2: "Tier 2 (Medium)",
    3: "Tier 3 (Low)",
}
ZONE_LABELS = {
    1: "Zone 1 (Enterprise)",
    2: "Zone 2 (Team)",
    3: "Zone 3 (Personal)",
}
REVIEWER_DISPLAY_NAMES = {
    "infosec": "InfoSec",
    "privacy": "Privacy",
    "compliance": "Compliance",
    "legal": "Legal",
    "mrm": "MRM",
}
DEFAULT_POLICY: dict[str, Any] = {
    "schema_version": "1.0.0-preview-defaults",
    "data_residency": {
        "default_action": "deny",
        "privacy_override_enabled": True,
        "privacy_team_upn": "privacy@contoso.com",
        "allowed_country_pairs": [],
    },
    "infosec_sampling": {
        "express_path_sample_rate": 0.10,
        "notification_channel": "Teams",
        "infosec_team_upn": "infosec-agent-review@contoso.com",
    },
    "sponsor_sla": {
        "initial_response_days": 3,
        "escalation_after_days": 7,
        "escalate_to": "manager",
    },
    "retention_labels": {
        "tier_1": "FSI-AgentIntake-7yr",
        "tier_2": "FSI-AgentIntake-7yr",
        "tier_3": "FSI-AgentIntake-7yr",
        "decision_log": "FSI-AgentIntake-7yr-WORM",
    },
    "managed_environment": {
        "tier_1": "required",
        "tier_2": "required",
        "tier_3": "recommended",
    },
    "dlp_connector_group": {
        "tier_1": "businessDataOnly",
        "tier_2": "businessDataOnly",
        "tier_3": "nonBusinessDataOnly",
    },
    "zone_routing": {
        "zone_1": {
            "sponsor_required": True,
            "infosec_required": True,
            "privacy_required": True,
            "compliance_required": True,
            "mrm_required_if_tier_1_or_2": True,
        },
        "zone_2": {
            "sponsor_required": True,
            "infosec_required": "sample",
            "privacy_required": False,
            "compliance_required": False,
        },
        "zone_3": {
            "sponsor_required": True,
            "infosec_required": "sample",
            "privacy_required": False,
            "compliance_required": False,
        },
    },
    "audience_to_zone": {
        "Just me": 3,
        "My team": 2,
        "My department": 2,
        "Anyone in the firm": 1,
        "External users": 1,
    },
    "quorum": {
        "tier_1": {"required": 3, "of": 5},
        "tier_2": {"required": 2, "of": 3},
        "tier_3": {"required": 1, "of": 1},
    },
    "parallel_routing": {
        "tier_1": "parallel",
        "tier_2": "parallel",
        "tier_3": "sequential",
    },
    "reviewer_routing": {
        "infosec": {
            "sla_days": 5,
            "escalate_to": "manager",
            "conditional_approval_allowed": True,
            "quorum_weight": 1,
        },
        "privacy": {
            "sla_days": 5,
            "escalate_to": "manager",
            "conditional_approval_allowed": True,
            "quorum_weight": 1,
        },
        "compliance": {
            "sla_days": 7,
            "escalate_to": "governance_lead",
            "conditional_approval_allowed": True,
            "quorum_weight": 1,
        },
        "legal": {
            "sla_days": 7,
            "escalate_to": "governance_lead",
            "conditional_approval_allowed": False,
            "quorum_weight": 1,
        },
        "mrm": {
            "sla_days": 10,
            "escalate_to": "mrm_committee",
            "conditional_approval_allowed": False,
            "quorum_weight": 1,
        },
    },
    "mrm": {
        "handoff_target": "model-risk-management-automation",
        "payload_version": "1.0.0",
        "required_when_tier_1": True,
        "fallback_when_target_not_deployed": "queue_locally",
    },
}

CaseTransform = Callable[[dict[str, Any]], dict[str, Any]]


def _canonical_key(value: Any) -> str:
    """Return a normalized key for defensive policy lookups."""
    return str(value or "").strip().lower().replace("-", "_").replace(" ", "_")


def _canonical_label(value: Any) -> str:
    """Return a case-insensitive label form."""
    return str(value or "").strip().casefold()


def _has_value(value: Any) -> bool:
    """Return True when the field is populated enough to classify."""
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    return True


def _as_int(value: Any, default: int) -> int:
    """Convert a value to int while preserving a fallback."""
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _tier_aliases(tier_key: str) -> tuple[str, ...]:
    """Return accepted aliases for a tier key such as tier_1/tier1."""
    suffix = tier_key.split("_")[-1]
    return (
        _canonical_key(tier_key),
        _canonical_key(tier_key.replace("_", "")),
        _canonical_key(f"tier{suffix}"),
    )


def _resolve_section(source: dict[str, Any], *names: str) -> dict[str, Any]:
    """Return the first matching top-level section from a raw policy mapping."""
    if not isinstance(source, dict):
        return {}
    canonical = {_canonical_key(key): value for key, value in source.items()}
    for name in names:
        value = canonical.get(_canonical_key(name))
        if isinstance(value, dict):
            return value
    return {}


def _resolve_tier_value(source: dict[str, Any], tier_key: str) -> Any:
    """Return a tier-specific value from keys such as tier_1 or tier1."""
    canonical = {_canonical_key(key): value for key, value in (source or {}).items()}
    for alias in _tier_aliases(tier_key):
        if alias in canonical:
            return canonical[alias]
    return None


def _merge_dict(default: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    """Deep-merge two dictionaries."""
    result = copy.deepcopy(default)
    for key, value in (override or {}).items():
        if isinstance(result.get(key), dict) and isinstance(value, dict):
            result[key] = _merge_dict(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def _normalize_audience_mapping(source: dict[str, Any]) -> dict[str, Any]:
    """Merge audience mappings while preserving the configured labels."""
    result = copy.deepcopy(DEFAULT_POLICY["audience_to_zone"])
    if isinstance(source, dict):
        for label, zone in source.items():
            result[str(label)] = _as_int(zone, 3)
    return result


def _normalize_tier_scalar_section(source: dict[str, Any], defaults: dict[str, Any]) -> dict[str, Any]:
    """Normalize tier sections whose values are simple scalars."""
    result = copy.deepcopy(defaults)
    for tier_key, default_value in defaults.items():
        override = _resolve_tier_value(source, tier_key)
        if override is not None:
            result[tier_key] = override
    return result


def _normalize_quorum(source: dict[str, Any]) -> dict[str, Any]:
    """Normalize quorum definitions with safe integer fallbacks."""
    result = copy.deepcopy(DEFAULT_POLICY["quorum"])
    for tier_key, default_value in DEFAULT_POLICY["quorum"].items():
        override = _resolve_tier_value(source, tier_key)
        if isinstance(override, dict):
            result[tier_key] = {
                "required": _as_int(override.get("required"), default_value["required"]),
                "of": _as_int(override.get("of"), default_value["of"]),
            }
    return result


def _normalize_reviewer_routing(source: dict[str, Any]) -> dict[str, Any]:
    """Normalize reviewer routing while tolerating key-shape drift."""
    result = copy.deepcopy(DEFAULT_POLICY["reviewer_routing"])
    canonical = {_canonical_key(key): value for key, value in (source or {}).items()}
    for reviewer_key, default_value in DEFAULT_POLICY["reviewer_routing"].items():
        override = canonical.get(_canonical_key(reviewer_key), {})
        merged = _merge_dict(default_value, override if isinstance(override, dict) else {})
        merged["sla_days"] = _as_int(merged.get("sla_days"), default_value["sla_days"])
        merged["quorum_weight"] = _as_int(
            merged.get("quorum_weight"),
            default_value["quorum_weight"],
        )
        result[reviewer_key] = merged
    return result


def _normalize_policy(policy: dict[str, Any] | None) -> dict[str, Any]:
    """Return a normalized policy with sensible fallbacks for missing sections."""
    source = policy if isinstance(policy, dict) else {}
    normalized = copy.deepcopy(DEFAULT_POLICY)
    normalized["schema_version"] = source.get("schema_version", normalized["schema_version"])
    normalized["data_residency"] = _merge_dict(
        DEFAULT_POLICY["data_residency"],
        _resolve_section(source, "data_residency", "cross_border", "dataResidency"),
    )
    normalized["infosec_sampling"] = _merge_dict(
        DEFAULT_POLICY["infosec_sampling"],
        _resolve_section(source, "infosec_sampling", "audit", "infosecSampling"),
    )
    normalized["sponsor_sla"] = _merge_dict(
        DEFAULT_POLICY["sponsor_sla"],
        _resolve_section(source, "sponsor_sla", "sponsor", "sponsorSla"),
    )
    normalized["retention_labels"] = _normalize_tier_scalar_section(
        _resolve_section(source, "retention_labels", "retention", "retentionLabels"),
        DEFAULT_POLICY["retention_labels"],
    )
    normalized["managed_environment"] = _normalize_tier_scalar_section(
        _resolve_section(source, "managed_environment", "managedEnvironment"),
        DEFAULT_POLICY["managed_environment"],
    )
    normalized["dlp_connector_group"] = _normalize_tier_scalar_section(
        _resolve_section(source, "dlp_connector_group", "dlpConnectorGroup"),
        DEFAULT_POLICY["dlp_connector_group"],
    )
    normalized["zone_routing"] = _merge_dict(
        DEFAULT_POLICY["zone_routing"],
        _resolve_section(source, "zone_routing", "zoneRouting"),
    )
    normalized["audience_to_zone"] = _normalize_audience_mapping(
        _resolve_section(source, "audience_to_zone", "audienceZoneMap", "audience_zone"),
    )
    normalized["quorum"] = _normalize_quorum(
        _resolve_section(source, "quorum", "review_quorum", "reviewQuorum"),
    )
    normalized["parallel_routing"] = _normalize_tier_scalar_section(
        _resolve_section(source, "parallel_routing", "parallelRouting"),
        DEFAULT_POLICY["parallel_routing"],
    )
    normalized["reviewer_routing"] = _normalize_reviewer_routing(
        _resolve_section(source, "reviewer_routing", "reviewerRouting"),
    )
    normalized["mrm"] = _merge_dict(
        DEFAULT_POLICY["mrm"],
        _resolve_section(source, "mrm", "model_risk_management", "modelRiskManagement"),
    )
    return normalized


def load_policy(path: Path = _DEFAULT_POLICY) -> dict[str, Any]:
    """Load classification policy defaults from YAML with safe built-in fallbacks."""
    if not path.exists():
        LOG.warning("Policy file %s not found; using bundled defaults.", path)
        return _normalize_policy({})

    with path.open(encoding="utf-8") as fh:
        loaded = yaml.safe_load(fh) or {}
    if not isinstance(loaded, dict):
        LOG.warning("Policy file %s did not contain a mapping; using bundled defaults.", path)
        return _normalize_policy({})
    return _normalize_policy(loaded)


def field_value(request: dict[str, Any], field: str) -> Any:
    """Return a request value by canonical Dataverse logical name."""
    return request.get(field, "")


def is_positive_answer(value: Any) -> bool:
    """Treat Yes and Not sure as routing-trigger hits."""
    return str(value or "").strip().lower() in {"yes", "not sure", "not-sure"}


def is_yes_answer(value: Any) -> bool:
    """Return True only for an explicit Yes answer."""
    return str(value or "").strip().lower() == "yes"


def is_truthy(value: Any) -> bool:
    """Return True for common boolean-like policy and Dataverse values."""
    return str(value or "").strip().lower() in {"1", "true", "yes", "y"}


def trigger_hits(request: dict[str, Any]) -> int:
    """Count trigger answers that are Yes or Not sure."""
    return sum(1 for field in TRIGGER_FIELDS if is_positive_answer(field_value(request, field)))


def _positive_triggers(request: dict[str, Any]) -> set[str]:
    """Return the set of trigger fields that evaluate as positive."""
    return {field for field in TRIGGER_FIELDS if is_positive_answer(field_value(request, field))}


def _resolve_audience(request: dict[str, Any]) -> str:
    """Return the first populated audience field or raise a field-specific error."""
    for field in AUDIENCE_FIELDS:
        value = request.get(field)
        if _has_value(value):
            return str(value).strip()
    raise ValueError("fsi_intendedaudience")


def _lookup_audience_zone(audience: str, policy: dict[str, Any]) -> int:
    """Return the configured zone for the selected audience."""
    for label, zone in policy["audience_to_zone"].items():
        if _canonical_label(label) == _canonical_label(audience):
            return _as_int(zone, 3)
    raise ValueError("fsi_intendedaudience")


def _validate_request(request: dict[str, Any]) -> str:
    """Validate required fields and return the resolved audience label."""
    for field in REQUIRED_REQUEST_FIELDS:
        if not _has_value(request.get(field)):
            raise ValueError(field)
    audience = _resolve_audience(request)
    if is_yes_answer(request.get("fsi_t6crossborderdata")) and not _has_value(
        request.get("fsi_dataresidencycountry")
    ):
        raise ValueError("fsi_dataresidencycountry")
    return audience


def _allowed_country_pair(policy: dict[str, Any], maker_country: str, data_country: str) -> bool:
    """Return True when the country pair is explicitly allow-listed in policy."""
    for pair in policy["data_residency"].get("allowed_country_pairs", []):
        if not isinstance(pair, dict):
            continue
        maker = str(pair.get("maker") or "").strip().upper()
        data = str(pair.get("data") or "").strip().upper()
        if maker == maker_country and data == data_country:
            return True
    return False


def _standard_reviewers(positive_triggers: set[str]) -> list[str]:
    """Return the reviewer board for the Standard path."""
    reviewers = [
        REVIEWER_DISPLAY_NAMES["infosec"],
        REVIEWER_DISPLAY_NAMES["privacy"],
    ]
    # ADR-002 says every trigger is a non-Express risk signal; T4 adds
    # privacy/compliance-sensitive data handling, so Standard includes Compliance.
    if "fsi_t4handlesnpi" in positive_triggers:
        reviewers.append(REVIEWER_DISPLAY_NAMES["compliance"])
    return reviewers


def _full_reviewers(mrm_required: bool) -> list[str]:
    """Return the reviewer board for the Full path."""
    reviewers = [
        REVIEWER_DISPLAY_NAMES["infosec"],
        REVIEWER_DISPLAY_NAMES["privacy"],
        REVIEWER_DISPLAY_NAMES["compliance"],
        REVIEWER_DISPLAY_NAMES["legal"],
    ]
    if mrm_required:
        reviewers.append(REVIEWER_DISPLAY_NAMES["mrm"])
    return reviewers


def _quorum_required(policy: dict[str, Any], tier: int, reviewer_count: int) -> int:
    """Return the required reviewer quorum for the selected tier."""
    if tier == 3:
        return 1
    tier_key = f"tier_{tier}"
    entry = policy["quorum"].get(tier_key, DEFAULT_POLICY["quorum"][tier_key])
    required = _as_int(entry.get("required"), DEFAULT_POLICY["quorum"][tier_key]["required"])
    return max(1, min(required, reviewer_count))


def _base_response(
    *,
    tier: int,
    zone: int,
    path_used: str,
    decision_path: str,
    routing_reason: str | None,
    positive_triggers: set[str],
    policy: dict[str, Any],
) -> dict[str, Any]:
    """Build the response payload shared by every routing outcome."""
    mrm_required = tier == 1 and is_truthy(policy["mrm"].get("required_when_tier_1", True))
    if path_used == "Express":
        parallel_reviewers: list[str] = []
    elif path_used == "Standard":
        parallel_reviewers = _standard_reviewers(positive_triggers)
    else:
        parallel_reviewers = _full_reviewers(mrm_required)

    retention_key = f"tier_{tier}"
    return {
        "decisionPath": decision_path,
        "pathUsed": path_used,
        "routingReason": routing_reason,
        "tier": tier,
        "riskTier": RISK_TIER_LABELS[tier],
        "risktier": RISK_TIER_LABELS[tier],
        "zone": zone,
        "zoneLabel": ZONE_LABELS[zone],
        "triggerHits": len(positive_triggers),
        "quorumRequired": _quorum_required(policy, tier, len(parallel_reviewers)),
        "parallelReviewers": parallel_reviewers,
        "mrmRequired": mrm_required,
        "mrmHandoffStatus": "Pending" if mrm_required else "NotApplicable",
        "retentionLabel": policy["retention_labels"].get(retention_key, "FSI-AgentIntake-7yr"),
        "routing": policy["zone_routing"].get(f"zone_{zone}", {}),
        "managedEnvironment": policy["managed_environment"].get(retention_key, "recommended"),
        "dlpConnectorGroup": policy["dlp_connector_group"].get(
            retention_key,
            "nonBusinessDataOnly",
        ),
    }


def classify(request: dict[str, Any], policy: dict[str, Any] | None = None) -> dict[str, Any]:
    """Return the routing decision for an agent-intake request.

    Backward compatibility: callers that already read `decisionPath`, `tier`,
    `risktier`, or `zone` can continue to do so; v1.0.0-preview adds path,
    quorum, reviewer, and MRM metadata.
    """
    resolved_policy = _normalize_policy(policy)
    audience = _validate_request(request)
    positive_triggers = _positive_triggers(request)
    hits = len(positive_triggers)
    audience_zone = _lookup_audience_zone(audience, resolved_policy)

    maker_upn = str(request["fsi_makerupn"]).strip().casefold()
    sponsor_upn = str(request["fsi_sponsorupn"]).strip().casefold()
    maker_country = str(request["fsi_makercountry"]).strip().upper()
    data_country = str(request.get("fsi_dataresidencycountry") or maker_country).strip().upper()
    privacy_override = is_truthy(request.get("fsi_privacyoverride"))
    crossborder_declared = is_yes_answer(field_value(request, "fsi_t6crossborderdata"))
    country_pair_allowed = _allowed_country_pair(resolved_policy, maker_country, data_country)
    crossborder_mismatch = (
        crossborder_declared
        and maker_country != data_country
        and not country_pair_allowed
    )
    crossborder_force_full = crossborder_mismatch and privacy_override

    # ADR-002 plus ADR-007/OQ-J: sponsor-only Express applies only to the
    # lowest-risk combination (no trigger hits and personal audience).
    if hits == 0 and audience_zone == 3:
        path_used = "Express"
        tier = 3
        zone = 3
    # OQ-001, OQ-002, and OQ-J: MNPI, Zone-1 audiences, Tier-1 hit counts, or
    # cross-border overrides route to Full with the largest reviewer board.
    elif audience_zone == 1 or hits >= 3 or "fsi_t5handlesmnpi" in positive_triggers or crossborder_force_full:
        path_used = "Full"
        tier = 1
        zone = 1
    # ADR-002 and OQ-J: anything above Express but below Tier-1 uses the
    # Standard path with sponsor evidence plus parallel reviewer evidence.
    else:
        path_used = "Standard"
        tier = 2
        zone = 2

    decision_path = path_used
    routing_reason = None
    # ADR-008: the sponsor must be a different person from the maker.
    if maker_upn == sponsor_upn:
        decision_path = "DefaultDeny"
        routing_reason = "sponsor_self_approval"
    # ADR-005 / OQ-005: unresolved cross-border routing defaults to deny.
    elif crossborder_mismatch and not privacy_override:
        default_action = _canonical_key(resolved_policy["data_residency"].get("default_action", "deny"))
        if default_action == "deny":
            decision_path = "DefaultDeny"
            routing_reason = "cross_border_data"

    return _base_response(
        tier=tier,
        zone=zone,
        path_used=path_used,
        decision_path=decision_path,
        routing_reason=routing_reason,
        positive_triggers=positive_triggers,
        policy=resolved_policy,
    )


def _base_request() -> dict[str, Any]:
    """Return a reusable baseline request for self-test and pytest."""
    return {field: "No" for field in TRIGGER_FIELDS} | {
        "fsi_intendedaudience": "Just me",
        "fsi_makerupn": "maker@contoso.com",
        "fsi_sponsorupn": "sponsor@contoso.com",
        "fsi_makercountry": "US",
        "fsi_dataresidencycountry": "US",
        "fsi_privacyoverride": False,
    }


def _request(**overrides: Any) -> dict[str, Any]:
    """Return a baseline request with the supplied overrides."""
    request = _base_request()
    request.update(overrides)
    return request


def _policy_without_quorum(policy: dict[str, Any]) -> dict[str, Any]:
    """Return a copy of policy without the quorum section."""
    updated = copy.deepcopy(policy)
    updated.pop("quorum", None)
    return updated


def _policy_with_crossborder_allow(policy: dict[str, Any]) -> dict[str, Any]:
    """Return a policy that allows mismatched cross-border routing."""
    updated = copy.deepcopy(policy)
    updated.setdefault("data_residency", {})["default_action"] = "allow"
    return updated


def _policy_with_allowed_country_pair(policy: dict[str, Any]) -> dict[str, Any]:
    """Return a policy that allows US -> CA routing without a deny gate."""
    updated = copy.deepcopy(policy)
    updated.setdefault("data_residency", {})["allowed_country_pairs"] = [
        {"maker": "US", "data": "CA"}
    ]
    return updated


def _alternate_key_policy(policy: dict[str, Any]) -> dict[str, Any]:
    """Return a raw policy that uses alternate key shapes for normalization tests."""
    normalized = _normalize_policy(policy)
    return {
        "cross_border": {
            "default_action": "deny",
            "allowed_country_pairs": [],
        },
        "audienceZoneMap": copy.deepcopy(normalized["audience_to_zone"]),
        "retention_labels": copy.deepcopy(normalized["retention_labels"]),
        "managedEnvironment": copy.deepcopy(normalized["managed_environment"]),
        "dlpConnectorGroup": copy.deepcopy(normalized["dlp_connector_group"]),
        "zone_routing": copy.deepcopy(normalized["zone_routing"]),
        "quorum": {
            "tier1": {"required": 4, "of": 5},
            "tier2": {"required": 2, "of": 3},
            "tier3": {"required": 1, "of": 1},
        },
        "parallelRouting": copy.deepcopy(normalized["parallel_routing"]),
        "reviewerRouting": {
            "InfoSec": copy.deepcopy(normalized["reviewer_routing"]["infosec"]),
            "Privacy": copy.deepcopy(normalized["reviewer_routing"]["privacy"]),
            "Compliance": copy.deepcopy(normalized["reviewer_routing"]["compliance"]),
            "Legal": copy.deepcopy(normalized["reviewer_routing"]["legal"]),
            "MRM": copy.deepcopy(normalized["reviewer_routing"]["mrm"]),
        },
        "mrm": copy.deepcopy(normalized["mrm"]),
    }


def _expected_result(
    request: dict[str, Any],
    *,
    path_used: str,
    decision_path: str | None = None,
    tier: int | None = None,
    zone: int | None = None,
    quorum_required: int | None = None,
    parallel_reviewers: list[str] | None = None,
    mrm_required: bool | None = None,
    routing_reason: str | None = None,
) -> dict[str, Any]:
    """Build an expected-result subset for self-test and pytest."""
    resolved_tier = tier if tier is not None else {"Express": 3, "Standard": 2, "Full": 1}[path_used]
    resolved_zone = zone if zone is not None else {"Express": 3, "Standard": 2, "Full": 1}[path_used]
    reviewers = list(parallel_reviewers or [])
    resolved_mrm = mrm_required if mrm_required is not None else resolved_tier == 1
    resolved_quorum = quorum_required
    if resolved_quorum is None:
        resolved_quorum = 1 if path_used == "Express" else 2 if path_used == "Standard" else 3
    return {
        "decisionPath": decision_path or path_used,
        "pathUsed": path_used,
        "routingReason": routing_reason,
        "tier": resolved_tier,
        "riskTier": RISK_TIER_LABELS[resolved_tier],
        "risktier": RISK_TIER_LABELS[resolved_tier],
        "zone": resolved_zone,
        "triggerHits": trigger_hits(request),
        "quorumRequired": resolved_quorum,
        "parallelReviewers": reviewers,
        "mrmRequired": resolved_mrm,
        "mrmHandoffStatus": "Pending" if resolved_mrm else "NotApplicable",
    }


def build_self_test_cases() -> list[dict[str, Any]]:
    """Return the regression matrix used by --self-test and pytest."""
    missing_t1 = _base_request()
    missing_t1.pop("fsi_t1initiatesfinancialtxn")

    missing_sponsor = _base_request()
    missing_sponsor.pop("fsi_sponsorupn")

    missing_data_residency = _request(fsi_t6crossborderdata="Yes")
    missing_data_residency.pop("fsi_dataresidencycountry")

    missing_policy_path = _DEFAULT_POLICY.parent / "policy-lookup-tables.missing.yaml"

    cases = [
        {
            "name": "all-no personal express",
            "request": _request(),
            "expected": _expected_result(_request(), path_used="Express"),
        },
        {
            "name": "all-no my-team standard",
            "request": _request(fsi_intendedaudience="My team"),
            "expected": _expected_result(
                _request(fsi_intendedaudience="My team"),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "all-no zone-one audience full",
            "request": _request(fsi_intendedaudience="Anyone in the firm"),
            "expected": _expected_result(
                _request(fsi_intendedaudience="Anyone in the firm"),
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "t1-yes just-me standard",
            "request": _request(fsi_t1initiatesfinancialtxn="Yes"),
            "expected": _expected_result(
                _request(fsi_t1initiatesfinancialtxn="Yes"),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "t2-yes zone-two standard",
            "request": _request(
                fsi_t2customerfacing="Yes",
                fsi_intendedaudience="My team",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t2customerfacing="Yes",
                    fsi_intendedaudience="My team",
                ),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "two-trigger zone-three standard",
            "request": _request(
                fsi_t1initiatesfinancialtxn="Yes",
                fsi_t2customerfacing="Yes",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t1initiatesfinancialtxn="Yes",
                    fsi_t2customerfacing="Yes",
                ),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "three-trigger zone-three full",
            "request": _request(
                fsi_t1initiatesfinancialtxn="Yes",
                fsi_t2customerfacing="Yes",
                fsi_t3autonomousunmonitored="Yes",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t1initiatesfinancialtxn="Yes",
                    fsi_t2customerfacing="Yes",
                    fsi_t3autonomousunmonitored="Yes",
                ),
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "t4-npi zone-two standard with compliance",
            "request": _request(
                fsi_t4handlesnpi="Yes",
                fsi_intendedaudience="My team",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t4handlesnpi="Yes",
                    fsi_intendedaudience="My team",
                ),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance"],
            ),
        },
        {
            "name": "t5-mnpi zone-two full",
            "request": _request(
                fsi_t5handlesmnpi="Yes",
                fsi_intendedaudience="My team",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t5handlesmnpi="Yes",
                    fsi_intendedaudience="My team",
                ),
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "t6-matching-countries standard",
            "request": _request(
                fsi_t6crossborderdata="Yes",
                fsi_intendedaudience="My team",
                fsi_dataresidencycountry="US",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t6crossborderdata="Yes",
                    fsi_intendedaudience="My team",
                    fsi_dataresidencycountry="US",
                ),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "t6-mismatch default-deny",
            "request": _request(
                fsi_t6crossborderdata="Yes",
                fsi_dataresidencycountry="CA",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t6crossborderdata="Yes",
                    fsi_dataresidencycountry="CA",
                ),
                path_used="Standard",
                decision_path="DefaultDeny",
                parallel_reviewers=["InfoSec", "Privacy"],
                routing_reason="cross_border_data",
            ),
        },
        {
            "name": "t6-mismatch privacy-override full",
            "request": _request(
                fsi_t6crossborderdata="Yes",
                fsi_dataresidencycountry="CA",
                fsi_privacyoverride=True,
            ),
            "expected": _expected_result(
                _request(
                    fsi_t6crossborderdata="Yes",
                    fsi_dataresidencycountry="CA",
                    fsi_privacyoverride=True,
                ),
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "sponsor-self-approval default-deny",
            "request": _request(fsi_sponsorupn="maker@contoso.com"),
            "expected": _expected_result(
                _request(fsi_sponsorupn="maker@contoso.com"),
                path_used="Express",
                decision_path="DefaultDeny",
                routing_reason="sponsor_self_approval",
            ),
        },
        {
            "name": "external-users full",
            "request": _request(fsi_intendedaudience="External users"),
            "expected": _expected_result(
                _request(fsi_intendedaudience="External users"),
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "not-sure counts positive",
            "request": _request(fsi_t1initiatesfinancialtxn="Not sure"),
            "expected": _expected_result(
                _request(fsi_t1initiatesfinancialtxn="Not sure"),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "all-six-yes just-me full",
            "request": _request(**{field: "Yes" for field in TRIGGER_FIELDS}),
            "expected": _expected_result(
                _request(**{field: "Yes" for field in TRIGGER_FIELDS}),
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "all-six-yes external-users full",
            "request": _request(
                **{field: "Yes" for field in TRIGGER_FIELDS},
                fsi_intendedaudience="External users",
                fsi_dataresidencycountry="US",
            ),
            "expected": _expected_result(
                _request(
                    **{field: "Yes" for field in TRIGGER_FIELDS},
                    fsi_intendedaudience="External users",
                    fsi_dataresidencycountry="US",
                ),
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "missing-trigger-field raises",
            "request": missing_t1,
            "expect_error": "fsi_t1initiatesfinancialtxn",
        },
        {
            "name": "missing-policy-file uses-defaults",
            "policy_path": missing_policy_path,
            "request": _request(fsi_intendedaudience="My team"),
            "expected": _expected_result(
                _request(fsi_intendedaudience="My team"),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "missing-quorum-section falls-back",
            "policy_transform": _policy_without_quorum,
            "request": _request(fsi_intendedaudience="My team"),
            "expected": _expected_result(
                _request(fsi_intendedaudience="My team"),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "my-department standard",
            "request": _request(fsi_intendedaudience="My department"),
            "expected": _expected_result(
                _request(fsi_intendedaudience="My department"),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "zone-one dominates one-trigger",
            "request": _request(
                fsi_t1initiatesfinancialtxn="Yes",
                fsi_intendedaudience="Anyone in the firm",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t1initiatesfinancialtxn="Yes",
                    fsi_intendedaudience="Anyone in the firm",
                ),
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "t4-not-sure still-adds-compliance",
            "request": _request(fsi_t4handlesnpi="Not sure"),
            "expected": _expected_result(
                _request(fsi_t4handlesnpi="Not sure"),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance"],
            ),
        },
        {
            "name": "t5-not-sure still-full",
            "request": _request(fsi_t5handlesmnpi="Not sure"),
            "expected": _expected_result(
                _request(fsi_t5handlesmnpi="Not sure"),
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "t6-not-sure standard",
            "request": _request(fsi_t6crossborderdata="Not sure"),
            "expected": _expected_result(
                _request(fsi_t6crossborderdata="Not sure"),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "two-trigger-with-npi standard",
            "request": _request(
                fsi_t1initiatesfinancialtxn="Yes",
                fsi_t4handlesnpi="Yes",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t1initiatesfinancialtxn="Yes",
                    fsi_t4handlesnpi="Yes",
                ),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance"],
            ),
        },
        {
            "name": "three-trigger-with-npi full",
            "request": _request(
                fsi_t1initiatesfinancialtxn="Yes",
                fsi_t2customerfacing="Yes",
                fsi_t4handlesnpi="Yes",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t1initiatesfinancialtxn="Yes",
                    fsi_t2customerfacing="Yes",
                    fsi_t4handlesnpi="Yes",
                ),
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "one-trigger-my-department standard",
            "request": _request(
                fsi_t3autonomousunmonitored="Yes",
                fsi_intendedaudience="My department",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t3autonomousunmonitored="Yes",
                    fsi_intendedaudience="My department",
                ),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "privacy-override-string-full",
            "request": _request(
                fsi_t6crossborderdata="Yes",
                fsi_dataresidencycountry="CA",
                fsi_privacyoverride="Yes",
                fsi_intendedaudience="My team",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t6crossborderdata="Yes",
                    fsi_dataresidencycountry="CA",
                    fsi_privacyoverride="Yes",
                    fsi_intendedaudience="My team",
                ),
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "policy-allow-skips-default-deny",
            "policy_transform": _policy_with_crossborder_allow,
            "request": _request(
                fsi_t6crossborderdata="Yes",
                fsi_dataresidencycountry="CA",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t6crossborderdata="Yes",
                    fsi_dataresidencycountry="CA",
                ),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "allowed-country-pair-skips-default-deny",
            "policy_transform": _policy_with_allowed_country_pair,
            "request": _request(
                fsi_t6crossborderdata="Yes",
                fsi_dataresidencycountry="CA",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t6crossborderdata="Yes",
                    fsi_dataresidencycountry="CA",
                ),
                path_used="Standard",
                parallel_reviewers=["InfoSec", "Privacy"],
            ),
        },
        {
            "name": "audience-label-alias-full",
            "request": {
                **{field: "No" for field in TRIGGER_FIELDS},
                "fsi_intendedaudiencelabel": "External users",
                "fsi_makerupn": "maker@contoso.com",
                "fsi_sponsorupn": "sponsor@contoso.com",
                "fsi_makercountry": "US",
                "fsi_dataresidencycountry": "US",
                "fsi_privacyoverride": False,
            },
            "expected": _expected_result(
                {
                    **{field: "No" for field in TRIGGER_FIELDS},
                    "fsi_intendedaudiencelabel": "External users",
                    "fsi_makerupn": "maker@contoso.com",
                    "fsi_sponsorupn": "sponsor@contoso.com",
                    "fsi_makercountry": "US",
                    "fsi_dataresidencycountry": "US",
                    "fsi_privacyoverride": False,
                },
                path_used="Full",
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "unknown-audience-raises",
            "request": _request(fsi_intendedaudience="Partners only"),
            "expect_error": "fsi_intendedaudience",
        },
        {
            "name": "missing-sponsor-raises",
            "request": missing_sponsor,
            "expect_error": "fsi_sponsorupn",
        },
        {
            "name": "alternate-key-policy-normalized",
            "policy_transform": _alternate_key_policy,
            "request": _request(
                fsi_t5handlesmnpi="Yes",
                fsi_intendedaudience="My team",
            ),
            "expected": _expected_result(
                _request(
                    fsi_t5handlesmnpi="Yes",
                    fsi_intendedaudience="My team",
                ),
                path_used="Full",
                quorum_required=4,
                parallel_reviewers=["InfoSec", "Privacy", "Compliance", "Legal", "MRM"],
            ),
        },
        {
            "name": "missing-data-residency-raises",
            "request": missing_data_residency,
            "expect_error": "fsi_dataresidencycountry",
        },
    ]
    return cases


def _resolve_case_policy(case: dict[str, Any], default_policy: dict[str, Any]) -> dict[str, Any]:
    """Return the effective policy for a self-test case."""
    if case.get("policy_path"):
        return load_policy(case["policy_path"])
    base_policy = copy.deepcopy(case.get("policy", default_policy))
    transform: CaseTransform | None = case.get("policy_transform")
    if transform:
        base_policy = transform(base_policy)
    return base_policy


def _check_expected(result: dict[str, Any], expected: dict[str, Any]) -> tuple[bool, list[str]]:
    """Return whether the result matched and a list of mismatched keys."""
    mismatches: list[str] = []
    for key, expected_value in expected.items():
        if result.get(key) != expected_value:
            mismatches.append(f"{key}: expected {expected_value!r}, got {result.get(key)!r}")
    return not mismatches, mismatches


def _self_test() -> int:
    """Run the built-in regression matrix and return a shell-friendly status code."""
    default_policy = load_policy()
    failed = 0
    for case in build_self_test_cases():
        case_policy = _resolve_case_policy(case, default_policy)
        try:
            result = classify(case["request"], case_policy)
            if case.get("expect_error"):
                ok = False
                detail = f"expected ValueError({case['expect_error']}) but classification succeeded"
            else:
                ok, mismatches = _check_expected(result, case["expected"])
                detail = "; ".join(mismatches) if mismatches else json.dumps(result, sort_keys=True)
        except ValueError as exc:
            result = {"error": str(exc)}
            ok = case.get("expect_error") == str(exc)
            detail = str(exc)
        marker = "PASS" if ok else "FAIL"
        print(f"[{marker}] {case['name']}: {detail}")
        if not ok:
            failed += 1
            if not case.get("expect_error"):
                print(json.dumps(result, indent=2, sort_keys=True))
    print(
        f"Self-test summary: {len(build_self_test_cases()) - failed}/{len(build_self_test_cases())} cases passed."
    )
    return 1 if failed else 0


def main() -> int:
    """CLI entrypoint."""
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(
        description="Classify an agent-intake request (Express/Standard/Full)"
    )
    parser.add_argument("--request-json", type=Path, help="Path to a JSON file with request fields")
    parser.add_argument("--policy", type=Path, default=_DEFAULT_POLICY, help="Path to policy-lookup-tables.yaml")
    parser.add_argument("--self-test", action="store_true", help="Run built-in test cases and exit")
    args = parser.parse_args()

    if args.self_test:
        return _self_test()
    if not args.request_json:
        parser.error("--request-json is required (or use --self-test)")
    policy = load_policy(args.policy)
    with args.request_json.open(encoding="utf-8") as fh:
        request = json.load(fh)
    result = classify(request, policy)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
