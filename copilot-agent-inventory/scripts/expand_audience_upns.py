#!/usr/bin/env python3
"""Expand an agent's sharing audience to concrete member UPNs (CBG input).

Copilot Billing Governance (CBG) consumes a per-agent ``intendedUsers[]`` list of
UPNs. The Copilot Agent Inventory ``fsi_caiauthshare`` row records the sharing
*audience* as security-group references (``fsi_viewergroups`` /
``fsi_editorprincipals`` / authorized security group ids), NOT enumerated users.
This module bridges that gap: it expands each shared security group to its member
UPNs via Microsoft Graph **transitive** membership
(``GET /groups/{id}/transitiveMembers``, permission ``GroupMember.Read.All``),
which flattens **nested groups** automatically.

Defensive behaviours (accuracy is customer-facing):

  * **"Everyone in the organization"** sharing is detected and marked with a
    ``wholeTenant`` flag; the tenant is **never enumerated**. A configurable
    ``--whole-tenant-cap`` is recorded for the downstream consumer but the
    expansion emits an empty UPN list for whole-tenant audiences.
  * **Per-group cap** (``--max-members-per-group``) bounds very large groups; the
    audience is flagged ``truncated`` when a cap is hit so a partial list is never
    mistaken for a complete one.
  * **Throttling** (HTTP 429) uses Retry-After-aware exponential backoff; a group
    that cannot be resolved records a per-group ``error`` rather than silently
    dropping members.
  * **De-duplication** across overlapping viewer/editor groups.
  * **Agents with no sharing** resolve cleanly to an empty audience.

Scope note: only the ``intendedUsers[].upn`` list is produced here (R5 gap #1).
The per-user ``hasCopilotLicense`` / cohort flags are separate downstream gaps and
are intentionally not populated by this module.

The network-touching work lives in ``GraphMemberResolver``; the orchestration
(``expand_agent_audience``) takes any resolver, so it is unit-tested without a
live tenant. ``--dry-run`` logs planned work and contacts nothing.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional, Protocol

logger = logging.getLogger("expand_audience_upns")

# =============================================================================
# Constants
# =============================================================================

GRAPH_BASE = "https://graph.microsoft.com/v1.0"
GRAPH_SCOPE = "https://graph.microsoft.com/.default"
GRAPH_PAGE_SIZE = 999
MAX_BACKOFF_SECONDS = 60

# Refresh the Graph access token when it is within this window of expiry. A long
# audience-expansion run can exceed the ~60-minute token lifetime, so the token
# is re-acquired per request once it nears expiry rather than cached for the
# whole resolver lifetime (which previously caused 401s on late agents).
TOKEN_REFRESH_SKEW_SECONDS = 300

DEFAULT_MAX_MEMBERS_PER_GROUP = 1000
DEFAULT_WHOLE_TENANT_CAP = 0  # 0 = never enumerate the tenant for whole-tenant shares

# Strong "Everyone in the organization" sentinels (lowercased). Conservative on
# purpose: a generic name like "All Users" can be a real distribution group, so
# the preferred signal is an explicit marker (sharedWithEveryone / type=Everyone)
# captured upstream. Override with --whole-tenant-sentinels.
DEFAULT_WHOLE_TENANT_SENTINELS = (
    "everyone",
    "everyone in the organization",
    "everyone except external users",
)

# fsi_audienceresolutionstatus values.
STATUS_COMPLETE = "Complete"
STATUS_PARTIAL = "Partial"
STATUS_WHOLE_TENANT = "WholeTenantNotEnumerated"
STATUS_FAILED = "Failed"
STATUS_NOT_RESOLVED = "NotResolved"


# =============================================================================
# Pure HTTP / OData helpers
# =============================================================================


def _parse_retry_after(value: Optional[str], fallback: float) -> float:
    """Parse an HTTP ``Retry-After`` header into a delay in seconds.

    ``Retry-After`` is either a non-negative number of seconds or an RFC 7231
    HTTP-date (e.g. ``Wed, 21 Oct 2026 07:28:00 GMT``). A naive ``float(value)``
    crashes on the date form; this helper tries int/float first, then falls back
    to date parsing, and finally to ``fallback`` for missing/garbage values so a
    throttled request never raises while computing its backoff.
    """
    if value is None:
        return fallback
    text = value.strip()
    if not text:
        return fallback
    try:
        seconds = float(text)
        return seconds if seconds >= 0 else fallback
    except ValueError:
        pass
    try:
        from email.utils import parsedate_to_datetime

        retry_at = parsedate_to_datetime(text)
    except (TypeError, ValueError, IndexError):
        return fallback
    if retry_at is None:
        return fallback
    if retry_at.tzinfo is None:
        retry_at = retry_at.replace(tzinfo=timezone.utc)
    delta = (retry_at - datetime.now(timezone.utc)).total_seconds()
    return delta if delta > 0 else fallback


def _odata_escape(value: Any) -> str:
    """Escape a string literal for an OData ``$filter`` (single quote -> doubled).

    OData string literals are single-quoted; an unescaped quote in the value
    breaks the query (and is an injection vector). Per the OData spec a literal
    single quote is escaped by doubling it.
    """
    return str(value).replace("'", "''")


# =============================================================================
# Reference normalization (pure)
# =============================================================================


@dataclass
class NormalizedRef:
    """A normalized sharing reference resolved from heterogeneous input."""

    kind: str  # "group" | "user_upn" | "user_id" | "whole_tenant" | "unknown"
    value: Optional[str] = None
    display: Optional[str] = None


def _looks_like_upn(text: str) -> bool:
    return "@" in text


def _whole_tenant_match(text: Optional[str], sentinels: tuple[str, ...]) -> bool:
    return bool(text) and text.strip().lower() in sentinels


def _ref_id(raw: dict) -> Optional[str]:
    for key in ("id", "groupId", "objectId", "principalId", "value"):
        if raw.get(key):
            return str(raw[key])
    return None


def _ref_type(raw: dict) -> str:
    return str(raw.get("type") or raw.get("principalType") or raw.get("@odata.type") or "").lower()


def normalize_group_ref(raw: Any, sentinels: tuple[str, ...]) -> NormalizedRef:
    """Normalize a viewer/authorized-security-group reference to a NormalizedRef.

    In this context a bare GUID is a group id (these are security-group ids).
    """
    if isinstance(raw, str):
        text = raw.strip()
        if _whole_tenant_match(text, sentinels):
            return NormalizedRef("whole_tenant", display=text)
        return NormalizedRef("group", value=text, display=text)
    if isinstance(raw, dict):
        display = raw.get("displayName") or raw.get("name")
        if raw.get("wholeTenant") is True or "everyone" in _ref_type(raw):
            return NormalizedRef("whole_tenant", display=display)
        if _whole_tenant_match(display, sentinels):
            return NormalizedRef("whole_tenant", display=display)
        gid = _ref_id(raw)
        if gid:
            return NormalizedRef("group", value=gid, display=display)
    return NormalizedRef("unknown", display=str(raw)[:200])


def normalize_editor_ref(raw: Any, sentinels: tuple[str, ...]) -> NormalizedRef:
    """Normalize an editor principal (individual user OR group) to a NormalizedRef."""
    if isinstance(raw, str):
        text = raw.strip()
        if _whole_tenant_match(text, sentinels):
            return NormalizedRef("whole_tenant", display=text)
        if _looks_like_upn(text):
            return NormalizedRef("user_upn", value=text, display=text)
        # A bare GUID editor ref is ambiguous; treat as a group id and expand
        # (Copilot Studio editor shares commonly target security groups). A
        # failed expansion is reported as a per-ref error rather than dropped.
        return NormalizedRef("group", value=text, display=text)
    if isinstance(raw, dict):
        display = raw.get("displayName") or raw.get("name")
        upn = raw.get("upn") or raw.get("userPrincipalName")
        if upn:
            return NormalizedRef("user_upn", value=str(upn), display=display or str(upn))
        rtype = _ref_type(raw)
        if raw.get("wholeTenant") is True or "everyone" in rtype:
            return NormalizedRef("whole_tenant", display=display)
        rid = _ref_id(raw)
        if rid and ("group" in rtype or raw.get("securityEnabled") is True):
            return NormalizedRef("group", value=rid, display=display)
        if rid and ("user" in rtype or "member" in rtype):
            return NormalizedRef("user_id", value=rid, display=display)
        if rid:
            # Unknown principal type -> attempt group expansion (best effort).
            return NormalizedRef("group", value=rid, display=display)
    return NormalizedRef("unknown", display=str(raw)[:200])


def detect_whole_tenant(agent: dict, sentinels: tuple[str, ...]) -> bool:
    """Return True when the agent is shared with 'Everyone in the organization'."""
    if agent.get("sharedWithEveryone") is True or agent.get("wholeTenant") is True:
        return True
    for raw in list(agent.get("viewerGroups") or []) + list(agent.get("editorPrincipals") or []):
        ref = normalize_group_ref(raw, sentinels)
        if ref.kind == "whole_tenant":
            return True
    return False


# =============================================================================
# Resolver protocol + result types
# =============================================================================


@dataclass
class ResolveResult:
    """Outcome of resolving a single group's transitive members."""

    upns: list[str] = field(default_factory=list)
    truncated: bool = False
    error: Optional[str] = None


class MemberResolver(Protocol):
    """Protocol for resolving group members / user UPNs (real or fake)."""

    def transitive_member_upns(self, group_id: str) -> ResolveResult: ...

    def user_upn(self, user_id: str) -> Optional[str]: ...


@dataclass
class ExpandConfig:
    """Tunables for an audience-expansion pass."""

    max_members_per_group: int = DEFAULT_MAX_MEMBERS_PER_GROUP
    whole_tenant_cap: int = DEFAULT_WHOLE_TENANT_CAP
    sentinels: tuple[str, ...] = DEFAULT_WHOLE_TENANT_SENTINELS


# =============================================================================
# Core orchestration (pure given a resolver)
# =============================================================================


def _derive_status(
    whole_tenant: bool,
    had_refs: bool,
    upn_count: int,
    truncated: bool,
    errors: list[dict],
    tenant_signal_known: bool = True,
) -> str:
    if whole_tenant:
        return STATUS_WHOLE_TENANT
    if not had_refs:
        if not tenant_signal_known:
            # No sharing refs AND no per-agent whole-tenant signal: the posture is
            # incomplete, so an empty audience cannot be asserted for a possibly
            # tenant-reachable agent. Never emit a confident empty here.
            return STATUS_PARTIAL
        # No groups or principals shared -> a cleanly empty audience.
        return STATUS_COMPLETE
    if errors and upn_count == 0:
        return STATUS_FAILED
    if errors or truncated:
        return STATUS_PARTIAL
    return STATUS_COMPLETE


def _has_tenant_signal(agent: dict, had_refs: bool) -> bool:
    """Return True when the posture carries a usable whole-tenant determination.

    An explicit per-agent ``sharedWithEveryone`` / ``wholeTenant`` boolean, or any
    viewer/editor refs to resolve, constitute a usable signal. A posture with none
    of these (e.g. a Dataverse row whose ``fsi_sharedwitheveryone`` column is unset,
    flagged via ``wholeTenantSignalKnown=False``) cannot be asserted as a confident
    empty audience.
    """
    if isinstance(agent.get("sharedWithEveryone"), bool):
        return True
    if isinstance(agent.get("wholeTenant"), bool):
        return True
    if had_refs:
        return True
    return bool(agent.get("wholeTenantSignalKnown", True))


def expand_agent_audience(
    agent: dict, resolver: MemberResolver, config: ExpandConfig
) -> dict:
    """Expand one agent's sharing audience to a de-duplicated UPN list.

    Honors the whole-tenant rule (no enumeration), the per-group cap (truncation
    flag), nested groups (via the resolver's transitive expansion), and overlap
    de-duplication. Returns a CBG-shaped per-agent object plus governance flags.
    """
    agent_id = agent.get("fsi_agentid") or agent.get("agentId") or ""
    agent_name = agent.get("fsi_agentname") or agent.get("agentName")
    environment_id = agent.get("fsi_environmentid") or agent.get("environmentId")

    whole_tenant = detect_whole_tenant(agent, config.sentinels)

    upns: dict[str, None] = {}  # ordered de-dup set
    source_groups: list[dict] = []
    errors: list[dict] = []
    any_truncated = False

    viewer_refs = [normalize_group_ref(r, config.sentinels)
                   for r in (agent.get("viewerGroups") or [])]
    editor_refs = [normalize_editor_ref(r, config.sentinels)
                   for r in (agent.get("editorPrincipals") or [])]
    all_refs = viewer_refs + editor_refs
    had_refs = bool(all_refs)

    if not whole_tenant:
        for ref in all_refs:
            if ref.kind == "user_upn" and ref.value:
                upns.setdefault(ref.value, None)
            elif ref.kind == "user_id" and ref.value:
                resolved = resolver.user_upn(ref.value)
                if resolved:
                    upns.setdefault(resolved, None)
                else:
                    errors.append({"ref": ref.value, "error": "user UPN not resolved"})
            elif ref.kind == "group" and ref.value:
                result = resolver.transitive_member_upns(ref.value)
                for upn in result.upns:
                    upns.setdefault(upn, None)
                any_truncated = any_truncated or result.truncated
                source_groups.append({
                    "id": ref.value,
                    "displayName": ref.display,
                    "memberCount": len(result.upns),
                    "truncated": result.truncated,
                    "error": result.error,
                })
                if result.error:
                    errors.append({"ref": ref.value, "error": result.error})
            elif ref.kind == "unknown":
                errors.append({"ref": ref.display, "error": "unrecognized sharing reference"})

    upn_list = sorted(upns)
    tenant_signal_known = _has_tenant_signal(agent, had_refs)
    if not whole_tenant and not had_refs and not tenant_signal_known:
        logger.warning(
            "Agent %s sharing posture has no whole-tenant signal "
            "(fsi_sharedwitheveryone unset) and no viewer/editor refs; the audience "
            "cannot be confirmed empty and is marked Partial. Populate "
            "fsi_sharedwitheveryone during discovery to resolve.",
            agent_id or "<unknown>",
        )
    status = _derive_status(whole_tenant, had_refs, len(upn_list), any_truncated,
                            errors, tenant_signal_known)

    return {
        "agentId": agent_id,
        "agentName": agent_name,
        "environmentId": environment_id,
        "wholeTenant": whole_tenant,
        "wholeTenantCap": config.whole_tenant_cap,
        "audienceSize": 0 if whole_tenant else len(upn_list),
        "truncated": any_truncated,
        "resolutionStatus": status,
        "resolutionErrors": errors,
        "sourceGroups": source_groups,
        # CBG -InputPath shape: intendedUsers[].upn (per-user license/cohort flags
        # are downstream gaps per R5 and are intentionally not populated here).
        "intendedUsers": [{"upn": upn} for upn in upn_list],
    }


def build_authshare_update(result: dict, run_id: str) -> dict:
    """Project an expansion result onto fsi_caiauthshare audience columns (no PII)."""
    return {
        "fsi_agentid": result["agentId"],
        "fsi_environmentid": result.get("environmentId"),
        "fsi_audiencewholetenant": result["wholeTenant"],
        "fsi_audienceupncount": result["audienceSize"],
        "fsi_audiencetruncated": result["truncated"],
        "fsi_audienceresolutionstatus": result["resolutionStatus"],
        "fsi_audienceresolvedat": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "fsi_runid": run_id,
    }


def expand_all(agents: list[dict], resolver: MemberResolver, config: ExpandConfig,
               run_id: str) -> dict:
    """Expand every agent's audience and assemble the artifact + summary."""
    expanded: list[dict] = []
    authshare_updates: list[dict] = []
    whole_tenant_count = 0
    error_agent_count = 0
    for agent in agents:
        result = expand_agent_audience(agent, resolver, config)
        expanded.append(result)
        authshare_updates.append(build_authshare_update(result, run_id))
        if result["wholeTenant"]:
            whole_tenant_count += 1
        if result["resolutionErrors"]:
            error_agent_count += 1
    summary = {
        "runId": run_id,
        "agentCount": len(agents),
        "wholeTenantAgentCount": whole_tenant_count,
        "agentsWithResolutionErrors": error_agent_count,
        "maxMembersPerGroup": config.max_members_per_group,
        "wholeTenantCap": config.whole_tenant_cap,
    }
    return {
        "schemaVersion": "0.2.0-preview",
        "summary": summary,
        "agents": expanded,
        "authShareUpdates": authshare_updates,
    }


# =============================================================================
# Microsoft Graph resolver (managed-identity-first)
# =============================================================================


class GraphMemberResolver:
    """Resolve group transitive members and user UPNs via Microsoft Graph.

    Requires the ``GroupMember.Read.All`` permission (plus ``User.Read.All`` to
    resolve a bare user object id). Authentication is managed-identity-first via
    azure-identity, lazily imported so ``--dry-run`` and unit tests need no
    credential or network.
    """

    def __init__(self, config: ExpandConfig, tenant_id: Optional[str] = None,
                 client_id: Optional[str] = None, auth_mode: str = "managed-identity") -> None:
        import requests  # local import: only needed for live runs
        from requests.adapters import HTTPAdapter, Retry

        self.config = config
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.auth_mode = auth_mode
        # Hold the credential (not just a bearer string) for the resolver lifetime
        # so the token can be refreshed per request; _access_token caches the most
        # recent azure-identity AccessToken (token + expires_on epoch seconds).
        self._credential_obj: Any = None
        self._access_token: Any = None
        session = requests.Session()
        retry = Retry(total=5, backoff_factor=2,
                      status_forcelist=[429, 500, 502, 503, 504],
                      allowed_methods=["GET"], respect_retry_after_header=True)
        session.mount("https://", HTTPAdapter(max_retries=retry))
        self._session = session

    def _credential(self) -> Any:
        if self._credential_obj is None:
            import azure.identity as azid  # type: ignore
            if self.auth_mode == "managed-identity":
                self._credential_obj = (
                    azid.ManagedIdentityCredential(client_id=self.client_id)
                    if self.client_id else azid.ManagedIdentityCredential()
                )
            elif self.auth_mode == "workload-identity":
                self._credential_obj = azid.WorkloadIdentityCredential(
                    tenant_id=self.tenant_id, client_id=self.client_id)
            elif self.auth_mode == "interactive":
                self._credential_obj = azid.InteractiveBrowserCredential(
                    tenant_id=self.tenant_id, client_id=self.client_id)
            else:
                self._credential_obj = azid.DefaultAzureCredential()
        return self._credential_obj

    def _bearer_token(self) -> str:
        """Return a valid Graph bearer token, refreshing it as it nears expiry.

        A long run can outlive the ~60-minute token lifetime; re-acquiring within
        TOKEN_REFRESH_SKEW_SECONDS of expiry avoids the 401s that a lifetime-cached
        token caused on late agents.
        """
        token = self._access_token
        if token is None or (token.expires_on - time.time()) < TOKEN_REFRESH_SKEW_SECONDS:
            self._access_token = self._credential().get_token(GRAPH_SCOPE)
        return self._access_token.token

    def _headers(self) -> dict:
        return {"Authorization": f"Bearer {self._bearer_token()}", "Accept": "application/json"}

    def _get_with_backoff(self, url: str) -> Any:
        """GET with explicit 429-aware backoff that honors Retry-After.

        Mirrors discover_agents._request_with_backoff: the session adapter
        already retries transient failures, and this outer guard adds the
        Retry-After-honoring loop for the longer throttling windows Graph can
        return at scale. Unlike the discovery scanner (which raises so a paging
        loop never mistakes a persistent 429 for end-of-data), this returns the
        final 429 response so the caller records it as a per-group resolution
        error: in a multi-agent batch one throttled group should be flagged
        Partial/Failed, never silently treated as an empty/complete group.
        """
        delay = 1.0
        for attempt in range(6):
            resp = self._session.get(url, headers=self._headers(), timeout=120)
            if resp.status_code != 429:
                return resp
            wait = _parse_retry_after(resp.headers.get("Retry-After"),
                                      min(delay, MAX_BACKOFF_SECONDS))
            logger.warning("429 throttled on %s; backing off %.1fs (attempt %d)",
                           url, wait, attempt + 1)
            time.sleep(wait)
            delay = min(delay * 2, MAX_BACKOFF_SECONDS)
        return resp  # last (still-429) response; caller records it as an error

    def transitive_member_upns(self, group_id: str) -> ResolveResult:
        cap = self.config.max_members_per_group
        url = (f"{GRAPH_BASE}/groups/{group_id}/transitiveMembers"
               f"?$select=id,userPrincipalName&$top={GRAPH_PAGE_SIZE}")
        upns: list[str] = []
        while url:
            resp = self._get_with_backoff(url)
            if resp.status_code == 404:
                return ResolveResult(upns=upns, error="group not found (404)")
            if resp.status_code != 200:
                return ResolveResult(upns=upns, error=f"HTTP {resp.status_code}")
            payload = resp.json()
            for obj in payload.get("value", []):
                upn = obj.get("userPrincipalName")
                if upn:
                    upns.append(upn)
                    if len(upns) >= cap:
                        return ResolveResult(upns=upns, truncated=True)
            url = payload.get("@odata.nextLink")
        return ResolveResult(upns=upns)

    def user_upn(self, user_id: str) -> Optional[str]:
        resp = self._get_with_backoff(
            f"{GRAPH_BASE}/users/{user_id}?$select=userPrincipalName")
        if resp.status_code == 200:
            return resp.json().get("userPrincipalName")
        logger.warning("Could not resolve user %s (HTTP %s)", user_id, resp.status_code)
        return None


class DryRunResolver:
    """No-network resolver used by --dry-run: resolves nothing, flags it."""

    def transitive_member_upns(self, group_id: str) -> ResolveResult:
        return ResolveResult(error="dry-run: not resolved")

    def user_upn(self, user_id: str) -> Optional[str]:
        return None


# =============================================================================
# Input loading
# =============================================================================


def load_agents_from_input(path: str) -> list[dict]:
    """Load the per-agent sharing posture from a JSON file.

    Accepts either a top-level ``{"agents": [...]}`` object or a bare ``[...]``
    list. Each element mirrors fsi_caiauthshare: ``viewerGroups`` /
    ``editorPrincipals`` (+ optional ``sharedWithEveryone``).
    """
    data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    if isinstance(data, dict):
        agents = data.get("agents", [])
    elif isinstance(data, list):
        agents = data
    else:
        raise SystemExit("--input must be a JSON object with 'agents' or a JSON array")
    if not isinstance(agents, list):
        raise SystemExit("'agents' must be a JSON array")
    return agents


def load_agents_from_dataverse(environment_url: str, tenant_id: str,
                               auth_mode: str) -> list[dict]:
    """Read fsi_caiauthshare rows from Dataverse and map to the input shape.

    Uses the shared DataverseClient. fsi_viewergroups / fsi_editorprincipals are
    stored as JSON memo columns; they are parsed back into lists here. Whole-tenant
    reach is read from the per-agent fsi_sharedwitheveryone boolean (NOT inferred
    from the environment-wide fsi_limitsharingmode policy).
    """
    import sys
    shared_dir = Path(__file__).resolve().parent.parent.parent / "scripts" / "shared"
    if str(shared_dir) not in sys.path:
        sys.path.insert(0, str(shared_dir))
    from dataverse_client import DataverseClient  # noqa: E402

    client = DataverseClient(
        tenant_id=tenant_id, environment_url=environment_url,
        interactive=(auth_mode == "interactive"), auth_mode=auth_mode,
    )
    rows = client.query(
        "fsi_caiauthshares",
        select=["fsi_agentid", "fsi_environmentid", "fsi_viewergroups",
                "fsi_editorprincipals", "fsi_sharedwitheveryone"],
    ) or []

    def _parse(value: Any) -> list:
        if not value:
            return []
        try:
            parsed = json.loads(value) if isinstance(value, str) else value
        except json.JSONDecodeError:
            return []
        return parsed if isinstance(parsed, list) else []

    agents: list[dict] = []
    for row in rows:
        agent: dict = {
            "fsi_agentid": row.get("fsi_agentid"),
            "fsi_environmentid": row.get("fsi_environmentid"),
            "viewerGroups": _parse(row.get("fsi_viewergroups")),
            "editorPrincipals": _parse(row.get("fsi_editorprincipals")),
        }
        # Whole-tenant reach is a PER-AGENT signal read from fsi_sharedwitheveryone
        # (populated during discovery from the bot accesscontrolpolicy). It is NOT
        # inferred from the environment-wide fsi_limitsharingmode policy. When the
        # column is unset, leave the signal unknown so a refless row is marked
        # Partial rather than emitted as a confident empty audience.
        shared_everyone = row.get("fsi_sharedwitheveryone")
        if isinstance(shared_everyone, bool):
            agent["sharedWithEveryone"] = shared_everyone
        else:
            agent["wholeTenantSignalKnown"] = False
        agents.append(agent)
    return agents


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    """CLI entry point for audience-to-UPN expansion."""
    parser = argparse.ArgumentParser(
        description="Expand agent sharing audiences to member UPNs (CBG input)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run from a captured auth-share JSON (no network)\n"
            "  python expand_audience_upns.py --input authshare.json --dry-run\n\n"
            "  # Live expansion via Microsoft Graph (managed identity)\n"
            "  python expand_audience_upns.py --input authshare.json "
            "--auth-mode managed-identity --output intended-users.json\n"
        ),
    )
    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument("--input", help="JSON file of per-agent sharing posture (fsi_caiauthshare shape)")
    src.add_argument("--from-dataverse", action="store_true",
                     help="Read fsi_caiauthshare rows from Dataverse (needs --environment-url/--tenant-id)")
    parser.add_argument("--environment-url", default=os.environ.get("CAI_ENVIRONMENT_URL"),
                        help="Governance Dataverse URL (with --from-dataverse / --write-back)")
    parser.add_argument("--tenant-id", default=os.environ.get("CAI_TENANT_ID"),
                        help="Microsoft Entra ID tenant ID")
    parser.add_argument("--client-id", default=os.environ.get("CAI_CLIENT_ID"),
                        help="Service principal / managed identity client ID")
    parser.add_argument("--auth-mode",
                        choices=["managed-identity", "workload-identity", "interactive", "default"],
                        default=os.environ.get("CAI_AUTH_MODE", "managed-identity"),
                        help="Graph/Dataverse auth mode; prefer managed-identity for automation")
    parser.add_argument("--max-members-per-group", type=int, default=DEFAULT_MAX_MEMBERS_PER_GROUP,
                        help="Per-group member cap (bounds very large groups; sets the truncated flag)")
    parser.add_argument("--whole-tenant-cap", type=int, default=DEFAULT_WHOLE_TENANT_CAP,
                        help="Recorded cap for 'Everyone in org' shares; the tenant is never enumerated")
    parser.add_argument("--whole-tenant-sentinels", default=None,
                        help="Comma-separated display-name sentinels treated as whole-tenant")
    parser.add_argument("--run-id", default=None, help="Scan run correlation id (default: generated)")
    parser.add_argument("--output", default=None, help="Write the CBG-input artifact JSON to this path")
    parser.add_argument("--write-back", action="store_true",
                        help="Update fsi_caiauthshare audience summary columns (needs Dataverse conn)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Resolve nothing over the network; log planned work")
    parser.add_argument("--log-level", default="INFO", help="Logging level")
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, str(args.log_level).upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    sentinels = (tuple(s.strip().lower() for s in args.whole_tenant_sentinels.split(",") if s.strip())
                 if args.whole_tenant_sentinels else DEFAULT_WHOLE_TENANT_SENTINELS)
    config = ExpandConfig(
        max_members_per_group=max(1, args.max_members_per_group),
        whole_tenant_cap=max(0, args.whole_tenant_cap),
        sentinels=sentinels,
    )
    run_id = args.run_id or f"cai-audience-{int(datetime.now(timezone.utc).timestamp())}"

    # Load the per-agent sharing posture.
    if args.from_dataverse:
        if not (args.environment_url and args.tenant_id):
            parser.error("--from-dataverse requires --environment-url and --tenant-id")
        agents = load_agents_from_dataverse(args.environment_url, args.tenant_id, args.auth_mode)
    else:
        agents = load_agents_from_input(args.input)
    logger.info("Loaded %d agent sharing postures", len(agents))

    # Choose the resolver.
    if args.dry_run:
        logger.info("[DRY RUN] resolving nothing over Graph; whole-tenant shares are flagged only.")
        resolver: MemberResolver = DryRunResolver()
    else:
        resolver = GraphMemberResolver(config, tenant_id=args.tenant_id,
                                       client_id=args.client_id, auth_mode=args.auth_mode)

    artifact = expand_all(agents, resolver, config, run_id)
    logger.info("Audience expansion summary: %s", json.dumps(artifact["summary"]))

    if args.write_back and not args.dry_run:
        _write_back_authshare(artifact["authShareUpdates"], args)

    if args.output:
        Path(args.output).write_text(json.dumps(artifact, indent=2), encoding="utf-8")
        logger.info("Wrote CBG-input artifact to %s", args.output)
    else:
        print(json.dumps(artifact, indent=2))


def _write_back_authshare(updates: list[dict], args: argparse.Namespace) -> None:
    """Update fsi_caiauthshare audience-summary columns (counts/flags only; no PII)."""
    if not (args.environment_url and args.tenant_id):
        logger.error("--write-back requires --environment-url and --tenant-id; skipping write-back")
        return
    import sys
    shared_dir = Path(__file__).resolve().parent.parent.parent / "scripts" / "shared"
    if str(shared_dir) not in sys.path:
        sys.path.insert(0, str(shared_dir))
    from dataverse_client import DataverseClient  # noqa: E402

    client = DataverseClient(
        tenant_id=args.tenant_id, environment_url=args.environment_url,
        interactive=(args.auth_mode == "interactive"), auth_mode=args.auth_mode,
    )
    for update in updates:
        existing = client.query(
            "fsi_caiauthshares",
            select=["fsi_caiauthshareid"],
            filter_expr=f"fsi_agentid eq '{_odata_escape(update['fsi_agentid'])}'",
            top=1,
        ) or []
        payload = {k: v for k, v in update.items() if k != "fsi_agentid"}
        if existing:
            client.update_record("fsi_caiauthshares", existing[0]["fsi_caiauthshareid"], payload)
        else:
            logger.warning("No fsi_caiauthshare row for agent %s; skipping write-back",
                           update["fsi_agentid"])


if __name__ == "__main__":
    main()
