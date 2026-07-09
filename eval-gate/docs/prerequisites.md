# eval-gate — Prerequisites

> These steps require human action (`judep_microsoft`) before CI can run live evaluations. The gate
> stays inert (and fails closed) until every item below is complete. Do not automate these.

The eval-gate is a CI wrapper around the [Power CAT Copilot Studio Kit](https://github.com/microsoft/Power-CAT-Copilot-Studio-Kit).
It drives the Kit's test runs and reads the results back from Dataverse; it does not install or
configure the Kit for you.

## Prerequisite matrix

| # | Prerequisite | Role | Why |
|---|--------------|------|-----|
| 1 | Install the Power CAT Copilot Studio Kit (managed solution) into each Dataverse environment (Dev, Test, Prod) and configure its Direct Line connection to the target agent. | Power Platform Admin | The Kit owns utterance delivery and rubric scoring. |
| 2 | Populate `configs/environments.json` per environment (`agentId`, `dataverseUrl`, `tenantId`, `clientId`). | Power Platform Admin | The wrapper authenticates and resolves test sets per environment. |
| 3 | Register a Microsoft Entra ID application with a **certificate** credential (not a client secret); grant Dataverse `user_impersonation` and read/write on the Kit's `mspcat_*` tables in each environment. | Security Admin | Certificate auth for the CI service principal; missing table access is caught by pre-flight (HARD-FAIL). |
| 4 | Publish the certificate thumbprint and Direct Line secret to each GitHub Actions environment (`CS_CERT_THUMBPRINT_{DEV,TEST,PROD}`, `CS_DIRECTLINE_SECRET_{DEV,TEST,PROD}`). | Security Admin | Secrets are read at run time; never committed to the repo. |
| 5 | Upload `test-sets/safety-baseline.json` to the Kit's test-set library in each environment as `safety-baseline-v1`. | Power Platform Admin | The gate resolves the test set by ID; a missing set is an intentional HARD-FAIL. |
| 6 | Configure the `production` GitHub Actions environment with **required reviewer `judep_microsoft`**. | GitHub Admin | Human sign-off gates Test→Prod regardless of eval score (framework Decision #8). |

## Verify

Run a pre-flight (no test runs) once the Kit and secrets are in place:

```powershell
.\eval-gate\Invoke-EvalGate.ps1 -Environment dev -TestSetId safety-baseline-v1 -WhatIf
```

A clean pre-flight confirms Dataverse auth and Kit-table reachability. See
[deployment.md](deployment.md) for activating the workflows.
