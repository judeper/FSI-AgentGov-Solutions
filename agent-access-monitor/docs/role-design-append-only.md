# Append-Only Audit by Role Design

## Why this document exists

The Agent Access Governance Monitor (AAM) writes every validation scan to the
`fsi_accessvalidationhistory` table (and violation detail to `fsi_accessviolations`) so
that the history forms a tamper-evident audit trail. This trail supports compliance with
records-retention obligations such as **FINRA Rule 4511**, **SEC Rule 17a-3 / 17a-4**,
and **SOX Section 404**.

A common misconception is that Dataverse provides native, column- or row-level
*immutability* that prevents records from being changed after they are written. **It does
not.** Dataverse has no native immutability feature. The `OwnershipType: OrganizationOwned`
setting on the audit tables controls **who owns** rows (the organization rather than an
individual user) — it does **not** control whether rows can be modified or deleted.

The append-only property AAM relies on is therefore achieved through **security-role
design**, applied post-deployment, not through any platform-level guarantee. This document
describes that role design so reviewers and operators do not over-state what the platform
provides.

## The role design

The append-only behavior is implemented by granting the AAM application user the minimum
privileges needed to write audit rows, and denying the privileges that would allow rows to
be altered or removed.

| Table | Create | Read | Write (Update) | Delete | Append / Append To |
|-------|:------:|:----:|:--------------:|:------:|:------------------:|
| `fsi_accessvalidationhistory` | ✅ Organization | ✅ Organization | ❌ None | ❌ None | As required by relationships |
| `fsi_accessviolations` | ✅ Organization | ✅ Organization | ❌ None | ❌ None | As required by relationships |
| `fsi_accessbaselines` | ✅ Organization | ✅ Organization | ✅ Organization* | ❌ None | As required by relationships |

\* Baselines are intentionally **re-capturable** (an approved configuration change produces a
new baseline). Treat baseline Write as a controlled operation governed by your change
process, not as part of the append-only audit trail. The history and violation tables carry
the append-only audit semantics.

### Recommended implementation

1. Create a dedicated security role (for example, `FSI AAM Audit Writer`).
2. On `fsi_accessvalidationhistory` and `fsi_accessviolations`, grant **Create** and
   **Read** at the **Organization** access level. Leave **Write** and **Delete** set to
   **None**.
3. Assign the role to the AAM application user (the identity the runbook authenticates as).
4. Do **not** also assign System Administrator or another role that re-grants
   Write/Delete on these tables — Dataverse privilege evaluation takes the **union** of all
   assigned roles, so a broader role would silently restore the ability to modify rows.
5. Keep separation of duties: the identity that defines the schema (System Administrator,
   used once at deployment) should be distinct from the runtime audit-writer identity.

## What this design supports — and what it does not

**Supports:**

- A practical append-only audit trail that helps meet FINRA 4511 / SEC 17a-3 records
  requirements, because the runtime identity cannot update or delete history rows.
- Clear, reviewable evidence of who can write versus who can alter audit data.
- Defense-in-depth when combined with Dataverse auditing and the SHA-256 evidence-export
  integrity hashes produced by `Export-AgentAccessEvidence.ps1`.

**Does not:**

- Provide cryptographic or platform-enforced immutability. A user or app explicitly
  granted Write/Delete (for example, a System Administrator) can still modify or remove
  rows. The control is **administrative**, enforced by role assignment and change
  governance — not by an unbreakable platform guarantee.
- Replace your organization's broader records-retention, backup, and legal-hold controls.

## Verifying the role design

- In the Power Platform admin center, open the AAM application user and confirm the
  assigned role shows **None** for Write and Delete on `fsi_accessvalidationhistory` and
  `fsi_accessviolations`.
- Confirm no additional role assigned to that identity re-grants Write/Delete on those
  tables.
- Periodically export evidence with `Export-AgentAccessEvidence.ps1` and retain the
  `.sha256` companion files; a changed hash on a re-export of the same period is a signal
  to investigate.

## Related

- [`dataverse-schema.md`](dataverse-schema.md) — table and column definitions.
- [`flow-configuration.md`](flow-configuration.md) — how validation history is written.
- [`evidence-export.md`](evidence-export.md) — integrity-hashed evidence export.
- `scripts/create_dataverse_schema.py` — source of truth for the table definitions.
