# Templates

This directory contains JSON configuration templates for the Compliance Dashboard. Power BI `.pbit` / `.pbix` binaries are not shipped in this repository.

## Files

| File | Description | How to Create |
|------|-------------|---------------|
| `exchange-config.sample.json` | Exchange compliance scan configuration | Copy and customize for your environment |

## Deployment

This solution does not ship a packaged `.zip` file. Build all Dataverse tables, columns, and flows manually:

1. Create the Dataverse schema following [Dataverse Schema](../docs/dataverse-schema.md)
2. Build Power Automate flows following [Flow Configuration](../docs/flow-configuration.md)
3. Create the Power BI template following [Power BI Template Specification](../docs/power-bi-template-spec.md) and store `ComplianceDashboard.pbit` in an organization-controlled artifact store outside this repository

---

*Compliance Dashboard v1.0.4*
