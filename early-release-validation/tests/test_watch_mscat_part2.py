"""Unit tests for the MSCAT Part 2 watch matcher (JudeSquad #1431).

Loads the sibling ``scripts/watch_mscat_part2.py`` by path so the test works
under the repo-wide ``pytest --import-mode=importlib`` run without packaging.
"""
import importlib.util
import pathlib

_SCRIPT = (
    pathlib.Path(__file__).resolve().parents[1] / "scripts" / "watch_mscat_part2.py"
)
_spec = importlib.util.spec_from_file_location("watch_mscat_part2", _SCRIPT)
watch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(watch)


def test_matches_part2_kebab():
    posts = [
        "2026-05-20-alm-copilot-studio-agents-foundation.md",
        "2026-08-01-building-enterprise-ai-solutions-part-2.md",
    ]
    assert (
        watch.find_part2(posts)
        == "2026-08-01-building-enterprise-ai-solutions-part-2.md"
    )


def test_matches_part2_no_separator():
    posts = ["2026-08-01-enterprise-ai-solutions-part2.md"]
    assert watch.find_part2(posts) == posts[0]


def test_matches_part_two_word():
    posts = ["2026-09-01-building-enterprise-ai-solutions-part-two.md"]
    assert watch.find_part2(posts) == posts[0]


def test_ignores_part1():
    posts = ["2026-07-01-building-enterprise-ai-solutions-part-1.md"]
    assert watch.find_part2(posts) is None


def test_ignores_unrelated_posts():
    posts = [
        "2026-05-20-alm-copilot-studio-agents-foundation.md",
        "2026-06-15-modern-mcs-agent-skills.md",
    ]
    assert watch.find_part2(posts) is None


def test_does_not_match_part_20_or_year():
    posts = ["2026-01-01-enterprise-ai-solutions-part-2024-recap.md"]
    assert watch.find_part2(posts) is None


def test_empty_input():
    assert watch.find_part2([]) is None
