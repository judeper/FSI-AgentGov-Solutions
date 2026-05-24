# Pilot Validation Gap Analysis — Issue #123

> **Date:** 2026-05-23  
> **Reviewer:** Saul (OceanSquad) via issue judeper/OceanSquad#13  
> **Scope:** `agent-intake` v0.2.0-preview (PR #122) — Entra Agent ID + Purview retention-label API paths

## Summary

The agent-intake scripts for Entra Agent ID and Purview retention-label creation are **well-structured and ready for live-tenant validation**. Code review found no blocking correctness issues. This analysis adds 58 new unit tests for the pure-logic functions and documents the gaps that require human intervention.

## Script Review

### Path A — Entra Agent ID (`setup_entra_agent_id.py`)

| Area | Status | Notes |
|------|--------|-------|
| Graph endpoint (`/v1.0/servicePrincipals/microsoft.graph.agentIdentity`) | ✅ Correct | Matches current Microsoft Learn docs |
| Managed-identity-first auth | ✅ Correct | Falls back to Azure CLI with appropriate comment |
| Sponsor resolution via `GET /v1.0/users/{upn}` | ✅ Correct | URL-encodes UPN |
| Reviewer attestation parsing | ✅ Correct | Validates roles, UPNs, hashes, quorum requirements |
| Express / Standard / Full path routing | ✅ Correct | Quorum enforcement: 0 / 1+ / 3+ non-sponsor attestations |
| 400 retry with PATCH fallback for reviewer evidence | ✅ Correct | Gracefully handles API rejecting open-type extension |
| Notes-only fallback when PATCH 400 | ✅ Correct | Downgrades to notes string when extension payload rejected |
| Dry-run mode | ✅ Correct | Emits planned payload without requiring token |
| Consent check mode | ✅ Correct | Best-effort permission readiness probe |
| `--approval-path` CLI validation | ✅ Correct | `choices` restricts to Express/Standard/Full |
| `--owner-upn` backward-compat alias | ✅ Correct | Maps to `sponsor_upn` via `dest` |

**No code changes needed.** Live validation required to confirm HTTP 201 and `fsiReviewerAttestations` acceptance.

### Path A prerequisite — Blueprint (`setup_agent_identity_blueprint.py`)

| Area | Status | Notes |
|------|--------|-------|
| Blueprint find-or-create idempotency | ✅ Correct | Looks up by display name before POST |
| Blueprint principal creation | ✅ Correct | Handles 409 conflict race condition |
| Inheritable permissions (enumerated/all/none) | ✅ Correct | Three OData types handled correctly |
| Permissions drift detection | ✅ Correct | PATCH when existing doesn't match desired |
| Feature gate detection (403/404) | ✅ Correct | Raises `ManualFallbackRequired` with exit code 2 |
| Manual fallback doc extraction | ✅ Correct | Reads from `identity-records-automation.md` |

### Path B — Purview retention label

| Area | Status | Notes |
|------|--------|-------|
| PowerShell wrapper (`setup_purview_retention_label.ps1`) | ✅ Correct | Idempotent, module version check, dry-run |
| Python wrapper delegates to PowerShell on Windows | ✅ Correct | `--use-powershell-wrapper` defaults to `sys.platform.startswith("win")` |
| Graph beta sample emission | ✅ Correct | POST URL and permission note are accurate |
| Label spec (7yr, WORM variant, regulatory refs) | ✅ Correct | SEC 17a-4, FINRA 4511, CFTC 1.31 cited |
| ExchangeOnlineManagement bootstrap | ✅ Correct | Version ≥ 3.2.0 required, interactive install offer |
| `Connect-IPPSSession` with `-DisableWAM` | ✅ Correct | Avoids invisible WebView2 popup hang |

## Test Coverage Added

| Test file | Tests | What it covers |
|-----------|-------|----------------|
| `test_entra_agent_id.py` | 30 | Attestation parsing, approval-path normalization, timestamp parsing, payload construction, evidence rendering |
| `test_purview_retention_label.py` | 8 | Label spec defaults, WORM variant, custom values, regulatory references, Graph beta sample, JSON serialization |
| `test_agent_identity_blueprint.py` | 20 | Scope normalization, blueprint payload, scope configuration (none/all/enumerated), permissions matching |

**Total:** 58 new tests. Suite now has **100 tests** (was 42), all passing.

## Gaps Requiring Human Intervention

These items cannot be validated without live tenant access. They map to the acceptance criteria in issue #123.

### Gap 1 — Entra Agent ID create (issue #123 Path A)

**What:** Execute `setup_entra_agent_id.py` against a tenant with Agent ID capabilities.  
**Prerequisites:**
- Tenant with Application Administrator role
- Custom directory role with `microsoft.directory/agentIdentity/createAsOwner` (or Global Admin)
- `AgentIdentity.ReadWrite.All` consented
- Pre-provisioned Agent Identity blueprint (via `setup_agent_identity_blueprint.py`)
- Sponsor UPN in the same tenant

**Validation steps:**
1. Run `python setup_agent_identity_blueprint.py --output blueprint.json` — capture `agentIdentityBlueprintId`
2. Run `python setup_entra_agent_id.py --intake-request-id <IRID> --display-name <NAME> --blueprint-id <BPID> --sponsor-upn <UPN>`
3. Confirm HTTP 201 and capture response body (`id`, `appId`)
4. Verify Agent Identity visible in Entra Admin Center → Applications → Agent Identities
5. Confirm sponsor relationship visible

**Risk if blocked:** If Agent ID create returns HTTP 400 on the `fsiReviewerAttestations` open-type field, the PATCH fallback handles it. If HTTP 403, update `docs/setup-prerequisites.md` with explicit consent steps.

### Gap 2 — Purview retention-label create (issue #123 Path B)

**What:** Execute `setup_purview_retention_label.ps1` against a tenant with Purview Compliance.  
**Prerequisites:**
- Compliance Administrator or Compliance Data Administrator role
- ExchangeOnlineManagement module ≥ 3.2.0

**Validation steps:**
1. Run `pwsh setup_purview_retention_label.ps1 -AdminUpn <UPN>`
2. Confirm both `FSI-AgentIntake-7yr` and `FSI-AgentIntake-7yr-WORM` labels created
3. Verify labels in Purview Compliance Portal → Information governance → Retention labels
4. Optionally test `setup_purview_retention_label.py --no-use-powershell-wrapper --include-graph-beta` for beta Graph path confirmation

### Gap 3 — `fsiReviewerAttestations` open-type field acceptance

**What:** The open-type extension field on Agent Identity POST is untested. The script handles rejection gracefully (PATCH fallback, then notes-only fallback), but the preferred path where POST accepts the extension payload directly has not been confirmed.  
**Impact:** Low — all three fallback paths are implemented. But knowing which path succeeds informs documentation.

## Failure Interpretation Matrix

| Failure mode | Classification | Action |
|---|---|---|
| HTTP 403 on Agent ID create | Docs gap | Update `setup-prerequisites.md` with consent + role steps |
| HTTP 400 / schema error on Agent ID create | Solution blocker | File bug issue; block GA promotion |
| HTTP 403 on Purview create | Docs gap | Update Purview prerequisites |
| HTTP 400 on Purview create | Solution blocker | File bug issue |
| Beta endpoint deprecated | Docs update | Switch to production portal path |
| `fsiReviewerAttestations` rejected on POST but accepted on PATCH | Expected behavior | Document PATCH as the supported path |
| `fsiReviewerAttestations` rejected on both POST and PATCH | Graceful degradation | Notes-only path is already implemented |
