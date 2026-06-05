# Lab-Readiness Validation — agent-intake

> Static validation report (no live tenant). Records what was checked, the authoritative
> Microsoft sources cited, the gaps found and fixed, runtime-only caveats, and a final
> lab-readiness assessment. Not customer-facing setup guidance — see [`README.md`](README.md)
> and [`docs/pilot-deployment-runbook.md`](docs/pilot-deployment-runbook.md) for deployment.

| | |
|---|---|
| **Solution** | agent-intake |
| **Version** | v1.0.0-preview |
| **Primary controls** | 1.2 (Agent Registry/Integrated Apps), 1.7 (Audit Logging), 2.1 (Managed Environments), 2.13 (Documentation & Record Keeping), 3.1 (Maker Onboarding) |
| **Validation date** | 2026-06-04 |
| **Method** | Parse-validity + authoritative Microsoft source verification + doc-completeness review |

## Purpose

A pre-build maker-intake layer that classifies AI-agent requests into Express / Standard / Full
paths, routes for sponsor 1-click approval or parallel reviewer quorum, records an immutable
7-year decision pack, performs an MRM handoff for high-risk requests, and mints a Microsoft Entra
Agent ID on approval before handing off to `agent-registry-automation`.

## What was checked

1. **Parse validity** — `python -m py_compile` over all 20 `.py` files (PASS) and
   `[System.Management.Automation.Language.Parser]::ParseFile` over every `.ps1` (zero parse errors).
2. **Microsoft Entra Agent ID handoff** (`scripts/setup_entra_agent_id.py`) — the highest-risk API
   surface. Verified endpoint paths, request body, permissions, and the open-type extension pattern
   against current Microsoft Graph v1.0 reference docs.
3. **Auto-detect endpoints** (`docs/auto-detect-playbook.md`, `scripts/autodetect_*.py`) — Graph
   `/me` + `/me/manager`, Power Platform BAP environments/DLP, Purview retention labels, Purview
   Data Map. Cross-checked against the recorded API-verification spike and current doc shapes.
4. **MRM handoff** (`scripts/handoff_mrm.py`) — coherence of the reuse-existing-schema design,
   `fsi_modelinventory` queue, `fsi_mrmcomplianceevent` event write, and `fsi_intakeauditevent`
   fallback.
5. **Dataverse column naming** — grep for snake_case `fsi_*_*` column references; confirmed all
   hits are legitimate global option-set names (`fsi_acv_zone`, `fsi_intake_*`) or connection-
   reference logical names (`fsi_cr_*`), not columns.
6. **FSI language rules** — grep for prohibited phrases across all docs/scripts/templates.
7. **Doc completeness** — README sections (Purpose, Prerequisites/roles, Deploy steps, Expected
   outcomes, Validation), internal consistency vs. CHANGELOG and AGENTS.md.
8. **Regulatory citations** — verified the OCC Bulletin 2026-13 reference.

## Authoritative sources cited

| Claim verified | Source URL |
|---|---|
| Create agentIdentity — `POST /v1.0/servicePrincipals/microsoft.graph.agentIdentity`; body requires `displayName`, `agentIdentityBlueprintId`, `sponsors@odata.bind`; `Content-Type: application/json`; 201 Created | https://learn.microsoft.com/graph/api/agentidentity-post?view=graph-rest-1.0 |
| App permissions: least `AgentIdentity.Create.All`; higher `AgentIdentity.CreateAsManager`, `AgentIdentity.ReadWrite.All`. Delegated: least `AgentIdentity.Create.All` | https://learn.microsoft.com/graph/api/agentidentity-post?view=graph-rest-1.0 |
| `agentIdentity` is an **open type** (additional properties allowed) — basis for the `fsiReviewerAttestations` extension | https://learn.microsoft.com/graph/api/resources/agentidentity?view=graph-rest-1.0 |
| List agentIdentity — `GET /servicePrincipals/microsoft.graph.agentIdentity`; least `AgentIdentity.Read.All` | https://learn.microsoft.com/graph/api/agentidentity-list?view=graph-rest-1.0 |
| Get agentIdentity — least `AgentIdentity.Read.All` | https://learn.microsoft.com/graph/api/agentidentity-get?view=graph-rest-1.0 |
| Update agentIdentity — `PATCH /servicePrincipals/{id}/microsoft.graph.agentIdentity`; `AgentIdentity.ReadWrite.All` | https://learn.microsoft.com/graph/api/agentidentity-update?view=graph-rest-1.0 |
| `AgentIdentity.CreateAsManager` is auto-granted to blueprint principals and can't be revoked; 250-identity cap | https://learn.microsoft.com/entra/agent-id/agent-id-creation-channels#agent-identity-blueprint-principals |
| Create blueprint principal — `POST /v1.0/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal` (used by `setup_agent_identity_blueprint.py`) | https://learn.microsoft.com/graph/api/agentidentityblueprintprincipal-post?view=graph-rest-1.0 |
| Create/delete agent identities (sponsor binding; blueprint app-only token acquisition; managed-identity-first) | https://learn.microsoft.com/entra/agent-id/create-delete-agent-identities |
| Agent identities, service principals, and applications (subtype, sponsor requirement) | https://learn.microsoft.com/entra/agent-id/agent-service-principals |
| Blocked Graph permissions for agents (governance context) | https://learn.microsoft.com/graph/api/resources/agentid-platform-overview?view=graph-rest-1.0 |
| OCC Bulletin 2026-13 (Apr 17 2026) — revised interagency MRM guidance rescinding OCC 2011-12; **excludes** generative/agentic AI from formal MRM scope | https://www.occ.gov/news-issuances/news-releases/2026/nr-occ-2026-29.html |

## Findings: gaps and fixes

### Fixed (docs)

- **Stale capability statements (customer-facing).** The README "Zone applicability" table was
  labelled "in v0.2" and described Standard/Full as merely "captured; routed to follow-up review,"
  and the README "Roadmap" listed the already-shipped Standard (v0.3) and Full (v0.4) paths as
  future work — both directly contradicting the top-of-README "Express, Standard, and Full paths
  all ship." `docs/maker-quick-start.md` likewise told makers Standard/Full were "available in
  v0.3 and v0.4" and linked to a non-existent "v0.3/v0.4 process." Updated all four to reflect the
  shipped v1.0.0-preview state and to point makers at `docs/maker-guide.md`. (README "Zone
  applicability", README "Roadmap", `docs/maker-quick-start.md` lines 18 and 83.)

### Verified accurate (no change required)

- **Entra Agent ID create/list/update.** `scripts/setup_entra_agent_id.py` uses the current GA
  (v1.0) paths and the exact request body (`displayName`, `agentIdentityBlueprintId`,
  `sponsors@odata.bind`). Documented permissions (`AgentIdentity.CreateAsManager` /
  `AgentIdentity.Create.All`, optional `AgentIdentity.Read.All`) match the Graph reference. The
  `fsiReviewerAttestations` open-type field is consistent with `agentIdentity` being an open type.
  The 400-retry-then-PATCH fallback for reviewer evidence, and the PATCH cast path
  `/servicePrincipals/{id}/microsoft.graph.agentIdentity`, both match the Update agentIdentity ref.
- **Blueprint principal.** `scripts/setup_agent_identity_blueprint.py` targets
  `…/microsoft.graph.agentIdentityBlueprintPrincipal`, matching the v1.0 ref.
- **Auto-detect playbook** endpoint table (Graph `/me`, BAP environments, Governance DLP policies,
  Purview retention labels, Purview Data Map, Agent ID create) is accurate and appropriately hedged
  (tenant feature availability, beta retention-label surface, delegated-only scopes).
- **Dataverse column naming** — no snake_case column violations; option-set and connection-
  reference names are correctly distinguished from logical column names.
- **FSI language rules** — no FSI-prohibited compliance-absolute phrases
  (per `fsi-language-rules.instructions.md`) in customer-facing docs/scripts/templates. (The only matches
  are in `research/` historical artifacts quoting external sources, and in AGENTS.md where the rule
  itself is stated — both intentionally preserved.)
- **OCC Bulletin 2026-13 citation** is real and correctly characterized in `docs/decisions.md`
  (the bulletin rescinds OCC 2011-12 and excludes agentic AI from formal MRM scope). The README's
  soft "Aids firm-policy governance for AI agents" wording is defensible; see the nuance caveat
  below.

## Runtime-only caveats (cannot be verified without a live tenant)

1. **Microsoft Entra Agent ID is in preview.** The Entra admin center surfaces "New agent identity
   (Preview)." Feature availability per tenant/cloud, the actual 201 response shape, and acceptance
   of the open-type `fsiReviewerAttestations` field require live-tenant verification (already
   tracked as a v1.1 closure item in AGENTS.md and the CHANGELOG).
2. **`tags` on agentIdentity create.** The script includes a `tags` array in the create payload.
   The Graph reference shows `tags` on the response object (inherited from servicePrincipal) but
   does not explicitly document it as writable on the agentIdentity POST. If a tenant rejects
   `tags` on create, the request would fail before the existing `notes`/extension 400-retry path
   engages (that fallback strips only `notes` and `fsiReviewerAttestations`, not `tags`). Confirm
   `tags` acceptance during the first live mint; if rejected, move tags to a post-create PATCH.
3. **Blueprint-scoped token acquisition.** Per Microsoft's create-delete-agent-identities guidance,
   agent identities are created with an app-only token acquired *by the agent identity blueprint*
   (client assertion). The script obtains a generic Graph token via managed identity / Azure CLI;
   the caller must ensure that identity carries the documented create permission and, where the
   blueprint-principal channel is used, that the blueprint principal is the token subject. This is
   an operational binding to confirm in the lab, not a code defect.
4. **OCC 2026-13 nuance.** Because OCC Bulletin 2026-13 explicitly excludes agentic AI from formal
   MRM scope, the MRM handoff in this solution supports *firm-level* governance and voluntary
   MRM-style rigor (carrying forward OCC 2011-12 principles), not formal MRM compliance against
   2026-13. `docs/decisions.md` states this correctly.
5. **Power Pages multistep form bindings** still require a documented MANUAL STEP — PAC CLI cannot
   create them programmatically (tracked).

## Final lab-readiness assessment

**Lab-ready for pilot validation.** All scripts parse cleanly; the highest-risk surface (Microsoft
Entra Agent ID minting) is accurate against current Microsoft Graph v1.0 references; auto-detect
endpoints are verified and well-hedged; Dataverse naming and FSI language rules pass; and the
customer-facing docs no longer contain stale capability claims. Remaining items are inherent
live-tenant verifications (Entra Agent ID preview behavior, `tags`-on-create acceptance,
blueprint-token binding) that cannot be closed by static analysis and are already tracked as v1.1
closure items. No blocking defects were found.

## Second-Pass Command-Existence Re-Verification (2026-06-05)

An independent second-pass audit re-derived every invoked command, cmdlet, CLI verb, REST endpoint and api-version, Dataverse entity set / logical column / option-set, and module against Microsoft Learn, with a sharpened focus on confirming each surface exists and will run in a live lab. Entra Agent ID Microsoft Graph v1.0 routes (agentIdentity / blueprint / inheritablePermissions), pac CLI verbs and flags, Security & Compliance PowerShell (e.g. New-ComplianceTag), BAP routes, and all fsi_ Dataverse logical names were confirmed against Microsoft Learn; 100/100 pytest passing. The fallback-only Az.Accounts 5.x SecureString-token item identified here was subsequently hardened: `seed-test-data.ps1` and `smoke_test.ps1` now type-guard `(Get-AzAccessToken).Token` and convert with `ConvertFrom-SecureString -AsPlainText` when the module returns a `SecureString` (default since Az.Accounts 5.0.0 / Az 14.0.0). See [Protect secrets in Azure PowerShell](https://learn.microsoft.com/powershell/azure/protect-secrets).

