# Agent 365 Lifecycle Governance — Delivery Checklist

**Version:** v1.1.5
**Solution:** Agent 365 Lifecycle Governance

Pre-deployment validation and post-deployment verification tasks. Complete each phase in order.

---

## Phase 0: Licensing and Tenant Readiness

- [ ] Confirm Microsoft Agent 365 Commercial GA availability and tenant SKU eligibility
- [ ] Confirm Microsoft Agent 365 licensing is active in target tenant and current pricing/SKU eligibility is documented
- [ ] Confirm Microsoft Entra ID Governance or Microsoft Entra Suite licensing for access reviews and sponsor-user lifecycle workflows
- [ ] Confirm Power Automate Premium licensing for HTTP and Power Platform Admin connectors
- [ ] Confirm `AuditLog.Read.All` permission is grantable in the target FSI tenant

---

## Phase 1: Entra ID Setup

- [ ] Create `FSI-AgentSponsors` security group for sponsor-user lifecycle workflow scope
- [ ] Create `FSI-AllAgentIdentities` security group for inventory/reporting
- [ ] Create `FSI-Zone3-Agents` security group for inventory/reporting
- [ ] Create Lifecycle Workflow 1: `Agent-Sponsor-Mover-Notification` — record workflow ID: __________
- [ ] Create Lifecycle Workflow 2: `Agent-Sponsor-Leaver-Deactivation` — record workflow ID: __________
- [ ] Create workload identity Conditional Access policy: `FSI-Zone3-Agent-Conditional-Access` with direct service-principal assignment
- [ ] Grant all 8 API permissions to the automation identity (managed identity or workload identity)
- [ ] Verify all permissions are admin-consented

---

## Phase 2: Dataverse Schema Deployment

- [ ] Run `create_alg_dataverse_schema.py --dry-run --auth-mode managed-identity` (or `--interactive`) to preview
- [ ] Run `create_alg_dataverse_schema.py --auth-mode managed-identity` (or `--interactive`) to deploy tables and columns
- [ ] Verify alternate key on `fsi_agentlifecyclerecord` is active (may take up to 30 minutes)
- [ ] Run `create_alg_environment_variables.py --auth-mode managed-identity` (or `--interactive`) to deploy environment variables
- [ ] Run `create_alg_connection_references.py --auth-mode managed-identity` (or `--interactive`) to deploy connection references
- [ ] Verify entity set names:
  - `fsi_agentlifecyclerecords` — confirmed: ☐
  - `fsi_sponsorassignments` — confirmed: ☐
  - `fsi_accessreviews` — confirmed: ☐
  - `fsi_deactivationrequests` — confirmed: ☐
  - `fsi_lifecyclecomplianceevents` — confirmed: ☐
- [ ] Record confirmed entity set names: __________
- [ ] Verify choice field integer values against deployed solution XML
- [ ] Record confirmed `fsi_ALG_reviewstatus` values: Pending=_____ In Progress=_____ Completed=_____ Overdue=_____ Escalated=_____
- [ ] Configure Dataverse Long-Term Retention on `fsi_lifecyclecomplianceevent` for 7-year retention (Power Platform Admin Center)

---

## Phase 3: API Validation (Non-Production Tenant)

- [ ] Validate Agent 365 `agentInstances` owner PATCH body schema (`ownerIds` collection) — confirm owner is actually set after the PATCH by calling GET
- [ ] Validate supported OData filter syntax for ownerless agent instances — document whether server-side filter works or client-side filtering is required
- [ ] Validate access review creation with `principalScopes` + `resourceScopes` returns 201 for agent service principals
- [ ] Validate PPAC Bots API (`api-version=2022-03-01-preview`) returns `lastModifiedTime` and `publishedOn` for Copilot Studio agents
- [ ] Validate Entra Lifecycle Workflow activation uses sponsor-user subjects, not agent service principals
- [ ] Document confirmed working API patterns in this section

### Confirmed API Behaviors

| API | Status | Notes |
|-----|--------|-------|
| Owner PATCH (`ownerIds`) | ☐ Confirmed / ☐ Modified | |
| Unsponsored agent filter | ☐ Server-side / ☐ Client-side | |
| Access review creation | ☐ Confirmed / ☐ Modified | |
| PPAC Bots API fields | ☐ Confirmed / ☐ Modified | |
| Sponsor-user Lifecycle Workflow activation | ☐ Confirmed / ☐ Modified | |

---

## Phase 4: Flow Deployment

- [ ] Set all environment variable values (see `templates/lifecycle-config.sample.json` for reference)
- [ ] Bind connection references to active connections
- [ ] Build and test Flow 1 (Enforce-SponsorAssignment-OnOnboard)
- [ ] Build and test Flow 2 (Schedule-AccessReview-ZoneBased)
- [ ] Build and test Flow 3 (Detect-InactiveAgents-Daily)
- [ ] Build and test Flow 4 (Execute-DeactivationWorkflow)
- [ ] Build and test Flow 5 (Monitor-SponsorChanges-Weekly)
- [ ] Build and test Flow 6 (Check-DeletionHold-Daily)
- [ ] Verify `IsAgent365LifecycleEnabled = "false"` causes graceful termination in all flows
- [ ] Set `IsAgent365LifecycleEnabled = "true"` to activate

---

## Phase 5: Post-Deployment Validation

- [ ] Run `Deploy-LifecycleGovernance-Baseline.ps1` to capture baseline
- [ ] Run `Test-LifecycleCompliance.ps1` to verify initial compliance state
- [ ] Verify append-only operation: confirm `fsi_lifecyclecomplianceevent` has no delete capability for non-admin roles
- [ ] Verify Dataverse LTR is active on `fsi_lifecyclecomplianceevent`
- [ ] Test end-to-end: register a test agent → sponsor assignment → access review → deactivation → deletion hold → deletion

---

## Phase 6: Go-Live and Handoff

- [ ] Enable all flows in production
- [ ] Document any environment-specific customizations
- [ ] Provide customer with `docs/troubleshooting.md` for operational support
- [ ] Schedule review cadence:
  - Quarterly: Sponsor coverage and access review completion rates
  - Monthly: Deactivation pipeline and deletion hold status
  - Weekly: Compliance event volume and anomaly review
- [ ] Confirm regulatory record retention:
  - SEC 17a-3/4: retention on compliance event table configured per firm record schedule (LTR and compliant archive where required)
  - FINRA 4511: Append-only compliance event records (requires no-delete security roles)

---

## Pre-Handoff Notes

### Agent 365 API Maturity

The Agent 365 Agent Registry and Package Management APIs are in Graph beta/preview and Microsoft Learn includes May 2026 convergence notices. Confirm the following before go-live:

- `agentInstances` list/update endpoint and `ownerIds` PATCH body format are stable in the target tenant
- OData filter support for ownerless agent instance queries
- Access review API supports the service principal or agent identity object selected for review

Document any API workarounds applied during Phase 3.

### Feature Flag

The `IsAgent365LifecycleEnabled` feature flag should remain `"false"` until:

1. All 6 flows are built and individually tested
2. API validation (Phase 3) is complete
3. Baseline population is verified

### Long-Term Retention (LTR)

The `fsi_lifecyclecomplianceevent` table is designed for Dataverse Long-Term Retention to support firm-defined record schedules. LTR must be enabled manually on the table after deployment. Verify that the target environment is a Managed Environment, as LTR is only available in Managed Environments, and add a SEC 17a-4-compliant archive where required by the firm's obligations.

---

## Files NOT to Include in Customer Package

Do NOT include these repository management files:

- ❌ `.git/` folder
- ❌ `.github/` folder
- ❌ `.claude/` folder
- ❌ `.codex/` folder
- ❌ `scripts/hooks/` (internal automation only)

---

**Package Version:** v1.1.5
**Solution:** Agent 365 Lifecycle Governance
