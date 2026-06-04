# Lab Validation Report — Pipeline Governance Cleanup

**Solution version:** v1.2.1
**Validation date:** 2026-06-04
**Validation type:** Static (no live tenant) — parse-validity, authoritative-source verification, doc completeness
**Primary controls:** 2.3 (ALM governance), 2.1 (environment governance)

## Purpose

Discover, notify, and clean up personal Power Platform deployment pipelines before
enforcing centralized ALM governance on a custom pipelines host. The solution is
intentionally PowerShell + manual-guidance only; force-linking environments to a
custom host requires UI interaction in the Deployment Pipeline Configuration app and
cannot be automated.

## What was checked

- Three PowerShell scripts (`Get-PipelineInventory.ps1`, `Send-OwnerNotifications.ps1`,
  `Set-GovernanceConfig.ps1`) — parse validity and command/API correctness.
- All documented `pac` CLI commands and parameters against the authoritative
  Microsoft Learn CLI reference.
- The Dataverse pipeline-table schema documented in `README.md` (table names,
  logical column names, option-set values) against the authoritative pipeline
  table reference.
- Documentation completeness (README Purpose/Prerequisites/Steps/Outcomes),
  script↔doc consistency, FSI language rules, and the known column-name and
  version-banner inconsistencies recorded in `.ralph-config.json`.

## Authoritative sources cited

| Topic | URL |
|-------|-----|
| Pipeline table reference (deploymentpipeline / deploymentstage / deploymentenvironment, option sets) | https://learn.microsoft.com/power-platform/developer/pipelines/table-reference |
| `pac admin` reference (set-governance-config, admin list) | https://learn.microsoft.com/power-platform/developer/cli/reference/admin |
| `pac pipeline` reference (pipeline list/deploy, `--environment`) | https://learn.microsoft.com/power-platform/developer/cli/reference/pipeline |
| `pac auth` reference (`auth who`, `auth create --managedIdentity`) | https://learn.microsoft.com/power-platform/developer/cli/reference/auth |
| Overview of pipelines in Power Platform | https://learn.microsoft.com/power-platform/alm/pipelines |
| Managed Environments overview | https://learn.microsoft.com/power-platform/admin/managed-environment-overview |

## Verified correct (no change required)

- **Dataverse schema (README).** `deploymentpipeline`, `deploymentstage`,
  `deploymentenvironment` table names, logical column names (including
  `previousdeploymentstageid`, `targetdeploymentenvironmentid`), and option-set
  values match the authoritative table reference exactly:
  `EnvironmentType` 200000000/200000001, `ValidationStatus`
  200000000/200000001/200000002, `statuscode` 1/2.
- **`pac admin list --json`** — valid; used by `Get-PipelineInventory.ps1`.
- **`pac pipeline list --environment`** — valid; `pac pipeline list` does not
  support `--json`, so the script's text-parsing approach and its "directional
  only" caveat are accurate.
- **`pac auth who`** and **`pac auth create --managedIdentity`** — valid flags.
- **`Send-OwnerNotifications.ps1`** Microsoft Graph usage (`Send-MgUserMail` with
  resolved sender, `Mail.Send` scope, transient-retry on HTTP status + Retry-After)
  is consistent with current Graph PowerShell behavior.

## Gaps found and fixed

### Scripts

1. **CRITICAL — `Set-GovernanceConfig.ps1` would always fail.** The script built
   `pac admin set-governance-config` **without** the required `--protection-level`
   parameter and appended two parameters that do not exist in the current `pac`
   CLI: `--disable-unmanaged-customizations` and `--enable-pipelines`. Fixed by
   adding a `-ProtectionLevel` parameter (Standard/Basic, default Standard → maps
   to the required `--protection-level`), adding `none` to the solution-checker
   set, and removing the two invalid switches.
2. **`Set-GovernanceConfig.ps1` verification step used a non-existent command**
   (`pac admin governance-config get`). Replaced with Power Platform Admin Center
   verification guidance (no `pac` governance-config read command exists).
3. **Version-banner drift.** `Get-PipelineInventory.ps1` (1.2.0) and
   `Send-OwnerNotifications.ps1` (1.1.0) banners lagged the manifest; both set to
   1.2.1.

### Documentation

4. **`docs/automation-guide.md`** propagated the invalid `-EnablePipelines` /
   `-DisableUnmanagedCustomizations` examples, an invalid flags table, and the
   non-existent `pac admin governance-config get` verification command. Rewritten
   to the supported parameter set with a scope note clarifying that deployment
   pipelines are enabled by installing the Power Platform Pipelines app and
   configuring a host environment, not by `set-governance-config`.
5. **`README.md`** optional `PipelineCleanupLog` table listed `scheduledremovaldate`
   while the notification templates and automation guide use `enforcementdate`.
   Reconciled to `enforcementdate`.

### Dependencies / prerequisites

- No dependency changes required. Prerequisites (Power Platform Admin, Deployment
  Pipeline Administrator role, PAC CLI, Microsoft Graph `Mail.Send` /
  `User.Read.All`, Power Platform Pipelines app on a custom host) are documented
  and accurate. `Send-OwnerNotifications.ps1` declares its Graph module
  dependencies via `#Requires -Modules`.

## Runtime-only caveats (cannot be verified statically)

- Actual `pac admin set-governance-config` execution requires a Power Platform
  Admin profile and a live tenant; only command shape was validated here.
- Pipeline detection via `pac pipeline list` text parsing is directional; manual
  validation in the Deployment Pipeline Configuration app remains required before
  enforcement, as documented.
- Microsoft Graph mail send (delegated or application) requires tenant consent and
  a mailbox; only code paths and parameters were validated.
- The Feb 2026 Managed Environment auto-enablement behavior for pipeline targets is
  a platform rollout; verify current state in-tenant before force-linking.

## Lab-readiness assessment

**Lab-ready.** The one blocking correctness defect (`Set-GovernanceConfig.ps1`
invalid/missing `pac` parameters) is fixed and the documentation now matches the
supported CLI surface. All three scripts parse cleanly, all documented `pac`
commands/parameters and the Dataverse schema are confirmed against authoritative
Microsoft Learn references, and FSI language rules pass. Remaining items are
inherently runtime/tenant-dependent and are clearly documented as manual steps.
