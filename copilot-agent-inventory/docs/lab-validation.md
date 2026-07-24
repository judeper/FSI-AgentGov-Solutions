# Copilot Agent Inventory v0.4 Lab Validation

**Validation date:** July 22-24, 2026<br>
**Version:** v0.4.0-preview  
**Tenant profile:** Microsoft 365 lab without Microsoft Agent 365  
**Report source:** `d062d50`  
**Live scan source:** `de86ded`

## Executive result

The no-Agent-365 path passed live validation for its declared scope. Explicit
`absent` and automatic license detection both completed without calling the
Package Management API. The final scans enumerated 31 environments, scoped 30
to Dataverse, skipped one environment explicitly without Dataverse, and
returned 209 Layer 2 agent records with no environment failures.

The nine-table Dataverse schema also passed live deployment, alternate-key
activation, repeat-deployment idempotency, direct Web API persistence, and
published Power Automate persistence. The final flow replay retained 209 agent
rows and one `fsi_caiscanrun` row with stable Dataverse row IDs, preserved a
null package count when the Package API was not attempted, and populated all
five previously missing Layer 2 count fields. A final documentation review also
corrected the fresh-deployment schema and flow instructions for package-only
rows; that licensed path was not redeployed or observed live.

The licensed Package Management API path remains **Static/Mock - Not Observed
Live** because the lab has no Microsoft Agent 365 license. Registry header
structure was observed from the actual confidential workbook, but its data rows
were not downloaded. Owner correlation and entitlement classification therefore
remain **Deferred**. One sanitized Power Automate run-history screenshot is
published below; the remaining portal screenshots are still Deferred or
conditional.

## Evidence classes

| Class | Meaning |
|---|---|
| **Observed Live** | Executed against the lab tenant and supported by sanitized, hash-anchored evidence |
| **Static/Mock** | Covered by automated tests or documented contract review, but not exercised against the live licensed service |
| **Partial** | A live component was exercised, but a dependent surface was not available |
| **Deferred** | Intentionally not attempted because a license, confidential input, or user-present browser session was unavailable |

## Validation matrix

| Area | Result | Evidence class | Key result |
|---|---|---|---|
| Explicit `--agent365 absent` | Pass | Observed Live | `Complete`; 209 agents; Package API not attempted; package count null |
| `--agent365 auto` | Pass | Observed Live | SKU probe succeeded; heuristic `NotDetected`; Package API skipped |
| ARG tenant-wide discovery | Unsupported | Observed Live | ARG requests were unsuccessful; no live `createdIn` authoring-surface classification |
| Environment/Dataverse discovery | Pass | Observed Live | 31 total, 30 in Layer 2 scope, 1 no-Dataverse, 0 failures |
| Dataverse schema | Pass | Observed Live | 1 shared Choice, 22 CAI Choices, 9 tables, 169 columns |
| Alternate keys | Pass | Observed Live | All 9 keys reached `Active`, including `fsi_ScanRunKey` |
| Schema idempotency | Pass | Observed Live | Repeat deployment detected every object and created no duplicate |
| Registry export contract | Pass | Observed Live - Header and Field Shape Only | 42 unique, nonblank headers; normalized field shapes retained without identity values |
| Registry row correlation | Deferred | Deferred | Confidential workbook rows were not downloaded |
| Owner entitlement classification | Deferred | Deferred | No real Registry owners were passed to the resolver |
| Dataverse row persistence | Pass | Observed Live - Direct Dataverse Writer | 209 agents plus 1 scan-run row; stable IDs on replay |
| Power Automate publication/run | Pass | Observed Live | Flow published and enabled; identical 209-agent payload replay succeeded in 1 minute 32 seconds |
| Power Automate read-back/idempotency | Pass | Observed Live | 209 agents plus 1 scan-run row; stable GUID sets; corrected Layer 2 counts |
| Package-only Dataverse flow persistence | Not observed live | Static/Mock | Environment ID is optional for fresh deployments; required create fields and pre-write Choice validation are documented |
| Package Management API success path | Pass | Static/Mock | Success, empty, paging, reconciliation, and typed failure paths covered |

## Final no-license scan results

| Metric | Explicit absent | Automatic detection |
|---|---:|---:|
| Overall status | Complete | Complete |
| Agent 365 resolved state | Absent | NotDetected |
| Detection confidence | OperatorDeclared | Heuristic |
| License probe attempted | No | Yes |
| Package API attempted | No | No |
| Package count | null | null |
| Environment/Dataverse layer | Full | Full |
| Environments enumerated | 31 | 31 |
| Dataverse-scoped environments | 30 | 30 |
| Explicit no-Dataverse environments | 1 | 1 |
| Environment failures | 0 | 0 |
| Agents | 209 | 209 |
| Feature rows | 7,601 | 7,601 |
| Auth/share rows | 209 | 209 |

`NotDetected` is a heuristic SKU no-match. It is not authoritative evidence
that the tenant lacks Agent 365. In both runs, a null package count means the
Package API was not attempted; it must not be interpreted as an observed empty
catalog.

## Findings and remediation

### BAP Dataverse URL contract

The initial live scan found the Dataverse URL under
`properties.linkedEnvironmentMetadata.instanceUrl`, rather than at the
environment object's top level. Public fix `788443d` normalized the nested
contract, skipped only environments explicitly without Dataverse, and added
auditable Layer 2 denominator counts.

### Dataverse global Choice payload

The first schema deployment created the global Choices, the first table, and six
String columns, then failed at `fsi_CreatedIn` with HTTP 400. The Choice column
payload included a local `OptionSet` property and omitted required Picklist
metadata.

Public fix `de86ded` now emits `AttributeType`, `AttributeTypeName`,
`SourceTypeMask`, and `GlobalOptionSet@odata.bind`, while omitting `OptionSet`.
The resumed deployment completed all nine tables and the repeat deployment was
idempotent.

### Environment access and PAC false-success

Four Dataverse reads initially returned HTTP 403. All four targets were
non-production environments: three Developer and one Sandbox.

PAC CLI 2.6.4 omitted the required Power Platform API version, reported an HTTP
400 internally, and still returned process exit code 0. Updating to PAC 2.9.3
allowed the supported self-elevation command to apply System Administrator
access. The repaired scans then completed with zero environment failures.

Automation that invokes PAC should inspect command output or verify the
resulting state; process exit code alone was not reliable for this operation.

### Registry header contract

In-place inspection of the actual Microsoft 365 admin center Registry workbook
observed one worksheet with 42 unique, nonblank columns and the normalized
shapes of selected fields. The validation process did not return, log, or retain
the underlying identity values. Relevant headers include:

| Header | Observed shape | CAI handling |
|---|---|---|
| `Name` | Text | Maps to `agent_name` |
| `Bot Id` | Identifier; blank in the inspected Agent Builder example | Maps to optional `agent_id` |
| `Owner` | UPN/email | Maps to `owner_upn` |
| `Date created` | Date/time | Maps to `date_created` |
| `Creator Id` | GUID | Intentionally not mapped to `owner_id` |
| `Environment Id` | Structured identifier | Retained as an observed source header; not used as an owner identity |
| `Title ID` | Identifier | Retained as an observed source header; mapping not assumed |
| `Platform` | Enum/text | Available for source validation |

Public fix `d062d50` updated the default alias map and namespaced unmapped display
labels. A future header such as `Owner Id` can no longer silently become the
canonical `owner_id` field without an explicit alias.

The Registry `Owner` remains distinct from `Creator Id`. This validation does
not claim that the owner is the original creator. No Registry column has yet
been validated as an immutable owner object ID, so the current bridge depends on
the mutable `Owner` UPN.

## Dataverse persistence and BI readiness

The Dataverse contract was first exercised through a direct Web API writer and
then through the published Power Automate flow. Both paths persisted 209 agent
rows and one `fsi_caiscanrun` row and retained the same row identities on replay.

Live connector testing found that Dataverse **Update a row** does not create a
missing row when supplied an alternate-key value; the missing-row request
returned HTTP 404. The validated connector-only pattern is:

`List rows by business key → Add missing row → capture primary GUID → Update by GUID`

The active alternate keys still protect uniqueness. Because lookup and create
are separate connector calls, the flow uses sequential agent iterations and
allows only one active flow run.

The first connector-only run succeeded but read-back found five null run-ledger
counts. A repair attempted in the legacy designer stored `@body(...)` text as a
literal string even though Flow Checker reported zero errors, and the replay
failed when Dataverse converted that text to an integer. The fields were
re-authored as expression tokens in the new designer and the identical payload
was replayed successfully.

Independent read-back after the corrected replay confirmed:

- 209 agent rows and one scan-run row;
- `coreAgentCount = 209`;
- `dataverseEnvironmentCount = 30`;
- `dataverseScannedAgentCount = 209`;
- `environmentFailureCount = 0`;
- `noDataverseEnvironmentCount = 1`;
- `packageApiAttempted = false`;
- package count remains null because the Package API was Deferred.

The stable GUID-set hashes were:

- agents:
  `56ee1003fc0af9e71ae91b0f113d2a3244706d19f69f0d4a217df896a0aab626`;
- scan run:
  `5750d9018b4ccadec634bda2b9eab9dc49cba0abcd322f3758527e2dc5bea269`.

![Sanitized Power Automate run history showing the successful 209-agent persistence replay](img/lab-validation/power-automate-run-success.png)

*The published validation flow replay succeeded in 1 minute 32 seconds. The
capture is tightly cropped to exclude tenant, account, environment, and flow
identifiers.*

Final diff review found that the documented fresh-row paths omitted
`fsi_lastscannedat`, `fsi_runid`, and other create-time fields, and that
`fsi_environmentid` was marked Business Required even though package-only rows
legitimately have no environment. The source schema now makes that column
optional for fresh deployments; the guide maps the required fields, uses
per-row Compose outputs for nullable Choice values, validates labels before any
row is created, verifies the critical read-back counts/null semantics, and
routes technical persistence failures to notification. The deployed no-license
lab contained no package-only rows, so these final guide/schema corrections
remain **Static/Mock - Not Observed Live**. Earlier v0.4 preview deployments
must change the Environment ID column requirement to Optional before authoring
the package-only flow branch.

Read-back found `fsi_createdin` unpopulated on all 209 rows. The Layer 2
Dataverse `bot` scan inventories agents but does not supply the ARG `createdIn`
authoring-surface field, and ARG was `Unsupported` in this tenant. This live
baseline therefore cannot identify which rows are Agent Builder agents. A null
`fsi_createdin` must not be interpreted as Copilot Studio or as zero Agent
Builder agents.

Registry owner and entitlement fields were also null because Registry data rows
were not downloaded. A null entitlement means not evaluated; it is distinct
from a computed `Unknown` classification. BI consumers should use the
`fsi_caiscanrun` coverage fields before interpreting any of these dimensions.

This result validates the documented lookup/create/GUID-update persistence
pattern and the BI-ready run-ledger mapping in the available no-license lab.

## Static licensed-path assurance

The automated suite covers Package Management API:

- successful Agent Builder inventory;
- successful empty catalog;
- pagination and truncation;
- package-only and existing-row scanner reconciliation;
- HTTP 401, 403, 404, 429, and 5xx responses;
- transport and parse failures;
- conservative status handling that never converts an API error into license
  absence.

These cases remain **Static/Mock - Not Observed Live**.

## Deferred work and coverage limits

- **Registry rows:** the confidential workbook was not downloaded into the lab
  evidence store; owner correlation remains Deferred.
- **Entitlement:** no real Registry owner identities were processed; Paid
  Copilot, Copilot Chat Only, and Unknown are not claimed as observed live.
- **Package API:** no Agent 365 license was available, so a successful live
  package catalog or package-only Dataverse flow write was not observed.
- **ARG:** unsuccessful requests left the attempted ARG layer `Unsupported`.
  Layer 2 provided the complete declared-scope inventory, but not
  authoring-surface classification.

## Screenshot capture checklist

One sanitized run-history screenshot is committed. Capture any additional
screenshots only in a user-present, authenticated lab browser session, then
crop, redact, flatten, strip metadata, hash, and review them before commit.

Place approved PNGs under `copilot-agent-inventory/docs/img/` and register each
one in `copilot-agent-inventory/docs/lab-validation-evidence.json` with its
SHA-256 hash, source class, UTC capture time, caption, and alt text. Run
`python scripts/build-manifest.py` followed by
`python scripts/build-manifest.py --check`; unregistered images are rejected.

| Screenshot | Requirement | Status |
|---|---|---|
| Dataverse alternate keys | Show all CAI keys Active, including `fsi_ScanRunKey`; exclude tenant/account chrome | Required - Deferred |
| Successful flow replay | Show one successful run for the explicit-absent payload without tenant, account, environment, or flow identifiers | Completed - sanitized run-history image published |
| Published/enabled flow state | Show the validation flow is published and enabled without exposing tenant/account chrome | Optional - live state verified; screenshot Deferred |
| `fsi_caiscanrun` read-back | Show requested mode Absent, Package API attempted false, Package API layer Deferred, and package count blank/null | Required - Browser capture Deferred; sanitized JSON read-back is authoritative |
| Registry headers | Prefer the sanitized table in this report; capture only if the header row can be isolated from every data row | Optional |
| Graph application permissions | Capture only if a dedicated scanner application is provisioned; no application was created for this delegated lab run | Conditional |

## Evidence index

Raw evidence remains outside Git in evidence set
`cai-lv-20260721T150805Z`. Sanitized summaries and SHA-256 manifests cover:

- unauthenticated absent/auto dry runs;
- initial and repaired live scans;
- BAP URL defect reproduction;
- schema dry run, failed deployment, remediation, key activation, and
  idempotency;
- environment access remediation;
- Registry header-only inspection;
- direct Dataverse persistence and replay;
- published Power Automate persistence, corrected replay, and independent
  Dataverse read-back.

Manifest files:

- `dry-run-sha256.txt`
- `live-bap-defect-sha256.txt`
- `live-absent-sha256.txt`
- `live-auto-sha256.txt`
- `schema-dry-run-sha256.txt`
- `schema-live-sha256.txt`
- `environment-access-sha256.txt`
- `live-remediated-sha256.txt`
- `registry-header-sha256.txt`
- `dataverse-persistence-sha256.txt`
- `power-automate-persistence-sha256.txt`

## Retained lab state

The non-production sandbox retains one shared Choice, 22 CAI Choices, nine CAI
tables, active alternate keys, 209 agent rows, and one scan-run row as a
reusable validation baseline. The current lab administrator also retains System
Administrator access in the four non-production environments used to close the
Layer 2 coverage gaps; review and revoke that standing access now that flow
validation is complete. PAC 2.9.3 is the active CLI version.

The published `CAI - Manual Persistence Validation` flow remains enabled pending
report review. Disable or delete it when no further replay evidence is needed.

These controls and evidence support governance review and BI interpretation;
they do not by themselves establish regulatory compliance.
