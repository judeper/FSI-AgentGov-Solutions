# Troubleshooting

Common issues and solutions for the Compliance Dashboard.

---

## Data Issues

### No Data Showing in Dashboard

**Symptoms:**
- All visuals show blank or zero
- "No data" message on report pages

**Solutions:**

1. **Verify Dataverse Connection**
   ```
   Power BI Desktop > Transform Data > Data source settings
   Verify Dataverse URL is correct
   ```

2. **Check Data Exists in Dataverse**
   - Open Power Apps > Tables
   - Verify `fsi_controlmaster` has 78 rows
   - Verify `fsi_controlassessment` has assessment records

3. **Refresh Dataset**
   - Click Refresh in Power BI Desktop
   - Check for errors in refresh dialog

4. **Verify Authentication**
   - Re-enter credentials if prompted
   - Ensure account has Dataverse read permissions

### Stale Data

**Symptoms:**
- Dashboard shows old data
- Score date is outdated

**Solutions:**

1. **Manual Refresh**
   - In Power BI Service: Dataset > Refresh now
   - In Power BI Desktop: Home > Refresh

2. **Check Scheduled Refresh**
   - Power BI Service > Dataset > Settings > Scheduled refresh
   - Verify refresh is enabled and scheduled

3. **Verify Flow Execution**
   - Power Automate > CD-ScoreCalculator
   - Check last run status and time

### Missing Controls

**Symptoms:**
- Fewer than 78 controls displayed
- Specific controls missing from list

**Solutions:**

1. **Load Control Master Data**
   ```powershell
   python scripts/load_sample_data.py --controls-only
   ```
   - Confirm the control master source reflects the validated 78-control framework baseline before rerunning the loader

2. **Verify Control Master Table**
   - Check `fsi_controlmaster` row count
   - Ensure all 78 controls present

3. **Check Filter Context**
   - Clear all slicers
   - Remove any report-level filters

---

## Performance Issues

### Slow Dashboard Loading

**Symptoms:**
- Report takes >10 seconds to load
- Visuals load sequentially

**Solutions:**

1. **Reduce Data Volume**
   - Filter to recent 90 days instead of all history
   - Use aggregated tables for trends

2. **Optimize Measures**
   - Replace calculated columns with measures
   - Use variables in complex DAX

3. **Enable Query Caching**
   - Power BI Service > Dataset > Settings
   - Enable "Enhanced compute engine"

4. **Use Import Mode**
   - If using DirectQuery, switch to Import
   - Schedule regular refresh instead

### Slow Refresh

**Symptoms:**
- Data refresh takes >15 minutes
- Timeout errors during refresh

**Solutions:**

1. **Incremental Refresh**
   - Configure incremental refresh for large tables
   - Only refresh recent data

2. **Reduce Query Complexity**
   - Review Power Query transformations
   - Move complex logic to Dataverse

3. **Gateway Performance** (if applicable)
   - Upgrade gateway hardware
   - Configure connection pooling

---

## Flow Issues

### Score Calculator Flow Fails

**Symptoms:**
- No new score records created
- Flow shows failed status

**Error: "Dataverse connection failed"**
```
Solution:
1. Open flow in edit mode
2. Expand failed action
3. Re-authenticate Dataverse connection
4. Save and test
```

**Error: "Invalid filter expression"**
```
Solution:
1. Verify filter syntax in List rows action
2. Check column names match schema
3. Update filter if schema changed
```

**Error: "Timeout expired"**
```
Solution:
1. Increase timeout in flow settings
2. Add pagination to List rows
3. Process in batches
```

### Exception Monitor Flow Fails

**Symptoms:**
- SLA status not updating
- No alert notifications sent

**Error: "User not found"**
```
Solution:
1. Verify exception owner lookup is valid
2. Check user exists in environment
3. Update orphaned ownership records
```

**Error: "Teams notification failed"**
```
Solution:
1. Verify the Microsoft Teams connection reference is valid (the solution uses the
   shared_teams connector with PostMessageToConversation, not incoming webhooks)
2. Re-authenticate the Teams connection in Power Automate > Connections
3. Check that the recipient user has a Teams license and mailbox
4. Verify the Flow bot is not blocked by the recipient
```

---

## Authentication Issues

### "Access Denied" Error

**Symptoms:**
- Cannot connect to Dataverse
- 403 error in Power BI

**Solutions:**

1. **Verify User Permissions**
   - Check user has CD Viewer security role
   - Verify environment access

2. **Check Service Principal**
   - Verify app registration is active
   - Check client secret hasn't expired
   - Confirm API permissions granted

3. **Conditional Access**
   - Check if CA policy blocks access
   - Verify location/device compliance

### "Token Expired" Error

**Symptoms:**
- Refresh fails with authentication error
- Interactive sign-in required

**Solutions:**

1. **Re-authenticate**
   - Power BI Service > Dataset > Settings
   - Click "Edit credentials"
   - Sign in again

2. **Service Principal Refresh**
   - Check client secret expiration
   - Rotate secret if expired
   - Update connection credentials

---

## Visual Issues

### Incorrect Calculations

**Symptoms:**
- Score doesn't match expected value
- Percentages don't add to 100%

**Solutions:**

1. **Verify Measure Logic**
   - Review DAX measure definitions
   - Test with known data

2. **Check Filter Context**
   - Verify slicer selections
   - Check cross-filtering behavior

3. **Validate Source Data**
   - Export data to Excel
   - Manually verify calculations

### Formatting Issues

**Symptoms:**
- Colors not displaying correctly
- Conditional formatting not working

**Solutions:**

1. **Verify Color Measures**
   - Check color measure returns valid hex codes
   - Test measure in card visual

2. **Apply Formatting Correctly**
   - Format pane > Conditional formatting
   - Select correct measure for "Field value"

3. **Check Visual Settings**
   - Reset visual to defaults
   - Re-apply formatting rules

---

## Deployment Issues

### Solution Import Fails

**Symptoms:**
- Error during Dataverse solution import
- Missing dependencies error

**Solutions:**

1. **Check Dependencies**
   - Verify prerequisite solutions installed
   - Check version compatibility

2. **Import in Correct Order**
   - Import base tables first
   - Then import flows
   - Finally import dashboard

3. **Environment Capacity**
   - Check Dataverse storage available
   - Remove old data if needed

### Publish to Power BI Fails

**Symptoms:**
- Error during report publish
- Workspace not found

**Solutions:**

1. **Verify Workspace Access**
   - Check user has Contributor or higher role
   - Verify workspace exists

2. **Check License**
   - Confirm Power BI Pro license assigned
   - For Premium workspace, verify capacity

3. **Network Issues**
   - Check proxy/firewall settings
   - Verify Power BI endpoints accessible

---

## Recovery Procedures

### Rebuild Score History

If score history is corrupted or missing, manually trigger the CD-ScoreCalculator flow for each date or re-run assessments:

```powershell
# Reload control master data and regenerate sample scores
python scripts/load_sample_data.py --export --force
```

### Reset Exception SLA Status

If SLA calculations are incorrect, manually trigger the CD-ExceptionMonitor flow:

```powershell
# Trigger the CD-ExceptionMonitor flow manually from Power Automate
# Navigate to: Power Automate > CD-ExceptionMonitor > Test > Manually
```

### Restore Control Master

If control master data is corrupted:

```powershell
# Reload control master from reference
python scripts/load_sample_data.py --controls-only --force
```

---

## Support

For issues not covered here:

1. Check [FSI-AgentGov-Solutions Issues](https://github.com/judeper/FSI-AgentGov-Solutions/issues)
2. Review flow run history for detailed errors
3. Check Power BI Service activity log
4. Contact your Power Platform administrator

---

*Compliance Dashboard v1.0.2*
