# Power Apps Configuration — Model Risk Management

This guide provides step-by-step instructions for manually building two Power Apps that support the MRM automation solution. These apps are designed to help meet institution-specific model risk management requirements for AI agents governed by Copilot Studio, using OCC Bulletin 2026-13 (formerly OCC Bulletin 2011-12) terminology and Fed SR 26-2 (formerly Fed SR 11-7) principles where applicable.

> **Important:** This guide describes how to build apps in the Power Apps designer. No exported app packages are provided. Administrators should adapt screen layouts, branding, and field placement to their organization's standards.
>
> **Column naming note:** The Dataverse column `fsi_sr117pillar` and its display label "SR 11-7 Pillar" retain the original SR 11-7 name for backward compatibility with existing deployments. The current superseding guidance is Fed SR 26-2 (formerly Fed SR 11-7). Do not rename the column in existing environments.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Dataverse Tables** | All six MRM tables deployed via `create_mrm_dataverse_schema.py` |
| **Environment Variables** | Deployed via `create_mrm_environment_variables.py` |
| **Connection References** | Deployed via `create_mrm_connection_references.py` |
| **Power Automate Flows** | Flow 2 (Score-ModelRisk-OnSubmission) configured per [flow-configuration.md](flow-configuration.md) |
| **Security Roles** | MRM Officer, Validator, and Agent Owner roles configured in Dataverse |
| **Agent Inventory** | `fsi_agentinventory` table available from the agent-registry-automation solution |

---

## App 1: MRM Submission Portal (Canvas App)

### Overview

The MRM Submission Portal provides two core functions:

1. **Agent owner interface** — submit agents for MRM review, track status, and respond to validation findings
2. **MRM team dashboard** — inventory management, filtering, evidence export, and risk rating overrides

This app supports compliance with first-line-of-defense model risk management responsibilities by providing agent owners a structured submission and remediation workflow.

### Create the App

1. Navigate to **make.powerapps.com** → select the target environment
2. Select **+ Create** → **Blank app** → **Blank canvas app**
3. Name: `MRM Submission Portal`
4. Format: **Tablet** (recommended for data-dense screens)
5. Add data sources:
   - `fsi_modelinventory`
   - `fsi_mrmriskrating`
   - `fsi_validationcycle`
   - `fsi_validationfinding`
   - `fsi_agentinventory` (read-only — from agent-registry-automation)

---

### Screen 1 — Submit New Agent for MRM Review

#### Purpose

Displays agents from `fsi_agentinventory` that are registered but do not yet have a corresponding record in `fsi_modelinventory`. Agent owners complete required fields and submit the agent for automated risk scoring via Flow 2.

#### Build Steps

1. **Add a new screen** → select **Blank** layout. Rename to `SubmitScreen`.

2. **Add a header label:**
   - Text: `"Submit Agent for MRM Review"`
   - Font size: 24, bold, positioned at top of screen

3. **Add a Gallery control** for eligible agents:
   - Control type: **Vertical gallery**
   - Rename to `galEligibleAgents`
   - Data source: `fsi_agentinventory`
   - Items formula — filters to agents owned by the current user that are not yet in the model inventory:

     ```
     Filter(
         fsi_agentinventory,
         fsi_ownerupn = User().Email,
         Not(
             fsi_agentid in
             ShowColumns(fsi_modelinventory, "fsi_agentid")
         )
     )
     ```

   - Display in each gallery row: agent name, environment ID, governance zone
   - Add a **Select** button in each row with `OnSelect: Set(varSelectedAgent, ThisItem)`

4. **Add a form panel** (visible when `varSelectedAgent` is set):
   - Add a **label** showing the selected agent name: `varSelectedAgent.fsi_agentname`
   - Add the following **Text Input** controls (all required):

     | Control | Maps To | Type | Notes |
     |---------|---------|------|-------|
     | `txtBusinessFunction` | `fsi_businessfunction` | Multi-line text | Declared use case — drives MRM tier assignment |
     | `txtDataInputs` | `fsi_datainputs` | Multi-line text | Input data sources description |
     | `txtKnownLimitations` | `fsi_knownlimitations` | Multi-line text | Documented limitations per Fed SR 26-2 (formerly SR 11-7) |
     | `txtIntendedUsers` | `fsi_intendedusers` | Single-line text | Target user population |

5. **Add a Submit button:**
   - Text: `"Submit for MRM Review"`
   - OnSelect — triggers Flow 2 (Score-ModelRisk-OnSubmission) and passes submission data:

     ```
     Set(varSubmitResult,
         'Score-ModelRisk-OnSubmission'.Run(
             varSelectedAgent.fsi_agentid,
             varSelectedAgent.fsi_environmentid,
             txtBusinessFunction.Text,
             txtDataInputs.Text,
             txtKnownLimitations.Text,
             txtIntendedUsers.Text,
             User().Email
         )
     );
     Notify("Agent submitted for MRM review.", NotificationType.Success);
     Set(varSelectedAgent, Blank())
     ```

   - DisplayMode: `If(IsBlank(txtBusinessFunction.Text) || IsBlank(txtIntendedUsers.Text), DisplayMode.Disabled, DisplayMode.Edit)`

6. **Add a read-only results panel** (visible after submission):
   - After submission, look up the newly created `fsi_modelinventory` record
   - Display the auto-scored fields as read-only labels:
     - `fsi_mrmtier` — MRM Tier assigned by scoring logic
     - `fsi_currentriskrating` — Composite risk rating
     - `fsi_validationcadence` — Assigned validation cadence
     - `fsi_nextvalidationdue` — Calculated next validation date
     - `fsi_modelid` — Auto-generated MRM ID (format: MRM-{YYYY}-{00000})

---

### Screen 2 — My Agent MRM Status

#### Purpose

Lists all agents owned by the current user from `fsi_modelinventory`, showing MRM lifecycle status. Provides alert banners for agents requiring attention.

#### Build Steps

1. **Add a new screen** → rename to `MyStatusScreen`.

2. **Add alert banners** at the top of the screen:

   - **Findings alert banner** (red/orange background):
     - Visible formula:

       ```
       CountRows(
           Filter(
               fsi_validationfinding,
               fsi_remediationstatus <> 'fsi_mrm_remediationstatus'.Closed,
               fsi_modelinventory_lookup.fsi_ownerupn = User().Email
           )
       ) > 0
       ```

     - Text: `"You have open validation findings requiring response."`

   - **Upcoming validation banner** (yellow background):
     - Visible formula:

       ```
       CountRows(
           Filter(
               fsi_modelinventory,
               fsi_ownerupn = User().Email,
               fsi_nextvalidationdue <= DateAdd(Today(), 30, TimeUnit.Days),
               fsi_nextvalidationdue >= Today()
           )
       ) > 0
       ```

     - Text: `"One or more agents are approaching their next validation due date."`

3. **Add a Gallery control** for the agent inventory:
   - Rename to `galMyAgents`
   - Items formula:

     ```
     Filter(
         fsi_modelinventory,
         fsi_ownerupn = User().Email
     )
     ```

   - Display columns in each gallery row:

     | Column | Source | Format |
     |--------|--------|--------|
     | Agent Name | `ThisItem.fsi_modelname` | Bold text |
     | MRM Tier | `ThisItem.fsi_mrmtier` | Picklist label |
     | Risk Rating | `ThisItem.fsi_currentriskrating` | Color-coded label (Critical=red, High=orange, Medium=yellow, Low=green) |
     | Validation Status | `ThisItem.fsi_validationstatus` | Picklist label |
     | Next Validation Due | `ThisItem.fsi_nextvalidationdue` | Date format |
     | Agent Card | `ThisItem.fsi_agentcardurl` | Hyperlink (visible only when not blank) |

4. **Add color-coding logic** for the risk rating label:
   ```
   Switch(
       ThisItem.fsi_currentriskrating,
       'fsi_mrm_riskrating'.Critical, Color.Red,
       'fsi_mrm_riskrating'.High, Color.OrangeRed,
       'fsi_mrm_riskrating'.Medium, Color.Gold,
       'fsi_mrm_riskrating'.Low, Color.Green,
       Color.Gray
   )
   ```

---

### Screen 3 — Respond to Validation Findings

#### Purpose

Displays open `fsi_validationfinding` records for agents owned by the current user. Allows owners to submit responses and evidence references as part of the remediation workflow.

#### Build Steps

1. **Add a new screen** → rename to `FindingsResponseScreen`.

2. **Add a header label:**
   - Text: `"Open Validation Findings"`

3. **Add a Gallery control** for open findings:
   - Rename to `galOpenFindings`
   - Items formula — sorted by severity ascending so Critical findings appear first:

     ```
     SortByColumns(
         Filter(
             fsi_validationfinding,
             fsi_remediationstatus <> 'fsi_mrm_remediationstatus'.Closed,
             fsi_modelinventory_lookup.fsi_ownerupn = User().Email
         ),
         "fsi_severity",
         SortOrder.Ascending
     )
     ```

   - Display in each gallery row:
     - Finding ID (`fsi_findingid`)
     - Agent Name (via `fsi_modelinventory_lookup.fsi_modelname`)
     - Severity (`fsi_severity`) — with color-coded icon
     - SR 11-7 Pillar (`fsi_sr117pillar`)
     - Finding Category (`fsi_findingcategory`)
     - Finding Description (`fsi_findingdescription`) — truncated to 200 chars in gallery, full text in detail view

4. **Add a Critical findings banner** at the top of the gallery:
   - Background color: Red
   - Visible formula:

     ```
     CountRows(
         Filter(
             galOpenFindings.AllItems,
             fsi_severity = 'fsi_mrm_severity'.Critical
         )
     ) > 0
     ```

   - Text: `"Critical findings require immediate attention."`

5. **Add a detail/response panel** (visible when a gallery item is selected):
   - **Read-only fields:**
     - Finding Description (full text): `galOpenFindings.Selected.fsi_findingdescription`
     - Required Remediation: `galOpenFindings.Selected.fsi_requiredremediation`
     - Due Date: `galOpenFindings.Selected.fsi_duedate`

   - **Editable fields:**

     | Control | Maps To | Type | Notes |
     |---------|---------|------|-------|
     | `txtOwnerResponse` | `fsi_ownerresponse` | Multi-line text | Owner's response to the finding |
     | `txtEvidenceRef` | N/A (passed to flow) | Single-line text | URL or reference to uploaded evidence |

6. **Add a Submit Response button:**
   - Text: `"Submit Response"`
   - OnSelect:

     ```
     Patch(
         fsi_validationfinding,
         galOpenFindings.Selected,
         {
             fsi_ownerresponse: txtOwnerResponse.Text,
             fsi_remediationstatus: 'fsi_mrm_remediationstatus'.'Submitted for Review'
         }
     );
     Notify("Response submitted for validator review.", NotificationType.Success);
     Reset(txtOwnerResponse);
     Reset(txtEvidenceRef)
     ```

   - DisplayMode: `If(IsBlank(txtOwnerResponse.Text), DisplayMode.Disabled, DisplayMode.Edit)`

---

### Screen 4 — MRM Team Inventory View (MRM Officer Role Only)

#### Purpose

Provides MRM Officers with a full inventory table across all tiers and statuses. Supports evidence package export and risk rating override capabilities required for second-line-of-defense model risk management responsibilities.

#### Build Steps

1. **Add a new screen** → rename to `MrmInventoryScreen`.

2. **Add a visibility wrapper** — the entire screen content should be inside a container with:
   - Visible formula (checks for MRM Officer role or governance team membership):

     ```
     // Option A: Check security role via Dataverse
     LookUp(
         'System User Roles',
         User = LookUp(Users, 'Primary Email' = User().Email),
         Role.'Role Name' = "MRM Officer"
     )
     // Option B: Check against GovernanceTeamEmail environment variable
     // Adapt based on your organization's role-checking approach
     ```

   - Add a **fallback label** outside the container:
     - Visible: `!varIsMrmOfficer`
     - Text: `"Access restricted. This view is available to MRM Officers only."`

3. **Add filter controls** at the top of the screen:

   | Control | Type | Options |
   |---------|------|---------|
   | `ddMrmTier` | Dropdown | Choices from `fsi_mrm_mrmtier` + "All" |
   | `ddRiskRating` | Dropdown | Choices from `fsi_mrm_riskrating` + "All" |
   | `ddValidationStatus` | Dropdown | Choices from `fsi_mrm_validationstatus` + "All" |
   | `dpDueFrom` | Date picker | Start of due date range |
   | `dpDueTo` | Date picker | End of due date range |

4. **Add a data table or gallery** for the full inventory:
   - Rename to `galFullInventory`
   - Items formula with dynamic filtering:

     ```
     Filter(
         fsi_modelinventory,
         (ddMrmTier.Selected.Value = "All" || fsi_mrmtier = ddMrmTier.Selected.Value),
         (ddRiskRating.Selected.Value = "All" || fsi_currentriskrating = ddRiskRating.Selected.Value),
         (ddValidationStatus.Selected.Value = "All" || fsi_validationstatus = ddValidationStatus.Selected.Value),
         (IsBlank(dpDueFrom.SelectedDate) || fsi_nextvalidationdue >= dpDueFrom.SelectedDate),
         (IsBlank(dpDueTo.SelectedDate) || fsi_nextvalidationdue <= dpDueTo.SelectedDate)
     )
     ```

   - Display columns:

     | Column | Source |
     |--------|--------|
     | Model ID | `fsi_modelid` |
     | Agent Name | `fsi_modelname` |
     | MRM Tier | `fsi_mrmtier` |
     | Risk Rating | `fsi_currentriskrating` |
     | Validation Status | `fsi_validationstatus` |
     | Owner | `fsi_ownerupn` |
     | MRM Officer | `fsi_mrmofficerupn` |
     | Next Validation Due | `fsi_nextvalidationdue` |
     | Last Validated | `fsi_lastvalidateddate` |
     | MRM Status | `fsi_mrmstatus` |

5. **Add an Export button** for examiner evidence packages:
   - Text: `"Export Evidence Package"`
   - OnSelect — generates a CSV export of the currently filtered inventory. Use a Power Automate flow triggered by button press, or use the built-in `Export` capability:

     ```
     // Option: Trigger a flow that queries fsi_modelinventory with the same
     // filters and returns a CSV file via email or SharePoint.
     'Export-MRM-EvidencePackage'.Run(
         ddMrmTier.Selected.Value,
         ddRiskRating.Selected.Value,
         ddValidationStatus.Selected.Value,
         Text(dpDueFrom.SelectedDate, "yyyy-MM-dd"),
         Text(dpDueTo.SelectedDate, "yyyy-MM-dd")
     )
     ```

6. **Add an Override button** (opens risk rating override form):
   - Text: `"Override Risk Rating"`
   - Visible: `!IsBlank(galFullInventory.Selected)`
   - OnSelect: `Set(varShowOverrideForm, true)`

7. **Add a risk rating override form** (overlay panel):
   - Visible: `varShowOverrideForm`
   - Data source: `fsi_mrmriskrating`
   - Fields:

     | Control | Maps To | Type | Notes |
     |---------|---------|------|-------|
     | `ddOverrideRating` | `fsi_compositerating` | Dropdown | New composite rating |
     | `txtOverrideRationale` | `fsi_overriderationale` | Multi-line text | Rationale for override (required) |

   - Submit button OnSelect:

     ```
     Patch(
         fsi_mrmriskrating,
         LookUp(
             fsi_mrmriskrating,
             fsi_modelinventory_lookup = galFullInventory.Selected,
             fsi_iscurrent = true
         ),
         {
             fsi_mrmofficeroverride: true,
             fsi_overriderationale: txtOverrideRationale.Text,
             fsi_overrideapprovedby: User().Email,
             fsi_compositerating: ddOverrideRating.Selected.Value
         }
     );
     Set(varShowOverrideForm, false);
     Notify("Risk rating override applied.", NotificationType.Success)
     ```

---

### Security Configuration

| Rule | Implementation |
|------|----------------|
| **Screen 4 visibility** | Check if user has MRM Officer security role or is a member of the GovernanceTeamEmail distribution list. Hide Screen 4 navigation for non-MRM-officer users. |
| **Row-level filtering** | Screens 1–3 filter all queries by `fsi_ownerupn = User().Email` so agent owners see only their own agents and findings. |
| **Submit restrictions** | Submit buttons require all mandatory fields to be populated before enabling. |
| **Read-only post-submission** | After submission on Screen 1, auto-scored fields display as read-only labels (not editable inputs). |

#### Navigation Configuration

Add a left navigation panel or tab bar with the following items:

| Tab | Screen | Visible To |
|-----|--------|------------|
| Submit Agent | `SubmitScreen` | All authenticated users |
| My Status | `MyStatusScreen` | All authenticated users |
| My Findings | `FindingsResponseScreen` | All authenticated users |
| MRM Inventory | `MrmInventoryScreen` | MRM Officer role only |

Set the default screen to `MyStatusScreen`.

---

## App 2: Validation Workbench (Model-Driven App)

### Overview

The Validation Workbench is a model-driven app that provides independent validators with a structured workflow interface for reviewing and closing validation cycles. It supports compliance with second-line-of-defense model risk management validation requirements by enforcing one-directional status transitions, minimum documentation lengths, and severity-based blocking rules.

### Create the App

1. Navigate to **make.powerapps.com** → select the target environment
2. Select **+ Create** → **Blank app** → **Blank model-driven app**
3. Name: `Validation Workbench`
4. Add the following tables to the app:

   | Table | Access Level |
   |-------|-------------|
   | `fsi_modelinventory` | Read only |
   | `fsi_validationcycle` | Full CRUD for assigned validator |
   | `fsi_validationfinding` | Create/Update for assigned validator |
   | `fsi_mrmriskrating` | Read only |
   | `fsi_monitoringrecord` | Read only |

---

### Key Views

Configure the following views in the Validation Workbench. Each view is created in the Dataverse table designer and then added to the model-driven app's site map.

#### View 1 — My Active Validation Cycles

- **Table:** `fsi_validationcycle`
- **Filter:** `fsi_validatorupn` equals current user AND `fsi_cyclestatus` is not `Validated` AND `fsi_cyclestatus` is not `Rejected`
- **Columns:**

  | Column | Logical Name | Width |
  |--------|-------------|-------|
  | Cycle ID | `fsi_cycleid` | 120px |
  | Agent Name | `fsi_modelinventory_lookup` (display name) | 200px |
  | MRM Tier at Start | `fsi_mrmtieratstart` | 120px |
  | Cycle Status | `fsi_cyclestatus` | 140px |
  | Validation Type | `fsi_validationtype` | 140px |
  | Assigned Date | `fsi_assigneddate` | 130px |
  | Remediation Due | `fsi_remediationduedate` | 130px |
  | SLA Breach | `fsi_slabreachflag` | 80px |

- **Sort:** `fsi_assigneddate` ascending (oldest first)
- **Default view** for Validator role

#### View 2 — All Open Cycles

- **Table:** `fsi_validationcycle`
- **Filter:** `fsi_cyclestatus` is not `Validated` AND `fsi_cyclestatus` is not `Rejected`
- **Columns:** Same as View 1, plus `fsi_validatorupn` (Validator)
- **Sort:** `fsi_cyclestatus` ascending, then `fsi_remediationduedate` ascending
- **Access:** MRM Officer role only — set via security role on the view

#### View 3 — Findings by Severity

- **Table:** `fsi_validationfinding`
- **Filter:** `fsi_remediationstatus` is not `Closed`
- **Columns:**

  | Column | Logical Name | Width |
  |--------|-------------|-------|
  | Finding ID | `fsi_findingid` | 120px |
  | Agent Name | `fsi_modelinventory_lookup` | 200px |
  | Cycle ID | `fsi_validationcycle_lookup` | 120px |
  | Severity | `fsi_severity` | 100px |
  | SR 11-7 Pillar | `fsi_sr117pillar` | 140px |
  | Category | `fsi_findingcategory` | 150px |
  | Remediation Status | `fsi_remediationstatus` | 140px |
  | Due Date | `fsi_duedate` | 120px |

- **Sort:** `fsi_severity` ascending (Critical = 100000001 first)
- **Group by:** `fsi_validationcycle_lookup` (Cycle)

#### View 4 — Cycles Approaching SLA Breach

- **Table:** `fsi_validationcycle`
- **Filter:** `fsi_cyclestatus` is not `Validated` AND `fsi_cyclestatus` is not `Rejected` AND `fsi_slabreachflag` equals `No` AND `fsi_remediationduedate` is within the next 5 business days
- **Columns:** Same as View 1
- **Sort:** `fsi_remediationduedate` ascending
- **Notes:** The "next 5 business days" filter uses the Dataverse relative date operator **Next X Days** with a value of `7` (to approximate 5 business days). For precise business-day calculations, supplement with a Power Automate flow that sets `fsi_slabreachflag`.

##### View Configuration Steps

For each view:

1. Navigate to **Tables** → select the target table → **Views**
2. Select **+ New view** → enter the view name
3. Add columns using **+ Table columns** → drag columns into desired order
4. Configure filters using **Edit filters** → add conditions as specified above
5. Set sort order via **Sort by** in the view properties
6. Save and publish the view
7. In the model-driven app designer, add the view to the appropriate table's view list

---

### Key Forms

#### Form 1 — Validation Cycle Form

- **Table:** `fsi_validationcycle`
- **Form type:** Main form
- **Purpose:** Validators update cycle status, enter outcome rationale, and close cycles

##### Form Layout

**Header section:**

| Field | Logical Name | Mode | Notes |
|-------|-------------|------|-------|
| Cycle ID | `fsi_cycleid` | Read-only | Auto-generated |
| Agent Name | `fsi_modelinventory_lookup` | Read-only | Lookup display |
| MRM Tier at Start | `fsi_mrmtieratstart` | Read-only | Captured at cycle creation |
| Risk Rating at Start | `fsi_ratingatstart` | Read-only | Captured at cycle creation |

**Status section:**

| Field | Logical Name | Mode | Notes |
|-------|-------------|------|-------|
| Cycle Status | `fsi_cyclestatus` | Editable | One-directional transitions only (see Business Rules) |
| Validation Type | `fsi_validationtype` | Read-only | Set at cycle creation |
| Validator | `fsi_validatorupn` | Read-only for validators; editable for MRM Officers | Assigned validator UPN |
| SLA Breach | `fsi_slabreachflag` | Read-only | Set by monitoring flow |

**Timeline section:**

| Field | Logical Name | Mode |
|-------|-------------|------|
| Submitted Date | `fsi_submitteddate` | Read-only |
| Assigned Date | `fsi_assigneddate` | Read-only |
| Validation Start | `fsi_validationstartdate` | Editable |
| Findings Issued | `fsi_findingsissueddate` | Read-only (auto-set) |
| Remediation Due | `fsi_remediationduedate` | Editable (MRM Officer only) |
| Remediation Submitted | `fsi_remediationsubmitteddate` | Read-only |
| Validation Completed | `fsi_validationcompleteddate` | Read-only (auto-set) |

**Outcome section** (visible when cycle status = `Findings Issued`, `Remediated`, or `Validated`):

| Field | Logical Name | Mode | Notes |
|-------|-------------|------|-------|
| Validation Outcome | `fsi_validationoutcome` | Editable | Required when closing cycle |
| Outcome Rationale | `fsi_outcomerationale` | Editable | Min 100 characters for outcomes other than "Validated - No Findings" |

**Related records sub-grid:**
- Add a sub-grid showing `fsi_validationfinding` records related to this cycle via `fsi_validationcycle_lookup`
- Columns: Finding ID, Severity, Category, Remediation Status
- Sort by `fsi_severity` ascending

##### Form Build Steps

1. Navigate to **Tables** → `fsi_validationcycle` → **Forms**
2. Select **+ New form** → **Main form** → name: `Validation Cycle Form`
3. Add a **Header** section with 4 columns — drag in the header fields listed above
4. Add a **1-column tab** named `Status` → add the status fields
5. Add a **2-column tab** named `Timeline` → arrange date fields chronologically
6. Add a **1-column tab** named `Outcome` → add outcome fields
7. Add a **Sub-grid** at the bottom:
   - Table: `fsi_validationfinding`
   - Related records: filter by `fsi_validationcycle_lookup` = current record
   - Columns: Finding ID, Severity, Category, Remediation Status
8. Save and publish

#### Form 2 — Finding Form

- **Table:** `fsi_validationfinding`
- **Form type:** Main form
- **Purpose:** Validators create findings with required classification, severity, and documentation

##### Form Layout

**Header section:**

| Field | Logical Name | Mode | Notes |
|-------|-------------|------|-------|
| Finding ID | `fsi_findingid` | Read-only | Auto-generated |
| Agent Name | `fsi_modelinventory_lookup` | Read-only | Lookup display |
| Cycle ID | `fsi_validationcycle_lookup` | Read-only | Set at creation |

**Classification section (all required):**

| Field | Logical Name | Mode | Options |
|-------|-------------|------|---------|
| SR 11-7 Pillar | `fsi_sr117pillar` | Required | Pillar 1 (Development), Pillar 2 (Validation), Pillar 3 (Governance) |
| Finding Category | `fsi_findingcategory` | Required | Conceptual Soundness, Data Integrity, Performance, Bias/Fairness, Documentation, Access Control, Monitoring Gap, Scope Limitation |
| Severity | `fsi_severity` | Required | Critical, High, Medium, Low |

**Details section:**

| Field | Logical Name | Mode | Validation |
|-------|-------------|------|------------|
| Finding Description | `fsi_findingdescription` | Required | Minimum 100 characters |
| Required Remediation | `fsi_requiredremediation` | Required | Minimum 50 characters |
| Due Date | `fsi_duedate` | Required | Must be future date |

**Remediation section:**

| Field | Logical Name | Mode | Notes |
|-------|-------------|------|-------|
| Remediation Status | `fsi_remediationstatus` | Read-only on create (defaults to Open) | Updated via remediation workflow |
| Owner Response | `fsi_ownerresponse` | Read-only for validators | Populated by agent owner in MRM Submission Portal |

##### Form Build Steps

1. Navigate to **Tables** → `fsi_validationfinding` → **Forms**
2. Select **+ New form** → **Main form** → name: `Finding Form`
3. Add a **Header** section → drag in Finding ID, Agent Name, Cycle ID
4. Add a **1-column tab** named `Classification` → add SR 11-7 Pillar, Finding Category, Severity — all set as **Business Required**
5. Add a **1-column tab** named `Details`:
   - Add Finding Description — set as **Business Required**
   - Add Required Remediation — set as **Business Required**
   - Add Due Date — set as **Business Required**
6. Add a **1-column tab** named `Remediation` → add Remediation Status (read-only), Owner Response (read-only)
7. Save and publish

##### Minimum Character Validation

Dataverse model-driven forms do not natively enforce minimum character counts. Implement validation using one of these approaches:

- **Option A — Business Rule (recommended):** Create a business rule on `fsi_validationfinding` that shows an error notification if `Len(fsi_findingdescription) < 100` or `Len(fsi_requiredremediation) < 50`. Set the rule scope to **Form** so it fires on save.

  Steps:
  1. Navigate to **Tables** → `fsi_validationfinding` → **Business rules**
  2. Select **+ New business rule** → name: `Enforce Minimum Finding Length`
  3. Add a **Condition**: field `fsi_findingdescription`, operator `Contains Data`, then add an expression checking `Length(fsi_findingdescription) < 100`
  4. **If true** → add action **Show Error Message** on `fsi_findingdescription`: `"Finding description must be at least 100 characters."`
  5. Repeat for `fsi_requiredremediation` with a 50-character minimum
  6. Save and activate

- **Option B — JavaScript web resource:** Register an `OnSave` event handler that validates field lengths and cancels the save if requirements are not met.

#### Form 3 — Finding Closure Form

- **Table:** `fsi_validationfinding`
- **Form type:** Quick create form or main form tab
- **Purpose:** Validators confirm remediation is adequate and close findings

##### Form Layout

| Field | Logical Name | Mode | Validation |
|-------|-------------|------|------------|
| Finding ID | `fsi_findingid` | Read-only | — |
| Owner Response | `fsi_ownerresponse` | Read-only | Populated by agent owner |
| Validator Closure Notes | `fsi_validatorclosurenotes` | Required | Minimum 50 characters |
| Remediation Status | `fsi_remediationstatus` | Editable | Set to `Closed` on save |
| Closed Date | `fsi_closeddate` | Auto-set | Set to current date/time on save |

##### Form Build Steps

1. Navigate to **Tables** → `fsi_validationfinding` → **Forms**
2. Either add a new **Main form** named `Finding Closure Form`, or add a tab to the existing Finding Form named `Closure`
3. Add fields as listed above
4. Create a **Business Rule** to auto-set `fsi_closeddate`:
   - Condition: `fsi_remediationstatus` equals `Closed`
   - Action: Set `fsi_closeddate` to `Now()`
5. Create a **Business Rule** for minimum closure notes length:
   - Condition: `fsi_remediationstatus` equals `Closed` AND `Len(fsi_validatorclosurenotes) < 50`
   - Action: Show error message on `fsi_validatorclosurenotes`: `"Closure notes must be at least 50 characters."`
6. Save and publish

---

### Business Rules

Configure the following business rules on the Dataverse tables to enforce MRM workflow integrity. These rules support compliance with model risk management governance requirements.

#### Rule 1 — One-Directional Cycle Status Transitions

- **Table:** `fsi_validationcycle`
- **Rule name:** `Enforce Cycle Status Progression`
- **Logic:** Cycle status may only move forward through the defined sequence. Reverse transitions are blocked.

  Valid transitions:

  ```
  Not Started → Submitted → In Progress → Findings Issued → Remediated → Validated
  ```

  `Rejected` is a terminal state reachable from `In Progress`, `Findings Issued`, or `Remediated`.

- **Implementation:** Create a business rule (or a plug-in for complex logic) that compares the previous `fsi_cyclestatus` value with the new value. If the new value's option set integer is less than the previous value's integer (and the new value is not `Rejected`), show an error and prevent the save.

  > **Note:** Dataverse business rules have limited comparison capabilities for option set values. For robust enforcement, a synchronous plug-in or Power Automate flow with a pre-validation trigger is recommended.

#### Rule 2 — Rejected Cycles Become Read-Only

- **Table:** `fsi_validationcycle`
- **Rule name:** `Lock Rejected Cycles`
- **Logic:** When `fsi_cyclestatus` equals `Rejected` (100000007), all fields on the form become read-only.
- **Implementation:**
  1. Create a business rule with condition: `fsi_cyclestatus` equals `Rejected`
  2. Action: Set all editable fields to **Read-only** (use the "Lock/Unlock" action for each field)

#### Rule 3 — Critical Findings Block Cycle Completion

- **Table:** `fsi_validationcycle`
- **Rule name:** `Block Validation With Open Critical Findings`
- **Logic:** A cycle cannot transition to `Validated` status if any related `fsi_validationfinding` records have `fsi_severity` = `Critical` AND `fsi_remediationstatus` ≠ `Closed`.
- **Implementation:** This rule requires a Power Automate flow or synchronous plug-in because business rules cannot query related records:
  1. Create a flow triggered on `fsi_validationcycle` update where `fsi_cyclestatus` changes to `Validated`
  2. Query `fsi_validationfinding` where `fsi_validationcycle_lookup` = current cycle AND `fsi_severity` = `Critical` (100000001) AND `fsi_remediationstatus` ≠ `Closed` (100000004)
  3. If any records are returned, revert `fsi_cyclestatus` to previous value and send notification to the validator

#### Rule 4 — Outcome Rationale Minimum Length

- **Table:** `fsi_validationcycle`
- **Rule name:** `Require Outcome Rationale`
- **Logic:** When `fsi_validationoutcome` is not `Validated - No Findings`, the `fsi_outcomerationale` field must contain at least 100 characters.
- **Implementation:** Business rule with condition and error message (see minimum character validation pattern in Form 2 above).

---

### Security Roles

Configure three security roles in the Dataverse environment to control access within the Validation Workbench.

#### Validator Role

| Table | Create | Read | Write | Delete | Append | Append To |
|-------|--------|------|-------|--------|--------|-----------|
| `fsi_validationcycle` | None | User | User | None | User | User |
| `fsi_validationfinding` | User | User | User | None | User | User |
| `fsi_modelinventory` | None | Organization | None | None | None | None |
| `fsi_mrmriskrating` | None | Organization | None | None | None | None |
| `fsi_monitoringrecord` | None | Organization | None | None | None | None |

- **Row-level access:** Validators can only update `fsi_validationcycle` and `fsi_validationfinding` records where `fsi_validatorupn` matches their UPN. This is enforced via Dataverse column-level security and view filtering.
- **Notes:** "User" scope means the validator can only access records they own or are assigned to. Organization-level read on inventory tables allows validators to see agent context during reviews.

#### MRM Officer Role

| Table | Create | Read | Write | Delete | Append | Append To |
|-------|--------|------|-------|--------|--------|-----------|
| `fsi_validationcycle` | Organization | Organization | Organization | None | Organization | Organization |
| `fsi_validationfinding` | Organization | Organization | Organization | None | Organization | Organization |
| `fsi_modelinventory` | None | Organization | Organization | None | Organization | Organization |
| `fsi_mrmriskrating` | None | Organization | Organization | None | Organization | Organization |
| `fsi_monitoringrecord` | None | Organization | None | None | None | None |

- **Capabilities:** View all cycles, assign validators (write to `fsi_validatorupn`), override risk ratings (write to `fsi_mrmriskrating`), extend SLA dates
- **Restrictions:** Cannot delete any records (audit trail integrity)

#### Agent Owner Role

| Table | Create | Read | Write | Delete | Append | Append To |
|-------|--------|------|-------|--------|--------|-----------|
| `fsi_validationcycle` | None | User | None | None | None | None |
| `fsi_validationfinding` | None | User | User | None | None | None |
| `fsi_modelinventory` | None | User | None | None | None | None |
| `fsi_mrmriskrating` | None | User | None | None | None | None |
| `fsi_monitoringrecord` | None | User | None | None | None | None |

- **Capabilities:** Read-only access to their agent's cycles and findings; write access limited to `fsi_ownerresponse` field on findings (via MRM Submission Portal, not this app)
- **Notes:** Agent Owners primarily interact through App 1 (MRM Submission Portal). This role provides read-only visibility into the Validation Workbench if direct access is granted.

##### Security Role Configuration Steps

1. Navigate to **Power Platform admin center** → select the environment → **Settings** → **Users + permissions** → **Security roles**
2. Select **+ New role** → name the role (e.g., `MRM Validator`)
3. Navigate to the **Custom Entities** tab
4. Set table-level permissions as specified in the tables above
5. Save the role
6. Assign users to roles via **Users** → select user → **Manage security roles**

---

### Site Map Configuration

Configure the model-driven app site map to organize navigation for the Validation Workbench.

```
Validation Workbench
├── Validation
│   ├── My Active Cycles        → fsi_validationcycle (View 1: My Active Validation Cycles)
│   ├── All Open Cycles         → fsi_validationcycle (View 2: All Open Cycles) [MRM Officer]
│   └── SLA Watch               → fsi_validationcycle (View 4: Cycles Approaching SLA Breach)
├── Findings
│   └── Findings by Severity    → fsi_validationfinding (View 3: Findings by Severity)
├── Reference
│   ├── Model Inventory         → fsi_modelinventory (default view, read-only)
│   ├── Risk Ratings            → fsi_mrmriskrating (default view, read-only)
│   └── Monitoring Records      → fsi_monitoringrecord (default view, read-only)
```

#### Site Map Build Steps

1. In the model-driven app designer, select **Navigation** (site map editor)
2. Add an **Area** named `Validation`:
   - Add a **Group** named `Validation`
   - Add **Sub-areas** pointing to the three cycle views listed above
3. Add an **Area** named `Findings`:
   - Add a **Sub-area** pointing to the Findings by Severity view
4. Add an **Area** named `Reference`:
   - Add **Sub-areas** for each read-only table view
5. Save and publish the app

---

## Post-Deployment Validation

After building both apps, verify the following:

| Check | Expected Result |
|-------|-----------------|
| Submit Screen filters correctly | Only agents in `fsi_agentinventory` not yet in `fsi_modelinventory` appear |
| Flow 2 triggers on submit | New `fsi_modelinventory` record created with auto-scored fields |
| My Status screen filters by owner | Only current user's agents displayed |
| Findings sorted by severity | Critical findings appear first in all galleries and views |
| Screen 4 hidden from non-officers | Users without MRM Officer role see access-restricted message |
| Cycle status one-directional | Attempting to revert status shows error or is blocked |
| Critical findings block validation | Cycle cannot reach `Validated` with open Critical findings |
| Minimum character rules fire | Saving a finding with < 100 char description shows error |
| Rejected cycles are read-only | All fields locked when cycle status = Rejected |
| Evidence export generates CSV | Export button produces filtered inventory data |

---

## Regulatory Context

These Power Apps support the following regulatory requirements. Organizations should verify that their specific configuration meets applicable obligations.

| Regulation | Requirement | App Support |
|-----------|-------------|-------------|
| Fed SR 26-2 (formerly Fed SR 11-7) | Independent model validation | Validation Workbench enforces validator separation from model owners |
| Fed SR 26-2 (formerly Fed SR 11-7) | Three lines of defense | Security roles map to 1LoD (Agent Owner), 2LoD (MRM Officer, Validator), 3LoD (Auditor read access) |
| OCC Bulletin 2026-13 (formerly OCC Bulletin 2011-12) | Model inventory maintenance | MRM Submission Portal provides structured inventory with required fields |
| FINRA 25-07 | AI governance documentation | Agent Card links and finding documentation support examiner review |
| SOX 302/404 | Internal controls over reporting | Audit trail via `fsi_mrmcomplianceevent`, one-directional status transitions |
| SEC 17a-3/4 | Record retention | Immutable compliance event log with recommended 7-year retention |

> **Note:** No single app or control satisfies a regulation in isolation. These tools aid in building a comprehensive MRM program. Organizations should consult legal and compliance teams to verify coverage.
