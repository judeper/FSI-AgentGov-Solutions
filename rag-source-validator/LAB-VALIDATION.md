# Lab Validation Report — RAG Source Validator

> **Solution:** rag-source-validator · **Version:** v1.3.1 (Unreleased doc fixes)
> **Controls:** 2.16 (RAG Source Integrity Validation), 1.7 (Comprehensive Audit Logging), 2.13 (Documentation and Record-Keeping)
> **Validation date:** 2026-06-04 · **Mode:** Static (no live tenant) — parse-validity, authoritative-source verification, doc completeness.

## Purpose

Integrity validation for Retrieval-Augmented Generation (RAG) knowledge sources used by Copilot Studio / Agent Builder agents. The solution computes SHA-256 content hashes for registered knowledge sources, compares against a stored baseline to detect unauthorized changes, records validation history and change audit trails in Dataverse, and exports tamper-evident evidence packages. Supports compliance with SEC Rule 17a-4 (record integrity), FINRA Rule 4511(a) (books and records accuracy), and SOX Section 404 (internal controls over data integrity).

## Scope checked

| Area | What was verified |
|------|-------------------|
| Python scripts | `create_rsv_dataverse_schema.py`, `create_rsv_connection_references.py`, `create_rsv_environment_variables.py` — `py_compile` clean; argparse auth-mode surface (`managed-identity`, `workload-identity`, `certificate`, `access-token`, `interactive`, `client-secret`) matches the shared `dataverse_client.py` contract |
| PowerShell scripts | `Invoke-SourceValidation.ps1`, `governance/Export-ValidationEvidence.ps1`, `governance/Get-SourceValidationSummary.ps1`, `governance/Test-EvidenceIntegrity.ps1` — `Parser::ParseFile` zero errors |
| Dataverse column names | All OData `$select`/`$filter` references in scripts cross-checked against `create_rsv_dataverse_schema.py` (source of truth) and `docs/dataverse-schema.md` — logical names lowercase, no inter-word underscores, consistent |
| Option-set values | Compact 1–N values (e.g. `fsi_RSV_sourcetype` 1–13, `fsi_RSV_validationresult` 1–8) are intentional and consistent across schema script, PowerShell integer literals, and docs — confirmed by `.ralph-config.json` domain facts |
| Authentication | Managed-identity-first; IMDS / App Service MSI endpoints and API versions verified; client-secret path marked `# legacy: dev-only` |
| Sovereign-cloud parity | Graph/Auth/Dataverse endpoint triples cross-validated in-script; China endpoints aligned on `login.chinacloudapi.cn` (prior council fix M1) |
| Language rules | grep for the four banned compliance-overclaim phrases across `*.md`/`*.ps1`/`*.py` (excluding CHANGELOG history) — zero hits |

## Authoritative sources cited

1. **Copilot Studio supported knowledge sources** — Public website, Documents (uploaded to Dataverse), SharePoint, Dataverse, Enterprise data via Microsoft Copilot connectors (Microsoft Search). Confirms the README source-type taxonomy. <https://learn.microsoft.com/microsoft-copilot-studio/knowledge-copilot-studio#supported-knowledge-sources>
2. **Unstructured data as a knowledge source** — SharePoint/OneDrive files and folders; Dataverse stores uploaded files and semantic/vector indexes. <https://learn.microsoft.com/microsoft-copilot-studio/knowledge-unstructured-data>
3. **Get driveItem content (Microsoft Graph)** — Downloading `driveItem` primary stream requires a Graph permission such as `Files.Read.All` or `Sites.Read.All`. Basis for the corrected Permissions table. <https://learn.microsoft.com/graph/api/driveitem-get-content>
4. **Use delta query to track changes (Microsoft Graph)** — Validates the README change-detection guidance (delta links, eTag/cTag, `lastModifiedDateTime`). <https://learn.microsoft.com/graph/delta-query-overview>
5. **Azure Instance Metadata Service / managed identity token acquisition** — Confirms IMDS endpoint `http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=...` and App Service `IDENTITY_ENDPOINT` + `X-IDENTITY-HEADER` with `api-version=2019-08-01`, both used by the scripts. <https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service>
6. **Dataverse application user + security role (server-to-server)** — The managed identity must be a Dataverse application user mapped to a security role to read/write tables. <https://learn.microsoft.com/power-apps/developer/data-platform/use-multi-tenant-server-server-authentication#create-an-application-user-associated-with-the-registered-application-in-dataverse>

## Gaps found and fixed

| # | Severity | Gap | Fix |
|---|----------|-----|-----|
| 1 | Minor (docs) | README Licensing table listed **"Power Platform Premium — Validation flows"**; the solution ships no Power Automate flows (it is script-based, run on Azure compute). Misleading prerequisite. | Replaced the row with the actual requirements: Dataverse capacity (registry + uploaded-document storage) and Azure compute (Automation / Functions / VM) hosting the script via managed identity. Added an explicit "no flows / no canvas apps" statement. `README.md` |
| 2 | Minor (docs) | Permissions table named only vague roles (`SharePoint Reader`, `Dataverse Reader`, `Storage Blob Reader`) and omitted the concrete Microsoft Graph application permission the managed identity needs to read `driveItem` content — a real prerequisite given the managed-identity-first design. | Rewrote the Permissions table around managed identity with citation-backed grants: Graph `Sites.Read.All`/`Files.Read.All`, a Dataverse application user with a security role on the three RSV tables, and `Storage Blob Data Reader` for the optional blob path. `README.md` |
| 3 | Trivial (consistency) | Deployment step 2 and the Troubleshooting authentication row referenced generic "Graph permissions" / "SharePoint Reader and Dataverse Reader roles," inconsistent with the corrected Permissions section. | Aligned both to the concrete permission names. `README.md` |

No script logic, schema, option-set, or column changes were required — the code paths and Dataverse references were already correct and internally consistent (the solution has been through three prior council reviews; see CHANGELOG v1.2.0/v1.3.0/v1.3.1).

## Runtime-only caveats (cannot be verified statically)

- **No live tenant:** Token acquisition (IMDS/App Service MSI, client-secret), actual Graph `driveItem` downloads, and Dataverse Web API reads/writes were not executed. Endpoint shapes and permission names are verified against Microsoft Learn but not exercised end-to-end.
- **Planned source types:** Only SharePoint Document Library (type 1) content validation is implemented; types 2–13 are registered in schema and correctly return `Skipped - Not Implemented` (result 7) or `Unsupported Type` (8). README labels these "Planned" accurately.
- **Trust-on-first-use baseline:** First-run baseline capture trusts current content; documented as a limitation. Operators must verify source integrity out-of-band.
- **WORM/immutability:** Validation results are stored in mutable Dataverse records; full SEC Rule 17a-4 WORM compliance requires an external immutable store. Documented in README.
- **No automated tests:** `Invoke-SourceValidation.ps1` has no unit-test coverage (documented limitation).
- **Schema package:** No managed/unmanaged solution `.zip` ships; schema is deployed via `create_rsv_dataverse_schema.py` or manual table creation (documented).

## Lab-readiness assessment

**Lab-ready.** The solution parses cleanly (Python + PowerShell), uses managed-identity-first authentication with correct IMDS/Graph/Dataverse endpoints and token audiences, references Dataverse columns and option-set values consistently with its schema source of truth, and honors the FSI language rules. The two documentation gaps that could block a first-time lab deployment — an inaccurate licensing prerequisite and missing concrete identity permissions — are now corrected and citation-backed. Remaining caveats are runtime-only or already-documented design limitations, none of which prevent a lab installation.
