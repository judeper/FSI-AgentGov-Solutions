# Power Pages portal configuration — Express intake form

> Build instructions for the maker-facing intake form. **No exported portal package is shipped** (per repo Solution Content Policy). Administrators build the page following these specs in Power Pages designer, then bind it to the `fsi_intakerequest` Dataverse table created by `scripts/create_fsi_intake_dataverse_schema.py`.

## 1. Page metadata

| Setting | Value |
|---|---|
| Page name | `Request a new agent` |
| URL slug | `/agent-intake` |
| Web role | `Authenticated Users` (Microsoft Entra ID) |
| Form mode | Insert (new request) |
| Target table | `fsi_intakerequest` |
| Layout | Single column, ~10 visible fields |

## 2. M365 profile pre-fill (on page load)

Use Power Pages Liquid + Microsoft Graph (via Power Automate "When a record is created" pre-handler) to pre-fill these fields from `me` and `me/manager`:

| Field | Source | Editable? |
|---|---|---|
| `fsi_makerupn` | `Graph /me.userPrincipalName` | No (read-only) |
| `fsi_makerdisplayname` | `Graph /me.displayName` | No |
| `fsi_makerdepartment` | `Graph /me.department` | Yes (for cost-center fix-ups) |
| `fsi_makercountry` | `Graph /me.usageLocation` | Yes (drives data-residency rule OQ-D) |
| `fsi_sponsorupn` | `Graph /me/manager.userPrincipalName` (fallback to manual entry on 404) | Yes |

If `Graph /me/manager` returns 404 (resolved per `research/04-api-verification-spike.md`), surface an explicit "Who is your sponsor?" people-picker and require entry before submit.

## 3. The 10 maker-facing questions (Express path)

Field order, label copy, input type, validation, and which Claude catalog ID each question realises.

| # | Field | Maker-facing label | Input type | Validation | Source Q |
|---|---|---|---|---|---|
| 1 | `fsi_agentname` | What will you call this agent? | Text (1–80 chars) | Required, unique within department | BJ-001 |
| 2 | `fsi_businesspurpose` | In one or two sentences, what will it do? | Multiline text (50–500 chars) | Required | BJ-002, BJ-003 |
| 3 | `fsi_intendedaudience` | Who will use it? | Choice: Just me / My team / My department / Anyone in the firm / External users | Required | ZN-001 |
| 4 | `fsi_t1_initiates_financial_txn` | Will it initiate financial transactions or move money? | Yes / No / Not sure | Required; "Yes" or "Not sure" → Standard or Full path | RT-001 |
| 5 | `fsi_t2_customer_facing` | Will customers (external) interact with it? | Yes / No | Required; "Yes" → Standard or Full | RT-004 |
| 6 | `fsi_t3_autonomous_unmonitored` | Will it act on its own without a human reviewing each action? | Yes / No / Not sure | Required; "Yes" or "Not sure" → Full path | RT-006 |
| 7 | `fsi_t4_handles_npi` | Will it read or write personally-identifiable customer info (NPI/PII)? | Yes / No / Not sure | Required; "Yes" → Standard | CT-001 |
| 8 | `fsi_t5_handles_mnpi` | Will it touch material non-public information (MNPI) or research embargo data? | Yes / No / Not sure | Required; "Yes" → Full | CT-002 |
| 9 | `fsi_t6_crossborder_data` | Will the data leave your country? | Yes / No / Not sure | Required; "Yes" + maker country mismatch → Privacy review (default-deny per OQ-D) | CT-003 |
| 10 | `fsi_makerattestation` | I confirm the answers above are accurate to the best of my knowledge. | Checkbox | Required | OH-001 |

Progressive disclosure: Q4–Q9 render in a single grid with help-text bubbles; on any "Yes" or "Not sure" the form surfaces a banner ("Based on your answers, this request will go through additional review — about 7-20 minutes more") rather than blocking.

## 4. Routing on submit

Server-side Power Automate `Router` flow (see `flow-configuration.md`) reads the 6 trigger answers and computes:

| All 6 trigger answers = "No"? | Path |
|---|---|
| Yes | **Express** → fsi_intakeapproval auto-created with `fsi_status=PendingSponsor`; Teams card to sponsor |
| Any "Yes" or "Not sure" | **Standard** or **Full** (deferred to v0.2.0; for v0.1.0-preview, surface a "This request needs the full review process — please contact your governance lead" banner and create the record with `fsi_status=DeferredOutOfScope`) |

## 5. Status surface

Add a second Power Pages page `/agent-intake/status` that lists the maker's submitted requests (filtered by `fsi_makerupn eq @user.upn`) showing `fsi_status`, `fsi_decisionpath`, and the latest `fsi_intakedecisionlog` entry.

## 6. Accessibility & mobile

- WCAG AA contrast on all custom CSS
- Field labels associated via `<label for>` (Power Pages default)
- Mobile-friendly: Power Pages Bootstrap grid; tested at 375px viewport
- Save-and-resume: enable Power Pages "Save for later" on the entity form

## 7. Out of scope for v0.1.0-preview

Not yet built (deferred to v0.2.0+):
- Conversational intake via M365 Copilot declarative agent (planned UX channel #2)
- Standard / Full path detail pages
- Reviewer queue UI for InfoSec / Privacy / Compliance / MRM
- Localization
- Save-and-resume across browser sessions (only within-session for v0.1.0-preview)
