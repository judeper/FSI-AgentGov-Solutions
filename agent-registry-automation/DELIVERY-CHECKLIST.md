# Agent Registry Automation — Customer Delivery Checklist

**Version:** v1.0.0
**Solution:** Agent Registry Automation

---

## Phase 0: Pre-Engagement Validation

- [ ] Confirm customer has Power Platform Premium licensing
- [ ] Confirm target environment is a **Managed Environment** (required for LTR)
- [ ] Confirm customer has Power Platform Admin role available
- [ ] Confirm customer has Entra Global Admin or Application Administrator for service principal setup
- [ ] Confirm Microsoft Teams is available for approval workflows
- [ ] Review customer DLP policies for potential connector blocks (Office 365 Users, HTTP with Microsoft Entra ID)

---

## Phase 1: Documentation Review

- [ ] Review `README.md` — solution overview and architecture
- [ ] Review `docs/dataverse-schema.md` — table definitions, option sets, and alternate keys
- [ ] Review `docs/flow-configuration.md` — manual build instructions for all 4 flows
- [ ] Review `docs/prerequisites.md` — licensing, permissions, and environment requirements
- [ ] Review `docs/troubleshooting.md` — common issues and resolutions
- [ ] Review `templates/agent-registry-config.sample.json` — sample zone policy configuration

---

## Phase 2: Environment Preparation

- [ ] Verify target environment is Managed Environment
- [ ] Register Microsoft Entra ID application for Bots API and Graph API access
- [ ] Grant required API permissions and admin consent (see `docs/prerequisites.md`)
- [ ] Create client secret and store securely (Azure Key Vault recommended)
- [ ] Verify Dataverse capacity is sufficient for agent inventory and compliance events
- [ ] Confirm DLP policies allow required connectors:
  - Dataverse
  - HTTP with Microsoft Entra ID
  - Office 365 Users (for SLA time zone lookup)
  - Microsoft Teams
  - Approvals

---

## Phase 3: Dataverse Schema Deployment

- [ ] Run `scripts/create_dataverse_schema.py` with `--dry-run` to preview changes
- [ ] Deploy schema to target environment
- [ ] Verify all 4 tables are created:
  - `fsi_agentinventory`
  - `fsi_registrationrequest`
  - `fsi_agentcomplianceevent`
  - `fsi_ownershipaudit`
- [ ] Verify alternate key on `fsi_agentinventory` (`fsi_agentid` + `fsi_environmentid`) is **Active**
  - **Note:** Alternate key status may show **Pending** for up to 30 minutes after creation. Do not proceed to Flow 1 until status is **Active**.
- [ ] Verify all option sets are created with correct values
- [ ] Enable Dataverse Long-Term Retention (LTR) on `fsi_agentcomplianceevent` table

---

## Phase 4: Environment Variables and Connection References

- [ ] Run `scripts/create_environment_variables.py` to deploy environment variables
- [ ] Configure current values for all environment variables:
  - `fsi_ARA_TenantId`
  - `fsi_ARA_DataverseEnvironment`
  - `fsi_ARA_GovernanceTeamEmail`
  - `fsi_ARA_TeamsChannelId`
  - `fsi_ARA_ApprovalDeadlineDays`
  - `fsi_ARA_EntraRegistrySyncEnabled`
  - `fsi_ARA_DefaultTimeZone`
- [ ] Run `scripts/create_connection_references.py` to deploy connection references
- [ ] Bind each connection reference to an active connection:
  - `fsi_cr_ara_dataverse` — Dataverse
  - `fsi_cr_ara_http_azuread` — HTTP with Microsoft Entra ID (Bots API + Graph API)
  - `fsi_cr_ara_teams` — Microsoft Teams
  - `fsi_cr_ara_approvals` — Approvals

---

## Phase 5: Power Automate Flow Build

Follow the step-by-step instructions in `docs/flow-configuration.md` for each flow:

- [ ] **Flow 1: Discover-UnregisteredAgents-Daily**
  - Build trigger (Recurrence — daily)
  - Build environment enumeration (HTTP with Microsoft Entra ID → Bots API)
  - Build Dataverse upsert logic (alternate key)
  - Build Zone 3 auto-quarantine branch
  - Build compliance event logging
  - Build Teams notification
  - Test with a single environment before enabling full scan
- [ ] **Flow 2: Enforce-RegistrationApproval-Gate**
  - Build trigger (Dataverse — when registration request created)
  - Build SLA calculation logic
  - Build Teams approval action
  - Build approval outcome handling (Approved/Rejected/Timeout)
  - Build escalation logic
  - Build compliance event logging
  - Test with a manual registration request
- [ ] **Flow 3: Sync-EntraAgentRegistry** (optional — feature-flagged)
  - Build trigger (Dataverse — when agent inventory updated)
  - Build feature flag gate (`fsi_ARA_EntraRegistrySyncEnabled`)
  - Build Entra Agent Registry API call
  - Build sync status update
  - **Note:** Skip if Entra Agent Registry API is not available
- [ ] **Flow 4: Detect-OrphanedAgents-Weekly**
  - Build trigger (Recurrence — weekly)
  - Build Graph API user status check
  - Build orphan classification logic
  - Build notification and reassignment workflow
  - Build compliance event logging
  - Test with known inactive user accounts

---

## Phase 6: Baseline Population

- [ ] Run `scripts/Deploy-AgentRegistry-Baseline.ps1` to seed the agent inventory
- [ ] Review baseline export output for accuracy
- [ ] Verify agent records appear in Dataverse with correct zone classifications
- [ ] Confirm agent count matches expected number from Bots API

---

## Phase 7: Validation

- [ ] Run `scripts/Validate-AgentRegistry-Compliance.ps1` for automated validation
- [ ] Verify Flow 1 completes a discovery scan without errors
- [ ] Verify Flow 2 processes a test registration request end-to-end
- [ ] Verify Flow 4 identifies a known orphaned agent (if available)
- [ ] Verify compliance events are written to `fsi_agentcomplianceevent`
- [ ] Verify Teams notifications are delivered to the configured channel
- [ ] Verify no DLP policy blocks on required connectors

---

## Phase 8: Go-Live and Handoff

- [ ] Enable all flows in production
- [ ] Document any environment-specific customizations
- [ ] Provide customer with `docs/troubleshooting.md` for operational support
- [ ] Schedule quarterly review cadence for:
  - Orphan detection results
  - Registration request SLA compliance
  - Compliance event volume and trends
  - Zone classification accuracy

---

## Pre-Handoff Notes

### BotFrameworkEndpoint Field Name

The `properties.botFrameworkEndpoint` field path in the Bots API response has been documented based on API specification review. **Confirm the exact field path** against a live API response in the customer's environment before enabling Flow 1 in production. The flow includes error handling for missing or renamed fields.

### Office 365 Users Connector (DLP Consideration)

Flow 2 uses the Office 365 Users connector to look up the approver's time zone for business-day SLA calculations. If the customer's DLP policies classify this connector as "Blocked," configure the `fsi_ARA_DefaultTimeZone` environment variable as a fallback (e.g., `Eastern Standard Time`).

### Entra Agent Registry Availability

Flow 3 (Sync-EntraAgentRegistry) is feature-flagged off by default. The Entra Agent Registry API requires Agent 365 / Frontier licensing and may not be available in all tenants. Confirm API availability before enabling this flow.

### Long-Term Retention (LTR)

The `fsi_agentcomplianceevent` table is designed for Dataverse Long-Term Retention to support SEC 17a-3/4 7-year retention requirements. LTR must be enabled manually on the table after deployment. Verify that the target environment is a Managed Environment, as LTR is only available in Managed Environments.

---

## Files NOT to Include in Customer Package

Do NOT include these repository management files:

- ❌ `.git/` folder
- ❌ `.github/` folder
- ❌ `.claude/` folder
- ❌ `.codex/` folder
- ❌ `scripts/hooks/` (internal automation only)

---

**Package Version:** v1.0.0
**Release Date:** March 2026
**Solution:** Agent Registry Automation
