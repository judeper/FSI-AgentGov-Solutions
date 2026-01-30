# Templates

Sample data and schema definitions for Environment Lifecycle Management.

## Files

| File | Description |
|------|-------------|
| `environment-request-sample.json` | Sample EnvironmentRequest record |
| `json-output-schema.json` | Copilot Studio JSON output schema for Power Automate |

## environment-request-sample.json

A sample `EnvironmentRequest` record showing all fields populated for a Zone 3 request.

**Use this to:**

- Understand the data structure
- Test Power Automate flows
- Validate Dataverse schema

## json-output-schema.json

The JSON schema for the Copilot Studio agent output when submitting to Power Automate.

**Use this to:**

- Configure Power Automate trigger input schema
- Validate agent output
- Document the interface contract

### Schema Overview

```
{
  "requestId": GUID,
  "timestamp": ISO datetime,
  "requester": {
    "upn": email,
    "displayName": string,
    "department": string
  },
  "environment": {
    "name": string (DEPT-Purpose-TYPE),
    "type": Production|Sandbox|Developer,
    "region": unitedstates|europe|unitedkingdom|australia
  },
  "classification": {
    "zone": 1|2|3,
    "autoFlags": string[],
    "dataSensitivity": Public|Internal|Confidential|Restricted,
    "zoneRationale": string (Zone 3 only)
  },
  "access": {
    "securityGroupId": GUID (Zone 2/3),
    "securityGroupName": string,
    "expectedUserCount": number
  },
  "businessContext": {
    "purpose": string,
    "expectedUsers": string
  },
  "approvalRequired": {
    "manager": boolean,
    "compliance": boolean,
    "zoneReviewRequired": boolean
  }
}
```

## Usage in Power Automate

### Flow Trigger Configuration

1. Create Power Automate flow with "When a HTTP request is received" trigger
2. Copy schema from `json-output-schema.json` into the trigger
3. Save flow and copy the HTTP POST URL
4. Configure Copilot Studio action to call the flow URL

### Mapping to Dataverse

| JSON Field | Dataverse Column |
|------------|------------------|
| `environment.name` | `fsi_environmentname` |
| `environment.type` | `fsi_environmenttype` |
| `environment.region` | `fsi_region` |
| `classification.zone` | `fsi_zone` |
| `classification.autoFlags` | `fsi_zoneautoflags` |
| `classification.dataSensitivity` | `fsi_datasensitivity` |
| `classification.zoneRationale` | `fsi_zonerationale` |
| `access.securityGroupId` | `fsi_securitygroupid` |
| `businessContext.purpose` | `fsi_businessjustification` |
| `requester.upn` | `fsi_requester` (lookup) |
