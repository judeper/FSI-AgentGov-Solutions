#!/usr/bin/env python3
"""
Resolver: owner UPNs -> Copilot license entitlement (fsi_ownerentitlement).

Takes a list of owner UPNs from fsi_copilotagent rows and resolves each to one
of three entitlement classes:

  Paid Copilot     — owner has at least one paid Microsoft 365 Copilot service
                     plan (M365_COPILOT_* or sibling plan) with provisioningStatus
                     == "Success".
  Copilot Chat Only — owner has the Bing_Chat_Enterprise deny-trap plan
                     (0d0c0d31-fae7-41f2-b909-eaf4d7f26dba) and NO paid plan.
  Unknown           — owner could not be resolved (lookup failure, missing UPN,
                     or any unhandled error). Fail-open: never assert "blocked"
                     for a user that could not be verified.

Reuse mechanism: invokes copilot-billing-governance/scripts/Get-CopilotEntitlement.ps1
as a subprocess. The PS script is the single source of truth for the service-plan
GUID allowlist and deny list; this resolver does NOT replicate those GUIDs.
Token is acquired via Azure Identity (managed-identity-first) and passed to the
PS script as -GraphAccessToken.

Output: JSON document with an "entitlements" array ordered to match the input
UPN list. Each entry contains:
  fsi_ownerentitlement       — string label ("Paid Copilot" | "Copilot Chat Only" | "Unknown")
  fsi_ownerentitlementevidence — JSON array of matched service-plan GUIDs (NO UPN/PII).
                                  Empty array on Unknown.

Auth: managed-identity-first (DefaultAzureCredential); falls back through
workload-identity -> interactive -> client-secret (dev-only).

Privacy: UPNs are runtime-only inputs. fsi_ownerentitlementevidence contains
ONLY service-plan GUIDs — no UPN, display name, or other PII is committed or
emitted in any output field.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Entitlement labels (must match fsi_cai_ownerentitlement option-set).
# ---------------------------------------------------------------------------
ENTITLEMENT_PAID = "Paid Copilot"
ENTITLEMENT_CHAT_ONLY = "Copilot Chat Only"
ENTITLEMENT_UNKNOWN = "Unknown"

# Bing_Chat_Enterprise service-plan GUID (deny trap from Get-CopilotEntitlement.ps1).
# This constant is used ONLY to classify the PS script output — it is NOT an allowlist
# reimplementation. The authoritative deny list lives in Get-CopilotEntitlement.ps1.
_BCE_PLAN_GUID = "0d0c0d31-fae7-41f2-b909-eaf4d7f26dba"

# Default PS1 path relative to this script's location.
_DEFAULT_PS1_PATH = (
    Path(__file__).parent.parent.parent
    / "copilot-billing-governance"
    / "scripts"
    / "Get-CopilotEntitlement.ps1"
)

# IMPORTANT: Get-CopilotEntitlement.ps1 guards its main execution block with
#   if ($MyInvocation.InvocationName -ne '.')
# This means dot-sourcing (`. 'path\script.ps1'`) SKIPS the main block entirely
# and produces no output file. The call operator (`&`) MUST be used so the script
# runs normally. _build_ps_command requires this; do not revert to dot-source.

# Graph resource scope for token acquisition.
GRAPH_SCOPE = "https://graph.microsoft.com/.default"


# ---------------------------------------------------------------------------
# Token acquisition (managed-identity-first).
# ---------------------------------------------------------------------------

def _get_graph_token(auth_mode: str, tenant_id: Optional[str], client_id: Optional[str]) -> str:
    """Acquire a Microsoft Graph bearer token (managed-identity-first).

    Lazily imports azure-identity so the module compiles and --dry-run runs
    without the optional dependency installed.
    """
    try:
        import azure.identity as azid  # type: ignore
    except ImportError as exc:
        raise RuntimeError(
            "azure-identity is required for live entitlement resolution. "
            "Install via: pip install 'azure-identity>=1.15.0', or use --dry-run."
        ) from exc

    if auth_mode == "managed-identity":
        cred = (
            azid.ManagedIdentityCredential(client_id=client_id)
            if client_id else azid.ManagedIdentityCredential()
        )
    elif auth_mode == "workload-identity":
        cred = azid.WorkloadIdentityCredential(tenant_id=tenant_id, client_id=client_id)
    elif auth_mode == "interactive":
        cred = azid.InteractiveBrowserCredential(tenant_id=tenant_id, client_id=client_id)
    elif auth_mode == "client-secret":
        # legacy: dev-only — replace with managed identity in production
        secret = os.environ.get("CAI_CLIENT_SECRET")
        if not (tenant_id and client_id and secret):
            raise ValueError(
                "client-secret auth requires --tenant-id, --client-id and "
                "CAI_CLIENT_SECRET env var (dev-only fallback)."
            )
        cred = azid.ClientSecretCredential(
            tenant_id=tenant_id, client_id=client_id, client_secret=secret
        )
    else:
        cred = azid.DefaultAzureCredential()

    return cred.get_token(GRAPH_SCOPE).token


# ---------------------------------------------------------------------------
# Subprocess invocation of Get-CopilotEntitlement.ps1.
# ---------------------------------------------------------------------------


def _build_ps_command(
    ps1_path: Path,
    input_file: Path,
    output_file: Path,
    billing_policy_file: Path,
) -> list[str]:
    """Build the pwsh argv list for invoking Get-CopilotEntitlement.ps1.

    Uses the CALL OPERATOR (`&`) — NOT dot-source (`.`) — because the PS1
    main block is guarded by `$MyInvocation.InvocationName -ne '.'`.
    Dot-sourcing would silently skip main and produce no output file.

    The Graph token is read by the PS1 from $env:CAI_GRAPH_TOKEN; it is
    NOT passed as a command-line argument to avoid process-list exposure.

    billing_policy_file must point to a file containing a JSON document with
    a "billingPolicies" key (typically the synthetic empty-policy file written
    by _invoke_ps1). Passing -BillingPolicyInputPath causes the PS1 main block
    to take the `elseif -not [string]::IsNullOrWhiteSpace($BillingPolicyInputPath)`
    branch and skip the live Power Platform billing API read. Without this, the
    PS1 falls to its else-branch and calls Get-CbgResourceToken for
    https://api.powerplatform.com/, which throws on a managed-identity runner
    with no ambient Az context when -BillingApiAccessToken is not supplied.

    Test hook: call this helper to assert the `&` operator is present
    without needing a live pwsh process.
    """
    return [
        "pwsh",
        "-NonInteractive",
        "-Command",
        (
            f"& '{ps1_path}'"
            f" -InputPath '{input_file}'"
            f" -OutputPath '{output_file}'"
            f" -GraphAccessToken $env:CAI_GRAPH_TOKEN"
            f" -BillingPolicyInputPath '{billing_policy_file}'"
        ),
    ]


def _invoke_ps1(
    upns: list[str],
    ps1_path: Path,
    graph_token: str,
    work_dir: Path,
    run_id: str,
) -> dict:
    """Invoke Get-CopilotEntitlement.ps1 for the given UPN list.

    Writes a temp input file to work_dir, runs the PS1 script, reads the output
    JSON, and cleans up temp files. The graph_token is passed via a subprocess
    environment variable (not as a command-line argument) to avoid process-list
    exposure.

    Returns the parsed output JSON dict from Get-CopilotEntitlement.ps1.
    Raises subprocess.CalledProcessError or RuntimeError on failure.
    """
    if not ps1_path.exists():
        raise FileNotFoundError(
            f"Get-CopilotEntitlement.ps1 not found at: {ps1_path}. "
            "Override with --ps1-path."
        )

    input_file = work_dir / f"_cai_entitlement_input_{run_id}.json"
    output_file = work_dir / f"_cai_entitlement_output_{run_id}.json"
    # Synthetic empty billing-policy file: passes -BillingPolicyInputPath to the
    # PS1 so it skips its live Power Platform billing API read. Without this the
    # PS1 else-branch calls Get-CbgResourceToken for https://api.powerplatform.com/
    # which throws on a managed-identity runner with no ambient Az context.
    # {"billingPolicies":[]} → Get-CbgBillingPolicyArray returns @() (zero policies)
    # → Graph-based license classification continues normally.
    billing_file = work_dir / f"_cai_billing_policy_{run_id}.json"

    try:
        input_file.write_text(
            json.dumps({"upns": upns}), encoding="utf-8"
        )
        billing_file.write_text(
            json.dumps({"billingPolicies": []}), encoding="utf-8"
        )

        # Pass the Graph token via an environment variable to avoid exposing it
        # in the process argument list. The PS1 script reads $env:CAI_GRAPH_TOKEN.
        child_env = {**os.environ, "CAI_GRAPH_TOKEN": graph_token}

        cmd = _build_ps_command(ps1_path, input_file, output_file, billing_file)
        logger.info(
            "Invoking Get-CopilotEntitlement.ps1 for %d UPN(s) (run_id=%s)",
            len(upns), run_id,
        )
        result = subprocess.run(
            cmd,
            env=child_env,
            capture_output=True,
            text=True,
            timeout=300,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"Get-CopilotEntitlement.ps1 exited with code {result.returncode}. "
                f"stderr: {result.stderr[:2000]}"
            )
        if not output_file.exists():
            raise RuntimeError(
                "Get-CopilotEntitlement.ps1 did not write an output file. "
                f"stdout: {result.stdout[:1000]}"
            )
        return json.loads(output_file.read_text(encoding="utf-8"))

    finally:
        for f in (input_file, output_file, billing_file):
            try:
                if f.exists():
                    f.unlink()
            except Exception:  # pragma: no cover - cleanup best-effort
                pass


# ---------------------------------------------------------------------------
# Classification logic.
# ---------------------------------------------------------------------------

def _classify_user(user_obj: dict) -> tuple[str, str]:
    """Classify one resolved user from the PS1 output into an entitlement label.

    Returns (fsi_ownerentitlement, fsi_ownerentitlementevidence).
    Evidence contains only service-plan GUIDs — no UPN or other PII.
    """
    if user_obj.get("hasCopilotLicense"):
        matched_plans = list(user_obj.get("matchedPlanIds") or [])
        evidence = json.dumps(matched_plans)
        return ENTITLEMENT_PAID, evidence

    denied_seen = [str(g).lower() for g in (user_obj.get("deniedPlanIdsObserved") or [])]
    if _BCE_PLAN_GUID in denied_seen:
        evidence = json.dumps([_BCE_PLAN_GUID])
        return ENTITLEMENT_CHAT_ONLY, evidence

    return ENTITLEMENT_UNKNOWN, "[]"


def resolve_entitlements(
    upns: list[str],
    ps1_path: Path,
    graph_token: str,
    work_dir: Path,
    run_id: str,
) -> tuple[list[dict], bool]:
    """Resolve entitlement for each UPN; return (results, invocation_failed).

    On any resolution failure for a UPN (unresolved in PS1 output, lookup error,
    or subprocess failure) the entry is set to Unknown — fail-open, never assert
    blocked for an unverifiable owner.

    invocation_failed is True when the PS1 subprocess could not be started or
    exited non-zero; False on a normal PS1 run (even if individual UPNs resolved
    to Unknown). Callers use this to distinguish "ran; owners genuinely Unknown"
    from "resolver crashed" when setting audit/summary status.

    Returns (results, invocation_failed):
      results: list of dicts with fsi_ownerentitlement + fsi_ownerentitlementevidence.
      invocation_failed: True when _invoke_ps1 raised (subprocess-level failure).
    No UPN appears in the returned dicts.
    """
    if not upns:
        return [], False

    try:
        ps_result = _invoke_ps1(upns, ps1_path, graph_token, work_dir, run_id)
    except Exception as exc:
        logger.error(
            "Get-CopilotEntitlement.ps1 invocation failed; "
            "all %d UPNs set to Unknown (fail-open): %s",
            len(upns), exc,
        )
        return (
            [
                {"fsi_ownerentitlement": ENTITLEMENT_UNKNOWN,
                 "fsi_ownerentitlementevidence": "[]"}
                for _ in upns
            ],
            True,  # invocation_failed
        )

    # Build a case-insensitive lookup from UPN to resolved user object.
    resolved_by_upn: dict[str, dict] = {}
    for user_obj in (ps_result.get("users") or []):
        upn_key = str(user_obj.get("upn") or "").strip().lower()
        if upn_key:
            resolved_by_upn[upn_key] = user_obj

    # For each input UPN, classify in input order (no UPN in output).
    results: list[dict] = []
    for upn in upns:
        upn_key = upn.strip().lower()
        user_obj = resolved_by_upn.get(upn_key)
        if user_obj is not None:
            entitlement, evidence = _classify_user(user_obj)
        else:
            # UPN appeared in unresolved[] or was entirely absent: Unknown.
            logger.debug("UPN not in resolved set; setting Unknown (fail-open).")
            entitlement, evidence = ENTITLEMENT_UNKNOWN, "[]"
        results.append({
            "fsi_ownerentitlement": entitlement,
            "fsi_ownerentitlementevidence": evidence,
        })

    resolved_count = sum(1 for r in results if r["fsi_ownerentitlement"] != ENTITLEMENT_UNKNOWN)
    logger.info(
        "Entitlement resolved: %d/%d (Unknown=%d)",
        resolved_count, len(upns), len(upns) - resolved_count,
    )
    return results, False


# ---------------------------------------------------------------------------
# CLI entry point.
# ---------------------------------------------------------------------------

def _main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--upns-file", required=True,
        help=(
            "Path to a JSON file containing the UPN list to resolve. "
            'Accepted shapes: {"upns": ["a@contoso.com", ...]} '
            'or a bare JSON array ["a@contoso.com", ...].'
        ),
    )
    parser.add_argument(
        "--ps1-path",
        default=str(_DEFAULT_PS1_PATH),
        help=(
            "Path to Get-CopilotEntitlement.ps1. "
            f"Default: {_DEFAULT_PS1_PATH}"
        ),
    )
    parser.add_argument(
        "--auth-mode",
        choices=["managed-identity", "workload-identity", "interactive",
                 "client-secret", "default"],
        default=os.environ.get("CAI_AUTH_MODE", "managed-identity"),
        help="Authentication mode for Graph token acquisition.",
    )
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("CAI_TENANT_ID"),
        help="Microsoft Entra tenant ID (or set CAI_TENANT_ID).",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CAI_CLIENT_ID"),
        help="Service principal client ID (or CAI_CLIENT_ID).",
    )
    parser.add_argument(
        "--work-dir",
        default=None,
        help=(
            "Directory for temporary input/output files passed to pwsh. "
            "Defaults to the directory of --upns-file."
        ),
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Write the result JSON to this path (default: stdout).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Log the planned invocation without contacting any service.",
    )
    parser.add_argument(
        "--log-level",
        default=os.environ.get("CAI_LOG_LEVEL", "INFO"),
        help="Logging level (DEBUG, INFO, WARNING, ERROR).",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, str(args.log_level).upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    # Load UPN list.
    upns_path = Path(args.upns_file)
    if not upns_path.exists():
        logger.error("UPNs file not found: %s", upns_path)
        return 1
    raw_input = json.loads(upns_path.read_text(encoding="utf-8"))
    if isinstance(raw_input, list):
        upns = [str(u) for u in raw_input if u]
    elif isinstance(raw_input, dict) and "upns" in raw_input:
        upns = [str(u) for u in raw_input["upns"] if u]
    else:
        logger.error(
            "UPNs file must contain a JSON array or {\"upns\": [...]}. Got: %s",
            type(raw_input).__name__,
        )
        return 1

    ps1_path = Path(args.ps1_path)
    work_dir = Path(args.work_dir) if args.work_dir else upns_path.parent
    run_id = str(uuid.uuid4()).replace("-", "")[:16]

    if args.dry_run:
        logger.info(
            "[DRY RUN] would invoke %s for %d UPN(s) "
            "(Graph token via auth_mode=%s; no network calls made)",
            ps1_path, len(upns), args.auth_mode,
        )
        # Emit placeholder Unknown entries in dry-run mode.
        dry_results = [
            {"fsi_ownerentitlement": ENTITLEMENT_UNKNOWN, "fsi_ownerentitlementevidence": "[]"}
            for _ in upns
        ]
        result_doc = {
            "run_id": run_id,
            "dry_run": True,
            "upn_count": len(upns),
            "entitlements": dry_results,
        }
        if args.output:
            Path(args.output).write_text(
                json.dumps(result_doc, indent=2), encoding="utf-8"
            )
        else:
            sys.stdout.write(json.dumps(result_doc, indent=2) + "\n")
        return 0

    # Acquire Graph token.
    try:
        graph_token = _get_graph_token(args.auth_mode, args.tenant_id, args.client_id)
    except Exception as exc:
        logger.error("Graph token acquisition failed: %s", exc)
        return 1

    entitlements, invocation_failed = resolve_entitlements(
        upns=upns,
        ps1_path=ps1_path,
        graph_token=graph_token,
        work_dir=work_dir,
        run_id=run_id,
    )

    result_doc = {
        "run_id": run_id,
        "dry_run": False,
        "invocation_failed": invocation_failed,
        "upn_count": len(upns),
        "entitlements": entitlements,
    }
    output_json = json.dumps(result_doc, indent=2, default=str)

    if args.output:
        Path(args.output).write_text(output_json, encoding="utf-8")
        logger.info("Wrote entitlement results to %s", args.output)
    else:
        sys.stdout.write(output_json + "\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
