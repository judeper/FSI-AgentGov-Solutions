#!/usr/bin/env python3
"""
Evidence packager: assemble the immutable evidence package.

Bundles the four artifacts that constitute one point-in-time evidence record and computes their
hashes:
  * report.html          -- the rendered report
  * cost_facts.jsonl     -- the normalized dataset
  * manifest.json        -- the provenance/integrity manifest (report_manifest.schema.json)
  * sha256.txt           -- newline-delimited 'sha256  filename' lines

The packager also (re)writes manifest.json with per-artifact hashes so the manifest is
self-describing. The package is intended for immutable / WORM-capable storage. The raw extracts
should be retained alongside it.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
import cost_report_lib as lib  # noqa: E402

logger = logging.getLogger(__name__)


def package(package_dir: str, manifest: dict, artifact_names: list) -> dict:
    """Hash each artifact, update the manifest, and write manifest.json + sha256.txt."""
    artifacts = []
    sha_lines = []
    for name in sorted(artifact_names):
        path = os.path.join(package_dir, name)
        if not os.path.exists(path):
            logger.warning("Artifact not found, skipping: %s", name)
            continue
        digest = lib.sha256_file(path)
        artifacts.append({"filename": name, "sha256": digest, "bytes": os.path.getsize(path)})
        sha_lines.append(f"{digest}  {name}")

    manifest["artifacts"] = artifacts
    manifest_path = os.path.join(package_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
    # Hash the manifest itself last and append.
    manifest_digest = lib.sha256_file(manifest_path)
    sha_lines.append(f"{manifest_digest}  manifest.json")
    with open(os.path.join(package_dir, "sha256.txt"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(sorted(sha_lines)) + "\n")
    return manifest


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-dir", required=True, help="Directory containing the artifacts.")
    parser.add_argument("--manifest", required=True, help="Path to the in-progress manifest JSON.")
    parser.add_argument(
        "--artifacts",
        default="report.html,cost_facts.jsonl,cost_facts.csv",
        help="Comma-separated artifact filenames to include (besides manifest.json).",
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    with open(args.manifest, encoding="utf-8") as handle:
        manifest = json.load(handle)
    names = [n.strip() for n in args.artifacts.split(",") if n.strip()]
    package(args.package_dir, manifest, names)
    logger.info("Evidence package written to %s (manifest.json + sha256.txt).", args.package_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
