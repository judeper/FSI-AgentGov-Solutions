#!/usr/bin/env python3
"""Mint a Microsoft Entra Agent ID for an approved intake request.

Called from Power Automate Flow 3 (`docs/flow-configuration.md`) after a
sponsor approves an Express-path request or after the Standard / Full reviewer
chain closes. The returned service principal ID is written back to
`fsi_intakerequest.fsi_entraagentid` and forwarded to
`agent-registry-automation` as the canonical identity for the new agent.

Current Microsoft Graph shape (verified 2026-06-06 against Microsoft Learn
https://learn.microsoft.com/graph/api/agentidentity-post?view=graph-rest-1.0):
  POST https://graph.microsoft.com/v1.0/servicePrincipals/microsoft.graph.agentIdentity

The create action requires a display name, an `agentIdentityBlueprintId`
(the blueprint `appId` returned by `setup_agent_identity_blueprint.py`), and a
valid `sponsors@odata.bind` reference. Per the Learn create reference the
least-privileged create permission is AgentIdentity.Create.All (delegated and
application); AgentIdentity.CreateAsManager is an accepted higher-privileged
application permission. Supported built-in roles for non-owner delegated callers
are Agent ID Administrator and Agent ID Developer.

Authentication: managed-identity-first. Falls back to Azure CLI for admin
workstation testing.

Reviewer evidence schema for `--reviewer-attestations-json`:
[
  {
    "role": "InfoSec | Privacy | Compliance | Legal | MRM | Sponsor",
    "upn": "alice@contoso.com",
    "decidedOnUtc": "2026-05-16T12:34:56Z",
    "decisionPackHash": "sha256-hex"
  }
]

Express callers can omit reviewer evidence. Standard requires at least one
non-Sponsor attestation. Full requires at least three non-Sponsor attestations;
the upstream flow still enforces the authoritative quorum policy.

Usage:
  python setup_entra_agent_id.py \
      --intake-request-id <guid> \
      --display-name "Cash Reconciliation Helper" \
      --sponsor-upn alice@contoso.com \
      --blueprint-id <agentIdentityBlueprintId> \
      --output result.json
"""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote

import requests

from autodetect_environments import get_token_via_cli, get_token_via_managed_identity

LOG = logging.getLogger("agent-intake.entra")

GRAPH_BASE = "https://graph.microsoft.com"
GRAPH_RESOURCE = "https://graph.microsoft.com/"
AGENT_ID_CREATE_PATH = "/v1.0/servicePrincipals/microsoft.graph.agentIdentity"
AGENT_ID_LIST_PATH = "/v1.0/servicePrincipals/microsoft.graph.agentIdentity"
# Least-privileged create permission first, per the Microsoft Learn create reference
# (https://learn.microsoft.com/graph/api/agentidentity-post?view=graph-rest-1.0):
# AgentIdentity.Create.All is least privileged; AgentIdentity.CreateAsManager is an
# accepted higher-privileged application permission.
REQUIRED_CREATE_PERMISSIONS = ("AgentIdentity.Create.All", "AgentIdentity.CreateAsManager")
OPTIONAL_READ_PERMISSION = "AgentIdentity.Read.All"
APPROVAL_PATH_CHOICES = ("Express", "Standard", "Full")
ATTESTATION_ROLES = {
    "sponsor": "Sponsor",
    "infosec": "InfoSec",
    "privacy": "Privacy",
    "compliance": "Compliance",
    "legal": "Legal",
    "mrm": "MRM",
}
DECISION_PACK_HASH = re.compile(r"^[0-9a-fA-F]{64}$")
REVIEWER_EXTENSION_FIELD = "fsiReviewerAttestations"


def get_user(token: str, upn: str) -> dict[str, Any]:
    """Resolve a sponsor UPN to a Microsoft Graph user ID."""
    encoded = quote(upn, safe="")
    resp = requests.get(
        f"{GRAPH_BASE}/v1.0/users/{encoded}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        params={"$select": "id,userPrincipalName,displayName"},
        timeout=60,
    )
    if resp.status_code == 404:
        raise ValueError(f"Sponsor user not found: {upn}")
    resp.raise_for_status()
    return resp.json()


def normalize_approval_path(path_value: str) -> str:
    """Return the canonical approval-path value."""
    return next(choice for choice in APPROVAL_PATH_CHOICES if choice.casefold() == path_value.casefold())


def parse_iso8601_utc(timestamp_value: str) -> str:
    """Validate and normalize a UTC timestamp."""
    normalized = timestamp_value.strip()
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ValueError(f"Invalid decidedOnUtc value: {timestamp_value}") from exc
    if parsed.tzinfo is None:
        raise ValueError(f"decidedOnUtc must include a timezone: {timestamp_value}")
    return parsed.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_reviewer_attestations(
    raw_json: str | None,
    *,
    approval_path: str,
    sponsor_upn: str,
) -> list[dict[str, str]]:
    """Parse and validate reviewer-attestation evidence."""
    approval_path = normalize_approval_path(approval_path)
    if not raw_json:
        if approval_path != "Express":
            raise ValueError("--reviewer-attestations-json is required for Standard and Full approval paths.")
        return []

    try:
        items = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        raise ValueError("--reviewer-attestations-json must be valid JSON.") from exc

    if not isinstance(items, list) or not items:
        raise ValueError("--reviewer-attestations-json must be a non-empty JSON array.")

    normalized_items: list[dict[str, str]] = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            raise ValueError(f"Reviewer attestation entry {index} must be a JSON object.")

        missing = [field for field in ("role", "upn", "decidedOnUtc", "decisionPackHash") if field not in item]
        if missing:
            raise ValueError(
                f"Reviewer attestation entry {index} is missing required fields: {', '.join(sorted(missing))}."
            )

        role_key = str(item["role"]).strip().lower()
        if role_key not in ATTESTATION_ROLES:
            raise ValueError(
                f"Reviewer attestation entry {index} has unsupported role '{item['role']}'. "
                f"Allowed roles: {', '.join(ATTESTATION_ROLES.values())}."
            )

        upn = str(item["upn"]).strip().lower()
        if "@" not in upn:
            raise ValueError(f"Reviewer attestation entry {index} has an invalid UPN: {item['upn']}")

        decision_pack_hash = str(item["decisionPackHash"]).strip().lower()
        if not DECISION_PACK_HASH.fullmatch(decision_pack_hash):
            raise ValueError(
                f"Reviewer attestation entry {index} has an invalid decisionPackHash. Expected sha256 hex."
            )

        normalized_items.append(
            {
                "role": ATTESTATION_ROLES[role_key],
                "upn": upn,
                "decidedOnUtc": parse_iso8601_utc(str(item["decidedOnUtc"])),
                "decisionPackHash": decision_pack_hash,
            }
        )

    sponsor_entries = [entry for entry in normalized_items if entry["role"] == "Sponsor"]
    if not sponsor_entries:
        raise ValueError("Reviewer evidence must include at least one Sponsor attestation.")
    if sponsor_upn.lower() not in {entry["upn"] for entry in sponsor_entries}:
        raise ValueError("Reviewer evidence must include a Sponsor attestation for the same UPN passed via --sponsor-upn.")

    non_sponsor_entries = [entry for entry in normalized_items if entry["role"] != "Sponsor"]
    if approval_path == "Standard" and len(non_sponsor_entries) < 1:
        raise ValueError("Standard approval requires at least one non-Sponsor reviewer attestation.")
    if approval_path == "Full" and len(non_sponsor_entries) < 3:
        # The upstream flow still enforces the authoritative quorum policy. This local
        # default keeps the CLI payload honest when a Full path reaches the handoff step.
        raise ValueError("Full approval requires at least three non-Sponsor reviewer attestations.")

    return normalized_items


def build_reviewer_evidence(
    reviewer_attestations: list[dict[str, str]],
    *,
    approval_path: str,
) -> tuple[str, dict[str, Any]]:
    """Return the reviewer note string and open-type extension payload."""
    extension_payload = {
        "approvalPath": normalize_approval_path(approval_path),
        "reviewerAttestations": reviewer_attestations,
    }
    compact = json.dumps(extension_payload, separators=(",", ":"), sort_keys=True)
    if len(compact) <= 900:
        note_text = f"fsi-agent-intake-reviewers:{compact}"
    else:
        payload_hash = hashlib.sha256(compact.encode("utf-8")).hexdigest()
        note_text = (
            "fsi-agent-intake-reviewers:"
            f'{{"approvalPath":"{approval_path}","attestationCount":{len(reviewer_attestations)},'
            f'"payloadSha256":"{payload_hash}"}}'
        )
    return note_text, extension_payload


def planned_payload(
    *,
    display_name: str,
    sponsor_id: str,
    blueprint_id: str,
    intake_request_id: str,
    approval_path: str,
    reviewer_attestations: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    """Return the payload sent to Graph for agent identity creation."""
    payload: dict[str, Any] = {
        "displayName": display_name,
        "agentIdentityBlueprintId": blueprint_id,
        "sponsors@odata.bind": [f"{GRAPH_BASE}/v1.0/users/{sponsor_id}"],
        "tags": [
            "fsi-agent-intake",
            f"intake-request:{intake_request_id}",
            f"approval-path:{normalize_approval_path(approval_path).lower()}",
        ],
    }
    if reviewer_attestations:
        note_text, extension_payload = build_reviewer_evidence(
            reviewer_attestations,
            approval_path=approval_path,
        )
        payload["notes"] = note_text
        payload[REVIEWER_EXTENSION_FIELD] = extension_payload
    return payload


def ensure_create_ready(response: requests.Response) -> None:
    """Raise tailored errors for create failures."""
    if response.status_code in {401, 403}:
        raise PermissionError(
            "Agent ID create permission required. Grant either "
            f"{REQUIRED_CREATE_PERMISSIONS[0]} or {REQUIRED_CREATE_PERMISSIONS[1]} and verify the caller has an eligible Agent ID admin/developer role."
        )
    if response.status_code == 404:
        raise RuntimeError("Agent Identity create action not available in this tenant/cloud; verify Microsoft Entra Agent ID availability.")


def attach_reviewer_evidence(token: str, agent_id: str, *, note_text: str, extension_payload: dict[str, Any]) -> dict[str, Any]:
    """Patch reviewer evidence onto the created agent identity when POST extras are rejected."""
    patch_url = f"{GRAPH_BASE}/v1.0/servicePrincipals/{agent_id}/microsoft.graph.agentIdentity"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    full_payload = {
        "notes": note_text,
        REVIEWER_EXTENSION_FIELD: extension_payload,
    }
    response = requests.patch(patch_url, headers=headers, json=full_payload, timeout=60)
    if response.status_code in {401, 403}:
        raise PermissionError("Agent ID update permission required to attach reviewer evidence after create.")
    if response.status_code == 404:
        raise RuntimeError("Agent Identity update action not available in this tenant/cloud; reviewer evidence requires manual follow-up.")
    if response.status_code == 400:
        LOG.warning("Reviewer extension payload was rejected on PATCH; retrying with notes only.")
        notes_only = requests.patch(patch_url, headers=headers, json={"notes": note_text}, timeout=60)
        if notes_only.status_code in {401, 403}:
            raise PermissionError("Agent ID update permission required to attach reviewer notes after create.")
        if notes_only.status_code == 404:
            raise RuntimeError("Agent Identity update action not available in this tenant/cloud; reviewer evidence requires manual follow-up.")
        notes_only.raise_for_status()
        return {
            "reviewerEvidencePatched": True,
            "reviewerEvidenceStoredAsNotesOnly": True,
        }
    response.raise_for_status()
    return {
        "reviewerEvidencePatched": True,
        "reviewerEvidenceStoredAsNotesOnly": False,
    }


def mint_agent_id(
    token: str,
    *,
    display_name: str,
    sponsor_upn: str,
    blueprint_id: str,
    intake_request_id: str,
    approval_path: str,
    reviewer_attestations: list[dict[str, str]],
) -> dict[str, Any]:
    """Create a Microsoft Entra Agent ID service principal."""
    sponsor = get_user(token, sponsor_upn)
    payload = planned_payload(
        display_name=display_name,
        sponsor_id=sponsor["id"],
        blueprint_id=blueprint_id,
        intake_request_id=intake_request_id,
        approval_path=approval_path,
        reviewer_attestations=reviewer_attestations,
    )
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    resp = requests.post(
        f"{GRAPH_BASE}{AGENT_ID_CREATE_PATH}",
        headers=headers,
        json=payload,
        timeout=60,
    )
    if resp.status_code == 400 and reviewer_attestations:
        LOG.warning("Agent ID create rejected the reviewer-evidence fields; retrying create without them and patching afterwards.")
        base_payload = {
            key: value
            for key, value in payload.items()
            if key not in {"notes", REVIEWER_EXTENSION_FIELD}
        }
        resp = requests.post(
            f"{GRAPH_BASE}{AGENT_ID_CREATE_PATH}",
            headers=headers,
            json=base_payload,
            timeout=60,
        )
        ensure_create_ready(resp)
        resp.raise_for_status()
        result = resp.json()
        note_text, extension_payload = build_reviewer_evidence(
            reviewer_attestations,
            approval_path=approval_path,
        )
        result.update(
            attach_reviewer_evidence(
                token,
                result["id"],
                note_text=note_text,
                extension_payload=extension_payload,
            )
        )
    else:
        ensure_create_ready(resp)
        resp.raise_for_status()
        result = resp.json()
        if reviewer_attestations:
            result["reviewerEvidencePatched"] = False
            result["reviewerEvidenceStoredAsNotesOnly"] = False

    result["sponsor"] = sponsor
    if reviewer_attestations:
        result["approvalPath"] = normalize_approval_path(approval_path)
        result["reviewerAttestations"] = reviewer_attestations
    return result


def check_consent(token: str) -> dict[str, Any]:
    """Best-effort readiness check for Graph access and documented permissions."""
    result: dict[str, Any] = {
        "requiredCreatePermissions": list(REQUIRED_CREATE_PERMISSIONS),
        "optionalReadPermission": OPTIONAL_READ_PERMISSION,
        "checks": [],
        "readyForCreate": "unknown",
    }
    resp = requests.get(
        f"{GRAPH_BASE}{AGENT_ID_LIST_PATH}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        params={"$top": "1", "$select": "id,displayName"},
        timeout=60,
    )
    if resp.ok:
        result["checks"].append({"name": "listAgentIdentities", "status": "passed"})
    elif resp.status_code in {401, 403}:
        result["checks"].append({
            "name": "listAgentIdentities",
            "status": "warning",
            "detail": "Read check failed; this is expected if only create permissions were consented. Verify create permission grants in Entra admin center.",
            "httpStatus": resp.status_code,
        })
    else:
        result["checks"].append({"name": "listAgentIdentities", "status": "failed", "httpStatus": resp.status_code, "body": resp.text[:500]})
    return result


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Mint an Entra Agent ID for an approved intake request")
    parser.add_argument("--intake-request-id")
    parser.add_argument("--display-name")
    parser.add_argument("--sponsor-upn", dest="sponsor_upn")
    parser.add_argument("--owner-upn", dest="sponsor_upn", help="Deprecated alias for --sponsor-upn")
    parser.add_argument(
        "--blueprint-id",
        default=None,
        help="Blueprint appId (agentIdentityBlueprintId) returned by setup_agent_identity_blueprint.py",
    )
    parser.add_argument("--output", type=Path, help="Where to write result JSON; if omitted, prints to stdout")
    parser.add_argument("--token-source", choices=["mi", "cli"], default="mi")
    parser.add_argument("--dry-run", action="store_true", help="Skip the POST; emit the planned payload only")
    parser.add_argument("--check-consent", action="store_true", help="Print readiness checks and documented permission requirements")
    parser.add_argument("--approval-path", choices=APPROVAL_PATH_CHOICES, default="Express", help="Intake approval path")
    parser.add_argument(
        "--reviewer-attestations-json",
        help="JSON array of reviewer attestations for Standard and Full approval chains",
    )
    args = parser.parse_args()

    if args.check_consent:
        token = get_token_via_managed_identity(GRAPH_RESOURCE) if args.token_source == "mi" else get_token_via_cli(GRAPH_RESOURCE)
        result = check_consent(token)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result, indent=2))
        return 0

    missing = [name for name, value in {
        "--intake-request-id": args.intake_request_id,
        "--display-name": args.display_name,
        "--sponsor-upn": args.sponsor_upn,
        "--blueprint-id": args.blueprint_id,
    }.items() if not value]
    if missing:
        parser.error("Missing required arguments for minting: " + ", ".join(missing))

    reviewer_attestations = parse_reviewer_attestations(
        args.reviewer_attestations_json,
        approval_path=args.approval_path,
        sponsor_upn=args.sponsor_upn,
    )

    if args.dry_run:
        LOG.info("Dry-run mode")
        would_post: dict[str, Any] = {
            "method": "POST",
            "apiVersion": "v1.0",
            "url": f"{GRAPH_BASE}{AGENT_ID_CREATE_PATH}",
            "payload": planned_payload(
                display_name=args.display_name,
                sponsor_id="<resolved-sponsor-user-id>",
                blueprint_id=args.blueprint_id,
                intake_request_id=args.intake_request_id,
                approval_path=args.approval_path,
                reviewer_attestations=reviewer_attestations,
            ),
            "requiredCreatePermissions": list(REQUIRED_CREATE_PERMISSIONS),
        }
        result = {
            "dryRun": True,
            "approvalPath": normalize_approval_path(args.approval_path),
            "wouldPost": would_post,
        }
        if reviewer_attestations:
            # The create POST may reject the open-type reviewer fields; the live path then
            # retries the create without them and PATCHes the evidence on afterwards.
            result["wouldPatchReviewerEvidenceOnRejection"] = {
                "method": "PATCH",
                "apiVersion": "v1.0",
                "url": f"{GRAPH_BASE}/v1.0/servicePrincipals/<created-agent-id>/microsoft.graph.agentIdentity",
                "fields": ["notes", REVIEWER_EXTENSION_FIELD],
                "note": "Conditional fallback only; not sent when the create POST accepts the reviewer fields.",
            }
    else:
        token = get_token_via_managed_identity(GRAPH_RESOURCE) if args.token_source == "mi" else get_token_via_cli(GRAPH_RESOURCE)
        result = mint_agent_id(
            token,
            display_name=args.display_name,
            sponsor_upn=args.sponsor_upn,
            blueprint_id=args.blueprint_id,
            intake_request_id=args.intake_request_id,
            approval_path=args.approval_path,
            reviewer_attestations=reviewer_attestations,
        )
        LOG.info("Minted agent ID service principal: %s", result.get("id"))

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    else:
        print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
