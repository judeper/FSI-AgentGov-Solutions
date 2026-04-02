# Troubleshooting

Common issues and resolutions when deploying or running the COI Testing Framework.

## Python Environment Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| `ModuleNotFoundError: No module named 'msal'` | Required packages not installed | Run `pip install -r scripts/requirements.txt` to install `msal` and `requests` |
| `ImportError: cannot import name 'ConfidentialClientApplication'` | Outdated `msal` version | Upgrade with `pip install --upgrade msal>=1.30.0` |
| Script fails with `SyntaxError` | Python version too old | The script requires Python 3.9+ (type hints, f-strings). Verify with `python --version` |
| `pip install` fails behind corporate proxy | Network proxy blocks PyPI | Configure pip proxy: `pip install --proxy http://proxy:port -r scripts/requirements.txt` |
| Package conflicts with existing environment | Global Python has conflicting versions | Use a virtual environment: `python -m venv .venv && .venv\Scripts\activate && pip install -r scripts/requirements.txt` |

## Authentication Failures

| Issue | Cause | Resolution |
|-------|-------|------------|
| `Authentication failed: AADSTS7000215` | Invalid or expired client secret | Regenerate the client secret in Entra ID → App registrations → Certificates & secrets |
| `Authentication failed: AADSTS700016` | Wrong `AZURE_CLIENT_ID` | Verify the Application (client) ID matches the registered app in Entra ID |
| `Authentication failed: AADSTS90002` | Wrong `AZURE_TENANT_ID` | Verify the Directory (tenant) ID from the Azure portal |
| Script runs in `[DRY RUN MODE]` unexpectedly | One or more environment variables not set | Set all three variables: `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` |
| `401 Unauthorized` on Dataverse API call | App registration lacks Dataverse permissions | Grant `user_impersonation` for the Dataverse environment under API permissions in Entra ID |
| Token acquisition hangs or times out | Network cannot reach `login.microsoftonline.com` | Verify outbound HTTPS (443) access to `login.microsoftonline.com` from the host |

## Test Execution Problems

| Issue | Cause | Resolution |
|-------|-------|------------|
| All tests return `SKIPPED` status | Direct Line API integration not yet implemented | Expected in v1.0.0 — agent interaction is planned for a future release |
| `--category` returns zero scenarios | Invalid category name | Use one of: `proprietary_bias`, `suitability`, `fee_transparency`, `cross_selling` |
| `--environment` URL rejected | Incorrect Dataverse URL format | Use the full organization URL (e.g., `https://your-org.crm.dynamics.com`) without trailing slash |
| `Warning: Failed to save result` | Dataverse table missing or permission denied | Verify the `fsi_coitestresults` table exists and the service principal has create permissions |
| HTML report is empty | No results generated | Check that at least one scenario ran (verify `--category` filter or remove it to run all) |
| `ConnectionError` during result save | Dataverse environment unreachable | Verify network connectivity to the Dataverse endpoint; check firewall and proxy settings |

## Dataverse Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| `Entity 'fsi_coitestresults' does not exist` | Dataverse schema not deployed | Create the table using the schema documentation in `docs/` or the solution's schema creation script when available |
| Column name mismatch errors | Using wrong column name format | Use logical names (all-lowercase, no word separators): `fsi_scenarioid`, not `fsi_scenario_id` |
| `403 Forbidden` on Dataverse write | Insufficient table-level security | Assign the service principal a security role with Create and Read on `fsi_coitestresults` |
| Results not appearing in Compliance Dashboard | Integration not configured | COI test results feed into Control 2.18 via the cross-solution-integration module — verify it is deployed |

## Report Generation

| Issue | Cause | Resolution |
|-------|-------|------------|
| `ZeroDivisionError` in pass-rate calculation | No test results collected | Verify scenarios exist for the specified category; run without `--category` to execute all |
| JSON report output is truncated | Console buffer limit | Redirect output to a file: `python scripts/run_coi_tests.py --report json > results.json` |
| ANSI color codes appear in log files | Terminal escape sequences in non-TTY output | Redirect to file and strip codes, or pipe through a tool that removes ANSI sequences |

## Getting Help

- **Solution issues:** [FSI-AgentGov-Solutions GitHub Issues](https://github.com/judeper/FSI-AgentGov-Solutions/issues)
- **Framework controls:** [Control 2.18 — Automated Conflict of Interest Testing](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.18-automated-conflict-of-interest-testing.md)

---

*FSI Agent Governance Framework — COI Testing*
