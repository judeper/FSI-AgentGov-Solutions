# Lab Validation Report — MIME Type Restrictions for File Uploads

**Solution:** `mime-type-restrictions` · **Version:** v1.2.1 (unreleased)
**Primary controls:** 1.5, 1.13, 1.25, 3.3, 3.7
**Validation date:** 2026-06-04 · **Method:** static (no live tenant) — parse-validity + authoritative-source verification + doc completeness

## Purpose

Zone-based MIME type configuration with server-side validation for Copilot Studio agent file-upload
scenarios. The solution ships a Dataverse pre-validation plugin (`ValidateMimeTypePlugin`), a
connector-classification reference for Power Platform data policies, a zone allowlist
(`mime-config.json`), and Microsoft Sentinel KQL queries / an analytics rule for monitoring. It
helps support FINRA 4511 and SEC 17a-4 recordkeeping and NIST 800-53 SI-3 malicious-code protection;
it does not by itself satisfy any regulation.

## What was checked

| Area | Result |
|------|--------|
| Python unit tests (`tests/test_mime_parser.py`) | **32 passed** (`pytest 9.0.3`, Python 3.12.10) |
| `python -m py_compile` on `tests/*.py` | Clean |
| C# plugin build (`dotnet build … /p:TreatWarningsAsErrors=true`, net462) | **0 warnings, 0 errors** (.NET SDK 9.0.314; net462 targeting pack present) |
| `mime-config.json`, `dlp-policy-template.json`, `high-volume-blocks.json` | Valid JSON; internally consistent |
| Prohibited-language scan (compliance-overclaim phrases, excl. CHANGELOG) | No hits |
| Dataverse column naming | Plugin operates on the OOTB `annotation` table (`documentbody`, `mimetype`, `filename`) — standard logical names, no `fsi_` custom columns; no naming-convention violations |
| Auth guidance | Managed-identity-first; client secret marked legacy/dev-only in `flow-configuration.md` |
| Copilot Studio file-upload claims | Verified against Microsoft Learn (see below); corrected |
| Power Platform DLP behavior claims | Consistent with Learn (connectors, not MIME/extension); `dlp-policy-template.json` correctly marked non-importable |

## Authoritative sources cited

- Allow file input from users — https://learn.microsoft.com/microsoft-copilot-studio/image-input-analysis
- Upload files as a knowledge source — https://learn.microsoft.com/microsoft-copilot-studio/knowledge-add-file-upload
- Copilot Studio quotas and limits — https://learn.microsoft.com/microsoft-copilot-studio/requirements-quotas

## Gaps found and fixes applied

### 1. Documented/tested WebP offset-8 check was not enforced by the plugin (security + script↔doc/test gap) — FIXED
`mime-config.json`, the README, the CHANGELOG, and `tests/test_mime_parser.py` all describe an
offset-8 `WEBP` signature check (bytes 8–11) to defeat RIFF-prefix collisions (a WAV/AVI renamed to
`.webp` and declared `image/webp`). The C# `AllowedType` model ignored the `offsetValidation` object
and only matched the leading `RIFF` prefix, so the check was **not actually enforced server-side**.

Fix (`src/ValidateMimeTypePlugin.cs`):
- Added an `OffsetSignature` model and `AllowedType.OffsetValidation` property bound to the existing
  `offsetValidation` JSON.
- Added a `MatchesAtOffset` helper (fail-secure when the file is shorter than `offset + signature`).
- Added **Step 4a** in `Execute` that validates the secondary signature at the configured offset for
  any allowlist entry that defines `offsetValidation`.
- Rebuilt with `TreatWarningsAsErrors=true` → clean. Behavior now matches the config, README, and the
  existing passing unit tests. CHANGELOG updated under [1.2.1].

### 2. Stale Copilot Studio user-file-input facts (doc accuracy) — FIXED
`docs/flow-configuration.md` claimed user file input supported "CSV, PDF, TXT, JPG, PNG, WebP, or
nonanimated GIF" with limits "15 MB (4 MB for DirectLine-based channels), PDFs under 40 pages, and
TXT/CSV files under 180 KB." Current Microsoft Learn guidance differs:
- Supported user-input types are **DOCX, CSV, PDF, TXT, JPG, PNG, WebP, nonanimated GIF**; **XLSX/PPTX
  are experimental**.
- Individual file size limit is **15 MB**; text content limit is **30,000 characters per file** (no
  limit with code interpreter). The "4 MB DirectLine / 40-page / 180 KB" figures are not in the
  current doc.

Fix: rewrote the user-file-input bullet to match the authoritative page and added the source link.
The knowledge-source bullet (formats, 512 MB, encrypted-file exclusion) was verified accurate and
extended with the "images only when embedded in PDF" and "up to 500 files" facts plus its source link.

### 3. Doc↔plugin consistency for the offset check — FIXED
Added an explicit offset-signature note to the plugin "Magic Byte Consistency" step in
`flow-configuration.md` so the documented validation flow matches the implemented Step 4a.

## Runtime-only caveats (cannot be verified statically)

- **Plugin registration / pre-image.** Correct behavior on `annotation` Update depends on a registered
  `PreImage` (attributes `mimetype, filename`); without it, partial updates are fail-secure-blocked.
  This is documented but only observable in a live Dataverse environment.
- **Sandbox isolation.** The published DLL is not strong-name signed; customers must ILRepack-merge
  `System.Text.Json` and apply their own `.snk` before registration (documented in `build-and-sign.md`).
  Merge/sign success can only be confirmed in a real build/deploy.
- **Sentinel/KQL.** Queries target `PowerPlatformDlpActivity_CL` (or `PowerPlatformAdminActivity`);
  column presence and event population depend on the tenant's diagnostic-settings pipeline.
- **Data policy propagation.** Connector-classification changes can take up to ~24 hours to enforce in
  large tenants.
- **ARM API version.** `high-volume-blocks.json` uses `2023-02-01` for the Sentinel alert rule
  (functional; intentionally not bumped without test-workspace validation, per inline note).

## Lab-readiness assessment

**Lab-ready.** All static checks pass: 32 unit tests green, plugin builds warnings-as-errors clean,
JSON valid, no prohibited compliance language, auth guidance managed-identity-first, and the
Copilot Studio / DLP claims now match current Microsoft Learn. The one material correctness gap (the
unenforced WebP offset-8 check) is fixed and verified by build + existing tests. Remaining items are
inherently runtime-only (plugin registration, sandbox signing, Sentinel ingestion) and are documented
for the deploying administrator.
