# Scripts

This directory contains shared utilities, orchestration scripts, and automation hooks for FSI-AgentGov-Solutions.

## Directory Structure

```
scripts/
├── Invoke-CopilotStudioBenchmark.ps1   # Orchestration: 10-check benchmark runner
├── hooks/                               # Claude Code hooks
│   ├── boundary-check.py                # PreToolUse: project boundary enforcement
│   └── researcher-package-reminder.py   # PostToolUse: pillar edit reminder
└── shared/                              # Shared utilities
    ├── dataverse_client.py              # Shared Dataverse Web API client
    └── Get-ZoneClassification.ps1       # Zone classification utility
```

---

## Invoke-CopilotStudioBenchmark.ps1

Runs 10 Copilot Studio governance benchmark checks in a single loop and produces a unified report (console summary table + JSON evidence file).

### Benchmark Checks

| # | Check | Solution | Controls |
|---|-------|----------|----------|
| 1 | Prevent Unauthorized Agent Actions | action-confirmation-auditor | 1.23 |
| 2 | User-Defined Action Messages | action-confirmation-auditor | 1.23 |
| 3 | Require Users to Sign In (Manual Auth) | session-security-configurator | 1.23, 1.11 |
| 4 | AI Agents Authentication Bypass | agent-access-monitor | 3.8 |
| 5 | Unrestricted Access to AI Agents | unrestricted-agent-sharing-detector | 1.1, 3.8 |
| 6 | AI Agents with File Analysis Enabled | file-upload-security | 1.14, 1.8, 1.4 |
| 7 | AI Agents Using Model Knowledge | generative-ai-config-auditor | 2.24 |
| 8 | AI Agents using Semantic Search | generative-ai-config-auditor | 2.24 |
| 9 | AI Agents with Insufficient Content Moderation | content-moderation-monitor | 1.8, 1.14 |
| 10 | Inter-agent Communication Restricted | agent-communication-restriction-detector | 2.17 |

### Usage

```powershell
# Dry-run (safe preview, no Dataverse writes)
.\scripts\Invoke-CopilotStudioBenchmark.ps1 -WhatIf

# Full run with service principal auth
.\scripts\Invoke-CopilotStudioBenchmark.ps1 `
    -TenantId $tenantId `
    -ClientId $clientId `
    -CertificateThumbprint $thumbprint `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -Zone Zone3

# Skip specific checks
.\scripts\Invoke-CopilotStudioBenchmark.ps1 -SkipChecks @(3, 5) -WhatIf

# Custom output path
.\scripts\Invoke-CopilotStudioBenchmark.ps1 -OutputPath ".\evidence\benchmark.json" -WhatIf
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-TenantId` | No | Microsoft Entra tenant ID |
| `-ClientId` | No | App registration client ID |
| `-CertificateThumbprint` | No | Certificate thumbprint for service principal auth |
| `-DataverseUrl` | No | Dataverse URL for zone classification lookup |
| `-Zone` | No | Governance zone (Zone1/Zone2/Zone3). Default: Zone3 |
| `-ConfigPath` | No | Tenant config JSON (required for session security check) |
| `-OutputPath` | No | JSON report output path. Default: `copilot-benchmark-<timestamp>.json` |
| `-ExcludeSandbox` | No | Exclude sandbox environments |
| `-ExcludeTrial` | No | Exclude trial environments |
| `-GracePeriodHours` | No | Grace period for new environments (default: 48) |
| `-SkipChecks` | No | Array of check numbers (1-10) to skip |
| `-WhatIf` | No | Preview mode — all sub-scripts run in dry-run mode |

### Output

- **Console:** Color-coded summary table with pass/fail status per check
- **JSON:** Structured report with metadata, summary, per-check results, and violation details

---

## Hooks

### boundary-check.py

**Purpose:** Prevents Claude Code from executing Bash commands outside the project directory.

**Trigger:** PreToolUse on Bash commands

**Behavior:**
- Parses the command to detect directory operations
- Blocks commands that attempt to operate outside `/Users/admin/dev/FSI-AgentGov-Solutions` or allowed sibling directories
- Returns JSON decision: `{"decision": "allow"}` or `{"decision": "block", "reason": "..."}`

**Configuration:** Defined in `.claude/settings.json` under `hooks.PreToolUse`

### researcher-package-reminder.py

**Purpose:** Reminds developers to regenerate the researcher package after editing pillar control files.

**Trigger:** PostToolUse on Edit or Write operations

**Behavior:**
- Checks if the edited file is in a pillar controls directory
- If so, emits a reminder to run `python scripts/compile_researcher_package.py`
- Only fires when working from FSI-AgentGov (not FSI-AgentGov-Solutions)

**Configuration:** Defined in `.claude/settings.json` under `hooks.PostToolUse`

---

## Related Documentation

- [Claude Code Hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) - Official documentation
- [FSI-AgentGov CLAUDE.md](https://github.com/judeper/FSI-AgentGov/blob/main/.claude/CLAUDE.md) - Cross-repository workflow guidance

---

*FSI-AgentGov-Solutions - January 2026*
