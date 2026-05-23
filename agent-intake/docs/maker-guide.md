# Maker guide — agent-intake

**Audience:** Business users who want approval to build an AI agent.

**Best time to read:** Before you open the intake form.

`agent-intake` is the front door for approved AI agents at your firm. It helps your admin, sponsor, and reviewer board capture the evidence your firm may need for supervisory review under FINRA Rule 3110, books-and-records support under FINRA Rule 4511(a), SEC Rules 17a-3(a)(17) and 17a-4(f), CFTC Rule 1.31, GLBA Section 501(b), and the AI-governance expectations your firm maps to FINRA 25-07 and Federal Reserve SR 11-7. It does not replace your firm's policy. It gives you a structured way to ask for the right approval before you build.

For the technical rule set behind this guide, see [`classification-rules.md`](./classification-rules.md), [`question-catalog-overview.md`](./question-catalog-overview.md), and [`decisions.md`](./decisions.md).

## 1. What this is

Think of `agent-intake` as the doorway to building an approved agent at your firm.

When you submit a request, the system does four things:

1. captures what the agent is for
2. checks how broad and how sensitive the use case is
3. routes the request to the right approval path
4. keeps the decision as a retained record so your firm can explain later why the request was approved, denied, or appealed

The three paths are simple:

| Path | When it is used | What you should expect |
|---|---|---|
| **Express** | Personal-scope, lowest-risk requests | One sponsor approval in Teams |
| **Standard** | Team or department use, or moderate-risk internal use | Parallel reviewer board plus sponsor evidence |
| **Full** | Enterprise, customer-facing, MNPI, cross-border, or other highest-risk requests | Broad reviewer board, quorum, and possible MRM handoff |

The detailed rule logic lives in [`classification-rules.md`](./classification-rules.md). This guide keeps the same logic in plain English.

## 2. Before you start

Have these ready before you begin:

- **A real sponsor.** Usually this is your manager or another accountable business sponsor. You cannot sponsor yourself. See [ADR-008 in `decisions.md`](./decisions.md#adr-008--sponsor-cannot-self-approve).
- **A short business case.** One or two sentences is enough if it clearly explains what the agent will do.
- **Your data picture.** Know which SharePoint sites, Dataverse tables, mailboxes, APIs, or files the agent will touch.
- **Your audience.** Be honest about who will use the agent first: only you, your team, your department, the whole firm, or external users.
- **Any sensitive-data flags.** Know whether the agent will touch nonpublic personal information (NPI), material nonpublic information (MNPI), or cross-border data.
- **A rough deployment idea.** If you already know the agent will use premium connectors, call other agents, or run across multiple environments, expect Standard or Full.

If you are unsure about a risk question, choose **Not sure**. In this solution, **Not sure is treated like Yes for routing** so the request gets the safer review path. See [`classification-rules.md`](./classification-rules.md#trigger-questions-and-why-they-matter).

## 3. The 6 questions that decide your path

The form always asks six routing questions. Your audience answer matters too, but these six questions are what usually move a request out of Express.

| Trigger | Plain-English meaning | If you answer **Yes** or **Not sure** |
|---|---|---|
| **T1** | Will the agent initiate a financial transaction or move money? | The request goes to the highest review depth because financial authority needs stronger controls. |
| **T2** | Will the agent interact with customers or external parties? | The request moves to Full because customer-facing use needs broader review. |
| **T3** | Can the agent act without a human checkpoint or routine monitoring? | The request leaves Express because autonomy needs more oversight. |
| **T4** | Will it handle customer NPI? | The request leaves Express and usually needs Privacy and Compliance review. |
| **T5** | Will it handle MNPI or information-barrier data? | The request goes to Full. |
| **T6** | Will data cross country or regional residency boundaries? | The request leaves Express, and a country mismatch can default to deny until Privacy approves an override. |

Examples:

- **Express example:** a personal research assistant that uses only your own internal notes and is not customer-facing
- **Standard example:** a team coaching assistant that uses controlled internal customer data but stays inside one named team
- **Full example:** an enterprise assistant that is customer-facing, uses MNPI, or needs cross-border handling with formal approvals

For the exact wording used by the form, see the catalogs:

- [`intake-questions-express.md`](./intake-questions-express.md)
- [`intake-questions-standard.md`](./intake-questions-standard.md)
- [`intake-questions-full.md`](./intake-questions-full.md)

## 4. Filling out the Express form

Even if you eventually route to Standard or Full, you start with the same baseline form. The maker-facing build is described in [`portal-configuration.md`](./portal-configuration.md) and [`maker-form-progressive-disclosure.md`](./maker-form-progressive-disclosure.md).

### What to enter, field by field

| Form field | What good looks like | Common mistake |
|---|---|---|
| **Agent name** | A plain business name such as “Sales Coverage Coach” | A project codename nobody else will understand |
| **Business outcome** | A short phrase tied to work output | “AI experimentation” with no business reason |
| **Business justification** | One or two sentences describing the user, task, and benefit | “Helps the team” with no detail |
| **Agent type** | The platform you actually plan to use | Guessing without knowing the build surface |
| **Intended audience** | The smallest truthful starting audience | Choosing “Just me” when you already plan to share with a team |
| **Sponsor** | The person who is truly accountable for your work | Picking yourself or a peer |
| **T1-T6** | Honest answers, including “Not sure” when needed | Answering “No” because you hope for a faster route |
| **Data residency country** | The country where the data is expected to reside | Leaving it blank when T6 is Yes or Not sure |
| **Maker attestation** | Check it only after reviewing your answers | Treating it like a no-read checkbox |

### Tips that save time

- Write the business justification in **business language**, not platform jargon.
- If the agent reads more than one source, list the sources consistently in the follow-up questions.
- If your sponsor auto-fill is wrong, correct it before you submit.
- If your idea might handle NPI or MNPI, talk to your sponsor before submitting so the Standard or Full route is expected, not surprising.

## 5. What happens after you submit (Express)

If your request stays on Express, the path is intentionally simple.

| Step | What happens | Typical timing |
|---|---|---:|
| Submit | The request is saved and routed | Instant |
| Sponsor card | Your sponsor receives a Teams adaptive card | Usually under 30 seconds |
| Sponsor response | Your sponsor approves or denies | Target: within 3 business days |
| Escalation | If there is no response, the flow escalates per policy | Day 7 by default |
| Final timeout denial | If still unanswered, the request closes | Day 11 by default |
| Approval handoff | The system writes the decision pack, mints the Microsoft Entra Agent ID, and hands off to the registry and drift integrations | Usually within minutes after approval |

### What the outcomes look like

- **Approved** — your request moves forward, the decision pack is written, and the downstream handoff begins
- **Denied** — the sponsor or the system closed the request; you receive the reason and the appeal option if your policy still allows it
- **Approved with conditions** — this does **not** exist on the Express sponsor card; it appears only on Standard or Full reviewer decisions

If your sponsor needs help, send them [`sponsor-guide.md`](./sponsor-guide.md).

## 6. What if I end up on Standard or Full?

That is normal. Routing to a richer path does **not** mean you did anything wrong. It means the use case needs more evidence.

| Path | What extra questions you will see | Who reviews |
|---|---|---|
| **Standard** | Team scope, data sources, connectors, training acknowledgement, monitoring plan, backup sponsor | Usually InfoSec, Privacy, and Compliance in parallel; sponsor evidence still matters |
| **Full** | Everything in Standard plus enterprise scope, legal posture, autonomy level, financial authority, model-risk evidence, shutdown plan, incident and notification planning | InfoSec, Privacy, Compliance, Legal, and MRM, plus sponsor evidence |

A few helpful expectations:

- **Standard** is designed for team or department use and usually aims for a 2-of-3 reviewer quorum. See [`classification-rules.md`](./classification-rules.md#reviewer-quorum-defaults).
- **Full** is designed for the broadest or most sensitive cases and usually aims for a 3-of-5 reviewer quorum plus the Tier-1 MRM path. See [`mrm-integration.md`](./mrm-integration.md).
- Reviewers use the model-driven reviewer app described in [`reviewer-app-build.md`](./reviewer-app-build.md) and the operating guidance in [`reviewer-cheat-sheet.md`](./reviewer-cheat-sheet.md).

## 7. Cross-border data and you

T6 is the cross-border question: **Will data cross country or regional residency boundaries?**

Why it matters:

- If your working country and the declared data-residency country do not match, the bundled policy defaults to **deny** until Privacy approves an override.
- That default supports a conservative stance for cross-border routing and privacy review. See [ADR-005 in `decisions.md`](./decisions.md#adr-005--default-deny-when-maker-country-differs-from-data-residency-country).

### Plain-English rule

If you work in one country and the agent will read, store, or send data in another, do **not** assume the request can move forward on the standard path.

### When to ask Privacy for help before you submit

Ask for guidance before you submit when:

- the data is customer data or employee personal data
- you are unsure which country the data is really stored in
- the agent will call an API or service hosted in another country
- you believe there is already an approved privacy exception or lawful transfer basis

If Privacy later records an override, the request can continue, but a high-risk cross-border request still routes to the richer review path rather than back to Express. See [`classification-rules.md`](./classification-rules.md#cross-border-behavior-and-privacy-override).

## 8. Common mistakes that lead to denial

Most denials come from a small set of avoidable issues:

1. **Sponsor = self** — the form and router block self-approval
2. **Missing business justification** — reviewers cannot approve what they cannot understand
3. **Choosing a smaller audience than you really intend** — later oversharing becomes a drift issue
4. **Using NPI or MNPI without saying so** — if reviewers discover it later, the request usually has to restart
5. **Cross-border declared too late** — country mismatch can trigger default-deny
6. **No infrastructure story for sensitive data** — if you plan to use NPI or MNPI, be ready to explain the source, access path, and controls
7. **Outdated sponsor** — a former manager or peer slows the request and can trigger denial after timeout

If the denial reason is factual and easy to fix, an appeal or clean resubmission may be the fastest path.

## 9. Appealing a denial

An appeal makes sense when:

- you picked the wrong sponsor
- you corrected a wrong answer
- you now have the missing business justification, data-source detail, or privacy evidence
- the denial was caused by timeout and you now have the right approver lined up

### What to add in the appeal

Add only the facts that changed:

- updated sponsor
- corrected trigger answers
- clarified data sources or audience
- any Privacy, Compliance, or Legal note that changes the original outcome

### What happens next

The denial card triggers the appeal flow described in [`flow-configuration.md`](./flow-configuration.md#flow-11-fsi-intake-denial-appeal). The system creates a **new intake request** and preserves the link to the original denial.

The bundled policy defaults are conservative:

- Express and Standard usually allow **one** resubmission
- Full may allow a second resubmission if the customer keeps the shipped default in `templates/policy-lookup-tables.yaml`

Your firm can tighten that rule. If you are unsure, ask your admin before appealing.

## 10. After approval

Approval is not the end of the story. It is the point where the build is allowed to start under the approved scope.

After approval:

- the request is written into the immutable decision pack in `fsi_intakedecisionlog`
- the handoff mints a Microsoft Entra Agent ID and posts the approved record into `agent-registry-automation`
- the approved audience, data sources, sponsor, and conditions become the baseline for downstream drift monitoring

That is why later scope changes matter.

### What “drift” means for you

You should expect follow-up if you:

- share the agent more broadly than you declared
- add new connectors or data sources not in the approved request
- change one of the trigger answers after approval
- move the agent into a different environment or permission profile without re-review

See [`drift-detection-integration.md`](./drift-detection-integration.md) and [ADR-009 in `decisions.md`](./decisions.md#adr-009--major-modification-triggers-fresh-review-minor-does-not).

### What you will see in the registry

Your admin and governance teams will see the approved request linked to:

- the original intake request ID
- your sponsor
- the approved path, tier, and zone
- the decision-pack hash
- the Microsoft Entra Agent ID created for the agent

If you later need to expand the use case, submit a new intake or re-review request instead of changing the live agent quietly. That keeps the record defensible for your firm and easier to explain to internal audit, regulators, and the next approver.
