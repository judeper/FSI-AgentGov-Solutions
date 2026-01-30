#!/usr/bin/env python3
"""
Boundary check hook for pipeline-governance-cleanup.
Simple pass-through since this is a standalone solution repository.
"""

import json
import sys

def main():
    # Allow all commands in this repository
    print(json.dumps({"decision": "allow"}))
    sys.exit(0)

if __name__ == "__main__":
    main()
