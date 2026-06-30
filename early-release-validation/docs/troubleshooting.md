# Troubleshooting

## A check reports a gap I do not believe is real

The structural checks are heuristic text inspections of the unpacked solution. The most common cause
is a `pac solution unpack` version that emits different node names than the default markers.

1. Open the unpacked topic YAML and find the actual node name (for example, the connector action
   `kind:` or the error-handling construct).
2. Edit the relevant marker list at the top of `scripts/Invoke-EarlyReleaseValidation.ps1`
   (`$script:ConnectorActionMarkers`, `$script:ErrorHandlingMarkers`, etc.).
3. Re-run the check.

See [fallback-testing-guide.md](fallback-testing-guide.md) for the full marker reference.

## "SolutionPath '…' does not exist"

`-SolutionPath` must point at the **unpacked** solution folder (the `--folder` you passed to
`pac solution unpack`), not the `.zip`. Unpack first:

```powershell
pac solution unpack --zipfile ./MyAgentSolution.zip --folder ./unpacked
```

## "Environment must be a valid Dataverse URL"

`-Environment` is validated against the supported Dataverse host suffixes
(`*.crm[N].dynamics.com`, `*.crm.microsoftdynamics.us`, `*.crm.appsplatform.us`,
`*.crm.dynamics.cn`). Pass the org URL with no trailing path, for example
`https://your-org.crm.dynamics.com`.

## Results are not saved to Dataverse

Evidence persistence needs both a valid `-Environment` and credentials (`-AccessToken`, or
`TenantId`/`ClientId`/`ClientSecret`). When credentials are missing the script still runs the checks
and prints results but warns that nothing was saved. Exit code `2` means the checks ran but the
Dataverse write failed — inspect the warning and the audit log under `scripts/../logs/`.

## EarlyReleaseReadinessCheck always reports Skipped

This is expected. The live probe is deferred pending MSCAT "Building Enterprise AI Solutions" Part 2
(JudeSquad issue #1266). The structural sub-checks still run; `fsi_promotionready` is recorded as
`false` until the probe is implemented.

## "ModuleNotFoundError: No module named 'requests'" (Python scripts)

Install the solution's Python dependencies:

```bash
pip install -r scripts/requirements.txt
```

`--output-docs` on the schema script imports `requests` at module load even though it does not call
it; installing the requirements resolves this.

## Schema option-set values look unusual (100000000+)

`fsi_erv_testtype` and `fsi_erv_teststatus` use the standard Dataverse `fsi_`-prefixed Picklist value
range starting at `100000000`. The PowerShell value maps in `Invoke-EarlyReleaseValidation.ps1` must
stay in sync with `create_erv_dataverse_schema.py`; the Pester tests assert the maps use the
`100000000+` range.
