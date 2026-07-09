#!/usr/bin/env python3
"""
Renderer: cost-fact dataset -> self-contained HTML evidence report.

Renders templates/report.html.j2 with Jinja2 into a single offline HTML file (no CDN, inline
SVG charts). Computes the executive aggregates, the source-authority matrix, per-surface freshness,
and embeds the dataset SHA-256. Output ordering is deterministic for diffability.

The HTML is a rendered evidence package, not the sole record -- it is meant to be archived together
with the dataset, the manifest, and the raw extracts (see package_evidence.py).
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
import cost_report_lib as lib  # noqa: E402

logger = logging.getLogger(__name__)

DISCLAIMER = (
    "Per-agent end-to-end USD is not fully attributable through supported public APIs at the time of "
    "report generation. Any per-agent cost shown is partial, heuristic, or based on a manual export "
    "where explicitly labeled. This report supports compliance with applicable regulatory requirements; "
    "it does not by itself establish regulatory compliance, and organizations should verify it against "
    "their specific obligations."
)

CONFIDENCE_BADGE = {
    "authoritative_api": ("authoritative-api", "green"),
    "authoritative_admin_export": ("authoritative-api", "green"),
    "supplementary_audit": ("supplementary-audit", "amber"),
    "heuristic_join": ("heuristic", "amber"),
    "manual": ("manual-export", "red"),
}


def inline_svg_bar_chart(pairs: list, width: int = 480, bar_height: int = 22) -> str:
    """Return a minimal inline SVG horizontal bar chart (no external dependency)."""
    if not pairs:
        return "<p>No monetary data.</p>"
    max_val = max((v for _, v in pairs), default=0) or 1
    rows = []
    y = 0
    for label, value in pairs:
        bar_w = int((value / max_val) * (width - 160))
        rows.append(
            f'<g transform="translate(0,{y})">'
            f'<text x="0" y="{bar_height - 7}" font-size="12">{label}</text>'
            f'<rect x="150" y="2" width="{bar_w}" height="{bar_height - 6}" fill="#0078D4"></rect>'
            f'<text x="{155 + bar_w}" y="{bar_height - 7}" font-size="11">{value:,.2f}</text>'
            f"</g>"
        )
        y += bar_height
    return f'<svg width="{width}" height="{y}" role="img">{"".join(rows)}</svg>'


def compute_view(facts: list) -> dict:
    """Compute the aggregates and tables the template renders."""
    cost_by_surface = defaultdict(float)
    usage_by_surface = defaultdict(int)
    unresolved = 0
    for fact in facts:
        if fact.get("fact_type") == "azure_cost" and fact.get("amount") is not None:
            cost_by_surface[fact["source_surface"]] += float(fact["amount"])
        elif fact.get("quantity") is not None:
            usage_by_surface[fact["source_surface"]] += 1
        if fact.get("attribution_status") in {"heuristic", "unattributable"}:
            unresolved += 1
    cost_pairs = sorted(cost_by_surface.items(), key=lambda kv: kv[0])
    return {
        "total_cost": round(sum(cost_by_surface.values()), 2),
        "cost_by_surface": dict(cost_pairs),
        "usage_by_surface": dict(sorted(usage_by_surface.items())),
        "unresolved_attribution_count": unresolved,
        "cost_chart_svg": inline_svg_bar_chart([(k, v) for k, v in cost_pairs]),
        "row_count": len(facts),
    }


def render(facts: list, manifest: dict, template_dir: str) -> str:
    """Render the HTML report string."""
    from jinja2 import Environment, FileSystemLoader, select_autoescape

    env = Environment(
        loader=FileSystemLoader(template_dir),
        autoescape=select_autoescape(["html", "j2"]),
        trim_blocks=True,
        lstrip_blocks=True,
    )
    template = env.get_template("report.html.j2")
    view = compute_view(facts)
    return template.render(
        manifest=manifest,
        view=view,
        facts=facts,
        disclaimer=DISCLAIMER,
        badge_map=CONFIDENCE_BADGE,
    )


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cost-facts", required=True, help="Path to cost_facts.jsonl.")
    parser.add_argument("--manifest", required=True, help="Path to the report manifest JSON.")
    parser.add_argument("--out", required=True, help="Path to write report.html.")
    parser.add_argument(
        "--template-dir",
        default=os.path.join(os.path.dirname(__file__), "..", "..", "templates"),
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    with open(args.cost_facts, encoding="utf-8") as handle:
        facts = [json.loads(line) for line in handle if line.strip()]
    with open(args.manifest, encoding="utf-8") as handle:
        manifest = json.load(handle)

    html = render(facts, manifest, os.path.abspath(args.template_dir))
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(html)
    logger.info("Rendered evidence report (%d facts) -> %s (sha256=%s)", len(facts), args.out, lib.sha256_file(args.out)[:12])
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
