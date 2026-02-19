# Deployment Checklist

Step-by-step deployment validation checklist for the Compliance Dashboard solution.

---

## Pre-Deployment Checklist

Verify all prerequisites are met before starting deployment.

### Licensing

- [ ] Power BI Pro or Premium license verified for target users
- [ ] Dataverse capacity available in target environment (minimum 1 GB recommended)
- [ ] Power Automate Premium license for automated data collection flows
- [ ] Microsoft 365 E5 or E5 Compliance license for Purview Compliance Manager access

### Permissions

- [ ] User has **Purview Compliance Admin** role (required for Purview Compliance Manager API access)
- [ ] User has **Power Platform Administrator** role (required for environment access and DLP policy data)
- [ ] User has **Power BI Admin** role (required for workspace creation and sharing)
- [ ] User has **System Administrator** role in target Dataverse environment (required for table creation)

### Dependencies

- [ ] Environment Lifecycle Management solution v1.1.0+ deployed (provides zone classification data)
- [ ] Network access to Dataverse environment confirmed (no firewall blocking)
- [ ] Azure AD tenant ID and Dataverse environment URL documented

---

## Solution Import Checklist

### Download Solution Package

- [ ] Download `ComplianceDashboard_1_0_0.zip` from `templates/` directory
- [ ] Verify file size (expected: ~200 KB for unmanaged solution)
- [ ] Confirm file is not corrupted (can open in archive tool)

### Import to Power Apps

- [ ] Navigate to [Power Apps maker portal](https://make.powerapps.com)
- [ ] Select target environment from environment picker
- [ ] Navigate to **Solutions** > **Import solution**
- [ ] Click **Browse** and select `ComplianceDashboard_1_0_0.zip`
- [ ] Click **Next**

### Configure Connection References

- [ ] **Dataverse connection:**
  - [ ] Select existing connection or click **New connection**
  - [ ] Authenticate with organizational account
  - [ ] Verify connection shows as "Connected"
- [ ] **Office 365 Outlook connection:**
  - [ ] Select existing connection or create new
  - [ ] Authenticate with service account or user account
  - [ ] Verify connection for exception notification emails
- [ ] **Note:** Teams alerts use an HTTP webhook via the `fsi_CD_TeamsWebhook` environment variable, not a Teams connector. No Teams connection reference is required.

### Configure Environment Variables

- [ ] **fsi_CD_NotificationEmail:**
  - [ ] Enter compliance administrator email address
  - [ ] Format: `compliance@contoso.com`
  - [ ] This address receives exception SLA notifications
- [ ] **fsi_CD_TeamsWebhook (optional):**
  - [ ] Enter Teams webhook URL if using Teams notifications
  - [ ] Format: `https://contoso.webhook.office.com/...`
  - [ ] Leave blank if not using Teams notifications
- [ ] **fsi_CD_DataverseEnvironment** and **fsi_CD_SLAMultiplier**: Skip — not used by current flows (reserved for future use)

### Complete Import

- [ ] Click **Import**
- [ ] Wait for import process to complete (typically 2-5 minutes)
- [ ] Verify "Solution imported successfully" message appears
- [ ] No errors or warnings displayed

---

## Post-Import Validation

### Verify Dataverse Tables

Navigate to **Power Apps** > **Tables** and confirm the following tables exist:

- [ ] **fsi_controlmaster** - Control master table
  - [ ] Verify columns: `fsi_controlid`, `fsi_name`, `fsi_pillar`, `fsi_weight`
  - [ ] Check security roles assigned (CD Viewer, CD Assessor, CD Admin)
- [ ] **fsi_controlassessment** - Assessment records table
  - [ ] Verify columns: `fsi_controlmasterid`, `fsi_status`, `fsi_zone`, `fsi_score`
  - [ ] Check relationship to `fsi_controlmaster` exists
- [ ] **fsi_compliancescore** - Daily compliance score snapshots
  - [ ] Verify columns: `fsi_scoredate`, `fsi_overallscore`, `fsi_pillar1score`
  - [ ] Check index on `fsi_scoredate` column exists
- [ ] **fsi_complianceexception** - Exception tracking table
  - [ ] Verify columns: `fsi_severity`, `fsi_exceptionstatus`, `fsi_slastatus`, `fsi_daysopen`
  - [ ] Check business rule for SLA calculation exists
- [ ] **fsi_complianceevidence** - Evidence collection table
  - [ ] Verify columns: `fsi_evidencetype`, `fsi_sourceurl`, `fsi_hash`
  - [ ] Check relationship to `fsi_controlassessment` exists

### Verify Power Automate Flows

Navigate to **Power Automate** > **Solutions** > **Compliance Dashboard** and confirm flows exist:

- [ ] **CD-ScoreCalculator** flow exists
  - [ ] Flow type: Scheduled cloud flow
  - [ ] Trigger: Recurrence (Daily at 6:00 AM)
  - [ ] Owner: Solution importer
- [ ] **CD-ExceptionMonitor** flow exists
  - [ ] Flow type: Scheduled cloud flow
  - [ ] Trigger: Recurrence (Hourly)
  - [ ] Owner: Solution importer

### Create Security Roles

Security roles are not included in the solution package and must be created manually. Navigate to **Power Apps** > **Security roles** and create the following roles per the definitions in [Dataverse Schema](dataverse-schema.md#security-roles):

- [ ] **CD Viewer** - Read-only access (create manually)
- [ ] **CD Assessor** - Assessment entry and exception management (create manually)
- [ ] **CD Admin** - Full administrative access (create manually)

---

## Sample Data Loading (Optional)

Load sample data for demonstration and testing purposes.

### Prerequisites

- [ ] Python 3.8+ installed
- [ ] Required packages: `requests`, `msal` (install with `pip install -r requirements.txt`)

### Set Environment Variables

```bash
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
```

Or on Windows:
```powershell
$env:AZURE_TENANT_ID = "your-tenant-id"
$env:AZURE_CLIENT_ID = "your-client-id"
$env:AZURE_CLIENT_SECRET = "your-client-secret"
```

### Run Sample Data Loader

- [ ] Navigate to `scripts/` directory
- [ ] Run: `python load_sample_data.py --environment "https://your-org.crm.dynamics.com"`
- [ ] Verify output: "Loaded X control master records"
- [ ] **Note:** The `--environment` mode only loads control master data. To generate assessment, score, and exception sample files, use `--export` separately.

### Verify Sample Data

- [ ] Navigate to **Power Apps** > **Tables** > **fsi_controlmaster**
- [ ] Verify 62 control records exist (one for each framework control)
- [ ] Check sample controls: "1.1 - Restrict Agent Publishing to Designated Makers", "2.12 - Supervision and Oversight (FINRA Rule 3110)"
- [ ] Navigate to **fsi_compliancescore** table
- [ ] Verify 90 daily score snapshots exist (today going back 90 days)
- [ ] Check score values are realistic (not all 100 or all 0)
- [ ] Navigate to **fsi_complianceexception** table
- [ ] Verify sample exceptions exist with varied severities and statuses

---

## Flow Activation

### Activate CD-ScoreCalculator Flow

- [ ] Navigate to **Power Automate** > **Solutions** > **Compliance Dashboard**
- [ ] Click on **CD-ScoreCalculator** flow
- [ ] Verify all connections show green checkmarks (no warnings)
- [ ] If connection warnings exist:
  - [ ] Click **Edit** and fix connection references
  - [ ] Save flow
- [ ] Click **Turn on** to activate flow
- [ ] Click **Test** > **Manually** to run immediately
- [ ] Verify flow runs successfully (check run history)
- [ ] Navigate to **fsi_compliancescore** table
- [ ] Verify new score record created with today's date
- [ ] Check `fsi_overallscore` value is calculated (not null)

### Activate CD-ExceptionMonitor Flow

- [ ] Navigate to **CD-ExceptionMonitor** flow
- [ ] Verify all connections valid (green checkmarks)
- [ ] Click **Turn on**
- [ ] Click **Test** > **Manually** to run immediately
- [ ] Verify flow runs successfully
- [ ] Navigate to **fsi_complianceexception** table
- [ ] Verify `fsi_slastatus` field updated for open exceptions
- [ ] Check exceptions near SLA deadline show "At Risk" status

---

## Power BI Deployment

### Open Power BI Template

- [ ] Locate `templates/ComplianceDashboard.pbit` file
- [ ] Open in Power BI Desktop (version: latest recommended)
- [ ] Template prompts for parameters

### Configure Parameters

- [ ] **DataverseEnvironmentUrl:**
  - [ ] Enter: `https://your-org.crm.dynamics.com`
  - [ ] No trailing slash
  - [ ] Use actual environment URL from Power Platform admin center
- [ ] **TenantId:**
  - [ ] Enter Azure AD tenant ID (format: `12345678-1234-1234-1234-123456789abc`)
  - [ ] Find in Azure Portal > Azure Active Directory > Overview
- [ ] Click **Load**

### Authenticate

- [ ] Sign in with organizational account when prompted
- [ ] Select **Organizational account** authentication type
- [ ] Click **Connect**
- [ ] Wait for authentication to complete

### Verify Data Refresh

- [ ] Power BI Desktop loads data from Dataverse
- [ ] Check status bar: "Loading data..."
- [ ] Wait for refresh to complete (typically 30-60 seconds)
- [ ] Verify no error messages
- [ ] Check table row counts in **Model view**:
  - [ ] ControlMaster: 62 rows (if sample data loaded)
  - [ ] ComplianceScore: 90 rows (if sample data loaded)
  - [ ] ComplianceException: varies based on sample data

### Verify Report Pages Render

- [ ] **Page 1 - Executive Summary:**
  - [ ] Overall Score card displays percentage
  - [ ] Score Trend line chart shows 30-day history
  - [ ] Pillar Scores column chart shows 4 pillars
  - [ ] Zone Scores donut chart shows 3 zones
  - [ ] Exception Count card displays number
  - [ ] SLA Status stacked bar chart displays
- [ ] **Page 2 - Pillar Overview:**
  - [ ] Pillar Cards show individual pillar scores
  - [ ] Control Status Matrix displays controls by pillar × status
  - [ ] Pillar Trend line chart shows historical trends
  - [ ] Non-Compliant Controls table displays affected controls
- [ ] **Page 3 - Control Details:**
  - [ ] Control List table shows all 62 controls
  - [ ] Assessment History line chart displays (click control to populate)
  - [ ] Evidence List table shows linked evidence
  - [ ] Regulatory Tags slicer displays filter options
- [ ] **Page 4 - Exception Tracker:**
  - [ ] Open Exceptions card displays count
  - [ ] SLA Distribution pie chart shows status breakdown
  - [ ] Exception Table displays full exception list
  - [ ] Age Distribution histogram shows days open
  - [ ] Owner Workload bar chart shows exceptions per owner
- [ ] **Page 5 - Trend Analysis:**
  - [ ] Score Trend line chart shows 90-day history
  - [ ] Pillar Trends multi-line chart shows all 4 pillars
  - [ ] MoM Change KPI displays month-over-month delta
  - [ ] Control Status Changes waterfall chart displays
  - [ ] 30-day forecast trendline visible (if enabled in analytics)

### Verify DAX Measures Calculate

- [ ] Click **Data** view in Power BI Desktop
- [ ] Select **ComplianceScore** table
- [ ] Verify measures appear in field list (right panel)
- [ ] Check key measures:
  - [ ] Overall Score: Displays percentage (e.g., "87.5%")
  - [ ] Score Trend: Displays delta (e.g., "+3.2%")
  - [ ] Compliant Count: Displays integer
  - [ ] Exception Count: Displays integer
  - [ ] SLA Compliance %: Displays percentage

### Publish to Power BI Service

- [ ] Click **Publish** button in Home ribbon
- [ ] Select destination workspace (or create new)
- [ ] Wait for publish to complete (progress bar reaches 100%)
- [ ] Click **Open 'ComplianceDashboard.pbix' in Power BI** link
- [ ] Browser opens to Power BI Service
- [ ] Report renders successfully in browser

### Configure Scheduled Refresh

- [ ] In Power BI Service, navigate to workspace
- [ ] Click **...** next to dataset name
- [ ] Select **Settings**
- [ ] Expand **Scheduled refresh** section
- [ ] Click **Keep your data up to date** toggle to **On**
- [ ] Set refresh frequency: **Daily**
- [ ] Set time: **7:00 AM** (after score calculation flow at 6:00 AM)
- [ ] Check **Send refresh failure notifications to:** and enter email
- [ ] Click **Apply**
- [ ] Verify "Scheduled refresh configured successfully" message

### Assign Workspace Access

- [ ] Navigate to workspace settings
- [ ] Click **Access** tab
- [ ] Add users or groups:
  - [ ] Compliance team: **Viewer** role (read-only dashboard access)
  - [ ] Risk managers: **Contributor** role (can edit reports)
  - [ ] Administrators: **Admin** role (full workspace control)
- [ ] Click **Add**
- [ ] Verify users receive email notification

---

## Final Validation

### Executive Summary Page

- [ ] Overall Score displays realistic value (0-100)
- [ ] Score Trend shows positive/negative/stable indicator
- [ ] Pillar breakdown shows 4 pillars with individual scores
- [ ] Zone distribution shows 3 zones
- [ ] Exception count matches fsi_complianceexception table count
- [ ] SLA Status shows On Track/At Risk/Breached breakdown

### Pillar Overview Page

- [ ] All 4 pillars display with scores
- [ ] Control count by status matches expected distribution
- [ ] Pillar trend lines show historical data (if 90 days available)
- [ ] Non-compliant controls table populated (if any exist)

### Control Details Page

- [ ] All 62 controls display in table
- [ ] Filtering by pillar/zone/status works correctly
- [ ] Click control in table populates assessment history chart
- [ ] Evidence list shows linked evidence items
- [ ] Regulatory tags slicer filters controls correctly

### Exception Tracker Page

- [ ] Open exception count accurate
- [ ] SLA distribution shows realistic percentages
- [ ] Exception table sortable by days open, severity, owner
- [ ] Age distribution histogram shows realistic distribution
- [ ] Owner workload chart shows balanced distribution

### Trend Analysis Page

- [ ] 90-day score trend displays continuous line
- [ ] Pillar trends show all 4 pillars with different colors
- [ ] Month-over-month change KPI displays delta
- [ ] 30-day forecast trendline extends beyond current date (if analytics enabled)
- [ ] Control status changes waterfall shows transitions

### Interactive Filtering

- [ ] Date range slicers work correctly
- [ ] Zone selector filters all pages
- [ ] Pillar selector filters all pages
- [ ] Drill-through from control details works
- [ ] Clear filters button resets to default view

---

## Rollback Procedure

If deployment issues are encountered and rollback is required:

### Delete Power BI Report

- [ ] Navigate to Power BI Service workspace
- [ ] Click **...** next to report name
- [ ] Select **Delete**
- [ ] Confirm deletion
- [ ] Delete dataset as well

### Turn Off Power Automate Flows

- [ ] Navigate to **Power Automate** > **Solutions** > **Compliance Dashboard**
- [ ] For each flow (CD-ScoreCalculator, CD-ExceptionMonitor):
  - [ ] Click flow name
  - [ ] Click **Turn off**
  - [ ] Verify flow status shows "Off"

### Delete Solution from Power Apps

- [ ] Navigate to **Power Apps** > **Solutions**
- [ ] Locate **Compliance Dashboard** solution
- [ ] Click **...** > **Delete**
- [ ] Confirm deletion
- [ ] Wait for deletion to complete (2-5 minutes)

### Delete Dataverse Tables (Optional)

**Warning:** This will delete all compliance data. Only perform if data is not needed.

- [ ] Navigate to **Power Apps** > **Tables**
- [ ] For each table (fsi_controlmaster, fsi_controlassessment, fsi_compliancescore, fsi_complianceexception, fsi_complianceevidence):
  - [ ] Click table name
  - [ ] Click **Delete table**
  - [ ] Confirm deletion
- [ ] Verify tables no longer appear in table list

### Clean Up Sample Data

If sample data was loaded but production data is needed:

- [ ] Run sample data loader with `--force` flag to overwrite existing data:
  ```bash
  python scripts/load_sample_data.py --environment "https://your-org.crm.dynamics.com" --force
  ```
- [ ] Manually delete remaining records via Power Apps if needed
- [ ] Verify sample records cleared
- [ ] Ready for production data loading

---

## Troubleshooting Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Solution import fails | Missing connection reference | Create required connections before import |
| Flow won't turn on | Invalid connection | Edit flow, update connection references |
| Power BI can't connect | Network restriction | Verify firewall allows Dataverse access |
| No data in dashboard | Tables empty | Load sample data or create assessments |
| Refresh fails in Service | Authentication expired | Re-authenticate dataset credentials |
| Measures show errors | Missing relationship | Verify DateTable relationship to ComplianceScore |

---

## Next Steps

After successful deployment:

1. **Load Production Data:**
   - Create assessment records for each applicable control
   - Link evidence items to assessments
   - Document exceptions with remediation plans

2. **Configure Users:**
   - Assign Dataverse security roles (CD Viewer, CD Assessor, CD Admin)
   - Add users to Power BI workspace
   - Configure Row-Level Security if needed (see [Power BI Setup](power-bi-setup.md))

3. **Schedule Regular Reviews:**
   - Weekly: Review open exceptions and SLA status
   - Monthly: Analyze trend data and identify patterns
   - Quarterly: Validate control assessments and update evidence

4. **Integrate with Workflows:**
   - Link to FINRA Supervision Workflow for supervision metrics
   - Connect to incident reporting processes
   - Embed dashboard in compliance review meetings

---

*Compliance Dashboard v1.0.0 - Deployment Checklist*
