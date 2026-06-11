#!/usr/bin/env python3
"""Three-layer Copilot agent discovery scanner (skeleton).

Discovers Copilot Studio and Agent Builder agents across a tenant and projects
them onto the Copilot Agent Inventory canonical store (fsi_copilotagent +
fsi_caiagentfeature ...). Three discovery layers:

  Layer 1 — Tenant-wide Azure Resource Graph (PRIMARY, gated by a runtime
            capability probe): POST {PowerPlatformAPI}/resourcequery/resources/
            query?api-version=2024-10-01 against the dedicated
            `PowerPlatformResources` table (NOT the standard ARM `resources`
            table), resource type `microsoft.copilotstudio/agents`, SkipToken
            paging. Absent from the standard ARG supported-types reference, so
            the type is probed at runtime, never assumed.
  Layer 2 — Per-environment Dataverse: `GET /bots` (widened $select) +
            `GET /botcomponents` filtered on `_parentbotid_value` with the six
            many-to-many $expands, parsed by a unified componenttype map.
  Layer 3 — PPAC reconciliation (drift / deleted-but-lingering) — see
            reconcile_sources().

Build-time truth baked in (verify in the customer tenant before hardcoding):
  * ARG lives in `PowerPlatformResources`; live-confirm the resource type
    resolves at tenant scope (digest checklist #2).
  * botcomponent->bot lookup is `_parentbotid_value` (NOT `_botid_value`).
  * componenttype max is 19 today; re-pull the live enum via
    GlobalOptionSetDefinitions(Name='botcomponent_componenttype') at build to
    catch any code >= 20 (digest checklist #6).
  * Lite / Agent-Builder agents are modeled as `incomplete-scan`: no public API
    returns their full definition.
  * Scale (~2,000 agents): Dataverse $batch reads, @odata.deltaLink change
    tracking, throttled (~10) concurrent per-environment fan-out, 429 backoff.

Auth: managed-identity-first. The least-privilege scanner service principal
should read `bot` / `botcomponent` only; its secret (dev fallback only) belongs
in Key Vault, retrieved via managed identity. Granting the scanner system
administrator on every environment ("sys-admin-everywhere") is a privileged-
identity risk and is NOT required for read-only discovery.

This is an intentionally runnable SKELETON: `--dry-run` logs the planned API
calls and emitted records without contacting any service. Network execution
paths build the verified request shapes and fail open (log telemetry, continue)
on unrecognized payloads so platform drift surfaces as an anomaly rather than a
silently zeroed count.
"""

import argparse
import json
import logging
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Optional

import requests
from requests.adapters import HTTPAdapter, Retry

logger = logging.getLogger("discover_agents")

# =============================================================================
# Verified API shapes and platform constants
# =============================================================================

# Power Platform API base (commercial cloud). Override with --power-platform-api.
DEFAULT_POWER_PLATFORM_API = "https://api.powerplatform.com"
BAP_API = "https://api.bap.microsoft.com"

ARG_TABLE = "PowerPlatformResources"            # NOT the standard ARM 'resources'
ARG_RESOURCE_TYPE = "microsoft.copilotstudio/agents"
ARG_API_VERSION = "2024-10-01"
ARG_QUERY_PATH = "/resourcequery/resources/query"
BAP_ENV_API_VERSION = "2020-10-01"

DATAVERSE_API_VERSION = "v9.2"
DEFAULT_MAX_WORKERS = 10                         # throttled per-environment fan-out
DEFAULT_PAGE_SIZE = 200
MAX_BACKOFF_SECONDS = 60

# Authoring-surface values from ARG `createdIn` (zero-rating disambiguator).
CREATED_IN_AGENT_BUILDER = "Microsoft 365 Copilot Agent Builder"
CREATED_IN_COPILOT_STUDIO = "Copilot Studio"

# Discovery-source labels (also the fsi_cai_discoverysource option-set labels).
# Both layers key fsi_agentid on the SAME bot-GUID id space; the source label
# selects which raw field holds that GUID (see _canonical_agent_id, H-3).
DISCOVERY_SOURCE_ARG = "Azure Resource Graph"
DISCOVERY_SOURCE_DATAVERSE = "Per-Environment Dataverse Scan"

# botcomponent_componenttype -> (feature label, component version).
# Verified against the 2025-10-31 platform docs (max code = 19). Includes the
# V1 codes 2-7 that the original brief omitted. Re-pull live at build time.
COMPONENTTYPE_MAP: dict[int, tuple[str, str]] = {
    0: ("Topic", "V1"),
    1: ("Skill", "V1"),
    2: ("Bot Variable", "V1"),
    3: ("Bot Entity", "V1"),
    4: ("Dialog", "V1"),
    5: ("Trigger", "V1"),
    6: ("Language Understanding", "V1"),
    7: ("Language Generation", "V1"),
    8: ("Dialog Schema", "V1"),        # code 8 = Dialog schema (distinct from code 4 = Dialog)
    9: ("Topic", "V2"),
    10: ("Bot Translations", "V2"),
    11: ("Bot Entity", "V2"),
    12: ("Bot Variable", "V2"),
    13: ("Skill", "V2"),
    14: ("File Attachment", "Not Applicable"),
    15: ("Custom GPT", "Not Applicable"),
    16: ("Knowledge Source", "Not Applicable"),
    17: ("External Trigger", "Not Applicable"),
    18: ("Copilot Settings", "Not Applicable"),
    19: ("Test Case", "Not Applicable"),
}

# The six botcomponent many-to-many relationships -> (feature label, target PK).
# A M:M $expand returns the TARGET entities (aipluginoperation, connectionreference,
# workflow, environmentvariabledefinition, dvtablesearch, msdyn_aimodel), which have
# NO botcomponentid column — each target must $select its OWN primary key. These
# surface the capability-composition layer.
MM_RELATIONSHIPS: dict[str, tuple[str, str]] = {
    "botcomponent_aipluginoperation": ("Tool / Plugin", "aipluginoperationid"),
    "botcomponent_connectionreference": ("Connector", "connectionreferenceid"),
    "botcomponent_workflow": ("Power Automate Flow", "workflowid"),
    "botcomponent_environmentvariabledefinition": (
        "Environment Variable", "environmentvariabledefinitionid"),
    "botcomponent_dvtablesearch": ("Dataverse Search Grounding", "dvtablesearchid"),
    "botcomponent_msdyn_aimodel": ("AI Builder Model", "msdyn_aimodelid"),
}

# Widened $select on the bot table (the legacy registry scan omitted authMode,
# createdon, modifiedon — all needed for the canonical Agent record).
BOT_SELECT = (
    "botid,name,schemaname,statecode,statuscode,authenticationmode,"
    "createdon,modifiedon,_ownerid_value"
)


# =============================================================================
# Scan context + HTTP plumbing
# =============================================================================


@dataclass
class ScanContext:
    """Holds resolved configuration for one scan run."""

    run_id: str
    dry_run: bool = True
    use_arg: bool = True
    max_workers: int = DEFAULT_MAX_WORKERS
    page_size: int = DEFAULT_PAGE_SIZE
    power_platform_api: str = DEFAULT_POWER_PLATFORM_API
    tenant_id: Optional[str] = None
    client_id: Optional[str] = None
    auth_mode: str = "managed-identity"
    _credential: Any = field(default=None, repr=False)


def _build_session() -> requests.Session:
    """Build a requests session with 429/5xx retry + backoff (scale safety)."""
    session = requests.Session()
    retry = Retry(
        total=5,
        backoff_factor=2,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET", "POST"],
        respect_retry_after_header=True,
    )
    adapter = HTTPAdapter(max_retries=retry, pool_maxsize=DEFAULT_MAX_WORKERS * 2)
    session.mount("https://", adapter)
    return session


def _get_credential(ctx: ScanContext) -> Any:
    """Return an azure-identity credential (managed-identity-first).

    Lazily imports azure-identity so the module compiles and the --dry-run path
    runs without the optional dependency installed.
    """
    if ctx._credential is not None:
        return ctx._credential
    try:
        import azure.identity as azid  # type: ignore
    except ImportError as exc:  # pragma: no cover - optional runtime dependency
        raise RuntimeError(
            "azure-identity is required for live scans. "
            "Install scripts/requirements.txt, or use --dry-run."
        ) from exc

    mode = ctx.auth_mode
    if mode == "managed-identity":
        cred = (
            azid.ManagedIdentityCredential(client_id=ctx.client_id)
            if ctx.client_id else azid.ManagedIdentityCredential()
        )
    elif mode == "workload-identity":
        cred = azid.WorkloadIdentityCredential(
            tenant_id=ctx.tenant_id, client_id=ctx.client_id
        )
    elif mode == "interactive":
        cred = azid.InteractiveBrowserCredential(
            tenant_id=ctx.tenant_id, client_id=ctx.client_id
        )
    elif mode == "client-secret":
        # legacy: dev-only — replace with managed identity in production
        secret = os.environ.get("CAI_CLIENT_SECRET")
        if not (ctx.tenant_id and ctx.client_id and secret):
            raise ValueError(
                "client-secret auth requires --tenant-id, --client-id and "
                "CAI_CLIENT_SECRET (dev-only fallback)."
            )
        cred = azid.ClientSecretCredential(
            tenant_id=ctx.tenant_id, client_id=ctx.client_id, client_secret=secret
        )
    else:  # default to the strongest available
        cred = azid.DefaultAzureCredential()
    ctx._credential = cred
    return cred


def _get_token(ctx: ScanContext, scope: str) -> str:
    """Acquire a bearer token for the given scope via the credential."""
    credential = _get_credential(ctx)
    return credential.get_token(scope).token


class ThrottlingExhaustedError(RuntimeError):
    """Raised when 429 backoff is exhausted on a persistent throttle.

    Distinct outcome (L-3): a throttled scan must NOT be mistaken for
    end-of-data. Paging loops should treat this as an INCOMPLETE scan, not a
    clean stop. `_scan_one_environment` catches it per-environment (fail-open);
    the ARG layer catches it and falls back to the Layer 2 per-environment scan.
    """


def _request_with_backoff(
    session: requests.Session, method: str, url: str, **kwargs: Any
) -> requests.Response:
    """Issue a request with explicit 429-aware exponential backoff.

    The session adapter already retries; this adds an outer guard that honors
    Retry-After for the long throttling windows Dataverse can return at scale.
    Raises ThrottlingExhaustedError (L-3) when every attempt is throttled, so a
    persistent 429 surfaces as an INCOMPLETE scan rather than being returned as
    a normal response that paging loops mistake for end-of-data.
    """
    delay = 1.0
    for attempt in range(6):
        response = session.request(method, url, timeout=120, **kwargs)
        if response.status_code != 429:
            return response
        retry_after = response.headers.get("Retry-After")
        wait = float(retry_after) if retry_after else min(delay, MAX_BACKOFF_SECONDS)
        logger.warning("429 throttled on %s; backing off %.1fs (attempt %d)",
                       url, wait, attempt + 1)
        time.sleep(wait)
        delay = min(delay * 2, MAX_BACKOFF_SECONDS)
    # Every attempt was throttled: surface a distinct outcome so callers do not
    # treat a persistent 429 as a successful end-of-data response (L-3).
    raise ThrottlingExhaustedError(
        f"429 throttling persisted after {attempt + 1} attempts on {url}"
    )


# =============================================================================
# Layer 1 — Azure Resource Graph (PRIMARY, capability-probed)
# =============================================================================


def probe_arg_resource_type(ctx: ScanContext, session: requests.Session) -> bool:
    """Probe whether the ARG resource type resolves at tenant scope.

    Returns True only when `PowerPlatformResources` + the
    `microsoft.copilotstudio/agents` type returns a well-formed response. The
    type is absent from the standard ARG supported-types reference, so this
    runtime probe gates the primary path; on failure the caller falls back to
    Layer 2 environment enumeration (the proven default).
    """
    if ctx.dry_run:
        logger.info("[DRY RUN] would probe ARG type '%s' in table '%s'",
                    ARG_RESOURCE_TYPE, ARG_TABLE)
        return False
    url = f"{ctx.power_platform_api}{ARG_QUERY_PATH}?api-version={ARG_API_VERSION}"
    body = {
        "TableName": ARG_TABLE,
        "Clauses": [
            {"Field": "type", "Operator": "eq", "Value": ARG_RESOURCE_TYPE}
        ],
        "Options": {"Top": 1},
    }
    try:
        token = _get_token(ctx, f"{ctx.power_platform_api}/.default")
        resp = _request_with_backoff(
            session, "POST", url,
            headers={"Authorization": f"Bearer {token}",
                     "Content-Type": "application/json"},
            json=body,
        )
        ok = resp.status_code == 200
        logger.info("ARG capability probe: %s (HTTP %s)",
                    "available" if ok else "unavailable", resp.status_code)
        return ok
    except Exception as exc:  # fail open to Layer 2
        logger.warning("ARG probe failed, falling back to per-env scan: %s", exc)
        return False


def query_arg_inventory(
    ctx: ScanContext, session: requests.Session
) -> Iterable[dict]:
    """Yield raw ARG agent resources via SkipToken paging.

    Response envelope exposes `skipToken` / `totalRecords` / `resultTruncated`;
    there is no ~500 ceiling on the ARG/API path (that limit is PPAC UI-only).
    """
    if ctx.dry_run:
        logger.info("[DRY RUN] would POST %s%s?api-version=%s (SkipToken paged)",
                    ctx.power_platform_api, ARG_QUERY_PATH, ARG_API_VERSION)
        return []
    url = f"{ctx.power_platform_api}{ARG_QUERY_PATH}?api-version={ARG_API_VERSION}"
    token = _get_token(ctx, f"{ctx.power_platform_api}/.default")
    headers = {"Authorization": f"Bearer {token}",
               "Content-Type": "application/json"}
    results: list[dict] = []
    skip_token: Optional[str] = None
    while True:
        options: dict[str, Any] = {"Top": ctx.page_size}
        if skip_token:
            options["SkipToken"] = skip_token
        body = {
            "TableName": ARG_TABLE,
            "Clauses": [
                {"Field": "type", "Operator": "eq", "Value": ARG_RESOURCE_TYPE}
            ],
            "Options": options,
        }
        resp = _request_with_backoff(session, "POST", url, headers=headers, json=body)
        if resp.status_code != 200:
            logger.warning("ARG query HTTP %s; stopping paging", resp.status_code)
            break
        payload = resp.json()
        results.extend(payload.get("value", payload.get("Data", [])))
        skip_token = payload.get("skipToken") or payload.get("SkipToken")
        if not skip_token:
            break
    logger.info("ARG inventory returned %d agent resources", len(results))
    return results


# =============================================================================
# Layer 2 — Per-environment enumeration + Dataverse scan
# =============================================================================


def enumerate_environments(ctx: ScanContext, session: requests.Session) -> list[dict]:
    """Enumerate environments via the BAP admin REST API (proven path).

    GET /providers/Microsoft.BusinessAppPlatform/scopes/admin/environments
    """
    if ctx.dry_run:
        logger.info("[DRY RUN] would GET %s/providers/Microsoft.BusinessAppPlatform"
                    "/scopes/admin/environments?api-version=%s",
                    BAP_API, BAP_ENV_API_VERSION)
        return []
    url = (f"{BAP_API}/providers/Microsoft.BusinessAppPlatform/scopes/admin/"
           f"environments?api-version={BAP_ENV_API_VERSION}")
    token = _get_token(ctx, f"{BAP_API}/.default")
    headers = {"Authorization": f"Bearer {token}"}
    environments: list[dict] = []
    while url:
        resp = _request_with_backoff(session, "GET", url, headers=headers)
        if resp.status_code != 200:
            logger.warning("Environment enumeration HTTP %s; stopping",
                           resp.status_code)
            break
        payload = resp.json()
        environments.extend(payload.get("value", []))
        url = payload.get("nextLink") or payload.get("@odata.nextLink")
        headers = {"Authorization": f"Bearer {token}"}
    logger.info("Enumerated %d environments", len(environments))
    return environments


def _dataverse_url(environment_url: str, path: str) -> str:
    base = environment_url.rstrip("/")
    return f"{base}/api/data/{DATAVERSE_API_VERSION}/{path}"


def scan_environment_bots(
    ctx: ScanContext,
    session: requests.Session,
    environment_url: str,
    delta_link: Optional[str] = None,
) -> tuple[list[dict], Optional[str]]:
    """Read `bot` rows for one environment with change tracking.

    Sends `Prefer: odata.track-changes` so Dataverse returns an
    `@odata.deltaLink`. Passing a stored delta link would read only the changes
    since the last scan, but persistence of the link is not yet implemented
    (delta-ready; persistence TODO) — callers capture the returned link rather
    than discarding it. Returns (bots, new_delta_link).
    """
    if ctx.dry_run:
        logger.info("[DRY RUN] would GET %s bots?$select=%s (Prefer: "
                    "odata.track-changes%s)", environment_url, BOT_SELECT,
                    ", using stored deltaLink" if delta_link else "")
        return [], delta_link
    scope = f"{environment_url.rstrip('/')}/.default"
    headers = {
        "Authorization": f"Bearer {_get_token(ctx, scope)}",
        "Prefer": "odata.track-changes,odata.maxpagesize=" + str(ctx.page_size),
        "OData-MaxVersion": "4.0",
        "OData-Version": "4.0",
        "Accept": "application/json",
    }
    url = delta_link or _dataverse_url(environment_url, f"bots?$select={BOT_SELECT}")
    bots: list[dict] = []
    new_delta: Optional[str] = delta_link
    while url:
        resp = _request_with_backoff(session, "GET", url, headers=headers)
        if resp.status_code != 200:
            logger.warning("bot scan HTTP %s for %s", resp.status_code, environment_url)
            break
        payload = resp.json()
        bots.extend(payload.get("value", []))
        new_delta = payload.get("@odata.deltaLink") or new_delta
        url = payload.get("@odata.nextLink")
    return bots, new_delta


def scan_bot_features(
    ctx: ScanContext,
    session: requests.Session,
    environment_url: str,
    bot_id: str,
) -> list[dict]:
    """Scan botcomponents for one agent and build AgentFeature rows.

    Filters on `_parentbotid_value` (the correct bot lookup — NOT
    `_botid_value`) and $expands all six many-to-many relationships. Each
    componenttype row and each M:M target becomes one fsi_caiagentfeature row.
    """
    expand = ",".join(
        f"{rel}($select={target_pk})"
        for rel, (_label, target_pk) in MM_RELATIONSHIPS.items()
    )
    query = (
        "botcomponents?"
        f"$filter=_parentbotid_value eq {bot_id}"
        "&$select=botcomponentid,name,componenttype"
        f"&$expand={expand}"
    )
    if ctx.dry_run:
        logger.info("[DRY RUN] would GET %s %s", environment_url, query)
        return []
    scope = f"{environment_url.rstrip('/')}/.default"
    headers = {
        "Authorization": f"Bearer {_get_token(ctx, scope)}",
        "Accept": "application/json",
    }
    url = _dataverse_url(environment_url, query)
    features: list[dict] = []
    while url:
        resp = _request_with_backoff(session, "GET", url, headers=headers)
        if resp.status_code != 200:
            logger.warning("botcomponent scan HTTP %s for bot %s",
                           resp.status_code, bot_id)
            break
        payload = resp.json()
        for component in payload.get("value", []):
            features.extend(_components_to_features(ctx, bot_id, component))
        url = payload.get("@odata.nextLink")
    return features


def classify_component(componenttype: Any) -> tuple[str, str]:
    """Map a raw componenttype code to (feature label, version), fail-open."""
    try:
        code = int(componenttype)
    except (TypeError, ValueError):
        logger.warning("Unparseable componenttype %r (fail-open)", componenttype)
        return ("Other / Unrecognized", "Not Applicable")
    mapped = COMPONENTTYPE_MAP.get(code)
    if mapped is None:
        # Telemetry, not a silent zero: a code >= 20 means the enum drifted.
        logger.warning("Unrecognized componenttype %d — re-pull "
                       "botcomponent_componenttype enum (fail-open)", code)
        return ("Other / Unrecognized", "Not Applicable")
    return mapped


def _components_to_features(
    ctx: ScanContext, bot_id: str, component: dict
) -> list[dict]:
    """Translate one botcomponent (+ its M:M expands) into feature records."""
    features: list[dict] = []
    label, version = classify_component(component.get("componenttype"))
    source_id = component.get("botcomponentid", "")
    features.append(_feature_record(
        ctx, bot_id, label, version, source_id,
        component.get("name"), component.get("componenttype"),
        relationship="botcomponent",
    ))
    for rel, (rel_label, target_pk) in MM_RELATIONSHIPS.items():
        for target in component.get(rel, []) or []:
            features.append(_feature_record(
                ctx, bot_id, rel_label, "Not Applicable",
                target.get(target_pk, source_id),
                None, None, relationship=rel,
            ))
    return features


def _feature_record(
    ctx: ScanContext,
    bot_id: str,
    feature_type: str,
    version: str,
    source_object_id: str,
    source_object_name: Optional[str],
    component_type: Any,
    relationship: str,
) -> dict:
    """Build one fsi_caiagentfeature row (logical column names).

    Botcomponent-derived rows are stamped with the Dataverse provenance and a
    "Configured (Dataverse)" confidence marker. Manifest-derived rows (e.g., the
    People capability detected by detect_people_capability.py) carry their own
    "Declared (Manifest)" marker — declared is NOT the same as effective.
    """
    return {
        "fsi_agentid": bot_id,
        "fsi_featuretype": feature_type,
        "fsi_componentversion": version,
        "fsi_componenttype": component_type,
        "fsi_sourceobjectid": source_object_id,
        "fsi_sourceobjectname": source_object_name,
        "fsi_relationshipname": relationship,
        "fsi_detectionsource": "Dataverse Botcomponent Scan",
        "fsi_detectionconfidence": "Configured (Dataverse)",
        "fsi_isenabled": True,
        "fsi_runid": ctx.run_id,
    }


# =============================================================================
# Mapping + classification
# =============================================================================


def classify_scan_completeness(agent: dict) -> tuple[str, str]:
    """Return (scan_completeness, reason).

    Lite / Agent-Builder agents are `Incomplete Scan`: no public API returns
    their full definition (instructions + knowledge + capabilities). The Graph
    Package Management API is beta, Agent-365-licensed, and delegated-only,
    which blocks unattended service-principal automation.
    """
    created_in = (agent.get("createdIn") or agent.get("fsi_createdin") or "")
    if created_in == CREATED_IN_AGENT_BUILDER:
        return (
            "Incomplete Scan",
            "Agent Builder agent: no public API returns the full definition "
            "(Graph Package Management API is beta / Agent-365 / delegated-only).",
        )
    return ("Complete", "")


def _canonical_agent_id(arg_item: dict, source: str) -> str:
    """Derive the ONE canonical agent id = the Copilot Studio bot GUID.

    Both discovery layers MUST key fsi_agentid on the SAME id space or
    reconcile_sources() intersects disjoint sets and drift detection dies
    (H-3). That shared space is the bot GUID:

      * ARG layer: the ARG resource `name` IS the CDS bot GUID (confirmed by the
        fsi_AgentId description in create_cai_dataverse_schema.py: "ARG 'name' /
        Dataverse botid"). Fall back only to an explicit bot-id field, never to
        a display name.
      * Dataverse layer: the GUID is `botid`; `name` is the friendly DISPLAY
        name and must NEVER be used as the id. Keying on `name` here split the
        id spaces (per-env scans keyed on display names while ARG keyed on
        GUIDs), so the two sets could never intersect.
    """
    if source == DISCOVERY_SOURCE_DATAVERSE:
        # Dataverse `bot` row: botid is the GUID; name is the display name.
        return str(arg_item.get("botid") or "")
    # ARG resource: `name` is the CDS bot GUID (never a display name here).
    return str(
        arg_item.get("name")
        or arg_item.get("botId")
        or arg_item.get("botid")
        or ""
    )


def map_agent_record(ctx: ScanContext, arg_item: dict, source: str) -> dict:
    """Map a raw ARG / bot resource to an fsi_copilotagent row (logical names)."""
    props = arg_item.get("properties", {}) if isinstance(arg_item, dict) else {}
    completeness, reason = classify_scan_completeness(arg_item)
    return {
        "fsi_agentid": _canonical_agent_id(arg_item, source),
        "fsi_agentname": props.get("displayName") or arg_item.get("name", ""),
        "fsi_environmentid": arg_item.get("environmentId")
        or props.get("environmentId", ""),
        "fsi_schemaname": arg_item.get("schemaName") or arg_item.get("schemaname"),
        "fsi_ownerupn": arg_item.get("ownerId") or props.get("ownerId"),
        "fsi_createdin": arg_item.get("createdIn"),
        "fsi_botid": arg_item.get("botId") or arg_item.get("botid"),
        "fsi_entraappid": arg_item.get("entraAppId"),
        "fsi_entraagentid": arg_item.get("entraAgentId"),
        "fsi_region": arg_item.get("location"),
        "fsi_authmode": arg_item.get("authenticationmode"),
        "fsi_lastpublishedat": arg_item.get("lastPublishedAt"),
        "fsi_discoverysource": source,
        "fsi_scancompleteness": completeness,
        "fsi_scancompletenessreason": reason,
        "fsi_runid": ctx.run_id,
        "fsi_rawjson": json.dumps(arg_item)[:100000],
    }


# =============================================================================
# Scale helpers — Dataverse $batch
# =============================================================================


def build_dataverse_batch(environment_url: str, operations: list[dict]) -> str:
    """Build a Dataverse $batch multipart body for bulk reads/writes.

    Skeleton for the scale path: at ~2,000 agents the per-agent botcomponent
    reads and the upserts into fsi_copilotagent should be batched into changeset
    envelopes rather than issued one row at a time. `operations` is a list of
    {method, path, body} dicts. POST the returned body to
    `<environment_url>/api/data/v9.2/$batch` with the multipart boundary header.
    """
    boundary = "batch_cai_inventory"
    lines: list[str] = []
    for op in operations:
        lines.append(f"--{boundary}")
        lines.append("Content-Type: application/http")
        lines.append("Content-Transfer-Encoding: binary")
        lines.append("")
        lines.append(f"{op['method']} {_dataverse_url(environment_url, op['path'])} HTTP/1.1")
        lines.append("Content-Type: application/json")
        lines.append("")
        lines.append(json.dumps(op.get("body", {})) if op.get("body") else "")
    lines.append(f"--{boundary}--")
    return "\r\n".join(lines)


# =============================================================================
# Orchestration
# =============================================================================


def _scan_one_environment(
    ctx: ScanContext, session: requests.Session, environment: dict
) -> dict:
    """Scan a single environment: bots + per-bot features. Fail-open per env."""
    env_url = environment.get("url") or environment.get("instanceUrl") or ""
    env_id = environment.get("name") or environment.get("id") or ""
    result = {"environmentId": env_id, "agents": [], "features": [],
              "deltaLink": None}
    try:
        bots, delta_link = scan_environment_bots(ctx, session, env_url)
        # Thread the delta link into the result instead of discarding it; a
        # future persistence layer can store it for incremental reads (L-4).
        result["deltaLink"] = delta_link
        for bot in bots:
            agent = map_agent_record(ctx, bot, DISCOVERY_SOURCE_DATAVERSE)
            agent["fsi_environmentid"] = agent.get("fsi_environmentid") or env_id
            result["agents"].append(agent)
            bot_id = bot.get("botid", "")
            if bot_id:
                result["features"].extend(
                    scan_bot_features(ctx, session, env_url, bot_id)
                )
    except Exception as exc:  # one bad env must not abort the tenant scan
        logger.warning("Environment %s scan failed (fail-open): %s", env_id, exc)
    return result


def reconcile_sources(arg_agents: list[dict], scanned_agents: list[dict]) -> dict:
    """Layer 3 — reconcile ARG vs per-environment Dataverse (drift detection).

    Reports agents present in one source but not the other ("present in A not
    B"), which surfaces deleted-but-lingering and not-yet-indexed agents. PPAC
    is the third leg; wire it in when its export is available.
    """
    arg_ids = {a.get("fsi_agentid") for a in arg_agents if a.get("fsi_agentid")}
    scan_ids = {a.get("fsi_agentid") for a in scanned_agents if a.get("fsi_agentid")}
    # Smoke check (H-3): both layers derive fsi_agentid from the SAME bot-GUID
    # id space (ARG resource name == Dataverse botid). If both sources returned
    # agents yet share zero ids, the id spaces have split again — surface it
    # loudly rather than reporting a silent 100% false drift.
    if arg_ids and scan_ids and not (arg_ids & scan_ids):
        logger.warning(
            "Reconciliation id-space check FAILED: ARG (%d ids) and Dataverse "
            "(%d ids) intersect to zero — verify fsi_agentid is the bot GUID in "
            "both layers (H-3).", len(arg_ids), len(scan_ids)
        )
    return {
        "in_arg_only": sorted(arg_ids - scan_ids),
        "in_dataverse_only": sorted(scan_ids - arg_ids),
        "in_both": sorted(arg_ids & scan_ids),
    }


def scan_all(ctx: ScanContext) -> dict:
    """Run the three-layer discovery and return the canonical record set."""
    session = _build_session()
    logger.info("Scan run %s (dry_run=%s, max_workers=%d)",
                ctx.run_id, ctx.dry_run, ctx.max_workers)

    arg_agents: list[dict] = []
    if ctx.use_arg and probe_arg_resource_type(ctx, session):
        try:
            arg_agents = [
                map_agent_record(ctx, item, DISCOVERY_SOURCE_ARG)
                for item in query_arg_inventory(ctx, session)
            ]
        except ThrottlingExhaustedError as exc:
            # ARG throttled to exhaustion: discard the partial (and therefore
            # misleading) ARG results and rely on the Layer 2 per-environment
            # scan instead of aborting the run (L-3).
            logger.warning("ARG layer throttled to exhaustion; discarding partial "
                           "ARG results and falling back to Layer 2: %s", exc)
            arg_agents = []
    elif ctx.use_arg:
        logger.info("ARG path unavailable — using Layer 2 per-environment scan "
                    "as the load-bearing default.")

    environments = enumerate_environments(ctx, session)
    scanned_agents: list[dict] = []
    features: list[dict] = []

    # Throttled concurrent per-environment fan-out (~10 workers, 429 backoff).
    with ThreadPoolExecutor(max_workers=ctx.max_workers) as pool:
        futures = {
            pool.submit(_scan_one_environment, ctx, session, env): env
            for env in environments
        }
        for future in as_completed(futures):
            outcome = future.result()
            scanned_agents.extend(outcome["agents"])
            features.extend(outcome["features"])

    reconciliation = reconcile_sources(arg_agents, scanned_agents)
    summary = {
        "runId": ctx.run_id,
        "argAgentCount": len(arg_agents),
        "scannedAgentCount": len(scanned_agents),
        "featureCount": len(features),
        "environmentCount": len(environments),
        "reconciliation": reconciliation,
    }
    logger.info("Scan summary: %s", json.dumps(summary, default=str))
    return {
        "summary": summary,
        "agents": arg_agents or scanned_agents,
        "features": features,
    }


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    """CLI entry point for the discovery scanner."""
    parser = argparse.ArgumentParser(
        description="Three-layer Copilot agent discovery scanner (skeleton)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run — log the planned API calls, contact nothing\n"
            "  python discover_agents.py --dry-run\n\n"
            "  # Live scan with managed identity (Azure-hosted runner)\n"
            "  python discover_agents.py --auth-mode managed-identity \\\n"
            "    --tenant-id <tenant> --output scan.json\n"
        ),
    )
    parser.add_argument("--tenant-id", default=os.environ.get("CAI_TENANT_ID"),
                        help="Microsoft Entra ID tenant ID (or set CAI_TENANT_ID)")
    parser.add_argument("--client-id", default=os.environ.get("CAI_CLIENT_ID"),
                        help="Scanner service principal client ID (or CAI_CLIENT_ID)")
    parser.add_argument(
        "--auth-mode",
        choices=["managed-identity", "workload-identity", "interactive",
                 "client-secret", "default"],
        default=os.environ.get("CAI_AUTH_MODE", "managed-identity"),
        help="Authentication mode; prefer managed-identity for automation",
    )
    parser.add_argument("--power-platform-api", default=DEFAULT_POWER_PLATFORM_API,
                        help="Power Platform API base URL")
    parser.add_argument("--max-workers", type=int, default=DEFAULT_MAX_WORKERS,
                        help="Concurrent per-environment workers (default 10)")
    parser.add_argument("--page-size", type=int, default=DEFAULT_PAGE_SIZE,
                        help="Page size for ARG / Dataverse paging")
    parser.add_argument("--no-arg", action="store_true",
                        help="Skip the ARG layer; per-environment scan only")
    parser.add_argument("--dry-run", action="store_true",
                        help="Log planned API calls without contacting any service")
    parser.add_argument("--output", default=None,
                        help="Write the scan result JSON to this path")
    parser.add_argument("--log-level", default=os.environ.get("CAI_LOG_LEVEL", "INFO"),
                        help="Logging level (DEBUG, INFO, WARNING, ERROR)")
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, str(args.log_level).upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    if not args.dry_run and not args.tenant_id and args.auth_mode != "managed-identity":
        parser.error("--tenant-id is required for live scans unless using "
                     "system-assigned managed identity")

    run_id = f"cai-{int(time.time())}"
    ctx = ScanContext(
        run_id=run_id,
        dry_run=args.dry_run,
        use_arg=not args.no_arg,
        max_workers=max(1, args.max_workers),
        page_size=max(1, args.page_size),
        power_platform_api=args.power_platform_api.rstrip("/"),
        tenant_id=args.tenant_id,
        client_id=args.client_id,
        auth_mode=args.auth_mode,
    )

    try:
        result = scan_all(ctx)
    except Exception as exc:
        logger.error("Scan failed: %s", exc)
        sys.exit(1)

    if args.output:
        out_path = Path(args.output)
        out_path.write_text(json.dumps(result, indent=2, default=str), encoding="utf-8")
        logger.info("Wrote scan result to %s", out_path)


if __name__ == "__main__":
    main()
