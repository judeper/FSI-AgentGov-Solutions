# Releasing FSI-AgentGov-Solutions

This document captures the release-time and release-blocking operations for
this repository. It complements `DEPLOYMENT-GUIDE.md` (which is targeted at
adopters / customer admins) and is intended for repository maintainers.

## Tagging a release

1. Confirm `python scripts/build-manifest.py --check` exits 0.
2. Confirm `python scripts/lint-odata-columns.py --strict` exits 0.
3. Update root `CHANGELOG.md` so the topmost section is no longer
   `## [Unreleased]` — change it to `## [vX.Y.Z] - YYYY-MM-DD` with the new
   semver tag.
4. Tag and push:

   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```

5. Publish a GitHub Release pointing at the tag. The `release.yml` workflow
   will attach the source tarball, SBOMs (SPDX + CycloneDX), SHA-256 manifest,
   and build-provenance attestation.
6. Manually trigger the health probe to confirm the new artifacts are
   reachable:

   ```bash
   gh workflow run health-check.yml
   ```

   `LATEST_TAG` is auto-derived from the latest GitHub Release (Issue #39),
   so no workflow edit is required.

## Schema evolution policy

`solutions.json` schemaVersion 1.4.x is **additive-only**. New optional
fields land in 1.4.x point releases. Field renames, new required fields, or
shape changes require **1.5.0** with a coordinated upgrade in
`judeper/fsi-agentgov` (the framework consumes `solutions.json`).

| Bump | When | Coordination required |
|---|---|---|
| 1.4.x patch | Bugfixes that don't touch `solutions.json` | None |
| 1.4.y minor | New optional manifest fields, additive | None (framework reads new fields if present) |
| **1.5.0** | Required fields, renames, shape changes | **Yes** — coordinated PR with `judeper/fsi-agentgov` |

## Schema 1.5.0 unblock procedure (Issue #37)

Schema 1.5.0 will make the `zones` field **required** on every manifest. The
35 current `zones` values were inferred by `scripts/_backfill-zones.py` and
are tagged with the sentinel comment:

```yaml
# zones/dataClassification backfilled by scripts/_backfill-zones.py
# INFERRED from domain/tier/controls — product team must review.
```

Tracking issue: <https://github.com/judeper/FSI-AgentGov-Solutions/issues/37>.

**Status:** Blocked on product-team review. Each `zones` value (and the
related `dataClassification`, `dataResidency`, `retention` fields) needs
human confirmation before we can drop the sentinel and treat the value as
authoritative.

### Step 1 — Product-team review

1. Export the current zone backfills for review:

   ```bash
   python scripts/_backfill-zones.py --print
   ```

   (If the `--print` mode is missing, the canonical map lives in
   `scripts/_backfill-zones.py` `ZONE_MAP`.)

2. The product team reviews each entry against:
   - The solution's actual deployment scope (personal / team / enterprise).
   - The solution's `dataClassification` (`internal` / `confidential` /
     `restricted`) — confirm with privacy / compliance stakeholders for
     anything that handles supervisory or evidence content (FINRA 4511,
     SEC 17a-4, GLBA 501(b)).
   - `dataResidency` (US-only vs multi-region).
   - `retention` (years; align with regulator-mandated minimums).

3. The product team's decision is recorded directly in each
   `manifest.yaml`. Removing the sentinel comment indicates the value is
   confirmed.

### Step 2 — Drop sentinel comments

For each confirmed manifest, delete the two-line sentinel block:

```yaml
# zones/dataClassification backfilled by scripts/_backfill-zones.py
# INFERRED from domain/tier/controls — product team must review.
```

(Do **not** modify the `zones:` block itself unless product-team review
changed the value.)

A helper one-liner if you have many to clear at once:

```bash
for f in */manifest.yaml; do
  python -c "
import sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding='utf-8')
out = '\n'.join(
  ln for ln in s.splitlines()
  if 'backfilled by scripts/_backfill-zones.py' not in ln
  and 'INFERRED from domain/tier/controls' not in ln
)
p.write_text(out + '\n', encoding='utf-8')
" "$f"
done
```

### Step 3 — Open coordinated PRs

Schema 1.5.0 requires a synchronous bump in two repos. Open both PRs at
the same time so they can be merged together:

#### PR A — `judeper/fsi-agentgov` (framework)

- Add a regression test that asserts every solution in `solutions.json` has
  a non-empty `zones` array.
- Update any framework consumers that previously treated `zones` as
  optional to fail fast if missing.
- Bump the framework `controls.json` minor version if needed.

#### PR B — `judeper/FSI-AgentGov-Solutions` (this repo)

- `scripts/manifest.schema.json`: move `zones` from `optional` to
  `required`. Update the `$schema` `description` field to call out the
  required transition.
- `scripts/build-manifest.py`: bump `solutions.json` schemaVersion from
  `1.4.2` to `1.5.0`. Update validation to fail any manifest missing
  `zones`.
- `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`: update the
  schema-evolution policy section to record that `zones` is now required.
- `CHANGELOG.md` (root): add an entry under `[Unreleased]` documenting the
  schemaVersion bump and the required-field change.
- After both PRs merge, tag a new release (`vX.Y.0`) per the procedure
  above. The auto-derived health-check `LATEST_TAG` (Issue #39) picks up
  the new tag on the next scheduled run.

### Step 4 — Close Issue #37

Once schema 1.5.0 is shipped and the health probe confirms the new
artifacts are reachable, close Issue #37 with a comment summarising:

- Which manifests had their `zones` corrected vs. confirmed-as-inferred.
- The PR numbers in both repos.
- Any follow-up issues filed for `dataClassification` / `dataResidency` /
  `retention` rework.

## Rollback

If a release introduces a regression:

1. Tag a `vX.Y.Z+1` patch from the previous-good commit (don't re-tag the
   broken version).
2. Publish the new release; the health probe auto-targets the latest
   release and will confirm recovery.
3. File a regression issue tracking the root cause; do **not** delete the
   bad tag (audit trail).

## Related

- `DEPLOYMENT-GUIDE.md` — adopter-facing deployment guidance, includes the
  "Post-Release Operations" section for the health-probe checklist.
- `SECURITY.md` — vulnerability disclosure and supported-version policy.
- `THREAT-MODEL.md` — STRIDE-by-asset threat model and trust boundaries.
- `.github/workflows/release.yml` — SBOM + provenance attestation builder.
- `.github/workflows/health-check.yml` — published-artifact health probe.
