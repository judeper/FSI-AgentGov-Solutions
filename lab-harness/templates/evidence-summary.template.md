# Lab Validation Summary

- **Solution:** {{solution}}
- **Execution mode:** {{executionMode}}
- **Result:** {{result}}
- **Exit code:** {{exitCode}}
- **Generated (UTC):** {{generatedAtUtc}}
- **Plan path:** {{planPath}}
- **Ownership manifest:** {{ownershipManifest}}

## Steps

{{#steps}}
- `{{id}}` · channel=`{{channel}}` · adapter=`{{adapter}}` · status=`{{status}}` · duration={{durationSeconds}}s
{{/steps}}

## Notes

- This summary is metadata-only and should not include raw tenant evidence.
- Runtime/API validation and portal/UI validation are separate channels by design.
- PlanOnly runs validate structure without claiming live execution success.
