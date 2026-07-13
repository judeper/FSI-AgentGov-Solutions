# Lab Validation — agent-intake

| | |
|---|---|
| **Solution** | agent-intake |
| **Version** | v1.0.1-preview |
| **Validation snapshot date** | 2026-07-13 |
| **Pinned source repo** | `C:\dev\FSI-AgentGov-Lab` |
| **Pinned source commit** | `625c762214fc11f588ada47a5ee1a85077927b2d` |
| **Pinned source subtree** | `agent-intake/` |

## Back-port scope in this release

This back-port includes only the lab-validated Express and Standard intake paths and their supporting deployment/runtime fixes:

- Express path validation support (sponsor-card flow trigger tooling)
- Standard path validation support (parallel-reviewer tooling + quorum wiring)
- connection-reference solution-membership enforcement in solution-shell provisioning
- unattended lab-cycle guardrails (`-SkipPurviewLabel`, readiness preflight, module gating)
- supporting scripts/tests/docs required to run the validated path checks

## Explicit exclusions

The following were intentionally excluded from this back-port:

- training HTML modules
- `RESUME.md`
- `config.local.json`
- live tenant identifiers (UPNs, tenant names, environment URLs, object IDs, webhook URLs)
- runtime evidence payload bodies and `.deploy-runtime` artifacts
- research-only artifacts not required for Express/Standard operation
- deferred production extensions: **F6, F7, F9, F10, F11**
- exported Power Automate flow JSON or any other runtime Power Platform artifacts

## Live-validation findings carried forward

Validated in lab source and carried into this repository:

1. **Express path:** submission → sponsor decision path validated end-to-end.
2. **Standard path:** single-reviewer and multi-reviewer quorum behavior validated (including any-deny path).
3. **Connection references:** solution-shell now adds references by `connectionreference` type name and verifies membership in `FSIAgentIntake` so references do not remain silently in Default solution.
4. **Unattended deployment cycle:** skip-label mode and preflight checks support non-interactive lab runs while preserving identity/policy probes.

## Evidence references (sanitized)

Evidence artifacts are retained in the lab source runtime area and are not committed here:

- `agent-intake/lab/.deploy-runtime/evidence/evidence-express-happy-20260614.json` *(gitignored runtime artifact)*
- `agent-intake/lab/.deploy-runtime/evidence/evidence-f4-standard-3-paths-20260614.json` *(gitignored runtime artifact)*

These references are preserved for traceability only; no live tenant IDs, bearer values, or runtime payload bodies are committed in this repository.

## Redaction sweep result

A redaction sweep was run across the back-port diff for tenant names, UPNs, GUIDs, environment URLs, object IDs, webhook URLs, and bearer values. Result:

- committed examples use placeholders (`https://<your-env>.crm.dynamics.com`, `admin@example.com`, placeholder GUID format)
- no live tenant-specific identifiers were retained in changed files
- no bearer token values are logged or persisted

## Deferred production extensions

The following remain deferred to later releases and were not included in this patch version:

- **F6** escalation workflow
- **F7** MRM-gated full-path handoff
- **F9** maker notification workflow
- **F10** platform handoff workflow
- **F11** denial appeal workflow

## Assessment

This v1.0.1-preview back-port supports compliance with the same controls as v1.0.0-preview while improving operational reliability for the validated Express/Standard lab paths. Production rollout still requires customer-specific governance approvals, environment hardening, and completion of deferred extensions where required by policy.
