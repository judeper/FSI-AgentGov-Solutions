# Troubleshooting

Common issues and resolutions when deploying or running the COI Testing Framework.

## Python Environment Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| `ModuleNotFoundError: No module named 'azure'` | Required packages not installed | Run `pip install -r scripts/requirements.txt` to install `azure-identity` and `requests` |
| `ImportError` for Azure Identity classes | Outdated `azure-identity` package | Upgrade with `pip install --upgrade azure-identity>=1.25.0` |
| Script fails with `SyntaxError` | Python version too old | The script requires Python 3.9+ (type hints, f-strings). Verify with `python --version` |
| `pip install` fails behind corporate proxy | Network proxy blocks PyPI | Configure pip proxy: `pip install --proxy http://proxy:port -r scripts/requirements.txt` |
| Package conflicts with existing environment | Global Python has conflicting versions | Use a virtual environment: `python -m venv .venv && .venv\Scripts\activate && pip install -r scripts/requirements.txt` |

## Authentication Failures

| Issue | Cause | Resolution |
|-------|-------|------------|
| `Authentication failed` with `--auth-mode managed-identity` | The host has no enabled managed identity or the user-assigned identity client ID is wrong | Enable a system-assigned identity, or set `AZURE_MANAGED_IDENTITY_CLIENT_ID` to the user-assigned managed identity client ID |
| `workload-identity authentication requires...` | Missing federated identity settings | Set `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_FEDERATED_TOKEN_FILE` after configuring a federated identity credential |
| `certificate authentication requires...` | Certificate auth variables are missing | Set `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_CLIENT_CERTIFICATE_PATH`; set `AZURE_CLIENT_CERTIFICATE_PASSWORD` when the certificate requires it |
| `client-secret authentication requires...` | Legacy development fallback variables are missing | Set `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_CLIENT_SECRET`, or switch to a stronger auth mode |
| `401 Unauthorized` on Dataverse API call | Identity token was acquired but isn't authorized in Dataverse | Create a Dataverse application user for the managed identity or app registration and assign a role with table Create/Read privileges |
| `403 Forbidden` on Dataverse write | Application user lacks table privileges | Add least-privilege Create and Read permissions on `fsi_coitestresults` |
| Token acquisition hangs or times out | Network cannot reach Microsoft Entra or managed identity endpoints | Verify outbound HTTPS access to `login.microsoftonline.com` and the platform managed identity endpoint |

## Test Execution Problems

| Issue | Cause | Resolution |
|-------|-------|------------|
| All tests return `SKIPPED` status | Direct Line API integration not yet implemented | Expected behavior in this scaffold release — agent interaction is planned for a future release. Pass `--allow-skipped` to exit 0; without it the runner exits 3. |
| `--category` returns zero scenarios | Invalid category name | Use one of: `proprietary_bias`, `suitability`, `fee_transparency`, `cross_selling` |
| `--environment` URL rejected | Incorrect Dataverse URL format | Use the full organization URL (e.g., `https://your-org.crm.dynamics.com`) without trailing slash |
| `Warning: Failed to save result` | Dataverse table missing or permission denied | Verify the `fsi_coitestresults` table exists and the application user has Create permissions |
| HTML report is empty | No results generated | Check that at least one scenario ran (verify `--category` filter or remove it to run all) |
| `ConnectionError` during result save | Dataverse environment unreachable | Verify network connectivity to the Dataverse endpoint; check firewall and proxy settings |

## Dataverse Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| `Entity 'fsi_coitestresults' does not exist` | Dataverse schema not deployed | Create the table using the schema documentation in `docs/` or the solution's schema creation script when available |
| Column name mismatch errors | Using wrong column name format | Use logical names (all-lowercase, no word separators): `fsi_scenarioid`, not `fsi_scenario_id` |
| Choice value rejected for `fsi_status` | Dataverse option-set value doesn't match the schema | Use PASS=`100000000`, FAIL=`100000001`, SKIPPED=`100000002`, WARN=`100000003`, ERROR=`100000004` |
| Results not appearing in Compliance Dashboard | Integration not implemented in this scaffold release | Treat dashboard publishing as planned work until the Compliance Dashboard integration ships |

## Report Generation

| Issue | Cause | Resolution |
|-------|-------|------------|
| `ZeroDivisionError` in pass-rate calculation | No test results collected (historical regression — guarded since v1.1.2 with an explicit `len(self.results) > 0` check before division) | Verify scenarios exist for the specified category; run without `--category` to execute all. Custom callers invoking `generate_report()` on an empty runner now receive `Pass Rate: 0.0%` rather than an error. |
| JSON report output is truncated | Console buffer limit | Redirect output to a file: `python scripts/run_coi_tests.py --report json --dry-run --allow-skipped > results.json` |
| ANSI color codes appear in log files | Terminal escape sequences in non-TTY output | The runner now suppresses color codes automatically when `sys.stderr` is not a TTY (v1.1.2+). For older releases, redirect to file and strip codes, or pipe through a tool that removes ANSI sequences. |

## Getting Help

- **Solution issues:** [FSI-AgentGov-Solutions GitHub Issues](https://github.com/judeper/FSI-AgentGov-Solutions/issues)
- **Framework controls:** [Control 2.18 — Automated Conflict of Interest Testing](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.18-automated-conflict-of-interest-testing.md)

---

*FSI Agent Governance Framework — COI Testing*
