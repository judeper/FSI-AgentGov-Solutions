# Manage Pipelines — PPAC Portal Walkthrough

> **Status:** Placeholder — screenshots should be captured from a live tenant.

This document describes the "Manage pipelines" UI surface in the Power Platform Admin Center (PPAC) for reference. Since screenshots cannot be captured programmatically, structured text descriptions and screenshot placeholders are provided.

## Navigation Path

1. **Sign in** to the Power Platform Admin Center at [admin.powerplatform.microsoft.com](https://admin.powerplatform.microsoft.com)
2. In the left navigation, select **Environments**
3. Select the **target environment** (the pipelines host environment)
4. Select **Settings** from the top command bar
5. Expand **Resources**
6. Select **Manage pipelines**

> **Note:** "Manage pipelines" opens an embedded model-driven app for **platform host** environments. For **custom host** environments, use the standalone **Deployment Pipeline Configuration** app instead. See [Microsoft Learn — Set up pipelines](https://learn.microsoft.com/power-platform/alm/set-up-pipelines) for the distinction.

## What You See

### Pipeline List View

The Manage pipelines surface displays:

| Field / Column | Description |
|---------------|-------------|
| **Pipeline Name** | Display name of the deployment pipeline |
| **Description** | Optional description of the pipeline purpose |
| **Stages** | Target environments configured as deployment stages |
| **Status** | Active / Inactive status of the pipeline |
| **Created On** | Date the pipeline was created |
| **Modified On** | Date of last modification |

### Actions Available

From the pipeline list, administrators can:

- **Create** a new pipeline with target stages
- **Edit** an existing pipeline (add/remove stages, rename)
- **Deactivate** a pipeline to prevent deployments
- **Delete** a pipeline (irreversible — deactivate first for safety)
- **View run history** for audit trail

### Stage Configuration

Each pipeline contains one or more stages. For each stage:

| Field | Description |
|-------|-------------|
| **Stage Name** | Target environment display name |
| **Environment** | Linked Power Platform environment |
| **Stage Order** | Deployment sequence (Dev → Test → Prod) |
| **Pre-deployment Step** | Optional approval gate |

## Screenshot Placeholders

The following screenshots should be captured from a live tenant to complete this documentation:

<!-- EXPECTED screenshots — capture from a live PPAC tenant -->

| # | Screenshot Description | Expected File |
|---|----------------------|---------------|
| 1 | PPAC Environments list with target host highlighted | `ppac-environments-list.png` |
| 2 | Environment Settings → Resources → Manage pipelines link | `manage-pipelines-link.png` |
| 3 | Manage pipelines — pipeline list view | `manage-pipelines-list.png` |
| 4 | Pipeline detail — stages configuration | `pipeline-stages-detail.png` |
| 5 | Deployment Pipeline Configuration app (custom host alternative) | `dpc-app-custom-host.png` |

> **Capture instructions:** Use browser zoom at 100%, capture the full browser viewport, save as PNG. Store screenshots in `maintainers-local/tenant-evidence/pipeline-governance-cleanup/` (gitignored).

## Platform Host vs. Custom Host

| Aspect | Platform Host | Custom Host |
|--------|--------------|-------------|
| **Access** | PPAC → Manage pipelines (embedded) | Standalone Deployment Pipeline Configuration app |
| **Setup** | Automatic for Managed Environments | Requires Power Platform Pipelines app installation |
| **Recommendation** | Use for standard ALM | Use when advanced stage configuration is needed |

For FSI organizations, a **dedicated custom host environment** is recommended to maintain separation between the pipeline infrastructure and target deployment environments.

---

*Updated: May 2026 | Version: v1.0*
