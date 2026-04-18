# Troubleshooting Guide

Common issues and resolutions for the DR Testing Framework solution.

---

## Authentication Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Token acquisition fails | Incorrect `TenantId` or `ClientId`, or expired client secret | Verify credentials in your configuration; regenerate the client secret in Entra ID |
| 401 Unauthorized from Dataverse | Token audience does not match the target Dataverse organization | Verify the `-Environment` parameter matches the Dataverse environment URL (e.g., `https://contoso.crm.dynamics.com`) |
| Sovereign cloud auth failure | Script auto-selects auth endpoint based on Dataverse URL (`.dynamics.cn` → `login.chinacloudapi.cn`, `.microsoftdynamics.us` / `.appsplatform.us` → `login.microsoftonline.us`) | Verify the Dataverse URL uses the correct sovereign domain; the script selects the matching authority automatically |
| `ConvertFrom-SecureString` error: "A parameter cannot be found that matches parameter name 'AsPlainText'" | Running on Windows PowerShell 5.1 — the `-AsPlainText` parameter requires PowerShell 7.0+ | Install PowerShell 7+ and run scripts with `pwsh` (not `powershell`) |

---

## Dataverse Persistence Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Exit code 2 (persistence failed) | Authentication error or Dataverse save operation failed | Verify the `fsi_drtestresult` table exists in the target environment; confirm the app registration has a System Administrator security role |
| 403 Forbidden on PATCH | Executing identity lacks the required security role | Add the executing identity as an application user with write access to the `fsi_drtestresult` table |
| Schema mismatch | Table columns do not match the expected schema definition | Re-run `create_drt_dataverse_schema.py` to reconcile the schema, or manually verify column logical names against `docs/dataverse-schema.md` |

---

## Test Execution Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| "AgentId required" error | `AgentRestore` and `FullDR` test types require an agent identifier | Provide the `-AgentId` parameter with a valid GUID |
| Invalid Environment URL | SSRF validation rejects the URL format | Use the format `https://<org>.crm.dynamics.com` (or the equivalent sovereign cloud domain) |
| RTO target exceeded | Recovery steps completed slower than the configured target | Review environment size and complexity; consider pre-staging backups to reduce recovery time |
| Validation checks fail | Agent or connectors not restored correctly after recovery | Verify backup integrity and completeness; re-run the test with `-Verbose` to identify the failing step |

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
| 0 | Test passed, results saved (or DryRun mode / no credentials provided) |
| 1 | Test failed (RTO exceeded or validation check failed) |
| 2 | Test passed but Dataverse persistence failed |

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

*DR Testing Framework — Troubleshooting Guide v1.2.1*
