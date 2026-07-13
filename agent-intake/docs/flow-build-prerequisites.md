# Flow build prerequisites

The repository intentionally does not ship exported Power Automate runtime artifacts. Complete this checklist before you build any of the flows in [`flow-configuration.md`](./flow-configuration.md).

## 1. Install and authenticate tooling

- PowerShell 7
- Power Platform CLI (`pac`)
- Python 3.11 or later for the identity, MRM, and smoke-test helper scripts
- An authenticated PAC profile targeted to the correct Dataverse environment

Recommended authentication patterns:

```powershell
# Azure-hosted runner or Function app
pac auth create --managedIdentity --environment https://<your-env>.crm.dynamics.com

# Admin workstation
pac auth create --deviceCode --environment https://<your-env>.crm.dynamics.com
```

Use `pac auth who --json` and `pac env who --json` to confirm the active profile and environment before you create solution components.

## 2. Provision the unmanaged solution shell

Run the solution-shell bootstrap script from the `agent-intake` folder:

```powershell
pwsh .\scripts\provision_solution_shell.ps1 `
  -EnvironmentUrl https://<your-env>.crm.dynamics.com `
  -EnvVarValues @{
    fsi_intake_powerplatformenvironmenturl = 'https://<your-env>.crm.dynamics.com'
    fsi_intake_makerportalurl              = 'https://<tenant>.powerpagesportals.com/agent-intake'
    fsi_intake_reviewerappurl              = 'https://make.powerapps.com/e/<env>/apps/<app-id>'
    fsi_intake_mrmtargetenv                = 'https://<your-env>.crm.dynamics.com'
    fsi_intake_driftdetectorenv            = 'https://<drift-endpoint>'
    fsi_intake_retentionlabelid            = '<purview-label-guid>'
    fsi_intake_sponsorbackupgroup          = 'agent-intake-sponsor-backups@example.com'
  }
```

Confirm that the script reports:

- publisher `FSIPublisher`
- unmanaged solution `FSIAgentIntake`
- all `fsi_intake*` tables plus `fsi_acv_zone`
- all seven environment variable definitions
- connection references for Dataverse, Teams, Office 365 Outlook, HTTP with Microsoft Entra ID, and the Microsoft Graph custom connector (or a `MANUAL STEP REQUIRED:` notice for the custom connector lookup)

If the script prints `MANUAL STEP REQUIRED: run create_fsi_intake_dataverse_schema.py first`, complete that foundation step before you build flows.

## 3. Bind connection references to working connections

`provision_solution_shell.ps1` creates the connection-reference **definitions** and adds them to the `FSIAgentIntake` solution. **Bind the existing references — do not create new ones.** Open **Solutions** > **FSI Agent Intake**, set the object filter to **Connection references**, open each reference, and choose a working connection before you save the first flow. (Create the underlying Dataverse/Teams/Office 365 connections first if they do not yet exist.)

| Connection reference | Connector | Used by |
|---|---|---|
| `fsi_cr_dataverse_agentintake` | Microsoft Dataverse | All flows that read or write `fsi_intakerequest` and child tables |
| `fsi_cr_teams_agentintake` | Microsoft Teams | Sponsor cards, reviewer cards, escalations, denial notifications |
| `fsi_cr_office365_agentintake` | Office 365 Outlook | Reviewer reminders and escalation mail fallback |
| `fsi_cr_http_agentintake` | HTTP with Microsoft Entra ID | Classifier API calls, MRM handoff, registry handoff, drift handoff, retention callbacks |
| `fsi_cr_graph_agentintake` | Microsoft Graph custom connector | Graph profile prefill, Agent ID actions, or a customer-specific wrapper around Microsoft Graph |

> The shell script creates the connection-reference definitions and adds them to the solution. Binding them to actual connections is still an admin step in the maker UI.

> **Troubleshooting — references missing from the solution.** If the references above do not appear under **Connection references** in the `FSIAgentIntake` solution, they were created in the **Default** solution and never added to this one. Do **not** use the **+ New connection reference** button — that creates a duplicate (for example `fsi_dataverseagentintake`) the flows and scripts will not use, and leaves the real `fsi_cr_*` reference unbound. Instead re-run `provision_solution_shell.ps1` (it now adds each reference by the pac type **name** `connectionreference` and verifies solution membership), or add each existing reference manually: `pac solution add-solution-component --solutionUniqueName FSIAgentIntake --component <connectionreferenceid> --componentType connectionreference`. The pac CLI does not recognize connection references by numeric component type — the **name** `connectionreference` is required.

## 4. Populate solution environment variables

Set current values in **FSI Agent Intake** > **Environment variables**.

| Schema name | Populate with | Used by |
|---|---|---|
| `fsi_intake_powerplatformenvironmenturl` | Current Dataverse environment URL | Link generation, API callbacks, and shell validation |
| `fsi_intake_makerportalurl` | Public maker portal URL for `/agent-intake` | Maker notifications and denial/appeal deep links |
| `fsi_intake_reviewerappurl` | Reviewer model-driven app URL | Reviewer adaptive card `Open in reviewer app` action |
| `fsi_intake_mrmtargetenv` | MRM target environment URL or wrapper endpoint | Flow 7 MRM handoff |
| `fsi_intake_driftdetectorenv` | Drift-detector environment URL or wrapper endpoint | Flow 10 drift handoff |
| `fsi_intake_retentionlabelid` | Purview retention label ID or the identifier used by your retention wrapper | Flow 8 and Flow 12 retention evidence |
| `fsi_intake_sponsorbackupgroup` | Microsoft 365 group, DL, or UPN used when sponsor escalation cannot route to the manager | Flow 3 sponsor timeout and Flow 6 escalation fallback |

All seven values are string variables. Keep them environment-specific so the same solution shell can move from dev to test to production without editing the flow definitions.

## 5. Create security roles and access surfaces

Before you build the reviewer-facing flows, confirm these access layers exist:

- Power Pages table permissions for `fsi_intakerequest`, `fsi_intakedatasource`, and `fsi_intakerisksignal`
- Reviewer model-driven app roles from [`reviewer-app-build.md`](./reviewer-app-build.md) for InfoSec, Privacy, Compliance, Legal, MRM, and Governance Lead
- A working reviewer app URL in `fsi_intake_reviewerappurl`
- Teams recipients or groups for sponsor backup, reviewer escalation, and governance notifications

## 6. Retention and identity prerequisites

Complete the supporting setup from [`identity-records-automation.md`](./identity-records-automation.md):

1. Run `pwsh .\scripts\setup_purview_retention_label.ps1` or complete the documented manual fallback.
2. Run `python .\scripts\setup_agent_identity_blueprint.py --output .\agent-identity-blueprint.json` and record the returned `agentIdentityBlueprintId`.
3. Decide how Flow 9 receives that blueprint ID. `provision_solution_shell.ps1` does **not** create a solution environment variable for it, so most teams keep it in a secure custom connector parameter, Azure Key Vault-backed action, or a customer-specific wrapper.
4. Decide whether Flow 12 applies retention labels through a wrapper/API or only logs `fsi_intakeretentionrecord` while table-level Purview auto-labeling does the actual label application.

## 7. Ready-to-build checklist

- [ ] `pac auth who --json` and `pac env who --json` point to the intended environment
- [ ] `FSIAgentIntake` exists as an unmanaged solution shell
- [ ] The `agent-intake` Dataverse tables and global option sets are already deployed
- [ ] All five connection references are bound to working connections
- [ ] All seven solution environment variables have current values
- [ ] Reviewer app URL resolves and reviewer roles are assigned
- [ ] Purview retention label setup is complete
- [ ] Microsoft Entra Agent ID blueprint setup is complete
- [ ] The related design docs were reviewed: `classification-rules.md`, `mrm-integration.md`, `drift-detection-integration.md`, `identity-records-automation.md`, and `maker-form-progressive-disclosure.md`
