# Claude Code Configuration

This directory contains Claude Code configuration for FSI-AgentGov-Solutions.

## Files

| File | Purpose | Committed |
|------|---------|-----------|
| `settings.json` | Team-shared settings (hooks, permissions) | Yes |
| `settings.local.json` | Local overrides (personal preferences) | No (.gitignore) |

---

## settings.json

Defines team-shared Claude Code behavior:

**Permissions:**
- Allows git, Python, and pip commands
- Allows Read, Glob, Grep tools
- Denies destructive commands (`rm -rf /`)

**Hooks:**
- **PreToolUse (Bash):** Runs `boundary-check.py` to enforce project directory limits
- **PostToolUse (Edit|Write):** Runs `researcher-package-reminder.py` for pillar edit reminders

---

## settings.local.json

Contains local overrides not committed to version control:
- WebFetch domain allowlists
- Personal API tokens (if any)
- Local path configurations

**Note:** Never commit secrets or personal credentials to this file. Use environment variables or secure vaults for sensitive values.

---

## Cross-Repository Context

When working across FSI-AgentGov and FSI-AgentGov-Solutions:

1. **Hooks only fire in the working directory repo** - `boundary-check.py` applies to the current repo
2. **Read/Write/Edit tools work cross-repo** - No restrictions on file access
3. **Git operations require `cd`** - Each repo has separate git history

See [FSI-AgentGov CLAUDE.md](https://github.com/judeper/FSI-AgentGov/blob/main/.claude/CLAUDE.md) for the full cross-repository workflow.

---

*FSI-AgentGov-Solutions - January 2026*
