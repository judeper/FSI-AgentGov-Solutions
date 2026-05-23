# Reviewer app managed solution placeholder

This folder is reserved for the managed model-driven app solution exported by [`..\..\scripts\provision_reviewer_app.ps1`](../../scripts/provision_reviewer_app.ps1).

- Expected artifact: `AgentIntakeReviewerApp_managed.zip`
- Generation path: run `pwsh .\agent-intake\scripts\provision_reviewer_app.ps1 -EnvironmentUrl https://<org>.crm.dynamics.com -Export` after the reviewer views, security roles, and app shell are provisioned in a live environment
- First producer: the lab / e2e-validation workstream captures the first real export once the live environment is available
- Policy reference: ADR-011 in [`..\..\docs\decisions.md`](../../docs/decisions.md) explains why the managed model-driven app package is treated as an allowed metadata artifact for this workstream

The placeholder stays in source control so the export path is stable even before the first lab run.
