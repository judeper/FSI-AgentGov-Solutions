# Auto-detect playbook — what the system fills in vs. what the maker types

The Express form asks the maker only the fields needed for routing. This document lists the back-office fields the decision-pack record carries and how each is populated automatically.

## Endpoints used

| # | Field family | Source | Endpoint | Auth | Status |
|---|---|---|---|---|---|
| 1 | Maker profile | Microsoft Graph v1.0 | `GET /me` | Delegated | Verified in spike |
| 2 | Sponsor default | Microsoft Graph v1.0 | `GET /me/manager` | Delegated | Verified; returns 404 if no manager is set |
| 3 | Tenant environments | Power Platform admin API | `GET https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01` | Delegated or app/managed identity with admin role | Verified in spike; newer Power Platform API namespaces may be adopted later |
| 4 | Data policies (DLP) | Power Platform admin API | `GET https://api.bap.microsoft.com/providers/PowerPlatform.Governance/v2/policies?api-version=2018-01-01` | Delegated or app/managed identity with admin role | Verified in spike |
| 5 | Purview retention labels | Microsoft Graph beta | `GET /beta/security/labels/retentionLabels` | Delegated `RecordsManagement.Read.All`; application permissions not supported on current beta surface | Verify during pilot or check manually in Purview |
| 6 | Purview data map search | Microsoft Purview Data Map | `POST https://<account>.purview.azure.com/datamap/api/search/query?api-version=2023-09-01` | Purview Data Reader on account | Optional; deferred for Express MVP |
| 7 | Microsoft Entra Agent ID creation | Microsoft Graph v1.0 | `POST /servicePrincipals/microsoft.graph.agentIdentity` | `AgentIdentity.CreateAsManager` or `AgentIdentity.Create.All`; tenant feature must be available | Used at handoff after approval |

## Field-by-field auto-detect map

### Maker profile

| Dataverse column | Graph field | Notes |
|---|---|---|
| `fsi_makerupn` | `userPrincipalName` | Read-only on form |
| `fsi_makerdisplayname` | `displayName` | Read-only |
| `fsi_makerdepartment` | `department` | Editable; null tolerated |
| `fsi_makercountry` | `usageLocation` or country | Drives data-residency check |
| `fsi_makerjobtitle` | `jobTitle` | Sponsor card display |
| `fsi_sponsorupn` | `manager.userPrincipalName` | Fallback to manual entry on 404 |

### Environment and data policy context

| Computed field | How |
|---|---|
| `fsi_targetenvironmentid` | Select from `expressPathEligible: true` in `autodetect_environments.py` output |
| `fsi_targetenvironmentname` | PPAC `properties.displayName` |
| `fsi_environmentmanaged` | `governanceConfiguration.protectionLevel` in `Basic` or `Standard` |
| `fsi_dlppolicyoutcome` | `autodetect_dlp_simulation.py` outcome (`allowed`, `review`, `dlp-violation`, `blocked`) |

### Records

| Computed field | How |
|---|---|
| `fsi_retentionlabelapplied` | `autodetect_purview.py` verifies `FSI-AgentIntake-7yr` exists, or Records Admin verifies manually |
| `fsi_retentionyears` | Constant `7` unless customer records counsel overrides |
| `fsi_immutablestorage` | `true` when WORM label is stamped on the decision log |

### Classification

| Computed field | Rule |
|---|---|
| `fsi_decisionpath` | `Express` if all six trigger answers are `No` and `fsi_intendedaudience = Just me`; `DeferredOutOfScope` for wider audiences or trigger hits; `DefaultDeny` for unresolved cross-border conflicts |
| `fsi_risktier` | Tier 3 for Express; Tier 2 if 1–2 trigger hits; Tier 1 if 3+ trigger hits |
| `fsi_zone` | Mapped from `fsi_intendedaudience` in `policy-lookup-tables.yaml` |
| `fsi_triggerhitcount` | Count of trigger answers equal to `Yes` or `Not sure` |

### Identity

| Computed field | How |
|---|---|
| `fsi_entraagentid` | `setup_entra_agent_id.py` creates a Microsoft Entra Agent ID service principal using an Agent Identity blueprint and sponsor reference |

## Customer pre-deployment checklist

Before pilot, the customer admin must:

1. Grant Power Platform admin scope to the identity used for environment and data-policy reads.
2. Confirm Microsoft Graph delegated access for profile pre-fill (`User.Read`) and optional admin-scale reads (`User.Read.All`).
3. Confirm Records Management Admin can create or verify `FSI-AgentIntake-7yr` in Purview. Use Security & Compliance PowerShell or the Purview portal for production setup.
4. Confirm the Microsoft Entra Agent ID feature is available in the target tenant/cloud and consent either `AgentIdentity.CreateAsManager` or `AgentIdentity.Create.All` for handoff automation.
5. Create or identify an Agent Identity blueprint and store its ID in `AGENT_INTAKE_AGENT_BLUEPRINT_ID`.

## Out of scope for v1.0.0-preview

- Defender for Cloud Apps signal enrichment
- Microsoft Entra ID Governance access-package integration
- Purview DSPM-for-AI signal pull-through
- ServiceNow CMDB sync for sponsor / cost-centre validation
