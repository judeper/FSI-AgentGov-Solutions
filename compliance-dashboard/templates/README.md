# Templates

This directory contains deployment artifacts for the Compliance Dashboard.

## Files

| File | Description | How to Create |
|------|-------------|---------------|
| `ComplianceDashboard.pbit` | Power BI template file | Follow [Power BI Template Specification](../docs/power-bi-template-spec.md) to create manually in Power BI Desktop |
| `exchange-config.sample.json` | Exchange compliance scan configuration | Copy and customize for your environment |

## Deployment

This solution does not ship a packaged `.zip` file. Build all Dataverse tables, columns, and flows manually:

1. Create the Dataverse schema following [Dataverse Schema](../docs/dataverse-schema.md)
2. Build Power Automate flows following [Flow Configuration](../docs/flow-configuration.md)
3. Create the Power BI template following [Power BI Template Specification](../docs/power-bi-template-spec.md) and save `ComplianceDashboard.pbit` to this directory

---

*Compliance Dashboard v1.0.3*
