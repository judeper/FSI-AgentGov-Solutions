# SharePoint Agent Card Library Setup

## Overview

Agent Cards are the primary examiner-facing evidence documents for model risk management. This guide covers the SharePoint site and library configuration required before activating Flow 5 (Generate-AgentCard-OnChange).

Agent Cards support compliance with Fed SR 11-7 documentation requirements by consolidating model metadata, risk ratings, validation status, and monitoring summaries into a single retrievable document per agent.

> **Important:** Complete all steps in this guide before setting `IsMRMAutomationEnabled` to `"true"`. Flow 5 depends on the library, metadata columns, template, and permissions described here.

## Site Configuration

| Setting | Value |
|---------|-------|
| Site Name | MRM Governance |
| Site URL | `https://{tenant}.sharepoint.com/sites/MRM` |
| Site Type | Communication Site (recommended for broad read access) |
| Site Language | English |
| Time Zone | Match your Dataverse environment time zone |

### Steps

1. Navigate to SharePoint Admin Center → Sites → Create
2. Select **Communication site**
3. Set the site name to **MRM Governance**
4. Set the URL suffix to **MRM**
5. Complete site creation

## Library Configuration

| Setting | Value |
|---------|-------|
| Library Name | Agent Cards |
| Library Type | Document Library |
| Versioning | Enabled — major versions only |
| Require check-out | No |
| Content approval | No |

### Steps

1. Navigate to the MRM Governance site
2. Select **New** → **Document Library**
3. Name the library **Agent Cards**
4. After creation, open **Library Settings** → **Versioning Settings**
5. Enable **Create major versions** — set no version limit (regulatory retention requires full history)

## Folder Structure

Flow 5 creates per-agent folders automatically using `fsi_modelid` as the folder name. The expected structure:

```
Agent Cards/
└── {fsi_modelid}/
    ├── MRM-2026-00001-AgentCard-v1.0.docx
    ├── MRM-2026-00001-AgentCard-v1.1.docx
    ├── MRM-2026-00001-AgentCard-v1.1.json   (fallback format)
    └── MRM-2026-00001-AgentCard-v2.0.docx
```

**Naming convention:** `{ModelId}-AgentCard-v{Major}.{Minor}.{format}`

- Major version increments on validation completion
- Minor version increments on material changes between validations
- `.json` files indicate the Word Online connector fallback was used

## Required Metadata Columns

Add the following columns to the **Agent Cards** library. These columns are populated by Flow 5.

| Column | Type | Maps To Dataverse Column | Notes |
|--------|------|--------------------------|-------|
| ModelId | Single line of text | `fsi_modelid` | Indexed — used for folder-level filtering |
| MRMTier | Choice: Tier 1 / Tier 2 / Tier 3 / Tier 4 | `fsi_mrmtier` | |
| RiskRating | Choice: Critical / High / Medium / Low | `fsi_currentriskrating` | |
| ValidationStatus | Choice: Not Started / Submitted / In Progress / Validated / Expired | `fsi_validationstatus` | |
| AgentCardVersion | Single line of text | `fsi_agentcardversion` | Format: `v{Major}.{Minor}` |
| AgentCardFormat | Choice: Word / JSON | `fsi_agentcardformat` | Indicates generation method |
| GeneratedBy | Single line of text | — | Flow name or user UPN |

### Steps

1. Open **Agent Cards** library → **Add column** for each column above
2. For Choice columns, enter the exact values listed (including capitalization)
3. Set **ModelId** as indexed: Library Settings → Indexed Columns → Create New Index

## Permissions

Configure permissions to support examiner access while protecting document integrity.

| Role | Access Level | Scope | Notes |
|------|-------------|-------|-------|
| MRM Team | Read / Write | Entire library | Create and update Agent Cards |
| Agent Owners | Read only | Own agent folder | Use folder-level permissions |
| Examiners | Read only | Entire library | Time-limited via Entra access package (recommended) |
| Governance Audit | Read only | Entire library | Persistent access for audit trail |

### Steps

1. Break permission inheritance on the **Agent Cards** library
2. Add the **MRM Team** security group with **Edit** permission
3. For **Agent Owners**, configure folder-level permissions after Flow 5 creates agent folders
4. For **Examiners**, create an Entra ID access package with time-limited SharePoint read access (recommended to limit standing examiner access)
5. Add the **Governance Audit** group with **Read** permission

> **Note:** Folder-level permissions for Agent Owners require manual or automated configuration after initial folder creation. Consider a Power Automate flow to assign permissions when new folders are created.

## Word Template Setup

Flow 5 uses Word Online connector to populate Agent Card documents from a template.

### Steps

1. Create **AgentCard-Template.docx** using the Word content control feature
2. Add the following content controls (Developer tab → Rich Text Content Control):

| Content Control Tag | Maps To | Section |
|--------------------|---------|---------|
| `agentCardVersion` | Version header | Title |
| `modelId` | Model ID | Header |
| `modelName` | Agent display name | Header |
| `mrmTier` | MRM Tier classification | Classification |
| `riskRating` | Current risk rating | Classification |
| `validationStatus` | Validation status | Classification |
| `businessFunction` | Business function | Overview |
| `underlyingModel` | Underlying AI model | Technical |
| `ownerUpn` | Agent owner | Ownership |
| `ownerDepartment` | Owner department | Ownership |
| `dataClassification` | Data classification | Risk Profile |
| `decisionAuthority` | Decision authority level | Risk Profile |
| `compositeScore` | Composite risk score | Risk Profile |
| `lastValidatedDate` | Last validation date | Validation |
| `nextValidationDue` | Next validation due | Validation |
| `monitoringSummary` | Latest monitoring summary | Monitoring |

3. Upload **AgentCard-Template.docx** to the **Agent Cards** library root (not inside an agent folder)
4. Verify the template is accessible by opening it from the library

> **Important:** If the Word Online connector cannot access the template, Flow 5 falls back to JSON format. This is a designed safety mechanism — Agent Cards are still created, but in `.json` format instead of `.docx`.

## Environment Variable Mapping

Verify these environment variables match your SharePoint configuration:

| Environment Variable | Expected Value |
|---------------------|----------------|
| `fsi_MRM_MRMSiteUrl` | `https://{tenant}.sharepoint.com/sites/MRM` |
| `fsi_MRM_MRMAgentCardLibrary` | `Agent Cards` |

## Pre-Activation Checklist

Complete all items before setting `IsMRMAutomationEnabled` to `"true"`:

- [ ] MRM Governance site created and URL matches `fsi_MRM_MRMSiteUrl` environment variable
- [ ] **Agent Cards** library created and name matches `fsi_MRM_MRMAgentCardLibrary`
- [ ] All metadata columns added per the table above
- [ ] ModelId column indexed
- [ ] Permissions configured per the permissions table
- [ ] `AgentCard-Template.docx` uploaded to library root and accessible
- [ ] `Sites.ReadWrite.All` permission granted to Managed Identity
- [ ] Word Online connector tested independently in Power Automate
- [ ] Document completion in DELIVERY-CHECKLIST.md
