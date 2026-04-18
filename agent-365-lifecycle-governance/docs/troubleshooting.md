# Troubleshooting Guide

Common issues and resolutions for the Agent 365 Lifecycle Governance solution.

---

## Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Sponsor PATCH returns 200 but sponsor not set | Wrong body format — used UPN string instead of `@odata.bind` | Use `{"sponsor@odata.bind": "https://graph.microsoft.com/v1.0/users/{objectId}"}` |
| Access review creation returns 400 | Missing `principalScopes` or `resourceScopes` | Both scopes are required — verify payload matches Flow 2 specification |
| Flow terminates immediately without processing | Feature flag `IsAgent365LifecycleEnabled` is `"false"` | Set to `"true"` after confirming Agent 365 GA licensing |
| Sign-in log query returns 403 | `AuditLog.Read.All` permission not granted or tenant restriction | Grant permission or accept fallback to PPAC-only activity data |
| Agent not added to security group | Group ID environment variable empty or incorrect | Verify `FSIAllAgentIdentitiesGroupId` and `FSIZone3AgentsGroupId` values |
| Deactivation approval timeout | No response within 5 business days | Approval escalates to `EscalationApproverUPN` automatically |
| Duplicate deactivation requests | Race condition between Flow 3 and Flow 5 | Flow 4 checks for existing open requests before creating |
| Deletion hold not enforced | Flow 4 calling DELETE API directly | Flow 4 must never call DELETE — only Flow 6 handles deletion |
| Entity set name mismatch in PowerShell | Auto-generated name differs from expected | Verify actual entity set name in Dataverse and update scripts |
| Lifecycle Workflow not triggering | Workflow scoped by OData filter instead of group | Use security group membership for scoping, not OData filters |

---

## Feature Flag Behavior

When `IsAgent365LifecycleEnabled = "false"`:

- All 6 flows check this flag as their first action
- Flows terminate with "Cancelled" status and log a skip event
- No external API calls are made
- Dataverse-only operations (if any) continue normally

**When to disable:**

- Before Agent 365 GA licensing is confirmed in the tenant
- During maintenance windows
- When troubleshooting API issues to prevent cascading failures

**Re-enabling:**

1. Set `IsAgent365LifecycleEnabled` to `"true"` in environment variables
2. Verify flows resume on next scheduled trigger
3. Check compliance event log for any gaps during the disabled period

---

## API-Specific Issues

### Graph Beta Endpoints

The `agentRegistry` endpoints are in Graph beta. Behavior may change before GA. Monitor the [Microsoft Graph changelog](https://developer.microsoft.com/en-us/graph/changelog) for breaking changes.

**Common beta issues:**

| Issue | Resolution |
|-------|------------|
| Endpoint returns 404 | Verify Agent 365 licensing is active; beta endpoints require feature enablement |
| Response schema changed | Compare current response against documented schema; update flow parsing logic |
| Throttling (429) | Implement retry with exponential backoff; reduce batch sizes |

### PPAC Bots API

The `api-version=2022-03-01-preview` may be superseded. Verify that `lastModifiedTime` and `publishedOn` fields are still returned in the response payload.

**Validation:**

```powershell
# Test PPAC Bots API response format
$uri = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$envId/bots?api-version=2022-03-01-preview"
$response = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $token" }
$response.value[0].properties | Get-Member -Name lastModifiedTime, publishedOn
```

### Access Review Instance IDs

The `entraReviewInstanceId` must be retrieved immediately after creating the access review definition. If this step fails, decision polling cannot function.

**Diagnosis:**

1. Open Flow 2 run history
2. Locate the access review creation HTTP action
3. Verify the response contains an `id` field
4. Verify the subsequent "Get Review Instance" action succeeded

---

## Sponsor Assignment Issues

### Sponsor Not Set After PATCH

**Symptoms:** API returns 200 but GET on the agent identity shows no sponsor.

**Root cause:** The sponsor PATCH requires `@odata.bind` format, not a plain UPN or object ID string.

**Correct payload:**

```json
{
    "sponsor@odata.bind": "https://graph.microsoft.com/v1.0/users/{sponsorObjectId}"
}
```

**Wrong payloads:**

```json
// WRONG - plain string
{ "sponsor": "sponsor@example.com" }

// WRONG - object without @odata.bind
{ "sponsor": { "id": "00000000-0000-0000-0000-000000000000" } }
```

### Unsponsored Agent Filter

**Symptoms:** Flow 1 or Flow 5 returns all agents instead of only unsponsored ones.

**Possible causes:**

| Cause | Resolution |
|-------|------------|
| Server-side `$filter` not supported for sponsor attribute | Use client-side filtering (retrieve all, filter in flow) |
| OData query syntax error | Verify filter syntax against Graph API documentation |

**Workaround:** If server-side filtering is not supported, retrieve all agent identities and use a condition action in the flow to filter for null sponsors.

---

## Dataverse Validation

After deploying the schema, verify:

1. **Entity set names** match expected values:
   - `fsi_agentlifecyclerecords`
   - `fsi_sponsorassignments`
   - `fsi_accessreviews`
   - `fsi_deactivationrequests`
   - `fsi_lifecyclecomplianceevents`

2. **Choice field integer values** match expected values (confirm in solution XML or Dataverse table designer)

3. **Alternate key** on `fsi_agentlifecyclerecord` (`fsi_agentid` + `fsi_environmentid`) is Active
   - Status may show "Pending" for up to 30 minutes after creation
   - Do not deploy flows until the key is Active

4. **Long-Term Retention** is enabled on `fsi_lifecyclecomplianceevent`

**Verify entity set name:**

```powershell
# Query Dataverse metadata to confirm entity set name
$uri = "$DataverseUrl/api/data/v9.2/EntityDefinitions?`$filter=LogicalName eq 'fsi_agentlifecyclerecord'&`$select=EntitySetName"
$result = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $token" }
$result.value[0].EntitySetName
```

---

## Performance Issues

### Flow Runs Slowly

**Symptoms:** Lifecycle flows take longer than 5 minutes.

| Cause | Resolution |
|-------|------------|
| Large agent population (>500 agents) | Implement pagination in Graph API calls |
| Multiple Graph API calls per agent | Batch API requests where possible |
| Dataverse query timeout | Add `$top` and pagination to Dataverse queries |

### Throttling

**Symptoms:** Flow fails with 429 Too Many Requests from Graph API or Dataverse.

**Resolution:**

1. Configure retry policies on HTTP actions (exponential backoff)
2. Reduce concurrent flow runs
3. Spread scheduled flows across different time windows
4. Use `$batch` for Graph API calls where supported

---

## Logging and Diagnostics

### Enable Verbose Logging

1. Open flow in edit mode
2. Select **Settings** on individual actions
3. Enable **Secure Inputs** and **Secure Outputs** (turn OFF for debugging only)
4. Run flow and check detailed action outputs

### View Flow Run History

1. Navigate to **Power Automate** → **My flows**
2. Select the flow
3. Click **28-day run history**
4. Click individual run to see action details

### Compliance Event Log

All significant lifecycle operations write to `fsi_lifecyclecomplianceevent`. Use this table for:

- Audit trail of all lifecycle state changes
- Diagnosing missed operations
- Verifying regulatory record completeness

### Contact Support

For issues not covered here:

1. Review [flow-configuration.md](flow-configuration.md)
2. Review [prerequisites.md](prerequisites.md) for configuration requirements
3. Check [GitHub Issues](https://github.com/judeper/FSI-AgentGov-Solutions/issues)
4. Submit new issue with:
   - Flow name and flow run ID
   - Error message (full text)
   - Steps to reproduce
   - Environment details (tenant type, licensing tier)

---

*Agent 365 Lifecycle Governance v1.1.3*
