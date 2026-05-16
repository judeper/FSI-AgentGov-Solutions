#!/usr/bin/env python3
"""Queue Tier-1 full-path intake requests into model-risk-management-automation.

This adapter intentionally reuses the existing MRM schema instead of creating a
new queue table. MRM v1.0.3 exposes `fsi_modelinventory` as the earliest durable
submission record, keyed by `fsi_agentid` + `fsi_environmentid`. The script
creates or updates a Pending Submission row there and, when available, writes an
`Inventory Submitted` entry to `fsi_mrmcomplianceevent` that carries the
validated handoff payload for idempotency and reviewer pickup.

If the MRM solution is not deployed, the script falls back to
`fsi_intakeauditevent` with `fsi_eventtype = MRMHandoffPending` so the firm
retains locally queryable evidence and a manual pickup payload.

The script uses the `jsonschema` package rather than a hand-rolled validator so
the runtime validation stays aligned with the published Draft 2020-12 contract.
Install it with:
    python -m pip install jsonschema
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
SOLUTION_ROOT = SCRIPT_DIR.parent
REPO_ROOT = SOLUTION_ROOT.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from autodetect_environments import get_token_via_cli, get_token_via_managed_identity  # noqa: E402

LOG = logging.getLogger("agent-intake.mrm")

SCHEMA_FILE = SOLUTION_ROOT / "templates" / "mrm-handoff-payload-schema.json"
SCHEMA_ID = "https://judeper.github.io/FSI-AgentGov-Solutions/schemas/mrm-handoff-payload-v1.json"

MRM_QUEUE_TABLE = "fsi_modelinventory"
MRM_EVENT_TABLE = "fsi_mrmcomplianceevent"
LOCAL_AUDIT_TABLE = "fsi_intakeauditevent"

ENTITY_SET_FALLBACKS = {
    MRM_QUEUE_TABLE: "fsi_modelinventories",
    MRM_EVENT_TABLE: "fsi_mrmcomplianceevents",
    LOCAL_AUDIT_TABLE: "fsi_intakeauditevents",
}

MRM_STATUS_PENDING_SUBMISSION = 100000000
MRM_TIER_FULL = 100000001
VALIDATION_STATUS_SUBMITTED = 100000002
MRM_EVENT_INVENTORY_SUBMITTED = 100000000
MRM_EVENT_PILLAR_GOVERNANCE = 100000002
MRM_EVENT_IMPACT_LOW = 100000001

ZONE_VALUES = {
    "Unclassified": 100000000,
    "Zone 1": 100000001,
    "Zone 2": 100000002,
    "Zone 3": 100000003,
}

PROVIDER_VALUES = {
    "Microsoft": 100000000,
    "Anthropic": 100000001,
    "OpenAI": 100000002,
    "Custom": 100000003,
    "Third-Party": 100000004,
}

DECISION_OUTPUT_VALUES = {
    "Quantitative Estimate": 100000000,
    "Decision Support": 100000001,
    "Information Retrieval": 100000002,
    "Productivity": 100000003,
}

MATERIALITY_VALUES = {
    "High": 100000000,
    "Medium": 100000001,
    "Low": 100000002,
}

RISK_RATING_VALUES = {
    "Critical": 100000000,
    "High": 100000001,
    "Medium": 100000002,
    "Low": 100000003,
}

VALIDATION_CADENCE_VALUES = {
    "Annual": 100000000,
    "Biennial": 100000001,
    "Triennial": 100000002,
}


@dataclass(frozen=True)
class EntityInfo:
    """Minimal Dataverse entity metadata needed for CRUD operations."""

    logical_name: str
    entity_set_name: str
    primary_id_attribute: str
    primary_name_attribute: str | None


def utc_now() -> datetime:
    """Return the current UTC timestamp."""
    return datetime.now(timezone.utc)


def format_datetime(value: datetime) -> str:
    """Format a timezone-aware datetime for Dataverse JSON payloads."""
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_datetime(value: str, field_name: str) -> datetime:
    """Parse an ISO 8601 datetime string into UTC."""
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"Invalid ISO 8601 value for {field_name}: {value}") from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def default_primary_id_attribute(logical_name: str) -> str:
    """Best-effort custom-table primary key naming fallback."""
    return f"{logical_name}id"


def compact_json(data: Any) -> str:
    """Serialize JSON deterministically without extra whitespace."""
    return json.dumps(data, separators=(",", ":"), sort_keys=True)


def serialize_with_limit(data: Any, *, max_length: int, summary: Any | None = None) -> str:
    """Serialize JSON and optionally fall back to a shorter summary when needed."""
    text = compact_json(data)
    if len(text) <= max_length:
        return text
    if summary is not None:
        summary_text = compact_json(summary)
        if len(summary_text) <= max_length:
            return summary_text
    raise ValueError(f"Serialized payload exceeds {max_length} characters")


def enforce_length(field_name: str, value: str, limit: int) -> str:
    """Fail fast when mapped content exceeds the destination Dataverse column size."""
    if len(value) > limit:
        raise ValueError(f"Mapped value for {field_name} exceeds {limit} characters")
    return value


def odata_escape(value: str) -> str:
    """Escape a string for use inside a single-quoted OData literal."""
    return value.replace("'", "''")


def load_json_file(path: Path) -> Any:
    """Load JSON from disk."""
    return json.loads(path.read_text(encoding="utf-8"))


def emit_result(result: dict[str, Any], output: Path | None) -> None:
    """Write result JSON to a file or stdout."""
    rendered = json.dumps(result, indent=2, sort_keys=True)
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered + "\n", encoding="utf-8")
        return
    sys.stdout.write(rendered + "\n")


def validation_error_path(path_parts: Any) -> str:
    """Convert a jsonschema error path to a user-friendly JSON pointer-like string."""
    if not path_parts:
        return "$"
    bits = ["$"]
    for part in path_parts:
        bits.append(f"[{part}]" if isinstance(part, int) else f".{part}")
    return "".join(bits)


def validate_payload_against_schema(payload: dict[str, Any], schema: dict[str, Any]) -> None:
    """Validate the handoff payload against the Draft 2020-12 schema."""
    try:
        from jsonschema import Draft202012Validator, FormatChecker
    except ImportError as exc:  # pragma: no cover - depends on optional runtime package
        raise RuntimeError(
            "The jsonschema package is required for handoff payload validation. "
            "Install it with 'python -m pip install jsonschema'."
        ) from exc

    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(payload), key=lambda item: list(item.path))
    if not errors:
        return
    first = errors[0]
    location = validation_error_path(list(first.path))
    raise ValueError(f"Payload validation failed at {location}: {first.message}")


def assert_handoff_eligibility(payload: dict[str, Any]) -> None:
    """Confirm the payload represents the Tier-1 Full-path handoff this script owns."""
    intake = payload["intake"]
    if intake["pathUsed"] != "Full":
        raise ValueError("MRM handoff only supports Full-path intake requests")
    if not intake["mrmRequired"]:
        raise ValueError("MRM handoff requires intake.mrmRequired = true")
    if not intake["riskTier"].lower().startswith("tier 1"):
        raise ValueError("MRM handoff only supports Tier 1 intake requests")
    if payload["model"]["materiality"] != "High":
        LOG.warning(
            "Payload materiality is %s; continuing because intake.mrmRequired is true",
            payload["model"]["materiality"],
        )


def resolve_enum_value(raw_value: str, mapping: dict[str, int], field_name: str) -> int:
    """Resolve a label or label-prefix to the Dataverse integer value."""
    candidate = raw_value.strip()
    if candidate in mapping:
        return mapping[candidate]
    lowered = candidate.lower()
    for label, value in mapping.items():
        if lowered == label.lower() or lowered.startswith(label.lower()):
            return value
    raise ValueError(f"Unsupported {field_name}: {raw_value}")


def derive_provider_label(model: dict[str, Any]) -> str:
    """Map wire-format provider fields to the MRM option-set labels."""
    provider_name = model["providerName"].strip()
    lowered = provider_name.lower()
    if lowered == "microsoft":
        return "Microsoft"
    if lowered == "anthropic":
        return "Anthropic"
    if lowered == "openai":
        return "OpenAI"
    if model["vendorOrInternal"] == "Internal":
        return "Custom"
    return "Third-Party"


def derive_underlying_model(model: dict[str, Any]) -> str:
    """Return the MRM underlying-model string."""
    underlying = model.get("underlyingModel")
    if underlying:
        return enforce_length("fsi_underlyingmodel", underlying, 200)
    parts = [model.get("providerName"), model.get("providerModelId") or model.get("modelFamily")]
    composed = " ".join(part for part in parts if part)
    if not composed:
        raise ValueError("Payload must provide model.underlyingModel or enough fields to derive it")
    return enforce_length("fsi_underlyingmodel", composed, 200)


def derive_validation_cadence_label(payload: dict[str, Any]) -> str:
    """Seed the queue row with the cadence implied by the intake tier."""
    return "Annual" if payload["intake"]["riskTier"].lower().startswith("tier 1") else "Biennial"


def derive_provisional_rating_label(payload: dict[str, Any]) -> str:
    """Choose a provisional rating until the MRM scorer recalculates it."""
    if payload["model"]["materiality"] == "High":
        return "High"
    if payload["model"]["materiality"] == "Medium":
        return "Medium"
    return "Low"


def derive_mrm_officer_upn(payload: dict[str, Any]) -> str | None:
    """Resolve the optional MRM officer UPN from routing or reviewer metadata."""
    routing = payload.get("routing", {})
    if routing.get("mrmOfficerUpn"):
        return enforce_length("fsi_mrmofficerupn", routing["mrmOfficerUpn"], 200)
    for reviewer in payload["reviewers"]:
        if reviewer["role"].strip().lower() == "mrm":
            return enforce_length("fsi_mrmofficerupn", reviewer["upn"], 200)
    return None


def derive_auditor_upn(payload: dict[str, Any]) -> str | None:
    """Resolve the optional auditor UPN from routing or reviewer metadata."""
    routing = payload.get("routing", {})
    if routing.get("auditorUpn"):
        return enforce_length("fsi_auditorupn", routing["auditorUpn"], 200)
    for reviewer in payload["reviewers"]:
        normalized = reviewer["role"].strip().lower().replace(" ", "")
        if normalized in {"audit", "auditor", "internalaudit", "internalauditor"}:
            return enforce_length("fsi_auditorupn", reviewer["upn"], 200)
    return None


def build_business_function(payload: dict[str, Any]) -> str:
    """Build the MRM business-function narrative from the handoff payload."""
    agent = payload["agent"]
    lines = [f"Outcome: {agent['businessOutcome']}"]
    justification = agent.get("businessJustification")
    if justification:
        lines.append(f"Justification: {justification}")
    champion_plan = payload["model"].get("championChallengerPlan")
    if champion_plan:
        lines.append(f"Champion/challenger plan: {champion_plan}")
    return enforce_length("fsi_businessfunction", "\n".join(lines), 10000)


def build_data_inputs(payload: dict[str, Any]) -> str:
    """Serialize declared sources into the MRM data-inputs memo field."""
    sources = payload["data"]["declaredSources"]
    full = compact_json(sources)
    if len(full) <= 10000:
        return full
    condensed = [
        {
            "name": source["name"],
            "classification": source["classification"],
            "residencyCountry": source["residencyCountry"],
        }
        for source in sources
    ]
    condensed_json = compact_json(condensed)
    if len(condensed_json) <= 10000:
        return condensed_json
    raise ValueError("Declared data sources exceed the fsi_datainputs column limit")


def build_known_limitations(payload: dict[str, Any]) -> str | None:
    """Build the known-limitations narrative stored with the queue row."""
    parts: list[str] = []
    known_limits = payload["model"].get("knownLimitations", [])
    if known_limits:
        parts.append("Known limitations: " + "; ".join(known_limits))
    validation_evidence = payload["model"].get("validationEvidenceUrl")
    if validation_evidence:
        parts.append(f"Validation evidence: {validation_evidence}")
    fairness_artifact = payload["controls"].get("biasFairnessAssessmentUrl")
    if fairness_artifact:
        parts.append(f"Bias/fairness assessment: {fairness_artifact}")
    explainability_artifacts = payload["controls"].get("explainabilityArtifacts", [])
    if explainability_artifacts:
        parts.append("Explainability artifacts: " + ", ".join(explainability_artifacts))
    if not parts:
        return None
    return enforce_length("fsi_knownlimitations", "\n".join(parts), 10000)


def build_mrm_queue_row(
    payload: dict[str, Any],
    *,
    submitted_on: datetime,
    now: datetime,
    create: bool,
) -> dict[str, Any]:
    """Map the wire contract into the existing MRM model inventory shape."""
    agent = payload["agent"]
    maker = payload["maker"]
    model = payload["model"]

    cadence_label = derive_validation_cadence_label(payload)
    cadence_days = {"Annual": 365, "Biennial": 730, "Triennial": 1095}[cadence_label]
    provisional_rating = derive_provisional_rating_label(payload)

    row: dict[str, Any] = {
        "fsi_modelname": enforce_length("fsi_modelname", agent["displayName"], 500),
        "fsi_agentid": enforce_length("fsi_agentid", agent["platformAgentId"], 100),
        "fsi_environmentid": enforce_length("fsi_environmentid", agent["environmentId"], 100),
        "fsi_businessfunction": build_business_function(payload),
        "fsi_underlyingmodel": derive_underlying_model(model),
        "fsi_modelprovider": PROVIDER_VALUES[derive_provider_label(model)],
        "fsi_decisionoutputtype": resolve_enum_value(
            model["decisionOutputType"],
            DECISION_OUTPUT_VALUES,
            "model.decisionOutputType",
        ),
        "fsi_materiality": resolve_enum_value(model["materiality"], MATERIALITY_VALUES, "model.materiality"),
        "fsi_datainputs": build_data_inputs(payload),
        "fsi_intendedusers": enforce_length("fsi_intendedusers", agent["intendedAudience"], 500),
        "fsi_governancezone": resolve_enum_value(payload["intake"]["zone"], ZONE_VALUES, "intake.zone"),
        "fsi_ownerupn": enforce_length("fsi_ownerupn", maker["upn"], 200),
        "fsi_lastupdated": format_datetime(now),
    }

    if agent.get("entraAgentId"):
        row["fsi_entraagentid"] = enforce_length("fsi_entraagentid", agent["entraAgentId"], 100)
    if maker.get("department"):
        row["fsi_ownerdepartment"] = enforce_length("fsi_ownerdepartment", maker["department"], 200)
    known_limitations = build_known_limitations(payload)
    if known_limitations:
        row["fsi_knownlimitations"] = known_limitations
    mrm_officer = derive_mrm_officer_upn(payload)
    if mrm_officer:
        row["fsi_mrmofficerupn"] = mrm_officer
    auditor = derive_auditor_upn(payload)
    if auditor:
        row["fsi_auditorupn"] = auditor

    if create:
        row.update(
            {
                "fsi_mrmtier": MRM_TIER_FULL,
                "fsi_mrmstatus": MRM_STATUS_PENDING_SUBMISSION,
                "fsi_currentriskrating": RISK_RATING_VALUES[provisional_rating],
                "fsi_validationcadence": VALIDATION_CADENCE_VALUES[cadence_label],
                "fsi_nextvalidationdue": format_datetime(submitted_on + timedelta(days=cadence_days)),
                "fsi_validationstatus": VALIDATION_STATUS_SUBMITTED,
                "fsi_firstsubmitted": format_datetime(submitted_on),
            }
        )

    return row


def build_mrm_event_summary(
    payload: dict[str, Any],
    *,
    queue_record_id: str,
    queue_action: str,
) -> dict[str, Any]:
    """Return the compact metadata shared by dry-run output and live event writes."""
    return {
        "sourceSolution": "agent-intake",
        "eventKind": "AgentIntakeMrmHandoff",
        "requestId": payload["intake"]["requestId"],
        "decisionPackHash": payload["decisionPackHash"],
        "payloadVersion": payload["payloadVersion"],
        "queueTable": MRM_QUEUE_TABLE,
        "queueRecordId": queue_record_id,
        "queueAction": queue_action,
        "retentionLabel": payload["retentionLabel"],
    }


def build_mrm_event_details(
    payload: dict[str, Any],
    *,
    queue_record_id: str,
    queue_action: str,
) -> str:
    """Build the MRM compliance-event JSON envelope."""
    base = build_mrm_event_summary(
        payload,
        queue_record_id=queue_record_id,
        queue_action=queue_action,
    )
    full = {**base, "handoffPayload": payload}
    summary = {
        **base,
        "handoffPayloadSummary": {
            "schema": payload["$schema"],
            "modelProvider": payload["model"]["providerName"],
            "decisionOutputType": payload["model"]["decisionOutputType"],
            "materiality": payload["model"]["materiality"],
        },
    }
    return serialize_with_limit(full, max_length=50000, summary=summary)


def build_mrm_event_row(
    payload: dict[str, Any],
    *,
    now: datetime,
    queue_record_id: str,
    queue_action: str,
) -> dict[str, Any]:
    """Build the MRM compliance-event row used for idempotency and traceability."""
    return {
        "fsi_eventtype": MRM_EVENT_INVENTORY_SUBMITTED,
        "fsi_eventtimestamp": format_datetime(now),
        "fsi_triggeredby": "agent-intake.handoff_mrm",
        "fsi_eventdetails": build_mrm_event_details(
            payload,
            queue_record_id=queue_record_id,
            queue_action=queue_action,
        ),
        "fsi_previousvalue": payload["intake"]["requestId"],
        "fsi_newvalue": payload["decisionPackHash"],
        "fsi_sr117pillar": MRM_EVENT_PILLAR_GOVERNANCE,
        "fsi_complianceimpact": MRM_EVENT_IMPACT_LOW,
    }


def build_local_fallback_payload(payload: dict[str, Any], reason: str) -> str:
    """Build the local intake-audit payload used when MRM is absent."""
    base = {
        "sourceSolution": "agent-intake",
        "eventKind": "MRMHandoffPending",
        "fallbackReason": reason,
        "requestId": payload["intake"]["requestId"],
        "decisionPackHash": payload["decisionPackHash"],
        "payloadVersion": payload["payloadVersion"],
        "manualNextStep": (
            "Deploy model-risk-management-automation or manually create the MRM "
            "submission using this payload."
        ),
    }
    full = {**base, "handoffPayload": payload}
    summary = {
        **base,
        "handoffPayloadSummary": {
            "schema": payload["$schema"],
            "modelProvider": payload["model"]["providerName"],
            "decisionOutputType": payload["model"]["decisionOutputType"],
            "materiality": payload["model"]["materiality"],
        },
    }
    return serialize_with_limit(full, max_length=65536, summary=summary)


def build_local_audit_row(payload: dict[str, Any], *, now: datetime, reason: str) -> dict[str, Any]:
    """Build the fallback intake-audit row."""
    request_id = payload["intake"]["requestId"]
    return {
        "fsi_name": enforce_length("fsi_name", f"MRM handoff pending - {request_id}", 500),
        "fsi_requestid": request_id,
        "fsi_eventtype": "MRMHandoffPending",
        "fsi_pathphase": "Handed off",
        "fsi_actorupn": "agent-intake.handoff_mrm",
        "fsi_eventon": format_datetime(now),
        "fsi_eventpayloadjson": build_local_fallback_payload(payload, reason),
    }


def build_dataverse_client(environment_url: str, access_token: str) -> Any:
    """Instantiate the shared Dataverse client lazily."""
    from scripts.shared.dataverse_client import DataverseClient

    return DataverseClient(
        tenant_id=None,
        environment_url=environment_url,
        access_token=access_token,
    )


def probe_entity(client: Any, logical_name: str) -> EntityInfo | None:
    """Probe Dataverse metadata to discover whether an entity exists."""
    metadata = client.get_entity_metadata(logical_name)
    if not metadata:
        return None
    return EntityInfo(
        logical_name=logical_name,
        entity_set_name=metadata.get("EntitySetName") or ENTITY_SET_FALLBACKS.get(logical_name, f"{logical_name}s"),
        primary_id_attribute=metadata.get("PrimaryIdAttribute") or default_primary_id_attribute(logical_name),
        primary_name_attribute=metadata.get("PrimaryNameAttribute"),
    )


def find_existing_queue_row(client: Any, queue_info: EntityInfo, payload: dict[str, Any]) -> dict[str, Any] | None:
    """Find an existing queue row by the MRM alternate-key columns."""
    agent = payload["agent"]
    filter_expr = (
        f"fsi_agentid eq '{odata_escape(agent['platformAgentId'])}' and "
        f"fsi_environmentid eq '{odata_escape(agent['environmentId'])}'"
    )
    results = client.query(
        queue_info.entity_set_name,
        select=[queue_info.primary_id_attribute, "fsi_modelname", "fsi_mrmstatus", "fsi_validationstatus"],
        filter_expr=filter_expr,
        top=1,
    )
    return results[0] if results else None


def find_existing_handoff_event(
    client: Any,
    event_info: EntityInfo,
    *,
    request_id: str,
    decision_pack_hash: str,
) -> dict[str, Any] | None:
    """Find an existing MRM compliance event for the same request/hash pair."""
    filter_expr = (
        f"fsi_eventtype eq {MRM_EVENT_INVENTORY_SUBMITTED} and "
        f"fsi_previousvalue eq '{odata_escape(request_id)}' and "
        f"fsi_newvalue eq '{odata_escape(decision_pack_hash)}'"
    )
    results = client.query(
        event_info.entity_set_name,
        select=[event_info.primary_id_attribute, "fsi_eventtimestamp", "fsi_previousvalue", "fsi_newvalue"],
        filter_expr=filter_expr,
        top=1,
    )
    return results[0] if results else None


def find_existing_local_fallback(
    client: Any,
    audit_info: EntityInfo,
    *,
    request_id: str,
    decision_pack_hash: str,
) -> dict[str, Any] | None:
    """Find an existing local fallback event for the same request/hash pair."""
    hash_marker = f'"decisionPackHash":"{decision_pack_hash}"'
    filter_expr = (
        f"fsi_requestid eq '{odata_escape(request_id)}' and "
        f"fsi_eventtype eq 'MRMHandoffPending' and "
        f"contains(fsi_eventpayloadjson, '{hash_marker}')"
    )
    results = client.query(
        audit_info.entity_set_name,
        select=[audit_info.primary_id_attribute, "fsi_eventon", "fsi_requestid"],
        filter_expr=filter_expr,
        top=1,
    )
    return results[0] if results else None


def queue_to_mrm(
    client: Any,
    payload: dict[str, Any],
    *,
    queue_info: EntityInfo,
    now: datetime,
    submitted_on: datetime,
) -> tuple[dict[str, Any], int]:
    """Create or update the MRM queue row and optional compliance-event marker."""
    request_id = payload["intake"]["requestId"]
    decision_pack_hash = payload["decisionPackHash"]
    warnings: list[str] = []

    existing_row = find_existing_queue_row(client, queue_info, payload)

    event_info: EntityInfo | None = None
    existing_event: dict[str, Any] | None = None
    try:
        event_info = probe_entity(client, MRM_EVENT_TABLE)
        if event_info:
            existing_event = find_existing_handoff_event(
                client,
                event_info,
                request_id=request_id,
                decision_pack_hash=decision_pack_hash,
            )
    except requests.HTTPError as exc:
        warnings.append(
            f"MRM compliance-event probe failed ({exc.response.status_code if exc.response else 'unknown'}); continuing without the sidecar marker."
        )

    if existing_row and existing_event:
        return (
            {
                "status": "alreadyPresent",
                "requestId": request_id,
                "decisionPackHash": decision_pack_hash,
                "payloadVersion": payload["payloadVersion"],
                "mrmTarget": {
                    "tableLogicalName": queue_info.logical_name,
                    "entitySetName": queue_info.entity_set_name,
                    "keyColumns": ["fsi_agentid", "fsi_environmentid"],
                    "recordId": existing_row[queue_info.primary_id_attribute],
                    "action": "skipped",
                },
                "mrmEvent": {
                    "tableLogicalName": event_info.logical_name,
                    "entitySetName": event_info.entity_set_name,
                    "recordId": existing_event[event_info.primary_id_attribute],
                    "action": "skipped",
                },
                "warnings": warnings,
            },
            0,
        )

    queue_action = "updated" if existing_row else "created"
    queue_row = build_mrm_queue_row(
        payload,
        submitted_on=submitted_on,
        now=now,
        create=not bool(existing_row),
    )

    if existing_row:
        queue_record_id = existing_row[queue_info.primary_id_attribute]
        client.update_record(queue_info.entity_set_name, queue_record_id, queue_row)
    else:
        queue_record_id = client.create_record(queue_info.entity_set_name, queue_row)

    mrm_event_result: dict[str, Any] | None = None
    if event_info and not existing_event:
        try:
            event_row = build_mrm_event_row(
                payload,
                now=now,
                queue_record_id=queue_record_id,
                queue_action=queue_action,
            )
            event_record_id = client.create_record(event_info.entity_set_name, event_row)
            mrm_event_result = {
                "tableLogicalName": event_info.logical_name,
                "entitySetName": event_info.entity_set_name,
                "recordId": event_record_id,
                "action": "created",
            }
        except requests.HTTPError as exc:
            warnings.append(
                f"MRM compliance-event write failed ({exc.response.status_code if exc.response else 'unknown'}); the queue row was still written."
            )
        except ValueError as exc:
            warnings.append(
                f"MRM compliance-event sidecar was too large to persist ({exc}); the queue row was still written."
            )
    elif event_info and existing_event:
        warnings.append("Existing MRM compliance-event marker found without a matching queue row; recreated the queue row only.")
        mrm_event_result = {
            "tableLogicalName": event_info.logical_name,
            "entitySetName": event_info.entity_set_name,
            "recordId": existing_event[event_info.primary_id_attribute],
            "action": "reused",
        }
    elif not event_info:
        warnings.append("MRM compliance-event table not deployed; idempotency falls back to the model-inventory alternate key.")

    result = {
        "status": "queued",
        "requestId": request_id,
        "decisionPackHash": decision_pack_hash,
        "payloadVersion": payload["payloadVersion"],
        "mrmTarget": {
            "tableLogicalName": queue_info.logical_name,
            "entitySetName": queue_info.entity_set_name,
            "keyColumns": ["fsi_agentid", "fsi_environmentid"],
            "recordId": queue_record_id,
            "action": queue_action,
        },
        "warnings": warnings,
    }
    if mrm_event_result:
        result["mrmEvent"] = mrm_event_result
    return result, 0


def queue_local_fallback(client: Any, payload: dict[str, Any], *, now: datetime) -> tuple[dict[str, Any], int]:
    """Write the local intake-audit fallback record."""
    request_id = payload["intake"]["requestId"]
    decision_pack_hash = payload["decisionPackHash"]
    audit_info = probe_entity(client, LOCAL_AUDIT_TABLE)
    if audit_info is None:
        raise RuntimeError(
            "MRM solution is not deployed and the local fallback table fsi_intakeauditevent is unavailable."
        )

    existing_event = find_existing_local_fallback(
        client,
        audit_info,
        request_id=request_id,
        decision_pack_hash=decision_pack_hash,
    )
    if existing_event:
        return (
            {
                "status": "alreadyPresent",
                "requestId": request_id,
                "decisionPackHash": decision_pack_hash,
                "payloadVersion": payload["payloadVersion"],
                "fallback": {
                    "tableLogicalName": audit_info.logical_name,
                    "entitySetName": audit_info.entity_set_name,
                    "recordId": existing_event[audit_info.primary_id_attribute],
                    "eventType": "MRMHandoffPending",
                    "action": "skipped",
                },
                "warnings": [
                    "MRM solution not deployed in this environment; a local fallback record already exists.",
                ],
            },
            0,
        )

    reason = "MRM solution not deployed in this environment"
    row = build_local_audit_row(payload, now=now, reason=reason)
    record_id = client.create_record(audit_info.entity_set_name, row)
    return (
        {
            "status": "fallbackQueued",
            "requestId": request_id,
            "decisionPackHash": decision_pack_hash,
            "payloadVersion": payload["payloadVersion"],
            "fallback": {
                "tableLogicalName": audit_info.logical_name,
                "entitySetName": audit_info.entity_set_name,
                "recordId": record_id,
                "eventType": "MRMHandoffPending",
                "action": "created",
            },
            "warnings": [reason],
        },
        2,
    )


def build_dry_run_result(
    payload: dict[str, Any],
    *,
    environment_url: str,
    submitted_on: datetime,
    now: datetime,
) -> dict[str, Any]:
    """Return a side-effect-free plan for smoke tests and contract validation."""
    return {
        "dryRun": True,
        "status": "validated",
        "requestId": payload["intake"]["requestId"],
        "decisionPackHash": payload["decisionPackHash"],
        "payloadVersion": payload["payloadVersion"],
        "environmentUrl": environment_url,
        "mrmTarget": {
            "tableLogicalName": MRM_QUEUE_TABLE,
            "entitySetName": ENTITY_SET_FALLBACKS[MRM_QUEUE_TABLE],
            "keyColumns": ["fsi_agentid", "fsi_environmentid"],
            "plannedAction": "createOrUpdate",
        },
        "mappedQueueRow": build_mrm_queue_row(
            payload,
            submitted_on=submitted_on,
            now=now,
            create=True,
        ),
        "plannedComplianceEvent": {
            **build_mrm_event_row(
                payload,
                now=now,
                queue_record_id="<resolved-after-create>",
                queue_action="create",
            ),
            "fsi_eventdetails": compact_json(
                build_mrm_event_summary(
                    payload,
                    queue_record_id="<resolved-after-create>",
                    queue_action="create",
                )
            ),
        },
        "fallbackTarget": {
            "tableLogicalName": LOCAL_AUDIT_TABLE,
            "entitySetName": ENTITY_SET_FALLBACKS[LOCAL_AUDIT_TABLE],
            "eventType": "MRMHandoffPending",
        },
    }


def acquire_dataverse_token(environment_url: str, token_source: str) -> str:
    """Acquire a Dataverse token using the shared managed-identity-first pattern."""
    resource = environment_url.rstrip("/")
    if token_source == "mi":
        return get_token_via_managed_identity(resource)
    return get_token_via_cli(resource)


def main() -> int:
    """CLI entrypoint."""
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    parser = argparse.ArgumentParser(
        description="Queue a Tier-1 agent-intake request into model-risk-management-automation"
    )
    parser.add_argument(
        "--intake-request-id",
        help="Optional cross-check for payload.intake.requestId",
    )
    parser.add_argument(
        "--environment-url",
        required=True,
        help="Dataverse environment URL (for example, https://contoso.crm.dynamics.com)",
    )
    parser.add_argument(
        "--token-source",
        choices=["mi", "cli"],
        default="mi",
        help="Token source: managed identity (default) or azure-cli cache",
    )
    parser.add_argument(
        "--input-json",
        type=Path,
        required=True,
        help="Path to the handoff payload JSON file",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional path to write result JSON",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate the payload and show the planned writes without calling Dataverse",
    )
    args = parser.parse_args()

    try:
        payload = load_json_file(args.input_json)
        schema = load_json_file(SCHEMA_FILE)
        validate_payload_against_schema(payload, schema)
        assert_handoff_eligibility(payload)

        request_id = payload["intake"]["requestId"]
        if args.intake_request_id and args.intake_request_id != request_id:
            raise ValueError(
                "--intake-request-id does not match payload.intake.requestId "
                f"({args.intake_request_id} != {request_id})"
            )

        submitted_on = parse_datetime(payload["intake"]["submittedOnUtc"], "intake.submittedOnUtc")
        now = utc_now()

        if args.dry_run:
            result = build_dry_run_result(
                payload,
                environment_url=args.environment_url,
                submitted_on=submitted_on,
                now=now,
            )
            emit_result(result, args.output)
            LOG.info("Dry-run validation succeeded for intake request %s", request_id)
            return 0

        LOG.info("Acquiring Dataverse token via %s", args.token_source)
        token = acquire_dataverse_token(args.environment_url, args.token_source)
        client = build_dataverse_client(args.environment_url, token)

        queue_info = probe_entity(client, MRM_QUEUE_TABLE)
        if queue_info is None:
            result, exit_code = queue_local_fallback(client, payload, now=now)
        else:
            result, exit_code = queue_to_mrm(
                client,
                payload,
                queue_info=queue_info,
                now=now,
                submitted_on=submitted_on,
            )

        emit_result(result, args.output)
        if exit_code == 2:
            LOG.warning("MRM solution not deployed in this environment — handoff queued locally")
        else:
            LOG.info("MRM handoff %s for intake request %s", result["status"], request_id)
        return exit_code
    except FileNotFoundError as exc:
        LOG.error("File not found: %s", exc)
        return 1
    except (RuntimeError, ValueError) as exc:
        LOG.error("%s", exc)
        return 1
    except requests.HTTPError as exc:
        body = exc.response.text[:1000] if exc.response is not None else str(exc)
        LOG.error("Dataverse request failed: %s", body)
        return 1
    except Exception as exc:  # pragma: no cover - defensive catch for CLI usage
        LOG.exception("Unexpected failure during MRM handoff: %s", exc)
        return 1


if __name__ == "__main__":
    sys.exit(main())
