# Validator suite

The files in this folder provide solution-scoped checks for the `agent-intake` workstream.

## Validators

- `validate_question_catalogs.py` — counts the Express, Standard, and Full question bindings and checks Dataverse symbols against `scripts/create_fsi_intake_dataverse_schema.py`.
- `validate_adaptive_cards.py` — parses each `templates/*-card.json` file, checks the Adaptive Card shape, and verifies that every `${token}` is documented in the card allowlist.
- `validate_manifest.py` — validates `agent-intake/manifest.yaml` against the repo `scripts/manifest.schema.json` contract.
- `validate_policy_yaml.py` — parses `templates/policy-lookup-tables.yaml`, checks the required top-level keys, and verifies the `schema_version` format.
- `test_validators_smoke.py` — pytest wrapper that runs each validator as a subprocess so CI can surface drift in one place.

## Local run

```powershell
python -m pip install jsonschema pyyaml pytest
python agent-intake/tests/validators/validate_question_catalogs.py
python agent-intake/tests/validators/validate_adaptive_cards.py
python agent-intake/tests/validators/validate_manifest.py
python agent-intake/tests/validators/validate_policy_yaml.py
python -m pytest agent-intake/tests/validators -v
```

These checks are intended to surface drift between parallel workstreams quickly, especially when the schema, policy, docs, and templates land in separate commits.
