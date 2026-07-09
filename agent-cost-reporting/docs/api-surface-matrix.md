# API Surface Matrix

Verified surfaces and endpoints this solution uses. API versions and meter names change; re-validate
during deployment. Status reflects research as of 2026-06-16.

| Surface | Dataset | Endpoint | API version | Auth | App-only / MI | Status |
|---------|---------|----------|-------------|------|----------------|--------|
| Azure Cost Management | PAYG cost by meter | `POST management.azure.com/{scope}/providers/Microsoft.CostManagement/query` | 2025-03-01 | ARM, Cost Management Reader | Yes | GA |
| Azure Cost Management | Cost details (bulk, async) | `POST .../generateCostDetailsReport` | 2025-03-01 | ARM, Cost Management Reader | Yes | GA |
| Microsoft Graph | Copilot usage user detail | `GET graph.microsoft.com/v1.0/reports/getMicrosoft365CopilotUsageUserDetail(period='Dn')` | v1.0 | Reports.Read.All | Yes | GA (usage, not cost) |
| Microsoft Graph | License / seat inventory | `GET /v1.0/subscribedSkus` | v1.0 | Organization.Read.All | Yes | GA (no $) |
| Power Platform API | Billing policies | `GET api.powerplatform.com/licensing/billingPolicies` | 2024-10-01 | SP + Power Platform RBAC | **No (delegated-only)** | GA |
| Power Platform API | Policy → environments | `GET .../licensing/billingPolicies/{id}/environments` | 2024-10-01 | SP + Power Platform RBAC | **No** | GA |
| Power Platform API | Capacity allocations | `GET .../licensing/capacityAllocations` | 2024-10-01 | SP + Power Platform RBAC | **No** | **Preview — "do not use in production"** |
| Purview audit (Graph) | Copilot interactions | `POST graph.microsoft.com/beta/security/auditLog/queries` | beta | AuditLogsQuery.Read.All | Yes | **Beta; not in US Gov/China** |
| Purview audit (Graph) | Copilot interaction records | `GET graph.microsoft.com/beta/security/auditLog/queries/{id}/records` | beta | AuditLogsQuery.Read.All | Yes | **Beta; `@odata.nextLink` paging; `auditData` mapping unverified** |
| Manual export | Per-agent credit consumption | M365 admin / PPAC CSV | n/a | Admin portal | No | **UI only (the gap)** |

## What is and is not attributable

- **Authoritative $:** Azure Cost Management, per subscription / resource group / meter.
- **Environment-level $:** derivable by joining Azure cost (subscription) to the Power Platform
  billing-policy → environment map.
- **Per-agent $:** **not** available via supported APIs. Azure Cost Management has no agent dimension;
  per-agent credit consumption is UI-export only. Any per-agent figure is partial/heuristic/manual.
- **Usage (not cost):** Graph Copilot usage reports and Purview audit interactions.
- **Unit price:** not exposed by any API; configured in `config.json` and documented in the report.

## Sources

Primary sources backing these endpoints (Microsoft Learn) are catalogued in the research artifacts
that produced this solution. Key references: *Programmability and Extensibility - Authentication*
(Power Platform, updated 2026-03-11); *Query - Usage* and *Generate Cost Details Report* (Azure Cost
Management, 2025-03-01); *getMicrosoft365CopilotUsageUserDetail* (Microsoft Graph v1.0);
*Create auditLogQuery* (Microsoft Graph beta).
