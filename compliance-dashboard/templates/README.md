# Templates

This directory contains deployment artifacts for the Compliance Dashboard.

## Required Files

| File | Description | How to Create |
|------|-------------|---------------|
| `ComplianceDashboard_1_0_0.zip` | Power Platform solution package | Export from Power Apps: **Solutions** > **Compliance Dashboard** > **Export** > **As unmanaged** |
| `ComplianceDashboard.pbit` | Power BI template file | Follow [Power BI Template Specification](../docs/power-bi-template-spec.md) to create manually in Power BI Desktop |

## Creating the Solution Package

1. Deploy the solution to a development environment first (import `src/ComplianceDashboard/`)
2. Navigate to [Power Apps maker portal](https://make.powerapps.com)
3. Select **Solutions** > **Compliance Dashboard**
4. Click **Export** > **As unmanaged**
5. Save the `.zip` file to this directory as `ComplianceDashboard_1_0_0.zip`

## Creating the Power BI Template

See [docs/power-bi-template-spec.md](../docs/power-bi-template-spec.md) for complete step-by-step instructions.

After creating the template, save `ComplianceDashboard.pbit` to this directory.

---

*Compliance Dashboard v1.0.0*
