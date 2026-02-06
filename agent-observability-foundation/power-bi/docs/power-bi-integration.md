# Power BI Integration Guide

## Overview

Executive-facing compliance dashboards and agent observability analytics for Microsoft 365 AI agents. This integration provides a self-service Power BI experience for compliance officers, risk managers, and executives to monitor agent governance posture without requiring KQL knowledge.

**What you get:**
- Pre-built semantic model (TMDL format) with star schema design
- 19 DAX measures covering sessions, latency, error rates, compliance score
- Executive dashboard with 5 pages optimized for regulatory examination readiness
- Zone-based Row-Level Security (RLS) aligned with FSI-AgentGov governance framework
- Deployment via TMDL import (`.pbit` template planned for future release)

## Prerequisites

### Required Software
- **Power BI Desktop** - June 2022 or newer (support for TMDL format)
- Power BI license:
  - **Power BI Pro** - For ADX connector with Import mode (8 scheduled refreshes/day max)
  - **Power BI Premium Per User (PPU)** or **Premium/Fabric F-SKU** - For DirectQuery or Hybrid mode

### Required Permissions
- **Read access to Log Analytics workspace** - Where Agent Observability Foundation telemetry is stored
- **Power BI Service workspace** - To publish and share reports (Admin or Member role)

### Required Infrastructure
- **Agent Observability Foundation deployed** - Phase 1-3 complete with Application Insights and Azure Monitor Workbooks
- **KQL query library available** - Phase 2 queries provide data source for semantic model

## Executive Dashboard Design

The Agent Compliance Dashboard provides 5 pages optimized for different audiences and use cases.

### Page 1: Compliance Posture (Landing Page)

**Purpose:** Executive summary for quick health check.

**Audience:** C-suite, compliance officers, board members.

**Layout:**

| Visual Type | Metric | Conditional Formatting |
|-------------|--------|------------------------|
| Card | Compliance Score | Green >90%, Yellow 80-90%, Red <80% |
| Card | Control Coverage % | Green >90%, Yellow 80-90%, Red <80% |
| Card | Active Agents | None |
| Card | Regulatory Gaps | Red if >0 |
| Matrix | Zone Health Summary | Zone × Pillar showing evidence status |

**Key Features:**
- First page executives see when opening the dashboard
- All metrics use WoW/MoM trend indicators (small arrow icons showing direction)
- Zone Health Summary matrix enables drill-down to specific zone/pillar combinations
- One-click navigation to Regulation Drill-Down page for gap investigation

**Compliance Score Calculation:**
Uses weighted pillar calculation per FSI-AgentGov framework:
- Pillar 1 (Security): 40%
- Pillar 2 (Management): 30%
- Pillar 3 (Reporting): 20%
- Pillar 4 (SharePoint): 10%

> **Note:** The Compliance Score measure provided is a simplified pattern. Organizations should customize this measure to integrate with their control evidence tracking system (e.g., GRC platform, ServiceNow, Azure DevOps).

### Page 2: Regulation Drill-Down

**Purpose:** Regulatory examination readiness — prepare documentation packages for audits.

**Audience:** Compliance officers, internal audit, legal counsel.

**Layout:**

| Visual Type | Purpose | Details |
|-------------|---------|---------|
| Slicer | Regulation selection | FINRA 3110, FINRA 4511, SEC 17a-3, SEC 17a-4, SOX 302, SOX 404, SR 11-7, GLBA 501(b), OCC 2011-12, Fed SR 11-7, CFTC 1.31 |
| Card | Selected Regulation Details | Regulation name, regulatory body, category |
| Table | Control Evidence Status | ControlId, ControlName, EvidenceStatus, LastVerified, GapDescription |
| Bar Chart | Gap Distribution by Pillar | Count of gaps per pillar for selected regulation |

**Key Features:**
- Frame as exam prep tool: "Use this page to prepare documentation packages for regulatory examinations."
- Evidence Status column populated from governance-mapping.md (Phase 2) — maps telemetry artifacts to control evidence
- GapDescription field provides actionable remediation guidance
- Export to Excel button for offline audit documentation

**Examination Readiness Workflow:**
1. Select regulation (e.g., FINRA 3110 for supervision requirements)
2. Review control evidence status table — identify controls with "Gap" or "Partial" status
3. For each gap: navigate to Agent Detail page (drill-through) to investigate specific agent coverage
4. Export evidence summary to Excel for audit preparation
5. Document remediation plan in GRC system

### Page 3: Operational Health

**Purpose:** Mirror Azure Monitor Operational Health workbook (Phase 3) in Power BI format for executives who prefer self-service analytics.

**Audience:** IT operations, platform administrators, DevOps teams.

**Layout:**

| Visual Type | Metric | Time Range |
|-------------|--------|------------|
| Line Chart | Session Trends | 30-day rolling window |
| Clustered Bar | Error Rate by Zone | Current period |
| Line Chart | P95 Latency Trend | 30-day rolling window |
| Card | Total Messages | WoW trend indicator |
| Card | Avg Completion Rate | WoW trend indicator |

**Key Features:**
- WoW/MoM trend indicators next to each KPI card (green ↑ = improving, red ↓ = degrading)
- Same data as KQL workbooks but in a format executives can self-serve
- Drill-through to Agent Detail page for agent-specific investigation
- Synchronized time range selector (global parameter, default 30 days)

### Page 4: Adoption Trends

**Purpose:** Track agent adoption velocity and channel distribution over time.

**Audience:** Product managers, platform adoption teams, change management.

**Layout:**

| Visual Type | Metric | Details |
|-------------|--------|---------|
| Line Chart | Active Agents by Month | Trend line with MoM growth indicator |
| Line Chart | Session Volume Trend | Monthly session count with MoM growth indicator |
| Donut Chart | Zone Distribution | Agent count by Zone 1/2/3 |
| Clustered Column | Agent Type Distribution | CopilotStudio vs AgentBuilder vs Agent365SDK |

**Key Features:**
- Month-over-month growth percentage displayed as data labels
- Zone distribution helps identify governance coverage (e.g., "80% of agents in Zone 1 = low-risk")
- Agent type distribution shows platform adoption (migration to Agent 365 SDK)

> **Note:** Viva Insights provides additional Copilot Studio adoption metrics (MAU, session counts). See `viva-insights-scope.md` for coverage gaps and reconciliation workflow between Viva and Application Insights telemetry.

### Page 5: Agent Detail (Drill-Through Page)

**Purpose:** Detailed investigation for a single agent.

**Audience:** Platform administrators, compliance analysts investigating specific agents.

**Layout:**

| Visual Type | Content |
|-------------|---------|
| Card | Agent metadata (Name, Type, Zone, Environment, Created Date) |
| Card | Sessions (count, trend) |
| Card | Error Rate (%, trend) |
| Card | Avg Latency (ms, trend) |
| Card | Completion Rate (%, trend) |
| Table | Event-level audit trail (EventTimestamp, EventType, UserId, LatencyMs, ErrorCategoryId, ControlId) |

**Key Features:**
- Right-click any agent in other pages to drill-through to this page
- Event-level table uses USERELATIONSHIP measures (Category 6: Event Detail)
- UserId displayed as SHA-256 hash for PII protection — requires supervisor role for unhashed view (implement via RLS or custom measure)
- Export event audit trail to Excel for detailed investigation

**Drill-Through Setup:**
In Power BI Desktop, configure drill-through on `DimAgent[AgentName]` field to enable right-click navigation from any visual.

## Deployment

### Option A: .pbit Template (Planned — Not Yet Available)

> **Status:** The `.pbit` template is planned for a future release. Use Option B (TMDL Import) below for current deployment. All semantic model files, DAX measures, and KQL functions are available today.

When available, the template will support parameterized deployment with:
- **Log Analytics Workspace URL**: `https://api.loganalytics.io/v1/workspaces/{workspace-id}`
- **Start Date**: Reporting period start (YYYY-MM-DD)
- **End Date**: Reporting period end (YYYY-MM-DD)
- Modify visuals: Download .pbix from Power BI Service → Edit in Desktop → Republish

### Option B: Building from TMDL (Customization)

**Best for:** Organizations requiring custom dimensions, measures, or integration with existing BI infrastructure.

**Steps:**

1. **Clone the repository:**
   ```bash
   git clone https://github.com/judeper/FSI-AgentGov-Solutions.git
   cd FSI-AgentGov-Solutions/agent-observability-foundation/power-bi/
   ```

2. **Open Power BI Desktop:**
   - File → Open → Navigate to `semantic-model/` folder
   - Power BI Desktop imports TMDL definitions (database, model, tables, relationships, measures, roles)
   - If prompted for compatibility mode, select "Power BI Desktop"

3. **Configure data source connection:**
   - Home ribbon → Transform data → Data source settings
   - Select "Azure Application Insights" source
   - Click "Change Source..." and enter your Log Analytics workspace details:
     - **Workspace URL**: `https://api.loganalytics.io/v1/workspaces/{workspace-id}`
     - **API Key** (if required): Generate from Log Analytics workspace → API Access
   - Click OK → Close

4. **Customize semantic model (optional):**
   - **Add custom dimensions**: Create new `Dim*.tmdl` file in `tables/` directory (copy existing pattern)
   - **Add custom measures**: Append to `CoreMetrics.tmdl` following existing category structure
   - **Modify RLS**: Edit `ZoneBasedAccess.tmdl` filterExpression for custom logic
   - **Add relationships**: Edit `relationships.tmdl` to connect custom dimensions

5. **Populate dimension tables:**
   - Open Power Query Editor (Home → Transform data)
   - For each dimension table (DimAgent, DimControl, etc.):
     - Replace placeholder M query with KQL query to Log Analytics
     - Example for DimAgent: Use KQL from `governance-queries.md` Phase 2
   - Click Close & Apply

6. **Create dashboard visualizations:**
   - Add pages (Page 1-5 from design section above)
   - Drag measures from `_Measures` table to visuals
   - Reference existing measure names (e.g., `[Total Sessions]`, `[Compliance Score]`)
   - Configure conditional formatting for Cards (green/yellow/red thresholds)

7. **Save and publish:**
   - Save as `.pbix` file
   - File → Publish → Select workspace
   - Configure dataset refresh and RLS (see sections below)

**Version control workflow:**
TMDL format is designed for git workflows. To update the semantic model:
1. Edit `.tmdl` files locally
2. Test in Power BI Desktop (open semantic-model/ folder)
3. Commit changes: `git add semantic-model/ && git commit -m "Add custom dimension"`
4. Push to repository
5. Collaborators pull changes and re-open in Power BI Desktop

## Row-Level Security (RLS)

### How Zone-Based RLS Works

The Agent Compliance Dashboard implements zone-based RLS aligned with FSI-AgentGov's governance framework (Zone 1 = Low/Personal, Zone 2 = Medium/Team, Zone 3 = High/Enterprise).

**Security Model:**
- **Single role:** `ZoneBasedAccess`
- **Dynamic filtering:** Uses `USERNAME()` to resolve current user's email
- **Lookup table:** `UserZoneMapping` table maps user emails to zone assignments
- **Filter propagation:** RLS filter applied to `DimZone` dimension cascades to fact tables via relationships
- **Secure default:** Users without zone assignment see NO data (`FALSE()` return)

**Filter Logic (from `ZoneBasedAccess.tmdl`):**
```dax
tablePermission DimZone =
    VAR UserZone =
        LOOKUPVALUE(
            UserZoneMapping[ZoneId],
            UserZoneMapping[UserEmail], USERNAME()
        )
    RETURN
        IF(
            NOT ISBLANK(UserZone) && DimZone[ZoneId] = UserZone,
            TRUE(),
            FALSE()
        )
```

**Example:**
- User: `compliance-officer@contoso.com`
- UserZoneMapping entry: `compliance-officer@contoso.com` → `Zone3`
- Result: User sees only Zone 3 agents and their telemetry
- If user not in UserZoneMapping: User sees NO data (secure default)

### Setting Up RLS

**Step 1: Populate UserZoneMapping Table**

Option A - CSV Import (Manual):
1. Create CSV file with columns: `UserEmail`, `ZoneId`
2. Example content:
   ```csv
   UserEmail,ZoneId
   compliance-officer@contoso.com,Zone3
   operations-analyst@contoso.com,Zone2
   developer@contoso.com,Zone1
   ```
3. Power BI Desktop → Home → Get Data → Text/CSV
4. Load CSV into UserZoneMapping table
5. Publish to Power BI Service

Option B - Entra ID Sync (Automated):
1. Create Azure Logic App or Power Automate flow:
   - Trigger: Daily schedule
   - Action: Query Entra ID for user attributes (e.g., `extension_AgentZone` custom attribute)
   - Action: Write to UserZoneMapping table in Power BI dataset via XMLA endpoint (Premium/PPU only)
2. Map Entra ID user principal name (UPN) to `UserEmail` column
3. Map custom zone attribute to `ZoneId` column

> **Note:** XMLA endpoint write access requires Power BI Premium or Premium Per User (PPU) license.

**Step 2: Publish Report to Power BI Service**

1. Power BI Desktop → File → Publish → Select workspace
2. If prompted for credentials, enter Log Analytics workspace credentials (OAuth or API key)
3. Verify dataset appears in workspace

**Step 3: Configure RLS Role Membership**

1. Navigate to Power BI Service workspace → Datasets
2. Locate `Agent Compliance Dashboard` dataset → Click **...** (More options) → **Security**
3. Select `ZoneBasedAccess` role
4. Add users or security groups:
   - **Users:** Enter individual email addresses
   - **Security groups:** Enter Entra ID security group name (e.g., `SG-Compliance-Officers`)
5. Click **Save**

**Step 4: Test RLS with "View as" Feature**

1. Power BI Service → Open published report
2. Click **...** (More options) → **View as**
3. Select `ZoneBasedAccess` role
4. (Optional) Enter specific user email to simulate their view
5. Click **OK** — report filters to user's assigned zone
6. Verify:
   - Correct zone data visible
   - Other zones' data hidden
   - Unassigned users see blank report

### RLS Performance Testing

RLS adds query overhead. Test performance to ensure acceptable user experience.

**Testing Steps:**

1. **Open Performance Analyzer:**
   - Power BI Desktop → View ribbon → Performance Analyzer → Start recording

2. **Baseline (No RLS):**
   - Refresh all visuals (Performance Analyzer → Refresh visuals)
   - Note query durations for each visual

3. **Test RLS (View as):**
   - View ribbon → View as → `ZoneBasedAccess` role → Specific user
   - Refresh all visuals again
   - Note query durations with RLS enabled

4. **Compare Results:**
   - **Acceptable:** <2x overhead (e.g., 500ms baseline → 800ms with RLS)
   - **Investigate if >3x overhead:**
     - Check DimZone filter propagation (relationships should be single-direction)
     - Verify UserZoneMapping table is small (<10,000 rows)
     - Consider denormalizing ZoneId directly into fact tables (loses flexibility)

5. **Optimization Tips:**
   - Use Import mode for UserZoneMapping (not DirectQuery) — faster LOOKUPVALUE()
   - Create index on UserZoneMapping[UserEmail] if using DirectQuery for fact tables
   - Minimize role complexity — avoid multiple LOOKUPVALUE() calls

## Refresh Strategy

Choose refresh strategy based on license tier and reporting latency requirements.

### ADX Connector with Import Mode (Pro License)

**Best for:** Organizations with Power BI Pro licenses requiring daily/weekly compliance reporting.

**Configuration:**

1. **Data Source:** Azure Data Explorer (ADX) connector
2. **Storage Mode:** Import mode (data cached in Power BI dataset)
3. **Scheduled Refresh:**
   - Power BI Service → Dataset settings → Scheduled refresh
   - Frequency: 1x daily recommended (8x/day maximum on Pro)
   - Time: Schedule after midnight to capture full previous day
4. **Data Window:** 90 days rolling default (configurable in KQL function parameters)

**Advantages:**
- Fast query performance (data served from cache)
- Works with Power BI Pro license (no Premium required)
- Lower Log Analytics query costs (queries run during refresh, not per user interaction)

**Disadvantages:**
- Data latency (up to 24 hours if daily refresh)
- Limited refresh frequency (8x/day max on Pro, 48x/day on PPU)
- Dataset size limits (1GB on Pro, 100GB on PPU)

**KQL Pre-Aggregation:**
Use KQL functions to pre-aggregate data before import:
```kql
// Example: Session fact pre-aggregation
function vw_session_fact(StartDate:datetime, EndDate:datetime) {
    traces
    | where timestamp between (StartDate .. EndDate)
    | where customDimensions.EventName == "SessionCompleted"
    | summarize
        SessionCount = count(),
        MessageCount = sum(toint(customDimensions.MessageCount)),
        ErrorCount = sum(toint(customDimensions.ErrorCount)),
        AvgLatencyMs = avg(todouble(customDimensions.LatencyMs)),
        P95LatencyMs = percentile(todouble(customDimensions.LatencyMs), 95),
        CompletionRate = avg(todouble(customDimensions.CompletionRate))
      by AgentId = tostring(customDimensions.AgentId),
         ZoneId = tostring(customDimensions.ZoneId),
         SessionDate = bin(timestamp, 1d)
}
```

Reference this function in Power Query M:
```m
let
    Source = AzureDataExplorer.Contents("cluster-url", "database",
        "vw_session_fact(datetime(2024-01-01), now())", [MaxRows=null])
in
    Source
```

### DirectQuery (Premium/PPU/Fabric F-SKU)

**Best for:** Organizations requiring real-time compliance monitoring and live dashboards.

**Configuration:**

1. **Data Source:** Azure Data Explorer (ADX) connector
2. **Storage Mode:** DirectQuery (queries live data on every interaction)
3. **Scheduled Refresh:** Not applicable (queries are live)
4. **Automatic Page Refresh:** Enable for near-real-time updates
   - Power BI Desktop → Page settings → Page refresh → Automatic
   - Interval: 15 minutes (minimum on Premium)

**Advantages:**
- Real-time data (no refresh lag)
- No dataset size limits
- Ideal for operational dashboards requiring current-hour metrics

**Disadvantages:**
- Requires Premium/PPU or Fabric F-SKU license
- Higher Log Analytics query costs (queries run per user interaction)
- Slower visual refresh (network latency to query Log Analytics)
- Limited DAX function support (USERELATIONSHIP works, complex time intelligence may not)

**Performance Optimization:**
- Use query folding — ensure DAX translates to KQL efficiently
- Avoid complex calculated columns (push calculations to KQL source)
- Use aggregations (Aggregations feature in Premium) to cache summary tables

### Hybrid Approach (Premium/PPU/Fabric F-SKU)

**Best for:** Organizations balancing performance and real-time requirements.

**Configuration:**

1. **FactAgentSessions:** Import mode with daily refresh
   - Small dataset (session-grain, 90-day window)
   - Fast visuals for trend analysis, KPI cards
2. **FactAgentEvents:** DirectQuery
   - Large dataset (event-grain, full retention period)
   - Live queries for event-level drill-down
3. **All Dimensions:** Import mode
   - Static or slowly changing data (agents, zones, controls)

**Implementation:**
- Power BI Desktop → Model view → Select table → Properties → Storage mode
- Set FactAgentSessions storage mode: **Import**
- Set FactAgentEvents storage mode: **DirectQuery**
- Set dimension tables storage mode: **Dual** (automatic switching based on query context)

**Advantages:**
- Best of both worlds — fast dashboards with live drill-down
- Reduced Log Analytics costs (only event detail queries are live)
- Session trend analysis uses cached data (no query latency)

**Disadvantages:**
- Requires Premium/PPU or Fabric F-SKU for dual storage mode
- More complex refresh configuration
- Composite model limitations (some DAX functions restricted)

## Fiscal Year Configuration

**Default:** Calendar year (January 1 - December 31).

If your organization uses a non-calendar fiscal year, update the DimDate table.

**Steps to Configure Fiscal Year:**

1. **Open Power Query Editor:**
   - Power BI Desktop → Home → Transform data

2. **Locate DimDate table:**
   - Left pane → Select `DimDate` table
   - View M query in formula bar

3. **Modify FiscalYear and FiscalQuarter logic:**
   - **Example:** Fiscal year ending June 30 (FY2024 = Jul 2023 - Jun 2024)
   ```m
   #"Added FiscalYear" = Table.AddColumn(#"Previous Step", "FiscalYear",
       each if Date.Month([Date]) >= 7
            then Date.Year([Date]) + 1
            else Date.Year([Date]),
       type number),
   #"Added FiscalQuarter" = Table.AddColumn(#"Added FiscalYear", "FiscalQuarter",
       each let
           Month = Date.Month([Date]),
           Quarter = if Month >= 7 then Month - 6 else Month + 6
       in Number.RoundUp(Quarter / 3),
       type number)
   ```

4. **Close & Apply:** Power Query Editor → Home → Close & Apply

5. **Update DAX time intelligence functions:**
   For measures using fiscal year context, pass `year_end_date` parameter:
   ```dax
   Total Sessions YTD (Fiscal) =
       TOTALYTD(
           [Total Sessions],
           DimDate[Date],
           "6/30"  // Fiscal year end date
       )
   ```

**Common Fiscal Year Ends:**
- **June 30** (Federal government, education): `"6/30"`
- **September 30** (US federal fiscal year): `"9/30"`
- **March 31** (UK, Japan, India): `"3/31"`
- **Calendar year** (most FSI firms): `"12/31"`

## Customization Guide

### Adding Custom Dimensions

**Use Case:** Organization tracks custom agent metadata (e.g., business unit, risk rating, cost center).

**Steps:**

1. **Create new TMDL file:**
   - Create `semantic-model/tables/DimBusinessUnit.tmdl`
   - Copy structure from existing dimension (e.g., `DimZone.tmdl`)
   - Define columns: `BusinessUnitId` (key), `BusinessUnitName`, `CostCenter`, `VicePresident`

2. **Add relationship:**
   - Edit `semantic-model/relationships.tmdl`
   - Add relationship: `FactAgentSessions[BusinessUnitId]` → `DimBusinessUnit[BusinessUnitId]`

3. **Populate data:**
   - Power Query Editor → Add M query to fetch business unit metadata
   - Source: CSV file, SharePoint list, or SQL database

4. **Use in visuals:**
   - Drag `DimBusinessUnit[BusinessUnitName]` to slicer or axis
   - Filter propagates to fact tables via relationship

### Adding Custom Measures

**Use Case:** Organization requires custom KPI (e.g., cost per session, SLA compliance %).

**Steps:**

1. **Open CoreMetrics.tmdl:**
   - Edit `semantic-model/measures/CoreMetrics.tmdl`

2. **Add measure to appropriate category:**
   ```dax
   measure 'Cost per Session' =
       DIVIDE(
           [Total Cost],
           [Total Sessions]
       )
       formatString: "$#,0.00"
       displayFolder: "Cost Metrics"
       lineageTag: {generate-unique-guid}
   ```

3. **Save and test:**
   - Power BI Desktop → Refresh model (F5)
   - Drag `[Cost per Session]` to Card visual
   - Verify calculation accuracy

4. **Document measure:**
   - Add comment above measure describing purpose, dependencies, and limitations

### Modifying RLS

**Use Case:** Organization requires department-level filtering in addition to zone filtering.

**Steps:**

1. **Add DepartmentId to UserZoneMapping:**
   - Edit `semantic-model/tables/UserZoneMapping.tmdl`
   - Add column: `DepartmentId`

2. **Update RLS filter expression:**
   - Edit `semantic-model/roles/ZoneBasedAccess.tmdl`
   - Add department filter:
   ```dax
   tablePermission DimZone =
       VAR UserZone = LOOKUPVALUE(UserZoneMapping[ZoneId], UserZoneMapping[UserEmail], USERNAME())
       VAR UserDept = LOOKUPVALUE(UserZoneMapping[DepartmentId], UserZoneMapping[UserEmail], USERNAME())
       RETURN
           IF(
               NOT ISBLANK(UserZone) && DimZone[ZoneId] = UserZone &&
               DimAgent[DepartmentId] = UserDept,
               TRUE(),
               FALSE()
           )
   ```

3. **Test with "View as":**
   - Verify department filtering works correctly
   - Test edge cases (user with no department, multiple departments)

### Adding Dashboard Pages

**Use Case:** Organization wants custom page for specific use case (e.g., risk heatmap, cost analysis).

**Steps:**

1. **Create new page:**
   - Power BI Desktop → Home → New Page
   - Rename page (right-click page tab → Rename)

2. **Add visuals:**
   - Insert → Visualizations pane → Select visual type
   - Drag measures and dimensions from Fields pane
   - Configure formatting, colors, titles

3. **Reference existing measures:**
   - Use measures from `_Measures` table (e.g., `[Compliance Score]`, `[Total Sessions]`)
   - Create page-specific measures if needed (add to CoreMetrics.tmdl)

4. **Configure drill-through (optional):**
   - Visual → Format pane → Drill through
   - Set drill-through field (e.g., `DimAgent[AgentName]`)
   - Enable "Keep all filters"

5. **Save and publish:**
   - File → Save → Publish to workspace

## Cross-References

### Related Documentation

**Connector Selection:**
- See `connector-decision-matrix.md` for detailed comparison of ADX connector (Import) vs DirectQuery
- Decision criteria: license tier, data latency requirements, query cost constraints

**Viva Insights Integration:**
- See `viva-insights-scope.md` for adoption metrics coverage and gaps
- Viva Insights covers **Copilot Studio agents only** (not Agent Builder or Agent 365 SDK)
- Reconciliation workflow: Compare Viva MAU with Application Insights `Active Agents` measure

**Governance Mapping:**
- See `governance-mapping.md` (Phase 2) for control-to-artifact mapping
- Populate DimControl and DimRegulation tables from governance mapping data
- Evidence status tracking aligns with workbook queries

### Control Alignment

This Power BI integration helps support compliance with:

**Control 3.9 - Executive Dashboards:**
- Pre-built compliance posture dashboard with zone-based security
- Regulation drill-down page aids in regulatory examination readiness

**Control 3.1 - Usage Metrics:**
- Active Agents, Total Sessions, Total Messages measures provide adoption visibility

**Control 3.2 - Error Tracking:**
- Error Rate, Error Rate by Zone measures enable error monitoring
- Event-level drill-down supports root cause analysis

**Control 3.3 - Performance Metrics:**
- Avg Latency (ms), P95 Latency (ms) measures support SLA monitoring
- WoW trend indicators enable proactive performance management

## Troubleshooting

### Issue: RLS not filtering correctly

**Symptoms:** Users see data for all zones, not just their assigned zone.

**Diagnosis:**
1. Verify user is assigned to `ZoneBasedAccess` role (Power BI Service → Dataset → Security)
2. Check UserZoneMapping table contains user's email (exact match, case-insensitive)
3. Test with "View as" specific user email (not just role)

**Resolution:**
- Add missing user to UserZoneMapping table
- Verify `USERNAME()` returns expected format (e.g., `user@domain.com` vs `DOMAIN\user`)
- For on-premises AD: Update RLS filter to handle `DOMAIN\user` format

### Issue: Measures return BLANK()

**Symptoms:** Card visuals show "(Blank)" instead of values.

**Diagnosis:**
1. Check data source connection status (Power BI Service → Dataset → Settings → Data source credentials)
2. Verify fact tables have data (Power BI Desktop → Data view → Select FactAgentSessions)
3. Check filter context (clear all slicers and test)

**Resolution:**
- Refresh dataset (Power BI Service → Dataset → Refresh now)
- Verify Log Analytics workspace has telemetry data (run KQL query directly)
- Check measure DAX for errors (e.g., incorrect column names, missing relationships)

### Issue: Slow visual refresh

**Symptoms:** Visuals take >5 seconds to render.

**Diagnosis:**
1. Open Performance Analyzer (Power BI Desktop → View → Performance Analyzer)
2. Identify slow visuals (DAX query >1 second or Visual display >500ms)
3. Check storage mode (Model view → Table properties → Storage mode)

**Resolution:**
- **If Import mode:** Reduce data window (e.g., 90 days → 30 days)
- **If DirectQuery:** Optimize KQL source query (add pre-aggregation function)
- **If Hybrid:** Move slow tables to Import mode
- Consider aggregations (Premium feature) for large fact tables

### Issue: Compliance Score shows unexpected value

**Symptoms:** Compliance Score is much higher/lower than expected.

**Diagnosis:**
1. Verify DimControl.PillarWeight values (40%, 30%, 20%, 10%)
2. Check FactAgentEvents has ControlId populated
3. Validate control evidence tracking system is sending ControlId to Application Insights

**Resolution:**
- Customize Compliance Score measure to integrate with GRC system
- Map telemetry artifacts to control evidence status (see governance-mapping.md)
- Document measure logic for audit transparency

---

**Version:** 1.0.0
**Last Updated:** February 2026
**Repository:** https://github.com/judeper/FSI-AgentGov-Solutions
**Framework Version:** 1.2.38
