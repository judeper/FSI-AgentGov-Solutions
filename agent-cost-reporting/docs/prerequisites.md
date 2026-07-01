# Prerequisites

This solution reads from several Microsoft surfaces. Each has its own identity and permission
requirements. Grant the least privilege required for read access.

## Identities and permissions

| Surface | Identity | Permission / role |
|---------|----------|-------------------|
| Azure Cost Management | Managed identity or app registration | **Cost Management Reader** (or Reader) on each in-scope subscription |
| Microsoft Graph — usage | Managed identity or app registration | **Reports.Read.All** (application) |
| Microsoft Graph — license inventory | Managed identity or app registration | **Organization.Read.All** (application) |
| Microsoft Graph — Purview audit (beta, optional) | App registration | **AuditLogsQuery.Read.All** (application) |
| Power Platform API | Service principal | App registered against the Power Platform API, plus a **Power Platform RBAC role** (Reader). Application permissions are not used; managed identity is not supported. |
| Manual Copilot Credits CSV | Admin user | **Microsoft 365 Billing Admin** / **Power Platform Admin** to export the CSV |

## Power Platform API setup (the exception)

The Power Platform API is delegated-only. For non-interactive automation:

1. Create an Entra app registration.
2. Add it as a Power Platform service principal and assign it a **Power Platform RBAC role** (Reader
   is sufficient for the billing-policy / environment reads).
3. Configure a certificate (preferred) or client secret.
4. Acquire tokens with the client-credentials grant against
   `https://api.powerplatform.com/.default`.

See `scripts/shared/auth_powerplatform.py` and the Microsoft Learn article
*Programmability and Extensibility - Authentication* for the authoritative steps.

## Preview / beta surfaces (off by default)

- **Power Platform capacity allocations** — Microsoft marks this API "do not use in production." It is
  disabled unless `--enable-preview` and `COSTRPT_ENABLE_PP_CAPACITY_PREVIEW=1` are both set.
- **Purview audit-log query API** — beta, and **not available in every cloud environment**.
  It is disabled unless `--enable-beta` and `COSTRPT_ENABLE_PURVIEW_AUDIT_BETA=1` are both set,
  and it degrades to `surface_unavailable` where unsupported.

## Recordkeeping note

The HTML report is an evidence package, not an approved recordkeeping format in itself. To aid in
meeting SEC 17a-4 / FINRA 4511 expectations, store the full package (report, dataset, manifest,
hashes, and raw extracts) in immutable (WORM) storage per your retention schedule. Organizations
should consult records-management counsel to confirm acceptability for their obligations.
