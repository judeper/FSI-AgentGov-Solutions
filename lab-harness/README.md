# Lab Harness Foundation (Public Surface Only)

This directory provides a reusable validation harness foundation for US commercial-cloud Microsoft 365 solution testing in `judeper/FSI-AgentGov-Solutions`.

## Public-code / private-execution boundary

- **Public repository scope:** reusable harness code, schemas, templates, docs, and GitHub-hosted CI checks.
- **Private execution scope:** live tenant execution, persistent lab runner registration, and dispatch workflows in `judep_microsoft/FSI-AgentGov-Lab`.
- **Hard boundary:** this public repository must not target self-hosted runners.

## Threat model and design assumptions

Primary risks addressed by this foundation:

1. **Unsafe execution inputs** (path traversal, arbitrary command execution).
2. **Cross-channel confusion** (runtime checks and portal/UI checks mixed without controls).
3. **Evidence leakage** (UPNs, GUIDs, webhook tokens, tenant URLs in committed artifacts).
4. **Overstated assurance** (claiming live success when only static validation ran).

Countermeasures implemented:

- Typed plan schema plus adapter allow-list.
- Explicit repo/evidence-root path confinement.
- Separate `runtime` and `playwright` channels.
- PlanOnly mode with explicit non-live outcome.
- Redaction and SHA-256 manifest tooling for sanitized evidence handling.

## What Playwright can and cannot prove

Playwright in this harness is intentionally limited to **portal/UI state**:

- Can prove page reachability, visible auth prompts, account-picker interruption, and basic portal rendering checks.
- Cannot prove API behavior, backend policy enforcement, Dataverse correctness, or runtime control outcomes.
- Runtime/API validation remains PowerShell/Pester/Python/pytest/direct REST in the `runtime` channel.

## Usage model

### Local foundation validation

Run the harness validation entry point in PlanOnly mode:

```powershell
pwsh .\lab-harness\runtime\Invoke-LabValidation.ps1 `
  -Solution audit-compliance-manager `
  -PlanPath .\lab-harness\templates\audit-compliance-manager.plan.json `
  -PlanOnly `
  -EvidenceRoot C:\FSI-Lab-Evidence
```

### Private-runner/live dispatch

- Live `workflow_dispatch` execution belongs in the private lab repository.
- This public repository intentionally excludes self-hosted runner workflows.
- The persistent lab runner must remain registered only to the private lab repository.

## Evidence lifecycle

1. Generate raw artifacts outside Git (for example, `C:\FSI-Lab-Evidence`).
2. Redact sensitive content via `lab-harness/evidence/Invoke-LabEvidenceRedaction.ps1`.
3. Generate a SHA-256 manifest via `lab-harness/evidence/New-LabEvidenceManifest.ps1`.
4. Publish only sanitized summary metadata and approved report outputs.
5. Clean up raw artifacts per ownership/cleanup manifest guidance.

Raw evidence is never committed to this repository.

## Redaction and rollback guidance

- Redaction targets: UPNs, tenant names/domains, GUIDs, environment URLs, webhook signatures, token-shaped values.
- Rollback/deletion: remove `lab-harness/` files from git history through normal revert if needed; this foundation does not provision tenant resources by itself.
- Optional `studio-video-factory` integration is evidence capture only and is not a runtime dependency.

## Scope and assurance language

- This content targets **US commercial-cloud Microsoft 365**.
- Any non-commercial cloud applicability should be validated independently with Microsoft.
- This harness **supports compliance with** evidence and validation workflows but does not guarantee legal or regulatory outcomes.
