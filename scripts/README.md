# Scripts

This directory contains shared utilities and automation scripts for FSI-AgentGov-Solutions.

## Directory Structure

```
scripts/
└── hooks/                    # Claude Code hooks
    ├── boundary-check.py     # PreToolUse: project boundary enforcement
    └── researcher-package-reminder.py  # PostToolUse: pillar edit reminder
```

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
