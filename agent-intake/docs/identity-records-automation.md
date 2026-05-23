# Identity and records automation

This document replaces the manual Stage 2 records-and-identity prerequisites in `docs/pilot-deployment-runbook.md` with repeatable setup scripts. The automation supports the retention objective in ADR-006 and the sponsor / reviewer evidence objective in ADR-007 when customers pair it with their own Microsoft Purview and Microsoft Entra governance configuration.

## Stage 2 automation sequence

Run these steps from the `agent-intake` solution folder before enabling the handoff flow:

1. `pwsh .\scripts\setup_purview_retention_label.ps1`
2. `python .\scripts\setup_agent_identity_blueprint.py --output .\.agent-intake-smoke\blueprint.json`
3. Read `agentIdentityBlueprintId` from the JSON output and stamp it into `AGENT_INTAKE_AGENT_BLUEPRINT_ID`.
4. Continue with `python .\scripts\setup_entra_agent_id.py` during smoke-test or production handoff runs.

## What changed from the preview workflow

| Previous step | New automation |
| --- | --- |
| `setup_purview_retention_label.py` emitted a spec and printed manual instructions. | `setup_purview_retention_label.ps1` now creates the labels idempotently through Security & Compliance PowerShell. |
| Admins manually recorded a blueprint ID for `AGENT_INTAKE_AGENT_BLUEPRINT_ID`. | `setup_agent_identity_blueprint.py` now creates or finds the blueprint, ensures the blueprint principal exists, and returns the `agentIdentityBlueprintId` (`appId`) in JSON. |
| `setup_entra_agent_id.py` only carried a sponsor attestation. | `setup_entra_agent_id.py` now accepts reviewer-attestation evidence for Standard and Full paths while preserving the Express-path sponsor-only flow. |

## Scripts and expected output

### `scripts\setup_purview_retention_label.ps1`

- Primary supported path for creating `FSI-AgentIntake-7yr` and `FSI-AgentIntake-7yr-WORM`.
- Connects with `Connect-IPPSSession`, checks for existing labels, creates only the missing labels, and prints a summary table.
- Returns exit code `0` when labels already exist or are created successfully. Returns nonzero on operational failure.
- `-DryRun` prints the exact `New-ComplianceTag` commands that would run.

### `scripts\setup_purview_retention_label.py`

- Windows wrapper around the PowerShell script by default (`--use-powershell-wrapper`).
- Still writes the JSON label spec used by lab automation and can emit the delegated Graph beta sample with `--no-use-powershell-wrapper --include-graph-beta`.
- Prints a clear message describing whether it took the PowerShell path or the spec / Graph-beta path.

### `scripts\setup_agent_identity_blueprint.py`

- Creates or finds the blueprint named `FSI-AgentIntake-Default-Blueprint` by default.
- Returns JSON containing:
  - `agentIdentityBlueprintId` — the blueprint `appId` for `AGENT_INTAKE_AGENT_BLUEPRINT_ID`
  - `blueprintObjectId` — the application object ID
  - `blueprintPrincipal.id` — the associated blueprint principal, if present or newly created
  - `configuredInheritablePermissions` — the Microsoft Graph inheritable-scopes state
- `--dry-run` emits the planned Graph calls without requiring a token.
- Exit code `2` means the tenant hit a feature gate or permission boundary and should follow the manual fallback path.

### `scripts\setup_entra_agent_id.py`

- Express path: sponsor-only evidence continues to work with no new required flags.
- Standard path: pass `--approval-path Standard --reviewer-attestations-json '<json-array>'`.
- Full path: pass `--approval-path Full --reviewer-attestations-json '<json-array>'`.
- Reviewer evidence is rendered into the Graph payload as structured notes plus an open-type extension payload when the API accepts it.

## Required permissions

| Script | Minimum access | Why it is needed |
| --- | --- | --- |
| `setup_purview_retention_label.ps1` | Purview Retention Manager or another records-management role that can run `Get-ComplianceTag` and `New-ComplianceTag` | Creates and verifies the retention labels used for intake decision records. |
| `setup_purview_retention_label.py` | Same as the PowerShell path when the wrapper is enabled; delegated `RecordsManagement.ReadWrite.All` only for the Graph beta sample path | Keeps the supported PowerShell automation as the default while preserving the preview spec / beta reference path. |
| `setup_agent_identity_blueprint.py` | Agent ID Developer or Agent ID Administrator, plus `AgentIdentityBlueprint.Create` / `AgentIdentityBlueprint.ReadWrite.All`, and `AgentIdentityBlueprintPrincipal.Create` / `AgentIdentityBlueprintPrincipal.ReadWrite.All` when using Graph | Creates the blueprint application, creates the required blueprint principal for Graph-created blueprints, and configures inheritable scopes. |
| `setup_entra_agent_id.py` | `AgentIdentity.CreateAsManager` or `AgentIdentity.Create.All` on Microsoft Graph | Creates the agent identity and attaches sponsor / reviewer evidence. |

## Idempotent behavior

| Script | Idempotent behavior |
| --- | --- |
| `setup_purview_retention_label.ps1` | Checks each label with `Get-ComplianceTag` before attempting creation. Existing labels are reported and not recreated. |
| `setup_agent_identity_blueprint.py` | Looks up the blueprint by display name before creating it, then ensures the same blueprint principal and Microsoft Graph inheritable-scope entry are present. |
| `setup_entra_agent_id.py` | Existing Express-path inputs still produce the same create payload. Reviewer evidence is only added when the new flag is supplied. |

## How the later orchestrator should chain these scripts

The later `deploy.ps1` workstream can call the scripts non-interactively in this order:

1. Run `setup_purview_retention_label.ps1 -AdminUpn <records-admin-upn>`.
2. Run `setup_agent_identity_blueprint.py --output <path>` and read `agentIdentityBlueprintId` from the JSON.
3. Export or inject `AGENT_INTAKE_AGENT_BLUEPRINT_ID=<agentIdentityBlueprintId>`.
4. During the handoff step, call `setup_entra_agent_id.py` with the stamped blueprint ID. Pass reviewer evidence only for Standard and Full paths.

## Manual fallback - Purview retention labels

Use this path when the tenant can't run Security & Compliance PowerShell or the records-management admin role isn't available yet.

1. Sign in to [Microsoft Purview](https://purview.microsoft.com/).
2. Browse to **Solutions** > **Records Management** > **File plan**.
3. Create a retention label named `FSI-AgentIntake-7yr`.
4. Configure it to retain items for `2555` days based on the creation date and take no action after the retention period.
5. Create a second label named `FSI-AgentIntake-7yr-WORM` with the same duration and turn on **Mark items as records**.
6. Save the labels and record the exact label names used by the intake decision-log flow.

## Manual fallback - Microsoft Entra Agent Identity blueprint

Use this path when `setup_agent_identity_blueprint.py` exits with code `2` because the tenant doesn't have the feature enabled yet or the caller can't use the Graph endpoint.

1. Sign in to the [Microsoft Entra admin center](https://entra.microsoft.com).
2. Browse to **Entra ID** > **Agents** > **Agent blueprints**.
3. Select **New agent blueprint (Preview)**.
4. Enter `FSI-AgentIntake-Default-Blueprint` as the display name.
5. Add a sponsor. An owner is recommended for the team that will maintain the blueprint.
6. Finish the wizard and record the resulting `appId` as `AGENT_INTAKE_AGENT_BLUEPRINT_ID`.
7. If you later create or update the blueprint through Microsoft Graph, also create the corresponding blueprint principal before enabling agent-identity creation from automation.

## Related decisions

- [ADR-006 — 7-year retention label](decisions.md#adr-006--7-year-immutable-retention-via-purview-fsi-agentintake-7yr-label)
- [ADR-007 — sponsor attestation and later reviewer evidence](decisions.md#adr-007--sponsor-1-click-is-sufficient-finra-3110-evidence-for-express-only)

This automation supports compliance with FINRA Rule 4511, SEC Rule 17a-4, CFTC Rule 1.31, and FINRA Rule 3110 by making the retention-label and identity-prerequisite steps repeatable, reviewable, and easier to re-run during controlled deployments. Organizations should still verify tenant licensing, role assignments, and downstream evidence stamping in their own environment.
