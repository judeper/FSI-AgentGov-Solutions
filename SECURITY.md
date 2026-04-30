# Security Policy

Thank you for helping keep `FSI-AgentGov-Solutions` and its downstream adopters safe.

## Project scope

This repository hosts **reference implementations** for AI-agent governance in regulated financial services. It contains:

- PowerShell, Python, and KQL scripts that read from and write to Microsoft 365, Power Platform, and Dataverse tenants.
- Dataverse schema generators (Web API).
- One C# Dataverse plugin source file (`mime-type-restrictions/src/ValidateMimeTypePlugin.cs`).
- Documentation, manifests, and JSON templates.

There are **no exported Power Platform flow `.zip` packages** and **no production runtime services** in this repo. Adopters operate the scripts inside their own tenants under their own identities.

## Supported versions

This is a moving reference catalog. Security fixes land on `main` and are tagged with the next semantic-version release (see `CHANGELOG.md`).

| Version    | Supported          |
|------------|--------------------|
| `main`     | ✅ Active development |
| Latest tag | ✅ Recommended for downstream consumption |
| Older tags | ⚠️ Best-effort only — please upgrade |

The companion framework `judeper/FSI-AgentGov` follows its own version policy. The `solutions.json` schema is **additive-only within 1.4.x**; breaking changes require coordinated 1.5.0 releases.

## Reporting a vulnerability

**Please do not open public GitHub issues for security reports.**

Use [GitHub's private vulnerability reporting](https://github.com/judeper/FSI-AgentGov-Solutions/security/advisories/new) to file a report. Include:

- Affected solution / file / commit
- Reproduction steps
- Impact and any evidence of exploitation
- Your disclosure timeline preference

You should receive an acknowledgement within **5 business days** and a triage assessment within **10 business days**. We aim to publish a fix and a CVE (if applicable) within **90 days**.

## In-scope issues

The following classes of issue are explicitly in scope:

- **Credential leakage** — committed secrets, tokens, certificates, or connection strings (current branch *or* git history).
- **Privilege escalation patterns in scripts** — scripts that grant broader Microsoft Graph / Power Platform / Dataverse permissions than they declare.
- **Injection flaws** — OData injection, command injection, KQL injection, or unsafe deserialization in any script or plugin.
- **Plugin trust-boundary issues** — the Dataverse plugin must not bypass platform validation or accept untrusted MIME data without verification.
- **Supply-chain weaknesses** — missing dependency pinning, missing signature verification on releases, GitHub Actions running untrusted code with elevated permissions.
- **Documentation that recommends insecure patterns** — e.g., long-lived client secrets, broad delegated scopes, or disabled DLP.

## Out of scope

- Vulnerabilities in third-party Microsoft services (Power Platform, Dataverse, Microsoft 365). Report those directly to [Microsoft Security Response Center](https://msrc.microsoft.com/).
- Vulnerabilities in customer Power Automate flows built from these reference docs — those are owned by the deploying organization.
- Theoretical risks without a documented exploitation path.

## Defensive controls in this repository

- **`.github/workflows/gitleaks.yml`** — secret scanning on every push and PR.
- **`.github/workflows/dependency-review.yml`** — GitHub-native dependency review on PRs.
- **`.github/workflows/codeql.yml`** — static analysis of Python (and C# when project files are present).
- **`.github/workflows/odata-lint.yml`** — narrow OData-context linter to catch Dataverse logical-name drift.
- **`.github/workflows/language-rules.yml`** — bans absolute-compliance language ("ensures compliance", "guarantees compliance").
- **Manifest schema validation** (`.github/workflows/manifest-check.yml`) — rejects manifests that reference unknown framework controls.
- **Health check** (`.github/workflows/health-check.yml`) — 30-minute probe of published artifacts.

See `THREAT-MODEL.md` for the high-level threat model.

## Coordinated disclosure

If your finding affects both `FSI-AgentGov` and `FSI-AgentGov-Solutions`, please report it via the framework repository's advisory channel and reference both repos. We will coordinate the fix and disclosure across the two repos.
