#!/usr/bin/env python3
"""Idempotently create or find a Microsoft Entra Agent Identity blueprint.

This script automates the Stage 2 identity prerequisite for the agent-intake
solution. The Microsoft Graph blueprint endpoints were verified on 2026-05-16 against:
- https://learn.microsoft.com/graph/api/agentidentityblueprint-list?view=graph-rest-1.0
- https://learn.microsoft.com/graph/api/agentidentityblueprint-post?view=graph-rest-1.0

The script creates or finds the blueprint application, ensures the matching
agentIdentityBlueprintPrincipal exists (Graph-created blueprints don't create the
principal automatically), and configures Microsoft Graph inheritable scopes for
the blueprint. The emitted `agentIdentityBlueprintId` value is the blueprint
`appId`, which is the value expected by `setup_entra_agent_id.py`.

Requires AgentIdentityBlueprint.Create / AgentIdentityBlueprint.ReadWrite.All and
AgentIdentityBlueprintPrincipal.Create / AgentIdentityBlueprintPrincipal.ReadWrite.All.
When Microsoft Entra Agent ID isn't available, the script prints the manual admin-center
fallback steps from `docs/identity-records-automation.md` and exits with code 2.

Usage:
  python setup_agent_identity_blueprint.py --output blueprint.json --dry-run
  python setup_agent_identity_blueprint.py \
      --display-name "FSI-AgentIntake-Default-Blueprint" \
      --sponsor-upn alice@contoso.com \
      --allowed-scopes User.Read,Mail.Read \
      --output blueprint.json
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote

import requests

from autodetect_environments import get_token_via_cli, get_token_via_managed_identity

LOG = logging.getLogger("agent-intake.entra")

GRAPH_BASE = "https://graph.microsoft.com"
GRAPH_RESOURCE = "https://graph.microsoft.com/"
BLUEPRINT_COLLECTION_PATH = "/v1.0/applications/microsoft.graph.agentIdentityBlueprint"
BLUEPRINT_PRINCIPAL_COLLECTION_PATH = "/v1.0/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal"
MICROSOFT_GRAPH_APP_ID = "00000003-0000-0000-c000-000000000000"
DEFAULT_DISPLAY_NAME = "FSI-AgentIntake-Default-Blueprint"
DEFAULT_DESCRIPTION = (
    "Default Microsoft Entra Agent Identity blueprint for the FSI agent-intake solution. "
    "Created by Stage 2 automation for AGENT_INTAKE_AGENT_BLUEPRINT_ID."
)
DEFAULT_ALLOWED_SCOPES = ("User.Read",)
MANUAL_FALLBACK_HEADING = "## Manual fallback - Microsoft Entra Agent Identity blueprint"

# Verified 2026-05-16 against Microsoft Learn:
# https://learn.microsoft.com/graph/api/agentidentityblueprint-post?view=graph-rest-1.0
# https://learn.microsoft.com/graph/api/agentidentityblueprint-list?view=graph-rest-1.0
# https://learn.microsoft.com/graph/api/agentidentityblueprintprincipal-post?view=graph-rest-1.0
# https://learn.microsoft.com/graph/api/agentidentityblueprintprincipal-list?view=graph-rest-1.0


class ManualFallbackRequired(RuntimeError):
    """Raised when the tenant must use the documented manual fallback path."""


def write_json_output(path: Path | None, payload: dict[str, Any]) -> None:
    """Write result JSON to disk or stdout."""
    if path:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        LOG.info("Wrote blueprint metadata to %s", path)
    else:
        print(json.dumps(payload, indent=2))


def read_manual_fallback_section() -> str:
    """Return the manual fallback section from the Stage 2 automation document."""
    doc_path = Path(__file__).resolve().parent.parent / "docs" / "identity-records-automation.md"
    fallback_text = (
        "## Manual fallback - Microsoft Entra Agent Identity blueprint\n"
        "1. Sign in to https://entra.microsoft.com.\n"
        "2. Browse to **Entra ID** > **Agents** > **Agent blueprints**.\n"
        "3. Create a blueprint named `FSI-AgentIntake-Default-Blueprint`, add a sponsor, and record the resulting `appId` as `AGENT_INTAKE_AGENT_BLUEPRINT_ID`.\n"
        "4. If the blueprint was created through Microsoft Graph rather than the admin-center wizard, create the corresponding agent identity blueprint principal before enabling agent creation.\n"
    )
    if not doc_path.exists():
        return fallback_text

    lines = doc_path.read_text(encoding="utf-8").splitlines()
    capturing = False
    captured: list[str] = []
    for line in lines:
        if line.strip() == MANUAL_FALLBACK_HEADING:
            capturing = True
        if capturing:
            if captured and line.startswith("## "):
                break
            captured.append(line)
    return "\n".join(captured).strip() or fallback_text


def acquire_token(token_source: str) -> tuple[str, str]:
    """Acquire a Microsoft Graph token, preferring managed identity when requested."""
    if token_source == "cli":
        return get_token_via_cli(GRAPH_RESOURCE), "cli"
    try:
        return get_token_via_managed_identity(GRAPH_RESOURCE), "mi"
    except Exception as exc:  # pragma: no cover - depends on environment configuration
        LOG.warning("Managed identity token acquisition failed (%s). Falling back to Azure CLI.", exc)
        return get_token_via_cli(GRAPH_RESOURCE), "cli"


def graph_headers(token: str) -> dict[str, str]:
    """Return common headers for Microsoft Graph requests."""
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }


def graph_error_message(response: requests.Response) -> str:
    """Extract a readable error message from a Graph response."""
    try:
        payload = response.json()
    except ValueError:
        return response.text[:500]
    error = payload.get("error", {})
    if isinstance(error, dict):
        code = error.get("code")
        message = error.get("message")
        if code or message:
            return f"{code or 'GraphError'}: {message or 'Unknown error'}"
    return json.dumps(payload)[:500]


def raise_for_feature_gate(response: requests.Response, action: str) -> None:
    """Raise a manual-fallback exception for feature-gated or unavailable endpoints."""
    detail = graph_error_message(response)
    if response.status_code in {403, 404}:
        raise ManualFallbackRequired(f"{action} is not available for this tenant or caller. {detail}")
    lowered = detail.lower()
    if any(marker in lowered for marker in ("feature", "not available", "unsupported", "not enabled")):
        raise ManualFallbackRequired(f"{action} is not available for this tenant. {detail}")


def graph_get_collection(token: str, url: str, *, action: str, params: dict[str, str] | None = None) -> list[dict[str, Any]]:
    """Retrieve all pages for a Microsoft Graph collection request."""
    items: list[dict[str, Any]] = []
    next_url = url
    next_params = params
    while next_url:
        response = requests.get(
            next_url,
            headers=graph_headers(token),
            params=next_params,
            timeout=60,
        )
        raise_for_feature_gate(response, action)
        response.raise_for_status()
        payload = response.json()
        items.extend(payload.get("value", []))
        next_url = payload.get("@odata.nextLink")
        next_params = None
    return items


def get_user(token: str, upn: str) -> dict[str, Any]:
    """Resolve a sponsor UPN to a Microsoft Graph user."""
    encoded = quote(upn, safe="")
    response = requests.get(
        f"{GRAPH_BASE}/v1.0/users/{encoded}",
        headers=graph_headers(token),
        params={"$select": "id,userPrincipalName,displayName"},
        timeout=60,
    )
    if response.status_code == 404:
        raise ValueError(f"Sponsor user not found: {upn}")
    raise_for_feature_gate(response, "Resolving sponsor user")
    response.raise_for_status()
    return response.json()


def get_current_user(token: str) -> dict[str, Any]:
    """Return the current delegated user, if one is available."""
    response = requests.get(
        f"{GRAPH_BASE}/v1.0/me",
        headers=graph_headers(token),
        params={"$select": "id,userPrincipalName,displayName"},
        timeout=60,
    )
    raise_for_feature_gate(response, "Resolving the current signed-in user")
    response.raise_for_status()
    return response.json()


def resolve_sponsor(token: str, sponsor_upn: str | None, token_source_used: str) -> dict[str, Any]:
    """Resolve the sponsor for the blueprint create request."""
    if sponsor_upn:
        return get_user(token, sponsor_upn)
    if token_source_used != "cli":
        raise ValueError("Provide --sponsor-upn (or AGENT_INTAKE_BLUEPRINT_SPONSOR_UPN) when using managed identity.")
    return get_current_user(token)


def normalize_allowed_scopes(raw_value: str | None) -> list[str]:
    """Parse the comma-separated allowed-scopes argument."""
    if raw_value is None:
        return list(DEFAULT_ALLOWED_SCOPES)
    scopes = [scope.strip() for scope in raw_value.split(",") if scope.strip()]
    if not scopes:
        return []
    return list(dict.fromkeys(scopes))


def build_blueprint_payload(*, display_name: str, description: str, sponsor_id: str) -> dict[str, Any]:
    """Return the payload used to create a blueprint."""
    return {
        "displayName": display_name,
        "description": description,
        "signInAudience": "AzureADMyOrg",
        "tags": [
            "fsi-agent-intake",
            "identity-records-automation",
        ],
        "sponsors@odata.bind": [f"{GRAPH_BASE}/v1.0/users/{sponsor_id}"],
    }


def find_blueprint_by_display_name(token: str, display_name: str) -> dict[str, Any] | None:
    """Return the first blueprint that matches the requested display name."""
    blueprints = graph_get_collection(
        token,
        f"{GRAPH_BASE}{BLUEPRINT_COLLECTION_PATH}",
        action="Listing agent identity blueprints",
        params={"$select": "id,appId,displayName,description,uniqueName,tags"},
    )
    matches = [
        blueprint
        for blueprint in blueprints
        if blueprint.get("displayName", "").casefold() == display_name.casefold()
    ]
    if len(matches) > 1:
        raise ValueError(
            f"Multiple agent identity blueprints matched display name '{display_name}'. "
            "Choose a unique display name or remove the duplicates."
        )
    return matches[0] if matches else None


def find_blueprint_principal_by_app_id(token: str, app_id: str) -> dict[str, Any] | None:
    """Return the blueprint principal associated with the blueprint appId, if present."""
    principals = graph_get_collection(
        token,
        f"{GRAPH_BASE}{BLUEPRINT_PRINCIPAL_COLLECTION_PATH}",
        action="Listing agent identity blueprint principals",
        params={"$select": "id,appId,displayName,servicePrincipalType"},
    )
    matches = [
        principal
        for principal in principals
        if principal.get("appId", "").casefold() == app_id.casefold()
    ]
    return matches[0] if matches else None


def scope_configuration(scopes: list[str]) -> dict[str, Any]:
    """Return the inheritablePermissions payload for Microsoft Graph scopes."""
    if not scopes:
        return {
            "resourceAppId": MICROSOFT_GRAPH_APP_ID,
            "inheritableScopes": {
                "@odata.type": "#microsoft.graph.noScopes",
                "kind": "none",
            },
            "inheritableRoles": {
                "@odata.type": "#microsoft.graph.noRoles",
                "kind": "none",
            },
        }
    if len(scopes) == 1 and scopes[0].casefold() in {"all", "*"}:
        return {
            "resourceAppId": MICROSOFT_GRAPH_APP_ID,
            "inheritableScopes": {
                "@odata.type": "#microsoft.graph.allAllowedScopes",
                "kind": "allAllowed",
            },
            "inheritableRoles": {
                "@odata.type": "#microsoft.graph.noRoles",
                "kind": "none",
            },
        }
    return {
        "resourceAppId": MICROSOFT_GRAPH_APP_ID,
        "inheritableScopes": {
            "@odata.type": "#microsoft.graph.enumeratedScopes",
            "kind": "enumerated",
            "scopes": scopes,
        },
        "inheritableRoles": {
            "@odata.type": "#microsoft.graph.noRoles",
            "kind": "none",
        },
    }


def permissions_match(existing: dict[str, Any], desired: dict[str, Any]) -> bool:
    """Return True when the existing inheritable permission matches the desired scopes."""
    if existing.get("resourceAppId") != desired.get("resourceAppId"):
        return False
    existing_scopes = existing.get("inheritableScopes", {})
    desired_scopes = desired.get("inheritableScopes", {})
    existing_roles = existing.get("inheritableRoles", {})
    desired_roles = desired.get("inheritableRoles", {})
    if existing_scopes.get("@odata.type") != desired_scopes.get("@odata.type"):
        return False
    if existing_roles.get("@odata.type") != desired_roles.get("@odata.type"):
        return False
    return sorted(existing_scopes.get("scopes", [])) == sorted(desired_scopes.get("scopes", []))


def ensure_inheritable_permissions(token: str, blueprint_object_id: str, *, allowed_scopes: list[str]) -> dict[str, Any]:
    """Ensure the blueprint has the requested Microsoft Graph inheritable scopes configured."""
    collection_url = (
        f"{GRAPH_BASE}/v1.0/applications/{blueprint_object_id}/microsoft.graph.agentIdentityBlueprint/inheritablePermissions"
    )
    response = requests.get(collection_url, headers=graph_headers(token), timeout=60)
    raise_for_feature_gate(response, "Listing blueprint inheritable permissions")
    response.raise_for_status()
    existing_entries = response.json().get("value", [])
    existing_entry = next(
        (entry for entry in existing_entries if entry.get("resourceAppId") == MICROSOFT_GRAPH_APP_ID),
        None,
    )
    desired = scope_configuration(allowed_scopes)

    if existing_entry and permissions_match(existing_entry, desired):
        return {
            "resourceAppId": MICROSOFT_GRAPH_APP_ID,
            "status": "AlreadyConfigured",
            "inheritablePermissions": existing_entry,
        }

    if existing_entry is None:
        write_response = requests.post(
            collection_url,
            headers={**graph_headers(token), "Content-Type": "application/json", "OData-Version": "4.0"},
            json=desired,
            timeout=60,
        )
        raise_for_feature_gate(write_response, "Creating blueprint inheritable permissions")
        write_response.raise_for_status()
        return {
            "resourceAppId": MICROSOFT_GRAPH_APP_ID,
            "status": "Created",
            "inheritablePermissions": write_response.json(),
        }

    write_response = requests.patch(
        f"{collection_url}/{MICROSOFT_GRAPH_APP_ID}",
        headers={**graph_headers(token), "Content-Type": "application/json", "OData-Version": "4.0"},
        json=desired,
        timeout=60,
    )
    raise_for_feature_gate(write_response, "Updating blueprint inheritable permissions")
    write_response.raise_for_status()
    return {
        "resourceAppId": MICROSOFT_GRAPH_APP_ID,
        "status": "Updated",
        "inheritablePermissions": write_response.json(),
    }


def ensure_blueprint_principal(token: str, app_id: str) -> dict[str, Any]:
    """Create or find the blueprint principal associated with the blueprint appId."""
    existing = find_blueprint_principal_by_app_id(token, app_id)
    if existing:
        return {
            "created": False,
            "id": existing.get("id"),
            "displayName": existing.get("displayName"),
        }

    response = requests.post(
        f"{GRAPH_BASE}{BLUEPRINT_PRINCIPAL_COLLECTION_PATH}",
        headers={**graph_headers(token), "Content-Type": "application/json"},
        json={"appId": app_id},
        timeout=60,
    )
    raise_for_feature_gate(response, "Creating the blueprint principal")
    if response.status_code == 409:
        existing = find_blueprint_principal_by_app_id(token, app_id)
        if existing:
            return {
                "created": False,
                "id": existing.get("id"),
                "displayName": existing.get("displayName"),
            }
    response.raise_for_status()
    principal = response.json()
    return {
        "created": True,
        "id": principal.get("id"),
        "displayName": principal.get("displayName"),
    }


def create_or_find_blueprint(
    token: str,
    *,
    display_name: str,
    description: str,
    sponsor: dict[str, Any],
    allowed_scopes: list[str],
) -> dict[str, Any]:
    """Create the blueprint when missing, or return the existing blueprint when present."""
    existing = find_blueprint_by_display_name(token, display_name)
    if existing:
        blueprint = existing
        created = False
    else:
        payload = build_blueprint_payload(
            display_name=display_name,
            description=description,
            sponsor_id=sponsor["id"],
        )
        response = requests.post(
            f"{GRAPH_BASE}{BLUEPRINT_COLLECTION_PATH}",
            headers={**graph_headers(token), "Content-Type": "application/json"},
            json=payload,
            timeout=60,
        )
        raise_for_feature_gate(response, "Creating the agent identity blueprint")
        if response.status_code == 409:
            existing = find_blueprint_by_display_name(token, display_name)
            if not existing:
                response.raise_for_status()
            blueprint = existing
            created = False
        else:
            response.raise_for_status()
            blueprint = response.json()
            created = True

    principal = ensure_blueprint_principal(token, blueprint["appId"])
    permissions = ensure_inheritable_permissions(
        token,
        blueprint["id"],
        allowed_scopes=allowed_scopes,
    )
    return {
        "created": created,
        "displayName": blueprint.get("displayName"),
        "description": blueprint.get("description"),
        "agentIdentityBlueprintId": blueprint.get("appId"),
        "blueprintObjectId": blueprint.get("id"),
        "sponsor": sponsor,
        "blueprintPrincipal": principal,
        "configuredInheritablePermissions": permissions,
    }


def planned_blueprint_result(
    *,
    display_name: str,
    description: str,
    sponsor: dict[str, Any],
    allowed_scopes: list[str],
    token_source_requested: str,
) -> dict[str, Any]:
    """Return the planned Graph calls without executing them."""
    payload = build_blueprint_payload(
        display_name=display_name,
        description=description,
        sponsor_id=sponsor["id"],
    )
    permissions_payload = scope_configuration(allowed_scopes)
    return {
        "dryRun": True,
        "tokenSourceRequested": token_source_requested,
        "displayName": display_name,
        "description": description,
        "allowedScopes": allowed_scopes,
        "sponsor": sponsor,
        "agentIdentityBlueprintId": "<new-agent-identity-blueprint-app-id>",
        "blueprintObjectId": "<new-agent-identity-blueprint-object-id>",
        "wouldPost": {
            "url": f"{GRAPH_BASE}{BLUEPRINT_COLLECTION_PATH}",
            "payload": payload,
        },
        "blueprintPrincipal": {
            "created": True,
            "dryRun": True,
            "id": "<new-agent-identity-blueprint-principal-id>",
            "wouldPost": {
                "url": f"{GRAPH_BASE}{BLUEPRINT_PRINCIPAL_COLLECTION_PATH}",
                "payload": {"appId": "<new-agent-identity-blueprint-app-id>"},
            },
        },
        "configuredInheritablePermissions": {
            "resourceAppId": MICROSOFT_GRAPH_APP_ID,
            "status": "DryRunPending",
            "inheritablePermissions": permissions_payload,
            "wouldPost": {
                "url": (
                    f"{GRAPH_BASE}/v1.0/applications/"
                    "<new-agent-identity-blueprint-object-id>/microsoft.graph.agentIdentityBlueprint/inheritablePermissions"
                ),
                "payload": permissions_payload,
            },
        },
    }


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Create or find the agent-intake Microsoft Entra Agent Identity blueprint")
    parser.add_argument("--display-name", default=DEFAULT_DISPLAY_NAME, help="Blueprint display name")
    parser.add_argument("--description", default=DEFAULT_DESCRIPTION, help="Blueprint description")
    parser.add_argument(
        "--allowed-scopes",
        help="Comma-separated Microsoft Graph delegated scopes to configure as inheritable permissions; use '*' or 'all' for all Graph scopes",
    )
    parser.add_argument(
        "--sponsor-upn",
        default=os.environ.get("AGENT_INTAKE_BLUEPRINT_SPONSOR_UPN"),
        help="Sponsor UPN for blueprint creation; defaults to AGENT_INTAKE_BLUEPRINT_SPONSOR_UPN or the current Azure CLI user",
    )
    parser.add_argument("--token-source", choices=["mi", "cli"], default="mi")
    parser.add_argument("--output", type=Path, help="Where to write the resulting blueprint metadata")
    parser.add_argument("--dry-run", action="store_true", help="Emit the planned Graph calls without executing them")
    args = parser.parse_args()

    allowed_scopes = normalize_allowed_scopes(args.allowed_scopes)

    try:
        if args.dry_run:
            sponsor = {
                "id": "<resolved-sponsor-object-id>",
                "userPrincipalName": args.sponsor_upn or "<current-cli-user-or-provide-sponsor-upn>",
                "displayName": "<resolved-sponsor-display-name>",
            }
            result = planned_blueprint_result(
                display_name=args.display_name,
                description=args.description,
                sponsor=sponsor,
                allowed_scopes=allowed_scopes,
                token_source_requested=args.token_source,
            )
        else:
            token, token_source_used = acquire_token(args.token_source)
            LOG.info("Using Microsoft Graph token source: %s", token_source_used)
            sponsor = resolve_sponsor(token, args.sponsor_upn, token_source_used)
            result = create_or_find_blueprint(
                token,
                display_name=args.display_name,
                description=args.description,
                sponsor=sponsor,
                allowed_scopes=allowed_scopes,
            )
            result["allowedScopes"] = allowed_scopes
            result["tokenSourceUsed"] = token_source_used
            LOG.info("Resolved blueprint appId: %s", result.get("agentIdentityBlueprintId"))

        write_json_output(args.output, result)
        return 0
    except ManualFallbackRequired as exc:
        payload = {
            "manualFallback": True,
            "reason": str(exc),
            "displayName": args.display_name,
            "allowedScopes": allowed_scopes,
        }
        write_json_output(args.output, payload)
        print(str(exc), file=sys.stderr)
        print(read_manual_fallback_section(), file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
