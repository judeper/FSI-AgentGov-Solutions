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
import re
import secrets
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
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
DISCOVERY_SOURCE_PACKAGE_API = "Package Management API"
DISCOVERY_SOURCE_RECONCILED = "Reconciled (multi-source)"

# Graph Package Management API (GA v1.0, application permission
# CopilotPackages.Read.All, admin-consented).
# Ref: learn.microsoft.com/microsoft-365/copilot/extensibility/api/
#      admin-settings/package/copilotpackages-list
GRAPH_SCOPE = "https://graph.microsoft.com/.default"
GRAPH_API_BASE = "https://graph.microsoft.com/v1.0"
PACKAGE_API_PATH = "/copilot/admin/catalog/packages"
SUBSCRIBED_SKUS_API_PATH = "/subscribedSkus"
SUBSCRIBED_SKUS_PERMISSION_GUIDANCE = (
    "Use Microsoft Graph application permission LicenseAssignment.Read.All "
    "(least privileged). Organization.Read.All is also supported."
)

# Platforms to query from the Package Management API. Restricted to Agent Builder
# ONLY — the ARG and Dataverse layers already cover Copilot Studio, and package
# joins are not strong enough to prevent duplicates if both are queried here.
PACKAGE_API_PLATFORMS = [
    CREATED_IN_AGENT_BUILDER,   # "Microsoft 365 Copilot Agent Builder"
]

# Package ids from the Package Management API start with "P_" — a DISTINCT id
# space from the Copilot Studio bot GUID that fsi_agentid uses for ARG and
# Dataverse sourced rows. Reconciliation joins on appId / manifestId; standalone
# package-only rows use the package id as fsi_agentid.
PACKAGE_ID_PREFIX = "P_"

AGENT365_MODE_PRESENT = "present"
AGENT365_MODE_ABSENT = "absent"
AGENT365_MODE_AUTO = "auto"
AGENT365_MODES = (AGENT365_MODE_PRESENT, AGENT365_MODE_ABSENT, AGENT365_MODE_AUTO)
DEFAULT_AGENT365_MODE = AGENT365_MODE_ABSENT
AGENT365_MODE_CHOICE_LABELS = {
    AGENT365_MODE_PRESENT: "Present",
    AGENT365_MODE_ABSENT: "Absent",
    AGENT365_MODE_AUTO: "Auto",
}

AGENT365_STATE_PRESENT = "Present"
AGENT365_STATE_ABSENT = "Absent"
AGENT365_STATE_NOT_DETECTED = "NotDetected"
AGENT365_STATE_INCONCLUSIVE = "Inconclusive"

LAYER_STATUS_FULL = "Full"
LAYER_STATUS_DEFERRED = "Deferred"
LAYER_STATUS_UNSUPPORTED = "Unsupported"
LAYER_STATUS_PARTIAL = "Partial"
LAYER_STATUS_FAILED = "Failed"
LAYER_STATUS_DRY_RUN = "Dry Run"

AGENT365_ALIAS_OVERRIDE_ENV = "CAI_AGENT365_LICENSE_ALIASES"
AGENT365_ALIAS_OVERRIDE_ENV_LEGACY = "CAI_AGENT365_SKU_ALIASES"
DEFAULT_AGENT365_LICENSE_ALIASES = frozenset(
    {
        # Heuristic aliases only, normalized from currently documented
        # product/display names (not authoritative SKU/service plan IDs).
        "MICROSOFT_AGENT_365",
        "MICROSOFT_365_E7",
        "AGENT_365_FRONTIER",
        "MICROSOFT_365_FRONTIER_FOR_AI_TEAMMATES",
    }
)

# Completeness label written to every package-touched row when the Package
# Management API enumeration was truncated (paging incomplete). Used by
# reconcile_package_catalog when the caller signals truncation.
_PACKAGE_TRUNCATION_REASON = (
    "Package Management API enumeration truncated (paging incomplete)"
)

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
# createdon, modifiedon - all needed for the canonical Agent record). The
# accesscontrolpolicy + authorizedsecuritygroupids columns carry the per-agent
# sharing posture used to derive whole-tenant reach (fsi_sharedwitheveryone).
BOT_SELECT = (
    "botid,name,schemaname,statecode,statuscode,authenticationmode,"
    "createdon,modifiedon,_ownerid_value,accesscontrolpolicy,authorizedsecuritygroupids"
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
    agent365_requested_mode: str = DEFAULT_AGENT365_MODE
    agent365_resolution_source: str = "Default"
    agent365_alias_overrides: tuple[str, ...] = ()
    # Optional registry-correlation + entitlement fields (D).
    registry_export_path: Optional[str] = None
    columnmap_path: Optional[str] = None
    as_of: Optional[str] = None
    resolve_entitlement: bool = False
    entitlement_ps1_path: Optional[str] = None
    _credential: Any = field(default=None, repr=False)


class Agent365ProbeOutcome(str, Enum):
    """Typed outcomes for the Agent 365 license probe."""

    DETECTED = "detected"
    NOT_DETECTED = "not-detected"
    INCONCLUSIVE = "inconclusive"
    DRY_RUN = "dry-run"
    NOT_ATTEMPTED = "not-attempted"


class PackageApiOutcome(str, Enum):
    """Typed outcomes for the Package Management API call."""

    SUCCESS_EMPTY = "success-empty"
    SUCCESS_DATA = "success-data"
    PAGING_TRUNCATED = "paging-truncated"
    HTTP_401 = "http-401"
    HTTP_403 = "http-403"
    HTTP_404_UNSUPPORTED = "http-404-unsupported"
    HTTP_429 = "http-429-throttle"
    HTTP_5XX = "http-5xx"
    TRANSPORT_FAILURE = "transport-failure"
    PARSE_FAILURE = "parse-failure"
    DRY_RUN = "dry-run"
    DEFERRED = "deferred"


@dataclass
class Agent365LicenseProbeResult:
    """Normalized result of probing /subscribedSkus."""

    outcome: Agent365ProbeOutcome
    attempted: bool
    http_status: Optional[int] = None
    error_code: str = ""
    error_subcode: str = ""
    reason: str = ""
    matched_aliases: tuple[str, ...] = ()


@dataclass
class PackageApiFetchResult:
    """Normalized result of querying the Package Management API."""

    outcome: PackageApiOutcome
    attempted: bool
    packages: list[dict] = field(default_factory=list)
    paging_truncated: bool = False
    http_status: Optional[int] = None
    error_code: str = ""
    error_subcode: str = ""
    reason: str = ""


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


class EnvironmentEnumerationError(RuntimeError):
    """Raised when the BAP environment enumeration itself fails.

    Distinct from a genuinely empty (HTTP 200, ``value: []``) tenant: an
    authorization or API failure on the environment-list call must NEVER be
    returned as a success-shaped empty list, because that makes a 401/403 look
    like a clean, agent-free tenant. Carries the HTTP status (when known) and a
    stage label so the caller can surface the failure in structured output and
    exit non-zero.
    """

    def __init__(
        self, message: str, *, http_status: Optional[int] = None,
        stage: str = "environment-enumeration",
    ) -> None:
        super().__init__(message)
        self.http_status = http_status
        self.stage = stage


class EnvironmentScanError(RuntimeError):
    """Raised when a per-environment Dataverse read returns a non-200 response.

    Retained (via `_scan_one_environment`) as a structured per-environment
    failure so a per-environment authorization failure (401/403) is never
    indistinguishable from an environment that genuinely contains zero agents.
    """

    def __init__(
        self, message: str, *, http_status: Optional[int] = None,
        stage: str = "bots",
    ) -> None:
        super().__init__(message)
        self.http_status = http_status
        self.stage = stage


class ArgQueryError(RuntimeError):
    """Raised when the Layer 1 ARG resource query returns a non-200 response.

    A failed ARG query must NOT be treated as an observed zero-agent tenant: the
    caller records the ARG layer as ``Failed`` (distinct from ``Available`` with
    zero results) and falls back to the load-bearing Layer 2 per-environment scan.
    """

    def __init__(self, message: str, *, http_status: Optional[int] = None) -> None:
        super().__init__(message)
        self.http_status = http_status


# Defensive scrubs for exception strings before they are written to structured
# output fields.
_BEARER_RE = re.compile(r"Bearer\s+[A-Za-z0-9\-\._~\+\/]+=*", re.IGNORECASE)
_UPN_RE = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
_URL_RE = re.compile(r'https?://[^\s"\'<>]+', re.IGNORECASE)
_SAFE_CODE_RE = re.compile(r"[^A-Za-z0-9_.-]")
_NON_ALNUM_RE = re.compile(r"[^A-Za-z0-9]+")


def _sanitize_reason(text: Any, limit: int = 500) -> str:
    """Return a bounded, token-free failure reason safe for structured output."""
    if not text:
        return ""
    cleaned = _BEARER_RE.sub("******", str(text))
    cleaned = _UPN_RE.sub("<redacted-upn>", cleaned)
    cleaned = _URL_RE.sub("<redacted-url>", cleaned)
    return cleaned[:limit]


def _sanitize_code(text: Any, limit: int = 120) -> str:
    """Return a bounded machine-safe code field."""
    if not text:
        return ""
    cleaned = _SAFE_CODE_RE.sub("", str(text))
    return cleaned[:limit]


def _normalize_alias_token(value: Any) -> str:
    """Normalize SKU/service-plan identifiers for exact alias matching."""
    if value is None:
        return ""
    normalized = _NON_ALNUM_RE.sub("_", str(value).strip().upper()).strip("_")
    return normalized


def _parse_agent365_alias_overrides(raw: Optional[str]) -> tuple[str, ...]:
    """Parse operator-provided Agent 365 alias overrides from environment."""
    if not raw:
        return ()
    aliases: list[str] = []
    seen: set[str] = set()
    for token in re.split(r"[,\n\r;]+", raw):
        token = token.strip()
        normalized = _normalize_alias_token(token)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        aliases.append(normalized)
    return tuple(aliases)


def _get_agent365_alias_override_raw() -> Optional[str]:
    """Resolve operator override aliases with legacy env-var compatibility."""
    primary = os.environ.get(AGENT365_ALIAS_OVERRIDE_ENV)
    if primary and primary.strip():
        return primary
    legacy = os.environ.get(AGENT365_ALIAS_OVERRIDE_ENV_LEGACY)
    if legacy and legacy.strip():
        logger.warning(
            "DEPRECATED: %s is retained for one release. Use %s for comma-separated "
            "Agent 365 license alias overrides.",
            AGENT365_ALIAS_OVERRIDE_ENV_LEGACY,
            AGENT365_ALIAS_OVERRIDE_ENV,
        )
        return legacy
    return None


def _coerce_int(value: Any) -> int:
    """Parse an int from mixed Graph payload values."""
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _extract_graph_error_fields(payload: Any) -> tuple[str, str]:
    """Extract sanitized Graph error code/subcode fields."""
    if not isinstance(payload, dict):
        return "", ""
    error = payload.get("error")
    if not isinstance(error, dict):
        return "", ""
    code = _sanitize_code(error.get("code"))
    subcode = ""
    inner_error = error.get("innerError")
    if isinstance(inner_error, dict):
        subcode = _sanitize_code(
            inner_error.get("code")
            or inner_error.get("errorCode")
            or inner_error.get("innerErrorCode")
        )
    if not subcode:
        subcode = _sanitize_code(error.get("subcode") or error.get("innerErrorCode"))
    return code, subcode


def _env_failure(
    environment_id: str,
    stage: str,
    http_status: Optional[int],
    reason: Any,
    bot_id: Optional[str] = None,
) -> dict:
    """Build one structured per-environment (or per-bot) scan-failure record.

    Preserves the environment identifier/provenance, the failing stage, the HTTP
    status (when known), and a sanitized reason so a coverage gap is auditable
    rather than silently collapsing to a zero-agent count.
    """
    record: dict = {
        "environmentId": environment_id,
        "stage": stage,
        "httpStatus": http_status,
        "reason": _sanitize_reason(reason),
    }
    if bot_id:
        record["botId"] = bot_id
    return record


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


def _generate_run_id(now: Optional[datetime] = None) -> str:
    """Generate a sortable, collision-resistant run id."""
    timestamp = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    return f"cai-{timestamp.strftime('%Y%m%dT%H%M%SZ')}-{secrets.token_hex(7)}"


def _agent365_aliases(ctx: ScanContext) -> set[str]:
    """Return the normalized baseline alias set plus operator overrides."""
    aliases = set(DEFAULT_AGENT365_LICENSE_ALIASES)
    aliases.update(ctx.agent365_alias_overrides)
    return aliases


def probe_agent365_license(
    ctx: ScanContext, session: requests.Session
) -> Agent365LicenseProbeResult:
    """Probe /subscribedSkus for Agent 365 license heuristics.

    Permission guidance: LicenseAssignment.Read.All is least-privilege;
    Organization.Read.All is also supported.
    """
    if ctx.dry_run:
        return Agent365LicenseProbeResult(
            outcome=Agent365ProbeOutcome.DRY_RUN,
            attempted=False,
            reason="Dry run: skipped /subscribedSkus probe.",
        )

    url = (
        f"{GRAPH_API_BASE}{SUBSCRIBED_SKUS_API_PATH}"
        "?$select=skuPartNumber,capabilityStatus,consumedUnits,prepaidUnits,servicePlans"
    )
    try:
        token = _get_token(ctx, GRAPH_SCOPE)
    except Exception as exc:
        return Agent365LicenseProbeResult(
            outcome=Agent365ProbeOutcome.INCONCLUSIVE,
            attempted=True,
            error_code="TokenAcquisitionFailed",
            reason="Agent 365 license probe token acquisition failed.",
            error_subcode=_sanitize_code(type(exc).__name__),
        )

    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    try:
        resp = _request_with_backoff(session, "GET", url, headers=headers)
    except ThrottlingExhaustedError:
        return Agent365LicenseProbeResult(
            outcome=Agent365ProbeOutcome.INCONCLUSIVE,
            attempted=True,
            http_status=429,
            error_code="TooManyRequests",
            reason="Agent 365 license probe throttled (HTTP 429).",
        )
    except requests.exceptions.RequestException as exc:
        return Agent365LicenseProbeResult(
            outcome=Agent365ProbeOutcome.INCONCLUSIVE,
            attempted=True,
            error_code="TransportFailure",
            reason="Agent 365 license probe transport failure.",
            error_subcode=_sanitize_code(type(exc).__name__),
        )

    payload: Any
    try:
        payload = resp.json()
    except ValueError:
        return Agent365LicenseProbeResult(
            outcome=Agent365ProbeOutcome.INCONCLUSIVE,
            attempted=True,
            http_status=resp.status_code,
            error_code="ParseFailure",
            reason="Agent 365 license probe returned malformed JSON.",
        )
    if not isinstance(payload, dict):
        return Agent365LicenseProbeResult(
            outcome=Agent365ProbeOutcome.INCONCLUSIVE,
            attempted=True,
            http_status=resp.status_code,
            error_code="MalformedResponse",
            reason="Agent 365 license probe response must be a JSON object.",
        )

    graph_code, graph_subcode = _extract_graph_error_fields(payload)
    if resp.status_code != 200:
        reason = "Agent 365 license probe failed."
        if resp.status_code == 401:
            reason = "Agent 365 license probe unauthorized (HTTP 401)."
        elif resp.status_code == 403:
            reason = (
                "Agent 365 license probe forbidden (HTTP 403). "
                f"{SUBSCRIBED_SKUS_PERMISSION_GUIDANCE}"
            )
        elif resp.status_code == 404:
            reason = "Agent 365 license probe endpoint unavailable (HTTP 404)."
        elif resp.status_code == 429:
            reason = "Agent 365 license probe throttled (HTTP 429)."
        elif 500 <= resp.status_code <= 599:
            reason = "Agent 365 license probe server failure (HTTP 5xx)."
        return Agent365LicenseProbeResult(
            outcome=Agent365ProbeOutcome.INCONCLUSIVE,
            attempted=True,
            http_status=resp.status_code,
            error_code=graph_code or f"Http{resp.status_code}",
            error_subcode=graph_subcode,
            reason=reason,
        )

    rows = payload.get("value")
    if not isinstance(rows, list):
        return Agent365LicenseProbeResult(
            outcome=Agent365ProbeOutcome.INCONCLUSIVE,
            attempted=True,
            http_status=200,
            error_code="MalformedResponse",
            reason="Agent 365 license probe missing 'value' array.",
        )

    aliases = _agent365_aliases(ctx)
    matched_aliases: set[str] = set()
    for sku in rows:
        if not isinstance(sku, dict):
            continue
        sku_alias = _normalize_alias_token(sku.get("skuPartNumber"))
        prepaid_units = sku.get("prepaidUnits")
        if not isinstance(prepaid_units, dict):
            prepaid_units = {}
        enabled_units = _coerce_int(prepaid_units.get("enabled"))
        consumed_units = _coerce_int(sku.get("consumedUnits"))
        capability_status = str(sku.get("capabilityStatus") or "").strip().lower()
        seat_signal_present = enabled_units > 0 or consumed_units > 0
        sku_usable = capability_status == "enabled" and seat_signal_present

        plan_aliases_success: set[str] = set()
        for plan in sku.get("servicePlans") or []:
            if not isinstance(plan, dict):
                continue
            normalized = _normalize_alias_token(plan.get("servicePlanName"))
            if not normalized or normalized not in aliases:
                continue
            provisioning = str(plan.get("provisioningStatus") or "").strip().lower()
            if provisioning == "success":
                plan_aliases_success.add(normalized)

        if sku_alias and sku_alias in aliases and sku_usable:
            matched_aliases.add(sku_alias)
        if plan_aliases_success and sku_usable:
            matched_aliases.update(plan_aliases_success)

    if matched_aliases:
        return Agent365LicenseProbeResult(
            outcome=Agent365ProbeOutcome.DETECTED,
            attempted=True,
            reason=(
                "Heuristic Agent 365 name aliases detected in /subscribedSkus "
                "with usable SKU signals (capabilityStatus Enabled and "
                "prepaidUnits.enabled>0 or consumedUnits>0). Service-plan-only "
                "matches require provisioningStatus Success. "
                "This signal is non-authoritative."
            ),
            matched_aliases=tuple(sorted(matched_aliases)),
        )

    return Agent365LicenseProbeResult(
        outcome=Agent365ProbeOutcome.NOT_DETECTED,
        attempted=True,
        reason=(
            "No heuristic Agent 365 name alias met usable SKU criteria in "
            "/subscribedSkus (capabilityStatus Enabled plus seats/assignments; "
            "service-plan-only matches require provisioningStatus Success). "
            "Manual verification or --agent365 present override is recommended."
        ),
    )


def _resolve_agent365_state(
    ctx: ScanContext, session: requests.Session
) -> tuple[str, str, str, Agent365LicenseProbeResult]:
    """Resolve Agent 365 state from requested mode and optional license probe."""
    requested = ctx.agent365_requested_mode
    if requested == AGENT365_MODE_ABSENT:
        return (
            AGENT365_STATE_ABSENT,
            ctx.agent365_resolution_source,
            "OperatorDeclared",
            Agent365LicenseProbeResult(
                outcome=Agent365ProbeOutcome.NOT_ATTEMPTED,
                attempted=False,
                reason="Operator declared Agent 365 absent.",
            ),
        )
    if requested == AGENT365_MODE_PRESENT:
        return (
            AGENT365_STATE_PRESENT,
            ctx.agent365_resolution_source,
            "OperatorDeclared",
            Agent365LicenseProbeResult(
                outcome=Agent365ProbeOutcome.NOT_ATTEMPTED,
                attempted=False,
                reason="Operator declared Agent 365 present.",
            ),
        )

    probe = probe_agent365_license(ctx, session)
    if probe.outcome == Agent365ProbeOutcome.DETECTED:
        return (AGENT365_STATE_PRESENT, "LicenseProbe", "Heuristic", probe)
    if probe.outcome == Agent365ProbeOutcome.NOT_DETECTED:
        return (AGENT365_STATE_NOT_DETECTED, "LicenseProbe", "Heuristic", probe)
    if probe.outcome == Agent365ProbeOutcome.DRY_RUN:
        return (AGENT365_STATE_INCONCLUSIVE, "DryRun", "Inconclusive", probe)
    return (AGENT365_STATE_INCONCLUSIVE, "LicenseProbe", "Inconclusive", probe)


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
            # A failed ARG query is NOT an observed zero-agent tenant. Raise so the
            # caller records the ARG layer as Failed and falls back to Layer 2,
            # rather than silently returning the (possibly partial) rows gathered
            # so far as if paging had reached its natural end.
            raise ArgQueryError(
                f"ARG query failed with HTTP {resp.status_code}",
                http_status=resp.status_code,
            )
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

    Raises EnvironmentEnumerationError on a non-200 response, a non-JSON body, or
    a payload missing a valid ``value`` array. This is deliberate: a soft break
    that returned the rows gathered so far (often none) would make an
    authorization/API failure indistinguishable from a genuinely empty tenant. A
    successful HTTP 200 with ``value: []`` is a genuinely empty result and is
    returned as an empty list (the caller distinguishes it in the summary).
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
            raise EnvironmentEnumerationError(
                f"Environment enumeration failed with HTTP {resp.status_code}",
                http_status=resp.status_code,
            )
        try:
            payload = resp.json()
        except ValueError as exc:
            raise EnvironmentEnumerationError(
                "Environment enumeration returned a non-JSON body"
            ) from exc
        value = payload.get("value")
        if not isinstance(value, list):
            raise EnvironmentEnumerationError(
                "Environment enumeration response is missing a valid 'value' array"
            )
        environments.extend(value)
        url = payload.get("nextLink") or payload.get("@odata.nextLink")
        headers = {"Authorization": f"Bearer {token}"}
    logger.info("Enumerated %d environments", len(environments))
    return environments


def _environment_dataverse_url(environment: dict) -> str:
    """Return the Dataverse instance URL from supported BAP response shapes."""
    properties = environment.get("properties")
    if not isinstance(properties, dict):
        properties = {}
    linked_metadata = properties.get("linkedEnvironmentMetadata")
    if not isinstance(linked_metadata, dict):
        linked_metadata = {}

    for candidate in (
        environment.get("url"),
        environment.get("instanceUrl"),
        properties.get("instanceUrl"),
        linked_metadata.get("instanceUrl"),
    ):
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip().rstrip("/")
    return ""


def _environment_has_no_dataverse(environment: dict) -> bool:
    """Return True when BAP explicitly classifies the environment as database-free."""
    properties = environment.get("properties")
    if not isinstance(properties, dict):
        return False
    return (
        not _environment_dataverse_url(environment)
        and str(properties.get("databaseType") or "").strip().casefold() == "none"
    )


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
            # A non-200 bot read is a per-environment scan failure, NOT an empty
            # environment. Raise so `_scan_one_environment` records a structured
            # coverage-gap entry instead of returning the (possibly partial) rows
            # gathered so far as if the environment simply had few/no agents.
            raise EnvironmentScanError(
                f"bot scan failed with HTTP {resp.status_code} for {environment_url}",
                http_status=resp.status_code,
                stage="bots",
            )
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
            # A non-200 botcomponent read is a per-bot feature-scan failure. Raise
            # so the caller can retain a structured failure and mark the agent's
            # scan incomplete, rather than silently returning fewer features.
            raise EnvironmentScanError(
                f"botcomponent scan failed with HTTP {resp.status_code} "
                f"for bot {bot_id}",
                http_status=resp.status_code,
                stage="botcomponents",
            )
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


# The bot.accesscontrolpolicy option-set: 0 = "Any" (everyone in the org) and
# 3 = "Any (multi-tenant)" (everyone + external) both mean the agent is reachable
# org-wide; 2 = specific security groups and 1 = a more restrictive policy are NOT
# whole-tenant. Values verified against unrestricted-agent-sharing-detector
# (SOLUTION-DOCUMENTATION.md: accesscontrolpolicy 0=Any, 2=security groups,
# 3=Any (multi-tenant)).
ORG_WIDE_ACCESS_POLICIES = frozenset({0, 3})
RESTRICTED_ACCESS_POLICIES = frozenset({1, 2})


def derive_shared_with_everyone(bot: dict) -> Optional[bool]:
    """Derive per-agent whole-tenant reach from the bot accesscontrolpolicy.

    Returns True for an org-wide policy (Any / Any multi-tenant), False for a
    restricted policy (security groups / more restrictive), and None when the
    signal is absent or unparseable. None is deliberate: it must NOT be coerced to
    False, because expand_audience_upns.py treats an unset fsi_sharedwitheveryone
    as an unknown whole-tenant signal and marks the audience Partial rather than
    emitting a confident empty audience for a possibly tenant-reachable agent.

    This is a PER-AGENT signal and must never be confused with the
    environment-wide bot-limitSharingMode policy.
    """
    raw = bot.get("accesscontrolpolicy")
    if raw is None or isinstance(raw, bool):
        return None
    try:
        policy = int(raw)
    except (TypeError, ValueError):
        return None
    if policy in ORG_WIDE_ACCESS_POLICIES:
        return True
    if policy in RESTRICTED_ACCESS_POLICIES:
        return False
    return None


def _authshare_record(ctx: ScanContext, bot: dict) -> dict:
    """Build one fsi_caiauthshare row capturing the agent's sharing posture.

    Stamps fsi_sharedwitheveryone from the per-agent accesscontrolpolicy signal.
    When the signal is unknown (derive_shared_with_everyone returns None) the
    column is intentionally left OFF the record so the Dataverse value stays unset
    and the downstream audience expander marks the agent Partial instead of
    asserting a confident empty audience.
    """
    record = {
        "fsi_agentid": bot.get("botid", ""),
        "fsi_authmode": bot.get("authenticationmode"),
        "fsi_runid": ctx.run_id,
    }
    groups = bot.get("authorizedsecuritygroupids")
    if groups:
        record["fsi_viewergroups"] = json.dumps(
            [g.strip() for g in str(groups).split(",") if g.strip()]
        )
    shared_everyone = derive_shared_with_everyone(bot)
    if shared_everyone is not None:
        record["fsi_sharedwitheveryone"] = shared_everyone
    return record


# =============================================================================
# Mapping + classification
# =============================================================================


def classify_scan_completeness(agent: dict) -> tuple[str, str]:
    """Return (scan_completeness, reason).

    Agent Builder agents discovered via the Graph Package Management API (GA
    v1.0, application permission CopilotPackages.Read.All, admin-consented) are
    classified as Complete: the catalog endpoint returns their package definition.
    Enable the API layer with --agent365 present (or --agent365 auto when
    license detection resolves to Present).

    Agent Builder agents discovered only via ARG or Dataverse without Package API
    enrichment remain Incomplete Scan: ARG/Dataverse do not return their full
    definition (instructions + knowledge + capabilities). fsi_packageid being
    set on a row signals that Package API data is present and upgrades
    completeness from Incomplete Scan to Complete.
    """
    created_in = (agent.get("createdIn") or agent.get("fsi_createdin") or "")
    if created_in == CREATED_IN_AGENT_BUILDER:
        if agent.get("fsi_packageid"):
            # Package Management API contributed catalog data: upgrade to Complete.
            return ("Complete", "")
        return (
            "Incomplete Scan",
            "Agent Builder agent discovered without Package API enrichment. "
            "Enable --agent365 present (GA v1.0, CopilotPackages.Read.All) "
            "to upgrade scan completeness when catalog data is available.",
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
    """Scan a single environment: bots + per-bot features.

    A per-environment failure is RETAINED as structured output (``failures`` +
    ``status``) rather than being swallowed. This is the core fix for the
    silent-authorization-failure gap: an environment that 401/403s on its bot
    read must surface as ``status="Failed"`` with a coverage-gap record, never as
    a ``status="Complete"`` environment that merely contributed zero agents.

    ``status`` is one of:
      * ``"Complete"``   — bots read and every per-bot feature read succeeded.
      * ``"Incomplete"`` — bots read, but at least one per-bot feature read failed
                           (the agent row is kept and flagged Incomplete Scan).
      * ``"Failed"``     — the bot read itself failed; the environment contributed
                           no trustworthy agent rows.
    """
    env_url = _environment_dataverse_url(environment)
    env_id = environment.get("name") or environment.get("id") or ""
    result: dict = {
        "environmentId": env_id,
        "environmentUrl": env_url,
        "agents": [],
        "features": [],
        "authShares": [],
        "deltaLink": None,
        "failures": [],
        "status": "Complete",
    }
    if not env_url:
        exc = ValueError(
            "BAP environment metadata is missing a Dataverse instance URL"
        )
        result["status"] = "Failed"
        result["failures"].append(_env_failure(env_id, "environment", None, exc))
        logger.warning(
            "Environment %s has no Dataverse instance URL; recorded as a "
            "coverage gap.",
            env_id,
        )
        return result
    try:
        bots, delta_link = scan_environment_bots(ctx, session, env_url)
    except EnvironmentScanError as exc:
        result["status"] = "Failed"
        result["failures"].append(
            _env_failure(env_id, exc.stage, exc.http_status, exc)
        )
        logger.warning("Environment %s bot scan FAILED (HTTP %s); recorded as a "
                       "coverage gap, not a zero-agent environment.",
                       env_id, exc.http_status)
        return result
    except ThrottlingExhaustedError as exc:
        result["status"] = "Failed"
        result["failures"].append(_env_failure(env_id, "bots", None, exc))
        logger.warning("Environment %s bot scan throttled to exhaustion; recorded "
                       "as a coverage gap (Failed).", env_id)
        return result
    except Exception as exc:  # one bad env must not abort the whole tenant scan
        result["status"] = "Failed"
        result["failures"].append(_env_failure(env_id, "environment", None, exc))
        logger.warning("Environment %s scan failed (recorded as coverage gap): %s",
                       env_id, exc)
        return result

    # Thread the delta link into the result instead of discarding it; a future
    # persistence layer can store it for incremental reads (L-4).
    result["deltaLink"] = delta_link
    try:
        for bot in bots:
            agent = map_agent_record(ctx, bot, DISCOVERY_SOURCE_DATAVERSE)
            agent["fsi_environmentid"] = agent.get("fsi_environmentid") or env_id
            result["agents"].append(agent)
            bot_id = bot.get("botid", "")
            if not bot_id:
                continue
            try:
                result["features"].extend(
                    scan_bot_features(ctx, session, env_url, bot_id)
                )
            except (EnvironmentScanError, ThrottlingExhaustedError) as exc:
                # The agent exists but its features could not be fully read: keep
                # the agent row, flag it Incomplete Scan, and downgrade the
                # environment to Incomplete (never silently drop features as if
                # the agent had none).
                if result["status"] == "Complete":
                    result["status"] = "Incomplete"
                stage = getattr(exc, "stage", "botcomponents")
                http_status = getattr(exc, "http_status", None)
                result["failures"].append(
                    _env_failure(env_id, stage, http_status, exc, bot_id=bot_id)
                )
                agent["fsi_scancompleteness"] = "Incomplete Scan"
                agent["fsi_scancompletenessreason"] = (
                    agent.get("fsi_scancompletenessreason")
                    or f"botcomponent feature read failed "
                       f"(stage={stage}, http={http_status})"
                )
                logger.warning("Bot %s in environment %s: feature scan FAILED "
                               "(HTTP %s); agent flagged Incomplete Scan.",
                               bot_id, env_id, http_status)
            authshare = _authshare_record(ctx, bot)
            authshare["fsi_environmentid"] = (
                authshare.get("fsi_environmentid") or env_id
            )
            result["authShares"].append(authshare)
    except Exception as exc:  # unexpected per-env error: retain, don't abort scan
        result["status"] = "Failed"
        result["failures"].append(_env_failure(env_id, "environment", None, exc))
        logger.warning("Environment %s scan failed mid-iteration (recorded as a "
                       "coverage gap): %s", env_id, exc)
    return result


def reconcile_sources(arg_agents: list[dict], scanned_agents: list[dict]) -> dict:
    """Layer 3 — reconcile ARG vs per-environment Dataverse (drift detection).

    Reports agents present in one source but not the other ("present in A not
    B"), which surfaces deleted-but-lingering and not-yet-indexed agents. PPAC
    is the third leg; wire it in when its export is available.

    Package Management API rows key fsi_agentid on P_... ids (a distinct id
    space from the bot GUID). They are reconciled separately in
    reconcile_package_catalog() and must NOT participate in ARG/Dataverse drift
    detection. P_... ids are excluded here as a defensive guard; callers should
    not pass package-sourced rows to this function — cross-id-space comparison
    produces a false 100% drift report (same H-3 guard, applied inter-layer).
    """
    def _is_bot_guid_row(a: dict) -> bool:
        aid = str(a.get("fsi_agentid") or "")
        return bool(aid) and not aid.startswith(PACKAGE_ID_PREFIX)

    arg_ids = {a.get("fsi_agentid") for a in arg_agents if _is_bot_guid_row(a)}
    scan_ids = {a.get("fsi_agentid") for a in scanned_agents if _is_bot_guid_row(a)}
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


# =============================================================================
# Layer 4 — Package Management API (Agent 365 mode-gated)
# =============================================================================


def _package_status_label(raw: Any) -> str:
    """Map a copilotPackage availableTo/deployedTo value to the option-set label.

    The API returns lowercase strings ("none", "some", "all"). The
    fsi_cai_packagestatus Dataverse option-set uses Title Case labels.
    """
    return {"none": "None", "some": "Some", "all": "All"}.get(
        str(raw or "").lower(), "None"
    )


def _package_fields(ctx: ScanContext, pkg: dict) -> dict:
    """Extract ALL first-class package API fields for merging into an agent row.

    Projects the full documented field set so BI consumers never need to parse
    rawjson. Includes the five new Yen columns (fsi_packagetype, fsi_elementtypes,
    fsi_isblocked, fsi_packageversion, fsi_assetid) plus fsi_modifiedon and the
    derived fsi_agenttype.
    """
    hosts = pkg.get("supportedHosts") or []
    element_types = pkg.get("elementTypes") or []
    if not isinstance(element_types, list):
        element_types = []

    # Derive fsi_agenttype from elementTypes per the contract.
    if "DeclarativeAgent" in element_types:
        agent_type = "Declarative Agent"
    elif "CustomEngineAgent" in element_types:
        agent_type = "Custom Engine Agent"
    else:
        agent_type = "Lite / Agent Builder"

    return {
        "fsi_packageid": pkg.get("id", ""),
        "fsi_publisher": pkg.get("publisher", ""),
        "fsi_supportedhosts": json.dumps(hosts if isinstance(hosts, list) else []),
        "fsi_availableto": _package_status_label(pkg.get("availableTo")),
        "fsi_deployedto": _package_status_label(pkg.get("deployedTo")),
        "fsi_manifestid": pkg.get("manifestId", ""),
        "fsi_manifestversion": pkg.get("manifestVersion", ""),
        "fsi_entraappid": pkg.get("appId"),
        "fsi_modifiedon": pkg.get("lastModifiedDateTime"),
        "fsi_packagetype": pkg.get("type"),
        "fsi_elementtypes": json.dumps(element_types),
        "fsi_isblocked": pkg.get("isBlocked"),
        "fsi_packageversion": pkg.get("version"),
        "fsi_assetid": pkg.get("assetId"),
        "fsi_agenttype": agent_type,
        "fsi_discoverysource": DISCOVERY_SOURCE_PACKAGE_API,
        "fsi_runid": ctx.run_id,
    }


def map_package_record(ctx: ScanContext, pkg: dict) -> dict:
    """Map a copilotPackage API object to a standalone fsi_copilotagent row.

    Used when reconcile_package_catalog() finds no appId/manifestId match in
    the existing agent set. The fsi_agentid is the package id (P_... id space)
    and fsi_ownermatchconfidence is "Unmatched" — the Package API returns no
    creator/owner field, so owner attribution is not possible from this source.
    """
    pkg_id = str(pkg.get("id") or "")
    platform = str(pkg.get("platform") or "")
    # The package 'platform' value mirrors the ARG/Dataverse 'createdIn' strings.
    agent_dict: dict = {
        "fsi_agentid": pkg_id,
        "fsi_agentname": pkg.get("displayName", ""),
        "fsi_createdin": platform,
        "fsi_entraappid": pkg.get("appId"),
        "fsi_ownermatchconfidence": "Unmatched",
        "fsi_rawjson": json.dumps(pkg)[:100000],
    }
    agent_dict.update(_package_fields(ctx, pkg))  # sets fsi_packageid
    completeness, reason = classify_scan_completeness(agent_dict)
    agent_dict["fsi_scancompleteness"] = completeness
    agent_dict["fsi_scancompletenessreason"] = reason
    return agent_dict


def _package_outcome_from_http_status(status_code: int) -> PackageApiOutcome:
    """Classify HTTP status into a typed Package API outcome."""
    if status_code == 401:
        return PackageApiOutcome.HTTP_401
    if status_code == 403:
        return PackageApiOutcome.HTTP_403
    if status_code == 404:
        return PackageApiOutcome.HTTP_404_UNSUPPORTED
    if status_code == 429:
        return PackageApiOutcome.HTTP_429
    if 500 <= status_code <= 599:
        return PackageApiOutcome.HTTP_5XX
    return PackageApiOutcome.PAGING_TRUNCATED


def fetch_package_catalog_details(
    ctx: ScanContext, session: requests.Session
) -> PackageApiFetchResult:
    """Fetch Package API data with typed outcome metadata."""
    if ctx.dry_run:
        for platform in PACKAGE_API_PLATFORMS:
            logger.info(
                "[DRY RUN] would GET %s%s?$filter=platform eq '%s' "
                "(app permission: CopilotPackages.Read.All)",
                GRAPH_API_BASE, PACKAGE_API_PATH, platform,
            )
        return PackageApiFetchResult(
            outcome=PackageApiOutcome.DRY_RUN,
            attempted=False,
            packages=[],
            paging_truncated=False,
            reason="Dry run: skipped Package Management API HTTP call.",
        )

    try:
        token = _get_token(ctx, GRAPH_SCOPE)
    except Exception as exc:
        return PackageApiFetchResult(
            outcome=PackageApiOutcome.TRANSPORT_FAILURE,
            attempted=True,
            paging_truncated=True,
            error_code="TokenAcquisitionFailed",
            error_subcode=_sanitize_code(type(exc).__name__),
            reason="Package API token acquisition failed.",
        )

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }
    all_packages: list[dict] = []

    for platform in PACKAGE_API_PLATFORMS:
        url: Optional[str] = (
            f"{GRAPH_API_BASE}{PACKAGE_API_PATH}"
            f"?$filter=platform eq '{platform}'"
        )
        while url:
            try:
                resp = _request_with_backoff(session, "GET", url, headers=headers)
            except ThrottlingExhaustedError:
                return PackageApiFetchResult(
                    outcome=PackageApiOutcome.HTTP_429,
                    attempted=True,
                    packages=all_packages,
                    paging_truncated=True,
                    http_status=429,
                    error_code="TooManyRequests",
                    reason="Package API throttled (HTTP 429).",
                )
            except requests.exceptions.RequestException as exc:
                return PackageApiFetchResult(
                    outcome=PackageApiOutcome.TRANSPORT_FAILURE,
                    attempted=True,
                    packages=all_packages,
                    paging_truncated=True,
                    error_code="TransportFailure",
                    error_subcode=_sanitize_code(type(exc).__name__),
                    reason="Package API transport failure.",
                )

            payload: Any
            try:
                payload = resp.json()
            except ValueError:
                return PackageApiFetchResult(
                    outcome=PackageApiOutcome.PARSE_FAILURE,
                    attempted=True,
                    packages=all_packages,
                    paging_truncated=True,
                    http_status=resp.status_code,
                    error_code="ParseFailure",
                    reason="Package API returned malformed JSON.",
                )
            if not isinstance(payload, dict):
                return PackageApiFetchResult(
                    outcome=PackageApiOutcome.PARSE_FAILURE,
                    attempted=True,
                    packages=all_packages,
                    paging_truncated=True,
                    http_status=resp.status_code,
                    error_code="MalformedResponse",
                    reason="Package API response must be a JSON object.",
                )

            if resp.status_code != 200:
                graph_code, graph_subcode = _extract_graph_error_fields(payload)
                outcome = _package_outcome_from_http_status(resp.status_code)
                reason = "Package API request failed."
                if outcome == PackageApiOutcome.HTTP_401:
                    reason = "Package API unauthorized (HTTP 401)."
                elif outcome == PackageApiOutcome.HTTP_403:
                    reason = (
                        "Package API forbidden (HTTP 403). "
                        "CopilotPackages.Read.All is required."
                    )
                elif outcome == PackageApiOutcome.HTTP_404_UNSUPPORTED:
                    reason = "Package API unsupported or unavailable (HTTP 404)."
                elif outcome == PackageApiOutcome.HTTP_429:
                    reason = "Package API throttled (HTTP 429)."
                elif outcome == PackageApiOutcome.HTTP_5XX:
                    reason = "Package API server failure (HTTP 5xx)."
                return PackageApiFetchResult(
                    outcome=outcome,
                    attempted=True,
                    packages=all_packages,
                    paging_truncated=True,
                    http_status=resp.status_code,
                    error_code=graph_code or f"Http{resp.status_code}",
                    error_subcode=graph_subcode,
                    reason=reason,
                )

            page_items = payload.get("value", [])
            if not isinstance(page_items, list):
                return PackageApiFetchResult(
                    outcome=PackageApiOutcome.PARSE_FAILURE,
                    attempted=True,
                    packages=all_packages,
                    paging_truncated=True,
                    http_status=200,
                    error_code="MalformedResponse",
                    reason="Package API response missing a list 'value' property.",
                )
            all_packages.extend(page_items)
            url = payload.get("@odata.nextLink")

    logger.info(
        "Package Management API: %d packages across %d platform(s)",
        len(all_packages), len(PACKAGE_API_PLATFORMS),
    )
    return PackageApiFetchResult(
        outcome=(
            PackageApiOutcome.SUCCESS_DATA
            if all_packages
            else PackageApiOutcome.SUCCESS_EMPTY
        ),
        attempted=True,
        packages=all_packages,
        paging_truncated=False,
        http_status=200,
    )


def fetch_package_catalog(
    ctx: ScanContext, session: requests.Session
) -> tuple[list[dict], bool]:
    """Backward-compatible package fetch wrapper.

    Returns only (packages, paging_was_truncated). Use
    fetch_package_catalog_details() for typed status metadata.
    """
    details = fetch_package_catalog_details(ctx, session)
    return details.packages, details.paging_truncated


def _package_layer_status(fetch: PackageApiFetchResult) -> str:
    """Map typed Package API outcomes to coverage layer status."""
    if fetch.outcome == PackageApiOutcome.DRY_RUN:
        return LAYER_STATUS_DRY_RUN
    if fetch.outcome in (PackageApiOutcome.SUCCESS_EMPTY, PackageApiOutcome.SUCCESS_DATA):
        return LAYER_STATUS_FULL
    if fetch.outcome == PackageApiOutcome.HTTP_404_UNSUPPORTED:
        return LAYER_STATUS_UNSUPPORTED
    if fetch.outcome == PackageApiOutcome.DEFERRED:
        return LAYER_STATUS_DEFERRED
    if fetch.paging_truncated and fetch.packages:
        return LAYER_STATUS_PARTIAL
    if fetch.outcome == PackageApiOutcome.PAGING_TRUNCATED:
        return LAYER_STATUS_PARTIAL
    return LAYER_STATUS_FAILED


def reconcile_package_catalog(
    ctx: ScanContext,
    packages: list[dict],
    existing_agents: list[dict],
    truncated: bool = False,
) -> tuple[list[dict], list[dict]]:
    """Reconcile Package API packages against existing bot-GUID agent rows.

    Best-effort join order:
      1. package.appId      == existing.fsi_entraappid
      2. package.manifestId == existing.fsi_manifestid

    MATCH -> Enrich the existing row in-place: set fsi_packageid + package
             fields + fsi_discoverysource. fsi_agentid stays as the bot GUID
             (id space is preserved). Re-classifies scan completeness — the
             fsi_packageid now present may upgrade an Agent Builder row from
             Incomplete Scan to Complete.

    NO MATCH -> Create a new standalone row: fsi_agentid = package id (P_...),
                fsi_ownermatchconfidence = "Unmatched".

    When truncated=True (Package API paging was cut short), EVERY package-touched
    row (enriched existing rows AND new standalone rows) is marked
    fsi_scancompleteness="Incomplete Scan" with _PACKAGE_TRUNCATION_REASON.  ARG-only and
    Dataverse-only rows are never modified by this function.

    Returns (existing_agents, new_package_only_rows).
    The caller appends new_package_only_rows to the final agent set; the
    existing_agents list is enriched in-place (no duplication).
    """
    # Build lookup maps over existing rows (skip empty/None values).
    by_app_id: dict[str, dict] = {}
    by_manifest_id: dict[str, dict] = {}
    for agent in existing_agents:
        app_id = str(agent.get("fsi_entraappid") or "").strip()
        if app_id:
            by_app_id[app_id] = agent
        manifest_id = str(agent.get("fsi_manifestid") or "").strip()
        if manifest_id:
            by_manifest_id[manifest_id] = agent

    new_rows: list[dict] = []
    enriched_ids: set = set()
    for pkg in packages:
        pkg_app_id = str(pkg.get("appId") or "").strip()
        pkg_manifest_id = str(pkg.get("manifestId") or "").strip()
        matched = (
            (by_app_id.get(pkg_app_id) if pkg_app_id else None)
            or (by_manifest_id.get(pkg_manifest_id) if pkg_manifest_id else None)
        )
        if matched:
            # Enrich without duplicating: merge package fields into existing row.
            matched.update(_package_fields(ctx, pkg))
            # Preserve multi-source provenance: an existing ARG/Dataverse row
            # enriched with package data is "Reconciled (multi-source)", NOT
            # "Package Management API" — overwriting the original source label
            # would destroy provenance.
            matched["fsi_discoverysource"] = DISCOVERY_SOURCE_RECONCILED
            enriched_ids.add(id(matched))
            if truncated:
                matched["fsi_scancompleteness"] = "Incomplete Scan"
                matched["fsi_scancompletenessreason"] = _PACKAGE_TRUNCATION_REASON
            else:
                completeness, reason = classify_scan_completeness(matched)
                matched["fsi_scancompleteness"] = completeness
                matched["fsi_scancompletenessreason"] = reason
            logger.debug(
                "Package %s enriched existing agent row "
                "(fsi_agentid=%s, truncated=%s, new_completeness=%s)",
                pkg.get("id"), matched.get("fsi_agentid"),
                truncated, matched["fsi_scancompleteness"],
            )
        else:
            new_row = map_package_record(ctx, pkg)
            if truncated:
                new_row["fsi_scancompleteness"] = "Incomplete Scan"
                new_row["fsi_scancompletenessreason"] = _PACKAGE_TRUNCATION_REASON
            new_rows.append(new_row)
            logger.debug(
                "Package %s: no bot-GUID match; standalone row created "
                "(fsi_agentid=%s, fsi_ownermatchconfidence=Unmatched, truncated=%s)",
                pkg.get("id"), pkg.get("id"), truncated,
            )

    logger.info(
        "Package reconciliation: %d enriched existing rows, %d new standalone rows "
        "(truncated=%s)",
        len(enriched_ids), len(new_rows), truncated,
    )
    return existing_agents, new_rows


# =============================================================================
# Orchestration
# =============================================================================


def _normalize_agent_name(name: str) -> str:
    """Collapse whitespace and lowercase an agent display name for exact-match joins.

    Used only for the LAST-RESORT name join in registry correlation — ambiguous
    normalised names (two or more candidates) are always skipped, never guessed.
    """
    return " ".join(name.split()).lower()


def _validate_as_of(value: str) -> str:
    """Validate and normalise an ISO-8601 UTC datetime string.

    Accepts a 'Z' suffix or an explicit UTC offset (e.g. +05:00).
    Rejects naive (timezone-less) values — UTC 'Z' or an explicit offset is
    required, matching the strict behaviour of import_registry_export._parse_iso8601_utc.

    Returns the canonical 'YYYY-MM-DDTHH:MM:SSZ' form.
    Raises ValueError on invalid format or absent timezone.
    """
    s = value.strip()
    # Normalise 'Z' suffix to '+00:00' for fromisoformat() on Python 3.7-3.10.
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        raise ValueError(
            f"Invalid ISO-8601 datetime: {value!r}. "
            "Expected UTC, e.g. '2026-07-20T18:00:00Z'."
        )
    if dt.tzinfo is None:
        raise ValueError(
            f"Datetime {value!r} has no timezone — UTC is required (append 'Z')."
        )
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _apply_registry_owner(
    agent: dict, reg_row: dict, as_of: Optional[str]
) -> None:
    """Enrich an agent row with owner attribution from a registry export row.

    Owner is NEVER set from creator/display-name fields.
    fsi_discoverysource is intentionally NOT modified (preserves API provenance).
    """
    # fsi_ownerupn: only copy if the importer set it (it already enforced '@').
    if "fsi_ownerupn" in reg_row:
        agent["fsi_ownerupn"] = reg_row["fsi_ownerupn"]
    if "fsi_ownerid" in reg_row:
        agent["fsi_ownerid"] = reg_row["fsi_ownerid"]
    if "fsi_createdon" in reg_row:
        agent["fsi_createdon"] = reg_row["fsi_createdon"]
    # Use the confidence already computed by the importer.
    agent["fsi_ownersource"] = "Agent Registry Export"
    agent["fsi_ownermatchconfidence"] = reg_row.get(
        "fsi_ownermatchconfidence", "Unmatched"
    )
    if as_of:
        agent["fsi_ownerasofdatetime"] = as_of
    # fsi_discoverysource intentionally NOT modified here.


def scan_all(ctx: ScanContext) -> dict:
    """Run the discovery layers and return the canonical record set.

    ARG + Dataverse remain load-bearing. Agent 365 Package API behavior is
    license-aware and controlled by ctx.agent365_requested_mode.
    """
    session = _build_session()
    logger.info("Scan run %s (dry_run=%s, max_workers=%d)",
                ctx.run_id, ctx.dry_run, ctx.max_workers)

    # Layer 1 — ARG. Track a distinct layer status so a failed query is never
    # mistaken for an observed zero-agent tenant: unavailable / failed / zero are
    # each separately representable in the summary (argLayer.status).
    arg_agents: list[dict] = []
    arg_layer_status = "Disabled"    # --no-arg
    arg_query_http: Optional[int] = None
    if ctx.use_arg:
        arg_layer_status = "Unavailable"
        if probe_arg_resource_type(ctx, session):
            try:
                arg_agents = [
                    map_agent_record(ctx, item, DISCOVERY_SOURCE_ARG)
                    for item in query_arg_inventory(ctx, session)
                ]
                arg_layer_status = "Available"
            except ThrottlingExhaustedError as exc:
                # ARG throttled to exhaustion: discard the partial (and therefore
                # misleading) ARG results and rely on the Layer 2 per-environment
                # scan instead of aborting the run (L-3). Recorded as Failed, NOT
                # as an observed zero.
                logger.warning("ARG layer throttled to exhaustion; discarding "
                               "partial ARG results and falling back to Layer 2: "
                               "%s", exc)
                arg_agents = []
                arg_layer_status = "Failed"
            except ArgQueryError as exc:
                logger.warning("ARG query failed (HTTP %s); falling back to Layer 2. "
                               "The ARG layer is Failed, not an observed zero.",
                               exc.http_status)
                arg_agents = []
                arg_layer_status = "Failed"
                arg_query_http = exc.http_status
            except requests.exceptions.RequestException as exc:
                logger.warning("ARG query transport error; falling back to "
                               "Layer 2: %s", exc)
                arg_agents = []
                arg_layer_status = "Failed"
        else:
            logger.info("ARG path unavailable — using Layer 2 per-environment scan "
                        "as the load-bearing default.")

    # Layer 2 — per-environment enumeration + scan. Enumeration failure is an
    # explicit, non-success outcome: a 401/403/5xx or malformed environment list
    # must never look like a genuinely empty tenant. A real HTTP 200 with an
    # empty list is a genuine (representable) empty result.
    enumeration_failed = False
    enumeration_http: Optional[int] = None
    enumeration_reason = ""
    try:
        environments = enumerate_environments(ctx, session)
    except (EnvironmentEnumerationError, ThrottlingExhaustedError,
            requests.exceptions.RequestException) as exc:
        enumeration_failed = True
        enumeration_http = getattr(exc, "http_status", None)
        enumeration_reason = _sanitize_reason(exc)
        environments = []
        logger.error("Environment enumeration FAILED (HTTP %s): %s — the scan is "
                     "marked Failed, NOT a clean empty tenant.",
                     enumeration_http, exc)

    scanned_agents: list[dict] = []
    features: list[dict] = []
    auth_shares: list[dict] = []
    env_failures: list[dict] = []
    env_statuses: list[str] = []

    # Power Platform can return environments that explicitly have no Dataverse
    # database. Layer 2 does not apply to those environments; they remain part of
    # the enumeration count but are not submitted as malformed relative URLs.
    scan_environments = [
        environment
        for environment in environments
        if not _environment_has_no_dataverse(environment)
    ]
    skipped_no_dataverse = len(environments) - len(scan_environments)
    if skipped_no_dataverse:
        logger.info(
            "Skipping %d environment(s) explicitly classified without Dataverse; "
            "Layer 2 is not applicable to them.",
            skipped_no_dataverse,
        )

    # Throttled concurrent per-environment fan-out (~10 workers, 429 backoff).
    with ThreadPoolExecutor(max_workers=ctx.max_workers) as pool:
        futures = {
            pool.submit(_scan_one_environment, ctx, session, env): env
            for env in scan_environments
        }
        for future in as_completed(futures):
            outcome = future.result()
            scanned_agents.extend(outcome["agents"])
            features.extend(outcome["features"])
            auth_shares.extend(outcome.get("authShares", []))
            env_failures.extend(outcome.get("failures", []))
            env_statuses.append(outcome.get("status", "Complete"))

    (
        agent365_resolved_state,
        agent365_resolution_source,
        agent365_detection_confidence,
        sku_probe,
    ) = _resolve_agent365_state(ctx, session)

    package_new_rows: list[dict] = []
    package_fetch = PackageApiFetchResult(
        outcome=PackageApiOutcome.DEFERRED,
        attempted=False,
        packages=[],
        paging_truncated=False,
        reason="Package API deferred for the requested Agent 365 mode.",
    )
    if agent365_resolved_state in {AGENT365_STATE_PRESENT, AGENT365_STATE_INCONCLUSIVE}:
        primary_agents = arg_agents if arg_agents else scanned_agents
        package_fetch = fetch_package_catalog_details(ctx, session)
        _, package_new_rows = reconcile_package_catalog(
            ctx,
            package_fetch.packages,
            primary_agents,
            truncated=package_fetch.paging_truncated,
        )
        if package_fetch.paging_truncated:
            logger.warning(
                "Package Management API paging was truncated; "
                "package-layer discovery is INCOMPLETE."
            )

    package_layer_status = _package_layer_status(package_fetch)

    reconciliation = reconcile_sources(arg_agents, scanned_agents)

    # Build final_agents before the optional post-processing steps so registry
    # correlation and entitlement resolution can operate on the complete set.
    final_agents = list(arg_agents or scanned_agents)
    final_agents.extend(package_new_rows)

    # Derive the overall scan status/completeness. Enumeration and per-environment
    # failures degrade the overall status so a partial or authorization-blocked
    # scan is never indistinguishable from a clean, complete one.
    if enumeration_failed:
        overall_status = "Failed"
    elif env_statuses and all(s == "Failed" for s in env_statuses):
        overall_status = "Failed"
    elif (any(s in ("Failed", "Incomplete") for s in env_statuses)
          or arg_layer_status == "Failed"):
        overall_status = "Incomplete"
    else:
        overall_status = "Complete"

    if package_layer_status in {LAYER_STATUS_FAILED, LAYER_STATUS_UNSUPPORTED}:
        if ctx.agent365_requested_mode == AGENT365_MODE_PRESENT:
            overall_status = "Failed"
        elif overall_status != "Failed":
            overall_status = "Incomplete"
    elif package_layer_status == LAYER_STATUS_PARTIAL and overall_status == "Complete":
        overall_status = "Incomplete"

    if (
        ctx.agent365_requested_mode == AGENT365_MODE_AUTO
        and agent365_resolved_state == AGENT365_STATE_INCONCLUSIVE
        and not ctx.dry_run
        and overall_status == "Complete"
    ):
        overall_status = "Incomplete"
    if ctx.dry_run:
        overall_status = "Dry Run"

    if enumeration_failed:
        enumeration_status = "Failed"
    elif ctx.dry_run:
        enumeration_status = "Dry Run"
    else:
        enumeration_status = "Success"

    agent365_http_status = package_fetch.http_status or sku_probe.http_status
    agent365_error_code = package_fetch.error_code or sku_probe.error_code
    agent365_error_subcode = package_fetch.error_subcode or sku_probe.error_subcode
    agent365_reason = package_fetch.reason or sku_probe.reason
    if (
        ctx.agent365_requested_mode == AGENT365_MODE_AUTO
        and agent365_resolved_state == AGENT365_STATE_NOT_DETECTED
    ):
        agent365_reason = (
            "No heuristic Agent 365 name aliases detected; this is non-authoritative. "
            "Manual verification or --agent365 present override is recommended."
        )
    packages_observed: Optional[int] = (
        len(package_fetch.packages) if package_fetch.attempted else None
    )
    package_new_row_count: Optional[int] = (
        len(package_new_rows) if package_fetch.attempted else None
    )
    requested_mode_label = AGENT365_MODE_CHOICE_LABELS.get(
        ctx.agent365_requested_mode,
        AGENT365_MODE_CHOICE_LABELS[DEFAULT_AGENT365_MODE],
    )

    summary: dict = {
        "runId": ctx.run_id,
        "status": overall_status,
        "argAgentCount": len(arg_agents),
        "scannedAgentCount": len(scanned_agents),
        "coreAgentCount": len(final_agents),
        "featureCount": len(features),
        "authShareCount": len(auth_shares),
        "environmentCount": len(environments),
        "environmentEnumeration": {
            "status": enumeration_status,
            "environmentCount": len(environments),
            "dataverseEnvironmentCount": len(scan_environments),
            "skippedNoDataverseCount": skipped_no_dataverse,
            "httpStatus": enumeration_http,
            "reason": enumeration_reason,
        },
        "argLayer": {
            "status": arg_layer_status,
            "agentCount": len(arg_agents),
            "httpStatus": arg_query_http,
        },
        "agent365": {
            "requestedMode": requested_mode_label,
            "resolvedState": agent365_resolved_state,
            "resolutionSource": agent365_resolution_source,
            "detectionConfidence": agent365_detection_confidence,
            "licenseProbeAttempted": sku_probe.attempted,
            "packageApiAttempted": package_fetch.attempted,
            "layerStatus": package_layer_status,
            "httpStatus": agent365_http_status,
            "errorCode": _sanitize_code(agent365_error_code),
            "errorSubcode": _sanitize_code(agent365_error_subcode),
            "reason": _sanitize_reason(agent365_reason),
            "packagesObserved": packages_observed,
            "packageNewRowCount": package_new_row_count,
            "pagingTruncated": bool(package_fetch.paging_truncated),
        },
        "environmentFailures": env_failures,
        "reconciliation": reconciliation,
    }
    if package_fetch.attempted:
        summary["packageNewRowCount"] = len(package_new_rows)
        summary["packageScanTruncated"] = bool(package_fetch.paging_truncated)

    # -------------------------------------------------------------------------
    # Step 5 — Registry correlation (optional; only when --registry-export set).
    # Enriches Agent Builder / package-sourced rows only.  Unmatched registry
    # rows are counted but never create orphan fsi_copilotagent rows.
    # fsi_discoverysource is never overwritten (API provenance is preserved).
    # -------------------------------------------------------------------------
    if ctx.registry_export_path:
        import import_registry_export as _reg  # type: ignore[import]  # noqa: PLC0415

        _registry_rows: list[dict] = []
        _import_warnings: list[str] = []
        _reg_status = "Complete"
        _matched_count = 0
        _unmatched_registry = 0
        _ambiguous_name_skipped = 0

        try:
            _cm_path = Path(
                ctx.columnmap_path
                or str(
                    Path(__file__).parent.parent
                    / "templates"
                    / "registry-columnmap.sample.json"
                )
            )
            _aliases, _required, _sheet = _reg.load_columnmap(_cm_path)
            _registry_rows, _import_warnings = _reg.import_registry_file(
                path=ctx.registry_export_path,
                aliases=_aliases,
                required_fields=_required,
                sheet_name=_sheet,
                as_of=ctx.as_of,
            )

            # Candidate rows: Agent Builder agents or rows already carrying package data.
            _candidates = [
                a for a in final_agents
                if a.get("fsi_packageid")
                or a.get("fsi_createdin") == CREATED_IN_AGENT_BUILDER
            ]

            # Build stable-key lookup maps over candidates.
            _by_agent_id: dict[str, dict] = {}
            _by_pkg_id: dict[str, dict] = {}
            _by_app_id: dict[str, dict] = {}
            _by_manifest_id: dict[str, dict] = {}
            _by_norm_name: dict[str, list] = {}
            for _ca in _candidates:
                _aid = str(_ca.get("fsi_agentid") or "").strip()
                if _aid:
                    _by_agent_id[_aid] = _ca
                _pid = str(_ca.get("fsi_packageid") or "").strip()
                if _pid:
                    _by_pkg_id[_pid] = _ca
                _appid = str(_ca.get("fsi_entraappid") or "").strip()
                if _appid:
                    _by_app_id[_appid] = _ca
                _mid = str(_ca.get("fsi_manifestid") or "").strip()
                if _mid:
                    _by_manifest_id[_mid] = _ca
                _nm = _normalize_agent_name(str(_ca.get("fsi_agentname") or ""))
                if _nm:
                    _by_norm_name.setdefault(_nm, []).append(_ca)

            for _rr in _registry_rows:
                _hit: Optional[dict] = None

                # (a) Stable agent id — strongest key.
                _r_aid = str(_rr.get("fsi_agentid") or "").strip()
                if _r_aid:
                    _hit = _by_agent_id.get(_r_aid)

                # (b) Package / app / manifest id (only if present in this export row).
                if _hit is None:
                    _r_pid = str(_rr.get("fsi_packageid") or "").strip()
                    if _r_pid:
                        _hit = _by_pkg_id.get(_r_pid)

                if _hit is None:
                    _r_appid = str(_rr.get("fsi_entraappid") or "").strip()
                    if _r_appid:
                        _hit = _by_app_id.get(_r_appid)

                if _hit is None:
                    _r_mid = str(_rr.get("fsi_manifestid") or "").strip()
                    if _r_mid:
                        _hit = _by_manifest_id.get(_r_mid)

                # (c) LAST-RESORT: exact normalised name — only when EXACTLY ONE
                # candidate matches.  Two or more candidates → skip + count.
                if _hit is None:
                    _r_nm = _normalize_agent_name(
                        str(_rr.get("fsi_agentname") or "")
                    )
                    if _r_nm:
                        _nm_cands = _by_norm_name.get(_r_nm, [])
                        if len(_nm_cands) == 1:
                            _hit = _nm_cands[0]
                        elif len(_nm_cands) > 1:
                            _ambiguous_name_skipped += 1
                            logger.debug(
                                "Registry correlation: ambiguous name %r matches "
                                "%d candidates; skipping (never guess).",
                                _r_nm, len(_nm_cands),
                            )

                if _hit is not None:
                    _apply_registry_owner(_hit, _rr, ctx.as_of)
                    _matched_count += 1
                else:
                    _unmatched_registry += 1
                    logger.debug(
                        "Registry row unmatched (agent_id=%r, name=%r); "
                        "no orphan row created.",
                        _rr.get("fsi_agentid"), _rr.get("fsi_agentname"),
                    )

            if _import_warnings:
                _reg_status = "Incomplete"

        except Exception as _reg_exc:
            logger.error(
                "Registry correlation failed: %s — continuing scan (zero matches).",
                _reg_exc,
            )
            _reg_status = "Failed"

        summary["registryCorrelation"] = {
            "registryRowCount": len(_registry_rows),
            "matched": _matched_count,
            "unmatchedRegistryRows": _unmatched_registry,
            "ambiguousNameSkipped": _ambiguous_name_skipped,
            "invalidDateWarnings": len(_import_warnings),
            "status": _reg_status,
        }

    # -------------------------------------------------------------------------
    # Step 6 — Entitlement resolution (optional; requires correlation to have run).
    # Builds an ordered unique UPN list from agents with UPN-shaped owners and
    # zip-joins results back deterministically.  No UPN appears in evidence.
    # -------------------------------------------------------------------------
    if ctx.resolve_entitlement and ctx.registry_export_path:
        import resolve_owner_entitlement as _ent  # type: ignore[import]  # noqa: PLC0415

        # Build ordered unique UPN list (UPN-shaped means contains '@').
        _eligible_upns: list[str] = []
        _seen_upns_lc: set[str] = set()
        for _ea in final_agents:
            _upn = str(_ea.get("fsi_ownerupn") or "").strip()
            if "@" in _upn and _upn.lower() not in _seen_upns_lc:
                _seen_upns_lc.add(_upn.lower())
                _eligible_upns.append(_upn)

        _ent_paid = _ent_chat = _ent_unknown = 0
        _ent_status = "Complete"

        if ctx.dry_run:
            # Dry-run: skip Graph token acquisition and pwsh subprocess entirely.
            logger.info(
                "[DRY RUN] Step 6 entitlement resolution skipped "
                "(%d eligible UPN(s)); no Graph call or pwsh invocation made.",
                len(_eligible_upns),
            )
            summary["entitlementResolution"] = {
                "ownersConsidered": len(_eligible_upns),
                "paidCount": 0,
                "chatOnlyCount": 0,
                "unknownCount": 0,
                "status": "Skipped (dry-run)",
            }
        else:
            try:
                _graph_token = _get_token(ctx, GRAPH_SCOPE)
                _ps1_path = Path(
                    ctx.entitlement_ps1_path
                    or str(
                        Path(__file__).parent.parent.parent
                        / "copilot-billing-governance"
                        / "scripts"
                        / "Get-CopilotEntitlement.ps1"
                    )
                )
                _ent_results, _invocation_failed = _ent.resolve_entitlements(
                    upns=_eligible_upns,
                    ps1_path=_ps1_path,
                    graph_token=_graph_token,
                    work_dir=Path(__file__).parent,
                    run_id=ctx.run_id,
                )
                # Subprocess-level failure: PS1 could not run or exited non-zero.
                # Results are all-Unknown (fail-open); status must reflect the failure
                # so callers distinguish "ran; genuine Unknown" from "resolver crashed".
                if _invocation_failed:
                    _ent_status = "Failed"

                # Deterministic zip join-back — no UPN written to evidence.
                _upn_to_result = {
                    _u.lower(): _r
                    for _u, _r in zip(_eligible_upns, _ent_results)
                }
                for _ea in final_agents:
                    _upn_lc = str(_ea.get("fsi_ownerupn") or "").strip().lower()
                    if _upn_lc in _upn_to_result:
                        _er = _upn_to_result[_upn_lc]
                        _ea["fsi_ownerentitlement"] = _er["fsi_ownerentitlement"]
                        _ea["fsi_ownerentitlementevidence"] = (
                            _er["fsi_ownerentitlementevidence"]
                        )

                _ent_paid = sum(
                    1 for _r in _ent_results
                    if _r.get("fsi_ownerentitlement") == "Paid Copilot"
                )
                _ent_chat = sum(
                    1 for _r in _ent_results
                    if _r.get("fsi_ownerentitlement") == "Copilot Chat Only"
                )
                _ent_unknown = sum(
                    1 for _r in _ent_results
                    if _r.get("fsi_ownerentitlement") == "Unknown"
                )

            except Exception as _ent_exc:
                logger.error(
                    "Entitlement resolution failed: %s — all %d UPN(s) set to Unknown.",
                    _ent_exc, len(_eligible_upns),
                )
                _ent_status = "Failed"
                _ent_unknown = len(_eligible_upns)
                for _ea in final_agents:
                    _upn_lc = str(_ea.get("fsi_ownerupn") or "").strip().lower()
                    if _upn_lc in _seen_upns_lc:
                        _ea["fsi_ownerentitlement"] = "Unknown"
                        _ea["fsi_ownerentitlementevidence"] = "[]"

            summary["entitlementResolution"] = {
                "ownersConsidered": len(_eligible_upns),
                "paidCount": _ent_paid,
                "chatOnlyCount": _ent_chat,
                "unknownCount": _ent_unknown,
                "status": _ent_status,
            }

    if not ctx.use_arg:
        arg_scope_status = LAYER_STATUS_DEFERRED
    elif ctx.dry_run:
        arg_scope_status = LAYER_STATUS_DRY_RUN
    elif arg_layer_status == "Available":
        arg_scope_status = LAYER_STATUS_FULL
    elif arg_layer_status == "Unavailable":
        arg_scope_status = LAYER_STATUS_UNSUPPORTED
    else:
        arg_scope_status = LAYER_STATUS_FAILED

    if ctx.dry_run:
        env_scope_status = LAYER_STATUS_DRY_RUN
    elif enumeration_failed or (env_statuses and all(s == "Failed" for s in env_statuses)):
        env_scope_status = LAYER_STATUS_FAILED
    elif any(s in ("Failed", "Incomplete") for s in env_statuses):
        env_scope_status = LAYER_STATUS_PARTIAL
    else:
        env_scope_status = LAYER_STATUS_FULL

    if not ctx.registry_export_path:
        registry_scope_status = LAYER_STATUS_DEFERRED
    else:
        reg_status = str(summary.get("registryCorrelation", {}).get("status") or "")
        registry_scope_status = (
            LAYER_STATUS_FULL
            if reg_status == "Complete"
            else LAYER_STATUS_PARTIAL
            if reg_status == "Incomplete"
            else LAYER_STATUS_FAILED
        )

    if not ctx.resolve_entitlement:
        entitlement_scope_status = LAYER_STATUS_DEFERRED
    else:
        ent_status = str(summary.get("entitlementResolution", {}).get("status") or "")
        if ent_status == "Skipped (dry-run)":
            entitlement_scope_status = LAYER_STATUS_DRY_RUN
        elif ent_status == "Complete":
            entitlement_scope_status = LAYER_STATUS_FULL
        elif ent_status == "Failed":
            entitlement_scope_status = LAYER_STATUS_FAILED
        else:
            entitlement_scope_status = LAYER_STATUS_PARTIAL

    authoritative_for = [
        "Copilot Studio inventory from ARG and per-environment Dataverse layers."
    ]
    if package_layer_status == LAYER_STATUS_FULL:
        authoritative_for.append(
            "Agent Builder package catalog from the Microsoft Graph Package API."
        )

    limitations = [
        "Deferred or NotDetected Agent 365 state is not an authoritative Agent Builder catalog."
    ]
    if package_layer_status in {LAYER_STATUS_PARTIAL, LAYER_STATUS_FAILED, LAYER_STATUS_UNSUPPORTED}:
        limitations.append(
            "Package API layer was not fully successful; review summary.agent365 before treating Agent Builder coverage as complete."
        )
    if sku_probe.http_status in {401, 403}:
        limitations.append(
            "Agent 365 license probe permission guidance: "
            f"{SUBSCRIBED_SKUS_PERMISSION_GUIDANCE}"
        )

    summary["coverageScope"] = {
        "layers": {
            "arg": arg_scope_status,
            "environmentDataverse": env_scope_status,
            "packageApi": package_layer_status,
            "registry": registry_scope_status,
            "entitlement": entitlement_scope_status,
        },
        "authoritativeFor": authoritative_for,
        "limitations": limitations,
        "warning": "Deferred/NotDetected is not an authoritative Agent Builder catalog.",
    }

    logger.info("Scan summary: %s", json.dumps(summary, default=str))
    return {
        "summary": summary,
        "agents": final_agents,
        "features": features,
        "authShares": auth_shares,
    }


# =============================================================================
# CLI Entry Point
# =============================================================================


def _resolve_requested_agent365_mode(
    args: argparse.Namespace,
    parser: argparse.ArgumentParser,
) -> tuple[str, str, tuple[str, ...]]:
    """Resolve requested Agent 365 mode with precedence + contradiction checks."""
    cli_mode = args.agent365
    env_raw = os.environ.get("CAI_AGENT365")
    env_mode: Optional[str] = None
    if env_raw and env_raw.strip():
        env_mode = env_raw.strip().lower()
        if env_mode not in AGENT365_MODES:
            parser.error(
                f"CAI_AGENT365 must be one of {', '.join(AGENT365_MODES)}; got {env_raw!r}."
            )

    alias_requested = bool(args.enable_package_api)
    if cli_mode and env_mode and cli_mode != env_mode:
        parser.error(
            f"Conflicting Agent 365 modes: --agent365 {cli_mode} and CAI_AGENT365={env_mode}."
        )
    if alias_requested and cli_mode and cli_mode != AGENT365_MODE_PRESENT:
        parser.error(
            "--enable-package-api is a deprecated alias for '--agent365 present' and "
            "cannot be combined with '--agent365 absent|auto'."
        )
    if alias_requested and not cli_mode and env_mode and env_mode != AGENT365_MODE_PRESENT:
        parser.error(
            "--enable-package-api (present) conflicts with CAI_AGENT365="
            f"{env_mode}. Use only one mode declaration."
        )

    if cli_mode:
        requested_mode = cli_mode
        resolution_source = "CLI"
    elif env_mode:
        requested_mode = env_mode
        resolution_source = "Environment"
    elif alias_requested:
        requested_mode = AGENT365_MODE_PRESENT
        resolution_source = "DeprecatedAlias"
    else:
        requested_mode = DEFAULT_AGENT365_MODE
        resolution_source = "Default"

    if alias_requested:
        logger.warning(
            "DEPRECATED: --enable-package-api is retained for one release and maps to "
            "--agent365 present. Use --agent365 present explicitly."
        )

    overrides = _parse_agent365_alias_overrides(_get_agent365_alias_override_raw())
    return requested_mode, resolution_source, overrides


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
            "    --tenant-id <tenant> --output scan.json\n\n"
            "  # Full integrated scan with registry correlation + entitlement\n"
            "  python discover_agents.py --agent365 present \\\n"
            "    --registry-export export.xlsx \\\n"
            "    --columnmap templates/registry-columnmap.sample.json \\\n"
            "    --as-of 2026-07-20T18:00:00Z \\\n"
            "    --resolve-entitlement --output scan.json\n"
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
    parser.add_argument(
        "--agent365",
        choices=list(AGENT365_MODES),
        default=None,
        help=(
            "Agent 365 mode: present | absent | auto. "
            "Precedence: explicit CLI > CAI_AGENT365 > --enable-package-api alias > default absent."
        ),
    )
    parser.add_argument(
        "--enable-package-api",
        action="store_true",
        default=False,
        help=(
            "DEPRECATED one-release alias for '--agent365 present'. "
            "Use --agent365 present instead."
        ),
    )
    # Registry correlation flags (D).
    parser.add_argument(
        "--registry-export",
        default=None,
        metavar="PATH",
        help=(
            "Path to the agent registry export file (.xlsx or .csv). "
            "When set, enriches Agent Builder / package rows with owner attribution "
            "from the export.  Unmatched export rows are counted; no orphan rows created."
        ),
    )
    parser.add_argument(
        "--columnmap",
        default=str(
            Path(__file__).parent.parent / "templates" / "registry-columnmap.sample.json"
        ),
        metavar="PATH",
        help=(
            "Path to the column-map JSON for the registry export. "
            "Default: templates/registry-columnmap.sample.json"
        ),
    )
    parser.add_argument(
        "--as-of",
        default=None,
        metavar="ISO8601",
        help=(
            "ISO-8601 UTC datetime when the registry export was produced "
            "(e.g., 2026-07-20T18:00:00Z). Stamped as fsi_ownerasofdatetime. "
            "Invalid values are rejected."
        ),
    )
    parser.add_argument(
        "--resolve-entitlement",
        action="store_true",
        default=False,
        help=(
            "After registry correlation, resolve Copilot license entitlement for "
            "each matched owner UPN via Get-CopilotEntitlement.ps1. "
            "Requires --registry-export."
        ),
    )
    parser.add_argument(
        "--entitlement-ps1-path",
        default=str(
            Path(__file__).parent.parent.parent
            / "copilot-billing-governance"
            / "scripts"
            / "Get-CopilotEntitlement.ps1"
        ),
        metavar="PATH",
        help=(
            "Path to Get-CopilotEntitlement.ps1. "
            "Default: ../../copilot-billing-governance/scripts/Get-CopilotEntitlement.ps1"
        ),
    )
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

    # --resolve-entitlement has no owner source without a registry export, so it
    # would otherwise perform no entitlement work silently. Fail fast.
    if args.resolve_entitlement and not args.registry_export:
        parser.error("--resolve-entitlement requires --registry-export: owner "
                     "entitlement is resolved only for owners attributed by the "
                     "registry correlation step. Provide --registry-export (and, "
                     "if needed, --columnmap / --as-of), or drop "
                     "--resolve-entitlement.")

    # Validate --as-of before constructing the context.
    as_of_validated: Optional[str] = None
    if args.as_of:
        try:
            as_of_validated = _validate_as_of(args.as_of)
        except ValueError as exc:
            parser.error(f"--as-of: {exc}")

    (
        requested_agent365_mode,
        agent365_resolution_source,
        alias_overrides,
    ) = _resolve_requested_agent365_mode(args, parser)

    run_id = _generate_run_id()
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
        agent365_requested_mode=requested_agent365_mode,
        agent365_resolution_source=agent365_resolution_source,
        agent365_alias_overrides=alias_overrides,
        registry_export_path=args.registry_export or None,
        columnmap_path=args.columnmap if args.registry_export else None,
        as_of=as_of_validated,
        resolve_entitlement=args.resolve_entitlement,
        entitlement_ps1_path=args.entitlement_ps1_path if args.resolve_entitlement else None,
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

    # Fail the process when environment enumeration or the full environment scan
    # fails. Partial environment gaps remain usable output with an explicit
    # Incomplete status and warning. Evidence (if requested) is written first.
    status = result.get("summary", {}).get("status")
    if status == "Failed":
        logger.error("Scan status is Failed (see summary.environmentEnumeration / "
                     "summary.environmentFailures); exiting non-zero.")
        sys.exit(1)
    if status == "Incomplete":
        logger.warning("Scan status is Incomplete: %d environment failure(s) "
                       "recorded (see summary.environmentFailures). Review the "
                       "coverage gap before treating the inventory as complete.",
                       len(result.get("summary", {}).get("environmentFailures", [])))


if __name__ == "__main__":
    main()
