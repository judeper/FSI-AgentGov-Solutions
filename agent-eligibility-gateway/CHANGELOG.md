# Agent Eligibility Gateway - Changelog

All notable changes to the Agent Eligibility Gateway solution are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0-preview] - 2026-06-09

Initial preview scaffold. This solution is **optional** and applies only to
**owned custom-web and Direct Line agent channels**; first-party Teams, Microsoft 365
Copilot, and SharePoint surfaces cannot host middleware and are out of scope for the
runtime gateway (they rely on native sharing controls plus telemetry drift detection).

### Added

- **Solution scaffold** — `README.md`, `manifest.yaml` (schema 1.5.0; `status: preview`,
  `tier: 3`, controls `1.1`, `1.18`, `3.8`, zone `enterprise`), and this changelog.
- **Architecture documentation** (`docs/architecture.md`) — the two runtime paths
  (owned-channel gateway path and first-party native-control path) and a control-layer
  summary describing where the gateway provides a hard allow/deny versus where native
  Managed Environment sharing applies.
- **Prerequisites** (`docs/prerequisites.md`) — Azure API Management, the gateway Entra
  app registration, the audience/Viewers security groups, and the managed-identity grant
  the gateway uses to read the governance store.
- **APIM gateway setup guide** (`docs/apim-gateway-setup.md`) — step-by-step build of the
  API Management instance, named values, JWT validation, and the eligibility allow/deny
  policy, plus the reference-gateway-first (non-production) validation approach.
- **APIM policy fragments** (`templates/apim-validate-jwt.policy.xml`,
  `templates/apim-eligibility-check.policy.xml`) — Azure infrastructure XML (not Power
  Platform flow artifacts). `validate-jwt` checks tokens against the tenant OpenID
  configuration; the eligibility policy applies the corrected switch-on-pathway
  entitlement contract with a required-claims group check and a managed-identity lookup
  against the governance store, emitting structured per-decision telemetry.
- **Decision-log Dataverse schema** (`scripts/create_aeg_dataverse_schema.py`) — creates
  the optional `fsi_aegdecisionlog` per-decision audit table; supports `--output-docs` to
  regenerate `docs/dataverse-schema.md`. Managed-identity-first authentication; client
  secret is a documented dev-only fallback.
- **Precondition assertion** (`scripts/Test-AgentEligibilityPrecondition.ps1`) — asserts
  that a target agent has Microsoft Entra ID authentication **and** require-users-to-sign-in
  enabled, the verified precondition for sharing-based audience control. No-authentication
  and Generic OAuth2 agents fail the assertion.
- **Sample decision rows** (`templates/decision-log.sample.json`) — allow and deny
  examples illustrating the `fsi_aegdecisionlog` row shape.

### Notes

- Several configuration values in `manifest.yaml` (zone scope, dependency solution ids)
  are recorded as **assumptions** pending ratification; they are flagged inline in the
  manifest and in `README.md` under *Assumptions and build-time verifications*.
- This preview ships **documentation, Azure APIM policy templates, and scripts only** —
  no exported Power Platform runtime artifacts.

[0.1.0-preview]: https://github.com/judeper/FSI-AgentGov-Solutions/releases
