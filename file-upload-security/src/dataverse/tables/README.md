# Dataverse Tables

Table definitions are provisioned programmatically via `scripts/create_dataverse_schema.py`.

See [SCHEMA.md](../../../docs/SCHEMA.md) for column definitions and data types.

Tables:
- `fsi_fileupload_baseline` — Approved file upload configuration baseline per agent
- `fsi_fileupload_validationhistory` — Immutable audit trail of compliance scans
- `fsi_fileupload_violation` — Active policy violations requiring remediation
