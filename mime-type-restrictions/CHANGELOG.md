# Changelog

All notable changes to MIME Type Restrictions for File Uploads are documented here.

## [1.2.0] — Unreleased — CI build, CodeQL, signed binary release (#38)

### Added

- **`src/ValidateMimeTypePlugin.csproj`** — SDK-style csproj targeting
  .NET Framework 4.6.2 with explicit `Microsoft.CrmSdk.CoreAssemblies` 9.0.2.59
  and `System.Text.Json` 8.0.5 package references. Supports both unsigned
  CI builds and strong-name-signed local production builds (see
  `docs/build-and-sign.md`).
- **`src/.gitignore`** — excludes build outputs (`bin/`, `obj/`), strong-name
  keys (`*.snk`, `*.pfx`), local NuGet artifacts, and cosign signing
  artifacts (`*.sig`, `*.cert`, `*.bundle`).
- **`docs/build-and-sign.md`** — full build / sign / verify guide:
  - Local CI parity build (unsigned, validates compilability)
  - Local production build (strong-name + ILRepack merge)
  - Customer verification of published DLL via SHA-256, cosign Sigstore
    bundle, cosign legacy signature/cert split, and GitHub build
    provenance attestation
  - Trust boundary notes distinguishing cosign signing from strong-name
    signing
- **`.github/workflows/ci-dotnet.yml`** (new repo-level workflow) —
  Debug and Release builds on `windows-latest` for every push/PR touching
  `mime-type-restrictions/src/**` or the workflow file itself. Soft-gate
  while baseline cleanup lands.
- **CodeQL `csharp` analysis** — `.github/workflows/codeql.yml` now
  analyses both Python (Linux) and C# (Windows). The C# job restores
  packages and builds the plugin before invoking CodeQL.
- **Signed plugin binary in releases** — `.github/workflows/release.yml`
  gained a `build-plugin` job that builds, hashes, and **cosign keyless
  signs** (Sigstore OIDC) the plugin DLL on every tagged release. The DLL,
  hash, signature, certificate, and Sigstore bundle are attached to the
  GitHub Release alongside the existing source tarball + SBOMs +
  build-provenance attestation.

### Changed

- Version bumped to **1.2.0** to reflect the new CI/release surface
  (no behavior change in the plugin itself).

## [1.1.0] — 2026-04-17 — BREAKING (control-coverage scope reduction)

### Changed (BREAKING)

- **Primary controls reduced** from 9 to 5. The solution previously claimed
  controls 1.10 (Communication Compliance), 1.11 (Conditional Access /
  MFA), 1.14 (Content Moderation Enforcement) and 4.3 (SharePoint
  Oversharing Prevention) — none of which are actually implemented by
  this artifact set. Removed those over-claims from the README. Retained
  primary controls: **1.5, 1.13, 1.25, 3.3, 3.7**.

### Added

- **Plugin: hard-deny denylist for executable / script extensions** —
  `.ps1`, `.bat`, `.cmd`, `.exe`, `.js`, `.vbs`, `.jar`, `.py`, `.sh`
  and ~25 others are blocked regardless of declared MIME type. Closes a
  bypass where a script file declared as `text/plain` would have passed
  the allowlist + binary-content check.
- **Plugin: filename-extension-vs-MIME-type cross-check** — the
  declared MIME type's allowlist entry now constrains which filename
  extensions are permitted, catching mislabeled files even when the
  MIME type itself is allow-listed.
- **Plugin: subtype-aware OpenXML inspection** — `wordprocessingml`,
  `spreadsheetml` and `presentationml` MIME types now require the
  corresponding `word/`, `xl/` or `ppt/` package directory inside the
  ZIP (in addition to `[Content_Types].xml`). A bare ZIP that only
  contains `[Content_Types].xml` no longer satisfies the check.
- **Flow doc:** Pre-Image registration is now an explicit, required
  step. Without a `PreImage` (mimetype + filename) on the Update step,
  partial updates that omit those columns are fail-secure-blocked by
  the plugin.
- **Delivery checklist:** matching Pre-Image entry added to the plugin
  registration checklist.

### Fixed

- **DLP template clarified as conceptual, not deployable.** The file
  `templates/dlp-policy-template.json` previously appeared importable
  via `New-AdminDlpPolicy`. It is now prominently marked as a
  reference document — Power Platform DLP cannot enforce extension or
  MIME-type rules directly; it only classifies connectors. The flow
  doc's "Step 3" was rewritten to translate the reference into
  connector classifications via the admin center / Set-DlpPolicy.
- **Removed fictional PAC CLI commands.** `pac plugin push` and
  `pac plugin step create` do not exist in any current PAC CLI release.
  The "Step 2 (Alternative)" section now redirects users to the
  Plugin Registration Tool (PRT) and `pac solution import` for CI/CD.

### Notes

- Council review (April 2026) findings closed for this solution.

---

## [1.0.2] — 2026-04-10

### Changed
- Restructured solution to follow standard layout
- Moved documentation from root and src/ to docs/
- Moved KQL queries to scripts/
- Moved JSON templates to templates/
- Retained C# plugin source code in src/

## [1.0.1] — 2026-02-20

### Fixed
- Standardized KQL field names in `high-volume-blocks.json` alert rule to use `OperationType_s`/`ActionTaken_s` (matching KQL queries)
- Fixed enforcement mode trace message in `ValidateMimeTypePlugin.cs` — now shows actual mode instead of hardcoded "LogOnly"
- Corrected alert frequency documentation from "Every 5 minutes" to "Every 1 hour" (matching actual PT1H)
- Corrected MITRE ATT&CK reference from T1566.001 to T1566 + T1204 (matching alert rule JSON)

### Added
- Rollback procedure in SOLUTION-DOCUMENTATION.md (3 options: disable step, change mode, unregister)
- PAC CLI deployment commands as alternative to Plugin Registration Tool
- Design decisions section documenting intentional exclusions (legacy Office, SVG, rate limiting)
- PowerShell module (FsiMimeControl) documentation in SOLUTION-DOCUMENTATION.md, README.md, and DELIVERY-CHECKLIST.md

## [1.0.0] — 2026-02-01

### Added
- Dataverse plugin (`ValidateMimeTypePlugin.cs`) for server-side MIME type validation
- DLP policy template (`dlp-policy-template.json`) for policy-based MIME restrictions
- MIME configuration file (`MimeConfig.json`) for allowlist/blocklist management
- Sentinel query (`query-mime-blocks.kql`) for blocked MIME type event monitoring
- Sentinel alert rule (`high-volume-blocks.json`) for high-volume block pattern detection
- Sentinel query (`query-exception-usage.kql`) for exception usage tracking
- All 6 artifacts migrated from FSI-AgentGov `src/` to FSI-AgentGov-Solutions
