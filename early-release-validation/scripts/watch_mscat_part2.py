#!/usr/bin/env python3
"""Detect publication of MSCAT "Building Enterprise AI Solutions" Part 2.

Part 2 specifies the early-release-ring environment-variable schema and ring URL
that ``create_erv_environment_variables.py`` and Check 4
(``EarlyReleaseReadinessCheck``) depend on. Until it publishes, those ship as
fail-closed stubs. This helper lets ``.github/workflows/mscat-part2-watch.yml``
self-surface the dependency instead of relying on manual polling / nudges.
Tracking: JudeSquad #1266 / #1431.

Reads MS Copilot Studio CAT blog ``_posts`` filenames (one per line) on stdin and
prints the first filename that names Part 2 of the series, or nothing. The match
logic is a pure function so it is unit-tested (``tests/test_watch_mscat_part2.py``)
without any network access.
"""
from __future__ import annotations

import os
import re
import sys

# Series signal + a "part 2" token. Both are overridable via environment so the
# watch can be tuned in one place if the published post's slug differs from the
# expected wording (e.g. spelled "part two" or a different series phrasing).
DEFAULT_SERIES_REGEX = r"enterprise[-_ ]?ai|building[-_ ]?enterprise"
DEFAULT_PART2_REGEX = r"part[-_ ]?(2|two)\b"


def find_part2(filenames, series_regex=DEFAULT_SERIES_REGEX,
               part2_regex=DEFAULT_PART2_REGEX):
    """Return the first filename that names Part 2 of the series, else ``None``.

    A filename matches when it contains both the series signal and a whole-token
    "part 2" marker. Part 1 (and false tokens like ``part-2024``) are excluded by
    the word boundary in the part-2 pattern.
    """
    series = re.compile(series_regex, re.IGNORECASE)
    part2 = re.compile(part2_regex, re.IGNORECASE)
    for name in filenames:
        if name and series.search(name) and part2.search(name):
            return name.strip()
    return None


def main():
    series_regex = os.environ.get("SERIES_REGEX", DEFAULT_SERIES_REGEX)
    part2_regex = os.environ.get("PART2_REGEX", DEFAULT_PART2_REGEX)
    names = [line.strip() for line in sys.stdin if line.strip()]
    match = find_part2(names, series_regex, part2_regex)
    if match:
        print(match)
    return 0


if __name__ == "__main__":
    sys.exit(main())
