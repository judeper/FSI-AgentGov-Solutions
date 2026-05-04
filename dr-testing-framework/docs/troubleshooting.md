# Troubleshooting Guide

Common issues and resolutions for the DR Testing Framework solution.

---

## Authentication Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Token acquisition fails | Managed identity is not assigned, workload identity federation is misconfigured, `TenantId`/`ClientId` is incorrect, or a legacy client secret expired | Prefer a fresh `-AccessToken` from managed identity or workload identity. For local development only, verify the legacy service-principal values and rotate the secret. |
| 401 Unauthorized from Dataverse | Token audience does not match the target Dataverse organization | Acquire the token for the exact Dataverse URL used in `-Environment` (for example, `https://contoso.crm.dynamics.com`) |
| 403 Forbidden from Dataverse | Executing identity is not configured as a Dataverse application user or lacks table privileges | Add the identity as an application user and assign a security role with read access to agent metadata and write access to `fsi_drtestresult` |
| Sovereign cloud auth failure | Script auto-selects auth endpoint based on Dataverse URL (`.dynamics.cn` → `login.chinacloudapi.cn`, `.microsoftdynamics.us` / `.appsplatform.us` → `login.microsoftonline.us`) | Verify the Dataverse URL uses the correct sovereign domain; the script selects the matching authority automatically for legacy credential flow |
| `ConvertFrom-SecureString` error: "A parameter cannot be found that matches parameter name 'AsPlainText'" | Running on Windows PowerShell 5.1 | Install PowerShell 7.1+ and run scripts with `pwsh` (not `powershell`) |

---

## Dataverse Persistence Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Exit code 2 (persistence failed) | Authentication error or Dataverse save operation failed | Verify the `fsi_drtestresult` table exists in the target environment; confirm the executing identity has write access |
| 403 Forbidden on PATCH | Executing identity lacks the required security role | Add the executing identity as an application user with write access to the `fsi_drtestresult` table |
| Schema mismatch | Table columns do not match the expected schema definition | Re-run `create_drt_dataverse_schema.py --output-docs` and verify column logical names against `docs/dataverse-schema.md` |

---

## Test Execution Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| "AgentId required" error | `AgentReadinessCheck` and `FullValidation` require an agent identifier | Provide the `-AgentId` parameter with a valid GUID |
| Invalid Environment URL | SSRF validation rejects the URL format | Use the format `https://<org>.crm.dynamics.com` (or the equivalent sovereign cloud domain) |
| Probe budget exceeded | Read-only validation checks completed slower than the configured probe budget | Review Dataverse throttling, network latency, and Application Insights `requests` / `dependencies` telemetry. Do not treat this as actual RTO evidence by itself. |
| Validation checks fail | Agent, connectors, or Dataverse evidence table are not reachable after the operator's recovery procedure | Verify the post-restore agent state in PPAC/Copilot Studio; re-run the individual scenario with `-Verbose` |
| No prior result for recency check | First run or evidence table was recently created | Treat the run as baseline evidence and schedule the next validation run |

---

## Pester Test Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Tests not found | Pester module not installed | Run `Install-Module Pester -Force -Scope CurrentUser` |
| Mock failures | Pester version incompatibility | Requires Pester 5.0+; verify with `Get-Module Pester -ListAvailable` and update if needed |

---

## Exit Codes Reference

| Code | Meaning |
|------|---------|
| 0 | Validation passed and results saved, or DryRun / explicit `-AllowConnectivityOnly` probe completed |
| 1 | Validation failed |
| 2 | Validation passed but Dataverse persistence failed, or evidence export found no data / incomplete validation coverage |

---

## Rate Limiting

- `Invoke-DRTest.ps1` supports `Retry-After` headers from Dataverse (HTTP 429).
- Default retry behavior uses exponential backoff with jitter.
- If persistent 429 errors occur, reduce test frequency or contact the Dataverse administrator to review service capacity.

---

## Getting Help

1. **Enable verbose output** — add the `-Verbose` parameter to any script invocation for detailed execution trace
2. **Check audit logs** — review the `logs/` directory for execution details and error context
3. **Open an issue** — report problems at [GitHub Issues](https://github.com/judeper/FSI-AgentGov-Solutions/issues)

---

*DR Testing Framework — Troubleshooting Guide v2.0.1*
