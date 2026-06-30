# Fallback testing guide

This guide explains what each structural check looks for, how to tune the detection markers for your
Copilot Studio export, and how to interpret the findings. The checks are a **pre-flight coverage
gate** — they detect missing resilience constructs in the unpacked solution source; they do not
prove that a construct behaves correctly at runtime.

## How the checks read the solution

`Invoke-EarlyReleaseValidation.ps1` operates on the output of `pac solution unpack`. It recursively
scans `*.yaml` / `*.yml` topic files and connection-reference definition files (`*.json` / `*.xml`
under a `connectionreferences` path or containing `connectionreferencelogicalname`).

Because the exact node names emitted by `pac solution unpack` vary by platform version, the
detection markers are **editable constants** at the top of the script:

| Constant | Meaning | Default markers |
|----------|---------|-----------------|
| `$script:ConnectorActionMarkers` | A topic reaches an external connector/flow | `InvokeConnectorAction`, `InvokeFlowAction`, `HttpRequestAction`, `InvokeAIBuilderModelAction`, `connectionReference:` |
| `$script:ErrorHandlingMarkers` | A topic handles a failure path | `errorHandling`, `kind: ConditionGroup`, `OnError`, `actionScopeErrorHandler` |
| `$script:FallbackTopicMarkers` | The System Fallback topic | `kind: OnUnknownIntent`, `ConversationalBoosting`, `System Fallback`, `SystemFallback` |
| `$script:EscalateTopicMarkers` | The Escalate / human-handoff topic | `kind: OnEscalate`, `Escalate` |
| `$script:MessageActivityMarker` | A user-facing message activity | `kind: SendActivity` |

If a check reports a false positive or false negative, inspect the unpacked YAML for the actual node
names your export uses and adjust the relevant marker list.

## Check 1 — FallbackCoverageCheck

**Looks for:** any topic that calls a connector/flow (a `ConnectorActionMarker`) but contains no
`ErrorHandlingMarker`.

**Why it matters:** a connector call with no error branch surfaces raw platform errors to the user
when the connector is unavailable, instead of a graceful fallback.

**Remediation:** add a condition branch on the action output, or an error-handling scope, that routes
to a user-facing message or the System Fallback topic.

## Check 2 — ConnectorResilienceCheck

**Looks for:** a connection-reference definition with a hard-coded `connectionid` (a GUID value in
JSON `"connectionid": "<guid>"` or XML `<connectionid>…</connectionid>`).

**Why it matters:** a hard-coded connection id does not rebind per environment, so the agent imported
into the early-release ring points at the wrong (or a missing) connection.

**Remediation:** leave `connectionid` empty in the solution so the import binds it per environment.

## Check 3 — ErrorRecoveryCheck

**Looks for:** the presence of a System Fallback topic and that it (and any Escalate topic) carries a
non-stub user-facing message (`SendActivity` with at least a few non-space characters of text).

**Why it matters:** an empty or default fallback leaves the user with no graceful recovery path.

**Remediation:** author a clear fallback message; add an Escalate topic for human handoff when the
agent operates in a regulated zone.

## Check 4 — EarlyReleaseReadinessCheck (deferred)

The composite gate runs checks 1–3 and then a **live probe** against the deployed agent (sending
known failure-trigger inputs and validating the fallback response). The live probe is **deferred
pending MSCAT "Building Enterprise AI Solutions" Part 2**, which specifies the early-release-ring
environment-config schema needed to target the ring. Until then the check reports `Skipped` and
records `fsi_promotionready = false`. Tracking: JudeSquad issue #1266.

## Interpreting results

- **Pass** — no gaps for that check.
- **Fail** — one or more gaps; the run exits non-zero (code `1`). Findings list the topic/file,
  severity, and issue.
- **Skipped** — only the composite readiness check, while the live probe is deferred.

Each finding is written to `fsi_findingdetail` as JSON, hashed (SHA-256) into `fsi_evidencehash`, and
packaged for review by `Export-ValidationEvidence.ps1`.
