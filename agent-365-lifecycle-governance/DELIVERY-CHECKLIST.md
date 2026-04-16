# Agent 365 Lifecycle Governance — Delivery Checklist

**Version:** v1.1.0
**Solution:** Agent 365 Lifecycle Governance

Pre-deployment validation and post-deployment verification tasks. Complete each phase in order.

---

## Phase 0: Licensing and Tenant Readiness

- [ ] Confirm Microsoft Agent 365 GA availability (target: May 1, 2026)
- [ ] Confirm Agent 365 licensing is active in target tenant ($15/user/month or M365 E7)
- [ ] Confirm Entra ID Governance P2 licensing for access reviews and lifecycle workflows
- [ ] Confirm Power Automate Premium licensing for HTTP and Power Platform Admin connectors
- [ ] Confirm `AuditLog.Read.All` permission is grantable in the target FSI tenant

---

## Phase 1: Entra ID Setup

- [ ] Create `FSI-AllAgentIdentities` security group
- [ ] Create `FSI-Zone3-Agents` security group
- [ ] Create Lifecycle Workflow 1: `Agent-Sponsor-Mover-Notification` — record workflow ID: __________
- [ ] Create Lifecycle Workflow 2: `Agent-Sponsor-Leaver-Deactivation` — record workflow ID: __________
- [ ] Create Conditional Access policy: `FSI-Zone3-Agent-Conditional-Access`
- [ ] Grant all 7 API permissions to the automation account's Managed Identity
- [ ] Verify all permissions are admin-consented

---

## Phase 2: Dataverse Schema Deployment

- [ ] Run `create_alg_dataverse_schema.py --dry-run` to preview
- [ ] Run `create_alg_dataverse_schema.py` to deploy tables and columns
- [ ] Verify alternate key on `fsi_agentlifecyclerecord` is active (may take up to 30 minutes)
- [ ] Run `create_alg_environment_variables.py` to deploy environment variables
- [ ] Run `create_alg_connection_references.py` to deploy connection references
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

## Phase 3: API Validation (Frontier-Enabled Test Tenant)

- [ ] Validate sponsor PATCH body schema (`@odata.bind` pattern) — confirm sponsor is actually set after the PATCH by calling GET
- [ ] Validate supported OData filter syntax for unsponsored agents — document whether server-side filter works or client-side filtering is required
- [ ] Validate access review creation with `principalScopes` + `resourceScopes` returns 201 for agent service principals
- [ ] Validate PPAC Bots API (`api-version=2022-03-01-preview`) returns `lastModifiedTime` and `publishedOn` for Copilot Studio agents
- [ ] Validate Entra Lifecycle Workflow tasks work for agent identities
- [ ] Document confirmed working API patterns in this section

### Confirmed API Behaviors

| API | Status | Notes |
|-----|--------|-------|
| Sponsor PATCH (@odata.bind) | ☐ Confirmed / ☐ Modified | |
| Unsponsored agent filter | ☐ Server-side / ☐ Client-side | |
| Access review creation | ☐ Confirmed / ☐ Modified | |
| PPAC Bots API fields | ☐ Confirmed / ☐ Modified | |
| Lifecycle Workflow tasks | ☐ Confirmed / ☐ Modified | |

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
- [ ] Run `Validate-LifecycleCompliance.ps1` to verify initial compliance state
- [ ] Verify immutability: confirm `fsi_lifecyclecomplianceevent` has no delete capability for non-admin roles
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
  - SEC 17a-3/4: 7-year retention on compliance event table (LTR)
  - FINRA 4511: Immutable compliance event records

---

## Pre-Handoff Notes

### Agent 365 API Maturity

The Agent 365 `agentRegistry` endpoints are in Graph beta. Confirm the following before go-live:

- Sponsor PATCH body format is stable
- OData filter support for unsponsored agent queries
- Access review API supports agent service principal types

Document any API workarounds applied during Phase 3.

### Feature Flag

The `IsAgent365LifecycleEnabled` feature flag should remain `"false"` until:

1. All 6 flows are built and individually tested
2. API validation (Phase 3) is complete
3. Baseline population is verified

### Long-Term Retention (LTR)

The `fsi_lifecyclecomplianceevent` table is designed for Dataverse Long-Term Retention to support SEC 17a-3/4 7-year retention requirements. LTR must be enabled manually on the table after deployment. Verify that the target environment is a Managed Environment, as LTR is only available in Managed Environments.

---

## Files NOT to Include in Customer Package

Do NOT include these repository management files:

- ❌ `.git/` folder
- ❌ `.github/` folder
- ❌ `.claude/` folder
- ❌ `.codex/` folder
- ❌ `scripts/hooks/` (internal automation only)

---

**Package Version:** v1.1.0
**Solution:** Agent 365 Lifecycle Governance
