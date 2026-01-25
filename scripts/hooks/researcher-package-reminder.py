#!/usr/bin/env python3
"""
Claude Code PostToolUse Hook: Researcher Package Reminder

This is a passthrough stub for FSI-AgentGov-Solutions.
The researcher package reminder is not applicable to this repository.
"""

import sys
import json


def main():
    """Main hook entry point - passthrough, no action needed."""
    try:
        # Read and discard input
        sys.stdin.read()
        # Output empty response (no reminder needed)
        print(json.dumps({}))
    except Exception:
        # On any error, output empty response
        print(json.dumps({}))


if __name__ == "__main__":
    main()
