# Power Pages Express form configuration

Build this form in Power Pages design studio against the Dataverse table `fsi_intakerequest`. Use a **Form** component (or a **Multistep form** if your firm wants save/resume). Avoid exported portal packages; this repository provides manual build instructions only.

Use Dataverse **logical names** in table permissions, form metadata, and flow expressions. The logical name is the schema name lowercased with no extra underscores.

## Table permissions

| Table | Permission | Web role |
|---|---|---|
| `fsi_intakerequest` | Create, Read own, Update own while Draft | Authenticated Users |
| `fsi_intakedatasource` | Create, Read own, Update own while Draft | Authenticated Users |
| `fsi_intakerisksignal` | Read own | Authenticated Users |

Administrators/reviewers should use model-driven app security roles rather than broad portal write access.

## Express intake fields

| Step | Dataverse logical name | Prompt | Control | Requirement |
|---|---|---|---|---|
| 1 | `fsi_agentdisplayname` | What should the agent be called? | Text (5–200 chars) | Required |
| 2 | `fsi_businessoutcome` | What business outcome should this support? | Choice or text per customer policy | Required |
| 3 | `fsi_businessjustification` | In one or two sentences, what will it do? | Multiline text (50–500 chars) | Required |
| 4 | `fsi_agenttype` | What type of agent will you build? | Choice `fsi_intake_agenttype` | Required |
| 5 | `fsi_intendedaudience` | Who will use it? | Choice: Just me / My team / My department / Anyone in the firm / External users | Required |
| 6 | `fsi_t1initiatesfinancialtxn` | Will it initiate financial transactions or move money? | Yes / No / Not sure | Required |
| 7 | `fsi_t2customerfacing` | Will it interact directly with customers or external parties? | Yes / No / Not sure | Required |
| 8 | `fsi_t3autonomousunmonitored` | Can it act without a human reviewing each action? | Yes / No / Not sure | Required |
| 9 | `fsi_t4handlesnpi` | Will it process customer nonpublic personal information (NPI)? | Yes / No / Not sure | Required |
| 10 | `fsi_t5handlesmnpi` | Will it process material nonpublic information (MNPI) or information-barrier data? | Yes / No / Not sure | Required |
| 11 | `fsi_t6crossborderdata` | Will data cross country or regional residency boundaries? | Yes / No / Not sure | Required |
| 12 | `fsi_dataresidencycountry` | Where is the data expected to reside? | Country/region text or choice | Required when T6 is Yes/Not sure |
| 13 | `fsi_makerattestation` | I confirm this request follows firm acceptable-use policy and is accurate to the best of my knowledge. | Checkbox | Required |

> `fsi_businessoutcome` is the canonical schema column. If you prefer a separate customer-specific choice for expected outcome, add it as a managed customization and include it in `fsi_decisionpackjson`.

## Auto-filled fields

Populate these before submission using Graph `/me` and `/me/manager`, or a pre-submit Power Automate cloud flow:

| Dataverse logical name | Source |
|---|---|
| `fsi_makerupn` | `/me.userPrincipalName` |
| `fsi_makerdisplayname` | `/me.displayName` |
| `fsi_makerdepartment` | `/me.department` |
| `fsi_makerjobtitle` | `/me.jobTitle` |
| `fsi_makercountry` | `/me.usageLocation` or country |
| `fsi_sponsorupn` | `/me/manager.userPrincipalName`; allow maker override if no manager is returned |
| `fsi_requestid` | New GUID generated on form load or in Flow 1 |
| `fsi_status` | `Draft` until submit; `Submitted` when maker clicks Submit |
| `fsi_policyversionapplied` | `0.2.0-preview` or customer policy version |

## Routing banner

After Flow 1 runs, surface a read-only status page to the maker:

| Condition | Message |
|---|---|
| `fsi_decisionpath = Express` | Request submitted. Your sponsor will receive a Teams approval card. |
| `fsi_decisionpath = DeferredOutOfScope` | This request needs the Standard or Full intake path. It has been captured, and your governance lead will follow up. |
| `fsi_decisionpath = DefaultDeny` | This request cannot proceed through Express because it conflicts with the configured data-residency policy. |

## Power Pages notes

- Configure table permissions narrowly; do not grant makers organization-wide read access to intake tables.
- For save/resume, use a Multistep form and keep records in `Draft` until the final submit step.
- If your site uses custom JavaScript to call Graph, use delegated user context and document consent in customer change control.
- Keep all approval and decision logic in Power Automate/Dataverse; the portal should only collect maker inputs and show status.
